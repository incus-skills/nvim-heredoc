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

-- Case 2: when more than one prior completed opener lies in the apparent new
-- body, the helper's prior-record order and source search select the first
-- opener in source order.
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
  assert(baseline.heredocs[1].opener_text == "cat <<'EOF'")
  assert(baseline.heredocs[2].opener_text == "printf x <<'EOF'")

  local lines = {
    "new_function() {",
    "  cat <<-'EOF'",
    "}",
    "cat <<'EOF'",
    "first payload",
    "EOF",
    "printf x <<'EOF'",
    "second payload",
    "EOF",
    "NEW",
  }
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 6)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == 3,
    "the first prior opener in source order should determine the earlier boundary")
end

-- Case 3: exact opener text inside the active body is indistinguishable from
-- the shifted prior opener to the current helper. A preceding body '}' is also
-- mistaken for the function boundary, even though both lines are heredoc
-- payload and the actual prior opener occurs later.
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
    "  cat <<'EOF'", -- body text identical to the prior opener
    "old_function() {",
    "  cat <<'EOF'", -- actual prior opener, later in the body
    "old payload",
    "EOF",
    "}",
    "NEW",
  }
  -- The first '}' is before the fake opener and is payload too: all of these
  -- lines are opaque body content to the scanner until the EOF line.
  local current = scan(lines)
  assert(current.complete and current.regions[1].terminator_line == 8)
  assert(preserve_boundary(baseline, current, lines))
  assert(current.regions[1].boundary_line == 3,
    "the helper falsely associates payload text and a payload brace with the prior structure")
end

print("prior opener identity characterization: PASS")
