-- Trace successive Return operations in the user's configured Neovim.
--
-- Run inside the affected Neovim instance:
--   :luafile /path/to/nvim-heredoc/scripts/trace-return.lua
--
-- This creates a temporary scratch buffer and exercises the configured Insert
-- <CR> mapping. It does not change indentation options or plugin source. Each
-- stage records literal buffer bytes (%q), mode, cursor, and relevant options.
-- The original buffer is restored after the trace.

local api = vim.api
local fn = vim.fn
local original_buf = api.nvim_get_current_buf()
local original_win = api.nvim_get_current_win()
local report = {}

local function add(label, value)
  report[#report + 1] = label .. ": " .. tostring(value)
end

local function inspect(value)
  return vim.inspect(value, { newline = "\n", indent = "  " })
end

local function snapshot(stage, buf)
  report[#report + 1] = ""
  report[#report + 1] = "===== " .. stage .. " ====="
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    report[#report + 1] = string.format("%04d %q", index, line)
  end
  add("mode", api.nvim_get_mode().mode)
  add("cursor", inspect(api.nvim_win_get_cursor(0)))
end

local function feed(keys)
  api.nvim_feedkeys(fn.replace_termcodes(keys, true, false, true), "mtx", false)
  vim.wait(40)
end

local function safe_option(name, scope)
  local ok, value = pcall(api.nvim_get_option_value, name, scope)
  return ok and value or ("<unavailable: " .. tostring(value) .. ">")
end

local scratch = api.nvim_create_buf(false, true)
api.nvim_win_set_buf(original_win, scratch)
api.nvim_buf_set_lines(scratch, 0, -1, false, {
  "# nvim-heredoc Return trace",
  "conf_print_test() {",
  "  cat <<-'TRACE'",
})
vim.bo[scratch].filetype = "sh"
vim.wait(100)

report[#report + 1] = "nvim-heredoc configured Return trace"
add("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
add("nvim_version", inspect(vim.version()))
add("scratch_filetype", vim.bo[scratch].filetype)
add("plugin_attached", inspect(vim.b[scratch].nvim_heredoc_attached))
for _, name in ipairs({
  "expandtab", "tabstop", "softtabstop", "shiftwidth", "autoindent",
  "smartindent", "cindent", "indentexpr", "indentkeys", "formatoptions",
}) do
  add(name, inspect(safe_option(name, { buf = scratch })))
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

-- Start at the end of the heredoc opener. The first Return creates the first
-- body line; later Returns should preserve that line's leading indentation.
api.nvim_win_set_cursor(original_win, { 3, # "  cat <<-'TRACE'" })
vim.cmd("startinsert")
vim.wait(40)
snapshot("before first Return", scratch)

feed("<CR>")
snapshot("after first Return (first body line)", scratch)

feed("hello1")
snapshot("after typing first payload", scratch)

feed("<CR>")
snapshot("after second Return (new body line)", scratch)

feed("hello2")
snapshot("after typing second payload", scratch)

feed("<CR>")
snapshot("after third Return (new body line)", scratch)

feed("hello3")
snapshot("after typing third payload", scratch)

feed("<CR>")
snapshot("after fourth Return (new body line)", scratch)

feed("hello4")
snapshot("after typing fourth payload", scratch)

-- Leave the scratch buffer intact for inspection but restore the user's
-- original buffer/window so this diagnostic does not displace their work.
vim.cmd("stopinsert")
api.nvim_win_set_buf(original_win, original_buf)

local path = fn.stdpath("state") .. "/nvim-heredoc-return-trace.txt"
local ok, err = pcall(fn.writefile, report, path)
if not ok then
  vim.notify("nvim-heredoc trace could not write report: " .. tostring(err), vim.log.levels.ERROR)
  return
end

vim.notify("nvim-heredoc Return trace written to " .. path, vim.log.levels.INFO)
