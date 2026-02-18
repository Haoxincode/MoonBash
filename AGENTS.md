# Repository Guidelines

## Project Structure & Module Organization
- `docs/` contains the project design and API docs (`ARCHITECTURE.md`, `API.md`, `SECURITY.md`, `ROADMAP.md`).
- `tests/` is the main executable asset today, split into `unit/`, `comparison/`, `spec/`, `security/`, and `agent-examples/`.
- `tests/` content is copied from `just-bash` and treated as imported reference assets by default.
- `tests/comparison/fixtures/` stores recorded Bash outputs used for deterministic cross-platform comparisons.
- Core implementation lives under `src/lib/` (MoonBit engine) and `src/wrapper/` (TypeScript facade).

## Build, Test, and Development Commands
- `cd src && moon build --target js` - compile MoonBit core to JavaScript.
- `cd src && moon check --target js` - type-check MoonBit code.
- `pnpm test:safe` - recommended default; runs Vitest in isolated batches with single worker, bounded heap, and `--no-cache` to avoid OOM/stale artifacts.
- `MOONBASH_TEST_HEAP_MB=1536 MOONBASH_TEST_SKIP_FUZZ=1 pnpm test:safe` - low-memory/local quick mode (skip fuzzing suites).
- `pnpm test` - full Vitest run in one process (faster on high-memory machines, but can OOM locally).
- `npx vitest run tests/comparison/` - run comparison tests directly.
- `pnpm test:comparison` - run fixture-based Bash parity tests.
- `pnpm test:comparison:record` - re-record comparison fixtures using real Bash.
- `RECORD_FIXTURES=1 pnpm test:run tests/comparison/ls.comparison.test.ts` - re-record a single comparison test.
- Build pipeline: MoonBit (`.mbt`) -> `moon build --target js` -> pure JS -> TypeScript wrapper -> `tsup` bundle -> npm package.

## Coding Style & Naming Conventions
- Follow existing TypeScript test style: 2-space indentation, double quotes, semicolons, and `describe/it/expect` structure.
- Keep filenames descriptive and suffix-based:
  - unit tests: `*.test.ts`
  - comparison tests: `*.comparison.test.ts`
  - spec runners: `*-spec.test.ts`
- Keep docs and code changes aligned; if behavior changes, update the relevant file under `docs/`.

## Testing Guidelines
- Framework: Vitest for TypeScript suites.
- Default test workflow: use `pnpm test:safe` to avoid machine freezes from Node OOM during full-suite runs.
- Use `pnpm test` only when you explicitly need the one-shot full run and have enough memory.
- Do not modify files under `tests/` unless explicitly requested for this repository.
- If test adaptation is explicitly requested, update files in the closest suite (`unit`, `comparison`, `security`, or `spec`) and keep attribution context intact.
- When changing comparison behavior, commit both the test file and updated fixture JSON.
- No formal coverage threshold is defined yet; minimum expectation is targeted tests for new logic and regressions.

## Commit & Pull Request Guidelines
- Use short, imperative commit subjects consistent with current history (for example, `Import test suite...`, `Initial commit...`).
- Keep commits focused (docs, tests, and implementation changes grouped logically).
- PRs should include: purpose, key changes, affected test suites, fixture re-record notes (if any), and linked issue/task.
- For security-sensitive changes, explicitly call out threat model impact and mitigations.

## Project Overview
- MoonBash is a zero-dependency, pure-memory POSIX Shell sandbox written in MoonBit and compiled to pure JavaScript (no WASM).
- It is a rewrite of `vercel-labs/just-bash` with API compatibility, targeting AI agents, serverless edge, and browser environments.
- Current status: Phase 2 complete, Phase 3 mostly complete. Core engine implemented (lexer, parser, interpreter, VFS, 50+ commands). Comparison test pass rate: 523/523 (100%).

## Architecture: "巨核与薄壳"（Fat Kernel & Thin Shell）

所有与"物理 I/O"无关的纯计算、纯解析任务，100% 收敛回 MoonBit 内部，实现零外部依赖。

- **Layer 1 - MoonBit 巨核** (`src/lib/`): Lexer → Parser (recursive descent → ADT-based AST) → Interpreter (tree-walking evaluator). 包含 50+ built-in commands、InMemoryFs (HashMap-based VFS)、awk/sed/jq 微型解释器等全部纯计算逻辑。编译后经 DCE 优化产出 <200 KB 无依赖 JS。
- **Layer 2 - FFI 薄壳** (`src/lib/ffi/` + `src/wrapper/`): 仅桥接 4 个系统原语 — 物理网络 (`fetch`)、事件循环 (`setTimeout`/`Date.now()`)、巨型异构 VM (`python`/`sqlite3`)、物理磁盘 (`OverlayFs`)。不含任何业务逻辑。
- **Layer 3 - TypeScript API Facade** (`src/wrapper/`): `Bash` class and `Sandbox` class providing identical API to just-bash. Entry point is `Bash.exec()`.

## Test Suite Details
- `tests/spec/bash/`: Bash spec tests using `## TESTNAME` / `## STDOUT:` / `## END` block format.
- `tests/spec/awk|grep|sed|jq/`: tool-specific spec tests with custom parsers/runners.
- `tests/comparison/fixtures/`: recorded bash outputs with `{command, files, stdout, stderr, exitCode}` for deterministic parity tests.
- `tests/security/`: fuzzing, sandbox escape, prototype pollution, resource limit, and attack-pattern tests.
- `tests/agent-examples/`: AI agent workflow scenarios (bug investigation, log analysis, code review, etc.).

## Key Design Docs

> ⚠️ **实现任何新命令前，必须先阅读 `docs/ECOSYSTEM_COMMAND_MAPPING.md`。** 该文档包含 87 条命令的完整五战区分层映射、社区包白嫖清单、FFI 终极红线，是所有实现决策的权威参考。

- **`ECOSYSTEM_COMMAND_MAPPING.md`** — 命令映射与架构全景表（必读）
- `ARCHITECTURE.md` - 巨核与薄壳 architecture, AST types, execution flow, module layout
- `API.md`, `SECURITY.md`, `ROADMAP.md`, `COMMANDS.md`, `FILESYSTEM.md`, `FFI.md` — 与行为变更保持同步

## Ecosystem-First Principle

**核心原则：优先复用 MoonBit 官方与社区能力，避免重复造轮子。所有纯计算逻辑 100% 收归 MoonBit 内核，FFI 边界压缩到 4 个系统原语。**

完整分层决策见 `docs/ECOSYSTEM_COMMAND_MAPPING.md`，以下为摘要：

### 社区包直接接管（已验证可用）

| 命令 | 必须使用的包 |
|---|---|
| `grep`, `sed` 正则匹配 | `@moonbitlang/core/regexp` |
| `jq` | `bobzhang/moonjq`（完整 jq 解释器）+ `@moonbitlang/core/json` |
| `sort` | `@moonbitlang/core/array` 的 `sort_by` |
| `tar` | `bobzhang/tar` |
| `diff` | `moonbit-community/piediff` |
| `gzip`/`gunzip`/`zcat` | `gmlewis/gzip` + `gmlewis/flate` |
| `base64` | `gmlewis/base64` |
| `md5sum` | `gmlewis/md5` |
| `sha256sum` | `shu-kitamura/sha256` 或 `gmlewis/sha256` |
| `yq` (YAML) | `moonbit-community/yaml` |
| `xan` (CSV) | `xunyoyo/NyaCSV` |

### 仅允许手写的核心

1. Shell Parser（lexer + recursive descent parser）
2. Shell Interpreter（tree-walking evaluator + 展开引擎）
3. `awk` 解释器
4. `sed` 执行器
5. `jq` 引擎（⚡ 现可用 `bobzhang/moonjq` 社区包替代；若需深度定制仍可基于 `core/json` 手搓）
6. `expr` 解析器（Pratt Parser）

### 禁止事项

- **禁止手写正则引擎** — 必须使用 `@moonbitlang/core/regexp`。
- **禁止手写排序算法** — 必须使用标准库的 `sort`/`sort_by`。
- **禁止在有现成社区包时重复造轮子** — 先查 [mooncakes.io](https://mooncakes.io) 确认。
- **禁止将纯计算命令推给 JS FFI** — `tar`、`diff`、`gzip`、`base64`、`md5sum`、`yq`、`xan` 等必须用纯 MoonBit 实现。

### 检查方法

实现新命令前，先查 [MoonBit 核心库文档](https://mooncakes.io/docs/#/moonbitlang/core/) 和 [mooncakes.io](https://mooncakes.io) 社区包，确认没有现成能力再手写。

## Implementation Notes
- Correctness first: behavior must match real Bash; use comparison fixtures for validation.
- Zero runtime dependencies: no external npm imports in generated runtime JS. MoonBit stdlib/official packages are acceptable compile-time dependencies.
- Respect execution limits:
  - Parser: 10MB input, 100K tokens, depth 100
  - Runtime: 10K commands, 10K loop iterations, call depth 100, string size 10MB
- Expansion order: Brace -> Tilde -> Parameter -> Command substitution -> Arithmetic -> Word splitting -> Pathname -> Quote removal.
- Command lookup order: Aliases -> Functions -> Builtins -> Registered commands.
- Module layout under `src/lib/`: `ast/`, `lexer/`, `parser/`, `interpreter/`, `commands/`, `fs/`, `regex/`, `ffi/`, `entry/`.

## MoonBit Language Skills（必读）

> ⚠️ **编写或修改任何 MoonBit (`.mbt`) 代码前，必须先阅读以下 skill 文档。** 这些是 MoonBit 官方提供的 agent 编码指南，包含语言惯用法、工具链用法、重构规范等关键约束。

- **[`moonbit-agent-guide`](.agents/skills/moonbit-agent-guide/SKILL.md)** — MoonBit 项目编写、测试、`moon` 工具链使用的完整工作流指南。涵盖模块/包组织、`moon check`/`moon test`/`moon ide` 命令、文件布局约定等。**编写新代码或修改现有 MoonBit 代码时必须遵循。**
- **[`moonbit-refactoring`](.agents/skills/moonbit-refactoring/SKILL.md)** — MoonBit 代码惯用重构指南。涵盖 API 最小化、函数转方法、模式匹配与 view 类型、循环不变量、测试覆盖等。**重构 MoonBit 代码时必须遵循。**

### 使用要求

1. **编写/修改 `.mbt` 文件前**，先阅读 `moonbit-agent-guide` skill 了解语言基础和工具链用法。
2. **重构 MoonBit 代码时**，先阅读 `moonbit-refactoring` skill 了解惯用模式和重构工作流。
3. 使用 `moon check` 而非直接 `moon build` 做快速验证；使用 `moon test --filter` 做针对性测试。
4. 使用 `moon ide doc`、`moon ide rename`、`moon ide find-references` 等语义化工具辅助开发。
