package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local plugin = require("nvim-heredoc")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "cat <<EOF",
  "ordinary payload",
  "EOF",
})
vim.bo[buf].filetype = "bash"
-- Deliberately expect an edit to ordinary <<. That expectation must fail.
assert(plugin.process_buffer(buf),
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged")
