# Test Suite Attribution

The test cases in this directory are derived from
[vercel-labs/just-bash](https://github.com/vercel-labs/just-bash),
copyright 2025 Vercel Inc., licensed under the Apache License 2.0.

A copy of the original license is included at `LICENSE-JUST-BASH` in the
project root.

## What was borrowed

| Directory | Source | Description |
|---|---|---|
| `comparison/fixtures/` | `src/comparison-tests/fixtures/` | 26 JSON fixture files with pre-recorded real bash outputs |
| `comparison/*.test.ts` | `src/comparison-tests/` | 31 comparison test scripts + runner utilities |
| `spec/bash/cases/` | `src/spec-tests/bash/cases/` | 136 bash specification test scripts (.test.sh) |
| `spec/jq/` | `src/spec-tests/jq/` | jq specification tests, parser, runner |
| `spec/grep/` | `src/spec-tests/grep/` | grep specification tests, parser, runner |
| `spec/awk/` | `src/spec-tests/awk/` | awk specification tests |
| `spec/sed/` | `src/spec-tests/sed/` | sed specification tests |
| `spec/utilities/` | `src/spec-tests/` + `src/test-utils/` | Shared test parser, runner, and busybox parser |
| `security/` | `src/security/` | Security, fuzzing, DoS, and prototype pollution tests |
| `agent-examples/` | `src/agent-examples/` | AI agent workflow test scenarios |
| `unit/` | `src/` | Root-level integration and unit tests |

## Modifications

These test files are imported as-is for reference. As MoonBash development
progresses, tests will be adapted to work with the MoonBit-based engine
while preserving the original test logic and expected outputs.

The comparison test fixtures (JSON files) are particularly valuable as they
contain **pre-recorded real bash outputs** that serve as the ground truth
for verifying MoonBash's behavioral compatibility.
