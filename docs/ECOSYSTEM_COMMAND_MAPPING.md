# MoonBit 生态命令实现映射（just-bash -> MoonBash）

这份文档用于沉淀 MoonBash 的工程实现策略：优先复用 MoonBit 官方与社区能力，避免重复造轮子，集中手写真正不可替代的核心模块。

## 目标

- 对 `just-bash` 的约 85 个内置 Unix 命令进行实现分层。
- 明确哪些命令可“直接调包”，哪些仅需标准库拼装，哪些必须走 FFI。
- 将手写核心严格收敛到解析器与最小语言执行器。

## 第一阵营：算法库直接接管（0 手写核心）

| 命令 | 推荐能力 | 实现要点 |
|---|---|---|
| `grep`, `egrep`, `fgrep`, `rg` | `@moonbitlang/core/regexp` | 使用编译后正则对象执行搜索；复用 VM 级正则能力。 |
| `sed`（核心替换子集） | `@moonbitlang/core/regexp` + `@moonbitlang/core/string` | `s/old/new/g` 对应正则替换与字符串拼接。 |
| `jq` | `@moonbitlang/core/json` | 解析为 JSON AST 后使用模式匹配提取。 |
| `base64` | `@moonbitlang/x/codec/base64`（或社区包） | 直接复用字节编码/解码。 |
| `md5sum` | 社区 `md5` 包 | 字节输入 -> 摘要字符串。 |
| `sha1sum`, `sha256sum` | 社区 SHA 包 | 统一哈希接口抽象。 |
| `gzip`, `gunzip`, `zcat` | 社区 gzip/flate 包 | 复用压缩流处理。 |
| `date`, `time` | `@moonbitlang/x/time` | 统一时间格式化与时区处理。 |

## 第二阵营：标准库一行式拼装

| 命令 | 核心库 | 最小实现思路 |
|---|---|---|
| `sort` | `core/array` | `sort`/`sort_by`（数字与逆序走自定义比较器）。 |
| `uniq` | `core/hashset` | 行去重或“先排序后相邻去重”。 |
| `head`, `tail` | `core/array` | 按行切片。 |
| `wc` | `core/string` | 统计行/词/字符。 |
| `cat`, `tac`, `rev` | `core/array` + `core/string` | 拼接、反转、字符级逆序。 |
| `cut`, `split` | `core/string` | 分隔符切分后抽取字段。 |
| `tr`, `expand`, `unexpand` | `core/string` | 字符映射与替换。 |
| `basename`, `dirname` | `core/string` | 路径字符串切片。 |
| `expr`, `seq` | `core/math` | 算术表达式与迭代序列。 |
| `join`, `comm`, `paste`, `nl`, `fold`, `column`, `strings` | `core/iter` | 用迭代器做双流对齐、编号、折行。 |

## 第三阵营：数据结构驱动状态管理（免底层算法）

| 模块 | 命令 | 数据结构与策略 |
|---|---|---|
| 环境上下文 | `env`, `printenv`, `export`, `alias`, `unalias`, `history` | `HashMap` 维护会话状态。 |
| 虚拟文件系统 | `ls`, `cd`, `pwd`, `mkdir`, `touch`, `rm`, `rmdir`, `cp`, `mv`, `tree`, `find`, `stat`, `du`, `chmod` | `VFSNode = File | Dir(Map)`，递归增删改查。 |
| 固定行为命令 | `true`, `false`, `echo`, `printf`, `clear`, `whoami` | 直接返回退出码与输出。 |

## 第四阵营：宿主能力（FFI）桥接

| 命令 | FFI 目标 |
|---|---|
| `curl`, `wget` | 桥接 JS `fetch` |
| `sleep`, `timeout` | 桥接 `setTimeout` + async 取消机制 |
| `python`, `python3` | 桥接 Pyodide（Wasm） |
| `sqlite3` | 桥接 `sql.js`（Wasm） |
| `tar` | 桥接 Node/Browser 现成 tar 库 |
| `yq`, `html-to-markdown`, `xan` | 桥接 JS 格式转换库 |

## 需要手写的核心仅两项

1. Shell Parser：把 Bash 文本解析为 AST（建议 `lexmatch` + 递归下降，或 `moonyacc`）。
2. `awk` 最小执行器：实现模式/动作与字段计算的解释执行内核。

## 落地建议

- 优先交付“高复用命令簇”：文本处理、文件系统、环境变量三大类。
- 所有命令实现都挂到统一命令注册表，底层能力通过 trait/接口注入，便于后续替换社区包。
- 在 CI 中将“比较测试 + 安全测试”作为合并门禁，确保兼容性与防御能力不回退。
