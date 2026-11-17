package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function private_upvalue(target)
  for index = 1, 32 do
    local name, value = debug.getupvalue(plugin.process_buffer, index)
    if not name then break end
    if name == target then return value end
  end
  error("could not inspect private upvalue " .. target)
end

local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sh"
  vim.bo[buf].tabstop = 2
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].expandtab = false
  return buf
end

local function attach_identity_tracker(buf, row)
  local processing = private_upvalue("processing")
  local tracked = { row = row, valid = true, events = {} }

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, changedtick, firstline, lastline, new_lastline)
      local was_processing = processing[changed_buf] == true
      tracked.events[#tracked.events + 1] = {
        changedtick = changedtick,
        firstline = firstline,
        lastline = lastline,
        new_lastline = new_lastline,
        processing = was_processing,
      }

      if not tracked.valid then
        return
      end
      local delta = new_lastline - lastline
      if tracked.row < firstline then
        -- The edit is after the tracked source line.
      elseif tracked.row >= lastline then
        tracked.row = tracked.row + delta
      else
        tracked.valid = false
      end
    end,
  })

  return tracked
end

local function assert_true(value, message)
  assert(value, message)
end

-- Baseline: the new function's unique close is visible, and an older
-- completed heredoc remains visible after the Return-local closer is reserved.
do
  local buf = make_buffer({
    "new_function() {",
    "\tcommand",
    "}",
    "old_function() {",
    "\tcat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  assert(plugin.setup_buffer(buf), "plugin failed to attach")
  local tracked = attach_identity_tracker(buf, 2)

  -- Completing the opener and creating the first body line is a user edit.
  -- The old completed heredoc is now apparently consumed by the new opener.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {
    "\tcommand <<-'EOF'",
    "",
  })

  assert(tracked.valid and tracked.row == 3,
    "user opener/body edit should rebase the retained function-close row")

  -- Invoke the real Return-local production path on the first body row.
  -- The closer insertion uses nvim_buf_set_lines() inside process_buffer().
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  plugin.process_buffer(buf, { start_row = 1, end_row = 3 }, false)

  assert(tracked.valid, "plugin closer insertion must not invalidate the close")
  assert(tracked.row == 4,
    "plugin-generated closer insertion should shift the retained close row")
  assert(vim.api.nvim_buf_get_lines(buf, tracked.row, tracked.row + 1, false)[1] == "}",
    "the tracked row should still identify the original function close")

  local plugin_events = {}
  for _, event in ipairs(tracked.events) do
    if event.processing then
      plugin_events[#plugin_events + 1] = event
    end
  end
  assert(#plugin_events >= 1,
    "plugin-generated buffer mutation must be reported through on_lines while processing")
  assert(plugin_events[1].firstline == 3
    and plugin_events[1].lastline == 3
    and plugin_events[1].new_lastline == 4,
    "the plugin closer insertion should report the expected zero-based line range")

  -- Replacing the original close through the buffer API, even with identical
  -- text, must invalidate its source identity rather than preserve it by text.
  vim.api.nvim_buf_set_lines(buf, tracked.row, tracked.row + 1, false, { "}" })
  assert(not tracked.valid,
    "replacement of the tracked close must invalidate identity even when text is identical")

  -- A later identical line must not revive the invalidated source identity.
  vim.api.nvim_buf_set_lines(buf, tracked.row, tracked.row, false, { "}" })
  assert(not tracked.valid, "later identical text must not revive invalidated identity")

  vim.api.nvim_buf_delete(buf, { force = true })
end

print("on_lines plugin-mutation accounting characterization: PASS")
vim.cmd("qa!")
