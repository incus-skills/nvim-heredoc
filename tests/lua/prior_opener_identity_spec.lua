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

-- Case 1: a previously recognised opener can be found after lines are inserted
-- above it. This shows that the current helper uses text search rather than a
-- stable source identity or the previous line number.
do
  local baseline = scan({
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  assert(baseline.complete and #baseline.heredocs == 1)

  local lines = {
    "new_function() {",
    "  cat <<-'EOF'",
    "}",
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
    "NEW",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 7)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == 3,
    "the matching prior opener should still be found after its line shifts")
end

-- Case 2: two prior completed records can both be represented in the apparent
-- new body if their old terminator lines have been edited. The current helper
-- stops at the first prior opener match; it does not select that opener as a
-- boundary, even though a later brace exists before the second prior opener.
do
  local baseline = scan({
    "cat <<'EOF'",
    "first payload",
    "EOF",
    "printf x <<'EOF'",
    "second payload",
    "EOF",
  })
  assert(baseline.complete and #baseline.heredocs == 2)

  local lines = {
    "new_function() {",
    "  cat <<-'EOF'",
    "cat <<'EOF'",
    "first payload",
    "FIRST-END",
    "}",
    "printf x <<'EOF'",
    "second payload",
    "SECOND-END",
    "EOF",
    "}",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 10)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == nil,
    "the helper recognises the first prior opener but does not select it as a boundary")
  assert(current.regions[1].terminator_line == 10,
    "the candidate terminator remains assigned across both prior opener obligations")
end

-- Case 3: exact opener text inside the active body is indistinguishable from
-- the shifted prior opener to the current helper. A body '}' before that text
-- is mistaken for the function boundary, although the actual function close
-- is after the scanner's apparent terminator.
do
  local baseline = scan({
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  assert(baseline.complete and #baseline.heredocs == 1)

  local lines = {
    "new_function() {",
    "  cat <<-'EOF'",
    "}", -- body payload, not the function close
    "  cat <<'EOF'", -- body text identical to the prior opener
    "old_function() {",
    "  cat <<'EOF'", -- actual prior opener, later in the body
    "old payload",
    "EOF",
    "}", -- actual new-function close, after the apparent terminator
    "NEW",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 8)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == 3,
    "the helper falsely associates payload text and a payload brace with the prior structure")
end

print("prior opener identity characterization: PASS")
