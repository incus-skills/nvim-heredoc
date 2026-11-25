package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api

local buf = api.nvim_create_buf(true, false)
local original = {
  "printf '%s\\n' \"",
  "cat <<-EOF",
  "\"",
}
api.nvim_buf_set_lines(buf, 0, -1, false, original)
api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 0
vim.bo[buf].autoindent = false
vim.bo[buf].smartindent = false
vim.bo[buf].cindent = false
vim.bo[buf].indentexpr = ""
vim.bo[buf].formatoptions = ""

plugin.setup()
assert(vim.wait(1000, function()
  return vim.b[buf].nvim_heredoc_attached == true
end, 10), "nvim-heredoc did not attach to the quoted shell buffer")

api.nvim_win_set_cursor(0, { 2, #original[2] })
api.nvim_input("A")
assert(vim.wait(1000, function()
  return api.nvim_get_mode().mode == "i"
end, 10), "could not enter Insert mode at the end of the quoted line")

api.nvim_input(api.nvim_replace_termcodes("<CR>", true, false, true))
assert(vim.wait(1000, function()
  return #api.nvim_buf_get_lines(buf, 0, -1, false) >= 4
end, 10), "Insert-mode Return did not create the expected new physical line")

-- Allow the registered on_lines/deferred path to run before inspecting the
-- final result. The test is about Return eligibility, not callback timing.
vim.wait(250, function() return false end, 10)

local actual = api.nvim_buf_get_lines(buf, 0, -1, false)
assert(#actual == 4,
  "Return inside an unterminated double-quoted string must not create a heredoc scope; lines="
    .. vim.inspect(actual))
assert(actual[1] == original[1] and actual[2] == original[2]
  and actual[3] == "" and actual[4] == original[3],
  "Return should be delegated as ordinary Insert-mode Return inside quoted text; lines="
    .. vim.inspect(actual))
assert(api.nvim_get_mode().mode == "i",
  "ordinary Return inside quoted text should leave the editor in Insert mode")

print("live Return quoted-context diagnostic: PASS")
vim.cmd("qa!")
