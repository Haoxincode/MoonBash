# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MoonBash is a zero-dependency, pure-memory POSIX Shell sandbox written in MoonBit, compiled to pure JavaScript (no WASM). It is a complete rewrite of vercel-labs/just-bash with 100% API compatibility, targeting AI agents, serverless edge, and browser environments.

**Current status:** Phase 2 in progress. Core engine implemented (lexer, parser, interpreter, VFS, 40+ commands). Comparison test pass rate: 367/523 (70%).

## Build Commands

```bash
cd src && moon build --target js   # Compile MoonBit to JS
cd src && moon check --target js   # Type-check without building
npx vitest run tests/comparison/   # Run comparison tests (Vitest)
```

Build pipeline: MoonBit (.mbt) → `moon build --target js` → Pure JS → TypeScript wrapper → `tsup` bundle → npm package

## Architecture

Three-layer design:

1. **Layer 1 - MoonBit Core Engine** (`src/lib/`): Lexer → Parser (recursive descent → ADT-based AST) → Interpreter (tree-walking evaluator). Includes 40+ built-in commands and InMemoryFs (HashMap-based VFS). 正则能力应使用 `@moonbitlang/core/regexp`（当前有手写实现待替换）。

2. **Layer 2 - FFI Boundary** (`src/lib/ffi/`): `extern "js"` declarations for filesystem callbacks, network, async bridging (MoonBit async ↔ JS Promise), and tracing.

3. **Layer 3 - TypeScript API Facade** (`src/wrapper/`): `Bash` class and `Sandbox` class providing identical API to just-bash. Entry point is `Bash.exec()`.

## Test Suite Structure

Tests are pre-imported from just-bash and organized into four categories:

- **`tests/spec/bash/`** - 136 bash specification tests (from Oils project). Format: lines of `## TESTNAME`, shell code, `## STDOUT:`, expected output, `## END`.
- **`tests/spec/awk|grep|sed|jq/`** - Spec tests with custom parsers/runners for each tool.
- **`tests/comparison/fixtures/`** - 26 JSON fixtures with pre-recorded bash outputs (`{command, files, stdout, stderr, exitCode}`). These eliminate platform differences and can be re-recorded against real bash.
- **`tests/security/`** - Fuzzing, sandbox escape, prototype pollution, resource limit, and attack pattern tests.
- **`tests/agent-examples/`** - 13 AI agent workflow scenarios (bug investigation, log analysis, code review, etc.).

All TypeScript tests use Vitest and the `Bash` class.

## Key Design Documents

All in `docs/`:
- `ARCHITECTURE.md` - Three-layer design, AST types (Token, Statement, Pipeline, Command, Word, ParamExpansion enums), execution flow, module layout
- `API.md` - Public TypeScript API surface and configuration options
- `COMMANDS.md` - 80+ command specifications with implementation priority phases
- `FILESYSTEM.md` - VFS trait (IFileSystem), InMemoryFs, OverlayFs, MountableFs designs
- `SECURITY.md` - Four-layer defense model, execution limits, threat mitigations
- `FFI.md` - MoonBit ↔ JavaScript interop callbacks and async bridging
- `ROADMAP.md` - 5-phase development plan with detailed task checklists

## 生态优先原则（Ecosystem-First Principle）

**核心原则：优先复用 MoonBit 官方与社区能力，避免重复造轮子，手写核心严格收敛到解析器与执行器。**

详见 `docs/ECOSYSTEM_COMMAND_MAPPING.md`。实现命令时必须按以下分层决策：

### 第一阵营：算法库直接接管（0 手写核心）

| 命令 | 必须使用的包 |
|---|---|
| `grep`, `sed` 的正则匹配 | `@moonbitlang/core/regexp` |
| `jq` | `@moonbitlang/core/json` |
| `sort` | `@moonbitlang/core/array` 的 `sort_by` |
| `base64` | `@moonbitlang/x/codec/base64` 或社区包 |

### 第二阵营：标准库拼装

`head`, `tail`, `wc`, `cat`, `cut`, `tr`, `uniq`, `basename`, `dirname`, `seq`, `nl`, `fold`, `expand`, `unexpand`, `join`, `paste`, `column`, `strings` 等命令应使用 `core/string`、`core/array`、`core/iter` 等标准库能力，而非逐字符手写遍历。

### 仅允许手写的核心

1. Shell Parser（lexer + recursive descent parser）
2. Shell Interpreter（tree-walking evaluator）
3. `awk` 最小执行器

### 禁止事项

- **禁止手写正则引擎** — 必须使用 `@moonbitlang/core/regexp`。当前 `src/lib/regex/regex.mbt` 的 710 行手写 VM 正则需要被替换。
- **禁止手写排序算法** — 必须使用标准库的 `sort`/`sort_by`。
- **禁止在有现成标准库方法时逐字符遍历字符串** — 优先使用 `core/string` 提供的 `contains`、`split`、`index_of`、`replace` 等方法。

### 检查方法

实现新命令前，先查 [MoonBit 核心库文档](https://mooncakes.io/docs/#/moonbitlang/core/) 和 [mooncakes.io](https://mooncakes.io) 社区包，确认没有现成能力再手写。

## Implementation Notes

- **Correctness first:** Behavior must match real bash. Use comparison test fixtures to verify.
- **Zero runtime dependencies:** Compiled JS must have no external npm imports. MoonBit 标准库和官方包属于编译期依赖，不是运行时依赖，可以且应该使用。
- **Execution limits:** Parser limits (10MB input, 100K tokens, depth 100) and runtime limits (10K commands, 10K loop iterations, 100 call depth, 10MB strings).
- **Expansion order:** Brace → Tilde → Parameter → Command substitution → Arithmetic → Word splitting → Pathname → Quote removal.
- **Command lookup order:** Aliases → Functions → Builtins → Registered commands.
- Module layout: MoonBit source in `src/lib/` with subpackages: `ast/`, `lexer/`, `parser/`, `interpreter/`, `commands/`, `fs/`, `regex/`, `ffi/`, `entry/`.
