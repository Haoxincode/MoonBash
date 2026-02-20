# MoonBash 终极命令映射与架构全景表

just-bash (87 commands) -> MoonBash (pure MoonBit) 的完整实现分层。

## 核心原则："巨核与薄壳"（Fat Kernel & Thin Shell）

**所有与"物理 I/O"无关的纯计算、纯解析任务，100% 收敛回 MoonBit 内部，实现零外部依赖。**

- **巨核（Fat Kernel）**：由 MoonBit 编译成的密集纯净计算逻辑。包含 Shell Parser、VFS、tar 解包、awk 虚拟机、diff 算法、jq 引擎、正则匹配。编译后经内联优化和死代码消除（DCE），产出一个 <200 KB 的无依赖 `.js` 文件。
- **薄壳（Thin Shell）**：<100 行 TypeScript 胶水层。不含任何业务逻辑，仅向内核"喂"4 类系统原语。

---

## 战区一：社区神库接管（免手搓、零 JS 外部依赖）

这是原版最容易妥协、引入几十个外部 npm 包的地方。利用 `mooncakes.io` 上的纯 MoonBit 轮子，将二进制和复杂格式解析权彻底夺回。编译后它们会全部内联（Inline）为极微小的纯 JS 代码。

| `just-bash` 命令 | 纯 MoonBit 社区库 | 降维打击点 |
|---|---|---|
| **`tar`** | 自有 MBTAR1 格式 | `bobzhang/tar` 仅为内存数据结构（无标准 tar 二进制序列化），不适用。MoonBash 使用自定义 MBTAR1 文本格式（`D\t`/`F\tpath\tsize\n`），在 VFS 纯内存环境下足够且高效 |
| **`gzip`**, **`gunzip`**, **`zcat`** | `gmlewis/gzip` + `gmlewis/flate` | ✅ **已集成真实 DEFLATE**（commit `1d0b311`）。彻底剥离 Node.js 的 `zlib`。纯内存字节级 DEFLATE 压缩与解压引擎。VFS 使用 Latin-1 编码存储二进制数据 |
| **`diff`**, **`cmp`** | `moonbit-community/piediff` | Git 底层同款 Myers Diff + Patience 算法纯 MoonBit 实现，文本对比性能起飞 |
| **`yq`** (YAML) | `moonbit-community/yaml` | 完美移植自 Rust 工业级 `yaml-rust2` 解析器，彻底取代 npm 上的 `js-yaml` |
| **`xan`**, **`csvlook`** (CSV) | `xunyoyo/NyaCSV` | 纯内存高性能 CSV 强类型解析器，自动处理带引号的复杂字段分隔 |
| **`base64`** | `gmlewis/base64` | 高性能字节流转字符串。边缘计算（Edge）就算缺失 `atob` 也能完美运行 |
| **`md5sum`** | `gmlewis/md5` | 纯手写位运算 Hash，结果在任何异构硬件和 JS 引擎下绝对一致 |
| **`sha1sum`**, **`sha256sum`** | `shu-kitamura/sha256` 或 `gmlewis/sha256` | 摆脱 `crypto` 模块依赖，Edge 环境稳定运行 |
| **`jq`** (JSON 查询) | `bobzhang/moonjq` | MoonBit 创始人亲写的完整 jq 解释器。lexer → parser → 流式求值器，支持管道、filter、内建函数、变量绑定，415+ 测试覆盖。可完全替代手写 jq 引擎 |
| **`find`**, **`ls *.txt`** 通配符 | `justjavac/glob` | 完美支持文件路径通配符（`*`, `**`, `?`）的跨目录模式匹配 |

---

## 战区二：官方基建碾压（纯血、极速、防漏洞）

Unix 文本处理的灵魂。过去用 JS/TS 写极其容易引发 ReDoS（正则灾难回溯）和内存泄漏。全部由 MoonBit 官方核心库（`@moonbitlang/core`）降维接管。

| `just-bash` 命令 | MoonBit 标准库 | 降维打击点 |
|---|---|---|
| **`grep`**, **`rg`**, **`sed`** 正则匹配 | `core/regexp` | 基于 VM 虚拟机的正则引擎。绝对免疫大模型生成的恶意正则回溯攻击 |
| **`jq`** (JSON) | `core/json` + `bobzhang/moonjq` | 官方强类型 JSON 解析 + 社区完整 jq 解释器（可替代手写引擎） |
| **`sort`**, **`uniq`** | `core/array`, `core/hashset` | 原生高效泛型排序（`Array::sort`）和 O(1) 内存去重 |
| **`head`**, **`tail`**, **`wc`** | `core/string`, `core/array` | 纯净的数组切片与字符串统计，按行切分 `lines[0:n]` |
| **`cut`**, **`split`**, **`paste`** | `core/string`, `core/iter` | 利用原生迭代器 `Iter::zip` 进行双向流合并与分割，零额外内存开销 |
| **`expr`**, **`seq`**, **`$(( ))`** 算术 | `Int64`（内建类型） | Bash 算术为 64 位有符号整数。当前实现使用 32 位 `Int`，超过 2³¹-1 会溢出。升级到 `Int64` 可精确匹配 bash 的 wrap-around 语义，JS target 下底层自动使用 `BigInt` |
| **`date`**, **`time`** | `x/time` | 官方实验库。支持跨时区与 RFC3339 格式输出，逻辑纯本地化闭环 |

---

## 战区三：纯内存虚拟文件系统与状态管理 (VFS)

不需要任何库，用 MoonBit 核心数据结构实现。整个文件系统就是一棵存在于运行内存中的多叉树。一切文件读写本质上是对 `Map` 的节点增删改查。AI 怎么执行 `rm -rf /` 都只会清空这个变量的内存。

| 功能模块 | 命令 | 底层数据结构 |
|---|---|---|
| **目录与树操作** | `cd`, `pwd`, `ls`, `tree`, `mkdir`, `rm`, `rmdir`, `cp`, `mv`, `ln`, `readlink`, `touch`, `stat`, `du`, `chmod`, `file` | `InMemoryFs` — HashMap VFS，递归增删改查 |
| **上下文与变量** | `env`, `export`, `printenv`, `alias`, `unalias`, `history` | `HashMap[String, String]` 维护会话状态 |
| **文本流水线** | `cat`, `tac`, `rev`, `tr`, `expand`, `unexpand`, `nl`, `fold`, `column`, `join`, `comm`, `strings`, `od`, `tee`, `xargs` | `core/string` + `core/iter` 标准库拼装 |
| **固定行为命令** | `true`, `false`, `echo`, `printf`, `clear`, `whoami`, `hostname`, `help`, `which`, `type` | 直接返回退出码与输出 |
| **Shell 元命令** | `bash`, `sh`, `source`, `eval` | 递归调用内部解释器 |

---

## 战区四：手搓微型虚拟机（The Hardcore Part）

不可回避的硬核部分，也是最能体现编译技术功底的地方。有了 MoonBit 的 ADT + 模式匹配，代码量相比 TS 可缩减 70%。

| `just-bash` 命令 | 原版痛点 | MoonBit 解决思路 |
|---|---|---|
| **Shell Parser** (管道 `\|`, 重定向 `>`, 变量 `$A`) | 原版 TS 满屏 `indexOf` 和嵌套 `if/else`，极易崩溃和被注入 | `lexmatch` 词法匹配 + recursive descent parser → ADT AST 枚举流。沙盒的大脑 |
| **Shell Interpreter** (展开引擎 + 执行器) | 展开顺序 (brace→tilde→param→cmd subst→arith→word split→glob→quote) 的正确实现 | Tree-walking evaluator，8 阶段展开管线，`ExecContext` 状态机 |
| **`awk`** (微型数据提取语言) | 原版只支持极简分割，无法执行 `awk '{s+=$1} END {print s}'` 带状态累加 | 手搓精简求值器，支持 `BEGIN/END`、字段分割、模式匹配、内建函数、控制流 |
| **`sed`** (流编辑器) | 地址匹配、hold space 等高级特性实现复杂 | 地址类型（行号/正则/范围）+ 命令执行器 + pattern/hold space 双缓冲 |
| **`jq`** (JSON 查询引擎) | 完整的 filter 语法需要独立解析器 | ⚡ 现可直接使用 `bobzhang/moonjq` 社区包替代手写。若需深度定制仍可手搓 filter parser + 求值器 |
| **`expr`** (表达式求值) | 运算符优先级处理 | Pratt Parser（算符优先解析器），递归下降处理括号优先级 |
| **参数解析** (所有命令的 `-h`, `-n`, `-v`) | TS 中的参数位置判断极其混乱 | 引入社区库 `TheWaWaR/clap` 或 `Yoorkin/ArgParser`，强类型 Struct 映射 |

---

## 战区五：FFI 宿主桥接区（不可跨越的物理边界）

受限于纯 JS/Wasm 黑盒环境的隔离性，以下命令**必须且只能**通过 `extern "js"` (FFI) 向外部宿主请求权限。这也是仅有的需要保留 TS 胶水层的地方。

| `just-bash` 命令 | FFI 桥接对象 | 降维打击点 |
|---|---|---|
| **`curl`**, **`html-to-markdown`** | `globalThis.fetch` | 真实的物理网络 I/O。利用 `@moonbitlang/async/js_async` 在 MoonBit 中无缝 `await` JS Promise |
| **`sleep`**, **`timeout`** | `setTimeout` | 时钟中断必须由宿主 Event Loop 提供，防止沙盒死循环卡死整个进程 |
| **`python3`**, **`sqlite3`** | `pyodide` / `sql.js` (Wasm) | 拉起重量级异构环境。将用户脚本打包为字符串，FFI 传给 Wasm 虚拟机执行并拿回结果 |
| **物理磁盘挂载** (OverlayFs) | `node:fs` / `Deno.fs` | InMemoryFs 纯内存不需要。OverlayFs/ReadWriteFs 需要通过 FFI 执行真实物理读写 |

---

## 社区白嫖清单（已验证可用的纯 MoonBit 包）

直接 `moon add` 拉进来当乐高拼。MoonBit 编译器的 DCE（死代码消除）会剪掉未使用代码，哪怕拉满 20 个依赖包，`moon build --target js --release` 产出的依然是一个 <200 KB 的单文件。

| 包名 | 用途 | 替代的 NPM 依赖 |
|---|---|---|
| ~~`bobzhang/tar`~~ | ⚠️ 仅内存数据结构，无二进制序列化。MoonBash 使用自有 MBTAR1 格式 | `tar-stream` |
| `moonbit-community/piediff` | Myers + Patience diff 算法 | `diff` |
| `gmlewis/gzip` + `gmlewis/flate` | ✅ DEFLATE 压缩解压（已集成真实 DEFLATE） | `zlib` |
| `gmlewis/base64` | Base64 编解码 | `Buffer.from` / `atob` |
| `gmlewis/md5` | MD5 哈希 | `crypto.createHash('md5')` |
| `shu-kitamura/sha256` 或 `gmlewis/sha256` | SHA-256 哈希 | `crypto.createHash('sha256')` |
| `moonbit-community/yaml` | YAML 解析（从 Rust yaml-rust2 移植） | `js-yaml` |
| `xunyoyo/NyaCSV` | CSV 解析 | `csv-parse` |
| `bobzhang/moonjq` | 完整 jq 解释器（MoonBit 创始人亲写，415+ 测试） | 手写 jq 引擎 |
| `justjavac/glob` | 通配符路径匹配 | `minimatch` |
| `TheWaWaR/clap` 或 `Yoorkin/ArgParser` | CLI 参数解析 | `commander` |
| `justjavac/btoi` | ASCII 字节数组与整数互转 | 手写 parseInt |

---

## 需要手写的核心

1. **Shell Parser** — lexer + recursive descent parser → ADT AST
2. **Shell Interpreter** — tree-walking evaluator + 8 阶段展开引擎
3. **`awk` 解释器** — 模式/动作 + 字段计算 + 内建函数
4. **`sed` 执行器** — 地址匹配 + 命令执行 + hold/pattern space
5. **`jq` 引擎** — filter parser + JSON 求值器（⚡ 现可用 `bobzhang/moonjq` 社区包替代）
6. **`expr` 解析器** — Pratt Parser 算符优先

`diff`、`tar`、`gzip`、`base64`、`md5sum`、`sha256sum`、`yq`、`xan` 全部通过社区包实现，无需手写算法。其余所有命令 = 标准库拼装 + 状态管理 + VFS 操作。

## 落地建议

- 所有命令挂到统一命令注册表，底层能力通过 trait/接口注入，便于后续替换社区包。
- 在 CI 中将"比较测试 + 安全测试"作为合并门禁，确保兼容性与防御能力不回退。
- 实现新命令前，先查 [MoonBit 核心库文档](https://mooncakes.io/docs/#/moonbitlang/core/) 和 [mooncakes.io](https://mooncakes.io) 社区包，确认没有现成能力再手写。
