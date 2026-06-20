#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v nvim >/dev/null 2>&1; then
  echo "error: nvim is required to run tests" >&2
  exit 1
fi

nvim --headless -u NONE \
  "+set rtp+=${ROOT}" \
  "+runtime! plugin/matrix.lua" \
  "+luafile ${ROOT}/tests/matrix_spec.lua" \
  "+qa!"
