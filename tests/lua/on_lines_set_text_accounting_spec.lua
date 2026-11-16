package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function private_upvalue(target)
  for index = 1, 32 do
    local name, value = debug.getupvalue(plugin.process_buffer, index)
    if not name then break end
    if name == target then return value end
  end
  error("could not inspect private upvalue " .. target)
end

local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sh"
  vim.bo[buf].tabstop = 2
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].expandtab = false
  return buf
end

local buf = make_buffer({
  "cat <<-EOF",
  "payload",
  "EOF",
  "after",
})
vim.api.nvim_set_current_buf(buf)
assert(plugin.setup_buffer(buf), "plugin failed to attach")

local processing = private_upvalue("processing")
local tracked = { row = 3, valid = true, events = {} }

vim.api.nvim_buf_attach(buf, false, {
  on_lines = function(_, changed_buf, changedtick, firstline, lastline, new_lastline)
    local event = {
      changedtick = changedtick,
      firstline = firstline,
      lastline = lastline,
      new_lastline = new_lastline,
      processing = processing[changed_buf] == true,
    }
    tracked.events[#tracked.events + 1] = event

    if not tracked.valid then return end
    local delta = new_lastline - lastline
    if tracked.row < firstline then
      -- The edit is after the tracked source row.
    elseif tracked.row >= lastline then
      tracked.row = tracked.row + delta
    else
      tracked.valid = false
    end
  end,
})

-- The complete standalone <<- heredoc is already present. Processing its
-- body takes prefix_region_range(), whose ordinary nonblank-line path uses
-- nvim_buf_set_text() to insert the managed TAB prefix.
assert(plugin.process_buffer(buf), "processing should prefix the heredoc body")

local actual = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(actual[2] == "\tpayload",
  "the production prefix path should insert a literal TAB with nvim_buf_set_text")
assert(actual[4] == "after", "the following source line must remain unchanged")
assert(tracked.valid and tracked.row == 3,
  "same-line text insertion must preserve the following source-row identity")

local plugin_events = {}
for _, event in ipairs(tracked.events) do
  if event.processing then
    plugin_events[#plugin_events + 1] = event
  end
end
assert(#plugin_events >= 1,
  "the plugin-generated nvim_buf_set_text mutation must reach on_lines while processing")
assert(plugin_events[1].firstline == 1
  and plugin_events[1].lastline == 2
  and plugin_events[1].new_lastline == 2,
  "same-line prefix insertion should report the expected zero-based on_lines range")

vim.api.nvim_buf_delete(buf, { force = true })

print("on_lines nvim_buf_set_text accounting characterization: PASS")
vim.cmd("qa!")
