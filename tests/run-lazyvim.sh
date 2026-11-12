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

nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_live_insert_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

bash tests/expect-failure.sh "LazyVim integration negative control" \
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged" \
  nvim --headless -u ci/lazyvim/init.lua \
    -c 'lua local ok, err = pcall(dofile, "tests/negative/lazyvim.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
