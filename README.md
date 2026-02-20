# cc-md

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-yellow)
![Obsidian](https://img.shields.io/badge/Obsidian-vault%20sync-7C3AED)
![iCloud](https://img.shields.io/badge/iCloud-supported-lightblue)

[中文](README.zh.md) | **English**

Local-first Obsidian multi-device sync. Zero cost. Zero signup. Zero maintenance.

## Why This Exists

Obsidian vault is just a folder of `.md` files. This means AI tools like Claude Code can **read and write your knowledge base directly**:

`No API` &ensp; `No plugins` &ensp; `No middleware`

```bash
# Claude Code works with your vault natively
Grep "system design" ~/vault/       # search all notes
Read ~/vault/some-note.md           # read content
Edit ~/vault/some-note.md           # modify content
Glob "**/*.md" ~/vault/             # traverse entire knowledge base
```

Compare with cloud-based solutions:

|  | Obsidian vault | Notion |
|--|---------------|--------|
| AI access | Read files directly, zero config | API + OAuth + MCP required |
| Data format | Standard markdown | Proprietary blocks, needs parsing |
| Read/write speed | Local I/O, milliseconds | Network requests + rate limits |
| Version history | Full Git log of every change | None |
| Data ownership | Files on your disk | Stored on someone else's server |

**Local files + standard format = no "integration" needed. It just works.**

cc-md simply keeps this local knowledge base in sync across all your devices.

## Architecture

```
iPhone Obsidian ←─ iCloud ─→ macOS Obsidian ←─ Git ─→ GitHub ←─ Git ─→ Windows Obsidian
```

- **macOS ↔ iOS**: iCloud auto-sync (seconds)
- **macOS ↔ GitHub**: Git timed sync (every 5 min, only when changes exist)
- **Windows ↔ GitHub**: Git manual or plugin sync

## Quick Start

```bash
# 1. Open Obsidian, create an iCloud vault (e.g. "notes")
# 2. Create a private repo on GitHub (e.g. "cc-md-vault")
# 3. Run:
git clone git@github.com:yourname/cc-md.git && cd cc-md && bash scripts/install.sh
# 4. Install Obsidian on iPhone, open the same iCloud vault
# Done.
```

## Prerequisites

- macOS + [Obsidian](https://obsidian.md) (free)
- Git + SSH key configured
- A **private** GitHub repo

## Installation

### Step 1: Create iCloud vault

Open Obsidian → Create new vault → Choose iCloud for storage → Create

### Step 2: Run install script

```bash
cd cc-md && bash scripts/install.sh
```

The script will ask three questions:

| Prompt | Input |
|--------|-------|
| Vault name | Your vault name, e.g. `notes` |
| GitHub remote URL | `git@github.com:yourname/repo.git` |
| Push now? | `y` |

### Step 3: Set up iOS

Install Obsidian on iPhone → Open the same iCloud vault → Done.

### Step 4: Set up Windows (optional)

```bash
git clone git@github.com:yourname/repo.git
```

Open the cloned directory with Obsidian. Recommend installing [obsidian-git](https://github.com/denolehov/obsidian-git) plugin for auto-sync.

## Verify

**Mac → iPhone**: Create a note on Mac, it should appear on iPhone within 30 seconds.

**iPhone → Mac**: Write something on iPhone, it should appear on Mac within 30 seconds.

**Git sync**: Wait 5 minutes or run `bash scripts/sync.sh`, then check GitHub for new commits.

## How Sync Works

**iCloud** (macOS ↔ iOS): Handled by Apple automatically. Vault lives at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault>/`. Syncs in seconds.

**Git** (macOS ↔ GitHub): A launchd job runs sync.sh every 5 minutes: check changes → `git add` → `git commit` → `git pull --rebase` → `git push`. Skips if nothing changed.

**Why 5 minutes**: 30s is too noisy, 1h is too slow, 5 min is just right for finishing a thought. Adjustable via `StartInterval` in `~/Library/LaunchAgents/com.cc-md.sync.plist`.

## Why Not Other Solutions

| Alternative | Why not |
|-------------|---------|
| iCloud everywhere | Poor Windows sync, no version history |
| Obsidian Sync | ~$4/mo, ~$480 over 10 years |
| Git everywhere | No good free Git client on iOS |
| Notion | Proprietary format, data not local, AI needs API |
| Self-hosted | High maintenance cost, dies when you stop |

This approach: iCloud for Apple ecosystem sync, Git for cross-platform + version history. Zero cost.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| iCloud corrupts .git | Low probability; remote repo is full backup |
| macOS off, iOS edits can't push | Auto-syncs when Mac wakes up |
| Git conflicts | `pull --rebase` + plain text is easy to resolve |
| GitHub down | Local + iCloud dual backup |

## Common Commands

```bash
bash scripts/sync.sh                        # manual sync
tail -20 ~/.cc-md/sync.log                  # view logs
launchctl list | grep cc-md                 # check if sync task is running (output = running, empty = stopped)
```

**Vault renamed?** No action needed. sync.sh auto-discovers the vault by scanning for `.git` in the iCloud Obsidian directory.

**Task not running?** Reload it:

```bash
launchctl load ~/Library/LaunchAgents/com.cc-md.sync.plist
```

## Uninstall

```bash
bash scripts/uninstall.sh
```

Your notes are not affected. iCloud sync continues. Only auto-push to GitHub stops.

## Project Structure

```
cc-md/
├── scripts/
│   ├── install.sh          # install
│   ├── uninstall.sh        # uninstall
│   └── sync.sh             # auto-sync (every 5 min)
├── com.cc-md.sync.plist    # launchd job template
├── LICENSE
├── README.md               # English
└── README.zh.md            # 中文
```
