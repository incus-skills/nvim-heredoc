package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function defer(fn, delay)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, delay or 20)
end

local function wait_for(buf, predicate, message)
  assert(vim.wait(1000, predicate, 10), message .. "; lines=" .. vim.inspect(lines(buf)))
end

local function assert_insert_mode(message)
  assert(vim.api.nvim_get_mode().mode == "i",
    message .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
end

-- Match the plugin coexistence fixture: real mini.pairs and Blink setup are
-- active alongside the provisioned heredoc ftplugin.
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
local blink_config = require("blink.cmp.config")
assert(vim.wait(10000, function()
  return package.loaded["blink.cmp.fuzzy"] ~= nil
end, 20), "blink.cmp did not finish initialising")
assert(blink_config.enabled(), "Blink should remain enabled during live input")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\tcat <<-LIVE" })
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 2
vim.bo[buf].autoindent = false
vim.bo[buf].smartindent = false
vim.bo[buf].cindent = false
vim.bo[buf].indentexpr = ""
vim.bo[buf].formatoptions = ""
vim.api.nvim_set_current_buf(buf)
dofile("tests/fixtures/provisioned/after/ftplugin/bash.lua")
assert(vim.b[buf].nvim_heredoc_attached == true,
  "provisioned Bash ftplugin did not attach")

-- Observe the buffer at the exact point before the first payload character
-- after a subsequent Enter is inserted. This distinguishes a prefix that is
-- ready for the next keystroke from one repaired later by a deferred wait.
local prefix_before_next_payload = nil
vim.api.nvim_create_autocmd("InsertCharPre", {
  buffer = buf,
  callback = function()
    if vim.v.char == "s" and prefix_before_next_payload == nil then
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      prefix_before_next_payload = line:sub(1, 1) == "\t"
    end
  end,
})

vim.api.nvim_win_set_cursor(0, { 1, #("\tcat <<-LIVE") })
vim.api.nvim_input("A\n")

defer(function()
  local actual = lines(buf)
  assert(actual[2] == "\t" and actual[3] == "\tLIVE",
    "LazyVim: Enter should create the first body prefix and reserve the closer; lines="
      .. vim.inspect(actual))
  assert_insert_mode("LazyVim: first Enter must remain in Insert mode")

  vim.api.nvim_input("typed")
  defer(function()
    actual = lines(buf)
    assert(actual[2] == "\ttyped",
      "LazyVim: first payload should follow the structural TAB; lines=" .. vim.inspect(actual))
    assert_insert_mode("LazyVim: typing first payload must remain in Insert mode")

    vim.api.nvim_input("\n")
    -- Give Neovim one short input-loop turn, not the test's normal 20 ms
    -- settling interval, before delivering the next user keystroke.
    defer(function()
      vim.api.nvim_input("s")
      defer(function()
        assert(prefix_before_next_payload == true,
          "LazyVim: the new body line must already have its structural TAB at InsertCharPre")
        actual = lines(buf)
        assert(actual[3] == "\ts",
          "LazyVim: first character after Enter must follow the structural TAB; lines="
            .. vim.inspect(actual))
        assert_insert_mode("LazyVim: subsequent Enter and first payload must remain in Insert mode")

        vim.api.nvim_input("econd")
        defer(function()
          actual = lines(buf)
          assert(actual[3] == "\tsecond",
            "LazyVim: second payload must follow the structural TAB; lines=" .. vim.inspect(actual))

          vim.api.nvim_input("\n")
          defer(function()
            wait_for(buf, function() return lines(buf)[4] == "\t" end,
              "LazyVim: next body line must be prefixed before paste")

            assert(vim.api.nvim_paste("  pasted one\n    pasted two", false, -1),
              "LazyVim: Neovim rejected the multi-line paste")
            defer(function()
              wait_for(buf, function()
                actual = lines(buf)
                return actual[4] == "\t  pasted one"
                  and actual[5] == "\t    pasted two"
                  and actual[6] == "\tLIVE"
              end, "LazyVim: multi-line paste must be prefixed before InsertLeave")
              assert_insert_mode("LazyVim: paste processing must remain in Insert mode")

              vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
              defer(function()
                actual = lines(buf)
                assert(vim.api.nvim_get_mode().mode ~= "i", "LazyVim: Escape should leave Insert mode")
                assert(actual[2] == "\ttyped" and actual[3] == "\tsecond"
                  and actual[4] == "\t  pasted one" and actual[5] == "\t    pasted two"
                  and actual[6] == "\tLIVE",
                  "LazyVim: InsertLeave must not be required to repair indentation; lines="
                    .. vim.inspect(actual))
                print("LazyVim live Insert-mode tests: PASS")
                vim.cmd("qa!")
              end)
            end)
          end)
        end)
      end)
    end, 1)
  end)
end)
