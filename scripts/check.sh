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
# 对仓库中用户实际下载的预编译产物运行同一套格式回归。
python3 scripts/cli_test.py --cli dist/moonuf2.cjs
python3 tests/differential.py --cli dist/moonuf2.cjs
