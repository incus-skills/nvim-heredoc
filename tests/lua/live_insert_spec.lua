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

local function assert_insert_mode(message)
  assert(vim.api.nvim_get_mode().mode == "i",
    message .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
end

local buf

local function wait_for(predicate, message)
  assert(vim.wait(1000, predicate, 10), message .. "; lines=" .. vim.inspect(lines(buf)))
end

buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\tcat <<-LIVE" })
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 2
-- Disable Neovim's own indentation so only the plugin can satisfy the
-- structural-prefix assertions after subsequent Enter presses.
vim.bo[buf].autoindent = false
vim.bo[buf].smartindent = false
vim.bo[buf].cindent = false
vim.bo[buf].indentexpr = ""
vim.bo[buf].formatoptions = ""
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
    "Enter should create the first body prefix and reserve the closer; lines="
      .. vim.inspect(actual))
  assert_insert_mode("the first Enter transition must remain in Insert mode")

  vim.api.nvim_input("typed")
  defer(function()
    actual = lines(buf)
    assert(actual[2] == "\ttyped",
      "first body payload should follow the opener's structural TAB; lines="
        .. vim.inspect(actual))
    assert_insert_mode("typing the first payload must remain in Insert mode")

    -- A second Enter creates a genuinely new body line. Wait for the
    -- deferred changed-range processor before typing; this regression guard
    -- checks the existing structural-prefix behaviour without claiming that
    -- the live Insert-mode timing problem is solved.
    vim.api.nvim_input("\n")
    defer(function()
      wait_for(function()
        return lines(buf)[3] == "\t"
      end, "a subsequent body line must receive its structural TAB")
      assert_insert_mode("indentation after Enter must remain in Insert mode")

      vim.api.nvim_input("second")
      defer(function()
        actual = lines(buf)
        assert(actual[3] == "\tsecond",
          "second body payload must follow the structural TAB; lines=" .. vim.inspect(actual))
        assert_insert_mode("typing on the newly indented line must remain in Insert mode")

        vim.api.nvim_input("\n")
        defer(function()
          wait_for(function()
            return lines(buf)[4] == "\t"
          end, "the next body line must be structurally indented before paste")

        -- Exercise Neovim's paste API while still in Insert mode. The
        -- inserted lines begin with spaces; the plugin must prepend only
        -- the structural TAB to each changed line and retain those spaces.
        local pasted = vim.api.nvim_paste("  pasted one\n    pasted two", false, -1)
        assert(pasted, "Neovim rejected the multi-line paste")
        defer(function()
          wait_for(function()
            actual = lines(buf)
            return actual[4] == "\t  pasted one"
              and actual[5] == "\t    pasted two"
              and actual[6] == "\tLIVE"
          end, "multi-line paste must be indented before InsertLeave/save without changing payload bytes")
          assert_insert_mode("live paste processing must remain in Insert mode")

          vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
          defer(function()
            assert(vim.api.nvim_get_mode().mode ~= "i", "Escape should leave Insert mode")
            actual = lines(buf)
            assert(actual[2] == "\ttyped" and actual[3] == "\tsecond"
              and actual[4] == "\t  pasted one" and actual[5] == "\t    pasted two"
              and actual[6] == "\tLIVE",
              "InsertLeave must not be required to repair live body indentation; lines="
                .. vim.inspect(actual))
            print("live Insert-mode buffer tests: PASS")
            vim.cmd("qa!")
          end)
        end)
      end)
    end)
  end)
end)
