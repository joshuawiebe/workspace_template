#!/usr/bin/env bash
# ==============================================================================
# Clean GitModules - Rebuild and sort .gitmodules alphabetically
# ==============================================================================
set -euo pipefail

# Source the tree generation functions
source "$(dirname "$0")/generate-tree.sh"

# Color output
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

[[ ! -f .gitmodules ]] && error ".gitmodules not found!"

info "Cleaning and sorting .gitmodules..."

# Create backup in temp location
temp_backup=$(mktemp)
cp .gitmodules "$temp_backup"

# Extract all submodule names and sort
names=$(git config --file "$temp_backup" --get-regexp path | awk '{print $2}' | sort)
[[ -z "$names" ]] && { info "No submodules found."; rm -f "$temp_backup"; exit 0; }

# Rebuild .gitmodules with consistent formatting
>.gitmodules
for name in $names; do
  url=$(git config --file "$temp_backup" "submodule.$name.url")
  branch=$(git config --file "$temp_backup" "submodule.$name.branch" 2>/dev/null || echo "main")
  ignore=$(git config --file "$temp_backup" "submodule.$name.ignore" 2>/dev/null || echo "all")
  
  {
    echo "[submodule \"$name\"]"
    echo "	path = $name"
    echo "	url = $url"
    echo "	branch = $branch"
    echo "	ignore = $ignore"
  } >>.gitmodules
done

# Remove temp backup
rm -f "$temp_backup"
success ".gitmodules sorted successfully!"

# Update README.md tree section
info "Updating README.md tree..."
update_readme_tree "$names"
success "README.md tree updated."

# Stage changes
git add .gitmodules README.md 2>/dev/null || git add .gitmodules
success "Changes staged."

# Skip prompt if in CI or AUTO_UPDATE mode
if [[ "${CI:-false}" == "true" ]] || [[ "${AUTO_UPDATE:-false}" == "true" ]]; then
  info "Automated mode - skipping update prompt"
  exit 0
fi

# Ask to run update.sh
echo ""
read -rp "Run .automations/update.sh to commit and push? (y/n): " run_update
if [[ "$run_update" =~ ^[Yy]$ ]]; then
  [[ -f .automations/update.sh ]] && { chmod +x .automations/update.sh; ./.automations/update.sh; } || error "update.sh not found!"
else
  info "Remember to commit manually:"
  echo "  git commit -m 'chore: clean and sort .gitmodules'"
  echo "  git push origin main"
fi
echo ""
success "Done."