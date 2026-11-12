#!/usr/bin/env bash
set -euo pipefail

if command -v lua5.1 >/dev/null 2>&1; then
  lua5.1 tests/lua/scanner_spec.lua
elif command -v nvim >/dev/null 2>&1; then
  nvim --headless -u NONE -c 'lua dofile("tests/lua/scanner_spec.lua")' -c 'qa!'
else
  echo "Lua 5.1 or Neovim is required for core tests" >&2
  exit 2
fi
