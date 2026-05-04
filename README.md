# Workspace Template - Clone one, access everything!

A GitHub template for creating a centralized Git super-repo that consolidates your projects using Git submodules. Each project is maintained as an independent submodule, preserving its own history and versioning while enabling a one-clone, multi-device workflow.

```filetree
workspace/
├─ .automations/               # automation scripts
│  ├─ add-submodule.sh         # add new submodule (auto-sorts everything)
│  ├─ bootstrap.sh             # clone-time submodule branch checkout
│  ├─ clean-gitmodules.sh      # clean and sort .gitmodules
│  ├─ generate-tree.sh         # shared tree generation logic
│  ├─ install.sh               # setup script for new workspaces
│  ├─ remove-submodule.sh      # remove submodule completely
│  └─ update.sh                # update all submodules, commit & push
```

---

## Why This Structure?

* **Single-Clone Onboarding** – Clone once, get everything; no more juggling dozens of repos
* **Independent Versioning** – Submodules maintain separate commit histories and release cycles
* **Zero Noise** – `ignore = all` silences pointer drift until you intentionally update
* **Multi-Device Consistency** – Same codebase on any laptop, desktop, or CI agent
* **Modular Experimentation** – Add or remove projects without polluting the super-repo history
* **Developer-Safe** – Local changes are never lost during automation runs
* **Automated Updates** – GitHub Actions keeps everything synchronized with zero manual effort

---

## Getting Started

### Use This Template

1. Click **"Use this template"** on GitHub to create your own workspace
2. Clone your new repository:
   ```bash
   git clone --recursive <your-workspace-url>
   cd workspace
   ```
3. Run the setup script:
   ```bash
   chmod +x .automations/install.sh
   ./.automations/install.sh
   ```

---

## Daily Workflow

### Update All Submodules

```bash
chmod +x .automations/update.sh
.automations/update.sh
```

This script intelligently handles updates based on where it runs:

**Local Development (Your Computer):**
* Detects your current branch and uncommitted changes in each submodule
* Temporarily switches to configured default branch (main) for updates
* Fetches and pulls latest changes from remote
* **Automatically restores your original branch and stashed changes** after update
* Your work is 100% preserved - no data loss, no surprises

**GitHub Actions (CI/CD):**
* Runs fast on default branch for clean automation
* Fetches, pulls, and pushes all submodule updates
* Creates descriptive commit and pushes workspace changes
* No state preservation overhead needed in automation environment

**Key Benefits:**
* Safe for multi-branch local development (e.g., working on feature branches)
* No risk of losing uncommitted work
* Automatic stash/restore for seamless integration
* Only workspace pointer changes are pushed - your submodule work stays local until you explicitly commit

**Example Scenario:**
```
BEFORE UPDATE:
  project-a/      → on branch "feature-config" with 3 uncommitted files
  project-b/      → on main (clean)

RUN: .automations/update.sh

AFTER UPDATE:
  project-a/      → restored to "feature-config" with 3 files unstaged again ✓
  project-b/      → updated to latest on main
  
Your work is intact!
```

---

## Adding a New Submodule

```bash
chmod +x .automations/add-submodule.sh
.automations/add-submodule.sh
```

The script will:

1. Prompt for the SSH URL
2. Add submodule with `ignore = all` configuration
3. Sort `.gitmodules` alphabetically
4. Optionally commit and push changes

**Manual method:**

```bash
git submodule add --branch main <repo-url> <folder>
git config -f .gitmodules submodule.<folder>.ignore all
git add .gitmodules <folder>
git commit -m "chore: add <folder> submodule"
git push origin main
```

---

## Cleaning .gitmodules

```bash
chmod +x .automations/clean-gitmodules.sh
.automations/clean-gitmodules.sh
```

Rebuilds `.gitmodules` with:

* Alphabetical sorting
* Consistent formatting (tabs, spacing)
* All required fields (path, url, branch, ignore)

---

## Removing a Submodule

```bash
chmod +x .automations/remove-submodule.sh
.automations/remove-submodule.sh
```

Or manually:

```bash
# Deinitialize submodule
git submodule deinit -f <folder>

# Remove from repository
git rm <folder>

# Remove metadata
rm -rf .git/modules/<folder>

# Edit .gitmodules manually to remove entry

# Commit & push
git commit -m "chore: remove <folder> submodule"
git push origin main
```

---

## Automated Nightly Updates

GitHub Actions automatically runs every night at **02:00 UTC** to keep everything synchronized:

* Updates all submodules to latest upstream commits
* Detects and fixes orphaned submodule commits (safeguard against data corruption)
* Commits changes with descriptive message (e.g., "chore: bump project-a, project-b to latest upstream")
* Pushes to main branch
* Generates summary in Actions workflow output

**No manual intervention needed** – your repositories stay in sync automatically.

**Setup required:** 
1. Push your workspace to GitHub
2. Go to Settings → Secrets and variables → Actions
3. Add `SSH_PRIVATE_KEY` secret with your GitHub SSH private key
4. Workflow will run automatically

**Manual trigger:** Go to Actions → Nightly Submodule Update → Run workflow

---

## Automation Architecture

### Local Development Scripts (.automations/)

All scripts use bash with strict error handling (`set -euo pipefail`) for reliability:

* **update.sh** – Dual-mode update engine (local-safe + CI-fast)
* **bootstrap.sh** – Clone-time initialization
* **add-submodule.sh** – Smart submodule addition with sorting
* **remove-submodule.sh** – Complete submodule removal
* **clean-gitmodules.sh** – Configuration cleanup and formatting
* **generate-tree.sh** – Shared tree generation with ASCII sorting

### GitHub Actions Workflow (.github/workflows/)

* **nightly-update.yml** – Scheduled automation (02:00 UTC daily)
  * Checks out repository with SSH credentials
  * Runs update.sh in GitHub Actions mode (`$GITHUB_ACTIONS=true`)
  * Generates workflow summary
  * Automatically pushes updates

---

## Optional Configuration

```bash
# Suppress submodule status in git status
git config status.submoduleSummary false

# Ignore all submodule diffs
git config diff.ignoreSubmodules all
```

---

## Useful Commands

```bash
# Check status of all submodules
git submodule status --recursive

# Run command in all submodules
git submodule foreach '<command>'

# Update specific submodule
git submodule update --remote <folder>

# View submodule configuration
git config --file .gitmodules --list
```

---

## Troubleshooting

**Submodule not updating?**

```bash
cd <submodule>
git fetch origin main
git pull origin main
cd ..
git add <submodule>
git commit -m "manual update"
git push
```

**Lost uncommitted changes after running update.sh?**

Check your git stash:
```bash
git stash list
git stash pop  # Restore most recent stash
```

The update script creates named stashes like `workspace-update-backup-<submodule>` for recovery.

**Merge conflicts?**

```bash
git fetch origin main
git pull origin main --rebase
# Resolve conflicts if any
git push origin main
```

**GitHub Actions failing?**

* Verify `SSH_PRIVATE_KEY` secret is configured in repository settings
* Ensure SSH key has access to all submodule repositories
* Review Actions logs for specific error messages
* Check that all submodule URLs use SSH format (`git@github.com:...`)

---

## Philosophy

* **Atomic Onboarding** – One clone, infinite projects
* **Clean Histories** – No noise from pointer drifts
* **Low Friction** – Seamless submodule management
* **Developer-First** – Automation that respects your work, never loses your data
* **Learning Sandbox** – Central hub for experiments and demos
* **Automated Maintenance** – GitHub Actions handles routine updates, local scripts stay flexible

---

Happy coding! Clone once, access everything.
