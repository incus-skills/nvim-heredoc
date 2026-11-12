#!/usr/bin/env bash
set -euo pipefail
command -v nvim >/dev/null 2>&1 || {
  echo "Neovim is required for buffer integration tests" >&2
  exit 2
}
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/buffer_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else local live_ok, live_err = pcall(dofile, "tests/lua/live_insert_spec.lua"); if not live_ok then print(live_err); vim.cmd("cquit 1") end end'
bash tests/expect-failure.sh "buffer integration negative control" \
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged" \
  nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/negative/buffer.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
