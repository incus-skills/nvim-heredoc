package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api
local buf = api.nvim_create_buf(true, false)

api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
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

local function lines()
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      print(err)
      vim.cmd("cquit 1")
    end
  end, 20)
end

-- Type a managed opener during this Insert session, but deliberately do not
-- press Return. The opener therefore has no Return-created body/closer.
api.nvim_input("icat <<-SESSION_ONLY")
defer(function()
  assert(vim.api.nvim_get_mode().mode == "i",
    "typing the incomplete opener should leave Neovim in Insert mode")
  local before_leave = lines()
  assert(#before_leave == 1 and before_leave[1] == "cat <<-SESSION_ONLY",
    "the opener should be present without a body or closer; lines=" .. vim.inspect(before_leave))

  api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
  defer(function()
    assert(vim.api.nvim_get_mode().mode ~= "i", "Escape should trigger InsertLeave")
    -- Let the InsertLeave callback and its synchronous buffer processing settle.
    vim.wait(100, function() return false end, 10)
    local after_leave = lines()
    print("===== InsertLeave cross-over diagnostic =====")
    for index, line in ipairs(after_leave) do
      print(string.format("%02d %q", index, line))
    end

    assert(#after_leave == 2 and after_leave[1] == "cat <<-SESSION_ONLY"
      and after_leave[2] == "SESSION_ONLY",
      "expected InsertLeave to append the closer to an opener typed in this session; lines="
        .. vim.inspect(after_leave))

    print("InsertLeave cross-over diagnostic: newly typed incomplete opener was closed without Return")
    print("InsertLeave cross-over diagnostic: PASS (observed behavior characterised)")
    vim.cmd("qa!")
  end)
end)
