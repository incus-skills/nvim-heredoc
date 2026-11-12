-- Run this with :luafile /path/to/nvim-heredoc/tests/lua/local_lazyvim_live_insert.lua
-- from the user's existing LazyVim instance. It uses a disposable scratch
-- buffer and the already-loaded configuration; it does not reconfigure plugins.

if vim.api.nvim_get_mode().mode ~= "n" then
  vim.notify("nvim-heredoc test: switch to Normal mode before running", vim.log.levels.WARN)
  return
end

local win = vim.api.nvim_get_current_win()
local original_buf = vim.api.nvim_win_get_buf(win)
local original_cursor = vim.api.nvim_win_get_cursor(win)
local buf = vim.api.nvim_create_buf(false, true)
local finished = false

local function cleanup(ok, message)
  if finished then
    return
  end
  finished = true

  if vim.api.nvim_get_mode().mode == "i" then
    vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
  end

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      if vim.api.nvim_buf_is_valid(original_buf) then
        vim.api.nvim_win_set_buf(win, original_buf)
        pcall(vim.api.nvim_win_set_cursor, win, original_cursor)
      end
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end

    local level = ok and vim.log.levels.INFO or vim.log.levels.ERROR
    vim.notify("nvim-heredoc local LazyVim test: " .. message, level)
  end)
end

local function fail(err)
  cleanup(false, tostring(err))
end

local function defer(fn, delay)
  vim.defer_fn(function()
    if finished then
      return
    end
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, delay or 20)
end

local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function assert_lines(condition, message)
  assert(condition, message .. "; lines=" .. vim.inspect(lines()))
end

local function assert_insert_mode(message)
  assert(vim.api.nvim_get_mode().mode == "i",
    message .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
end

local function start()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\tcat <<-LIVE" })
  vim.bo[buf].filetype = "bash"

  assert(vim.b[buf].nvim_heredoc_attached == true,
    "the installed Bash ftplugin did not attach nvim-heredoc")
  assert(vim.bo[buf].expandtab == false,
    "the installed Bash ftplugin must set expandtab=false")
  assert(vim.bo[buf].tabstop == 2 and vim.bo[buf].softtabstop == 0
    and vim.bo[buf].shiftwidth == 2,
    "the installed Bash ftplugin did not establish the expected TAB settings")

  -- Report whether the common LazyVim input plugins were already loaded.
  local integrations = {
    mini_pairs = package.loaded["mini.pairs"] ~= nil,
    blink = package.loaded["blink.cmp"] ~= nil,
  }
  vim.api.nvim_win_set_cursor(win, { 1, #("\tcat <<-LIVE") })
  vim.api.nvim_input("A\n")

  defer(function()
    local actual = lines()
    assert_lines(actual[2] == "\t" and actual[3] == "\tLIVE",
      "first Enter must create the body TAB and reserve the closer")
    assert_insert_mode("first Enter must remain in Insert mode")

    vim.api.nvim_input("typed")
    defer(function()
      actual = lines()
      assert_lines(actual[2] == "\ttyped",
        "first payload must follow the structural TAB")
      assert_insert_mode("typing the first payload must remain in Insert mode")

      vim.api.nvim_input("\n")
      -- One short input-loop turn before the next keystroke: do not allow the
      -- normal 20ms settling interval to hide a late structural prefix.
      defer(function()
        vim.api.nvim_input("s")
        defer(function()
          assert(prefix_before_next_payload == true,
            "the new body line must have its TAB before InsertCharPre")
          actual = lines()
          assert_lines(actual[3] == "\ts",
            "the first character after Enter must follow the structural TAB")
          assert_insert_mode("subsequent Enter and typing must remain in Insert mode")

          vim.api.nvim_input("econd")
          defer(function()
            actual = lines()
            assert_lines(actual[3] == "\tsecond",
              "the rest of the second payload must follow the structural TAB")

            vim.api.nvim_input("\n")
            defer(function()
              assert(vim.wait(1000, function()
                return lines()[4] == "\t"
              end, 10), "the next body line was not prefixed before paste")

              assert(vim.api.nvim_paste("  pasted one\n    pasted two", false, -1),
                "Neovim rejected the multi-line paste")
              defer(function()
                assert(vim.wait(1000, function()
                  actual = lines()
                  return actual[4] == "\t  pasted one"
                    and actual[5] == "\t    pasted two"
                    and actual[6] == "\tLIVE"
                end, 10), "multi-line paste was not prefixed before InsertLeave")
                assert_insert_mode("paste processing must remain in Insert mode")

                vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
                defer(function()
                  actual = lines()
                  assert(vim.api.nvim_get_mode().mode ~= "i",
                    "Escape should leave Insert mode")
                  assert_lines(actual[2] == "\ttyped" and actual[3] == "\tsecond"
                    and actual[4] == "\t  pasted one"
                    and actual[5] == "\t    pasted two"
                    and actual[6] == "\tLIVE",
                    "InsertLeave must not be required to repair indentation")

                  cleanup(true, "PASS (typing, pre-keystroke TAB, and multi-line paste); "
                    .. "mini.pairs loaded=" .. tostring(integrations.mini_pairs)
                    .. ", Blink loaded=" .. tostring(integrations.blink))
                end)
              end)
            end)
          end)
        end)
      end, 1)
    end)
  end)
end

local prefix_before_next_payload = nil
vim.api.nvim_create_autocmd("InsertCharPre", {
  buffer = buf,
  callback = function()
    if vim.v.char == "s" and prefix_before_next_payload == nil then
      local row = vim.api.nvim_win_get_cursor(win)[1] - 1
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      prefix_before_next_payload = line:sub(1, 1) == "\t"
    end
  end,
})

local ok, err = xpcall(start, debug.traceback)
if not ok then
  fail(err)
end
