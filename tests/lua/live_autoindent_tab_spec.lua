package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local buf = vim.api.nvim_create_buf(true, false)

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

vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "conf_print_test() {",
  "\tcat <<-'LIVE'",
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

vim.api.nvim_win_set_cursor(0, { 2, #"\tcat <<-'LIVE" })
vim.api.nvim_input("A\n")

defer(function()
  wait_for(function()
    local actual = lines()
    return actual[3] == "\t\t" and actual[4] == "\tLIVE"
  end, "first Return must produce one body TAB beyond the opener prefix")
  assert(vim.api.nvim_get_mode().mode == "i", "first Return must remain in Insert mode")

  vim.api.nvim_input("hello1")
  defer(function()
    assert(lines()[3] == "\t\thello1",
      "first payload must have exactly one additional TAB; lines=" .. vim.inspect(lines()))

    vim.api.nvim_input("\n")
    defer(function()
      wait_for(function()
        return lines()[4] == "\t\t"
      end, "second Return must retain exactly the body prefix, not accumulate another TAB")
      vim.api.nvim_input("hello2")
      defer(function()
        assert(lines()[4] == "\t\thello2",
          "second payload must have exactly one additional TAB; lines=" .. vim.inspect(lines()))

        vim.api.nvim_input("\n")
        defer(function()
          wait_for(function()
            return lines()[5] == "\t\t"
          end, "third Return must not accumulate another TAB")
          vim.api.nvim_input("hello3")
          defer(function()
            local actual = lines()
            assert(actual[3] == "\t\thello1")
            assert(actual[4] == "\t\thello2")
            assert(actual[5] == "\t\thello3")
            assert(actual[6] == "\tLIVE")
            vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
            defer(function()
              actual = lines()
              assert(actual[3] == "\t\thello1")
              assert(actual[4] == "\t\thello2")
              assert(actual[5] == "\t\thello3")
              assert(actual[6] == "\tLIVE")
              print("TAB-opener autoindent regression test: PASS")
              vim.cmd("qa!")
            end)
          end)
        end)
      end)
    end)
  end)
end)
