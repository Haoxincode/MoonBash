# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MoonBash is a zero-dependency, pure-memory POSIX Shell sandbox written in MoonBit, compiled to pure JavaScript (no WASM). It is a complete rewrite of vercel-labs/just-bash with 100% API compatibility, targeting AI agents, serverless edge, and browser environments.

**Current status:** Phase 1–3 complete, Phase 4 in progress. Core engine fully implemented (lexer, parser, interpreter, VFS, 87 commands). All 87 target commands implemented. Comparison test pass rate: 522/523 (1 awk regression). Security test suite: 27 files, all passing. Community packages: 12 (moonjq, piediff, gzip, etc.). gzip/gunzip/zcat uses real DEFLATE compression via `gmlewis/gzip`.

## Build Commands

```bash
cd src && moon build --target js   # Compile MoonBit to JS
cd src && moon check --target js   # Type-check without building
pnpm test:safe                     # Recommended default: batched, heap-bounded, no-cache
MOONBASH_TEST_HEAP_MB=1536 MOONBASH_TEST_SKIP_FUZZ=1 pnpm test:safe  # Low-memory local mode
pnpm test                          # One-shot full run (can OOM on low-memory machines)
npx vitest run tests/comparison/   # Run comparison tests (Vitest)
```

Build pipeline: MoonBit (.mbt) → `moon build --target js` → Pure JS → TypeScript wrapper → `tsup` bundle → npm package

## Architecture: "巨核与薄壳"（Fat Kernel & Thin Shell）

所有与"物理 I/O"无关的纯计算、纯解析任务，100% 收敛回 MoonBit 内部，实现零外部依赖。

1. **Layer 1 - MoonBit 巨核** (`src/lib/`): Lexer → Parser (recursive descent → ADT-based AST) → Interpreter (tree-walking evaluator). 包含 50+ built-in commands、InMemoryFs (HashMap-based VFS)、awk/sed/jq 微型解释器、tar 字节解包、diff 算法等全部纯计算逻辑。编译后经 DCE 优化产出 <200 KB 无依赖 JS。

2. **Layer 2 - FFI 薄壳** (`src/lib/ffi/` + `src/wrapper/`): 仅桥接 4 个系统原语 — 物理网络 (`fetch`)、事件循环 (`setTimeout`/`Date.now()`)、巨型异构 VM (`python`/`sqlite3`)、物理磁盘 (`OverlayFs`)。不含任何业务逻辑。

3. **Layer 3 - TypeScript API Facade** (`src/wrapper/`): `Bash` class and `Sandbox` class providing identical API to just-bash. Entry point is `Bash.exec()`.

## Test Suite Structure

Tests are pre-imported from just-bash and organized into four categories:

- **`tests/spec/bash/`** - 136 bash specification tests (from Oils project). Format: lines of `## TESTNAME`, shell code, `## STDOUT:`, expected output, `## END`.
- **`tests/spec/awk|grep|sed|jq/`** - Spec tests with custom parsers/runners for each tool.
- **`tests/comparison/fixtures/`** - 26 JSON fixtures with pre-recorded bash outputs (`{command, files, stdout, stderr, exitCode}`). These eliminate platform differences and can be re-recorded against real bash.
- **`tests/security/`** - Fuzzing, sandbox escape, prototype pollution, resource limit, and attack pattern tests.
- **`tests/agent-examples/`** - 13 AI agent workflow scenarios (bug investigation, log analysis, code review, etc.).

All TypeScript tests use Vitest and the `Bash` class.

### Test Execution Policy (OOM Avoidance)

- Default to `pnpm test:safe` for routine validation; it splits suites into isolated batches and disables Vitest cache.
- `test:safe` runs with single-worker fork mode and bounded heap (`MOONBASH_TEST_HEAP_MB`, default `4096`).
- Set `MOONBASH_TEST_SKIP_FUZZ=1` when iterating locally to skip the heaviest fuzzing suites.
- Use plain `pnpm test` only on high-memory environments when you explicitly want one-shot full execution.

## Key Design Documents

All in `docs/`:
- **`ECOSYSTEM_COMMAND_MAPPING.md`** — ⚠️ **实现任何命令前必读。** 87 条命令的完整分层映射（社区包接管 / 标准库拼装 / 手写核心 / FFI 桥接），附社区白嫖清单和禁止事项。
- `ARCHITECTURE.md` - 巨核与薄壳 architecture, AST types, execution flow, module layout
- `API.md` - Public TypeScript API surface and configuration options
- `COMMANDS.md` - 87 command specifications (matching just-bash) with implementation priority phases
- `FILESYSTEM.md` - VFS trait (IFileSystem), InMemoryFs, OverlayFs, MountableFs designs
- `SECURITY.md` - Four-layer defense model, execution limits, threat mitigations
- `FFI.md` - MoonBit ↔ JavaScript interop callbacks and async bridging
- `ROADMAP.md` - 5-phase development plan with detailed task checklists

## 生态优先原则（Ecosystem-First Principle）

> ⚠️ **实现任何新命令前，必须先阅读 [`docs/ECOSYSTEM_COMMAND_MAPPING.md`](docs/ECOSYSTEM_COMMAND_MAPPING.md)。** 该文档包含 87 条命令的完整五战区分层映射、社区包白嫖清单、FFI 终极红线，是所有实现决策的权威参考。

**核心原则：优先复用 MoonBit 官方与社区能力，避免重复造轮子。所有纯计算逻辑 100% 收归 MoonBit 内核，FFI 边界压缩到 4 个系统原语。**

实现命令时必须按以下分层决策：

### 社区包直接接管（已验证可用）

| 命令 | 必须使用的包 |
|---|---|
| `grep`, `sed` 的正则匹配 | `@moonbitlang/core/regexp` |
| `jq` | `bobzhang/moonjq`（完整 jq 解释器，MoonBit 创始人亲写）+ `@moonbitlang/core/json` |
| `sort` | `@moonbitlang/core/array` 的 `sort_by` |
| `tar` | 自有 MBTAR1 格式（`bobzhang/tar` 仅为内存数据结构，无二进制序列化，不适用） |
| `diff` | `moonbit-community/piediff`（Myers + Patience 算法） |
| `gzip`/`gunzip`/`zcat` | `gmlewis/gzip` + `gmlewis/flate`（纯 DEFLATE） |
| `base64` | `gmlewis/base64` |
| `md5sum` | `gmlewis/md5` |
| `sha256sum` | `shu-kitamura/sha256` 或 `gmlewis/sha256` |
| `yq` (YAML) | `moonbit-community/yaml`（从 Rust yaml-rust2 移植） |
| `xan` (CSV) | `xunyoyo/NyaCSV` |

### 标准库拼装

`head`, `tail`, `wc`, `cat`, `tac`, `cut`, `tr`, `uniq`, `basename`, `dirname`, `seq`, `nl`, `fold`, `expand`, `unexpand`, `join`, `comm`, `paste`, `column`, `strings`, `od`, `rev`, `tee` 等命令应使用 `core/string`、`core/array`、`core/iter`、`core/bytes` 等标准库能力。

### 手写核心（解析器与微型语言执行器）

1. Shell Parser（lexer + recursive descent parser）
2. Shell Interpreter（tree-walking evaluator + 展开引擎）
3. `awk` 解释器（模式/动作 + 字段计算 + 内建函数）
4. `sed` 执行器（地址匹配 + 命令执行 + hold/pattern space）
5. `jq` 引擎（⚡ 现可用 `bobzhang/moonjq` 社区包替代手写；若需深度定制仍可基于 `core/json` 手搓）
6. `expr` 解析器（Pratt Parser 算符优先）

### FFI 终极红线：仅 4 个系统原语

| 系统原语 | 涉及命令 | FFI 目标 |
|---|---|---|
| 物理网络 | `curl`, `html-to-markdown` | `globalThis.fetch` |
| 事件循环与时钟 | `sleep`, `timeout`, `date`(实时) | `setTimeout`, `Date.now()` |
| 巨型异构 VM | `python3`, `sqlite3` | Pyodide / sql.js (Wasm) |
| 物理磁盘 | OverlayFs, ReadWriteFs | Node.js `fs` 模块 |

### 禁止事项

- **禁止手写正则引擎** — 必须使用 `@moonbitlang/core/regexp`。已完成迁移。
- **禁止手写排序算法** — 必须使用标准库的 `sort`/`sort_by`。
- **禁止在有现成社区包时重复造轮子** — 先查 [mooncakes.io](https://mooncakes.io) 确认。
- **禁止将纯计算命令推给 JS FFI** — `tar`、`diff`、`gzip`、`base64`、`md5sum`、`yq`、`xan` 等必须用纯 MoonBit 实现。

### 检查方法

实现新命令前，先查 [MoonBit 核心库文档](https://mooncakes.io/docs/#/moonbitlang/core/) 和 [mooncakes.io](https://mooncakes.io) 社区包，确认没有现成能力再手写。

## Implementation Notes

- **Correctness first:** Behavior must match real bash. Use comparison test fixtures to verify.
- **Zero runtime dependencies:** Compiled JS must have no external npm imports. MoonBit 标准库和官方包属于编译期依赖，不是运行时依赖，可以且应该使用。
- **Execution limits:** Parser limits (10MB input, 100K tokens, depth 100) and runtime limits (10K commands, 10K loop iterations, 100 call depth, 10MB strings).
- **Expansion order:** Brace → Tilde → Parameter → Command substitution → Arithmetic → Word splitting → Pathname → Quote removal.
- **Command lookup order:** Aliases → Functions → Builtins → Registered commands.
- Module layout: MoonBit source in `src/lib/` with subpackages: `ast/`, `lexer/`, `parser/`, `interpreter/`, `commands/`, `fs/`, `regex/`, `ffi/`, `entry/`.

## MoonBit Language Skills（必读）

> ⚠️ **编写或修改任何 MoonBit (`.mbt`) 代码前，必须先阅读以下 skill 文档。** 这些是 MoonBit 官方提供的 agent 编码指南，包含语言惯用法、工具链用法、重构规范等关键约束。

- **[`moonbit-agent-guide`](.agents/skills/moonbit-agent-guide/SKILL.md)** — MoonBit 项目编写、测试、`moon` 工具链使用的完整工作流指南。涵盖模块/包组织、`moon check`/`moon test`/`moon ide` 命令、文件布局约定等。**编写新代码或修改现有 MoonBit 代码时必须遵循。**
- **[`moonbit-refactoring`](.agents/skills/moonbit-refactoring/SKILL.md)** — MoonBit 代码惯用重构指南。涵盖 API 最小化、函数转方法、模式匹配与 view 类型、循环不变量、测试覆盖等。**重构 MoonBit 代码时必须遵循。**

### 使用要求

1. **编写/修改 `.mbt` 文件前**，先阅读 `moonbit-agent-guide` skill 了解语言基础和工具链用法。
2. **重构 MoonBit 代码时**，先阅读 `moonbit-refactoring` skill 了解惯用模式和重构工作流。
3. 使用 `moon check` 而非直接 `moon build` 做快速验证；使用 `moon test --filter` 做针对性测试。
4. 使用 `moon ide doc`、`moon ide rename`、`moon ide find-references` 等语义化工具辅助开发。
