package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local buf = vim.api.nvim_create_buf(true, false)

local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "conf_print_test() {",
  "\tcat <<-'BURST'",
})
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 2
vim.bo[buf].autoindent = true
vim.bo[buf].smartindent = false
vim.bo[buf].cindent = false
vim.bo[buf].indentexpr = ""
vim.bo[buf].formatoptions = ""
vim.api.nvim_set_current_buf(buf)
plugin.setup()

vim.api.nvim_win_set_cursor(0, { 2, #"\tcat <<-'BURST" })
vim.api.nvim_input("A\nhello1\nhello2\nhello3")

vim.defer_fn(function()
  local actual = lines()
  local expected = {
    "conf_print_test() {",
    "\tcat <<-'BURST'",
    "\t\thello1",
    "\t\thello2",
    "\t\thello3",
    "\tBURST",
  }
  assert(vim.deep_equal(actual, expected),
    "rapid successive Returns must not accumulate body TABs; actual="
      .. vim.inspect(actual) .. "; expected=" .. vim.inspect(expected))
  assert(vim.api.nvim_get_mode().mode == "i",
    "burst input must remain in Insert mode until explicitly exited")
  print("rapid TAB-opener autoindent regression test: PASS")
  vim.cmd("qa!")
end, 50)
