#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}/src"
moon build --target js

cd "${ROOT_DIR}"
mkdir -p examples/website/dist

pnpm exec esbuild examples/website/main.js \
  --bundle \
  --format=esm \
  --platform=browser \
  --target=es2022 \
  --minify \
  --sourcemap \
  --loader:.md=text \
  --loader:.txt=text \
  --outfile=examples/website/dist/app.js

cp examples/website/index.html examples/website/styles.css examples/website/dist/
