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
chmod +x .automations/*.sh
echo -e "${GREEN}✓ Scripts are now executable${NC}"

# Initialize submodules if .gitmodules exists and has entries
if [ -s ".gitmodules" ]; then
    echo -e "\n${YELLOW}Initializing submodules...${NC}"
    git submodule update --init --recursive
    
    # Run bootstrap if it exists
    if [ -f ".automations/bootstrap.sh" ]; then
        .automations/bootstrap.sh
    fi
    echo -e "${GREEN}✓ Submodules initialized${NC}"
fi

# Setup instructions
echo -e "\n${BLUE}════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup Complete!${NC}\n"

echo -e "${YELLOW}Next Steps:${NC}\n"

echo "1. Add your first submodule:"
echo -e "   ${BLUE}.automations/add-submodule.sh${NC}\n"

echo "2. Or manually add a project:"
echo -e "   ${BLUE}git submodule add --branch main <url> <folder>${NC}\n"

echo "3. Update all submodules:"
echo -e "   ${BLUE}.automations/update.sh${NC}\n"

echo "4. View available commands:"
echo -e "   ${BLUE}git submodule foreach '<command>'${NC}\n"

echo "5. Create initial commit and push:"
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
