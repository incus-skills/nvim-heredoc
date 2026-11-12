package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local plugin = require("nvim-heredoc")
require("mini.pairs").setup({
  modes = { insert = true, command = true, terminal = false },
  skip_ts = { "string" },
  skip_unbalanced = true,
  markdown = true,
})
require("blink.cmp").setup({
  sources = { default = { "buffer" } },
  completion = { menu = { auto_show = false } },
})
assert(vim.wait(10000, function()
  return package.loaded["blink.cmp.fuzzy"] ~= nil
end, 20), "blink.cmp did not finish initialising for negative control")
dofile("tests/fixtures/provisioned/after/ftplugin/bash.lua")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "cat <<EOF",
  "ordinary payload",
  "EOF",
})
vim.bo[buf].filetype = "bash"
vim.api.nvim_set_current_buf(buf)
-- Deliberately expect the plugin to edit an ordinary heredoc. This must fail.
assert(plugin.process_buffer(buf),
  "NEGATIVE_CONTROL: ordinary heredoc was unexpectedly left unchanged")
