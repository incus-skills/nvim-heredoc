package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- Candidate E: model the first-Return transition without consulting a prior
-- scan. The changed body row is the line created immediately below the new
-- opener. Reserve the managed closer there before accepting a later candidate
-- terminator from the scanner.
local function apply_return_local_closer(lines, current, body_row)
  local pending
  for _, heredoc in ipairs(current.heredocs) do
    if heredoc.body_start_line == body_row + 1 then
      pending = heredoc
      break
    end
  end
  if not pending then
    return false
  end
  local closer = (pending.structural_prefix or "") .. pending.delimiter
  table.insert(lines, body_row + 1, closer)
  return true
end

local function assert_two_obligations(lines, message)
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 2,
    message .. "; scan=" .. vim.inspect(result))
  assert(result.heredocs[1].terminator_line == 4,
    message .. "; new closer should terminate the first obligation")
  assert(result.heredocs[2].terminator_line == 9,
    message .. "; old closer should remain with the second obligation")
end

-- Standalone: the current scan incorrectly lets the new opener consume the
-- old terminator. The Return-local candidate needs no previous scan to repair
-- the source order.
do
  local lines = {
    "command <<-'EOF'",
    "",
    "old_command <<'EOF'",
    "old payload",
    "EOF",
  }
  local current = scan(lines)
  assert(current.complete and #current.heredocs == 1
    and current.heredocs[1].terminator_line == 5,
    "control: current scan should demonstrate the terminator-claim ambiguity")
  assert(apply_return_local_closer(lines, current, 2),
    "candidate should recognise the first body row from the current scan")
  assert(lines[4] == "\tEOF", "candidate should insert the managed closer after the new body row")
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 2,
    "candidate should restore two standalone heredoc obligations")
end

-- Function-wrapped: the first Return-local closer belongs before the
-- enclosing brace. A brace in payload remains opaque.
do
  local lines = {
    "new_function() {",
    "\tcommand <<-'EOF'",
    "",
    "}",
    "old_function() {",
    "\told_command <<'EOF'",
    "old payload }",
    "EOF",
    "}",
  }
  local current = scan(lines)
  assert(current.complete and #current.heredocs == 1
    and current.heredocs[1].terminator_line == 8,
    "control: current scan should consume the old terminator")
  assert(apply_return_local_closer(lines, current, 2),
    "candidate should identify the newly created first body row")
  assert(lines[4] == "\tEOF" and lines[5] == "}",
    "candidate closer must precede the function's structural close")
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 2,
    "candidate should preserve both wrapped and earlier heredoc obligations")
  assert(result.heredocs[1].terminator_line == 4
    and result.heredocs[2].terminator_line == 8,
    "payload brace must not displace either terminator")
end

-- Negative control: heredoc-looking syntax and braces inside a body are not
-- independent source obligations and must not be used as Return boundaries.
do
  local lines = {
    "command <<-'EOF'",
    "",
    "payload }",
    "cat <<'INNER'",
    "EOF",
  }
  local current = scan(lines)
  assert(current.complete and #current.heredocs == 1,
    "payload lookalikes must remain opaque in the current scan")
  assert(apply_return_local_closer(lines, current, 2),
    "candidate should reserve the new closer without parsing payload")
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 1
    and result.heredocs[1].terminator_line == 3,
    "the new closer should end the obligation; payload remains opaque")
end

print("Return-local closer candidate reference model: PASS")
