package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")
local api = vim.api

local buf

local function lines(target)
  return api.nvim_buf_get_lines(target, 0, -1, false)
end

local function wait_for(predicate, message)
  assert(vim.wait(1000, predicate, 10), message .. "; lines=" .. vim.inspect(lines(buf)))
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

buf = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(buf, 0, -1, false, {
  "old_command <<'EOF'",
  "old payload",
  "EOF",
})
api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "sh"
assert(plugin.setup_buffer(buf), "plugin should attach to the shell buffer")

-- Test-only integration seam: emulate candidate E at the exact deferred
-- process_buffer call reached from the plugin's real on_lines callback.
-- No production callback or implementation is changed.
local original_process_buffer = plugin.process_buffer
local candidate_applied = false
plugin.process_buffer = function(target, changed_range, close_incomplete)
  if target == buf and not candidate_applied and changed_range then
    local current_lines = lines(buf)
    local current = scanner.scan(table.concat(current_lines, "\n"), {
      tabstop = vim.bo[buf].tabstop,
    })
    local cursor_row = api.nvim_win_get_cursor(0)[1] - 1

    if current.complete
      and changed_range.start_row <= cursor_row
      and changed_range.end_row > cursor_row then
      for _, region in ipairs(current.heredocs) do
        if region.operator == "<<-"
          and region.body_start_line - 1 == cursor_row
          and region.terminator_line then
          local closer = assert(editing.closer_line(region))
          api.nvim_buf_set_lines(buf, cursor_row + 1, cursor_row + 1, false, { closer })
          candidate_applied = true
          break
        end
      end
    end
  end

  return original_process_buffer(target, changed_range, close_incomplete)
end

-- Exercise actual Insert-mode input. The new opener is placed immediately
-- before an existing completed heredoc with the same delimiter.
api.nvim_win_set_cursor(0, { 1, 0 })
api.nvim_input("O")
defer(function()
  assert(api.nvim_get_mode().mode == "i",
    "O should enter Insert mode above the existing heredoc")

  api.nvim_input(api.nvim_replace_termcodes("command <lt><lt>-'EOF'", true, false, true))
  defer(function()
    assert(lines(buf)[1] == "command <<-'EOF'",
      "the new managed opener should be typed in Insert mode; lines=" .. vim.inspect(lines(buf)))

    api.nvim_input(api.nvim_replace_termcodes("<CR>", true, false, true))
    defer(function()
      wait_for(function()
        return candidate_applied and lines(buf)[3] == "EOF"
      end, "Return-local candidate should reserve the closer before the old heredoc")

      local actual = lines(buf)
      assert(api.nvim_get_mode().mode == "i", "Return should leave the user in Insert mode")
      assert(actual[1] == "command <<-'EOF'", "new opener should remain unchanged")
      assert(actual[3] == "EOF", "new closer should follow the first body row")
      assert(actual[4] == "old_command <<'EOF'"
        and actual[5] == "old payload"
        and actual[6] == "EOF",
        "the earlier completed heredoc should remain intact; lines=" .. vim.inspect(actual))

      print("Return-local closer live callback candidate: PASS")
      vim.cmd("qa!")
    end)
  end)
end)
