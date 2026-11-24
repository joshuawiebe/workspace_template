#!/usr/bin/env bash
# ==============================================================================
# Workspace Update — single entry point for normalization + submodule updates
# ==============================================================================
set -euo pipefail

# Shared helpers: normalize_gitmodules, clean_orphan_cache, signed_commit,
# generate_tree_only, update_readme_tree, ...
source "$(dirname "$0")/generate-tree.sh"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

info()    { echo -e "\033[0;34m[INFO]\033[0m $1"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m $1" >&2; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# ------------------------------------------------------------------------------
# Options
# ------------------------------------------------------------------------------
DRY_RUN=false
NO_PUSH=false
FORCE_CI=false
NORMALIZE_ONLY=false

usage() {
  cat <<'EOF'
Usage: .automations/update.sh [options]

  --dry-run         Report what would change; no changes, no commit, no push.
  --no-push         Commit locally but do not push.
  --ci              Force GitHub Actions (fast) mode.
  --normalize-only  Only sort .gitmodules + regenerate the README tree, then commit/push.
  --help            Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true ;;
    --no-push)        NO_PUSH=true ;;
    --ci)             FORCE_CI=true ;;
    --normalize-only) NORMALIZE_ONLY=true ;;
    --help|-h)        usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

IS_GITHUB_ACTIONS=false
if [[ "$FORCE_CI" == "true" ]] || [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  IS_GITHUB_ACTIONS=true
fi

echo ""
info "=========================================="
info "  Workspace Update"
if [[ "$IS_GITHUB_ACTIONS" == "true" ]]; then
  info "  Mode: GitHub Actions"
else
  info "  Mode: Local Development"
fi
[[ "$DRY_RUN" == true ]]        && info "  Dry run: no changes will be made"
[[ "$NORMALIZE_ONLY" == true ]] && info "  Scope: .gitmodules + README only"
info "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Temp files / cleanup
# ------------------------------------------------------------------------------
STASH_FILE=""
CHANGE_RESULTS=""
ORPHAN_RESULTS=""
UPDATE_RESULTS=""
ELIGIBLE_FILE=""
POINTER_CHANGES=""
UNCOMMITTED_FILE=""
DRY_GITMODULES=""

cleanup_trap() {
  local f
  for f in "$STASH_FILE" "$CHANGE_RESULTS" "$ORPHAN_RESULTS" "$UPDATE_RESULTS" \
           "$ELIGIBLE_FILE" "$POINTER_CHANGES" "$UNCOMMITTED_FILE" "$DRY_GITMODULES"; do
    [[ -n "$f" ]] && [[ -f "$f" ]] && rm -f "$f"
  done
  # An EXIT trap's last status becomes the script's exit code — never fail here.
  return 0
}
trap cleanup_trap EXIT

mapfile -t SUBMODULE_PATHS < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')

# ------------------------------------------------------------------------------
# Dry run: read-only preview
# ------------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
  info "Previewing .gitmodules normalization..."
  DRY_GITMODULES=$(mktemp)
  cp .gitmodules "$DRY_GITMODULES"
  normalize_gitmodules "$DRY_GITMODULES"
  if diff -q .gitmodules "$DRY_GITMODULES" >/dev/null 2>&1; then
    success ".gitmodules already normalized"
  else
    warn ".gitmodules would be re-sorted / reformatted:"
    diff -u .gitmodules "$DRY_GITMODULES" || true
  fi

  info "Previewing README tree..."
  current_tree=$(awk '/^```filetree$/{flag=1;next} flag && /^```$/{exit} flag' README.md 2>/dev/null || true)
  new_tree=$(generate_readme_tree "$(printf '%s\n' "${SUBMODULE_PATHS[@]}")" | sed '1d;$d')
  if [[ "$current_tree" == "$new_tree" ]]; then
    success "README tree already up to date"
  else
    warn "README tree would be regenerated"
  fi

  info "Previewing staged changes..."
  staged_preview=$(git diff --cached --name-only --ignore-submodules=none 2>/dev/null || true)
  if [[ -n "$staged_preview" ]]; then
    echo "$staged_preview" | sed 's/^/  • /'
  else
    success "Nothing staged"
  fi

  info "Previewing submodule pointer drift..."
  drift=$(git submodule status --recursive 2>/dev/null | grep -E '^[+-]' || true)
  if [[ -n "$drift" ]]; then
    echo "$drift" | sed 's/^/  • /'
  else
    success "No pointer drift"
  fi

  success "Dry run complete — nothing was changed."
  exit 0
fi

# ------------------------------------------------------------------------------
# Pre-flight: be transparent about changes already in the index
# ------------------------------------------------------------------------------
PRESTAGED=$(git diff --cached --name-only --ignore-submodules=none 2>/dev/null || true)
if [[ -n "$PRESTAGED" ]]; then
  warn "Pre-existing staged changes will be included in this run's commit:"
  echo "$PRESTAGED" | sed 's/^/    /'
fi

# ------------------------------------------------------------------------------
# 1. Normalize .gitmodules + README tree (always, in CI and locally)
# ------------------------------------------------------------------------------
info "Normalizing .gitmodules..."
normalize_gitmodules
if git diff --quiet -- .gitmodules; then
  success ".gitmodules already normalized"
else
  success ".gitmodules normalized and sorted"
fi

info "Regenerating README tree..."
generate_tree_only
success "README tree updated"
echo ""

# ------------------------------------------------------------------------------
# 2-6. Submodule work (skipped with --normalize-only)
# ------------------------------------------------------------------------------
if [[ "$NORMALIZE_ONLY" != true ]]; then
  # 2. Pull workspace
  info "Pulling latest workspace changes..."
  if git pull origin main 2>&1; then
    success "Workspace up to date"
  else
    warn "git pull failed — continuing with local state"
  fi
  echo ""

  # 3. Detect and repair orphaned submodule commits
  info "Checking for orphaned submodule commits..."
  ORPHAN_RESULTS=$(mktemp)
  ORPHANED_COUNT=0
  CHECKED_COUNT=$(git submodule status --recursive 2>/dev/null | wc -l | tr -d ' ')

  # foreach already runs inside each submodule — do NOT cd again.
  git submodule foreach --quiet --recursive '
    branch=$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch" 2>/dev/null || echo "main")
    ref=$(git rev-parse HEAD 2>/dev/null || echo "")
    [[ -z "$ref" ]] && exit 0
    if ! git cat-file -e "$ref" >/dev/null 2>&1; then
      echo "ORPHANED:$name:$branch"
    fi
  ' > "$ORPHAN_RESULTS" 2>/dev/null || true

  while IFS=: read -r status submodule branch; do
    [[ "$status" == "ORPHANED" ]] || continue
    warn "  Found orphaned commit in: $submodule (resetting to origin/$branch)"
    git -C "$REPO_ROOT/$submodule" fetch origin "$branch" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT/$submodule" reset --hard "origin/$branch" >/dev/null 2>&1 || true
    ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
  done < "$ORPHAN_RESULTS"

  if [[ "$ORPHANED_COUNT" -gt 0 ]]; then
    success "Fixed $ORPHANED_COUNT orphaned commit(s)"
  else
    success "All $CHECKED_COUNT submodules valid"
  fi
  echo ""

  # 4. Local mode: stash dirty submodules
  if [[ "$IS_GITHUB_ACTIONS" != "true" ]]; then
    info "Checking for local changes in submodules..."
    STASH_FILE=$(mktemp)
    CHANGE_RESULTS=$(mktemp)
    CHANGED_COUNT=0

    git submodule foreach --quiet --recursive '
      changes=$(git status --porcelain 2>/dev/null | wc -l)
      [[ "$changes" -gt 0 ]] && echo "$name:$changes"
    ' > "$CHANGE_RESULTS" 2>/dev/null || true

    while IFS=: read -r submodule change_count; do
      [[ -z "$submodule" ]] && continue
      [[ ! -d "$REPO_ROOT/$submodule" ]] && continue
      CHANGED_COUNT=$((CHANGED_COUNT + 1))

      branch=$(git -C "$REPO_ROOT/$submodule" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
      [[ "$branch" == "HEAD" ]] && branch="main"

      warn "  $submodule: stashing $change_count changed file(s)"
      if git -C "$REPO_ROOT/$submodule" stash push --include-untracked \
           -m "workspace-update-backup-$submodule" >/dev/null 2>&1; then
        echo "$submodule:$branch" >> "$STASH_FILE"
      else
        warn "  $submodule: stash failed — its update will be skipped"
      fi
    done < "$CHANGE_RESULTS"

    if [[ "$CHANGED_COUNT" -gt 0 ]]; then
      success "Stashed local changes in $CHANGED_COUNT submodule(s)"
    else
      success "No local changes detected"
    fi
    echo ""
  fi

  # 5. Update all submodules
  info "Updating submodules..."
  UPDATE_RESULTS=$(mktemp)
  ELIGIBLE_FILE=$(mktemp)
  UNCOMMITTED_FILE=$(mktemp)
  UPDATE_COUNT=0

  git submodule foreach --quiet --recursive '
    branch=$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch" 2>/dev/null || echo "main")
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    echo "PROCESS:$name:$branch:$current_branch"
  ' > "$UPDATE_RESULTS" 2>/dev/null || true

  while IFS=: read -r marker submodule branch current_branch; do
    [[ "$marker" == "PROCESS" ]] || continue
    [[ -z "$submodule" ]] && continue
    [[ ! -d "$REPO_ROOT/$submodule" ]] && continue

    UPDATE_COUNT=$((UPDATE_COUNT + 1))
    path="$REPO_ROOT/$submodule"

    if [[ "$IS_GITHUB_ACTIONS" == "true" ]]; then
      git -C "$path" fetch origin "$branch"  >/dev/null 2>&1 || true
      git -C "$path" pull  origin "$branch"  >/dev/null 2>&1 || true
      git -C "$path" push  origin "$branch"  >/dev/null 2>&1 || true
      echo "$submodule" >> "$ELIGIBLE_FILE"
    elif [[ "$current_branch" != "$branch" ]]; then
      # On a feature/detached branch: update the default branch, then restore.
      git -C "$path" checkout "$branch" >/dev/null 2>&1 || true
      git -C "$path" fetch origin "$branch" >/dev/null 2>&1 || true
      git -C "$path" pull origin "$branch" >/dev/null 2>&1 || true

      if git -C "$path" fetch origin "$current_branch" >/dev/null 2>&1; then
        git -C "$path" checkout "$current_branch" >/dev/null 2>&1 || true
      elif grep -q "^${submodule}:" "$STASH_FILE" 2>/dev/null; then
        # Feature branch deleted upstream: drop its backup and stay on default.
        git -C "$path" stash drop >/dev/null 2>&1 || true
        sed -i "\|^${submodule}:|d" "$STASH_FILE" 2>/dev/null || true
        echo "$submodule" >> "$ELIGIBLE_FILE"
      fi
    else
      git -C "$path" fetch origin "$branch" >/dev/null 2>&1 || true
      git -C "$path" pull origin "$branch" >/dev/null 2>&1 || true
      echo "$submodule" >> "$ELIGIBLE_FILE"
    fi

    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
      echo "$submodule" >> "$UNCOMMITTED_FILE"
    fi
  done < "$UPDATE_RESULTS"

  success "Processed $UPDATE_COUNT submodule(s)"
  if [[ -s "$UNCOMMITTED_FILE" ]]; then
    while IFS= read -r submodule; do
      warn "  $submodule: has uncommitted changes (will not be staged)"
    done < "$UNCOMMITTED_FILE"
  fi
  echo ""

  # 6. Local mode: restore original branches and stashed changes
  if [[ "$IS_GITHUB_ACTIONS" != "true" && -s "$STASH_FILE" ]]; then
    info "Restoring local state..."
    RESTORE_COUNT=0
    while IFS=: read -r module_name saved_branch; do
      [[ -z "$module_name" ]] && continue
      [[ ! -d "$REPO_ROOT/$module_name" ]] && continue
      RESTORE_COUNT=$((RESTORE_COUNT + 1))
      git -C "$REPO_ROOT/$module_name" checkout "$saved_branch" >/dev/null 2>&1 || true
      if git -C "$REPO_ROOT/$module_name" stash list | grep -q "workspace-update-backup-$module_name"; then
        git -C "$REPO_ROOT/$module_name" stash pop >/dev/null 2>&1 || \
          warn "  $module_name: stash pop failed — see 'git stash list' in that submodule"
      fi
    done < "$STASH_FILE"
    success "Restored state in $RESTORE_COUNT submodule(s)"
    echo ""
  fi

  # 7. Clean stale .git/modules entries
  info "Validating submodule cache..."
  clean_orphan_cache
  if [[ "$ORPHAN_CACHE_REMOVED" -gt 0 ]]; then
    success "Removed $ORPHAN_CACHE_REMOVED orphaned cache entry/entries"
  else
    success "Submodule cache is in sync"
  fi
  echo ""
fi

# ------------------------------------------------------------------------------
# 8. Stage explicit paths only (never `git add .`)
# ------------------------------------------------------------------------------
POINTER_CHANGES=$(mktemp)
for submodule in "${SUBMODULE_PATHS[@]}"; do
  [[ -z "$submodule" ]] && continue
  [[ ! -e "$REPO_ROOT/$submodule" ]] && continue
  [[ -z "$(git status --porcelain --ignore-submodules=none -- "$submodule" 2>/dev/null)" ]] && continue

  if [[ "$IS_GITHUB_ACTIONS" == "true" ]] || grep -qx "$submodule" "$ELIGIBLE_FILE" 2>/dev/null; then
    echo "$submodule" >> "$POINTER_CHANGES"
  else
    warn "$submodule: pointer left unstaged (submodule was on a non-default branch)"
  fi
done

git add -- .gitmodules README.md
while IFS= read -r submodule; do
  git add --force -- "$submodule"
done < "$POINTER_CHANGES"

# ------------------------------------------------------------------------------
# 9. Commit (single path, real staged-file detection) and push
# ------------------------------------------------------------------------------
STAGED=$(git diff --cached --name-only --ignore-submodules=none 2>/dev/null || true)
if [[ -z "$STAGED" ]]; then
  success "=========================================="
  success "  No changes to commit"
  success "=========================================="
else
  mapfile -t staged_files <<< "$STAGED"
  list=$(printf '%s\n' "${staged_files[@]}" | paste -sd, -)

  all_submodules=true
  for f in "${staged_files[@]}"; do
    [[ -z "$f" ]] && continue
    is_submodule=false
    for s in "${SUBMODULE_PATHS[@]}"; do
      [[ "$f" == "$s" ]] && { is_submodule=true; break; }
    done
    [[ "$is_submodule" == false ]] && { all_submodules=false; break; }
  done

  if [[ "$all_submodules" == true ]]; then
    msg="chore: bump ${list} to latest upstream"
  elif [[ "${#staged_files[@]}" -eq 1 && "${staged_files[0]}" == "README.md" ]]; then
    msg="docs: update file tree in README"
  else
    msg="chore: update ${list}"
  fi

  info "Committing: $msg"
  if signed_commit "$msg"; then
    if [[ "$NO_PUSH" == true ]]; then
      success "Committed locally (push skipped via --no-push)"
    elif git push origin main; then
      success "Pushed to origin main"
    else
      warn "Push failed — changes committed locally"
    fi
    success "=========================================="
    success "  Update Complete!"
    success "=========================================="
  else
    warn "Commit failed — changes remain staged for manual recovery"
    exit 1
  fi
fi
echo ""
