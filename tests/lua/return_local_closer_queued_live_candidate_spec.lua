package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
local api = vim.api

local buf = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(buf, 0, -1, false, {
  "old_command <<'EOF' <<'EOF'",
  "old payload one",
  "EOF",
  "old payload two",
  "EOF",
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

local original_process_buffer = plugin.process_buffer
local callback_count = 0
plugin.process_buffer = function(target, changed_range, close_incomplete)
  if target == buf and changed_range then
    callback_count = callback_count + 1
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

local function wait_for(predicate, message)
  if not vim.wait(1000, predicate, 10) then
    fail(message)
  end
end

api.nvim_win_set_cursor(0, { 1, 0 })
api.nvim_input("O")
defer(function()
  assert(api.nvim_get_mode().mode == "i", "O should enter Insert mode above the old command")
  api.nvim_input(api.nvim_replace_termcodes("command <lt><lt>-'EOF' <lt><lt>-'EOF'", true, false, true))
  defer(function()
    assert(lines()[1] == "command <<-'EOF' <<-'EOF'",
      "both managed heredoc redirections should be typed on the new command")
    api.nvim_input(api.nvim_replace_termcodes("<CR>", true, false, true))
    defer(function()
      wait_for(function()
        return lines()[3] == "EOF" and lines()[4] == "EOF"
      end, "Return should reserve both new queued closers before the old command")

      local actual = lines()
      assert(callback_count > 0, "the real on_lines callback should invoke production processing")
      assert(api.nvim_get_mode().mode == "i", "Return should leave the user in Insert mode")
      assert(actual[1] == "command <<-'EOF' <<-'EOF'",
        "new command should remain intact")
      assert(actual[3] == "EOF" and actual[4] == "EOF",
        "both generated closers should be adjacent and ordered after the first body row")
      assert(actual[5] == "old_command <<'EOF' <<'EOF'"
        and actual[6] == "old payload one"
        and actual[7] == "EOF"
        and actual[8] == "old payload two"
        and actual[9] == "EOF",
        "the old command and both of its heredocs should remain intact; lines=" .. vim.inspect(actual))

      local result = scanner.scan(table.concat(actual, "\n"), {
        tabstop = vim.bo[buf].tabstop,
      })
      assert(result.complete and #result.heredocs == 4
        and result.heredocs[1].opener_line == 1
        and result.heredocs[1].terminator_line == 3
        and result.heredocs[2].opener_line == 1
        and result.heredocs[2].terminator_line == 4
        and result.heredocs[3].opener_line == 5
        and result.heredocs[3].terminator_line == 7
        and result.heredocs[4].opener_line == 5
        and result.heredocs[4].terminator_line == 9,
        "all four heredoc obligations should remain visible in declaration order")

      print("Queued Return-local closer production integration: PASS")
      vim.cmd("qa!")
    end)
  end)
end)
