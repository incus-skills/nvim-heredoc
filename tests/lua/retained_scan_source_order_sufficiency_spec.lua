package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")

local function scan(lines)
  return scanner.scan(table.concat(lines, "\n"))
end

-- The retained complete scan is the only historical input. Its opener rows
-- are adjusted once for a known insertion; no text matching or document
-- search is used to associate retained records with current source.
local function adjust_retained_rows_for_insertion(retained, first_line, count)
  for _, heredoc in ipairs(retained.heredocs) do
    if heredoc.opener_line and heredoc.opener_line >= first_line then
      heredoc.opener_line = heredoc.opener_line + count
    end
  end
end

-- Replacement invalidates the retained source position. Identical text does
-- not restore it and no later scan is used to rediscover the old identity.
local function invalidate_replaced_opener(retained, replaced_line)
  for _, heredoc in ipairs(retained.heredocs) do
    if heredoc.opener_line == replaced_line then
      heredoc.opener_line = nil
    end
  end
end

-- Composition of the existing source-order selector with scanner records:
-- current scan supplies the new opener and candidate terminator; the one
-- retained complete scan supplies independently recognised prior openers.
-- The optional function close competes by source position, not by case type.
local function select_boundary(current, retained, function_close)
  assert(current.complete, "current scan must provide a complete candidate")
  assert(retained.complete, "retained scan must be complete")

  local new = assert(current.heredocs[1], "current scan must contain the new heredoc")
  local selected = { kind = "terminator", row = assert(new.terminator_line) }

  local function consider(kind, row)
    if row and row > new.opener_line and row < selected.row then
      selected = { kind = kind, row = row }
    end
  end

  consider("function_close", function_close)
  for _, prior in ipairs(retained.heredocs) do
    -- Only retained scanner source positions are considered. Delimiter,
    -- opener text, body text and current textual resemblance are irrelevant.
    consider("intervening_opener", prior.opener_line)
  end

  return selected
end

local function assert_boundary(actual, kind, row, message)
  assert(actual.kind == kind and actual.row == row,
    string.format("%s: expected %s at line %d, got %s at line %s",
      message, kind, row, actual.kind, tostring(actual.row)))
end

-- 1. Standalone: the prior opener is retained across insertion above it and
-- blocks the new opener from claiming the later candidate terminator.
do
  local retained = scan({
    "cat <<'OLD'",
    "old payload",
    "OLD",
  })
  assert(retained.complete and #retained.heredocs == 1)

  local current = scan({
    "cat <<-'NEW'",
    "cat <<'OLD'",
    "old payload",
    "OLD",
    "new payload",
    "NEW",
  })
  assert(current.complete and current.heredocs[1].terminator_line == 6)

  adjust_retained_rows_for_insertion(retained, 1, 1)
  assert(retained.heredocs[1].opener_line == 2,
    "the retained opener position must rebase after the insertion")

  local actual = select_boundary(current, retained, nil)
  assert_boundary(actual, "intervening_opener", 2,
    "standalone retained opener blocks candidate")
end

-- 2. Function-wrapped: the function close wins when it precedes the retained
-- opener. The selector must not prefer the opener merely because it is a
-- heredoc boundary.
do
  local retained = scan({
    "old_fn() {",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "}",
  })
  assert(retained.complete and #retained.heredocs == 1)

  local current = scan({
    "new_fn() {",
    "  cat <<-'NEW'",
    "}",
    "old_fn() {",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "new payload",
    "NEW",
  })
  assert(current.complete and current.heredocs[1].terminator_line == 9)

  adjust_retained_rows_for_insertion(retained, 1, 3)
  assert(retained.heredocs[1].opener_line == 5)

  local actual = select_boundary(current, retained, 3)
  assert_boundary(actual, "function_close", 3,
    "function close precedes retained opener")
end

-- 3. Function-wrapped inverse: the retained opener wins when it precedes the
-- function close. This guards against a fixed preference for function scope.
do
  local retained = scan({
    "outer() {",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "}",
  })
  assert(retained.complete and #retained.heredocs == 1)

  local current = scan({
    "outer() {",
    "  cat <<-'OLD'",
    "  cat <<'OLD'",
    "old payload",
    "OLD",
    "}",
  })
  assert(current.complete and current.heredocs[1].terminator_line == 5)

  adjust_retained_rows_for_insertion(retained, 1, 1)
  assert(retained.heredocs[1].opener_line == 3)

  local actual = select_boundary(current, retained, 6)
  assert_boundary(actual, "intervening_opener", 3,
    "retained opener precedes function close")
end

-- 4. Payload lookalikes and repeated delimiters: the baseline scanner records
-- the two actual queued redirections (same delimiter, distinct queue slots),
-- but does not create records for opener-looking or brace-like payload lines.
do
  local retained = scan({
    "command <<'A' <<'A'",
    "cat <<'A'",
    "}",
    "first body",
    "A",
    "second body",
    "A",
  })
  assert(retained.complete and #retained.heredocs == 2,
    "only the two source redirections should be retained")
  assert(retained.heredocs[1].queue_position == 1)
  assert(retained.heredocs[2].queue_position == 2)
  assert(retained.heredocs[1].delimiter == "A"
    and retained.heredocs[2].delimiter == "A")

  local current = scan({
    "cat <<-'NEW'",
    "command <<'A' <<'A'",
    "cat <<'A'",
    "}",
    "first body",
    "A",
    "second body",
    "A",
    "NEW",
  })
  assert(current.complete and current.heredocs[1].terminator_line == 9)

  adjust_retained_rows_for_insertion(retained, 1, 1)
  local actual = select_boundary(current, retained, nil)
  assert_boundary(actual, "intervening_opener", 2,
    "only independently recognised source openers can block")
end

-- 5. Continuity is not textual equality. After the same insertion/rebase,
-- replacing the retained opener with identical text invalidates its source
-- position. The selector must not restore it or search for a matching line.
do
  local retained = scan({
    "cat <<'OLD'",
    "old payload",
    "OLD",
  })
  local current = scan({
    "cat <<-'NEW'",
    "cat <<'OLD'",
    "old payload",
    "OLD",
    "new payload",
    "NEW",
  })
  assert(retained.complete and current.complete)

  adjust_retained_rows_for_insertion(retained, 1, 1)
  assert(retained.heredocs[1].opener_line == 2)
  invalidate_replaced_opener(retained, 2)
  assert(retained.heredocs[1].opener_line == nil,
    "identical-text replacement must invalidate the retained source position")

  local actual = select_boundary(current, retained, nil)
  assert_boundary(actual, "terminator", 6,
    "invalidated opener must not be rediscovered by text")
end

print("retained-scan source-order sufficiency composition: PASS")
