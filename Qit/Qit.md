# Qit — Project Reference

> A lightweight PowerShell GUI app for quick Git operations. Built for developers who want to push, link, and clone repos without touching a terminal.

---

## What it is

Qit is a Windows desktop app (`Qit.ps1` + `Qit.vbs`) that wraps common Git workflows in a clean dark-themed GUI. It lives in `C:\Arun\Tools\Qit\` and is launched by double-clicking `Qit.vbs` (no console window).

---

## Files

| File | Purpose |
|------|---------|
| `Qit.ps1` | Main PowerShell script — all logic and UI |
| `Qit.vbs` | Silent launcher — runs Qit.ps1 with no console window via `powershell -WindowStyle Hidden -ExecutionPolicy Bypass` |
| `Qit.config` | Saved GitHub username (plain text, auto-created on first run) |
| `Qit.exe` | Optional compiled executable via ps2exe (see Option 3 below) |

---

## Startup sequence

Every time Qit launches it runs these checks in order, each only showing a prompt if needed:

1. **GitHub connectivity** — TCP check to `github.com:443` with 3 second timeout. Shows warning and exits if offline.
2. **Git installation** — Checks if `git` is on PATH. If missing, offers to install via `winget` automatically, or opens `https://git-scm.com/download/win` in the browser.
3. **Git identity** — Checks `git config --global user.name` and `user.email`. If either is blank, shows a form to set both (required for commits).
4. **GitHub username** — Checks `Qit.config` for a saved username. If missing, prompts once and saves it. Used for fetching public repo lists via the GitHub API (no token needed).
5. **Folder picker** — Standard Windows folder browser dialog. User picks the project folder to work in. The window opens pointing at that folder.

---

## Main window

**Size:** 640 x 620px, fixed single border, dark theme (`#121218` background).

### UI sections (top to bottom)

| Section | Description |
|---------|-------------|
| Blue accent strip | 4px top bar, color `RGB(88, 166, 255)` |
| **DIRECTORY** | Shows current folder path. **Change...** button opens folder browser |
| **GITHUB REPO** | Shows `repoName / branch` in blue if linked, yellow if local-only, red if not a repo. **Link Repo...** button (purple) appears when not linked. **Clone Repo...** button (teal) always visible |
| Divider | 1px separator |
| **COMMIT MESSAGE** | Single-line text box. Press Enter or click Quick Push to trigger |
| **OUTPUT** | RichTextBox log — colour-coded output from git commands |
| Bottom buttons | **Quick Push** (green), **Clear Log** (dark), **Change User** (dark) |

### Repo label format
`repoName / branchName` — extracted from the remote URL, `.git` suffix stripped. No full URL shown.

---

## Features

### Quick Push
Runs the standard commit + push sequence on the current folder:
```
git add .
git commit -m "<message>"
git push
```
- Enter key in the commit message box triggers this
- Disabled if the folder is not a linked git repo

### Link Repo
Connects a local folder (which may have existing code) to an existing GitHub repo and force-pushes all local content up, overwriting whatever was in the repo.

Flow:
1. Fetches all public repos for the saved GitHub username via `GET https://api.github.com/users/{username}/repos`
2. Shows a searchable listbox (sorted by last updated, type to filter)
3. User picks a repo and sets an initial commit message (defaults to "Initial commit")
4. Runs:
```
git init                          (if not already a repo)
git remote add origin <url>       (or set-url if remote exists)
git add .
git commit -m "<message>"
git branch -M main
git push -u origin main --force   (force overwrites repo contents)
```
5. On success, calls `Refresh-RepoInfo` to update the repo label

### Clone Repo
Downloads an existing repo from GitHub to a local folder on a fresh machine.

Flow:
1. Same searchable repo picker as Link Repo
2. Shows a destination folder field, pre-filled with `currentDirectory\repoName`. Selecting a repo auto-updates the path. Browse button available.
3. Creates the destination folder if it doesn't exist
4. Runs:
```
git clone <url> "<destPath>"
```
5. On success, automatically switches the main window to the cloned folder and refreshes repo info

---

## GitHub API

- **Endpoint:** `GET https://api.github.com/users/{username}/repos?per_page=100&page=N&sort=updated&type=owner`
- **Auth:** None — public repos only, no token required
- **Pagination:** Loops through pages until a page returns fewer than 100 results
- **Header:** `User-Agent: Qit-App`
- **Function:** `Get-GitHubPublicRepos($username)` — returns array of repo objects or `$null` on error

---

## Key functions

| Function | Purpose |
|----------|---------|
| `Get-SavedUsername` | Reads GitHub username from `Qit.config` |
| `Save-Username` | Writes username to `Qit.config` |
| `Prompt-ForUsername` | Shows username input dialog |
| `Get-GitHubPublicRepos` | Fetches paginated public repo list from GitHub API |
| `Get-GitRemoteUrl` | Returns `origin` remote URL or `$null` |
| `Get-RepoName` | Extracts repo name from a GitHub URL (strips path and `.git`) |
| `Is-GitRepo` | Returns true if current directory is inside a git repo |
| `Get-GitBranch` | Returns current branch name |
| `Append-Log` | Writes colour-coded text to the output RichTextBox |
| `Refresh-RepoInfo` | Updates directory label, repo label, and button visibility based on current folder state |

---

## Design rules

- **ASCII only** — no Unicode characters, emoji, or special symbols in any PowerShell strings (causes encoding errors on some machines)
- **Flat style** — all buttons use `FlatStyle = "Flat"`, no borders on primary action buttons
- **Colour coding in output log:**
  - White/default — info messages
  - Green `RGB(80, 200, 120)` — success steps (OK:)
  - Red `RGB(255, 100, 100)` — failures (FAILED:, ERROR:)
  - Yellow `RGB(255, 200, 80)` — warnings
  - Blue `RGB(88, 166, 255)` — final success (SUCCESS:)
  - Dark grey `RGB(50, 50, 70)` — separators
  - Muted blue `RGB(100, 120, 160)` — info/switched messages
- **Form brought to front** on show via `Activate()` + `TopMost` toggle to prevent it hiding behind other windows after folder picker closes

---

## Button colour reference

| Button | Color | RGB |
|--------|-------|-----|
| Quick Push | Green | `(35, 134, 54)` |
| Link Repo... | Purple | `(88, 60, 160)` |
| Clone Repo... | Teal | `(30, 100, 140)` |
| Change... / Clear Log / Change User | Dark | `(40, 40, 58)` |

---

## Option 3 — Compile to .exe

To show Qit as its own app in the taskbar (not as a PowerShell process):

```powershell
# One-time: install ps2exe
Install-Module ps2exe -Scope CurrentUser -Force

# Compile
ps2exe C:\Arun\Tools\Qit\Qit.ps1 C:\Arun\Tools\Qit\Qit.exe -noConsole -title "Qit"

# Optional: with custom icon
ps2exe C:\Arun\Tools\Qit\Qit.ps1 C:\Arun\Tools\Qit\Qit.exe -noConsole -title "Qit" -iconFile C:\Arun\Tools\Qit\Qit.ico
```

Recompile any time `Qit.ps1` is updated.

---

## Planned / in-progress features

- [ ] Sync status indicator — show whether local folder is ahead/behind/in-sync with remote
- [ ] Compile-to-exe suggestion banner in the app UI

---

## Claude Code prompt conventions

When writing prompts for Claude Code to extend Qit, always include:

```
File: C:\Arun\Tools\Qit\Qit.ps1

Task: <description>

Keep all existing functionality unchanged. ASCII only, no unicode or emoji in PowerShell strings.
```

Reference existing functions by name (e.g. `Get-GitHubPublicRepos`, `Refresh-RepoInfo`, `Append-Log`) so Claude Code knows to reuse them rather than rewrite them.
