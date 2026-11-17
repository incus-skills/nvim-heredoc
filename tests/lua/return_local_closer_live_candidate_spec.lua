package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
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

-- Observe the real on_lines-driven process call; do not simulate insertion.
local original_process_buffer = plugin.process_buffer
local observed_ranges = {}
plugin.process_buffer = function(target, changed_range, close_incomplete)
  if target == buf and changed_range then
    observed_ranges[#observed_ranges + 1] = {
      start_row = changed_range.start_row,
      end_row = changed_range.end_row,
      cursor_row = api.nvim_win_get_cursor(0)[1] - 1,
    }
  end
  return original_process_buffer(target, changed_range, close_incomplete)
end

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
        local actual = lines(buf)
        return actual[3] == "EOF" and actual[4] == "old_command <<'EOF'"
      end, "production Return handling should reserve the closer before the old heredoc")

      local saw_return_range = false
      for _, range in ipairs(observed_ranges) do
        if range.start_row < range.cursor_row and range.end_row > range.cursor_row then
          saw_return_range = true
        end
      end
      assert(saw_return_range,
        "standalone Return callback should span from before through the first body row; ranges="
          .. vim.inspect(observed_ranges))

      local actual = lines(buf)
      assert(api.nvim_get_mode().mode == "i", "Return should leave the user in Insert mode")
      assert(actual[1] == "command <<-'EOF'", "new opener should remain unchanged")
      assert(actual[3] == "EOF", "new closer should follow the first body row")
      assert(actual[4] == "old_command <<'EOF'"
        and actual[5] == "old payload"
        and actual[6] == "EOF",
        "the earlier completed heredoc should remain intact; lines=" .. vim.inspect(actual))

      local result = scanner.scan(table.concat(actual, "\n"), {
        tabstop = vim.bo[buf].tabstop,
      })
      assert(result.complete and #result.heredocs == 2
        and result.heredocs[1].terminator_line == 3
        and result.heredocs[2].terminator_line == 6,
        "both heredoc obligations should remain visible in source order")

      print("Return-local closer production integration: PASS")
      vim.cmd("qa!")
    end)
  end)
end)
