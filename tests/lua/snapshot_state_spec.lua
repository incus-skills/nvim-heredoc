package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")

local function snapshot_store()
  for index = 1, 32 do
    local name, value = debug.getupvalue(plugin.process_buffer, index)
    if not name then break end
    if name == "scan_snapshots" then return value end
  end
  error("could not inspect the plugin's private scan_snapshots upvalue")
end

local function private_upvalue(target)
  for index = 1, 32 do
    local name, value = debug.getupvalue(plugin.process_buffer, index)
    if not name then break end
    if name == target then return value end
  end
  error("could not inspect private upvalue " .. target)
end

local function describe(scan)
  local records = {}
  for _, item in ipairs(scan.heredocs or {}) do
    records[#records + 1] = {
      opener_line = item.opener_line,
      opener_text = item.opener_text,
      delimiter = item.delimiter,
      delimiter_original = item.delimiter_original,
      queue_position = item.queue_position,
      terminator_line = item.terminator_line,
      confidence = item.confidence,
      editable = item.editable,
    }
  end
  return {
    complete = scan.complete,
    diagnostics = scan.diagnostics,
    heredocs = records,
  }
end

local function replace_buffer(buf, source)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(source, "\n", { plain = true }))
end

local function process_and_capture(buf, label)
  local store = snapshot_store()
  local before = store[buf]
  assert(before, label .. ": expected a previous snapshot")
  plugin.process_buffer(buf, nil, false)
  local after = store[buf]
  assert(after, label .. ": expected a new snapshot")
  print("===== " .. label .. " =====")
  print("previous=" .. vim.inspect(describe(before)))
  print("current=" .. vim.inspect(describe(scanner.scan(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    { tabstop = vim.bo[buf].tabstop }
  ))))
  print("saved=" .. vim.inspect(describe(after)))
  return before, after
end

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "sh"
vim.bo[buf].tabstop = 2
vim.bo[buf].shiftwidth = 2
vim.bo[buf].expandtab = false

local stores = snapshot_store()

-- Case A: standalone heredoc edited in place. The same opener identity remains
-- represented while a syntactically complete delimiter word is refined.
local standalone = table.concat({
  "command <<-'EOF'",
  "payload",
  "EOF",
}, "\n")
replace_buffer(buf, standalone)
assert(plugin.setup_buffer(buf), "plugin failed to attach for standalone fixture")
local initial = stores[buf]
assert(initial and #initial.heredocs == 1 and initial.heredocs[1].delimiter == "EOF")

for _, delimiter in ipairs({ "E", "EO", "EOF" }) do
  replace_buffer(buf, table.concat({
    "command <<-'" .. delimiter .. "'",
    "payload",
    "EOF",
  }, "\n"))
  local previous, saved = process_and_capture(buf, "standalone delimiter " .. delimiter)
  assert(#saved.heredocs == 1, "standalone opener should remain represented at " .. delimiter)
  assert(saved.heredocs[1].delimiter == delimiter)
  if delimiter ~= "EOF" then
    assert(saved.heredocs[1].terminator_line == nil,
      "shortened delimiter must retain an outstanding closer obligation")
  else
    assert(saved.heredocs[1].terminator_line == 3)
  end
  assert(#previous.heredocs == 1, "standalone prior snapshot should retain its preceding opener record")
end

-- The latest incomplete scan is also needed by operator-transition
-- reconciliation. A last-complete-only baseline would still describe EOF,
-- while the current edit has moved to E.
replace_buffer(buf, table.concat({
  "command <<-'EOF'",
  "\tpayload",
  "\tEOF",
}, "\n"))
plugin.process_buffer(buf, nil, false)
local last_complete = stores[buf]
assert(last_complete.complete and last_complete.heredocs[1].delimiter == "EOF")

replace_buffer(buf, table.concat({
  "command <<-'E'",
  "\tpayload",
}, "\n"))
local _, transition_pending = process_and_capture(buf, "operator transition: incomplete managed E")
assert(not transition_pending.complete and transition_pending.heredocs[1].delimiter == "E"
  and transition_pending.heredocs[1].terminator_line == nil)

replace_buffer(buf, table.concat({
  "command <<'E'",
  "\tpayload",
  "E",
}, "\n"))
local transition_previous, transition_saved =
  process_and_capture(buf, "operator transition: managed E to ordinary E")
assert(transition_previous == transition_pending,
  "reconciliation must receive the latest incomplete snapshot, not the older complete baseline")
assert(transition_previous.heredocs[1].operator == "<<-"
  and transition_previous.heredocs[1].delimiter == "E")
local transitioned_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(transitioned_lines[2] == "payload" and transitioned_lines[3] == "E",
  "operator transition should withdraw only the managed TAB prefix from body and closer")
assert(transition_saved.heredocs[1].operator == "<<"
  and transition_saved.heredocs[1].delimiter == "E")
assert(last_complete.heredocs[1].delimiter == "EOF",
  "the last-complete baseline is insufficient for this operator transition")

-- Case B: a new function-wrapped opener is inserted before a previously
-- completed function-wrapped heredoc. The new opener's partial delimiter
-- changes whether the old completed heredoc remains visible to the scanner.
local wrapped_baseline = table.concat({
  "old_function() {",
  "  cat <<'EOF'",
  "old payload",
  "EOF",
  "}",
}, "\n")
replace_buffer(buf, wrapped_baseline)
plugin.process_buffer(buf, nil, false)
local baseline = stores[buf]
assert(#baseline.heredocs == 1 and baseline.heredocs[1].delimiter == "EOF"
  and baseline.heredocs[1].terminator_line == 4,
  "wrapped baseline must contain the old completed heredoc")

local function wrapped_source(delimiter)
  return table.concat({
    "new_function() {",
    "  command <<-'" .. delimiter .. "'",
    "  ",
    "}",
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  }, "\n")
end

replace_buffer(buf, wrapped_source("E"))
local before_e, after_e = process_and_capture(buf, "wrapped delimiter E")
assert(#before_e.heredocs == 1 and before_e.heredocs[1].opener_text == "  cat <<'EOF'",
  "the pre-edit snapshot should still contain the old completed heredoc")
assert(#after_e.heredocs == 1 and after_e.heredocs[1].delimiter == "E"
  and after_e.heredocs[1].terminator_line == nil,
  "the first complete delimiter word should replace the old record with the new incomplete opener")

replace_buffer(buf, wrapped_source("EO"))
local before_eo, after_eo = process_and_capture(buf, "wrapped delimiter EO")
assert(#before_eo.heredocs == 1 and before_eo.heredocs[1].delimiter == "E")
assert(#after_eo.heredocs == 1 and after_eo.heredocs[1].delimiter == "EO"
  and after_eo.heredocs[1].terminator_line == nil)

replace_buffer(buf, wrapped_source("EOF"))
local final_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local boundary_helper = private_upvalue("preserve_function_heredoc_boundary")
local baseline_probe = scanner.scan(table.concat(final_lines, "\n"), { tabstop = vim.bo[buf].tabstop })
assert(boundary_helper(baseline, baseline_probe, final_lines),
  "the retained completed baseline should let boundary recovery recognise the old heredoc")
assert(baseline_probe.regions[1].boundary_line == 4
  and baseline_probe.regions[1].terminator_line == nil,
  "the baseline should recover the new function's closing-brace boundary")
local latest_probe = scanner.scan(table.concat(final_lines, "\n"), { tabstop = vim.bo[buf].tabstop })
assert(not boundary_helper(before_eof, latest_probe, final_lines),
  "the latest incomplete EO snapshot cannot recover the old EOF heredoc boundary")

local before_eof, after_eof = process_and_capture(buf, "wrapped delimiter EOF")
assert(#before_eof.heredocs == 1 and before_eof.heredocs[1].delimiter == "EO",
  "the snapshot immediately before EOF completion no longer contains the old completed heredoc")
assert(#after_eof.heredocs == 1 and after_eof.heredocs[1].delimiter == "EOF"
  and after_eof.heredocs[1].terminator_line == 8,
  "the new opener should consume the old EOF line as its apparent terminator")

print("snapshot state-transition characterization: PASS")
vim.cmd("qa!")
