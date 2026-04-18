#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v moon >/dev/null 2>&1; then
  echo "[vercel-build] MoonBit toolchain not found, installing..."
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  export PATH="$HOME/.moon/bin:$PATH"
else
  echo "[vercel-build] Using existing MoonBit toolchain: $(command -v moon)"
fi

echo "[vercel-build] Moon version:"
moon version

cd "${ROOT_DIR}"
pnpm build:website
