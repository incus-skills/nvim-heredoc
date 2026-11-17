package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- Case 1: queue identity is source order, not delimiter uniqueness. Different
-- and repeated delimiters must each retain their own closer obligation.
do
  local result = scanner.scan(table.concat({
    "command <<-'A' <<-'B' <<-'A'",
    "first body",
    "A",
    "second body",
    "B",
    "third body",
    "A",
  }, "\n"))
  assert(result.complete and #result.heredocs == 3)
  local first, second, third = result.heredocs[1], result.heredocs[2], result.heredocs[3]
  assert(first.opener_line == 1 and second.opener_line == 1 and third.opener_line == 1)
  assert(first.queue_position == 1 and second.queue_position == 2 and third.queue_position == 3)
  assert(first.delimiter == "A" and second.delimiter == "B" and third.delimiter == "A")
  assert(first.terminator_line == 3 and second.terminator_line == 5 and third.terminator_line == 7,
    "each queued obligation must consume its own terminator in declaration order")
end

-- Case 2: heredoc-looking payload is not an independently recognised opener.
do
  local result = scanner.scan(table.concat({
    "cat <<-'OUTER'",
    "cat <<'INNER'",
    "OUTER",
  }, "\n"))
  assert(result.complete and #result.heredocs == 1)
  assert(result.heredocs[1].delimiter == "OUTER")
  assert(result.heredocs[1].terminator_line == 3)
end

print("source-order boundary matrix characterization: PASS")
