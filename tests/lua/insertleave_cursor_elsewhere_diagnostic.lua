package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api
local buf = api.nvim_create_buf(true, false)

-- The first managed heredoc is complete but deliberately unformatted. The
-- second opener is incomplete and predates this InsertLeave event.
api.nvim_buf_set_lines(buf, 0, -1, false, {
  "\tcat <<-COMPLETE",
  "payload",
  "\tCOMPLETE",
  "cat <<-PENDING",
  "",
})
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
end, 10), "nvim-heredoc did not attach to the diagnostic buffer")

-- Put the cursor in the complete, unrelated heredoc, not near the pending
-- opener. InsertLeave is fired without changing either region.
api.nvim_win_set_cursor(0, { 2, 0 })
api.nvim_exec_autocmds("InsertLeave", { buffer = buf })

local actual = api.nvim_buf_get_lines(buf, 0, -1, false)
print("===== InsertLeave cursor-elsewhere diagnostic =====")
for index, line in ipairs(actual) do
  print(string.format("%02d %q", index, line))
end

-- These assertions characterize the current broad callback, not the desired
-- recovery contract: the later incomplete region is closed at EOF, and the
-- earlier complete region is formatted despite the cursor being inside it.
assert(actual[2] == "\t\tpayload",
  "current InsertLeave processing should expose whole-buffer formatting of the unrelated complete region; lines="
    .. vim.inspect(actual))
assert(actual[#actual] == "PENDING",
  "current InsertLeave fallback should append the pending closer at EOF; lines="
    .. vim.inspect(actual))

print("InsertLeave cursor-elsewhere diagnostic: PASS (current cross-region effects characterised)")
vim.cmd("qa!")
