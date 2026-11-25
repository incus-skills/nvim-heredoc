#!/usr/bin/env bash
set -euo pipefail
command -v nvim >/dev/null 2>&1 || {
  echo "Neovim is required for buffer integration tests" >&2
  exit 2
}
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/planner_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else local merge_ok, merge_err = pcall(dofile, "tests/lua/merge_spec.lua"); if not merge_ok then print(merge_err); vim.cmd("cquit 1") else local buffer_ok, buffer_err = pcall(dofile, "tests/lua/buffer_spec.lua"); if not buffer_ok then print(buffer_err); vim.cmd("cquit 1") else local live_ok, live_err = pcall(dofile, "tests/lua/live_insert_spec.lua"); if not live_ok then print(live_err); vim.cmd("cquit 1") else vim.cmd("qa!") end end end end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/snapshot_batch_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/insertleave_local_recovery_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/live_space_indent_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/live_autoindent_tab_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/live_autoindent_burst_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'
bash tests/expect-failure.sh "buffer integration negative control" \
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged" \
  nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/negative/buffer.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
nvim --headless -u NONE -c 'lua local ok, err = pcall(dofile, "tests/lua/live_return_quoted_context_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'
