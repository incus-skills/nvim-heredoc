package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
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

local function range_contains(range, row)
  return range and range.start_row <= row and range.end_row > row
end

-- Observe production processing and preserve the callback evidence.
local original_process_buffer = plugin.process_buffer
local observed_ranges = {}
plugin.process_buffer = function(target, changed_range, close_incomplete)
  if target == buf then
    local cursor_row = api.nvim_win_get_cursor(0)[1] - 1
    local current_lines = lines()
    observed_ranges[#observed_ranges + 1] = {
      range = changed_range,
      cursor_row = cursor_row,
      body_line = current_lines[cursor_row + 1],
      next_line = current_lines[cursor_row + 2],
    }
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
      return lines()[4] == "\tEOF"
    end, 10) then
      fail("production Return handling should reserve exactly one closer")
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
    assert(result.complete and #result.heredocs == 2
      and result.heredocs[1].terminator_line == 4
      and result.heredocs[2].terminator_line == 9,
      "both obligations should be visible in source order")

    -- Later typing edits the same body row and must not insert another closer.
    api.nvim_input("payload")
    defer(function()
      if not vim.wait(1000, function()
        return lines()[3] == "\t\tpayload" and #observed_ranges >= 3
      end, 10) then
        fail("subsequent payload typing should reach the deferred callback")
      end
      assert(lines()[4] == "\tEOF",
        "nonblank payload edit must not insert a duplicate closer")

      -- Delete the payload bytes again through the same buffer-change surface.
      api.nvim_buf_set_text(buf, 2, 2, 2, #lines()[3], { "" })
      defer(function()
        if not vim.wait(1000, function()
          return lines()[3]:match("^[ \t]*$") ~= nil and #observed_ranges >= 4
        end, 10) then
          fail("payload deletion should reach the deferred callback; observations=" .. vim.inspect(observed_ranges))
        end
        assert(lines()[4] == "\tEOF",
          "blanking an already-reserved body row must not insert a duplicate closer")

        local saw_return_range = false
        for _, observation in ipairs(observed_ranges) do
          if observation.cursor_row == 2 and range_contains(observation.range, 2)
            and observation.range.start_row < 2 then
            saw_return_range = true
          end
        end
        assert(saw_return_range,
          "Return callback range should include the new first body row")

        local saw_later_body_edit = false
        for _, observation in ipairs(observed_ranges) do
          if observation.cursor_row == 2 and observation.range
            and observation.range.start_row == 2 and observation.range.end_row == 3
            and observation.body_line:match("^[ \t]*$") then
            saw_later_body_edit = true
          end
        end
        assert(saw_later_body_edit,
          "later blanking edit should cover only the body row, not the preceding opener row")

        print("Return-local stateless trigger production integration: PASS")
        vim.cmd("qa!")
      end)
    end)
  end)
end)
