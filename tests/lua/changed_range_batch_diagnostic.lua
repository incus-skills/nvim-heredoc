package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function set_buffer(source)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  vim.bo[buf].filetype = "bash"
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  return buf
end

local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function drain_scheduled_callbacks()
  -- vim.wait processes scheduled callbacks while the predicate remains false.
  vim.wait(100, function()
    return false
  end, 10)
end

-- Control: with only the managed-operator transition in the pending batch,
-- the previous snapshot is still available and reconciliation removes the
-- structural TABs.
do
  local buf = set_buffer({
    "\tcat <<-'EOF'",
    "\t\tpayload",
    "\tEOF",
  })

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\tcat <<'EOF'" })
  drain_scheduled_callbacks()

  local actual = get_lines(buf)
  assert(actual[2] == "payload" and actual[3] == "EOF",
    "control transition should reconcile when its batch begins with ordinary scanning")
end

-- Diagnostic: the first changed interval is a recognised but unsupported
-- Return-local candidate (two queued managed openers). The second disjoint
-- interval changes an established managed heredoc from <<- to <<.
--
-- process_pending_ranges() sends pending.edits only to the first interval.
-- insert_return_local_closers() returns false for the first interval, so
-- M.process_buffer() skips reconciliation but still refreshes scan_snapshots.
-- The later interval then sees the already-refreshed snapshot and cannot
-- reconcile the operator transition.
do
  local buf = set_buffer({
    "cat <<-A <<-B",
    "",
    "A",
    "B",
    "echo between",
    "\tcat <<-'EOF'",
    "\t\tpayload",
    "\tEOF",
    "echo after",
  })

  -- The cursor and first changed range satisfy the Return-local candidate
  -- coordinates. Two openers make this candidate explicitly unsupported.
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  -- First disjoint interval: retain two openers but change the physical line,
  -- causing the first process_buffer() call to take its false early-return.
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "cat  <<-A <<-B" })

  -- Second disjoint interval: a previously established managed heredoc
  -- changes operator. This transition should remove its structural prefixes.
  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { "\tcat <<'EOF'" })

  drain_scheduled_callbacks()

  local actual = get_lines(buf)
  assert(actual[1] == "cat  <<-A <<-B", "unsupported first candidate must remain unchanged")
  assert(actual[6] == "\tcat <<'EOF'", "later ordinary opener edit must remain")
  assert(actual[7] == "\t\tpayload" and actual[8] == "\tEOF",
    "diagnostic expects the later transition to remain unreconciled after the first-range early return")

  print("changed-range batch diagnostic: first-range early return skipped later transition reconciliation")
end

print("changed-range batch diagnostic: PASS (observed behavior characterised)")
