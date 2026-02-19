# Test Remediation Plan (2026-02-19, Post-Fix)

## Objective
Prioritize remaining failures after unit/comparison stabilization.

## Completed This Round
- Fixed command dispatch regression caused by default `/bin/*` stubs executing as empty scripts.
- Restored green status for:
  - `tests/unit` (`168/168`)
  - `tests/comparison` (`523/523`)
- Fixed `sort -c` duplicate diagnostics under `2>&1`.
- Added `grep -x` and `grep -L` support (spec grep reduced `59 -> 54` failures).

## Next Priorities

## Priority 1: Security/Fuzz Quick Wins
### Why first
Low scope, high confidence, blocks `test:safe` tail stages.

### Targets
- `tests/security/attacks/filename-attacks.test.ts` (1 failing case)
- `tests/security/fuzzing/__tests__/fuzz-malformed.test.ts`
- `tests/security/fuzzing/__tests__/fuzz-coverage.test.ts`

### Likely code/files
- `src/lib/interpreter/interpreter_execution.mbt` (if stderr/redirect behavior adjustment is needed)
- `tests/security/fuzzing/generators/malformed-generator.ts` (fast-check API adaptation)
- `tests/security/fuzzing/__tests__/fuzz-coverage.test.ts` (coverage gate/corpus bootstrap)

## Priority 2: Grep Behavior Gaps (Low-Risk First)
### Why second
`59` failing tests; a subset (`-x`, `-L`, status rules) is isolated and high ROI.

### Phase 2A (quick semantic fixes)
- `-x` full-line match behavior
- `-L` exit/status behavior
- empty-input anchor handling where safe

### Phase 2B (regex compatibility)
- POSIX char classes / word-boundary classes
- brace/literal edge behavior
- invalid-regex error parity

### Likely code/files
- `src/lib/interpreter/grep.mbt`
- `src/lib/regex/regex.mbt`

## Priority 3: JQ Compatibility
### Why third
`170` failures remain, mostly compatibility breadth.

### Focus
- missing/undefined function coverage
- filter normalization/rewrite edge cases
- format handlers (`@urid`, etc.)

### Likely code/files
- `src/lib/commands/jq_cmd.mbt`
- `src/lib/commands/jq_normalize.mbt`
- `src/lib/commands/jq_compat.mbt`
- `src/lib/commands/jq_rewrite.mbt`

## Priority 4: Bash Spec Backlog (Chunked)
### Why last
Large surface area; requires subsystem-by-subsystem treatment.

### Initial subtracks
- alias expansion pipeline
- array/index/sparse semantics
- `declare/typeset/local/readonly/export` behavior
- `[ ... ]` / `test` predicate parsing and status

### Execution mode
- Continue chunked runs (`spec bash [n/10]`) and close one subsystem at a time.

## Verification Strategy
- After each patch batch, run focused suites first.
- Promote to broader checks only after local green in target area.
- Stable checkpoint command set:
  - `npx vitest run tests/unit/`
  - `npx vitest run tests/comparison/`
  - `npx vitest run tests/spec/grep/grep-spec.test.ts`
  - `npx vitest run tests/spec/jq/jq-spec.test.ts`
  - targeted security/fuzz suites
