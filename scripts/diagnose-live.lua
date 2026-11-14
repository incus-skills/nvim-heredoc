-- Live environment diagnostic for incus-skills/nvim-heredoc.
-- Run from the affected Neovim instance with:
--   :luafile /path/to/nvim-heredoc/scripts/diagnose-live.lua
--
-- This script is read-only with respect to the current buffer. It records the
-- current buffer, local editing options, relevant mappings/autocmds, plugin
-- load/attach state, and runtime environment to a report under stdpath("state").

local api = vim.api
local fn = vim.fn
local current_buf = api.nvim_get_current_buf()
local current_win = api.nvim_get_current_win()
local report = {}

local function add(label, value)
  report[#report + 1] = label .. ": " .. tostring(value)
end

local function section(name)
  report[#report + 1] = ""
  report[#report + 1] = "===== " .. name .. " ====="
end

local function inspect(value)
  return vim.inspect(value, { newline = "\n", indent = "  " })
end

local function safe_option(name, scope)
  local ok, value = pcall(api.nvim_get_option_value, name, scope)
  if ok then
    return value
  end
  return "<unavailable: " .. tostring(value) .. ">"
end

local function source_of(module)
  local ok, value = pcall(require, module)
  if not ok then
    return nil, tostring(value)
  end
  local info
  if type(value) == "table" and type(value.setup) == "function" then
    info = debug.getinfo(value.setup, "S")
  elseif type(value) == "table" and type(value.process_buffer) == "function" then
    info = debug.getinfo(value.process_buffer, "S")
  end
  return value, info and info.source or "<loaded; source unavailable>"
end

section("Runtime")
add("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
add("nvim_version", inspect(vim.version()))
add("nvim_executable", fn.exepath("nvim"))
add("v:progpath", vim.v.progpath)
add("cwd", fn.getcwd())
add("config", fn.stdpath("config"))
add("data", fn.stdpath("data"))
add("state", fn.stdpath("state"))
add("runtimepath", inspect(vim.opt.runtimepath:get()))
add("packpath", inspect(vim.opt.packpath:get()))

section("Current buffer")
add("buffer", current_buf)
add("name", api.nvim_buf_get_name(current_buf))
add("filetype", safe_option("filetype", { buf = current_buf }))
add("buftype", safe_option("buftype", { buf = current_buf }))
add("modifiable", safe_option("modifiable", { buf = current_buf }))
add("modified", safe_option("modified", { buf = current_buf }))
add("cursor", inspect(api.nvim_win_get_cursor(current_win)))
add("mode", inspect(api.nvim_get_mode()))
add("line_count", api.nvim_buf_line_count(current_buf))
add("lines (Lua %q preserves TAB/space distinctions)", "")
for row, line in ipairs(api.nvim_buf_get_lines(current_buf, 0, -1, false)) do
  report[#report + 1] = string.format("%04d %q", row, line)
end

section("Indentation and editing options")
local option_names = {
  "expandtab", "tabstop", "softtabstop", "shiftwidth", "smarttab",
  "autoindent", "smartindent", "cindent", "indentexpr", "indentkeys",
  "copyindent", "preserveindent", "shiftround", "formatoptions",
  "paste", "textwidth", "wrap", "filetype", "commentstring",
}
for _, name in ipairs(option_names) do
  add(name, inspect(safe_option(name, { buf = current_buf })))
end

section("Relevant mappings")
local function relevant_mapping(map)
  local lhs = tostring(map.lhs or "")
  return lhs == "<CR>" or lhs == "<Enter>" or lhs == "<Tab>"
    or lhs == "<S-Tab>" or lhs == "<C-J>" or lhs == "<C-M>"
    or lhs:find("CR", 1, true) ~= nil
end
for _, mode in ipairs({ "i", "n", "s" }) do
  local maps = {}
  for _, map in ipairs(api.nvim_get_keymap(mode)) do
    if relevant_mapping(map) then
      maps[#maps + 1] = map
    end
  end
  for _, map in ipairs(api.nvim_buf_get_keymap(current_buf, mode)) do
    if relevant_mapping(map) then
      maps[#maps + 1] = map
    end
  end
  add("mode " .. mode, inspect(maps))
end

section("Autocmds for current buffer")
local autocmd_ok, autocmds = pcall(api.nvim_get_autocmds, { buffer = current_buf })
if autocmd_ok then
  local selected = {}
  for _, autocmd in ipairs(autocmds) do
    local event = tostring(autocmd.event or "")
    local group = tostring(autocmd.group_name or "")
    if event:match("Insert") or event:match("TextChanged") or event == "FileType"
      or group:match("Heredoc") or group:match("Lazy") then
      selected[#selected + 1] = autocmd
    end
  end
  add("selected autocmds", inspect(selected))
else
  add("autocmd query error", autocmds)
end

section("nvim-heredoc module and attachment state")
local plugin, plugin_source = source_of("nvim-heredoc")
add("require('nvim-heredoc')", plugin and "loaded" or "not loaded")
add("plugin source", plugin_source)
local scanner, scanner_source = source_of("nvim-heredoc.scanner")
add("scanner module", scanner and "loaded" or "not loaded")
add("scanner source", scanner_source)
local editing, editing_source = source_of("nvim-heredoc.editing")
add("editing module", editing and "loaded" or "not loaded")
add("editing source", editing_source)
add("b:nvim_heredoc_attached", inspect(vim.b[current_buf].nvim_heredoc_attached))
add("package.loaded modules", inspect({
  ["nvim-heredoc"] = package.loaded["nvim-heredoc"] ~= nil,
  ["nvim-heredoc.scanner"] = package.loaded["nvim-heredoc.scanner"] ~= nil,
  ["nvim-heredoc.editing"] = package.loaded["nvim-heredoc.editing"] ~= nil,
}))

local lazy_ok, lazy_config = pcall(require, "lazy.core.config")
if lazy_ok and lazy_config.plugins then
  local entry = lazy_config.plugins["nvim-heredoc"]
  add("lazy plugin entry", inspect(entry and {
    dir = entry.dir,
    url = entry.url,
    name = entry.name,
    branch = entry.branch,
    commit = entry.commit,
    version = entry.version,
    lazy = entry.lazy,
    event = entry.event,
    ft = entry.ft,
  } or "<not found in lazy.core.config.plugins>"))
else
  add("lazy plugin config", "<unavailable>")
end

section("Environment")
local env_names = {
  "NVIM_APPNAME", "VIMRUNTIME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
  "XDG_STATE_HOME", "TERM", "SHELL",
}
for _, name in ipairs(env_names) do
  add(name, inspect(vim.env[name]))
end

local output = table.concat(report, "\n") .. "\n"
local path = fn.stdpath("state") .. "/nvim-heredoc-live-diagnostic.txt"
local ok, err = pcall(fn.writefile, vim.split(output, "\n", { plain = true }), path)
if not ok then
  vim.notify("nvim-heredoc diagnostic could not write report: " .. tostring(err), vim.log.levels.ERROR)
  return
end

vim.notify("nvim-heredoc diagnostic written to " .. path, vim.log.levels.INFO)
