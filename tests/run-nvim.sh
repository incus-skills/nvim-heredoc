#!/usr/bin/env bash
set -euo pipefail
command -v nvim >/dev/null 2>&1 || {
  echo "Neovim is required for buffer integration tests" >&2
  exit 2
}
nvim --headless -u NONE -c 'lua dofile("tests/lua/buffer_spec.lua")' -c 'qa!'
