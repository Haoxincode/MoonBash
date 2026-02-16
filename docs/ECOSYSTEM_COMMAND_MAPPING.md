# MoonBit 生态命令实现映射（just-bash -> MoonBash）

这份文档用于沉淀 MoonBash 的工程实现策略。

## 核心原则："巨核与薄壳"（Fat Kernel & Thin Shell）

**所有与"物理 I/O"无关的纯计算、纯解析任务，100% 收敛回 MoonBit 内部，实现零外部依赖。**

- **巨核（Fat Kernel）**：由 MoonBit 编译成的密集纯净计算逻辑。包含 Shell Parser、VFS、tar 解包、awk 虚拟机、diff 算法、jq 引擎、正则匹配。编译后经内联优化和死代码消除，产出一个 <200 KB 的无依赖 `.js` 文件。
- **薄壳（Thin Shell）**：<100 行 TypeScript 胶水层。不含任何业务逻辑，仅向内核"喂"4 类系统原语。

## 目标

- 对 `just-bash` 的 87 个内置 Unix 命令进行实现分层。
- 将纯计算命令 100% 收归 MoonBit 内核，FFI 边界压缩到 4 个系统原语。
- 手写核心收敛到解析器、语言执行器与经典算法。

---

## 第一战区：微型语言与解析器（纯 MoonBit 手搓内核）

编写解析器和虚拟机，正是具有 ML 语言血统的 MoonBit 的绝对统治区。这些命令本身就是微型编程语言，必须手搓 AST 与解释器。

| 命令 | 实现策略 | 技术要点 |
|---|---|---|
| **Shell Parser** | 手搓 lexer + recursive descent parser | `lexmatch` 词法匹配 + ADT 模式匹配，核心中的核心 |
| **`awk`** | 手搓微型 AST 与解释器 | `BEGIN/END`、字段分割、模式匹配、内建函数、控制流 |
| **`sed`** | 手搓地址匹配 + 命令执行器 | 地址类型（行号/正则/范围）、替换、hold space、分支 |
| **`jq`** | 手搓 filter parser + 求值器 | 管道、字段访问、数组切片、条件、内建函数，基于 `core/json` |
| **`find`** | 纯内存布尔树求值 | `enum FindExpr { And; Or; Name; Type }` 在 VFS 递归求值 |
| **`expr`** | Pratt Parser（算符优先解析器） | 递归下降处理加减乘除和括号优先级 |
| **`diff`** | Myers 差分算法 | 经典 O(ND) 算法，内存占用极小，Git 底层同款 |
| **`yq`** | YAML parser + jq 风格查询 | 社区已有纯 MoonBit `yaml` 解析器，复用 jq 求值器 |

## 第二战区：算法库直接接管（0 手写核心）

这些命令的核心能力已被 MoonBit 官方库或社区包覆盖，直接调包。

| 命令 | 推荐能力 | 实现要点 |
|---|---|---|
| `grep`, `egrep`, `fgrep`, `rg` | `@moonbitlang/core/regexp` | 编译后正则对象执行搜索；VM 级正则安全 |
| `sort` | `core/array` 的 `sort_by` | 数字/逆序/字段排序走自定义比较器 |
| `base64` | `@moonbitlang/x/codec/base64` 或社区包 | 直接复用字节编码/解码 |
| `md5sum` | 社区 `md5` 包或纯 MoonBit 位运算 | 字节输入 -> 摘要字符串 |
| `sha1sum`, `sha256sum` | 社区 SHA 包或纯 MoonBit 位运算 | 统一哈希接口抽象 |

## 第三战区：标准库拼装（一行式组合）

这些命令不需要复杂算法，用 `core/string`、`core/array`、`core/iter` 等标准库能力组合即可。

| 命令 | 核心库 | 最小实现思路 |
|---|---|---|
| `head`, `tail` | `core/array` | 按行切片 |
| `wc` | `core/string` | 统计行/词/字符 |
| `cat`, `tac`, `rev` | `core/array` + `core/string` | 拼接、反转、字符级逆序 |
| `cut`, `split` | `core/string` | 分隔符切分后抽取字段 |
| `tr`, `expand`, `unexpand` | `core/string` | 字符映射与替换 |
| `basename`, `dirname` | `core/string` | 路径字符串切片 |
| `seq` | `core/math` | 算术迭代序列 |
| `join`, `comm`, `paste` | `core/iter` | 双流对齐、交集/差集 |
| `nl`, `fold`, `column`, `strings` | `core/iter` + `core/string` | 编号、折行、列对齐 |
| `uniq` | `core/hashset` 或相邻去重 | 行去重 |
| `xargs` | Shell 解释器自身 | 解析参数后调用内部命令执行 |
| `od` | `core/bytes` | 八进制/十六进制 dump |
| `tee` | `core/string` | 复制 stdin 到文件 + stdout |

## 第四战区：二进制与字节流处理（纯 MoonBit 位运算）

这些命令在前端生态中通常依赖庞大的 NPM 包，但完全可以用 MoonBit 的 `core/bytes` 底层字节操作实现。

| 命令 | 实现策略 | 技术要点 |
|---|---|---|
| **`tar`** | 纯手工字节解包 | POSIX tar 无压缩算法，仅 512 字节 Block 拼接 + ASCII 头。用 `core/bytes` 一两百行搞定 |
| **`gzip`/`gunzip`/`zcat`** | DEFLATE 算法纯 MoonBit 实现 | 基于 Huffman 编码 + LZ77 滑动窗口，社区包或手搓 |
| **`base64`** | 原生位运算 | 对 `Bytes` 进行 `>>` 和 `&` 位移 + 查表法，避免 JS 堆拷贝 |

## 第五战区：数据结构驱动状态管理（免底层算法）

| 模块 | 命令 | 数据结构与策略 |
|---|---|---|
| 环境上下文 | `env`, `printenv`, `export`, `alias`, `unalias`, `history` | `HashMap` 维护会话状态 |
| 虚拟文件系统 | `ls`, `cd`, `pwd`, `mkdir`, `touch`, `rm`, `rmdir`, `cp`, `mv`, `ln`, `readlink`, `tree`, `find`, `stat`, `du`, `chmod`, `file` | `InMemoryFs` HashMap VFS，递归增删改查 |
| 固定行为命令 | `true`, `false`, `echo`, `printf`, `clear`, `whoami`, `hostname`, `help`, `which`, `type`, `date`, `time` | 直接返回退出码与输出 |
| Shell 元命令 | `bash`, `sh`, `source`, `eval` | 递归调用内部解释器 |

---

## FFI 终极红线：仅 4 个系统原语

经过极限压榨，**真正必须通过 FFI 向宿主 JavaScript 借用的能力，被压缩到 4 个系统原语**：

| 系统原语 | 涉及命令 | FFI 目标 | 原因 |
|---|---|---|---|
| **物理网络** | `curl`, `html-to-markdown` | `globalThis.fetch` | 纯计算环境无 Syscall 权限，发包必须借用宿主 |
| **事件循环与时钟** | `sleep`, `timeout`, `date`(实时时间) | `setTimeout`, `Date.now()` | 纯计算环境写死循环会卡死宿主，需要时钟中断信号 |
| **巨型异构虚拟机** | `python3`/`python`, `sqlite3` | Pyodide (Wasm), sql.js (Wasm) | 不可能用 MoonBit 重写整个 Python 解释器或关系型数据库引擎 |
| **物理磁盘读写** | OverlayFs, ReadWriteFs | Node.js `fs` 模块 | InMemoryFs 纯内存不需要，但 OverlayFs 需要读真实磁盘 |

**注意**：`xan` (CSV) 可以基于纯 MoonBit 迭代器实现 Map-Reduce 内存计算。`yq` (YAML) 社区已有纯 MoonBit 解析器。这两者**不需要 FFI**。

---

## 社区白嫖清单（已验证可用的纯 MoonBit 包）

直接 `moon add` 拉进来当乐高拼，MoonBit 编译器的 DCE 会剪掉未使用代码，不影响包体积。

| 包名 | 用途 | 替代的 NPM 依赖 |
|---|---|---|
| `bobzhang/tar` | tar 归档解包（MoonBit 创始人亲写） | `tar-stream` |
| `moonbit-community/piediff` | Myers + Patience diff 算法 | `diff` |
| `gmlewis/gzip` + `gmlewis/flate` | DEFLATE 压缩解压 | `zlib` |
| `gmlewis/base64` | Base64 编解码 | `Buffer.from` |
| `gmlewis/md5` | MD5 哈希 | `crypto.createHash` |
| `shu-kitamura/sha256` 或 `gmlewis/sha256` | SHA-256 哈希 | `crypto.createHash` |
| `moonbit-community/yaml` | YAML 解析（从 Rust yaml-rust2 移植） | `js-yaml` |
| `xunyoyo/NyaCSV` | CSV 解析 | `csv-parse` |
| `justjavac/glob` | 通配符路径匹配 | `minimatch` |
| `TheWaWaR/clap` 或 `Yoorkin/ArgParser` | CLI 参数解析 | `commander` |

## 需要手写的核心

1. **Shell Parser**：lexer + recursive descent parser → ADT AST
2. **Shell Interpreter**：tree-walking evaluator + 展开引擎
3. **`awk` 解释器**：模式/动作 + 字段计算 + 内建函数
4. **`sed` 执行器**：地址匹配 + 命令执行 + hold/pattern space
5. **`jq` 引擎**：filter parser + JSON 求值器
6. **`expr` 解析器**：Pratt Parser 算符优先

`diff`、`tar`、`gzip`、`base64`、`md5sum`、`sha256sum`、`yq`、`xan` 全部通过社区包实现，无需手写算法。

其余所有命令 = 标准库拼装 + 状态管理 + VFS 操作。

## 落地建议

- 所有命令挂到统一命令注册表，底层能力通过 trait/接口注入，便于后续替换社区包。
- 在 CI 中将"比较测试 + 安全测试"作为合并门禁，确保兼容性与防御能力不回退。
- 实现新命令前，先查 [MoonBit 核心库文档](https://mooncakes.io/docs/#/moonbitlang/core/) 和 [mooncakes.io](https://mooncakes.io) 社区包，确认没有现成能力再手写。
