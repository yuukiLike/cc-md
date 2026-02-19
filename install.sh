#!/bin/bash
# =========================================================================
# cc-md 安装脚本
# =========================================================================
# 这个脚本做三件事：
#   1. 给你的 Obsidian vault（iCloud 里的笔记文件夹）加上 Git 版本控制
#   2. 把它连接到你的 GitHub 私有仓库，作为远程备份
#   3. 安装一个每 5 分钟自动同步的后台任务（有改动才同步，没改动不动）
#
# 前提条件：
#   - macOS 上已安装 Obsidian，并创建了 iCloud vault
#   - 已在 GitHub 上创建了私有仓库（如 cc-md-vault）
#   - macOS 上已配置好 Git 和 SSH key
#
# 它不会：
#   - 删除你的任何文件
#   - 修改系统级配置
#   - 安装任何第三方软件
# =========================================================================

# 遇到任何错误立即停止，不会静默继续执行
set -euo pipefail

# ---------- 路径变量 ----------
# 获取本脚本所在的目录（不管你从哪里运行它）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 自动同步脚本的路径（每 5 分钟执行一次的那个）
SYNC_SCRIPT="$SCRIPT_DIR/scripts/sync.sh"
# launchd 任务模板（macOS 的定时任务配置文件模板）
PLIST_TEMPLATE="$SCRIPT_DIR/config/com.cc-md.sync.plist"
# launchd 任务实际安装位置（系统会从这里读取定时任务）
PLIST_TARGET="$HOME/Library/LaunchAgents/com.cc-md.sync.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "========================================="
echo "  cc-md installer"
echo "========================================="
echo ""

# =========================================================================
# 第 1 步：找到你的 Obsidian vault
# =========================================================================
# 这是 Obsidian 在 iCloud 中存放 vault 的固定路径
# 如果你在 Obsidian 里创建了 iCloud vault，它就在这个目录下
ICLOUD_OBSIDIAN="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"

# 检查这个目录是否存在——不存在说明 Obsidian 还没创建 iCloud vault
if [ ! -d "$ICLOUD_OBSIDIAN" ]; then
    echo "ERROR: 未找到 iCloud Obsidian 目录。"
    echo "请先在 iOS 或 macOS 上打开 Obsidian 并启用 iCloud vault。"
    exit 1
fi

# 列出所有已有的 vault，让你选一个
echo "检测到 iCloud Obsidian 目录: $ICLOUD_OBSIDIAN"
echo ""
echo "可用的 vault:"
ls -1 "$ICLOUD_OBSIDIAN" 2>/dev/null || echo "(空)"
echo ""

# 你输入 vault 名称，比如 "notes"
read -r -p "请输入 vault 名称: " VAULT_NAME
VAULT_DIR="$ICLOUD_OBSIDIAN/$VAULT_NAME"

# 如果输入的 vault 不存在，问你要不要创建
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

# =========================================================================
# 第 2 步：在 vault 里初始化 Git 仓库
# =========================================================================
# 如果 vault 里还没有 .git 目录，说明还没初始化过
if [ ! -d "$VAULT_DIR/.git" ]; then
    echo ""
    echo "初始化 Git 仓库..."
    cd "$VAULT_DIR"
    # 创建一个新的 Git 仓库，主分支叫 main
    git init
    git checkout -b main

    # 创建 .gitignore 文件
    # 这些是 Obsidian 的本地配置，每台设备不同，不需要同步：
    #   workspace.json        — 当前打开的标签页、窗口布局
    #   workspace-mobile.json — 手机端的窗口布局
    #   appearance.json       — 主题、字体等外观设置
    #   .trash/               — Obsidian 的回收站
    #   .DS_Store             — macOS 的文件夹元数据
    cat > .gitignore << 'GITIGNORE'
# Obsidian 本地配置（不需要跨端同步）
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/appearance.json
.trash/
.DS_Store
GITIGNORE

    # 把当前所有文件加入 Git 并做第一次提交
    git add -A
    git commit -m "init: cc-md vault" --no-gpg-sign
    echo "Git 仓库初始化完成。"
else
    echo "Git 仓库已存在，跳过初始化。"
fi

# =========================================================================
# 第 3 步：连接 GitHub 远程仓库
# =========================================================================
cd "$VAULT_DIR"
# 检查是否已经设置过远程仓库
if ! git remote get-url origin &>/dev/null; then
    echo ""
    # 你输入 GitHub 仓库的 SSH 地址，比如 git@github.com:yourname/cc-md-vault.git
    read -r -p "请输入 GitHub 远程仓库 URL (例: git@github.com:user/vault.git): " REMOTE_URL
    # 把这个地址注册为 "origin"（Git 默认的远程仓库名）
    git remote add origin "$REMOTE_URL"
    echo "远程仓库已设置。"

    # 问你要不要现在就把第一次提交推上去
    echo "是否立即推送到远程? (y/n)"
    read -r DO_PUSH
    if [ "$DO_PUSH" = "y" ]; then
        # -u 表示以后 git push 默认推到这个远程分支
        git push -u origin main
        echo "推送完成。"
    fi
else
    echo "远程仓库已配置: $(git remote get-url origin)"
fi

# =========================================================================
# 第 4 步：保存配置
# =========================================================================
# 在 ~/.cc-md/ 目录下记录 vault 路径
# 这样同步脚本就知道去哪里找你的笔记
mkdir -p "$HOME/.cc-md"
echo "$VAULT_DIR" > "$HOME/.cc-md/vault-path"

# 设置环境变量，供后面的步骤使用
export CC_MD_VAULT_DIR="$VAULT_DIR"

# =========================================================================
# 第 5 步：安装定时自动同步任务
# =========================================================================
# macOS 用 launchd 管理后台任务（类似 Linux 的 cron）
# 我们注册一个任务：每 300 秒（5 分钟）执行一次 sync.sh
# sync.sh 的逻辑很简单：
#   - 检查有没有新改动 → 没有就跳过，什么都不做
#   - 有改动 → git add → git commit → git pull --rebase → git push
echo ""
echo "安装定时同步任务（每 5 分钟）..."

# 确保 LaunchAgents 目录存在
mkdir -p "$LAUNCH_AGENTS_DIR"

# 把模板中的占位符替换成实际路径，生成最终的 plist 文件
# __CC_MD_SYNC_SCRIPT__ → sync.sh 的实际路径
# __CC_MD_HOME__        → 你的 home 目录
sed -e "s|__CC_MD_SYNC_SCRIPT__|$SYNC_SCRIPT|g" \
    -e "s|__CC_MD_HOME__|$HOME|g" \
    "$PLIST_TEMPLATE" > "$PLIST_TARGET"

# 往 plist 文件里写入环境变量
# 这样 sync.sh 执行时能知道 vault 在哪里，以及能找到 git 命令
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$PLIST_TARGET" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:CC_MD_VAULT_DIR '$VAULT_DIR'" "$PLIST_TARGET" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CC_MD_VAULT_DIR string '$VAULT_DIR'" "$PLIST_TARGET"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:PATH string '/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin'" "$PLIST_TARGET" 2>/dev/null || true

# 先卸载旧任务（如果有的话），再加载新任务
launchctl unload "$PLIST_TARGET" 2>/dev/null || true
launchctl load "$PLIST_TARGET"

echo "定时任务已安装。"

# =========================================================================
# 完成
# =========================================================================
echo ""
echo "========================================="
echo "  安装完成"
echo "========================================="
echo ""
echo "  Vault 路径: $VAULT_DIR"
echo "  同步频率:   每 5 分钟（有改动才提交，没改动不动）"
echo "  同步日志:   ~/.cc-md/sync.log"
echo ""
echo "  后续步骤:"
echo "  1. macOS: 用 Obsidian 打开 iCloud 中的 vault"
echo "  2. iOS:   打开 Obsidian → 选择 iCloud vault"
echo "  3. Windows: git clone 仓库，用 Obsidian 打开"
echo ""
