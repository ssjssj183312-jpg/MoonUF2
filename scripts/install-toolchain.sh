#!/usr/bin/env bash
# 使用官方归档并固定已测试版本的哈希；仅适用于 Linux x86_64。
set -euo pipefail
DEST=${1:?用法：bash scripts/install-toolchain.sh 尚不存在的目标目录}
if [[ -e "$DEST" ]]; then echo '拒绝覆盖已经存在的目标目录' >&2; exit 1; fi
[[ $(uname -sm) == 'Linux x86_64' ]] || { echo '仅支持 Linux x86_64'; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [[ -n ${MOONUF2_ARCHIVE_CACHE:-} ]]; then
  cp "$MOONUF2_ARCHIVE_CACHE/toolchain.tar.gz" "$TMP/toolchain.tar.gz"
  cp "$MOONUF2_ARCHIVE_CACHE/core.tar.gz" "$TMP/core.tar.gz"
else
  curl -fL --retry 2 https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz -o "$TMP/toolchain.tar.gz"
  curl -fL --retry 2 https://cli.moonbitlang.com/cores/core-latest.tar.gz -o "$TMP/core.tar.gz"
fi
(cd "$TMP"; printf '%s\n' \
 '9226694de9ff978db1ecf820b7710c4224e84ec7a76b19a222d96f0cd4e31b6a  toolchain.tar.gz' \
 '6f18b8fdea18f85e628a75e4a1bd3977c5a5c9c6a836fd8824192b0e6bd91b14  core.tar.gz' | sha256sum -c -)
mkdir -p "$DEST/lib"
tar xf "$TMP/toolchain.tar.gz" -C "$DEST"
tar xf "$TMP/core.tar.gz" -C "$DEST/lib"
chmod +x "$DEST"/bin/* "$DEST/bin/internal/tcc"
export MOON_HOME="$DEST"
export PATH="$DEST/bin:$PATH"
moon -C "$DEST/lib/core" bundle --warn-list -a --all
moon version --all
