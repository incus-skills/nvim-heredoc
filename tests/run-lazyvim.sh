#!/usr/bin/env bash
set -euo pipefail

command -v nvim >/dev/null 2>&1 || {
  echo "Neovim is required for LazyVim integration tests" >&2
  exit 2
}
command -v shfmt >/dev/null 2>&1 || {
  echo "shfmt is required for Conform integration tests" >&2
  exit 2
}

nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua dofile("tests/lua/lazyvim_spec.lua")' \
  -c 'qa!'
