#!/usr/bin/env bash
# ==============================================================================
# Convert HTTPS remotes to SSH (main repo, .gitmodules, and submodule origins)
# ==============================================================================
set -euo pipefail

info()    { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m $1" >&2; }

to_ssh() {
  local url="$1"
  [[ "$url" == https://github.com/* ]] || { echo "$url"; return 0; }
  echo "${url/https:\/\/github.com\//git@github.com:}"
}

converted=0

# 1. Main repository remote
main_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$main_url" != "$(to_ssh "$main_url")" ]]; then
  ssh_url=$(to_ssh "$main_url")
  git remote set-url origin "$ssh_url"
  success "Main repo remote switched to SSH: $ssh_url"
  converted=$((converted + 1))
fi

# 2. .gitmodules URLs (recursive submodules are listed here too)
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  url=$(git config --file .gitmodules "submodule.$path.url" 2>/dev/null || echo "")
  ssh_url=$(to_ssh "$url")
  if [[ "$url" != "$ssh_url" ]]; then
    git config --file .gitmodules "submodule.$path.url" "$ssh_url"
    success "  .gitmodules: $path → $ssh_url"
    converted=$((converted + 1))
  fi
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')

if [[ "$converted" -gt 0 ]]; then
  git submodule sync --recursive >/dev/null 2>&1 || warn "git submodule sync failed"
fi

# 3. Each submodule's own origin remote (including nested ones)
git submodule foreach --quiet --recursive '
  url=$(git remote get-url origin 2>/dev/null || echo "")
  case "$url" in
    https://github.com/*)
      sshurl="${url/https:\/\/github.com\//git@github.com:}"
      git remote set-url origin "$sshurl"
      echo "  $name → $sshurl"
      ;;
  esac
' 2>/dev/null || true

if [[ "$converted" -gt 0 ]]; then
  success "$converted URL(s) converted — run .automations/update.sh to commit and push."
else
  success "All remotes are already SSH."
fi
