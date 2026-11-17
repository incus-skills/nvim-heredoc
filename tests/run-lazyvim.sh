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

echo "===== Return-local closer live callback candidate ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/return_local_closer_live_candidate_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Function-wrapped Return-local closer live callback candidate ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/return_local_closer_wrapped_live_candidate_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Queued Return-local closer live callback candidate ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/return_local_closer_queued_live_candidate_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Incremental heredoc snapshot state characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/snapshot_state_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Completed-opener boundary characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/completed_opener_boundary_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Source-order boundary matrix characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/source_order_boundary_matrix_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Prior opener identity characterization ====="
nvim --headless -u NONE \

echo "===== Edit-mapped prior opener identity characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/edit_mapped_opener_identity_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Opener identity edit-boundary characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/opener_identity_edit_boundaries_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Retained-scan source-order sufficiency composition ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/retained_scan_source_order_sufficiency_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Post-heredoc structural-close characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/post_heredoc_structural_close_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Source-order selector reference model ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/source_order_selector_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Retained function-close identity characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/retained_function_close_identity_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== on_lines plugin-mutation accounting characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/on_lines_plugin_mutation_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== on_lines nvim_buf_set_text accounting characterization ====="
nvim --headless -u NONE \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/on_lines_set_text_accounting_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end'

echo "===== Live function-boundary insertion with MiniPairs ====="
NVIM_HEREDOC_FUNCTION_BOUNDARY=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/live_insert_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== Live function-boundary withdrawal with MiniPairs ====="
NVIM_HEREDOC_FUNCTION_BOUNDARY_DELETE=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/live_insert_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return trace: shell indentexpr enabled ====="
nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return regression: indented opener with MiniPairs and shell indentexpr ====="
NVIM_HEREDOC_ASSERT_INDENTED=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return regression: indented opener with MiniPairs and indentexpr disabled control ====="
NVIM_HEREDOC_DISABLE_INDENTEXPR=1 NVIM_HEREDOC_ASSERT_INDENTED=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return trace: column-zero opener with MiniPairs and shell indentexpr ====="
NVIM_HEREDOC_COLUMN_ZERO=1 NVIM_HEREDOC_ASSERT_COLUMN_ZERO=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return trace: column-zero opener with expandtab=true ====="
NVIM_HEREDOC_COLUMN_ZERO=1 NVIM_HEREDOC_ASSERT_COLUMN_ZERO=1 NVIM_HEREDOC_DISABLE_INDENTEXPR=1 NVIM_HEREDOC_NATIVE_CR=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

echo "===== LazyVim Return trace: native Return with provisioning expandtab=false ====="
NVIM_HEREDOC_DISABLE_INDENTEXPR=1 NVIM_HEREDOC_NATIVE_CR=1 NVIM_HEREDOC_PROVISIONED_EXPANDTAB=1 nvim --headless -u ci/lazyvim/init.lua \
  -c 'lua local ok, err = pcall(dofile, "tests/lua/lazyvim_return_trace_spec.lua"); if not ok then print(err); vim.cmd("cquit 1") end'

bash tests/expect-failure.sh "LazyVim integration negative control" \
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged" \
  nvim --headless -u ci/lazyvim/init.lua \
    -c 'lua local ok, err = pcall(dofile, "tests/negative/lazyvim.lua"); if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit 1") end'
