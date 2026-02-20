# Test Failure Matrix (2026-02-19, Post-Fix)

> This matrix is the canonical failure inventory for compatibility hardening at the `2026-02-19` snapshot.
> If roadmap completion markers differ, use this file (and `docs/TEST_STATUS_2026-02-19.md`) for test-health truth.

## 1) Spec/Grep (`tests/spec/grep/grep-spec.test.ts`)
- Current: `54` failed, `227` passed, `51` skipped.

### Failure Clusters
- Exact-match and exit-status behavior:
  - `grep -x` partial-match cases still match incorrectly.
  - `grep -L` exit-code behavior diverges.
- ERE/BRE compatibility:
  - many patterns return `invalid regular expression` where GNU/Bash fixtures expect match or different error behavior.
  - affected areas include POSIX char classes (`[[:alpha:]]`, `[[:digit:]]`), braces (`{...}` literal/quantifier edge cases), word-boundary classes (`[[:<:]]`, `[[:>:]]`).
- Empty-input anchor handling:
  - `^$`, `$$`, `^^`, `$^` style cases diverge on empty input.
- `UNEXPECTED PASS` markers:
  - multiple cases previously marked skip now pass; test metadata/skips need cleanup strategy (do not edit tests unless explicitly requested).

## 2) Spec/JQ (`tests/spec/jq/jq-spec.test.ts`)
- Current: `170` failed, `598` passed.

### Failure Distribution (from JSON report)
- `jq.test`: `92` failures
- `man.test`: `74` failures
- `base64.test`: `2` failures
- `uri.test`: `2` failures

### Common Signatures
- `jq: invalid filter`
- `EvalError("Undefined function: ...")`
- unknown format handlers (e.g. `@urid`)
- compatibility mismatches in normalization/rewrite behavior

## 3) Spec/Bash (`tests/spec/bash/spec.test.ts`, chunked safe run partial)
- Chunked safe run completed `[1/10]` to `[5/10]` before interruption at `[6/10]`.
- Failures already confirmed in first 5 chunks:
  - `[1/10]`: `205`
  - `[2/10]`: `142`
  - `[3/10]`: `146`
  - `[4/10]`: `51`
  - `[5/10]`: `145`
- Subsystems with heavy concentration (from failing chunk outputs):
  - alias expansion semantics
  - array assignment/indexing and sparse/negative index behavior
  - `declare/typeset/local/readonly/export` flag and output behavior
  - bracket/test predicate and parsing edge cases
  - extglob / globignore behavior

## 4) Security Suites
### `tests/security/attacks/filename-attacks.test.ts`
- `1` failing case:
  - `Symlink Security > should handle broken symlinks gracefully`
  - expectation currently checks `stderr` truthiness after `2>&1` command path.

### `tests/security/fuzzing/__tests__`
- `2` failing suites:
  - `fuzz-malformed.test.ts`: `fc.stringOf` API mismatch
  - `fuzz-coverage.test.ts`: coverage threshold assertion (`>=30`) currently reports `0`

## 5) Passing Areas (now green)
- `tests/unit`: `168/168`
- `tests/comparison`: `523/523`
- `tests/spec/sed`: pass
- `tests/spec/awk`: pass
- `tests/agent-examples/*`: `272/272`
