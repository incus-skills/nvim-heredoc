package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api

local buf = api.nvim_create_buf(true, false)
local original = {
  "printf '%s\\n' \"",
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

-- Open a line inside the multiline double-quoted string, type the
-- opener-looking text, and deliver Return in one uninterrupted input batch.
-- The initial "o" is the mode-entry keycode; explicit CR is the tested key.
api.nvim_win_set_cursor(0, { 1, #original[1] })
api.nvim_input("ocat <<-EOF\r")

local expected = {
  original[1],
  "cat <<-EOF",
  "",
  original[2],
}
assert(vim.wait(1000, function()
  local actual = api.nvim_buf_get_lines(buf, 0, -1, false)
  return #actual == #expected
    and actual[1] == expected[1]
    and actual[2] == expected[2]
    and actual[3] == expected[3]
    and actual[4] == expected[4]
end, 10),
  "Return inside an unterminated double-quoted string must not create a heredoc scope; lines="
    .. vim.inspect(api.nvim_buf_get_lines(buf, 0, -1, false)))

local actual = api.nvim_buf_get_lines(buf, 0, -1, false)
assert(actual[1] == expected[1] and actual[2] == expected[2]
  and actual[3] == expected[3] and actual[4] == expected[4],
  "Return should be delegated as ordinary Insert-mode Return inside quoted text; lines="
    .. vim.inspect(actual))
assert(api.nvim_get_mode().mode == "i",
  "ordinary Return inside quoted text should leave the editor in Insert mode")

print("live Return quoted-context diagnostic: PASS")
vim.cmd("qa!")
