package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- Candidate E: model the first-Return transition without consulting a prior
-- scan. body_row is the zero-based row created immediately below the opener.
-- Reserve the managed closer after that row before accepting a later scanner
-- candidate as the new heredoc's terminator.
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
  table.insert(lines, body_row + 2, closer)
  return true
end

-- Standalone: current scan lets the new opener consume the old terminator.
-- The Return-local candidate needs no previous scan to restore source order.
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
  assert(apply_return_local_closer(lines, current, 1),
    "candidate should recognise the first body row from the current scan")
  assert(lines[3] == "EOF",
    "column-zero opener should produce a column-zero managed closer")
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 2
    and result.heredocs[1].terminator_line == 3
    and result.heredocs[2].terminator_line == 6,
    "candidate should restore both standalone heredoc obligations")
end

-- Function-wrapped: the Return-local closer belongs before the enclosing
-- brace. A brace in the earlier heredoc payload remains opaque.
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
  assert(result.complete and #result.heredocs == 2
    and result.heredocs[1].terminator_line == 4
    and result.heredocs[2].terminator_line == 9,
    "candidate should preserve both obligations without interpreting payload braces")
end

-- Negative control: heredoc-looking syntax and braces inside a body are not
-- independent source obligations and must not be used as Return boundaries.
do
  local lines = {
    "command <<-'EOF'",
    "",
  }
  local current = scan(lines)
  assert(not current.complete and #current.heredocs == 1,
    "control: a new opener with its first body row is an outstanding obligation")
  assert(apply_return_local_closer(lines, current, 1),
    "candidate should reserve the new closer without parsing payload")
  -- Subsequent typing inserts payload before the reserved closer, as it does
  -- in the live editing arrangement.
  table.insert(lines, 3, "payload }")
  table.insert(lines, 4, "cat <<'INNER'")
  local result = scan(lines)
  assert(result.complete and #result.heredocs == 1
    and result.heredocs[1].terminator_line == 5,
    "brace and heredoc-looking payload must remain opaque before the reserved closer")
end

print("Return-local closer candidate reference model: PASS")
