#!/usr/bin/env bash
set -euo pipefail

if command -v lua5.1 >/dev/null 2>&1; then
  lua5.1 tests/lua/scanner_spec.lua
  bash tests/expect-failure.sh "core scanner negative control" \
    "NEGATIVE_CONTROL: ordinary heredoc was classified as managed" \
    lua5.1 tests/negative/core.lua
elif command -v nvim >/dev/null 2>&1; then
  nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/scanner_spec.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
  bash tests/expect-failure.sh "core scanner negative control" \
    "NEGATIVE_CONTROL: ordinary heredoc was classified as managed" \
    nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/negative/core.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
else
  echo "Lua 5.1 or Neovim is required for core tests" >&2
  exit 2
fi
