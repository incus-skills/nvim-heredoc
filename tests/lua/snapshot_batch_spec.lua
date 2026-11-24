package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local plugin = require("nvim-heredoc")

local function set_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "bash"
  assert(plugin.setup_buffer(buf), "the bash buffer should attach")
  return buf
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function snapshot(buf)
  return plugin._snapshot_for_test(buf)
end

local function wait_generation(buf, generation)
  assert(vim.wait(1500, function()
    return snapshot(buf).generation >= generation
  end, 10), "scheduled on_lines batch did not publish generation " .. generation
    .. "; actual=" .. tostring(snapshot(buf).generation))
end

local function assert_one_batch(buf, before)
  wait_generation(buf, before + 1)
  assert(snapshot(buf).generation == before + 1,
    "one coalesced on_lines batch must publish exactly one generation")
end

-- Case 1: payload-only edit is observed through the real on_lines callback.
do
  local buf = set_buffer({ "cat <<-EOF", "\tpayload", "EOF", "echo after" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "\tchanged payload" })
  assert_one_batch(buf, before)
  assert(#snapshot(buf).heredocs == 1)
  assert(snapshot(buf).heredocs[1].terminator_line == 3)
end

-- Case 2: opener and terminator edits in one event batch retain ordered history.
do
  local buf = set_buffer({ "cat <<-OLD", "\tbody", "OLD", "echo after" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "cat <<-NEW" })
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "NEW" })
  assert_one_batch(buf, before)
  assert(snapshot(buf).heredocs[1].delimiter == "NEW")
  assert(snapshot(buf).heredocs[1].terminator_line == 3)
end

-- Case 3: deleting a terminator commits an incomplete, conservative snapshot.
do
  local buf = set_buffer({ "cat <<-EOF", "\tbody", "EOF", "echo after" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, {})
  assert_one_batch(buf, before)
  assert(snapshot(buf).complete == false)
  assert(snapshot(buf).heredocs[1].terminator_line == nil)
  assert(snapshot(buf).heredocs[1].confidence == "uncertain")
end

-- Case 4: a continuation-line edit is reconciled as part of the same batch.
do
  local buf = set_buffer({ "cat \\", "  <<-EOF", "\tbody", "EOF", "echo after" })
  assert(#snapshot(buf).heredocs == 1, "fixture must begin with one continued heredoc")
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "    <<-EOF" })
  assert_one_batch(buf, before)
  assert(#snapshot(buf).heredocs == 1)
  assert(snapshot(buf).heredocs[1].terminator_line == 4)
end

-- Case 5: inserting an earlier matching terminator inside payload moves the
-- lexical boundary to that line; the former terminator becomes shell source.
do
  local buf = set_buffer({ "cat <<-EOF", "\tpayload", "\tmore", "EOF", "echo after" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "EOF" })
  assert_one_batch(buf, before)
  assert(snapshot(buf).heredocs[1].terminator_line == 3)
end

-- Case 6: insertion at a surviving checkpoint still creates a non-empty
-- rescan footprint and discovers the newly inserted command group.
do
  local buf = set_buffer({ "cat <<-A", "\ta", "A", "echo tail" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 3, 3, false, {
    "cat <<-B", "\tb", "B",
  })
  assert_one_batch(buf, before)
  assert(#snapshot(buf).heredocs == 2,
    "a command inserted at a checkpoint must be discovered")
  assert(snapshot(buf).heredocs[2].delimiter == "B")
end

-- Multiple disjoint edits in one event-loop turn form one owned batch and one
-- snapshot publication, not one publication per aggregate range.
do
  local buf = set_buffer({
    "cat <<-A", "\ta", "A",
    "echo middle",
    "cat <<-B", "\tb", "B",
  })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "\tfirst changed" })
  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { "\tsecond changed" })
  assert_one_batch(buf, before)
  assert(#snapshot(buf).heredocs == 2)
end

-- An empty TextChanged callback cannot trigger an un-ranged full-buffer scan.
do
  local buf = set_buffer({ "echo unchanged" })
  local before = snapshot(buf).generation
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  vim.wait(50, function() return false end, 10)
  assert(snapshot(buf).generation == before,
    "an empty pending queue must not publish a fallback scan")
end

-- A batch superseded by a newer full-scan publication before its scheduled
-- callback runs must be discarded without a second generation advance.
do
  local buf = set_buffer({ "cat <<-EOF", "\tbody", "EOF" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "\tnew body" })
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  assert(snapshot(buf).generation == before + 1,
    "InsertLeave's existing full scan should supersede the queued batch")
  vim.wait(100, function() return false end, 10)
  assert(snapshot(buf).generation == before + 1,
    "the superseded scheduled batch must not publish")
end

-- Insertion before a later edit in the same batch must preserve the second
-- notification's post-edit coordinate space.
do
  local buf = set_buffer({ "cat <<-EOF", "\tbody", "EOF", "echo after" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "# inserted before" })
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "\tshifted payload" })
  assert_one_batch(buf, before)
  assert(snapshot(buf).heredocs[1].opener_line == 2)
  assert(snapshot(buf).heredocs[1].terminator_line == 4)
end

-- An incomplete later group makes a bounded prefix edit require the merge's
-- full-buffer fallback; the fallback must retain the whole-buffer uncertainty.
do
  local buf = set_buffer({
    "cat <<-A", "\ta", "A",
    "cat <<-B", "\tb",
  })
  assert(snapshot(buf).complete == false)
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "\tchanged a" })
  assert_one_batch(buf, before)
  assert(#snapshot(buf).heredocs == 2,
    "fallback must reconstruct both the edited prefix and incomplete suffix")
  assert(snapshot(buf).complete == false)
  assert(snapshot(buf).heredocs[2].terminator_line == nil)
end

-- Deferred reconciliation is not a second scope-creation authority: editing
-- the first body row of an incomplete opener must not append a closer.
do
  local buf = set_buffer({ "cat <<-EOF", "first body" })
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "first body changed" })
  assert_one_batch(buf, before)
  local actual = lines(buf)
  assert(#actual == 2 and actual[2] == "first body changed",
    "deferred on_lines reconciliation must not create a closer")
end

-- Scanner observations are option-sensitive. If tabstop changes after
-- attachment, the owned edit batch must full-scan with the current option
-- rather than reuse structurally incompatible observations.
do
  local buf = set_buffer({ "  cat <<-EOF", "payload", "EOF" })
  assert(snapshot(buf).tabstop == 8,
    "fixture should begin with the default tabstop snapshot")
  vim.bo[buf].tabstop = 2
  local before = snapshot(buf).generation
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "changed payload" })
  assert_one_batch(buf, before)
  assert(snapshot(buf).tabstop == 2)
  assert(snapshot(buf).heredocs[1].editable,
    "the current tabstop should restore the safe structural prefix")
  assert(lines(buf)[2] == "\t\tchanged payload",
    "the batch fallback should apply the current structural prefix")
end

print("snapshot batch integration tests: PASS")
