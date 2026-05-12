#!/usr/bin/env bash
# ==============================================================================
# Add Submodule Script
# Adds a new Git submodule, configures it, sorts .gitmodules, and updates README
# ==============================================================================
set -euo pipefail

# Source the tree generation functions
source "$(dirname "$0")/generate-tree.sh"

# Color output
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() {
  echo -e "\033[0;31m[ERROR]\033[0m $1"
  exit 1
}
warn() { echo -e "\033[0;33m[WARN]\033[0m $1" >&2; }

# Prompt for SSH URL
info "Starting submodule addition process..."
read -rp "Enter SSH URL (git@github.com:user/repo.git): " ssh_url
[[ -z "${ssh_url// /}" ]] && error "No URL provided. Exiting."

# Derive folder name
folder=$(basename "$ssh_url" .git)
info "Adding submodule: $folder"

# Check if already exists
[[ -d "$folder" ]] && error "Folder '$folder' already exists!"
git config --file .gitmodules --get-regexp "submodule.${folder}.path" &>/dev/null && error "Submodule '$folder' already in .gitmodules!"

# Add the submodule
info "Adding submodule to repository..."
git submodule add --branch main "$ssh_url" "$folder" || error "Failed to add submodule."
git config -f .gitmodules submodule."$folder".ignore all
success "Submodule added successfully."

# Sort .gitmodules alphabetically
info "Sorting .gitmodules alphabetically..."
cp .gitmodules .gitmodules.bak
names=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' | sort)

>.gitmodules
for name in $names; do
  url=$(git config --file .gitmodules.bak "submodule.$name.url" 2>/dev/null || echo "")
  branch=$(git config --file .gitmodules.bak "submodule.$name.branch" 2>/dev/null || echo "main")
  ignore=$(git config --file .gitmodules.bak "submodule.$name.ignore" 2>/dev/null || echo "all")

  # If URL is empty, fetch from the submodule directory
  if [[ -z "$url" ]]; then
    url=$(cd "$name" 2>/dev/null && git config --get remote.origin.url || echo "")
  fi

  {
    echo "[submodule \"$name\"]"
    echo "	path = $name"
    echo "	url = $url"
    echo "	branch = $branch"
    echo "	ignore = $ignore"
  } >>.gitmodules
done
rm -f .gitmodules.bak
success ".gitmodules sorted."

# Update README.md tree section
info "Updating README.md..."
update_readme_tree "$names"
success "README.md updated."

# Stage changes
git add .gitmodules "$folder" README.md 2>/dev/null || git add .gitmodules "$folder"

# Prompt for commit message
echo ""
info "Preparing to commit changes..."
read -rp "Enter commit message (default: 'chore: add $folder submodule'): " commit_msg
[[ -z "${commit_msg// /}" ]] && commit_msg="chore: add $folder submodule"

git commit -S -m "$commit_msg"
success "Changes committed: $commit_msg"

# Ask to push changes
echo ""
read -rp "Push changes to origin main? (y/n): " push_changes
if [[ "$push_changes" =~ ^[Yy]$ ]]; then
  git push origin main || warn "Push failed — changes committed locally"
  success "Changes pushed to origin main!"
else
  info "Don't forget to push manually:"
  echo "  git push origin main || warn "Push failed — changes committed locally""
fi

success "Done! Submodule '$folder' added."