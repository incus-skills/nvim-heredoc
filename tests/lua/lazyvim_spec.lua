package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function set_buffer(source, filetype)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(source, "\n", { plain = true }))
  vim.bo[buf].filetype = filetype
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function shell_output(source)
  local output = vim.fn.system({ "bash" }, source .. (source:sub(-1) == "\n" and "" or "\n"))
  assert(vim.v.shell_error == 0, "bash fixture failed: " .. output)
  return output
end

-- These options mirror the mini.pairs defaults supplied by the observed
-- LazyVim coding.lua revision. The legacy after/ftplugin files are not loaded.
require("mini.pairs").setup({
  modes = { insert = true, command = true, terminal = false },
  skip_ts = { "string" },
  skip_unbalanced = true,
  markdown = true,
})

assert(vim.fn.maparg('"', "i") ~= "", "mini.pairs quote mapping should remain active")
assert(vim.b.minipairs_disable ~= true, "mini.pairs must not be disabled in the fixture")

-- Blink is loaded with its normal fuzzy implementation and buffer source.
-- This keeps the installed plugin's default completion path under test.
require("blink.cmp").setup({
  sources = { default = { "buffer" } },
  completion = { menu = { auto_show = false } },
})
local blink_config = require("blink.cmp.config")
assert(vim.wait(10000, function()
  return package.loaded["blink.cmp.fuzzy"] ~= nil
end, 20), "blink.cmp did not finish initialising")
assert(blink_config.enabled(), "blink.cmp should remain enabled by default")
assert(vim.b.completion == nil, "the fixture must not inject a buffer-wide completion override")

-- Conform is configured as observed: shfmt for Bash and POSIX sh only.
-- No format_on_save callback is installed; the test invokes formatting explicitly.
local conform = require("conform")
conform.setup({
  formatters_by_ft = {
    bash = { "shfmt" },
    sh = { "shfmt" },
  },
  formatters = {
    shfmt = {
      prepend_args = { "-i", "0", "-p" },
    },
  },
})
assert(conform.list_formatters_for_buffer(0)[1] == "shfmt", "Bash should resolve to shfmt")
local zsh = set_buffer("print -r -- ok", "zsh")
assert(#conform.list_formatters_for_buffer(zsh) == 0, "Zsh must not resolve to shfmt")

plugin.setup()

-- Managed heredoc: scanner editing remains safe while pair/completion plugins
-- are active in the same buffer.
local managed_source = table.concat({
  "if true; then",
  "\tcat <<-EOF",
  "\t  payload with two leading spaces",
  "\tEOF",
  "fi",
}, "\n")
local managed = set_buffer(managed_source, "bash")
assert(vim.fn.maparg('"', "i") ~= "", "mini.pairs mapping disappeared in managed buffer")
assert(blink_config.enabled(), "completion unexpectedly disabled in managed buffer")
local managed_before = shell_output(table.concat(lines(managed), "\n"))
assert(plugin.process_buffer(managed) == false, "already structured managed heredoc should be idempotent")
local managed_after = shell_output(table.concat(lines(managed), "\n"))
assert(managed_before == managed_after, "plugin processing changed the managed heredoc payload")

-- Ordinary heredoc is a non-managed control and must remain byte-for-byte intact.
local ordinary_source = table.concat({
  "cat <<EOF",
  "  ordinary payload",
  "EOF",
}, "\n")
local ordinary = set_buffer(ordinary_source, "bash")
assert(plugin.process_buffer(ordinary) == false, "ordinary heredoc must not be edited")
assert(table.concat(lines(ordinary), "\n") == ordinary_source, "ordinary heredoc changed")

-- Exercise Conform's actual formatter path in the same Neovim process.
local format_source = table.concat({
  "if true; then",
  "\tcat <<-EOF",
  "\t  payload with two leading spaces",
  "\t\tleading tab is stripped by the shell",
  "\tEOF",
  "fi",
}, "\n")
local format_buf = set_buffer(format_source, "bash")
local payload_before = shell_output(table.concat(lines(format_buf), "\n"))
assert(conform.format({ buf = format_buf, async = false, lsp_format = "never" }),
  "Conform did not invoke a formatter")
vim.wait(300, function() return false end, 10)
local payload_after = shell_output(table.concat(lines(format_buf), "\n"))
assert(payload_before == payload_after, "Conform/shfmt changed the delivered heredoc payload")

print("LazyVim/plugin coexistence tests: PASS")
