#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HEAP_MB="${MOONBASH_TEST_HEAP_MB:-2048}"
if [[ -n "${NODE_OPTIONS:-}" ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS} --max-old-space-size=${HEAP_MB}"
else
  export NODE_OPTIONS="--max-old-space-size=${HEAP_MB}"
fi

COMMON_ARGS=(run --pool=forks --maxWorkers=1 --fileParallelism=false --silent)

run_batch() {
  local name="$1"
  shift
  echo
  echo "== [test:safe] ${name} =="
  pnpm exec vitest "${COMMON_ARGS[@]}" "$@"
}

run_batch "unit" tests/unit
run_batch "comparison" tests/comparison
run_batch "spec" tests/spec

run_batch "security attacks" tests/security/attacks
run_batch "security sandbox" tests/security/sandbox
run_batch "security limits" tests/security/limits
run_batch "security prototype-pollution" tests/security/prototype-pollution
run_batch \
  "security top-level" \
  tests/security/worker-defense-in-depth.test.ts \
  tests/security/defense-in-depth-box.test.ts \
  tests/security/defense-in-depth-box-concurrent.test.ts \
  tests/security/security-violation-logger.test.ts

if [[ "${MOONBASH_TEST_SKIP_FUZZ:-0}" != "1" ]]; then
  run_batch "security fuzzing generators" tests/security/fuzzing/generators
  run_batch "security fuzzing suites" tests/security/fuzzing/__tests__
fi

run_batch \
  "agent examples core" \
  tests/agent-examples/bug-investigation.test.ts \
  tests/agent-examples/code-review.test.ts \
  tests/agent-examples/config-analysis.test.ts \
  tests/agent-examples/debugging-workflow.test.ts \
  tests/agent-examples/dependency-analysis.test.ts \
  tests/agent-examples/feature-implementation.test.ts \
  tests/agent-examples/log-analysis.test.ts \
  tests/agent-examples/multi-file-migration.test.ts \
  tests/agent-examples/refactoring-workflow.test.ts \
  tests/agent-examples/security-audit.test.ts \
  tests/agent-examples/text-processing-workflows.test.ts
run_batch "agent examples python" tests/agent-examples/python-scripting.test.ts
run_batch "agent examples codebase exploration" tests/agent-examples/codebase-exploration.test.ts

echo
echo "== [test:safe] done =="
