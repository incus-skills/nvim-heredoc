package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- This is deliberately a post-closer check: once the heredoc terminator is
-- present, shell source recognition resumes after it. For the representative
-- brace-delimited forms under consideration, the first standalone close
-- following that terminator is the nearest enclosing structural boundary.
local function first_close_after_terminator(lines, heredoc)
  assert(heredoc and heredoc.terminator_line,
    "a completed heredoc is required")
  for row = heredoc.terminator_line + 1, #lines do
    if lines[row]:match("^[ \t]*}$") then
      return row
    end
  end
  return nil
end

local function assert_row(actual, expected, message)
  assert(actual == expected,
    string.format("%s: expected row %s, got %s",
      message, tostring(expected), tostring(actual)))
end

-- 1. Ordinary function-wrapped heredoc. A brace in payload is opaque; the
-- first structural close after the terminator is the function's close.
do
  local lines = {
    "run() {",
    "  cat <<'EOF'",
    "payload }",
    "EOF",
    "}",
  }
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 1)
  assert_row(result.heredocs[1].terminator_line, 4,
    "scanner should identify the heredoc terminator")
  assert_row(first_close_after_terminator(lines, result.heredocs[1]), 5,
    "first post-terminator close should be the function boundary")
end

-- 2. A heredoc inside an already-open brace group. The first close after the
-- terminator closes that immediately containing group; it need not be the
-- function's outer close.
do
  local lines = {
    "run() {",
    "  {",
    "    cat <<'EOF'",
    "payload }",
    "EOF",
    "  }",
    "}",
  }
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 1)
  assert_row(first_close_after_terminator(lines, result.heredocs[1]), 6,
    "first post-terminator close should exit the containing brace group")
end

-- 3. The standalone form has no enclosing brace boundary. Its heredoc
-- terminator remains sufficient; the helper must not invent a close.
do
  local lines = {
    "cat <<'EOF'",
    "payload }",
    "EOF",
    "after",
  }
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 1)
  assert_row(first_close_after_terminator(lines, result.heredocs[1]), nil,
    "standalone heredoc should have no structural close")
end


-- 4. Exercise the existing production Return-processing path against the
-- retained-old-heredoc case. The plugin places the new terminator before the
-- first enclosing close. A brace subsequently typed as payload remains before
-- that terminator and cannot displace the post-terminator structural close.
do
  local plugin = require("nvim-heredoc")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "sh"
  vim.bo[buf].tabstop = 2
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].expandtab = false

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "new_function() {",
    "\tcommand",
    "}",
    "old_function() {",
    "\tcat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  assert(plugin.setup_buffer(buf), "plugin failed to attach to integration fixture")

  -- This is the Return-time buffer shape: a new opener and its first blank
  -- body line have appeared, while the old completed heredoc remains below.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {
    "\tcommand <<-'EOF'",
    "",
  })
  plugin.process_buffer(buf, { start_row = 1, end_row = 3 }, false)

  local processed = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local result = scan(processed)
  assert(result.complete and #result.heredocs == 2,
    "processing should leave both the new and old heredoc obligations intact")
  assert(processed[4] == "\tEOF" and processed[5] == "}",
    "the production path should place the new closer immediately before the enclosing brace")

  -- Add a literal brace to the new heredoc payload, then check the source
  -- position after the actual scanner-confirmed terminator.
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "payload }" })
  processed = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  result = scan(processed)
  assert(result.complete and result.heredocs[1].terminator_line == 4)
  assert_row(first_close_after_terminator(processed, result.heredocs[1]), 5,
    "the first post-terminator close remains the enclosing structural boundary")

  vim.api.nvim_buf_delete(buf, { force = true })
end

print("post-heredoc structural-close characterization: PASS")
