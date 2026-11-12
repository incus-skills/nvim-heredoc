package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, 20)
end

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\tcat <<-LIVE" })
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 2
vim.api.nvim_set_current_buf(buf)
plugin.setup()

-- nvim_input queues keys for Neovim's normal input loop. Unlike feedkeys(...,
-- "x"), it does not drain the whole sequence inside this synchronous Lua
-- command and accidentally turn the test into a Normal-mode observation.
vim.api.nvim_win_set_cursor(0, { 1, #("\tcat <<-LIVE") })
vim.api.nvim_input("A\n")

defer(function()
  local actual = lines(buf)
  assert(actual[2] == "\t" and actual[3] == "\tLIVE",
    "Enter should create the body prefix and reserve the closer before InsertLeave; lines="
      .. vim.inspect(actual))
  assert(vim.api.nvim_get_mode().mode == "i",
    "the Enter transition must still be in Insert mode; mode="
      .. vim.inspect(vim.api.nvim_get_mode()))

  -- Type through Neovim's input loop, then allow scheduled on_lines work to
  -- run before observing the buffer. This verifies live typing, not InsertLeave
  -- or save-time formatting.
  vim.api.nvim_input("typed")
  defer(function()
    actual = lines(buf)
    assert(actual[2] == "\ttyped",
      "typed body text must retain TAB before payload while still in Insert mode; lines="
        .. vim.inspect(actual))
    assert(vim.api.nvim_get_mode().mode == "i",
      "live body indentation must not leave Insert mode; mode="
        .. vim.inspect(vim.api.nvim_get_mode()))

    vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
    defer(function()
      assert(vim.api.nvim_get_mode().mode ~= "i", "Escape should leave Insert mode")

      vim.api.nvim_buf_set_lines(buf, 1, 2, false, {
        "  pasted one",
        "    pasted two",
        "",
      })
      assert(vim.wait(1000, function()
        actual = lines(buf)
        return actual[2] == "\t  pasted one"
          and actual[3] == "\t    pasted two"
          and actual[4] == "\t"
      end, 10), "multi-line paste should receive structural TABs without changing payload indentation; lines="
        .. vim.inspect(lines(buf)))
      actual = lines(buf)
      assert(actual[5] == "\tLIVE", "paste processing must preserve the reserved closer")

      print("live Insert-mode buffer tests: PASS")
      vim.cmd("qa!")
    end)
  end)
end)
