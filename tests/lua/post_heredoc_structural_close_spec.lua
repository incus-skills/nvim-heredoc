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

print("post-heredoc structural-close characterization: PASS")
