#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd vendor/firmware && sha256sum -c SHA256SUMS)
moon check --target js
moon test --target js
moon test --target wasm-gc
moon test --target native
moon build --target js cmd/moonuf2
python3 scripts/cli_test.py
python3 tests/differential.py
