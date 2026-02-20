# Test Status Snapshot (2026-02-19, Post-Fix)

## Scope
This snapshot reflects the current status after the latest command-dispatch and redirection fixes.

## Status Convention Alignment
- This file is the pass/fail source of truth for test health as of `2026-02-19`.
- In `docs/ROADMAP.md`, `✅`/`🔧` checkboxes primarily track implementation coverage and roadmap closure state, not automatic full-green test parity.
- When `ROADMAP` and older summaries conflict, use this snapshot + `docs/TEST_FAILURE_MATRIX_2026-02-19.md` as canonical for current failures.

## Commands Run
- `cd src && moon build --target js`
- `npx vitest run tests/unit/`
- `npx vitest run tests/comparison/`
- `npx vitest run tests/spec/sed/sed-spec.test.ts tests/spec/awk/awk-spec.test.ts`
- `npx vitest run tests/spec/grep/grep-spec.test.ts`
- `npx vitest run tests/spec/jq/jq-spec.test.ts --reporter=json --outputFile=.tmp/jq-spec-report.json`
- `npx vitest run tests/security/attacks tests/security/sandbox tests/security/limits tests/security/prototype-pollution`
- `npx vitest run tests/security/fuzzing/generators tests/security/fuzzing/__tests__`
- `npx vitest run tests/agent-examples`
- partial `pnpm test:safe` (spec bash chunked run reached `[6/10]`, interrupted)

## High-Level Results
- `tests/unit`: `7/7` files passed, `168/168` tests passed.
- `tests/comparison`: `31/31` files passed, `523/523` tests passed.
- `tests/spec/sed`: passed (`237/237`).
- `tests/spec/awk`: passed (`152` passed, `1` skipped).
- `tests/spec/grep`: failed (`54` failed, `227` passed, `51` skipped).
- `tests/spec/jq`: failed (`170` failed, `598` passed).
- `tests/spec/bash` (chunked safe run, partial):
  - `[1/10]`: `205` failed, `179` passed, `1952` skipped
  - `[2/10]`: `142` failed, `135` passed, `2059` skipped
  - `[3/10]`: `146` failed, `194` passed, `1996` skipped
  - `[4/10]`: `51` failed, `133` passed, `2152` skipped
  - `[5/10]`: `145` failed, `114` passed, `2077` skipped

## Security and Agent Suites
- `tests/security/attacks|sandbox|limits|prototype-pollution`:
  - `17` files passed
  - `1` file failed (`tests/security/attacks/filename-attacks.test.ts`)
  - failing case: `Symlink Security > should handle broken symlinks gracefully`
- `tests/security/fuzzing/generators`: passed (`42/42`).
- `tests/security/fuzzing/__tests__`: `2` failed suites:
  - `fuzz-malformed.test.ts`: `fc.stringOf` API mismatch at `tests/security/fuzzing/generators/malformed-generator.ts:55`
  - `fuzz-coverage.test.ts`: coverage threshold assertion failed at `tests/security/fuzzing/__tests__/fuzz-coverage.test.ts:177`
- `tests/agent-examples/*`: passed (`272/272`).

## Fixed In This Round
- Resolved command-dispatch regression that caused empty output/incorrect exit status in many unit/comparison tests.
- Added virtual command-stub dispatch for default `/bin/*` stubs.
- Fixed `sort -c` duplicate output under `2>&1`.

## References
- Detailed matrix: `docs/TEST_FAILURE_MATRIX_2026-02-19.md`
- Remediation plan: `docs/TEST_FIX_PLAN_2026-02-19.md`
