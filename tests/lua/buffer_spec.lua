package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local plugin = require("nvim-heredoc")

local function set_buffer(lines, ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or "bash"
  return buf
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[1] == "\tcat <<-EOF")
  assert(actual[2] == "\t")
  assert(actual[3] == "\tEOF")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\t  already", "  pasted", "" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[2] == "\t  already", "existing structural prefix must not duplicate")
  assert(actual[3] == "\t  pasted", "body spaces must remain after structural TAB")
  assert(actual[4] == "\t")
  assert(actual[5] == "\tEOF")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\tfirst", "  changed", "\tEOF" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  local changed = plugin.process_buffer(buf, { start_row = 2, end_row = 3 }, false)
  assert(changed)
  local actual = lines(buf)
  assert(actual[2] == "\tfirst", "unmodified body lines must remain untouched by a changed-range operation")
  assert(actual[3] == "\t  changed", "only the supplied changed range should receive the structural prefix")
  local cursor = vim.api.nvim_win_get_cursor(0)
  assert(cursor[1] == 3 and cursor[2] == 3, "cursor should remain on the same payload byte after prefix insertion")
  assert(not plugin.process_buffer(buf, { start_row = 2, end_row = 3 }, false), "repeated changed-range processing must be idempotent")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\tuntouched", "  changed", "\tEOF" })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "  changed by API" })
  assert(vim.wait(1000, function()
    return lines(buf)[3] == "\t  changed by API"
  end, 10), "on_lines should schedule prefixing for the changed body range")
  local actual = lines(buf)
  assert(actual[2] == "\tuntouched", "on_lines must not rewrite an unchanged body line")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tfirst",
    "untouched middle",
    "\tthird",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- Two disjoint edits in one scheduling window must remain separate ranges.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  first changed" })
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  third changed" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[2] == "\t  first changed" and actual[4] == "\t  third changed"
  end, 10), "both disjoint changed ranges should receive their structural prefix")
  local actual = lines(buf)
  assert(actual[3] == "untouched middle",
    "coalescing disjoint edits must not prefix an untouched line between them")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tfirst",
    "untouched middle",
    "\tthird",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- First edit a later line, then insert before it before scheduled processing.
  -- The earlier pending range must follow the old line to its new row.
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  third changed" })
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "  inserted before first" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[2] == "\t  inserted before first"
      and actual[5] == "\t  third changed"
  end, 10), "pending changed ranges should be rebased after a line insertion")
  local actual = lines(buf)
  assert(actual[4] == "untouched middle",
    "line insertion before a pending range must not redirect it onto an untouched line")
  assert(actual[3] == "\tfirst",
    "the insertion must not cause unrelated body lines to be rewritten")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tfirst",
    "untouched middle",
    "\tthird",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- Delete a line before a pending edit. Its old row must shift upward.
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  third changed" })
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[3] == "\t  third changed"
  end, 10), "pending changed ranges should be rebased after a line deletion")
  local actual = lines(buf)
  assert(actual[2] == "untouched middle",
    "line deletion before a pending range must not redirect it onto an untouched line")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tbefore",
    "untouched one",
    "untouched two",
    "\tlast",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- A later replacement overlaps the first pending range and changes line
  -- count. The resulting replacement interval must be treated as one edit.
  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "  last changed" })
  vim.api.nvim_buf_set_lines(buf, 2, 5, false, {
    "  replacement one",
    "  replacement two",
    "  replacement three",
  })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[3] == "\t  replacement one"
      and actual[4] == "\t  replacement two"
      and actual[5] == "\t  replacement three"
  end, 10), "overlapping replacement should rebase and merge the pending interval")
  local actual = lines(buf)
  assert(actual[2] == "\tbefore", "overlapping replacement must not expand into the preceding line")
  assert(actual[6] == "\tEOF", "overlapping replacement must not consume the terminator")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tfirst",
    "untouched middle",
    "\tthird",
    "\tfourth",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- Two previously disjoint pending edits are both swallowed by a single
  -- replacement. Their intervals must collapse onto the replacement range.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  first changed" })
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  third changed" })
  vim.api.nvim_buf_set_lines(buf, 1, 4, false, {
    "  merged one",
    "  merged two",
  })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[2] == "\t  merged one" and actual[3] == "\t  merged two"
  end, 10), "replacement spanning multiple pending ranges should merge onto new content")
  local actual = lines(buf)
  assert(actual[4] == "\tfourth", "replacement merge must not prefix the untouched line after it")
  assert(actual[5] == "\tEOF", "replacement merge must preserve the terminator")
end

do
  local buf = set_buffer({
    "\tcat <<-EOF",
    "\tbefore",
    "  changed",
    "\tafter",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- Inserting at the beginning of a pending interval creates a second
  -- adjacent changed interval; both should be prefixed, but not its neighbor.
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "  changed" })
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "  inserted at range start" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[3] == "\t  inserted at range start"
      and actual[4] == "\t  changed"
  end, 10), "insertion at a pending range boundary should retain both changed lines")
  local actual = lines(buf)
  assert(actual[2] == "\tbefore" and actual[5] == "\tafter",
    "boundary insertion must not widen into adjacent unchanged lines")
end

do
  -- Enter after an opener inside a function must create the closer immediately
  -- before the existing function terminator, without waiting for InsertLeave.
  local buf = set_buffer({ "my_function() {", "\tcat <<-EOF", "}" })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  -- Edits to the opener itself must not create the closer prematurely.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "\tcat <<-EOF" })
  vim.wait(100, function() return false end, 10)
  assert(#lines(buf) == 3 and lines(buf)[3] == "}",
    "typing the opener must not treat the existing function terminator as a body line")
  -- This insertion represents Enter after the opener: the new body line is
  -- now part of the changed range and authorises immediate closer creation.
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[4] == "\tEOF"
  end, 10), "on_lines should insert the closer immediately after Enter")
  local actual = lines(buf)
  assert(actual[1] == "my_function() {")
  assert(actual[2] == "\tcat <<-EOF")
  assert(actual[3] == "\t", "the new body line should receive its structural TAB")
  assert(actual[4] == "\tEOF", "the closer must precede the enclosing function terminator")
  assert(actual[5] == "}", "the enclosing function terminator must remain outside the heredoc")

  -- Typing into the body should be prefixed by the scheduled on_lines path,
  -- while still in the editing session (no InsertLeave event is fired).
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "typed payload" })
  assert(vim.wait(1000, function()
    return lines(buf)[3] == "\ttyped payload"
  end, 10), "typed body content should receive structural indentation live")

  -- A multi-line paste is one changed range; preserve payload spaces and
  -- relative indentation while adding only the structural TAB.
  vim.api.nvim_buf_set_lines(buf, 3, 3, false, { "  pasted one", "    pasted two", "" })
  assert(vim.wait(1000, function()
    local actual_lines = lines(buf)
    return actual_lines[4] == "\t  pasted one"
      and actual_lines[5] == "\t    pasted two"
      and actual_lines[6] == "\t"
  end, 10), "pasted body lines should receive structural indentation live")
  actual = lines(buf)
  assert(actual[7] == "\tEOF", "live body edits must leave the closer below the payload")
  assert(actual[8] == "}", "live body edits must preserve the enclosing function")
end

do
  local buf = set_buffer({ "\tcat <<-AUTO", "" })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  local actual = lines(buf)
  assert(actual[3] == "\tAUTO", "InsertLeave should invoke automatic closer placement")
end

do
  local buf = set_buffer({ "    cat <<-EOF", "body" })
  assert(not plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(#actual == 2 and actual[1] == "    cat <<-EOF" and actual[2] == "body")
end

do
  local buf = set_buffer({ "cat <<EOF", "body" })
  assert(not plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(#actual == 2 and actual[1] == "cat <<EOF" and actual[2] == "body")
end

do
  local buf = set_buffer({ "\tcat <<-A <<-B", "", "first", "A", "second" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[5] == "\tsecond")
  assert(actual[6] == "\tB")
end

print("buffer integration tests: PASS")
