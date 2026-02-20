#!/bin/bash
# cc-md sync script
# 将 iCloud 中 Obsidian vault 的变更自动同步到 Git 远程仓库
#
# vault 查找策略（按优先级）：
#   1. 环境变量 CC_MD_VAULT_DIR（install.sh 设置的）
#   2. ~/.cc-md/vault-path 文件里记录的路径
#   3. 自动扫描 iCloud Obsidian 目录，找到第一个有 .git 的 vault
# 这意味着即使你重命名了 vault，第 3 步也能自动找到它。

set -euo pipefail

LOG_FILE="${CC_MD_LOG_FILE:-$HOME/.cc-md/sync.log}"
ICLOUD_OBSIDIAN="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ---------- 查找 vault ----------

find_vault() {
    # 策略 1：环境变量
    if [ -n "${CC_MD_VAULT_DIR:-}" ] && [ -d "${CC_MD_VAULT_DIR}/.git" ]; then
        echo "$CC_MD_VAULT_DIR"
        return
    fi

    # 策略 2：配置文件
    if [ -f "$HOME/.cc-md/vault-path" ]; then
        local saved
        saved="$(cat "$HOME/.cc-md/vault-path")"
        if [ -d "$saved/.git" ]; then
            echo "$saved"
            return
        fi
    fi

    # 策略 3：自动扫描 iCloud 目录，找有 .git 的 vault
    if [ -d "$ICLOUD_OBSIDIAN" ]; then
        for dir in "$ICLOUD_OBSIDIAN"/*/; do
            if [ -d "$dir/.git" ]; then
                # 找到了，顺便更新配置文件，下次直接命中策略 2
                echo "$dir" > "$HOME/.cc-md/vault-path"
                echo "${dir%/}"
                return
            fi
        done
    fi

    return 1
}

VAULT_DIR="$(find_vault)" || {
    log "ERROR: 找不到任何有 .git 的 Obsidian vault"
    exit 1
}

# 检查是否是 Git 仓库（双重保险）
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
