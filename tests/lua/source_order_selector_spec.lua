-- Reference model for selecting the first source-order boundary for a heredoc.
-- This is an executable specification only; it does not call production code.

local function select_boundary(new_opener, candidate_terminator, prior_openers, function_close)
  local selected = {
    kind = "terminator",
    row = candidate_terminator,
  }

  local function consider(kind, row)
    if row and row > new_opener.row and row < selected.row then
      selected = { kind = kind, row = row }
    end
  end

  -- A function close is structural source, not heredoc payload.
  consider("function_close", function_close)

  -- Only independently retained opener identities are eligible here.
  -- Delimiter spelling and current textual resemblance are deliberately
  -- irrelevant: identity and current source position establish the blocker.
  for _, opener in ipairs(prior_openers) do
    if opener.valid and opener.id ~= new_opener.id then
      consider("intervening_opener", opener.row)
    end
  end

  return selected
end

local function assert_boundary(actual, kind, row, message)
  assert(actual.kind == kind and actual.row == row,
    string.format("%s: expected %s at row %d, got %s at row %d",
      message, kind, row, actual.kind, actual.row))
end

-- Standalone: a previously recognised opener blocks a later matching closer.
-- Its delimiter differs from the new opener's delimiter.
do
  local actual = select_boundary(
    { id = "new", row = 1 },
    8,
    { { id = "old", row = 4, delimiter = "OLD", valid = true } },
    nil
  )
  assert_boundary(actual, "intervening_opener", 4, "standalone different delimiter")
end

-- Function-wrapped: the enclosing function close is the first boundary.
do
  local actual = select_boundary(
    { id = "new", row = 1 },
    9,
    { { id = "old", row = 6, delimiter = "OLD", valid = true } },
    3
  )
  assert_boundary(actual, "function_close", 3, "function close before old opener")
end

-- Function-wrapped: when the prior opener comes first, it is the boundary.
do
  local actual = select_boundary(
    { id = "new", row = 1 },
    10,
    { { id = "old", row = 3, delimiter = "SAME", valid = true } },
    7
  )
  assert_boundary(actual, "intervening_opener", 3, "old opener before function close")
end

-- With no earlier structural boundary, the scanner's candidate terminator
-- remains available.
do
  local actual = select_boundary({ id = "new", row = 2 }, 6, {}, nil)
  assert_boundary(actual, "terminator", 6, "unblocked candidate")
end

-- Several retained identities: choose the earliest source-order opener,
-- not the first record in storage order and not the one sharing a delimiter.
do
  local actual = select_boundary(
    { id = "new", row = 1 },
    12,
    {
      { id = "later", row = 8, delimiter = "SAME", valid = true },
      { id = "earlier", row = 4, delimiter = "OTHER", valid = true },
      { id = "invalid", row = 2, delimiter = "SAME", valid = false },
    },
    nil
  )
  assert_boundary(actual, "intervening_opener", 4, "earliest valid identity")
end

-- Payload lookalikes are not identities. A brace and an opener-looking line
-- inside an active heredoc body must not become boundaries merely by text.
do
  local payload = {
    { row = 3, text = "}" },
    { row = 4, text = "  cat <<'OLD'" },
  }
  local retained_identities = {}
  local actual = select_boundary({ id = "new", row = 1 }, 8, retained_identities, nil)
  assert_boundary(actual, "terminator", 8, "payload lookalikes ignored")
  assert(#payload == 2)
end

-- Queue identity is independent of delimiter equality. Records on one
-- command line retain source redirection order, including repeated values.
do
  local queued = {
    { id = "third", row = 2, queue_position = 3, delimiter = "A" },
    { id = "first", row = 2, queue_position = 1, delimiter = "A" },
    { id = "second", row = 2, queue_position = 2, delimiter = "B" },
  }
  table.sort(queued, function(a, b)
    if a.row == b.row then
      return a.queue_position < b.queue_position
    end
    return a.row < b.row
  end)
  assert(queued[1].id == "first")
  assert(queued[2].id == "second")
  assert(queued[3].id == "third")
  assert(queued[1].delimiter == queued[3].delimiter)
end

print("source-order selector reference model: PASS")
