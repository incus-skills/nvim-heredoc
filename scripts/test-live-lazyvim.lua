-- Run from the user's existing LazyVim instance:
--   :luafile /path/to/nvim-heredoc/scripts/test-live-lazyvim.lua
--
-- Uses a disposable scratch buffer and the already-loaded configuration.
-- It does not alter the user's files or plugin configuration. On failure it
-- prints one structured report containing the buffer, scanner, module sources,
-- options, and the event trace from the exact test run.

if vim.api.nvim_get_mode().mode ~= "n" then
  vim.notify("nvim-heredoc live test: switch to Normal mode, then rerun", vim.log.levels.WARN)
  return
end

local ok_module, heredoc = pcall(require, "nvim-heredoc")
if not ok_module then
  vim.notify("nvim-heredoc live test: cannot load module: " .. tostring(heredoc), vim.log.levels.ERROR)
  return
end

local scanner_ok, scanner = pcall(require, "nvim-heredoc.scanner")
if not scanner_ok then
  vim.notify("nvim-heredoc live test: cannot load scanner: " .. tostring(scanner), vim.log.levels.ERROR)
  return
end

local function source_of(value)
  local info = debug.getinfo(value, "S")
  return info and info.source or "unavailable"
end

local old_trace_setting = vim.g.nvim_heredoc_trace
vim.g.nvim_heredoc_trace = true
heredoc.clear_trace()

local win = vim.api.nvim_get_current_win()
local original_buf = vim.api.nvim_win_get_buf(win)
local original_cursor = vim.api.nvim_win_get_cursor(win)
local original_bufhidden = vim.bo[original_buf].bufhidden
vim.bo[original_buf].bufhidden = "hide"

local buf = vim.api.nvim_create_buf(false, true)
local finished = false
local stage = "initialisation"
local prefix_before_next_payload = nil

local function lines()
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function diagnostic_report(err)
  local current_lines = lines()
  local scan = scanner.scan(table.concat(current_lines, "\n"))
  return {
    result = "FAIL",
    stage = stage,
    error = tostring(err),
    module_sources = {
      init = source_of(heredoc.setup_buffer),
      scanner = source_of(scanner.scan),
    },
    buffer = {
      filetype = vim.bo[buf].filetype,
      expandtab = vim.bo[buf].expandtab,
      tabstop = vim.bo[buf].tabstop,
      softtabstop = vim.bo[buf].softtabstop,
      shiftwidth = vim.bo[buf].shiftwidth,
      attached = vim.b[buf].nvim_heredoc_attached == true,
      lines = current_lines,
      lines_inspected = vim.inspect(current_lines),
      scan = scan,
    },
    prefix_seen_at_insert_char_pre = prefix_before_next_payload,
    trace = heredoc.get_trace(),
  }
end

local function cleanup(ok, message, err)
  if finished then
    return
  end
  finished = true

  local report = not ok and diagnostic_report(err or message) or nil

  if vim.api.nvim_get_mode().mode == "i" then
    vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
  end

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(original_buf) then
      vim.api.nvim_win_set_buf(win, original_buf)
      vim.bo[original_buf].bufhidden = original_bufhidden
      pcall(vim.api.nvim_win_set_cursor, win, original_cursor)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    vim.g.nvim_heredoc_trace = old_trace_setting

    if ok then
      vim.notify("nvim-heredoc local LazyVim test: " .. message, vim.log.levels.INFO)
    else
      vim.notify("nvim-heredoc local LazyVim test: FAIL at " .. stage
        .. " (full diagnostic report follows)", vim.log.levels.ERROR)
      vim.print(report)
    end
  end)
end

local function fail(err)
  cleanup(false, nil, err)
end

local function defer(fn, delay)
  vim.defer_fn(function()
    if finished then
      return
    end
    local success, err = xpcall(fn, debug.traceback)
    if not success then
      fail(err)
    end
  end, delay or 20)
end

local function assert_lines(condition, message)
  assert(condition, message .. "; lines=" .. vim.inspect(lines()))
end

local function assert_insert_mode(message)
  assert(vim.api.nvim_get_mode().mode == "i",
    message .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
end

local function start()
  stage = "buffer setup"
  -- Prepare the opener while the scratch buffer is not current and before
  -- the plugin attaches. Otherwise TextChanged can observe this setup edit in
  -- Normal mode and close the incomplete heredoc before the simulated Return.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "cat <<-LIVE" })
  vim.bo[buf].filetype = "bash"
  vim.api.nvim_win_set_buf(win, buf)

  assert(vim.b[buf].nvim_heredoc_attached == true,
    "the installed Bash ftplugin did not attach nvim-heredoc")
  assert(vim.bo[buf].expandtab == false,
    "the installed Bash ftplugin must set expandtab=false")
  assert(vim.bo[buf].tabstop == 2 and vim.bo[buf].softtabstop == 0
    and vim.bo[buf].shiftwidth == 2,
    "the installed Bash ftplugin did not establish the expected TAB settings")

  stage = "first Return (closer and first body TAB)"
  vim.api.nvim_win_set_cursor(win, { 1, #"cat <<-LIVE" })
  vim.api.nvim_input("A\n")

  defer(function()
    assert(vim.wait(1000, function()
      return lines()[2] == "\t" and lines()[3] == "LIVE"
    end, 10), "scheduled first-Return processing did not create the body TAB and closer")
    assert_lines(lines()[2] == "\t" and lines()[3] == "LIVE",
      "first Return must create the body TAB and reserve the closer")
    assert_insert_mode("first Return must remain in Insert mode")

    stage = "first payload typing"
    vim.api.nvim_input("typed")
    defer(function()
      assert_lines(lines()[2] == "\ttyped",
        "first payload must follow the structural TAB")
      assert_insert_mode("first payload typing must remain in Insert mode")

      stage = "subsequent Return before next payload"
      vim.api.nvim_input("\n")
      defer(function()
        stage = "pre-keystroke TAB observation"
        vim.api.nvim_input("s")
        defer(function()
          assert(prefix_before_next_payload == true,
            "the new body line must have its TAB before InsertCharPre")
          assert_lines(lines()[3] == "\ts",
            "the first character after Return must follow the structural TAB")
          assert_insert_mode("subsequent Return and typing must remain in Insert mode")

          stage = "remaining second payload typing"
          vim.api.nvim_input("econd")
          defer(function()
            assert_lines(lines()[3] == "\tsecond",
              "the rest of the second payload must follow the structural TAB")

            stage = "next body line before paste"
            vim.api.nvim_input("\n")
            defer(function()
              assert(vim.wait(1000, function()
                return lines()[4] == "\t"
              end, 10), "the next body line was not prefixed before paste")

              stage = "multi-line paste"
              assert(vim.api.nvim_paste("  pasted one\n    pasted two", false, -1),
                "Neovim rejected the multi-line paste")
              defer(function()
                assert(vim.wait(1000, function()
                  local actual = lines()
                  return actual[4] == "\t  pasted one"
                    and actual[5] == "\t    pasted two"
                    and actual[6] == "LIVE"
                end, 10), "multi-line paste was not prefixed before InsertLeave")
                assert_insert_mode("paste processing must remain in Insert mode")

                stage = "InsertLeave integrity"
                vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
                defer(function()
                  local actual = lines()
                  assert(vim.api.nvim_get_mode().mode ~= "i",
                    "Escape should leave Insert mode")
                  assert_lines(actual[2] == "\ttyped" and actual[3] == "\tsecond"
                    and actual[4] == "\t  pasted one"
                    and actual[5] == "\t    pasted two"
                    and actual[6] == "\tLIVE",
                    "InsertLeave must not be required to repair indentation")

                  cleanup(true, "PASS (first Return, typing, pre-keystroke TAB, and multi-line paste); "
                    .. "mini.pairs loaded=" .. tostring(package.loaded["mini.pairs"] ~= nil)
                    .. ", Blink loaded=" .. tostring(package.loaded["blink.cmp"] ~= nil))
                end)
              end)
            end)
          end)
        end)
      end, 1)
    end)
  end)
end

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

local success, err = xpcall(start, debug.traceback)
if not success then
  fail(err)
end
