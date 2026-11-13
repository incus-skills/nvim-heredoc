package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  cat <<-LIVE" })
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

local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function fail(message)
  print(message .. "; lines=" .. vim.inspect(lines()))
  vim.cmd("cquit 1")
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then fail(err) end
  end, 20)
end

local function wait_for(predicate, message)
  if not vim.wait(1000, predicate, 10) then
    fail(message)
  end
end

vim.api.nvim_win_set_cursor(0, { 1, #"  cat <<-LIVE" })
vim.api.nvim_input("A\n")

defer(function()
  wait_for(function()
    local actual = lines()
    return actual[2] == "\t" and actual[3] == "\tLIVE"
  end, "first Return must replace copied two-space autoindent with a structural TAB")
  assert(vim.api.nvim_get_mode().mode == "i", "first Return must remain in Insert mode")

  vim.api.nvim_input("typed")
  defer(function()
    local actual = lines()
    assert(actual[2] == "\ttyped",
      "typed payload must follow the structural TAB without leaked opener spaces")
    vim.api.nvim_input("\n")
    defer(function()
      wait_for(function()
        return lines()[3] == "\t"
      end, "subsequent body line must retain the structural TAB")
      vim.api.nvim_input("second")
      defer(function()
        assert(lines()[3] == "\tsecond",
          "second payload must follow the structural TAB")
        vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
        defer(function()
          local actual = lines()
          assert(actual[1] == "  cat <<-LIVE")
          assert(actual[2] == "\ttyped")
          assert(actual[3] == "\tsecond")
          assert(actual[4] == "\tLIVE")
          print("space-indented live Insert-mode tests: PASS")
          vim.cmd("qa!")
        end)
      end)
    end)
  end)
end)
