package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local planner = require("nvim-heredoc.planner")

local function region(opts)
  local value = {
    operator = "<<-", delimiter = "EOF",
    command_start_line = 1, command_end_line = 1,
    opener_line = 1, body_start_line = 2, body_end_line = 3,
    terminator_line = 4, queue_position = 1, is_final_in_queue = true,
  }
  for key, item in pairs(opts or {}) do value[key] = item end
  return value
end

local function snapshot(regions, checkpoints, complete)
  return { regions = regions, heredocs = regions, checkpoints = checkpoints or {},
    complete = complete ~= false }
end

local function checkpoint(pos, key)
  return { pos = pos, group_key = key }
end

local function plan(old, edits, lines)
  return planner.plan(old, edits, lines)
end

local function contains(values, wanted)
  for _, value in ipairs(values) do
    if value == wanted then return true end
  end
  return false
end

-- Insertion before the snapshot shifts every surviving line coordinate.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 0, lastline = 0, new_lastline = 1 },
  }, { "inserted", "cat <<-EOF", "payload", "more", "EOF" })
  local mapped = result.mapped_snapshot.heredocs[1]
  assert(mapped.command_start_line == 2 and mapped.command_end_line == 2)
  assert(mapped.opener_line == 2 and mapped.body_start_line == 3)
  assert(mapped.body_end_line == 4 and mapped.terminator_line == 5)
  assert(result.mapped_snapshot.checkpoints[1].pos == 6)
  assert(result.mapped_snapshot.checkpoints[1].group_key == 2)
  assert(contains(result.R, 1))
end

-- Later events use the coordinate space produced by earlier events in the batch.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 0, lastline = 0, new_lastline = 1 },
    { firstline = 4, lastline = 5, new_lastline = 5 },
  }, { "prefix", "cat <<-EOF", "payload", "more", "changed terminator" })
  local mapped = result.mapped_snapshot.heredocs[1]
  assert(mapped.opener_line == 2 and mapped.terminator_line == nil)
  assert(result.mapped_snapshot.checkpoints[1].pos == 6)
  assert(#result.I == 1 and contains(result.R_structural, 5))
end

-- Deletion before a region shifts its line coordinates in the opposite direction.
do
  local old = snapshot({ region({
    command_start_line = 2, command_end_line = 2, opener_line = 2,
    body_start_line = 3, body_end_line = 4, terminator_line = 5,
  }) }, { checkpoint(6, 2) })
  local result = plan(old, {
    { firstline = 0, lastline = 1, new_lastline = 0 },
  }, { "cat <<-EOF", "payload", "more", "EOF" })
  local mapped = result.mapped_snapshot.heredocs[1]
  assert(mapped.opener_line == 1 and mapped.body_start_line == 2)
  assert(mapped.terminator_line == 4)
  assert(result.mapped_snapshot.checkpoints[1].pos == 5)
end

-- Same-count replacement preserves later coordinates but invalidates a group
-- whose command structure/opener line was replaced.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 0, lastline = 1, new_lastline = 1 },
  }, { "new command", "payload", "more", "EOF" })
  assert(result.mapped_snapshot.heredocs[1].opener_line == nil)
  assert(result.I[1].invalidated)
  assert(contains(result.R_structural, 1))
end

-- Join and split events are applied in their own successive coordinate spaces.
do
  local old = snapshot({ region({
    command_start_line = 2, command_end_line = 2, opener_line = 2,
    body_start_line = 3, body_end_line = 4, terminator_line = 5,
  }) }, { checkpoint(6, 2) })
  local joined = plan(old, {
    { firstline = 0, lastline = 2, new_lastline = 1 },
  }, { "joined", "payload", "more", "EOF" })
  assert(joined.mapped_snapshot.heredocs[1].opener_line == nil)
  assert(joined.I[1].invalidated)

  local split_old = snapshot({ region({
    command_start_line = 2, command_end_line = 2, opener_line = 2,
    body_start_line = 3, body_end_line = 3, terminator_line = 4,
  }) }, { checkpoint(5, 2) })
  local split = plan(split_old, {
    { firstline = 0, lastline = 1, new_lastline = 2 },
  }, { "prefix", "new line", "cat <<-EOF", "payload", "EOF" })
  assert(split.mapped_snapshot.heredocs[1].opener_line == 3)
  assert(split.mapped_snapshot.checkpoints[1].pos == 6)
end

-- Checkpoints have before affinity at insertion boundaries.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 4, lastline = 4, new_lastline = 5 },
  }, { "cat <<-EOF", "payload", "more", "EOF", "echo inserted" })
  assert(result.mapped_snapshot.checkpoints[1].pos == 5)
  assert(not result.mapped_snapshot.checkpoints[1].invalidated)
  assert(result.S == 5 and contains(result.R, 5))
  assert(#result.I == 0)
end

-- Inserting between physical lines of a continued command invalidates its
-- group; insertion at the completed group's checkpoint does not.
do
  local continued = region({
    command_start_line = 1, command_end_line = 2, opener_line = 2,
    body_start_line = 3, body_end_line = 3, terminator_line = 4,
  })
  local old = snapshot({ continued }, { checkpoint(5, 2) })
  local result = plan(old, {
    { firstline = 1, lastline = 1, new_lastline = 2 },
  }, { "cat \\", "inserted command line", "<<-EOF", "body", "EOF" })
  assert(#result.I == 1 and contains(result.R_structural, 2))
end

-- Replacing opener, terminator, or command-structure lines invalidates the group.
do
  local cases = {
    {
      item = region(),
      edit = { firstline = 0, lastline = 1, new_lastline = 1 },
      lines = { "changed opener", "payload", "more", "EOF" },
      key = 1,
    },
    {
      item = region(),
      edit = { firstline = 3, lastline = 4, new_lastline = 4 },
      lines = { "cat <<-EOF", "payload", "more", "changed terminator" },
      key = 1,
    },
    {
      item = region({ command_start_line = 1, command_end_line = 2, opener_line = 2 }),
      edit = { firstline = 0, lastline = 1, new_lastline = 1 },
      lines = { "changed continued command", "<<-EOF", "payload", "EOF" },
      key = 2,
    },
  }
  for index, case in ipairs(cases) do
    local old = snapshot({ case.item }, { checkpoint(5, case.key) })
    local result = plan(old, { case.edit }, case.lines)
    assert(#result.I == 1, "structural edit must invalidate checkpoint " .. index)
  end
end

-- Deleting a structural line creates a zero-width structural anchor.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 3, lastline = 4, new_lastline = 3 },
  }, { "cat <<-EOF", "payload", "more" })
  assert(#result.R_content == 0)
  assert(contains(result.R_structural, 4))
  assert(#result.I == 1)
end

-- A later edit that consumes an earlier structural anchor relocates the
-- anchor to its own first resulting position instead of dropping R_structural.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 3, lastline = 4, new_lastline = 5 },
    { firstline = 2, lastline = 5, new_lastline = 2 },
  }, { "cat <<-EOF", "payload" })
  assert(#result.R_content == 0)
  assert(contains(result.R_structural, 3))
  assert(#result.I == 1)
end

-- Matching delimiters inside payload invalidate the owning group. <<- strips
-- leading TABs only; ordinary << requires an exact line match.
do
  local managed = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(managed, {
    { firstline = 2, lastline = 2, new_lastline = 3 },
  }, { "cat <<-EOF", "payload", "\tEOF", "more", "EOF" })
  assert(contains(result.R_content, 3) and #result.I == 1)

  local managed_spaces = plan(managed, {
    { firstline = 2, lastline = 2, new_lastline = 3 },
  }, { "cat <<-EOF", "payload", " EOF", "more", "EOF" })
  assert(#managed_spaces.I == 0,
    "<<- must not strip leading spaces when matching a delimiter")

  local ordinary = snapshot({ region({ operator = "<<" }) }, { checkpoint(5, 1) })
  local exact = plan(ordinary, {
    { firstline = 2, lastline = 2, new_lastline = 3 },
  }, { "cat <<EOF", "payload", "EOF", "more", "EOF" })
  assert(contains(exact.R_content, 3) and #exact.I == 1)

  local spaces_do_not_match = plan(ordinary, {
    { firstline = 2, lastline = 2, new_lastline = 3 },
  }, { "cat <<EOF", "payload", " EOF", "more", "EOF" })
  assert(#spaces_do_not_match.I == 0)
end

-- A delimiter-looking line is compared only with the delimiter of the region
-- whose payload contains it; it cannot invalidate an unrelated group.
do
  local first = region({
    delimiter = "FIRST", command_start_line = 1, command_end_line = 1,
    opener_line = 1, body_start_line = 2, body_end_line = 4, terminator_line = 5,
  })
  local second = region({
    delimiter = "SECOND", command_start_line = 6, command_end_line = 6,
    opener_line = 6, body_start_line = 7, body_end_line = 7, terminator_line = 8,
  })
  local old = snapshot({ first, second }, { checkpoint(6, 1), checkpoint(9, 6) })
  local result = plan(old, {
    { firstline = 2, lastline = 2, new_lastline = 3 },
  }, {
    "cat <<-FIRST", "payload", "SECOND", "more", "still payload",
    "FIRST", "cat <<-SECOND", "payload", "SECOND",
  })
  assert(#result.I == 0)
  assert(#result.R == 0)
end

-- Ordinary payload-only edits do not require lexical rescanning.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 1, lastline = 2, new_lastline = 2 },
  }, { "cat <<-EOF", "changed payload", "more", "EOF" })
  assert(#result.R == 0 and #result.I == 0)
  assert(not result.requires_rescan and result.S == nil and result.E == nil)
end

-- A command inserted at a checkpoint leaves I empty while R is non-empty.
do
  local old = snapshot({ region() }, { checkpoint(5, 1) })
  local result = plan(old, {
    { firstline = 4, lastline = 4, new_lastline = 5 },
  }, { "cat <<-EOF", "payload", "more", "EOF", "echo new command" })
  assert(#result.I == 0 and #result.R > 0)
  assert(result.S == 5)
end

-- S and E bracket the complete footprint using surviving checkpoints.
do
  local a = region({
    command_start_line = 1, command_end_line = 1, opener_line = 1,
    body_start_line = 2, body_end_line = 2, terminator_line = 3,
  })
  local b = region({
    command_start_line = 7, command_end_line = 7, opener_line = 7,
    body_start_line = 8, body_end_line = 8, terminator_line = 9,
  })
  local old = snapshot({ a, b }, { checkpoint(4, 1), checkpoint(10, 7) })
  local result = plan(old, {
    { firstline = 4, lastline = 5, new_lastline = 5 },
  }, {
    "cat <<-EOF", "body", "EOF", "echo before",
    "changed shell line", "echo after", "cat <<-EOF", "body", "EOF",
  })
  assert(result.S == 4 and result.E == 10)
end

-- An incomplete snapshot with a mapped checkpoint at or beyond E requires
-- full-buffer fallback rather than preserving an unproven suffix.
do
  local a = region({
    command_start_line = 1, command_end_line = 1, opener_line = 1,
    body_start_line = 2, body_end_line = 2, terminator_line = 3,
  })
  local b = region({
    command_start_line = 8, command_end_line = 8, opener_line = 8,
    body_start_line = 9, body_end_line = 9, terminator_line = 10,
  })
  local old = snapshot({ a, b }, { checkpoint(4, 1), checkpoint(11, 8) }, false)
  local result = plan(old, {
    { firstline = 4, lastline = 5, new_lastline = 5 },
  }, {
    "cat <<-EOF", "body", "EOF", "echo before",
    "changed shell line", "echo after", "tail",
    "cat <<-EOF", "body", "EOF",
  })
  assert(result.E == 11 and result.fallback_required)
end

print("snapshot planner tests: PASS")
