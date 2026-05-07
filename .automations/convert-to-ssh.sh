#!/usr/bin/env bash
# ==============================================================================
# Convert HTTPS Remotes to SSH
# Safely rewrites all git remote URLs from HTTPS to SSH format
# ==============================================================================
set -euo pipefail

info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# Convert main repo remote
main_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$main_url" == https://github.com/* ]]; then
    ssh_url="${main_url/https:\/\/github.com\//git@github.com:}"
    git remote set-url origin "$ssh_url"
    success "Main repo remote switched to SSH"
fi

# Convert submodule remotes
git submodule foreach '
    url=$(git remote get-url origin 2>/dev/null)
    if [[ "$url" == https://github.com/* ]]; then
        sshurl="${url/https:\/\/github.com\//git@github.com:}"
        git remote set-url origin "$sshurl"
        echo "  $name → $sshurl"
    fi
' 2>/dev/null

success "All remotes are now SSH!"
