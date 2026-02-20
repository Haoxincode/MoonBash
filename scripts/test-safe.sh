#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HEAP_MB="${MOONBASH_TEST_HEAP_MB:-4096}"
if [[ -n "${NODE_OPTIONS:-}" ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS} --max-old-space-size=${HEAP_MB}"
else
  export NODE_OPTIONS="--max-old-space-size=${HEAP_MB}"
fi

COMMON_ARGS=(run --no-cache --pool=forks --maxWorkers=1 --fileParallelism=false --silent)

FAILED=()

run_batch() {
  local name="$1"
  shift
  echo
  echo "== [test:safe] ${name} =="
  if pnpm exec vitest "${COMMON_ARGS[@]}" "$@"; then
    echo "   ✓ ${name} passed"
  else
    echo "   ✗ ${name} FAILED (exit $?)"
    FAILED+=("${name}")
  fi
}

# Run a spec suite by splitting case files into groups of $chunk_size,
# each group in its own vitest process (isolated memory).
# Usage: run_spec_chunked <name> <suite_path> <cases_dir> <glob> <chunk_size>
run_spec_chunked() {
  local name="$1" suite_path="$2" cases_dir="$3" glob_pat="$4" chunk="$5"
  local files=()
  while IFS= read -r f; do
    files+=("$(basename "$f")")
  done < <(find "$cases_dir" -maxdepth 1 -name "$glob_pat" ! -name 'LICENSE*' | sort)

  local total=${#files[@]}
  local i=0
  while (( i < total )); do
    local pattern=""
    local end=$(( i + chunk ))
    (( end > total )) && end=$total
    for (( j=i; j<end; j++ )); do
      [[ -n "$pattern" ]] && pattern="${pattern}|"
      # Escape dots in filenames for regex
      pattern="${pattern}${files[$j]//./\\.}"
    done
    local part=$(( i/chunk + 1 ))
    local parts=$(( (total + chunk - 1) / chunk ))
    run_batch "${name} [${part}/${parts}]" "$suite_path" --testNamePattern="$pattern"
    i=$end
  done
}

run_batch "unit" tests/unit
run_batch "comparison" tests/comparison

# Spec tests split per tool to avoid OOM.
# Small suites (sed, awk) run directly.
# Large suites (grep, jq, bash) split case files into chunks, each in its own process.
run_batch "spec sed" tests/spec/sed
run_batch "spec awk" tests/spec/awk
run_spec_chunked "spec grep" tests/spec/grep tests/spec/grep/cases "*.tests" 2
run_spec_chunked "spec jq"   tests/spec/jq   tests/spec/jq/cases   "*.test"  3
run_spec_chunked "spec bash" tests/spec/bash  tests/spec/bash/cases "*.test.sh" 15

run_batch "security attacks" tests/security/attacks
run_batch "security sandbox" tests/security/sandbox
run_batch "security limits" tests/security/limits
run_batch "security prototype-pollution" tests/security/prototype-pollution
# NOTE: security top-level tests (defense-in-depth-box, security-violation-logger)
# are skipped because the implementation modules are not yet written (Phase 4 TODO).
# run_batch \
#   "security top-level" \
#   tests/security/worker-defense-in-depth.test.ts \
#   tests/security/defense-in-depth-box.test.ts \
#   tests/security/defense-in-depth-box-concurrent.test.ts \
#   tests/security/security-violation-logger.test.ts

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
echo "==============================="
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "== [test:safe] ALL PASSED =="
  exit 0
else
  echo "== [test:safe] ${#FAILED[@]} FAILED: =="
  for name in "${FAILED[@]}"; do
    echo "   - ${name}"
  done
  exit 1
fi
