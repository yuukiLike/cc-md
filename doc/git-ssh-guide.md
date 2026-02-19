# Git Config 与 SSH Config 完全指南

## 一句话理解

**Git config 管"你是谁"，SSH config 管"你怎么证明你是谁"。**

它们是两套完全独立的系统，分别在不同的阶段工作。

## 全局流程图

```
你输入 git commit
       │
       ▼
┌──────────────┐     ┌─────────────────┐
│  Git Config  │────▶│ 读取 user.name  │
│ ~/.gitconfig │     │ 读取 user.email │
└──────────────┘     └────────┬────────┘
                              │
       仓库在 ~/work/ 下？     │
       ├── 是 → 加载 ~/.gitconfig-company → 覆盖为公司身份
       └── 否 → 使用默认的个人身份
                              │
                              ▼
                    提交记录写入本地仓库
                    Author: zhangsan <zhangsan@gmail.com>


─────────────────────────────────────────────────────────


你输入 git push
       │
       ▼
┌──────────────┐     ┌──────────────────────┐
│  SSH Config  │────▶│ 解析 remote URL 域名 │
│ ~/.ssh/config│     └──────────┬───────────┘
└──────────────┘               │
                               │
       域名是什么？             │
       ├── github.com         → 用 ~/.ssh/id_ed25519
       └── gitlab.company.com → 用 ~/.ssh/id_rsa
                               │
                               ▼
                    SSH 握手 → 服务器验证密钥 → 传输数据
```

## 两套系统的本质区别

```
┌─────────────────────────────────────────────────────────┐
│                     git commit                          │
│                                                         │
│   "这次提交是谁写的？"                                    │
│                                                         │
│   ┌─────────────┐    按目录     ┌──────────────────┐    │
│   │ ~/.gitconfig │───区分身份──▶│ name + email     │    │
│   └─────────────┘              │ 写入提交记录       │    │
│                                └──────────────────┘    │
├─────────────────────────────────────────────────────────┤
│                   git push / pull                       │
│                                                         │
│   "用什么凭证连接服务器？"                                 │
│                                                         │
│   ┌──────────────┐   按域名     ┌──────────────────┐    │
│   │ ~/.ssh/config │──区分密钥──▶│ 私钥文件          │    │
│   └──────────────┘             │ 发送给服务器验证    │    │
│                                └──────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## Part 1：Git Config

### 它解决什么问题

每次 `git commit`，Git 在提交记录里写入两个字段：

```
commit 3a7f2b1
Author: zhangsan <zhangsan@gmail.com>    ← 从 git config 读取
Date:   Wed Feb 19 21:00:00 2026
```

如果你有多个身份（个人 + 公司），需要根据项目自动切换。

### 配置文件结构

```
~/.gitconfig              ← 主配置（默认身份 + 通用设置）
~/.gitconfig-company      ← 公司配置（仅覆盖 user）
```

### 加载机制

```
加载 ~/.gitconfig
│
├── [user]        name = zhangsan           ← 先设置默认值
├── [alias]       st = status               ← 通用配置
├── [credential]  helper = osxkeychain      ← 通用配置
│
├── [includeIf "gitdir:~/work/"]
│   │
│   └── 当前仓库在 ~/work/ 下？
│       ├── 是 → 加载 ~/.gitconfig-company
│       │        [user] name = san.zhang     ← 覆盖默认值
│       │        [user] email = san.zhang@.. ← 覆盖默认值
│       │        （其他配置继承主配置，不用重复写）
│       │
│       └── 否 → 跳过，使用默认值
│
└── 最终结果：所有配置合并完毕
```

### Demo：~/.gitconfig

```ini
# 全局忽略规则，所有仓库共享
[core]
    excludesfile = ~/.gitignore_global

# 快捷命令
[alias]
    st = status       # git st  → git status
    cm = commit       # git cm  → git commit
    co = checkout     # git co  → git checkout

# 默认身份（个人）
[user]
    name = zhangsan
    email = zhangsan@gmail.com

# HTTPS 密码存储（用 SSH 的话这行不生效，但留着无害）
[credential]
    helper = osxkeychain

# ~/work/ 下自动切换为公司身份
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-company

# 信任所有目录（单人电脑可以开）
[safe]
    directory = *
```

### Demo：~/.gitconfig-company

```ini
# 只写需要覆盖的部分，其他继承主配置
[user]
    name = san.zhang
    email = san.zhang@some-company.com
```

### 验证

```bash
# 在个人项目里检查
cd ~/projects/my-app && git config user.name
# → zhangsan

# 在公司项目里检查
cd ~/work/internal-tool && git config user.name
# → san.zhang
```

## Part 2：SSH Config

### 它解决什么问题

`git push` 需要连接远程服务器。服务器要验证你的身份——不是看你叫什么名字，而是看你有没有正确的密钥。

如果你连接多个服务器（GitHub + 公司 GitLab），每个服务器用不同的密钥，SSH config 告诉系统：连哪个域名，用哪把钥匙。

### 配置文件结构

```
~/.ssh/
├── config                 ← SSH 配置文件（路由规则）
├── id_ed25519             ← 个人私钥
├── id_ed25519.pub         ← 个人公钥（贴到 GitHub Settings 里）
├── id_rsa                 ← 公司私钥
├── id_rsa.pub             ← 公司公钥（贴到 GitLab Settings 里）
└── known_hosts            ← 连接过的服务器指纹（防中间人攻击）
```

### 匹配机制

```
git push git@github.com:zhangsan/repo.git
              │
              ▼
SSH 解析域名：github.com
              │
              ▼
遍历 ~/.ssh/config，找到匹配的 Host：
              │
              ├── Host gitlab.some-company.com  ← 不匹配，跳过
              │
              └── Host github.com               ← 匹配！
                  IdentityFile ~/.ssh/id_ed25519 ← 用这把钥匙
                  Port 443                       ← 连这个端口
              │
              ▼
用 id_ed25519 私钥向 github.com 证明身份 → 验证通过 → 传输数据
```

### Demo：~/.ssh/config

```
# 公司 GitLab
Host gitlab.some-company.com
    HostName gitlab.some-company.com   # 实际服务器地址
    Port 22                            # 端口（默认 22）
    User git                           # Git 服务器固定是 git
    IdentityFile ~/.ssh/id_rsa         # 用 RSA 密钥
    IdentitiesOnly yes                 # 只用这把，别猜

# 个人 GitHub
Host github.com
    HostName github.com                # 实际服务器地址
    Port 443                           # GitHub 也支持 443 端口
    User git                           # Git 服务器固定是 git
    IdentityFile ~/.ssh/id_ed25519     # 用 Ed25519 密钥
    IdentitiesOnly yes                 # 只用这把，别猜
```

### 各字段含义

| 字段 | 作用 | 备注 |
|------|------|------|
| `Host` | 匹配规则 | 你输入的域名匹配到这里，就用下面的配置 |
| `HostName` | 实际连接地址 | 通常和 Host 一样，但可以不同（比如跳板机） |
| `Port` | 端口号 | 默认 22，有些公司改了端口 |
| `User` | 登录用户名 | Git 服务器永远是 `git`，不是你的用户名 |
| `IdentityFile` | 私钥路径 | 这把钥匙的公钥需要提前贴到服务器上 |
| `IdentitiesOnly` | 只用指定密钥 | 设为 yes 防止 SSH 尝试其他钥匙导致认证失败 |

### 验证

```bash
# 测试个人 GitHub 连接
ssh -T git@github.com
# → Hi zhangsan! You've successfully authenticated...

# 测试公司 GitLab 连接
ssh -T git@gitlab.some-company.com
# → Welcome to GitLab, @san.zhang!
```

## 总结

```
┌────────────┬──────────────────┬──────────────────┐
│            │   Git Config     │   SSH Config     │
├────────────┼──────────────────┼──────────────────┤
│ 文件       │ ~/.gitconfig     │ ~/.ssh/config    │
│ 区分方式   │ 按目录           │ 按域名           │
│ 决定什么   │ 提交者身份       │ 认证密钥         │
│ 生效时机   │ git commit       │ git push / pull  │
│ 核心问题   │ "你是谁"         │ "你怎么证明"     │
└────────────┴──────────────────┴──────────────────┘
```

两套系统各司其职，互不干扰。配置一次，永久生效。
