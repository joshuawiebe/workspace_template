#!/usr/bin/env bash
# ==============================================================================
# Generate README Tree Function
# Shared function for all automation scripts to generate perfectly formatted tree
# ==============================================================================

generate_readme_tree() {
  local names="$1"
  
  # Start tree
  echo '```filetree'
  echo 'workspace/'
  
  # Define all entries with their descriptions
  local -A entries=(
    [".automations/"]="automation scripts"
    ["add-submodule.sh"]="add new submodule (auto-sorts everything)"
    ["bootstrap.sh"]="clone-time submodule branch checkout"
    ["clean-gitmodules.sh"]="clean and sort .gitmodules"
    ["generate-tree.sh"]="shared tree generation logic"
    ["install.sh"]="setup script for new workspaces"
    ["remove-submodule.sh"]="remove submodule completely"
    ["update.sh"]="update all submodules, commit & push"
    [".github/"]="hidden github automation scripts"
    ["workflows/"]="all worklows for github automations"
    ["nightly-update.yml"]="automated nightly updates at 02:00 UTC"
  )
  
  # Collect all potential entries to find max length
  local all_entries=()
  
  # Add automation entries
  all_entries+=("├─ .automations/")
  all_entries+=("│  ├─ add-submodule.sh")
  all_entries+=("│  ├─ bootstrap.sh")
  all_entries+=("│  ├─ clean-gitmodules.sh")
  all_entries+=("│  ├─ generate-tree.sh")
  all_entries+=("│  ├─ install.sh")
  all_entries+=("│  ├─ remove-submodule.sh")
  all_entries+=("│  └─ update.sh")
  all_entries+=("├─ .github/")
  all_entries+=("│  └─ workflows/")
  all_entries+=("│     └─ nightly-update.yml")
  
  # Add submodule entries
  while IFS= read -r name; do
    if [[ -n "$name" ]]; then
      if [[ "$name" == "saved/"* ]]; then
        local submodule_basename="${name#saved/}"
        all_entries+=("├─ saved/")
        all_entries+=("│  └─ ${submodule_basename}/")
      else
        all_entries+=("├─ ${name}/")
      fi
    fi
  done <<< "$names"
  
  # Add final entries
  all_entries+=("├─ .gitignore")
  all_entries+=("├─ .gitmodules")
  all_entries+=("└─ README.md")
  
  # Find the longest entry to determine comment alignment
  local max_len=0
  for entry in "${all_entries[@]}"; do
    local entry_len=${#entry}
    if [[ $entry_len -gt $max_len ]]; then
      max_len=$entry_len
    fi
  done
  
  # Add 2 spaces padding before comment
  local comment_col=$((max_len + 2))
  
  # Find the longest entry to determine comment alignment
  local max_len=0
  for entry in "${all_entries[@]}"; do
    local entry_len=${#entry}
    if [[ $entry_len -gt $max_len ]]; then
      max_len=$entry_len
    fi
  done
  
  # Add 2 spaces padding before comment
  local comment_col=$((max_len + 2))
  
  # Print automation section with dynamic alignment
  local auto_entry="├─ .automations/"
  local auto_spaces=$((comment_col - ${#auto_entry}))
  local auto_padding=$(printf "%*s" "$auto_spaces")
  echo "${auto_entry}${auto_padding}# ${entries[.automations/]}"
  
  local add_entry="│  ├─ add-submodule.sh"
  local add_spaces=$((comment_col - ${#add_entry}))
  local add_padding=$(printf "%*s" "$add_spaces")
  echo "${add_entry}${add_padding}# ${entries[add-submodule.sh]}"
  
  local boot_entry="│  ├─ bootstrap.sh"
  local boot_spaces=$((comment_col - ${#boot_entry}))
  local boot_padding=$(printf "%*s" "$boot_spaces")
  echo "${boot_entry}${boot_padding}# ${entries[bootstrap.sh]}"
  
  local clean_entry="│  ├─ clean-gitmodules.sh"
  local clean_spaces=$((comment_col - ${#clean_entry}))
  local clean_padding=$(printf "%*s" "$clean_spaces")
  echo "${clean_entry}${clean_padding}# ${entries[clean-gitmodules.sh]}"
  
  local gen_entry="│  ├─ generate-tree.sh"
  local gen_spaces=$((comment_col - ${#gen_entry}))
  local gen_padding=$(printf "%*s" "$gen_spaces")
  echo "${gen_entry}${gen_padding}# ${entries[generate-tree.sh]}"
  
  local install_entry="│  ├─ install.sh"
  local install_spaces=$((comment_col - ${#install_entry}))
  local install_padding=$(printf "%*s" "$install_spaces")
  echo "${install_entry}${install_padding}# ${entries[install.sh]}"
  
  local remove_entry="│  ├─ remove-submodule.sh"
  local remove_spaces=$((comment_col - ${#remove_entry}))
  local remove_padding=$(printf "%*s" "$remove_spaces")
  echo "${remove_entry}${remove_padding}# ${entries[remove-submodule.sh]}"
  
  local update_entry="│  └─ update.sh"
  local update_spaces=$((comment_col - ${#update_entry}))
  local update_padding=$(printf "%*s" "$update_spaces")
  echo "${update_entry}${update_padding}# ${entries[update.sh]}"
  
  # Print github section
  local github_entry="├─ .github/"
  local github_spaces=$((comment_col - ${#github_entry}))
  local github_padding=$(printf "%*s" "$github_spaces")
  echo "${github_entry}${github_padding}# ${entries[.github/]}"
  
  local workflows_entry="│  └─ workflows/"
  local workflows_spaces=$((comment_col - ${#workflows_entry}))
  local workflows_padding=$(printf "%*s" "$workflows_spaces")
  echo "${workflows_entry}${workflows_padding}# ${entries[workflows/]}"
  
  local nightly_entry="│     └─ nightly-update.yml"
  local nightly_spaces=$((comment_col - ${#nightly_entry}))
  local nightly_padding=$(printf "%*s" "$nightly_spaces")
  echo "${nightly_entry}${nightly_padding}# ${entries[nightly-update.yml]}"
  
  # Process all submodules and sort them alphabetically
  local all_modules=()
  
  while IFS= read -r name; do
    if [[ -n "$name" ]]; then
      all_modules+=("$name")
    fi
  done <<< "$names"
  
  # Sort all modules alphabetically (ASCII sorting to match GitHub)
  IFS=$'\n' sorted_modules=($(LC_ALL=C sort <<<"${all_modules[*]}"))
  unset IFS
  
  # Process each module and determine if it's a saved/ module or regular module
  local saved_modules_added=false
  
  for name in "${sorted_modules[@]}"; do
    if [[ "$name" == "saved/"* ]]; then
      # First time we encounter a saved/ module, add saved/ directory header
      if [[ "$saved_modules_added" == false ]]; then
        local saved_entry="├─ saved/"
        local saved_spaces=$((comment_col - ${#saved_entry}))
        local saved_padding=$(printf "%*s" "$saved_spaces")
        echo "${saved_entry}${saved_padding}# directory → saved repos from others i want to have locally"
        saved_modules_added=true
      fi
      
      # Extract just the submodule name after saved/
      local submodule_basename="${name#saved/}"
      local prefix="│  └─ ${submodule_basename}/"
      local current_len=${#prefix}
      local spaces_needed=$((comment_col - current_len))
      local padding=$(printf "%*s" "$spaces_needed")
      
      # Get the actual URL from .gitmodules
      local url=$(git config --file .gitmodules "submodule.${name}.url" 2>/dev/null || echo "git@github.com:frontend-joe/${submodule_basename}.git")
      
      echo "${prefix}${padding}# submodule → ${url}"
    else
      # Regular submodule - calculate padding based on comment column
      local prefix="├─ ${name}/"
      local current_len=${#prefix}
      local spaces_needed=$((comment_col - current_len))
      local padding=$(printf "%*s" "$spaces_needed")
      
      # Get the actual URL from .gitmodules
      local url=$(git config --file .gitmodules "submodule.${name}.url" 2>/dev/null || echo "git@github.com:joshuawiebe/${name}.git")
      
      echo "${prefix}${padding}# submodule → ${url}"
    fi
  done
  
  # Add final files
  local gitignore_entry="├─ .gitignore"
  local gitignore_spaces=$((comment_col - ${#gitignore_entry}))
  local gitignore_padding=$(printf "%*s" "$gitignore_spaces")
  echo "${gitignore_entry}${gitignore_padding}# root ignores"
  
  local gitmodules_entry="├─ .gitmodules"
  local gitmodules_spaces=$((comment_col - ${#gitmodules_entry}))
  local gitmodules_padding=$(printf "%*s" "$gitmodules_spaces")
  echo "${gitmodules_entry}${gitmodules_padding}# defines all submodules (ignore = all)"
  
  local readme_entry="└─ README.md"
  local readme_spaces=$((comment_col - ${#readme_entry}))
  local readme_padding=$(printf "%*s" "$readme_spaces")
  echo "${readme_entry}${readme_padding}# this file"
  echo '```'
}

update_readme_tree() {
  local names="$1"
  
  if [[ ! -f README.md ]]; then
    echo "README.md not found, skipping tree update."
    return 0
  fi
  
  # Generate tree content to a temporary file
  local temp_tree=$(mktemp)
  generate_readme_tree "$names" >"$temp_tree"

  # Use awk to precisely replace the filetree block
  awk '
  BEGIN { in_tree = 0; skip_next = 0 }
  /^```filetree$/ { 
    in_tree = 1
    while ((getline line < "'"$temp_tree"'") > 0) {
      print line
    }
    close("'"$temp_tree"'")
    skip_next = 1
    next
  }
  in_tree && /^```$/ && skip_next { 
    in_tree = 0
    skip_next = 0
    next
  }
  !in_tree { print }
  ' README.md > README.md.tmp && mv README.md.tmp README.md

  rm -f "$temp_tree"
}

# Main execution when script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Get all submodule names and update the README tree
  names=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' | LC_ALL=C sort)
  update_readme_tree "$names"
fi
