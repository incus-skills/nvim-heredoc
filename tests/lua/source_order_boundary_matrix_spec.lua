package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")

local function private_upvalue(target)
  for index = 1, 32 do
    local name, value = debug.getupvalue(plugin.process_buffer, index)
    if not name then break end
    if name == target then return value end
  end
  error("could not inspect private upvalue " .. target)
end

local preserve_boundary = private_upvalue("preserve_function_heredoc_boundary")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- Case 1: standalone old opener blocks a later NEW terminator even when the
-- intervening heredoc uses a different delimiter. The current scanner cannot
-- see the old obligation once the new body has swallowed its opener.
do
  local baseline = scan({
    "cat <<'OLD'",
    "old payload",
    "OLD",
  })
  assert(baseline.complete and #baseline.heredocs == 1)

  local lines = {
    "cat <<-'NEW'",
    "cat <<'OLD'",
    "old payload",
    "OLD",
    "new payload",
    "NEW",
  }
  local current = scan(lines)
  assert(current.complete and #current.heredocs == 1)
  assert(current.heredocs[1].delimiter == "NEW")
  assert(current.heredocs[1].terminator_line == 6,
    "current scan consumes NEW after swallowing the intervening OLD obligation")
  assert(not preserve_boundary(baseline, current, lines),
    "current recovery helper does not protect standalone obligations with distinct delimiters")
end

-- Case 2: when the new function's closing brace occurs before the old opener,
-- the brace is the earlier boundary. This is the existing narrow recovery
-- case, retained as a positive control.
do
  local baseline = scan({
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  local lines = {
    "new_function() {",
    "  cat <<-'EOF'",
    "}",
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 7)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == 3,
    "the earlier function close brace must be selected")
  assert(current.regions[1].terminator_line == nil,
    "the old terminator must not cross the selected brace boundary")
end

-- Case 3: when the old opener occurs before the enclosing function's closing
-- brace, the old opener is the earlier boundary. The current helper notices
-- the old opener but fails to assign a boundary because it only searches for
-- a brace before that opener.
do
  local baseline = scan({
    "outer() {",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "}",
  })
  local lines = {
    "outer() {",
    "  cat <<-'NEW'",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "}",
    "NEW",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 7)
  assert(preserve_boundary(baseline, current, lines),
    "the previous old-heredoc identity should be recognised")
  assert(current.regions[1].boundary_line == nil,
    "current helper does not select the intervening opener as a boundary")
  assert(current.regions[1].terminator_line == 7,
    "current helper leaves the later NEW terminator assigned across the old opener")
end

-- Case 4: queue identity is source order, not delimiter uniqueness. Different
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

-- Case 5: heredoc-looking payload is not an independently recognised opener.
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
