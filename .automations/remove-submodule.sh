#!/usr/bin/env bash
# ==============================================================================
# Remove Submodule Script
# Completely removes a submodule from git, .gitmodules, and README
# ==============================================================================
set -euo pipefail

source "$(dirname "$0")/generate-tree.sh"

info()    { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m $1" >&2; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

[[ -t 0 ]] || { warn "This script is interactive; run it from a terminal."; exit 1; }

[[ ! -f .gitmodules ]] && error ".gitmodules not found!"

info "Available submodules:"
submodules=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}' | LC_ALL=C sort)
[[ -z "$submodules" ]] && error "No submodules found in .gitmodules"

i=1
while IFS= read -r submodule; do
  echo "  $i) $submodule"
  ((i++))
done <<< "$submodules"

echo ""
read -rp "Enter number of submodule to remove (or name directly): " selection

if [[ "$selection" =~ ^[0-9]+$ ]]; then
  submodule_name=$(echo "$submodules" | sed -n "${selection}p")
  [[ -z "$submodule_name" ]] && error "Invalid selection: $selection"
else
  submodule_name="$selection"
  echo "$submodules" | grep -q "^${submodule_name}$" || error "Submodule '$submodule_name' not found in .gitmodules"
fi

info "Removing submodule: $submodule_name"
echo ""
warn "This will completely remove '$submodule_name' from:"
warn "  - Git submodules, .gitmodules, README.md tree, and the local directory"
echo ""
read -rp "Are you sure you want to continue? (y/n): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || error "Aborted by user"

info "Deinitializing submodule..."
git submodule deinit -f "$submodule_name" || warn "Failed to deinitialize (may already be deinitialized)"

info "Removing from git index..."
git rm -f "$submodule_name" || warn "Failed to remove from git index (may already be removed)"

info "Removing from .gitmodules..."
git config --file .gitmodules --remove-section "submodule.${submodule_name}" || warn "Failed to remove .gitmodules section (may already be removed)"

info "Cleaning up git modules directory..."
rm -rf ".git/modules/${submodule_name}" || warn "Failed to remove git modules directory"

info "Cleaning up orphaned cache entries..."
clean_orphan_cache
[[ "$ORPHAN_CACHE_REMOVED" -gt 0 ]] && success "Removed $ORPHAN_CACHE_REMOVED orphaned cache entry/entries"

if [[ -d "$submodule_name" ]]; then
  info "Removing local directory..."
  rm -rf "$submodule_name"
fi

info "Sorting .gitmodules and updating README tree..."
normalize_gitmodules
generate_tree_only
success "Configuration updated."

info "Staging changes..."
git add -- .gitmodules README.md
git add -u -- "$submodule_name" 2>/dev/null || true

echo ""
info "Preparing to commit changes..."
read -rp "Enter commit message (default: 'chore: remove $submodule_name submodule'): " commit_msg
[[ -z "${commit_msg// /}" ]] && commit_msg="chore: remove $submodule_name submodule"

signed_commit "$commit_msg" || exit 1
success "Changes committed: $commit_msg"

echo ""
read -rp "Push changes to origin main? (y/n): " push_changes
if [[ "$push_changes" =~ ^[Yy]$ ]]; then
  git push origin main || warn "Push failed — changes committed locally"
  success "Changes pushed to origin main!"
else
  info "Don't forget to push manually: git push origin main"
fi

success "Done! Submodule '$submodule_name' completely removed."
