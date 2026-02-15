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
- `pnpm test` - run Vitest TypeScript suites.
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
- Current status (from `CLAUDE.md`): Phase 2 in progress; core engine implemented (lexer, parser, interpreter, VFS, 40+ commands); comparison pass rate `367/523` (`70%`).

## Architecture
- Three-layer architecture:
  - Layer 1 (`src/lib/`): MoonBit core engine (`lexer` -> `parser` -> `interpreter`), built-in commands, `InMemoryFs`.
  - Layer 2 (`src/lib/ffi/`): `extern "js"` FFI boundary for fs callbacks, network, async bridge, tracing.
  - Layer 3 (`src/wrapper/`): TypeScript facade (`Bash` and `Sandbox` classes), entry via `Bash.exec()`.
- Regex capability should use `@moonbitlang/core/regexp`; handwritten regex engine is technical debt to be replaced.

## Test Suite Details
- `tests/spec/bash/`: Bash spec tests using `## TESTNAME` / `## STDOUT:` / `## END` block format.
- `tests/spec/awk|grep|sed|jq/`: tool-specific spec tests with custom parsers/runners.
- `tests/comparison/fixtures/`: recorded bash outputs with `{command, files, stdout, stderr, exitCode}` for deterministic parity tests.
- `tests/security/`: fuzzing, sandbox escape, prototype pollution, resource limit, and attack-pattern tests.
- `tests/agent-examples/`: AI agent workflow scenarios (bug investigation, log analysis, code review, etc.).

## Key Design Docs
- In addition to `ARCHITECTURE.md`, `API.md`, `SECURITY.md`, `ROADMAP.md`, keep `COMMANDS.md`, `FILESYSTEM.md`, and `FFI.md` aligned with behavior changes.

## Ecosystem-First Principle
- Prefer MoonBit official/community packages before handwritten implementations.
- Allowed handwritten core is strictly limited to:
  - Shell parser (`lexer` + recursive descent parser)
  - Shell interpreter (tree-walking evaluator)
  - Minimal `awk` executor
- Must-use examples:
  - Regex for `grep`/`sed`: `@moonbitlang/core/regexp`
  - `jq`: `@moonbitlang/core/json`
  - `sort`: `@moonbitlang/core/array` (`sort_by`)
  - `base64`: `@moonbitlang/x/codec/base64` or equivalent community package
- Prohibitions:
  - Do not handwrite a regex engine.
  - Do not handwrite sorting algorithms.
  - Do not do character-by-character string traversal when standard library methods already solve it.
- Before implementing a new command, check MoonBit core docs and `mooncakes.io` packages first.

## Implementation Notes
- Correctness first: behavior must match real Bash; use comparison fixtures for validation.
- Zero runtime dependencies: no external npm imports in generated runtime JS. MoonBit stdlib/official packages are acceptable compile-time dependencies.
- Respect execution limits:
  - Parser: 10MB input, 100K tokens, depth 100
  - Runtime: 10K commands, 10K loop iterations, call depth 100, string size 10MB
- Expansion order: Brace -> Tilde -> Parameter -> Command substitution -> Arithmetic -> Word splitting -> Pathname -> Quote removal.
- Command lookup order: Aliases -> Functions -> Builtins -> Registered commands.
- Module layout under `src/lib/`: `ast/`, `lexer/`, `parser/`, `interpreter/`, `commands/`, `fs/`, `regex/`, `ffi/`, `entry/`.
