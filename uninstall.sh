#!/bin/bash
# =========================================================================
# cc-md 卸载脚本
# =========================================================================
# 这个脚本做三件事：
#   1. 停止并移除定时同步任务
#   2. 删除配置和日志文件
#   3. 可选：移除 vault 里的 Git
#
# 它不会：
#   - 删除你的笔记（vault 里的 .md 文件不受影响）
#   - 影响 iCloud 同步（苹果系统自己管的，跟这个脚本无关）
#   - 删除 GitHub 上的远程仓库（需要你手动去 GitHub 删）
# =========================================================================

set -uo pipefail

PLIST_TARGET="$HOME/Library/LaunchAgents/com.cc-md.sync.plist"
CONFIG_DIR="$HOME/.cc-md"
VAULT_PATH_FILE="$CONFIG_DIR/vault-path"

# 在删除配置之前，先把 vault 路径读出来，后面第 3 步要用
SAVED_VAULT_DIR=""
if [ -f "$VAULT_PATH_FILE" ]; then
    SAVED_VAULT_DIR="$(cat "$VAULT_PATH_FILE")"
fi

echo "========================================="
echo "  cc-md uninstaller"
echo "========================================="
echo ""

# =========================================================================
# 第 1 步：停止并移除定时任务
# =========================================================================
# 必须先 unload 再删文件
# 如果只删文件不 unload，任务会继续运行直到重启
if [ -f "$PLIST_TARGET" ]; then
    echo "停止定时同步任务..."
    launchctl unload "$PLIST_TARGET" 2>/dev/null || true
    rm "$PLIST_TARGET"
    echo "已停止并移除定时任务。"
else
    echo "定时任务不存在，跳过。"
fi

# =========================================================================
# 第 2 步：删除配置和日志
# =========================================================================
# ~/.cc-md/ 目录下有：vault-path、sync.log、launchd 日志
if [ -d "$CONFIG_DIR" ]; then
    echo ""
    echo "删除配置和日志 ($CONFIG_DIR)..."
    rm -rf "$CONFIG_DIR"
    echo "已删除。"
else
    echo "配置目录不存在，跳过。"
fi

# =========================================================================
# 第 3 步：可选 - 移除 vault 里的 Git
# =========================================================================
# 读取之前保存的 vault 路径
# 注意：如果第 2 步已经删了 ~/.cc-md，这里就读不到了
# 所以我们在第 2 步之前先读出来
echo ""
echo "是否移除 vault 中的 Git 仓库？"
echo "  输入 y：删除 .git 和 .gitignore，vault 彻底脱离 Git"
echo "  输入 n：保留 Git 历史，以后还能恢复"
read -r -p "你的选择 (y/n): " REMOVE_GIT

if [ "$REMOVE_GIT" = "y" ]; then
    if [ -n "$SAVED_VAULT_DIR" ]; then
        echo "检测到 vault 路径：$SAVED_VAULT_DIR"
        read -r -p "使用这个路径？(y/n): " USE_SAVED
        if [ "$USE_SAVED" = "y" ]; then
            VAULT_DIR="$SAVED_VAULT_DIR"
        else
            read -r -p "请输入 vault 路径: " VAULT_DIR
            VAULT_DIR="${VAULT_DIR/#\~/$HOME}"
        fi
    else
        read -r -p "请输入 vault 路径: " VAULT_DIR
        VAULT_DIR="${VAULT_DIR/#\~/$HOME}"
    fi

    if [ -d "$VAULT_DIR/.git" ]; then
        rm -rf "$VAULT_DIR/.git"
        echo "已删除 $VAULT_DIR/.git"
    else
        echo "$VAULT_DIR/.git 不存在，跳过。"
    fi

    if [ -f "$VAULT_DIR/.gitignore" ]; then
        rm "$VAULT_DIR/.gitignore"
        echo "已删除 $VAULT_DIR/.gitignore"
    else
        echo "$VAULT_DIR/.gitignore 不存在，跳过。"
    fi
fi

echo ""
echo "========================================="
echo "  卸载完成"
echo "========================================="
echo ""
echo "  你的笔记没有被删除。"
echo "  iCloud 同步不受影响。"
echo "  GitHub 远程仓库需要手动删除（如果需要的话）。"
echo ""
