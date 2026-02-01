# cc-md 存储方案

## 最终选型

**Obsidian（编辑器） + Git（跨平台同步） + iCloud（Apple 生态内同步）**

## 架构

```
macOS ←── Git ──→ GitHub ←── Git ──→ Windows
  ↕
iCloud (自动)
  ↕
 iOS
```

## 各端职责

| 设备 | Obsidian | 同步方式 | 说明 |
|------|----------|----------|------|
| macOS | 本地客户端 | iCloud + Git | 中枢节点，负责将 iCloud 变更同步到 Git |
| iOS | 本地客户端 | iCloud | 零配置，Obsidian 原生支持 iCloud vault |
| Windows | 本地客户端 | Git | 直接 clone 仓库作为 vault |

## 为什么不用其他方案

### iCloud 全平台

- Windows 上 iCloud 同步体验差：慢、冲突多、偶尔丢文件
- 没有版本历史，误删无法恢复

### Obsidian Sync

- 每月 ~$4，10 年约 $480
- 功能上 Git 可以完全替代，且 Git 有更完整的版本历史

### 纯 Git 全平台

- iOS 上 Git 体验极差，没有好用的免费方案
- Working Copy 付费 ~$20 且需要手动切 app 操作

### 自建服务

- 10 年运维成本高（服务器、SSL、升级）
- 一旦停止维护，数据访问中断
- 纯本地文件方案运维成本为零

## 混合方案的工作原理

1. **Obsidian vault 存放在 iCloud Drive 中**
   - macOS 路径: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault-name>`
   - iOS 自动同步，打开 Obsidian 即可使用

2. **macOS 上对 vault 初始化 Git 仓库**
   - vault 目录本身就是 Git repo
   - `.obsidian` 目录中与同步无关的本地配置加入 `.gitignore`

3. **定时自动同步脚本（macOS）**
   - launchd 定时任务，每 5 分钟执行一次
   - 自动 `git add` → `git commit` → `git pull --rebase` → `git push`
   - iOS 上的编辑通过 iCloud 到达 macOS，再由脚本推到 Git

4. **Windows 端直接使用 Git 仓库**
   - `git clone` 到本地，用 Obsidian 打开该目录
   - 使用 obsidian-git 插件自动同步，或手动 pull/push

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| iCloud 同步 .git 目录导致损坏 | 概率低；Git 有自修复能力；远程仓库是完整备份 |
| macOS 关机时 iOS 编辑无法推到 Git | iOS 编辑先存 iCloud，macOS 开机后自动同步 |
| Git 冲突（macOS 和 Windows 同时编辑） | 脚本使用 `pull --rebase`；markdown 纯文本冲突易解决 |
| GitHub 服务中断 | 本地 + iCloud 双备份，不影响日常使用 |

## 成本

**零**。Obsidian 个人免费，Git 免费，GitHub 私有仓库免费，iCloud 5GB 免费额度足够纯文本。
