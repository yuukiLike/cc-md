#!/bin/bash
# cc-md 安装脚本
# 功能：初始化 Obsidian vault 的 Git 仓库，安装定时同步任务

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/scripts/sync.sh"
PLIST_TEMPLATE="$SCRIPT_DIR/config/com.cc-md.sync.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.cc-md.sync.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "========================================="
echo "  cc-md installer"
echo "========================================="
echo ""

# 1. 获取 vault 路径
ICLOUD_OBSIDIAN="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"

if [ ! -d "$ICLOUD_OBSIDIAN" ]; then
    echo "ERROR: 未找到 iCloud Obsidian 目录。"
    echo "请先在 iOS 或 macOS 上打开 Obsidian 并启用 iCloud vault。"
    exit 1
fi

echo "检测到 iCloud Obsidian 目录: $ICLOUD_OBSIDIAN"
echo ""
echo "可用的 vault:"
ls -1 "$ICLOUD_OBSIDIAN" 2>/dev/null || echo "(空)"
echo ""

read -r -p "请输入 vault 名称: " VAULT_NAME
VAULT_DIR="$ICLOUD_OBSIDIAN/$VAULT_NAME"

if [ ! -d "$VAULT_DIR" ]; then
    echo "Vault 不存在，是否创建? (y/n)"
    read -r CREATE_VAULT
    if [ "$CREATE_VAULT" = "y" ]; then
        mkdir -p "$VAULT_DIR"
        echo "已创建: $VAULT_DIR"
    else
        echo "取消安装。"
        exit 1
    fi
fi

# 2. 初始化 Git
if [ ! -d "$VAULT_DIR/.git" ]; then
    echo ""
    echo "初始化 Git 仓库..."
    cd "$VAULT_DIR"
    git init
    git checkout -b main

    # 创建 .gitignore
    cat > .gitignore << 'GITIGNORE'
# Obsidian 本地配置（不需要跨端同步）
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/appearance.json
.trash/
.DS_Store
GITIGNORE

    git add -A
    git commit -m "init: cc-md vault" --no-gpg-sign
    echo "Git 仓库初始化完成。"
else
    echo "Git 仓库已存在，跳过初始化。"
fi

# 3. 设置远程仓库
cd "$VAULT_DIR"
if ! git remote get-url origin &>/dev/null; then
    echo ""
    read -r -p "请输入 GitHub 远程仓库 URL (例: git@github.com:user/vault.git): " REMOTE_URL
    git remote add origin "$REMOTE_URL"
    echo "远程仓库已设置。"

    echo "是否立即推送到远程? (y/n)"
    read -r DO_PUSH
    if [ "$DO_PUSH" = "y" ]; then
        git push -u origin main
        echo "推送完成。"
    fi
else
    echo "远程仓库已配置: $(git remote get-url origin)"
fi

# 4. 保存 vault 路径配置
mkdir -p "$HOME/.cc-md"
echo "$VAULT_DIR" > "$HOME/.cc-md/vault-path"

# 5. 设置环境变量到 sync 脚本
export CC_MD_VAULT_DIR="$VAULT_DIR"

# 6. 安装 launchd 定时任务
echo ""
echo "安装定时同步任务（每 5 分钟）..."

mkdir -p "$LAUNCH_AGENTS_DIR"

# 用实际路径替换模板中的占位符
sed -e "s|__CC_MD_SYNC_SCRIPT__|$SYNC_SCRIPT|g" \
    -e "s|__CC_MD_HOME__|$HOME|g" \
    "$PLIST_TEMPLATE" > "$PLIST_TARGET"

# 写入环境变量到 plist
# 在 ProgramArguments 之前插入环境变量配置
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$PLIST_TARGET" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:CC_MD_VAULT_DIR '$VAULT_DIR'" "$PLIST_TARGET" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CC_MD_VAULT_DIR string '$VAULT_DIR'" "$PLIST_TARGET"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:PATH string '/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin'" "$PLIST_TARGET" 2>/dev/null || true

# 加载任务
launchctl unload "$PLIST_TARGET" 2>/dev/null || true
launchctl load "$PLIST_TARGET"

echo "定时任务已安装。"

echo ""
echo "========================================="
echo "  安装完成"
echo "========================================="
echo ""
echo "  Vault 路径: $VAULT_DIR"
echo "  同步频率:   每 5 分钟"
echo "  同步日志:   ~/.cc-md/sync.log"
echo ""
echo "  后续步骤:"
echo "  1. macOS: 用 Obsidian 打开 iCloud 中的 vault"
echo "  2. iOS:   打开 Obsidian → 选择 iCloud vault"
echo "  3. Windows: git clone 仓库，用 Obsidian 打开"
echo ""
