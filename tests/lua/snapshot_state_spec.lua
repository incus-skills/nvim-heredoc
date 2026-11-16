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
local before_eof, after_eof = process_and_capture(buf, "wrapped delimiter EOF")
assert(#before_eof.heredocs == 1 and before_eof.heredocs[1].delimiter == "EO",
  "the snapshot immediately before EOF completion no longer contains the old completed heredoc")
assert(#after_eof.heredocs == 1 and after_eof.heredocs[1].delimiter == "EOF"
  and after_eof.heredocs[1].terminator_line == 7,
  "the new opener should consume the old EOF line as its apparent terminator")

print("snapshot state-transition characterization: PASS")
vim.cmd("qa!")
