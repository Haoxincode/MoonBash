# Repository Guidelines

## Project Structure & Module Organization
- `docs/` contains the project design and API docs (`ARCHITECTURE.md`, `API.md`, `SECURITY.md`, `ROADMAP.md`).
- `tests/` is the main executable asset today, split into `unit/`, `comparison/`, `spec/`, `security/`, and `agent-examples/`.
- `tests/` content is copied from `just-bash` and treated as imported reference assets by default.
- `tests/comparison/fixtures/` stores recorded Bash outputs used for deterministic cross-platform comparisons.
- Implementation directories (`src/lib/`, `src/wrapper/`) are planned in docs but are not scaffolded in this snapshot.

## Build, Test, and Development Commands
Current repository state is docs + tests; root build config is not committed yet. Use these commands once scaffolding is added:
- `moon build --target js` - compile MoonBit core to JavaScript.
- `moon test` - run MoonBit unit tests.
- `pnpm test` - run Vitest TypeScript suites.
- `pnpm test:comparison` - run fixture-based Bash parity tests.
- `pnpm test:comparison:record` - re-record comparison fixtures using real Bash.
- `RECORD_FIXTURES=1 pnpm test:run tests/comparison/ls.comparison.test.ts` - re-record a single comparison test.

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
