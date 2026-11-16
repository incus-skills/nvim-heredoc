package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Characterize retaining a function-close source identity before a new
-- heredoc makes that line opaque. This is a test-side reference model only.

local scanner = require("nvim-heredoc.scanner")

local function is_function_header(line)
  return line:match("^[ \t]*[A-Za-z_][A-Za-z0-9_]*%(%)[ \t]*{[ \t]*$")
    or line:match("^[ \t]*function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*{[ \t]*$")
end

local function capture_unique_function_close(lines, header_row)
  local result = scanner.scan(table.concat(lines, "\n"))
  if not result.complete then
    return nil, "baseline scan is incomplete"
  end

  local header = lines[header_row]
  if not header or not is_function_header(header) then
    return nil, "function header not recognised"
  end

  -- Heredoc bodies and their terminators are opaque to structural discovery.
  local opaque = {}
  for _, heredoc in ipairs(result.heredocs) do
    if heredoc.terminator_line then
      for row = heredoc.body_start_line, heredoc.terminator_line do
        opaque[row] = true
      end
    end
  end

  local limit = #lines + 1
  for row = header_row + 1, #lines do
    if is_function_header(lines[row]) then
      limit = row
      break
    end
  end

  local candidates = {}
  for row = header_row + 1, limit - 1 do
    if not opaque[row] and lines[row]:match("^[ \t]*}$") then
      candidates[#candidates + 1] = row
    end
  end

  -- Deliberately conservative: this reference model accepts only an
  -- unambiguous standalone close in the target function's source interval.
  if #candidates ~= 1 then
    return nil, #candidates == 0 and "no close candidate" or "ambiguous close candidates"
  end
  return candidates[1] - 1
end

local function attach_row_tracker(buf, row)
  local tracked = { row = row, valid = true }
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, firstline, lastline, new_lastline)
      if not tracked.valid then
        return
      end
      local delta = new_lastline - lastline
      if tracked.row < firstline then
        -- Edit after the tracked source line.
      elseif tracked.row >= lastline then
        tracked.row = tracked.row + delta
      else
        tracked.valid = false
      end
    end,
  })
  return tracked
end

local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function assert_close(actual, expected, message)
  assert(actual == expected,
    string.format("%s: expected row %s, got %s",
      message, tostring(expected), tostring(actual)))
end

-- A pre-opener complete scan can identify the new function's unique close.
-- A brace in an already recognised heredoc body is not a candidate.
do
  local lines = {
    "new_fn() {",
    "  cat ",
    "}",
    "old_fn() {",
    "  cat <<'OLD'",
    "payload }",
    "OLD",
    "}",
  }
  local baseline_scan = scanner.scan(table.concat(lines, "\n"))
  assert(#baseline_scan.heredocs == 1, "baseline scanner should recognise the old heredoc")
  assert(baseline_scan.heredocs[1].body_start_line == 6
    and baseline_scan.heredocs[1].terminator_line == 7,
    "existing heredoc body and terminator should be opaque")
  local actual, reason = capture_unique_function_close(lines, 1)
  assert_close(actual, 2, "unique function close")
  assert(reason == nil)
end

-- Completing the opener and inserting the first body line moves the tracked
-- close. A later payload brace inserted before it moves the identity again;
-- it must not replace the retained close merely because the text is equal.
do
  local lines = {
    "new_fn() {",
    "  cat ",
    "}",
    "old_fn() {",
    "  cat <<'OLD'",
    "payload }",
    "OLD",
    "}",
  }
  local buf = make_buffer(lines)
  local row = capture_unique_function_close(lines, 1)
  local tracked = attach_row_tracker(buf, row)

  -- Replace the command line with a completed opener and its first body line.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  cat <<-'NEW'", "" })
  assert(tracked.valid)
  assert_close(tracked.row, 3, "close rebased after first body line")

  -- Insert a payload line that looks exactly like a structural close.
  vim.api.nvim_buf_set_lines(buf, tracked.row, tracked.row, false, { "}" })
  assert(tracked.valid)
  assert_close(tracked.row, 4, "retained close survives payload brace insertion")

  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(current[tracked.row + 1] == "}", "tracked source line remains the original close")
  assert(current[tracked.row] == "}", "payload lookalike precedes the tracked close")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Multiple functions are bounded independently by the next function header.
do
  local lines = {
    "first_fn() {",
    "}",
    "second_fn() {",
    "}",
  }
  assert_close(capture_unique_function_close(lines, 1), 1, "first function close")
  assert_close(capture_unique_function_close(lines, 3), 3, "second function close")
end

-- If a payload-looking brace was already present before opener completion,
-- the pre-opener source alone cannot distinguish it from a real close.
-- The conservative reference model must report ambiguity, not guess.
do
  local lines = {
    "new_fn() {",
    "  cat ",
    "}",
    "  }",
    "old_fn() {",
    "  cat <<'OLD'",
    "OLD",
    "}",
  }
  local actual, reason = capture_unique_function_close(lines, 1)
  assert(actual == nil, "ambiguous close candidates must not be selected")
  assert(reason == "ambiguous close candidates")
end

-- Replacing or deleting the tracked source line invalidates identity. A later
-- identical textual brace must not be promoted as the original close.
do
  local buf = make_buffer({ "new_fn() {", "  cat ", "}", "old_fn() {" })
  local tracked = attach_row_tracker(buf, 2)
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "}" })
  assert(not tracked.valid, "replacement invalidates close identity")
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, {})
  assert(not tracked.valid, "later deletion cannot revive invalid identity")
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "}" })
  assert(not tracked.valid, "identical replacement text is not source continuity")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- If no close was captured before the opener became opaque, a later brace
-- inside that body is not retrospectively trusted as structural.
do
  local lines = { "new_fn() {", "  cat ", "old_fn() {" }
  local actual, reason = capture_unique_function_close(lines, 1)
  assert(actual == nil)
  assert(reason == "no close candidate")
end

print("retained function-close identity characterization: PASS")
