# cc-md

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-yellow)
![Obsidian](https://img.shields.io/badge/Obsidian-vault%20sync-7C3AED)
![iCloud](https://img.shields.io/badge/iCloud-supported-lightblue)

**中文** | [English](README.md)

本地优先的 Obsidian 多端同步方案。零成本，零注册，零维护。

## 为什么做这个

Obsidian vault 就是一个文件夹，里面全是 `.md` 文件。这意味着 Claude Code 等 AI 工具可以**直接读写你的知识库**：

`零 API` &ensp; `零插件` &ensp; `零中间层`

```bash
# Claude Code 天然能做这些事
Grep "系统设计" ~/vault/         # 搜索所有笔记
Read ~/vault/某篇笔记.md        # 读取内容
Edit ~/vault/某篇笔记.md        # 修改、补充
Glob "**/*.md" ~/vault/         # 遍历整个知识库
```

对比 Notion 等云端方案：

|  | Obsidian vault | Notion |
|--|---------------|--------|
| AI 接入 | 直接读文件，零配置 | 需要 API + OAuth + MCP |
| 数据格式 | 标准 markdown | 私有 block 结构，需解析 |
| 读写速度 | 本地 I/O，毫秒级 | 网络请求 + rate limit |
| 版本历史 | Git log 完整记录每次变更 | 无 |
| 数据所有权 | 文件在你的硬盘上 | 存在别人的服务器上 |

**本地文件 + 标准格式 = 不需要"接入"，天然就在一起。**

cc-md 做的事很简单：让这个本地知识库在你的所有设备间保持同步。

## 架构

```
iPhone Obsidian ←─ iCloud ─→ macOS Obsidian ←─ Git ─→ GitHub ←─ Git ─→ Windows Obsidian
```

- **macOS ↔ iOS**：iCloud 自动同步（秒级）
- **macOS ↔ GitHub**：Git 定时同步（每 5 分钟，有改动才提交）
- **Windows ↔ GitHub**：Git 手动或插件同步

## 快速上手

```bash
# 1. 打开 Obsidian，创建 iCloud vault（名字如 notes）
# 2. 在 GitHub 上创建私有仓库（如 cc-md-vault）
# 3. 运行：
git clone git@github.com:用户名/cc-md.git && cd cc-md && bash scripts/install.sh
# 4. iPhone 装 Obsidian，打开同一个 iCloud vault
# 搞定。
```

## 前提条件

- macOS + [Obsidian](https://obsidian.md)（免费）
- Git + SSH key 已配置
- GitHub 上有一个**私有**仓库

## 安装

### 第 1 步：创建 iCloud vault

打开 Obsidian → Create new vault → 存储位置选 iCloud → Create

### 第 2 步：运行安装脚本

```bash
cd cc-md && bash scripts/install.sh
```

脚本会问三个问题：

| 提示 | 输入 |
|------|------|
| vault 名称 | 你的 vault 名字，如 `notes` |
| GitHub 远程仓库 URL | `git@github.com:用户名/仓库.git` |
| 是否立即推送 | `y` |

### 第 3 步：配置 iOS

iPhone 装 Obsidian → 打开同一个 iCloud vault → 完成。

### 第 4 步：配置 Windows（可选）

```bash
git clone git@github.com:用户名/仓库.git
```

用 Obsidian 打开 clone 下来的目录。推荐装 [obsidian-git](https://github.com/denolehov/obsidian-git) 插件自动同步。

## 验证

**Mac → iPhone**：Mac 上新建笔记，30 秒后 iPhone 应该能看到。

**iPhone → Mac**：iPhone 上写几个字，30 秒后 Mac 应该能看到。

**Git 同步**：等 5 分钟或手动执行 `bash scripts/sync.sh`，GitHub 上应该能看到新 commit。

## 同步原理

**iCloud**（macOS ↔ iOS）：苹果系统自动处理，vault 存在 `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault名>/`，秒级同步。

**Git**（macOS ↔ GitHub）：launchd 定时任务每 5 分钟执行 sync.sh：检查改动 → `git add` → `git commit` → `git pull --rebase` → `git push`。没改动就跳过。

**为什么 5 分钟**：30 秒太碎，1 小时太慢，5 分钟刚好写完一段想法。可改 `~/Library/LaunchAgents/com.cc-md.sync.plist` 中的 `StartInterval`。

## 方案选型

| 替代方案 | 不选的原因 |
|----------|-----------|
| iCloud 全平台 | Windows 同步差，无版本历史 |
| Obsidian Sync | ~$4/月，10 年 ≈ $480 |
| 纯 Git 全平台 | iOS 无好用的免费 Git 方案 |
| Notion | 私有格式，数据不在本地，AI 接入需要 API |
| 自建服务 | 运维成本高，停维即断 |

本方案：iCloud 管 Apple 生态同步，Git 管跨平台 + 版本历史。成本为零。

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| iCloud 同步 .git 导致损坏 | 概率低；远程仓库是完整备份 |
| macOS 关机时 iOS 编辑无法推到 Git | 开机后自动补推 |
| Git 冲突 | `pull --rebase` + 纯文本易解决 |
| GitHub 中断 | 本地 + iCloud 双备份 |

## 常用命令

```bash
bash scripts/sync.sh                        # 手动同步
tail -20 ~/.cc-md/sync.log                  # 查看日志
launchctl list | grep cc-md                 # 检查定时任务（有输出 = 运行中，空 = 未运行）
```

**改了 vault 名字？** 不需要任何操作。sync.sh 会自动扫描 iCloud 目录，找到有 `.git` 的 vault。

**任务没在运行？** 重新加载：

```bash
launchctl load ~/Library/LaunchAgents/com.cc-md.sync.plist
```

## 卸载

```bash
bash scripts/uninstall.sh
```

笔记不受影响，iCloud 同步照常，只是不再自动推 GitHub。

## 项目结构

```
cc-md/
├── scripts/
│   ├── install.sh          # 安装
│   ├── uninstall.sh        # 卸载
│   └── sync.sh             # 自动同步（每 5 分钟）
├── com.cc-md.sync.plist    # launchd 任务模板
├── LICENSE
├── README.md               # English
└── README.zh.md            # 中文
```
