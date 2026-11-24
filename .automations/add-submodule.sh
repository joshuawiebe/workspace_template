#!/usr/bin/env bash
# ==============================================================================
# Add Submodule Script
# Adds a new Git submodule, configures it, sorts .gitmodules, and updates README
# ==============================================================================
set -euo pipefail

source "$(dirname "$0")/generate-tree.sh"

info()    { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m $1" >&2; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

[[ -t 0 ]] || { warn "This script is interactive; run it from a terminal."; exit 1; }

info "Starting submodule addition process..."
read -rp "Enter SSH URL (git@github.com:user/repo.git): " ssh_url
[[ -z "${ssh_url// /}" ]] && error "No URL provided. Exiting."

folder=$(basename "$ssh_url" .git)
info "Adding submodule: $folder"

[[ -d "$folder" ]] && error "Folder '$folder' already exists!"
git config --file .gitmodules --get-regexp "submodule.${folder}.path" &>/dev/null && error "Submodule '$folder' already in .gitmodules!"

info "Adding submodule to repository..."
git submodule add --branch main "$ssh_url" "$folder" || error "Failed to add submodule."
git config -f .gitmodules submodule."$folder".ignore all
success "Submodule added successfully."

info "Sorting .gitmodules alphabetically..."
normalize_gitmodules
success ".gitmodules sorted."

info "Updating README.md..."
generate_tree_only
success "README.md updated."

git add -- .gitmodules README.md
git add --force -- "$folder"

echo ""
info "Preparing to commit changes..."
read -rp "Enter commit message (default: 'chore: add $folder submodule'): " commit_msg
[[ -z "${commit_msg// /}" ]] && commit_msg="chore: add $folder submodule"

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

success "Done! Submodule '$folder' added."
