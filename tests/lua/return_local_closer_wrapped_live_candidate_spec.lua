package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")
local api = vim.api

local buf = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(buf, 0, -1, false, {
  "new_function() {",
  "\t",
  "}",
  "old_function() {",
  "\told_command <<'EOF'",
  "old payload }",
  "EOF",
  "}",
})
api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "sh"
assert(plugin.setup_buffer(buf), "plugin should attach to the shell buffer")

local function lines()
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function fail(message)
  print(message .. "; lines=" .. vim.inspect(lines()))
  vim.cmd("cquit 1")
end

-- Test-only seam: observe the changed range at the real deferred callback
-- boundary, then apply candidate E. Do not call the old boundary helper.
local original_process_buffer = plugin.process_buffer
local candidate_applied = false
local process_calls = 0
local observed_ranges = {}
plugin.process_buffer = function(target, changed_range, close_incomplete)
  if target == buf then
    process_calls = process_calls + 1
    local cursor_row = api.nvim_win_get_cursor(0)[1] - 1
    observed_ranges[#observed_ranges + 1] = {
      range = changed_range,
      cursor_row = cursor_row,
      line_count = api.nvim_buf_line_count(buf),
      opener_line = lines()[2],
    }
    print("RETURN_RANGE_TRACE " .. vim.inspect(observed_ranges[#observed_ranges]))
  end

  if target == buf and not candidate_applied then
    local current_lines = lines()
    local current = scanner.scan(table.concat(current_lines, "\n"), {
      tabstop = vim.bo[buf].tabstop,
    })
    local cursor_row = api.nvim_win_get_cursor(0)[1] - 1

    if current.complete then
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

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, 20)
end

api.nvim_win_set_cursor(0, { 2, 1 })
api.nvim_input("A")
defer(function()
  assert(api.nvim_get_mode().mode == "i", "A should enter Insert mode")
  api.nvim_input(api.nvim_replace_termcodes("command <lt><lt>-'EOF'<CR>", true, false, true))
  defer(function()
    if not vim.wait(1000, function()
      return candidate_applied and lines()[4] == "\tEOF"
    end, 10) then
      fail("Return-local candidate should reserve the closer before the earlier heredoc terminator")
    end

    local actual = lines()
    assert(api.nvim_get_mode().mode == "i", "Return should leave the user in Insert mode")
    assert(actual[1] == "new_function() {" and actual[2] == "\tcommand <<-'EOF'",
      "new function and opener should remain intact")
    assert(actual[3] == "\t\t" and actual[4] == "\tEOF" and actual[5] == "}",
      "new managed closer should be inside the function and before its structural close; lines="
        .. vim.inspect(actual))
    assert(actual[6] == "old_function() {"
      and actual[7] == "\told_command <<'EOF'"
      and actual[8] == "old payload }"
      and actual[9] == "EOF"
      and actual[10] == "}",
      "the earlier function and heredoc, including its payload brace, should remain intact; lines="
        .. vim.inspect(actual))

    local result = scanner.scan(table.concat(actual, "\n"), {
      tabstop = vim.bo[buf].tabstop,
    })
    assert(result.complete and #result.heredocs == 2,
      "both heredoc obligations should be visible after the local insertion")
    assert(result.heredocs[1].terminator_line == 4
      and result.heredocs[2].terminator_line == 9,
      "new and prior terminators should retain source order")

    print("RETURN_RANGE_TRACE_SUMMARY " .. vim.inspect(observed_ranges))
    print("Function-wrapped Return-local closer live callback candidate: PASS")
    vim.cmd("qa!")
  end)
end)
