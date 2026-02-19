# cc-md

Obsidian 笔记多端同步方案。零成本，零注册，零维护。

## 它是什么

一套脚本，让你的 Obsidian 笔记在 macOS、iOS、Windows 之间自动同步。

```
iPhone Obsidian ←─ iCloud ─→ macOS Obsidian ←─ Git ─→ GitHub ←─ Git ─→ Windows Obsidian
```

- **macOS ↔ iOS**：iCloud 自动同步（苹果系统原生能力，秒级）
- **macOS ↔ GitHub**：Git 定时同步（每 5 分钟检查，有改动才提交）
- **Windows ↔ GitHub**：Git 手动或插件同步

## 快速上手

```bash
# 1. 打开 Obsidian，创建 iCloud vault（名字如 notes）
# 2. 在 GitHub 上创建私有仓库（如 cc-md-vault）
# 3. 运行：
cd ~/legend/cc-md && bash install.sh
# 4. iPhone 装 Obsidian，打开同一个 iCloud vault
# 搞定。笔记自动同步到 GitHub，手机秒级同步。
```

## 前提条件

- macOS 上已安装 [Obsidian](https://obsidian.md)（免费，无需注册）
- macOS 上已配置好 Git 和 SSH key
- 已在 GitHub 上创建一个**私有**仓库（如 `cc-md-vault`）

## 安装

### 第 1 步：创建 iCloud vault

1. 打开 Obsidian
2. 选 **Create new vault**
3. 名字随意（如 `notes`）
4. 存储位置选 **iCloud**
5. 点 Create

### 第 2 步：运行安装脚本

```bash
cd ~/legend/cc-md && bash install.sh
```

脚本会依次问你三个问题：

| 提示 | 你输入什么 |
|------|-----------|
| 请输入 vault 名称 | 你刚创建的 vault 名字，如 `notes` |
| 请输入 GitHub 远程仓库 URL | `git@github.com:你的用户名/cc-md-vault.git` |
| 是否立即推送到远程 | `y` |

脚本做的事：
1. 在 vault 目录里初始化 Git 仓库
2. 创建 `.gitignore`（排除 Obsidian 本地配置）
3. 连接你的 GitHub 私有仓库
4. 安装 macOS 定时任务（每 5 分钟自动同步）

### 第 3 步：配置 iOS

1. iPhone 上安装 Obsidian
2. 打开 Obsidian，选择同一个 iCloud vault
3. 完成。不需要任何其他配置

### 第 4 步：配置 Windows（可选）

```bash
git clone git@github.com:你的用户名/cc-md-vault.git
```

用 Obsidian 打开 clone 下来的目录。推荐安装 [obsidian-git](https://github.com/denolehov/obsidian-git) 插件实现自动同步。

## 验证安装

装完后做三个测试：

**测试 1：Mac → iPhone**
在 Mac Obsidian 里新建笔记，写几个字。等 30 秒，打开 iPhone Obsidian，应该能看到。

**测试 2：iPhone → Mac**
在 iPhone Obsidian 里写几个字。等 30 秒，Mac 上应该能看到。

**测试 3：Git 同步**
等 5 分钟，或手动执行：

```bash
bash ~/legend/cc-md/scripts/sync.sh
```

然后去 GitHub 仓库页面，应该能看到新的 commit。

## 同步原理

### iCloud 同步（macOS ↔ iOS）

苹果系统自动处理，不需要任何代码。Obsidian vault 存在 iCloud Drive 目录中：

```
~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault名>/
```

文件变更后几秒到几十秒内同步完成。

### Git 同步（macOS ↔ GitHub）

install.sh 安装了一个 macOS launchd 定时任务，每 5 分钟执行 `scripts/sync.sh`：

1. 检查有没有新改动 → 没有就跳过
2. `git add -A` → 暂存所有改动
3. `git commit` → 提交（自动生成时间戳消息）
4. `git pull --rebase` → 拉取远程变更
5. `git push` → 推送到 GitHub

### 为什么 5 分钟

- 太快（30 秒）：写到一半就被 commit，Git 历史太碎
- 太慢（1 小时）：手机等太久才能看到，崩溃最多丢 1 小时内容
- 5 分钟：够写完一段想法，手机几分钟内可见

可以改。编辑 `~/Library/LaunchAgents/com.cc-md.sync.plist`，修改 `StartInterval` 的值（单位：秒）。

## 日志

同步日志在 `~/.cc-md/sync.log`，可以查看同步状态：

```bash
tail -20 ~/.cc-md/sync.log
```

## 安装产物

install.sh 会在系统中创建以下文件：

| 文件 | 位置 | 作用 |
|------|------|------|
| `.git/` | vault 目录下 | Git 仓库数据 |
| `.gitignore` | vault 目录下 | Git 忽略规则 |
| `vault-path` | `~/.cc-md/vault-path` | 记录 vault 路径 |
| `sync.log` | `~/.cc-md/sync.log` | 同步日志（运行后产生） |
| `launchd-stdout.log` | `~/.cc-md/launchd-stdout.log` | 定时任务标准输出 |
| `launchd-stderr.log` | `~/.cc-md/launchd-stderr.log` | 定时任务错误输出 |
| `com.cc-md.sync.plist` | `~/Library/LaunchAgents/` | 定时任务配置 |

还有一个隐性状态：`launchctl load` 注册了一个正在运行的后台任务，重启前会持续运行。

## 卸载

```bash
bash ~/legend/cc-md/uninstall.sh
```

或者手动执行：

```bash
# 1. 停止后台任务（不做的话任务会继续每 5 分钟执行，直到重启）
launchctl unload ~/Library/LaunchAgents/com.cc-md.sync.plist

# 2. 删除定时任务配置（不做的话重启后任务会重新加载）
rm ~/Library/LaunchAgents/com.cc-md.sync.plist

# 3. 删除配置和日志
rm -rf ~/.cc-md

# 4.（可选）移除 vault 里的 Git
#    如果你想彻底断开 Git，取消注释下面两行：
#    rm -rf <vault路径>/.git
#    rm <vault路径>/.gitignore
```

卸载后你的笔记不受影响。Obsidian vault 和 iCloud 同步依然正常工作，只是不再自动推送到 GitHub。

## 成本

**零。** Obsidian 个人免费，Git 免费，GitHub 私有仓库免费，iCloud 5GB 免费额度对纯文本绰绰有余。

## 常用命令

```bash
# 手动触发一次同步（不想等 5 分钟）
bash ~/legend/cc-md/scripts/sync.sh

# 查看最近同步日志
tail -20 ~/.cc-md/sync.log

# 检查定时任务是否在运行
launchctl list | grep cc-md

# 修改同步频率（改 StartInterval 的值，单位：秒）
open ~/Library/LaunchAgents/com.cc-md.sync.plist
```

## 项目结构

```
cc-md/
├── install.sh                          # 安装脚本（注释详尽，可逐行阅读）
├── uninstall.sh                        # 卸载脚本（干净移除所有安装产物）
├── scripts/
│   └── sync.sh                         # 自动同步脚本（launchd 每 5 分钟调用）
├── config/
│   └── com.cc-md.sync.plist            # launchd 任务模板
├── doc/
│   ├── storage-solution.md             # 方案选型分析
│   ├── git-ssh-guide.md                # Git Config 与 SSH Config 指南
│   ├── shell-notes.md                  # Shell 学习笔记
│   └── todo.md                         # 待办
└── README.md                           # ← 你在这里
```
