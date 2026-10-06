#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
moon build --target js --release cmd/moonuf2
mkdir -p dist
cp _build/js/release/build/cmd/moonuf2/moonuf2.js dist/moonuf2.cjs
node dist/moonuf2.cjs --version
