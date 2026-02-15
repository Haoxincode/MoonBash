# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MoonBash is a zero-dependency, pure-memory POSIX Shell sandbox written in MoonBit, compiled to pure JavaScript (no WASM). It is a complete rewrite of vercel-labs/just-bash with 100% API compatibility, targeting AI agents, serverless edge, and browser environments.

**Current status:** Design phase complete, test suite imported (637 files), no source code implemented yet. Ready to begin Phase 1 implementation.

## Build Commands (Planned)

No build pipeline exists yet. When implemented:

```bash
moon build --target js          # Compile MoonBit to JS
moon test                       # Run MoonBit unit tests
pnpm test                       # Run TypeScript integration tests (Vitest)
```

Build pipeline: MoonBit (.mbt) → `moon build --target js` → Pure JS → TypeScript wrapper → `tsup` bundle → npm package

## Architecture

Three-layer design:

1. **Layer 1 - MoonBit Core Engine** (`src/lib/`): Lexer (`lexmatch`-based tokenizer) → Parser (recursive descent → ADT-based AST) → Interpreter (tree-walking evaluator). Includes 80+ built-in commands, InMemoryFs (HashMap-based VFS), and a VM-based regex engine (ReDoS-immune).

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

## Implementation Notes

- **Correctness first:** Behavior must match real bash. Use comparison test fixtures to verify.
- **Zero runtime dependencies:** Compiled JS must have no external npm imports.
- **Execution limits:** Parser limits (10MB input, 100K tokens, depth 100) and runtime limits (10K commands, 10K loop iterations, 100 call depth, 10MB strings).
- **Expansion order:** Brace → Tilde → Parameter → Command substitution → Arithmetic → Word splitting → Pathname → Quote removal.
- **Command lookup order:** Aliases → Functions → Builtins → Registered commands.
- The planned module layout places MoonBit source in `src/lib/` with subpackages: `ast/`, `lexer/`, `parser/`, `interpreter/`, `commands/`, `fs/`, `regex/`, `ffi/`.
