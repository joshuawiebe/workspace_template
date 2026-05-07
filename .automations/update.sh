#!/usr/bin/env bash
set -euo pipefail

# Source the tree generation functions
source "$(dirname "$0")/generate-tree.sh"

# Get root directory for accessing .gitmodules
REPO_ROOT=$(git rev-parse --show-toplevel)

# Color helpers
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
debug() { echo -e "\033[0;36m[DEBUG]\033[0m $1"; }

# Detect if running in GitHub Actions
IS_GITHUB_ACTIONS="${GITHUB_ACTIONS:-false}"

echo ""
info "=========================================="
info "  Workspace Update"
if [ "$IS_GITHUB_ACTIONS" = "true" ]; then
  info "  Mode: GitHub Actions"
else
  info "  Mode: Local Development"
fi
info "=========================================="
echo ""

# Initialize all temp file variables upfront
STASH_FILE=""
CHANGE_RESULTS=""
ORPHAN_RESULTS=""
UPDATE_RESULTS=""
UPDATED_REPOS=""

# Set up cleanup trap for all temp files
cleanup_trap() {
  [ -n "$STASH_FILE" ] && [ -f "$STASH_FILE" ] && rm -f "$STASH_FILE"
  [ -n "$CHANGE_RESULTS" ] && [ -f "$CHANGE_RESULTS" ] && rm -f "$CHANGE_RESULTS"
  [ -n "$ORPHAN_RESULTS" ] && [ -f "$ORPHAN_RESULTS" ] && rm -f "$ORPHAN_RESULTS"
  [ -n "$UPDATE_RESULTS" ] && [ -f "$UPDATE_RESULTS" ] && rm -f "$UPDATE_RESULTS"
  [ -n "$UPDATED_REPOS" ] && [ -f "$UPDATED_REPOS" ] && rm -f "$UPDATED_REPOS"
}
trap cleanup_trap EXIT

# For local mode, we'll track stashed modules in a temp file
if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
  STASH_FILE=$(mktemp)
  CHANGE_RESULTS=$(mktemp)
  info "Preserving local state for restoration..."
fi

# 1. Pull latest workspace changes
info "Pulling latest workspace changes..."
if git pull origin main 2>&1; then
  success "Workspace up to date"
else
  warn "git pull failed — check your network or auth"
fi
echo ""

# 2. Detect and fix orphaned submodule commits
info "Checking for orphaned submodule commits..."

# Create temp file for tracking orphaned detection results
ORPHAN_RESULTS=$(mktemp)

ORPHANED_COUNT=0
CHECKED_COUNT=0

while IFS= read -r submodule_path; do
  [ -z "$submodule_path" ] && continue
  
  CHECKED_COUNT=$((CHECKED_COUNT + 1))
  
  if [ ! -d "$submodule_path" ]; then
    continue
  fi
  
  (
    cd "$submodule_path" || exit 1
    
    # Get configured branch from root .gitmodules
    branch=$(git config -f "$REPO_ROOT/.gitmodules" --get "submodule.$submodule_path.branch" 2>/dev/null || echo "main")
    current_ref=$(git rev-parse HEAD 2>/dev/null || echo "")
    
    if [ -z "$current_ref" ]; then
      exit 0
    fi
    
    if ! git cat-file -t "$current_ref" >/dev/null 2>&1; then
      echo "ORPHANED:$submodule_path:$branch"
    fi
  ) >> "$ORPHAN_RESULTS" 2>/dev/null || true
done < <(git config -f "$REPO_ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

# Process orphan detection results
while IFS=':' read -r status submodule branch; do
  case "$status" in
    ORPHANED)
      warn "  Found orphaned commit in: $submodule (resetting to origin/$branch)"
      
      (
        cd "$submodule" || exit 1
        git fetch origin "$branch" >/dev/null 2>&1 || true
        git reset --hard "origin/$branch" >/dev/null 2>&1 || true
      )
      
      ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
      ;;
  esac
done < "$ORPHAN_RESULTS"

if [ "$ORPHANED_COUNT" -gt 0 ]; then
  success "Fixed $ORPHANED_COUNT orphaned commit(s)"
else
  success "All $CHECKED_COUNT submodules valid"
fi
echo ""

# 3. LOCAL MODE: Check and save state for submodules with local changes
if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
  info "Checking for local changes in submodules..."
  
  CHANGED_COUNT=0
  
  git submodule foreach --quiet '
    has_changes=$(git status --porcelain | grep -v "^??" | wc -l)
    if [ "$has_changes" -gt 0 ]; then
      echo "$name:$has_changes"
    fi
  ' >> "$CHANGE_RESULTS" 2>/dev/null || true
  
  if [ -f "$CHANGE_RESULTS" ] && [ -s "$CHANGE_RESULTS" ]; then
    while IFS=':' read -r submodule change_count; do
      [ -z "$submodule" ] && continue
      
      if [ ! -d "$submodule" ]; then
        continue
      fi
      
      CHANGED_COUNT=$((CHANGED_COUNT + 1))
      
      branch=$(cd "$submodule" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
      
      # If in detached HEAD, use main branch
      if [ "$branch" = "HEAD" ]; then
        branch="main"
      fi
      
      # Only show details for modules with changes
      warn "  $submodule: Found $change_count file(s) with changes"
      
      # Stash the changes
      (cd "$submodule" && git stash push -m "workspace-update-backup-$submodule" >/dev/null 2>&1 || true)
      
      # Record this module and branch for restoration
      echo "$submodule:$branch" >> "$STASH_FILE"
    done < "$CHANGE_RESULTS"
    
    success "Stashed changes in $CHANGED_COUNT submodule(s)"
  else
    success "No local changes detected"
  fi
  echo ""
fi

# 4. Update all submodules
info "Updating submodules..."

# Create temp file for update tracking
UPDATE_RESULTS=$(mktemp)
UPDATED_REPOS=$(mktemp)

UPDATE_COUNT=0

git submodule foreach --quiet '
  branch=$(git config -f "$toplevel/.gitmodules" submodule.$name.branch 2>/dev/null || echo "main")
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
  echo "PROCESS:$name:$branch:$current_branch"
' >> "$UPDATE_RESULTS" 2>/dev/null || true

if [ -f "$UPDATE_RESULTS" ] && [ -s "$UPDATE_RESULTS" ]; then
  while IFS=':' read -r marker submodule branch current_branch; do
    [ "$marker" != "PROCESS" ] && continue
    [ -z "$submodule" ] && continue
    
    if [ ! -d "$submodule" ]; then
      continue
    fi
    
    UPDATE_COUNT=$((UPDATE_COUNT + 1))
    
    (
      cd "$submodule" || exit 1
      
      # Get current state before any changes
      before_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
      
      if [ "$IS_GITHUB_ACTIONS" = "true" ]; then
        # GitHub Actions: full update with push
        # Always on default branch in CI
        git fetch origin "$branch" >/dev/null 2>&1 || true
        git pull origin "$branch" >/dev/null 2>&1 || true
        git push origin "$branch" >/dev/null 2>&1 || true
      else
        # Local mode: handle feature branches safely
        if [ "$current_branch" != "$branch" ]; then
          # On a feature branch - switch to default, update, switch back
          git checkout "$branch" >/dev/null 2>&1 || true
          git fetch origin "$branch" >/dev/null 2>&1 || true
          git pull origin "$branch" >/dev/null 2>&1 || true
          git checkout "$current_branch" >/dev/null 2>&1 || true
        else
          # Already on default branch
          git fetch origin "$branch" >/dev/null 2>&1 || true
          git pull origin "$branch" >/dev/null 2>&1 || true
        fi
      fi
      
      # Check if repo was actually updated
      after_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
      if [ "$before_sha" != "$after_sha" ]; then
        echo "$submodule" >> "$UPDATED_REPOS"
      fi
      
      # Check for uncommitted changes after update
      if git status --porcelain | grep -q .; then
        warn "  $submodule: Has uncommitted changes (will not push)"
      fi
    ) 2>/dev/null || true
  done < "$UPDATE_RESULTS"
fi

# Count how many repos were actually updated
ACTUALLY_UPDATED=$(wc -l < "$UPDATED_REPOS" 2>/dev/null | tr -d ' ')
if [ "$ACTUALLY_UPDATED" -gt 0 ]; then
  success "Updated $ACTUALLY_UPDATED submodule(s) with new commits"
else
  success "All submodules already up to date"
fi
echo ""

# 5. LOCAL MODE: Restore state
if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
  if [ -f "$STASH_FILE" ] && [ -s "$STASH_FILE" ]; then
    info "Restoring local changes..."
    
    RESTORE_COUNT=0
    
    while IFS=':' read -r module_name saved_branch; do
      [ -z "$module_name" ] && continue
      
      if [ ! -d "$module_name" ]; then
        continue
      fi
      
      RESTORE_COUNT=$((RESTORE_COUNT + 1))
      
      (
        cd "$module_name" || exit 1
        
        git checkout "$saved_branch" >/dev/null 2>&1 || true
        git stash pop >/dev/null 2>&1 || true
      ) || true
    done < "$STASH_FILE"
    
    success "Restored changes in $RESTORE_COUNT submodule(s)"
    echo ""
  fi
fi

# 6. Validate and sync .gitmodules
info "Validating and syncing .gitmodules..."

# Check for orphaned submodules in git cache (in .git/modules but not in .gitmodules)
ORPHANED_IN_CACHE=0
if [ -d ".git/modules" ]; then
  for module_dir in .git/modules/*/; do
    module_name=$(basename "$module_dir")
    
    # Check if this module is still in .gitmodules
    # Need to handle both exact matches and parent directory matches
    # e.g., "saved" is a parent dir of "saved/css-components"
    found_in_gitmodules=false
    while IFS= read -r gitmodule_path; do
      if [ "$gitmodule_path" = "$module_name" ]; then
        # Exact match
        found_in_gitmodules=true
        break
      elif [[ "$gitmodule_path" == "$module_name"/* ]]; then
        # Parent directory match (e.g., "saved" is parent of "saved/css-components")
        found_in_gitmodules=true
        break
      fi
    done < <(git config --file .gitmodules --get-regexp "submodule\\." | grep -oE "path .+$" | sed 's/^path //')
    
    if [ "$found_in_gitmodules" = false ]; then
      warn "  Found orphaned submodule in cache: $module_name (removing)"
      rm -rf "$module_dir"
      ORPHANED_IN_CACHE=$((ORPHANED_IN_CACHE + 1))
    fi
  done
fi

if [ "$ORPHANED_IN_CACHE" -gt 0 ]; then
  success "Removed $ORPHANED_IN_CACHE orphaned submodule(s) from git cache"
else
  success ".gitmodules is valid and in sync"
fi
echo ""

# 7. Update README.md tree section
info "Updating README.md tree..."
generate_tree_only 2>/dev/null
success "README.md tree updated"
echo ""

# 8. Stage changes
git add .gitmodules README.md . 2>/dev/null || true

# 9. Check if there are actually submodule updates to commit
# This is more reliable than checking git status for submodule changes
if [ -f "$UPDATED_REPOS" ] && [ -s "$UPDATED_REPOS" ]; then
  info "Submodules with new commits:"
  cat "$UPDATED_REPOS" | sed 's/^/  • /'
  echo ""
  
  # Stage all submodule changes (--force overrides ignore = all)
  while IFS= read -r repo; do
    git add --force "$repo"
  done < "$UPDATED_REPOS"
  
  # Build commit message from updated repos
  group=$(cat "$UPDATED_REPOS" | tr '\n' ', ' | sed 's/, $//')
  msg="chore: bump ${group} to latest upstream"
  
  # Only commit if there are staged changes
  if git diff --cached --quiet; then
    success "=========================================="
    success "  No pointer change to push"
    success "=========================================="
    echo ""
  else
    # 10. Create commit and push
    git commit -m "$msg"
    git push origin main
    
    success "=========================================="
    success "  Update Complete!"
    success "=========================================="
    echo ""
  fi
else
  # Check for .gitmodules or README.md changes
  changed=$(git status --porcelain | awk '$1 == "M" {print $2}')
  
  if [ -n "$changed" ]; then
    group=$(echo "$changed" | tr '\n' ', ' | sed 's/, $//')
    msg="chore: bump ${group} to latest upstream"
    
    git commit -m "$msg"
    git push origin main
    
    success "=========================================="
    success "  Update Complete!"
    success "=========================================="
    echo ""
  else
    success "=========================================="
    success "  No changes to commit"
    success "=========================================="
    echo ""
  fi
fi


success "=========================================="
success "  Update Complete!"
success "=========================================="
echo ""
