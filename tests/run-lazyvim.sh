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
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Return-local closer candidate reference model ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/return_local_closer_candidate_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Incremental heredoc snapshot state characterization ====="
echo "===== Completed-opener boundary characterization ====="
