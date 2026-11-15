-- Trace successive Return operations through Neovim's real input queue.
--
-- Run inside the affected Neovim instance:
--   :luafile /path/to/nvim-heredoc/scripts/trace-return.lua
--
-- The test uses nvim_input(), so configured Insert-mode mappings (including
-- MiniPairs) are exercised. It verifies Insert mode around every operation and
-- aborts rather than recording a misleading trace if that invariant fails.
-- A temporary scratch buffer is always removed and the original buffer restored.
-- No indentation options or plugin source are changed.

local api = vim.api
local fn = vim.fn
local original_buf = api.nvim_get_current_buf()
local original_win = api.nvim_get_current_win()
local report = {}
local scratch

local function add(label, value)
  report[#report + 1] = label .. ": " .. tostring(value)
end

local function inspect(value)
  return vim.inspect(value, { newline = "\n", indent = "  " })
end

local function mode()
  return api.nvim_get_mode().mode
end

local function assert_insert(stage)
  local current = mode()
  if current:sub(1, 1) ~= "i" then
    error(stage .. ": expected Insert mode, got mode " .. inspect(current))
  end
end

local function wait_for(predicate, description, timeout)
  local ok = vim.wait(timeout or 1500, predicate, 10)
  if not ok then
    error("Timed out waiting for " .. description .. "; mode=" .. inspect(mode()))
  end
end

local function settle(stage)
  wait_for(function()
    return mode():sub(1, 1) == "i"
  end, stage .. " to remain in Insert mode")
  vim.wait(100)
  assert_insert(stage .. " after settling")
end

local function input(keys, stage)
  assert_insert("before " .. stage)
  local accepted = api.nvim_input(keys)
  add("nvim_input bytes (" .. stage .. ")", accepted)
  settle(stage)
end

local function snapshot(stage)
  assert_insert("snapshot " .. stage)
  report[#report + 1] = ""
  report[#report + 1] = "===== " .. stage .. " ====="
  local lines = api.nvim_buf_get_lines(scratch, 0, -1, false)
  for index, line in ipairs(lines) do
    report[#report + 1] = string.format("%04d %q", index, line)
  end
  add("mode", mode())
  add("cursor", inspect(api.nvim_win_get_cursor(original_win)))
end

local function safe_option(name)
  local ok, value = pcall(api.nvim_get_option_value, name, { buf = scratch })
  return ok and value or ("<unavailable: " .. tostring(value) .. ">")
end

local function return_and_check(expected_lines, label)
  input("\r", label)
  wait_for(function()
    return #api.nvim_buf_get_lines(scratch, 0, -1, false) >= expected_lines
  end, label .. " to create line " .. expected_lines)
  settle(label .. " after line creation")
  snapshot(label)
end

local function type_and_check(payload, line_number, label)
  input(payload, label)
  wait_for(function()
    local line = api.nvim_buf_get_lines(scratch, line_number - 1, line_number, false)[1] or ""
    return line:find(payload, 1, true) ~= nil
  end, label .. " to appear on line " .. line_number)
  settle(label .. " after payload")
  snapshot(label)
end

local function run()
  scratch = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(original_win, scratch)
  api.nvim_buf_set_lines(scratch, 0, -1, false, {
    "# nvim-heredoc Return trace",
    "conf_print_test() {",
    "  cat <<-'TRACE'",
  })
  vim.bo[scratch].filetype = "sh"
  vim.wait(150)

  report[#report + 1] = "nvim-heredoc configured Return trace"
  add("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
  add("nvim_version", inspect(vim.version()))
  add("scratch_filetype", vim.bo[scratch].filetype)
  add("plugin_attached", inspect(vim.b[scratch].nvim_heredoc_attached))
  for _, name in ipairs({
    "expandtab", "tabstop", "softtabstop", "shiftwidth", "autoindent",
    "smartindent", "cindent", "indentexpr", "indentkeys", "formatoptions",
  }) do
    add(name, inspect(safe_option(name)))
  end

  local cr_maps = {}
  for _, map in ipairs(api.nvim_get_keymap("i")) do
    if map.lhs == "<CR>" or map.lhs == "<Enter>" then
      cr_maps[#cr_maps + 1] = map
    end
  end
  for _, map in ipairs(api.nvim_buf_get_keymap(scratch, "i")) do
    if map.lhs == "<CR>" or map.lhs == "<Enter>" then
      cr_maps[#cr_maps + 1] = map
    end
  end
  add("Insert Return mappings", inspect(cr_maps))

  -- Position at the opener's end, then enter Insert mode through real input.
  api.nvim_win_set_cursor(original_win, { 3, #"  cat <<-'TRACE'" })
  api.nvim_input("i")
  wait_for(function()
    return mode():sub(1, 1) == "i"
  end, "Insert mode entry")
  settle("Insert mode entry")
  snapshot("before first Return")

  return_and_check(4, "after first Return (first body line)")
  type_and_check("hello1", 4, "after typing first payload")
  return_and_check(5, "after second Return (new body line)")
  type_and_check("hello2", 5, "after typing second payload")
  return_and_check(6, "after third Return (new body line)")
  type_and_check("hello3", 6, "after typing third payload")
  return_and_check(7, "after fourth Return (new body line)")
  type_and_check("hello4", 7, "after typing fourth payload")
end

local ok, err = xpcall(run, debug.traceback)

-- Cleanup is unconditional, including when an assertion or input step fails.
pcall(function()
  if api.nvim_get_current_win() == original_win and mode():sub(1, 1) == "i" then
    vim.cmd("stopinsert")
  end
end)
pcall(function()
  if api.nvim_win_is_valid(original_win) and api.nvim_buf_is_valid(original_buf) then
    api.nvim_win_set_buf(original_win, original_buf)
  end
end)
pcall(function()
  if scratch and api.nvim_buf_is_valid(scratch) then
    api.nvim_buf_delete(scratch, { force = true })
  end
end)

report[#report + 1] = ""
add("trace_result", ok and "PASS" or "ABORTED")
if not ok then
  add("trace_error", err)
end

local path = fn.stdpath("state") .. "/nvim-heredoc-return-trace.txt"
local write_ok, write_err = pcall(fn.writefile, report, path)
if not write_ok then
  vim.notify("nvim-heredoc trace could not write report: " .. tostring(write_err), vim.log.levels.ERROR)
elseif ok then
  vim.notify("nvim-heredoc Return trace written to " .. path, vim.log.levels.INFO)
else
  vim.notify("nvim-heredoc trace aborted; diagnostic report written to " .. path, vim.log.levels.ERROR)
end
