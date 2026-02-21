#!/bin/bash
# =========================================================================
# cc-md setup — 智能安装器
# =========================================================================
# 分 8 个 phase，每个 phase 幂等（检测已完成则跳过）：
#   0. Pre-flight：检查 git、SSH key、iCloud 目录
#   1. 自动发现/选择 vault
#   2. vault 内 git init
#   3. 连接 GitHub remote（gh 自动建 repo / 手动贴 URL）
#   4. 首次 push（先测 SSH 连通性）
#   5. 安装 launchd daemon
#   6. 安装 CLI + 自动修 PATH
#   7. 打印摘要
#
# 设计理念：
#   最好的情况：零提示，全自动
#   最差的情况：每一步失败都告诉你怎么修
# =========================================================================

set -euo pipefail

# ---------- 路径变量 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync.sh"
PLIST_TEMPLATE="$PROJECT_DIR/com.cc-md.sync.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.cc-md.sync.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
STATE_DIR="$HOME/.cc-md"
ICLOUD_OBSIDIAN="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"

# ---------- 输出工具 ----------
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

phase() {
    echo ""
    echo -e "${BOLD}[$1/7] $2${NC}"
}

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

skip() {
    echo -e "  ${DIM}· $1 (already done)${NC}"
}

warn() {
    echo -e "  ${YELLOW}!${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
}

# =========================================================================
# Phase 0: Pre-flight
# =========================================================================
phase 0 "Pre-flight checks"

# git
if ! command -v git &>/dev/null; then
    fail "git not found"
    echo ""
    echo "  Install Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi
ok "git available"

# SSH key
if [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ecdsa" ]; then
    ok "SSH key found"
else
    fail "No SSH key found (~/.ssh/id_ed25519 or id_rsa)"
    echo ""
    echo "  Generate one:"
    echo "    ssh-keygen -t ed25519 -C \"your-email@example.com\""
    echo ""
    echo "  Add it to GitHub:"
    echo "    https://github.com/settings/keys"
    echo ""
    echo "  Then re-run this installer."
    exit 1
fi

# iCloud Obsidian directory
if [ ! -d "$ICLOUD_OBSIDIAN" ]; then
    fail "iCloud Obsidian directory not found"
    echo ""
    echo "  Expected: $ICLOUD_OBSIDIAN"
    echo ""
    echo "  Fix: Open Obsidian → Create new vault → Storage: iCloud"
    echo "  Then re-run this installer."
    exit 1
fi
ok "iCloud Obsidian directory found"

# =========================================================================
# Phase 1: Vault discovery
# =========================================================================
phase 1 "Vault discovery"

VAULT_DIR=""

# Check if already configured and valid
if [ -f "$STATE_DIR/vault-path" ]; then
    saved="$(cat "$STATE_DIR/vault-path")"
    if [ -d "$saved" ]; then
        VAULT_DIR="$saved"
        skip "using configured vault: $(basename "$VAULT_DIR")"
    fi
fi

if [ -z "$VAULT_DIR" ]; then
    # Scan for vaults
    vaults=()
    while IFS= read -r -d '' dir; do
        name="$(basename "$dir")"
        # Skip hidden directories
        [[ "$name" == .* ]] && continue
        vaults+=("$dir")
    done < <(find "$ICLOUD_OBSIDIAN" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    if [ ${#vaults[@]} -eq 0 ]; then
        fail "No vaults found in iCloud Obsidian directory"
        echo ""
        echo "  Fix: Open Obsidian → Create new vault → Storage: iCloud"
        echo "  Then re-run this installer."
        exit 1
    elif [ ${#vaults[@]} -eq 1 ]; then
        # Single vault — zero prompts
        VAULT_DIR="${vaults[0]}"
        ok "found vault: $(basename "$VAULT_DIR")"
    else
        # Multiple vaults — numeric selection
        echo "  Found ${#vaults[@]} vaults:"
        echo ""
        for i in "${!vaults[@]}"; do
            local_name="$(basename "${vaults[$i]}")"
            echo "    $((i + 1)). $local_name"
        done
        echo ""
        read -r -p "  Choose vault [1-${#vaults[@]}]: " choice
        # Validate input
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#vaults[@]} ]; then
            fail "Invalid choice: $choice"
            exit 1
        fi
        VAULT_DIR="${vaults[$((choice - 1))]}"
        ok "selected vault: $(basename "$VAULT_DIR")"
    fi
fi

VAULT_NAME="$(basename "$VAULT_DIR")"

# =========================================================================
# Phase 2: Git init
# =========================================================================
phase 2 "Git init in vault"

if [ -d "$VAULT_DIR/.git" ]; then
    skip "git repo exists in $VAULT_NAME"
else
    cd "$VAULT_DIR"
    git init -b main --quiet

    # Create .gitignore
    cat > .gitignore << 'GITIGNORE'
# Obsidian local config (device-specific, not synced)
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/appearance.json
.trash/
.DS_Store
GITIGNORE

    git add -A
    git commit -m "init: cc-md vault" --quiet --no-gpg-sign
    ok "initialized git repo with first commit"
fi

# Save vault config
mkdir -p "$STATE_DIR"
echo "$VAULT_DIR" > "$STATE_DIR/vault-path"
export CC_MD_VAULT_DIR="$VAULT_DIR"

# =========================================================================
# Phase 3: GitHub remote
# =========================================================================
phase 3 "Connect to GitHub"

cd "$VAULT_DIR"

if git remote get-url origin &>/dev/null; then
    skip "remote already configured: $(git remote get-url origin)"
else
    REMOTE_URL=""

    # Try gh CLI first
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        ok "gh CLI authenticated"
        # Get GitHub username
        gh_user="$(gh api user --jq '.login' 2>/dev/null || echo "")"
        if [ -n "$gh_user" ]; then
            repo_name="cc-md-vault"
            echo -e "  ${DIM}Creating private repo: $gh_user/$repo_name${NC}"
            if gh repo create "$repo_name" --private --source="$VAULT_DIR" --remote=origin 2>/dev/null; then
                ok "created private repo: $gh_user/$repo_name"
                REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
            else
                # Repo might already exist, try to set remote
                REMOTE_URL="git@github.com:$gh_user/$repo_name.git"
                git remote add origin "$REMOTE_URL" 2>/dev/null || true
                ok "connected to existing repo: $gh_user/$repo_name"
            fi
        fi
    fi

    # Fallback: ask for URL
    if [ -z "$REMOTE_URL" ] && ! git remote get-url origin &>/dev/null; then
        echo ""
        if ! command -v gh &>/dev/null; then
            warn "gh CLI not found (optional but recommended)"
            echo "    Install: https://cli.github.com"
            echo ""
        fi
        echo "  Create a private repo on GitHub:"
        echo "    https://github.com/new"
        echo ""
        read -r -p "  Paste repo SSH URL (git@github.com:user/repo.git): " REMOTE_URL

        # Validate URL format
        if [[ ! "$REMOTE_URL" =~ ^git@github\.com:.+/.+\.git$ ]]; then
            fail "Invalid URL format: $REMOTE_URL"
            echo ""
            echo "  Expected format: git@github.com:username/repo.git"
            exit 1
        fi

        git remote add origin "$REMOTE_URL"
        ok "remote configured: $REMOTE_URL"
    fi
fi

# =========================================================================
# Phase 4: First push
# =========================================================================
phase 4 "First push"

cd "$VAULT_DIR"

# Check if remote already has commits
if git ls-remote origin HEAD &>/dev/null 2>&1; then
    remote_head="$(git ls-remote origin HEAD 2>/dev/null | awk '{print $1}')"
    if [ -n "$remote_head" ]; then
        skip "remote already has commits"
    else
        # Remote exists but empty — push
        _do_push=1
    fi
else
    _do_push=1
fi

if [ "${_do_push:-0}" = "1" ]; then
    # Test SSH connectivity first
    echo -e "  ${DIM}Testing SSH connection to GitHub...${NC}"
    if ssh -T git@github.com 2>&1 | grep -qi "successfully authenticated"; then
        ok "SSH connection works"
    else
        # ssh -T returns exit code 1 even on success, check stderr
        ssh_output="$(ssh -T git@github.com 2>&1 || true)"
        if echo "$ssh_output" | grep -qi "successfully authenticated\|Hi "; then
            ok "SSH connection works"
        else
            fail "SSH authentication failed"
            echo ""
            echo "  1. Check your SSH key is added to GitHub:"
            echo "     https://github.com/settings/keys"
            echo ""
            echo "  2. Test manually:"
            echo "     ssh -T git@github.com"
            echo ""
            echo "  Re-run this installer after fixing."
            exit 1
        fi
    fi

    if git push -u origin main 2>/dev/null; then
        ok "pushed to remote"
    else
        fail "push failed"
        echo ""
        echo "  Check: does the remote repo exist and is it empty?"
        echo "  Try: git -C \"$VAULT_DIR\" push -u origin main"
        exit 1
    fi
fi

# =========================================================================
# Phase 5: launchd daemon
# =========================================================================
phase 5 "Install sync daemon"

mkdir -p "$LAUNCH_AGENTS_DIR"

if launchctl list 2>/dev/null | grep -q "com.cc-md.sync"; then
    skip "launchd job already loaded"
else
    # Generate plist from template
    sed -e "s|__CC_MD_SYNC_SCRIPT__|$SYNC_SCRIPT|g" \
        -e "s|__CC_MD_HOME__|$HOME|g" \
        "$PLIST_TEMPLATE" > "$PLIST_TARGET"

    # Add environment variables
    /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$PLIST_TARGET" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:CC_MD_VAULT_DIR '$VAULT_DIR'" "$PLIST_TARGET" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CC_MD_VAULT_DIR string '$VAULT_DIR'" "$PLIST_TARGET"
    /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:PATH string '/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin'" "$PLIST_TARGET" 2>/dev/null || true

    launchctl unload "$PLIST_TARGET" 2>/dev/null || true
    launchctl load "$PLIST_TARGET"
    ok "sync daemon installed (every 5 min)"
fi

# =========================================================================
# Phase 6: CLI install
# =========================================================================
phase 6 "Install md CLI"

mkdir -p "$HOME/.local/bin"
ln -sf "$SCRIPT_DIR/cc-md" "$HOME/.local/bin/md"

if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    skip "md command in PATH"
else
    # Auto-fix PATH
    shell_rc=""
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_rc="$HOME/.bash_profile"
    fi

    if [ -n "$shell_rc" ]; then
        if ! grep -q '\.local/bin' "$shell_rc" 2>/dev/null; then
            echo '' >> "$shell_rc"
            echo '# cc-md CLI' >> "$shell_rc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
            ok "added ~/.local/bin to PATH in $(basename "$shell_rc")"
            warn "run: source $shell_rc (or open new terminal)"
        else
            ok "PATH entry already in $(basename "$shell_rc")"
        fi
    else
        warn "could not find shell rc file, add manually:"
        echo '    export PATH="$HOME/.local/bin:$PATH"'
    fi
fi
ok "installed: md → $(readlink "$HOME/.local/bin/md" 2>/dev/null || echo "$SCRIPT_DIR/cc-md")"

# =========================================================================
# Phase 7: Summary
# =========================================================================
phase 7 "Done"

echo ""
echo -e "${GREEN}  cc-md is running.${NC}"
echo ""
echo "  Vault:  $VAULT_DIR"
echo "  Remote: $(cd "$VAULT_DIR" && git remote get-url origin 2>/dev/null || echo 'N/A')"
echo "  Sync:   every 5 min (only when changes exist)"
echo "  Log:    ~/.cc-md/sync.log"
echo ""
echo "  Commands:"
echo "    md status    — check sync state"
echo "    md sync      — sync now"
echo "    md doctor    — diagnose issues"
echo ""
echo "  iPhone: Install Obsidian → open the same iCloud vault. Done."
echo ""
