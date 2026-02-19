# Shell 学习笔记

> 在读 cc-md install.sh 时学到的

---

## 特殊变量

| 变量 | 含义 |
|------|------|
| `$0` | 当前脚本自身的路径，只在脚本中有效，终端里是 shell 名字（如 `-zsh`） |
| `$HOME` | 当前用户的 home 目录，如 `/Users/chp` |

---

## dirname

砍掉路径最后一段，返回父目录。纯字符串操作，不关心是文件还是目录。

```bash
dirname /Users/chp/legend/cc-md/install.sh  →  /Users/chp/legend/cc-md
dirname /Users/chp/legend/cc-md             →  /Users/chp/legend
dirname /Users/chp/legend                   →  /Users/chp
```

---

## $() 命令替换

先执行括号里的命令，把输出作为外层命令的参数。

```bash
# dirname 的输出变成 cd 的参数
cd "$(dirname /Users/chp/legend/cc-md/install.sh)"

# 等价于
cd "/Users/chp/legend/cc-md"
```

注意：`$()` 不是 `()`。少了 `$` shell 不知道要执行里面的命令。

---

## 连接符

| 符号 | 含义 | 例子 |
|------|------|------|
| `&&` | 前一个成功才执行后一个 | `mkdir foo && cd foo` |
| `&` | 前一个丢到后台，立刻执行后一个 | `sleep 10 & echo "hi"` |
| `||` | 前一个失败才执行后一个 | `cd foo || echo "目录不存在"` |
| `;` | 无论成败，依次执行 | `cd foo; echo "hi"` |

`&` 和 `&&` 完全不同：
- `cd foo & pwd` — cd 被丢到后台，pwd 打印的是**原来**的目录
- `cd foo && pwd` — cd 成功后才 pwd，打印的是**新**目录

---

## set -euo pipefail

install.sh 开头的安全设置：

| 标志 | 含义 |
|------|------|
| `-e` | 任何命令失败立即停止脚本 |
| `-u` | 使用未定义的变量时报错（而不是当空字符串处理） |
| `-o pipefail` | 管道中任何一步失败，整个管道算失败 |

没有这行的话，脚本遇到错误会默默继续执行，可能造成意想不到的后果。
