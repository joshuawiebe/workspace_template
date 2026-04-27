#!/usr/bin/env bash
# ==============================================================================
# Remove Submodule Script
# Completely removes a submodule from git, .gitmodules, and README
# ==============================================================================
set -euo pipefail

# Source the tree generation functions
source "$(dirname "$0")/generate-tree.sh"

# Color output
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }

# Check if .gitmodules exists
[[ ! -f .gitmodules ]] && error ".gitmodules not found!"

# List available submodules
info "Available submodules:"
submodules=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' | sort)
if [[ -z "$submodules" ]]; then
  error "No submodules found in .gitmodules"
fi

# Display submodules with numbers
i=1
while IFS= read -r submodule; do
  echo "  $i) $submodule"
  ((i++))
done <<< "$submodules"

# Prompt for selection
echo ""
read -rp "Enter number of submodule to remove (or name directly): " selection

# Determine submodule name
if [[ "$selection" =~ ^[0-9]+$ ]]; then
  # Numeric selection
  submodule_name=$(echo "$submodules" | sed -n "${selection}p")
  [[ -z "$submodule_name" ]] && error "Invalid selection: $selection"
else
  # Direct name input
  submodule_name="$selection"
  # Verify it exists
  if ! echo "$submodules" | grep -q "^${submodule_name}$"; then
    error "Submodule '$submodule_name' not found in .gitmodules"
  fi
fi

info "Removing submodule: $submodule_name"

# Confirm removal
echo ""
warn "This will completely remove '$submodule_name' from:"
warn "  - Git submodules"
warn "  - .gitmodules file"
warn "  - README.md tree"
warn "  - Local directory"
echo ""
read -rp "Are you sure you want to continue? (y/n): " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && { error "Aborted by user"; }

# 1. Deinitialize submodule
info "Deinitializing submodule..."
git submodule deinit -f "$submodule_name" || warn "Failed to deinitialize submodule (may already be deinitialized)"

# 2. Remove from git index
info "Removing from git index..."
git rm -f "$submodule_name" || warn "Failed to remove from git index (may already be removed)"

# 3. Remove from .gitmodules
info "Removing from .gitmodules..."
git config --file .gitmodules --remove-section "submodule.${submodule_name}" || warn "Failed to remove from .gitmodules (may already be removed)"

# 4. Clean up git modules directory
info "Cleaning up git modules directory..."
rm -rf ".git/modules/${submodule_name}" || warn "Failed to remove git modules directory (may not exist)"

# 5. Clean up any other orphaned submodules in git cache
info "Cleaning up git cache for orphaned submodules..."
ORPHANED_CLEANED=0

if [ -d ".git/modules" ]; then
  for module_dir in .git/modules/*/; do
    # Get the module name from the directory
    cached_module=$(basename "$module_dir")
    
    # Check if this module is still in .gitmodules
    # Need to handle both exact matches and parent directory matches
    # e.g., "saved" is a parent dir of "saved/css-components"
    found_in_gitmodules=false
    while IFS= read -r gitmodule_path; do
      if [ "$gitmodule_path" = "$cached_module" ]; then
        # Exact match
        found_in_gitmodules=true
        break
      elif [[ "$gitmodule_path" == "$cached_module"/* ]]; then
        # Parent directory match (e.g., "saved" is parent of "saved/css-components")
        found_in_gitmodules=true
        break
      fi
    done < <(git config --file .gitmodules --get-regexp "submodule\\." | grep -oE "path .+$" | sed 's/^path //')
    
    if [ "$found_in_gitmodules" = false ]; then
      # This module is not in .gitmodules, so it's orphaned
      warn "  Removing orphaned cache: $cached_module"
      rm -rf "$module_dir"
      ORPHANED_CLEANED=$((ORPHANED_CLEANED + 1))
    fi
  done
fi

if [ "$ORPHANED_CLEANED" -gt 0 ]; then
  success "Cleaned up $ORPHANED_CLEANED orphaned submodule(s) from git cache"
fi

# 6. Remove any remaining local directory
if [[ -d "$submodule_name" ]]; then
  info "Removing local directory..."
  rm -rf "$submodule_name"
fi

# 7. Update README.md tree section
info "Updating README.md tree..."
# Get current submodule names (excluding the one being removed)
current_names=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' | sort)
update_readme_tree "$current_names"
success "README.md tree updated."

# Stage changes
info "Staging changes..."
git add .gitmodules README.md 2>/dev/null || git add .gitmodules

# Prompt for commit message
echo ""
info "Preparing to commit changes..."
read -rp "Enter commit message (default: 'chore: remove $submodule_name submodule'): " commit_msg
[[ -z "${commit_msg// /}" ]] && commit_msg="chore: remove $submodule_name submodule"

git commit -m "$commit_msg"
success "Changes committed: $commit_msg"

# Ask to push changes
echo ""
read -rp "Push changes to origin main? (y/n): " push_changes
if [[ "$push_changes" =~ ^[Yy]$ ]]; then
  git push origin main
  success "Changes pushed to origin main!"
else
  info "Don't forget to push manually:"
  echo "  git push origin main"
fi

success "Done! Submodule '$submodule_name' completely removed."