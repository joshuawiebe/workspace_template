#!/bin/bash
# Workspace Template - Setup Guide
# This script guides you through setting up your workspace

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════╗"
echo "║   Workspace Template - Initial Setup       ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Check if git is configured
echo -e "${YELLOW}Checking git configuration...${NC}"
if ! git config user.name > /dev/null 2>&1; then
    echo -e "${YELLOW}Git user not configured. Setting up...${NC}"
    read -p "Enter your name: " git_name
    read -p "Enter your email: " git_email
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    echo -e "${GREEN}✓ Git configured${NC}"
else
    echo -e "${GREEN}✓ Git already configured${NC}"
fi

# Initialize repository if needed
if [ ! -d ".git" ]; then
    echo -e "\n${YELLOW}Initializing git repository...${NC}"
    git init
    git config user.name "$(git config --global user.name)"
    git config user.email "$(git config --global user.email)"
    git branch -M main
    echo -e "${GREEN}✓ Repository initialized${NC}"
else
    echo -e "${GREEN}✓ Already a git repository${NC}"
fi

# Make scripts executable
echo -e "\n${YELLOW}Setting up automation scripts...${NC}"
find .automations/ -maxdepth 1 -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
echo -e "${GREEN}✓ Scripts are now executable${NC}"

# Initialize submodules if .gitmodules exists and has entries
if [ -s "../.gitmodules" ]; then
    echo -e "\n${YELLOW}Initializing submodules...${NC}"
    git submodule update --init --recursive
    
    # Run bootstrap if it exists
    if [ -f "bootstrap.sh" ]; then
        ./bootstrap.sh
    fi
    echo -e "${GREEN}✓ Submodules initialized${NC}"
fi

# Setup instructions
echo -e "\n${BLUE}════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup Complete!${NC}\n"

echo -e "${YELLOW}Available Automation Scripts:${NC}\n"

echo "1. ${BLUE}add-submodule.sh${NC} - Add a new Git submodule to your workspace"
echo "   - Prompts for SSH URL (git@github.com:user/repo.git)"
echo "   - Automatically sorts .gitmodules alphabetically"
echo "   - Updates README.md tree structure"
echo "   - Use this first to add your projects!\n"

echo "2. ${BLUE}bootstrap.sh${NC} - Initialize and checkout correct branches for all submodules"
echo "   - Run after cloning a workspace with existing submodules"
echo "   - Ensures all submodules are on their configured branches"
echo "   - Run this after adding your first submodule\n"

echo "3. ${BLUE}update.sh${NC} - Update all submodules to latest upstream commits"
echo "   - Safely handles local changes (stashes and restores them)"
echo "   - Commits submodule pointer updates to workspace repo"
echo "   - In GitHub Actions: creates commits like 'chore: bump repo1, repo2 to latest upstream'\n"

echo "4. ${BLUE}remove-submodule.sh${NC} - Completely remove a submodule"
echo "   - Cleans up .gitmodules, git cache, and README.md"
echo "   - Use when you want to permanently remove a project\n"

echo "5. ${BLUE}clean-gitmodules.sh${NC} - Rebuild and sort .gitmodules alphabetically"
echo "   - Useful if .gitmodules gets out of order or corrupted\n"

echo -e "${YELLOW}Recommended Workflow:${NC}\n"

echo "1. Add your first submodule:"
echo -e "   ${BLUE}./add-submodule.sh${NC}\n"

echo "2. Bootstrap to ensure proper initialization:"
echo -e "   ${BLUE}./bootstrap.sh${NC}\n"

echo "3. Update all submodules regularly:"
echo -e "   ${BLUE}./update.sh${NC}\n"

echo "4. Or manually add a project:"
echo -e "   ${BLUE}git submodule add --branch main <url> <folder>${NC}\n"

echo "5. View available commands:"
echo -e "   ${BLUE}git submodule foreach '<command>'${NC}\n"

echo "6. Create initial commit and push:"
echo -e "   ${BLUE}git add .${NC}"
echo -e "   ${BLUE}git commit -m 'chore: initial setup'${NC}"
echo -e "   ${BLUE}git remote add origin <your-github-url>${NC}"
echo -e "   ${BLUE}git push -u origin main${NC}\n"

echo -e "${YELLOW}GitHub Actions Setup (optional):${NC}"
echo "  1. Push to GitHub"
echo "  2. Settings → Secrets and variables → Actions"
echo "  3. Add SSH_PRIVATE_KEY with your GitHub SSH key"
echo "  4. Nightly updates run automatically at 02:00 UTC\n"

echo -e "${BLUE}For more information, see README.md${NC}\n"

# Generate README with dynamic content (only if template markers or email placeholder still exist)
user_email=$(git config user.email 2>/dev/null || echo "your-email@example.com")
if grep -q '<!-- TEMPLATE_START -->' README.md 2>/dev/null || grep -q 'ssh-keygen -t ed25519 -C "your-email@example.com"' README.md 2>/dev/null; then
    bash "$(dirname "$0")/generate-tree.sh" --customize "$user_email"
fi
