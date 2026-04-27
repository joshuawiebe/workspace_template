#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Script - Initialize all submodules after cloning
# ==============================================================================
set -euo pipefail

# Color output
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

echo ""
info "=========================================="
info "  Workspace Bootstrap"
info "=========================================="
echo ""

# Sync and initialize submodules
info "Syncing submodule configurations..."
git submodule sync --recursive
success "Sync complete"

info "Initializing submodules..."
git submodule update --init --recursive
success "Submodules initialized"

# Checkout correct branch for each submodule
info "Checking out correct branches..."
echo ""

git submodule foreach '
  branch=$(git config -f "$toplevel/.gitmodules" submodule.$name.branch 2>/dev/null || echo "main")
  echo "  → $name (branch: $branch)"
  
  git fetch origin "$branch" 2>/dev/null || { echo "    [WARN] Fetch failed"; exit 0; }
  git checkout "$branch" 2>/dev/null || { echo "    [WARN] Checkout failed"; exit 0; }
  git pull origin "$branch" 2>/dev/null || { echo "    [WARN] Pull failed"; exit 0; }
  echo "    [OK] Updated"
'

echo ""
success "=========================================="
success "  Bootstrap Complete!"
success "=========================================="
echo ""
info "All submodules initialized and up to date."
info "Run '.automations/update.sh' to keep them updated."
echo ""
