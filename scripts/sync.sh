#!/bin/bash
# cc-md sync script
# 将 iCloud 中 Obsidian vault 的变更自动同步到 Git 远程仓库

set -euo pipefail

# ========== 配置 ==========
# Obsidian vault 路径（iCloud 中）
VAULT_DIR="${CC_MD_VAULT_DIR:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/vault}"
LOG_FILE="${CC_MD_LOG_FILE:-$HOME/.cc-md/sync.log}"
# ==========================

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查 vault 目录是否存在
if [ ! -d "$VAULT_DIR" ]; then
    log "ERROR: Vault directory not found: $VAULT_DIR"
    exit 1
fi

# 检查是否是 Git 仓库
if [ ! -d "$VAULT_DIR/.git" ]; then
    log "ERROR: Not a git repo: $VAULT_DIR"
    exit 1
fi

cd "$VAULT_DIR"

# 检查是否有变更
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log "No changes detected, skip."
    exit 0
fi

log "Changes detected, syncing..."

# 添加所有变更
git add -A

# 提交
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
git commit -m "auto-sync: $TIMESTAMP" --no-gpg-sign 2>> "$LOG_FILE" || {
    log "Nothing to commit after staging."
    exit 0
}

# 拉取远程变更并 rebase
git pull --rebase origin main 2>> "$LOG_FILE" || {
    log "ERROR: pull --rebase failed. May need manual conflict resolution."
    exit 1
}

# 推送
git push origin main 2>> "$LOG_FILE" || {
    log "ERROR: push failed."
    exit 1
}

log "Sync completed successfully."
