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
  local buf = set_buffer({ "echo ok" })
  vim.bo[buf].expandtab = true
  vim.bo[buf].tabstop = 8
  vim.bo[buf].softtabstop = 6
  vim.bo[buf].shiftwidth = 4
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  assert(vim.bo[buf].expandtab == true, "setup must not apply the obsolete opener-positioning workaround")
  assert(vim.bo[buf].tabstop == 8, "setup must not change the buffer tabstop")
  assert(vim.bo[buf].softtabstop == 6, "setup must not change the buffer softtabstop")
  assert(vim.bo[buf].shiftwidth == 4, "setup must not change the buffer shiftwidth")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "cat <<-EOF", "payload" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[1] == "cat <<-EOF", "the opener must remain at column zero without a leading TAB")
  assert(actual[2] == "\tpayload", "the body must receive its structural TAB without option changes")
  assert(actual[3] == "EOF", "the closer must align with the opener at column zero")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[1] == "\tcat <<-EOF")
  assert(actual[2] == "\t\t")
  assert(actual[3] == "\tEOF")
end

do
  local buf = set_buffer({
    "  cat <<-'EOF'",
    "  ",
    "later_function() {",
    "  cat <<'EOF'",
    "payload",
    "EOF",
    "}",
  })
  vim.bo[buf].tabstop = 2
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  assert(plugin.process_buffer(buf, { start_row = 0, end_row = 1 }, false),
    "Return-local recognition should insert a closer without consulting a later same-delimiter heredoc")
  local actual = lines(buf)
  assert(actual[1] == "  cat <<-'EOF'")
  assert(actual[2] == "\t\t", "the first body line should receive its structural TAB prefix")
  assert(actual[3] == "\tEOF", "the new closer should be inserted before the later function")
  assert(actual[4] == "later_function() {"
    and actual[5] == "  cat <<'EOF'"
    and actual[6] == "payload"
    and actual[7] == "EOF"
    and actual[8] == "}",
    "the later same-delimiter heredoc and its enclosing structure must remain unchanged")
  assert(not plugin.process_buffer(buf, { start_row = 0, end_row = 1 }, false),
    "reprocessing the same Return range must not duplicate the closer")
  assert(#lines(buf) == 8, "the local closer must remain unique")
end

do
  -- A first body line containing literal TABs is whitespace-only too.
  -- Return-local recovery must recognise it just as it recognises spaces.
  local buf = set_buffer({
    "  cat <<-'TAB_BODY'",
    "\t\t",
    "later_function() {",
    "}",
  })
  vim.bo[buf].tabstop = 2
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  assert(plugin.process_buffer(buf, { start_row = 0, end_row = 1 }, false),
    "Return-local recognition should accept a TAB-indented first body line")
  local actual = lines(buf)
  assert(actual[1] == "  cat <<-'TAB_BODY'")
  assert(actual[2] == "\t\t", "the existing TAB-only body prefix should be preserved")
  assert(actual[3] == "\tTAB_BODY", "the closer should be inserted after the TAB-only body line")
  assert(actual[4] == "later_function() {"
    and actual[5] == "}", "following structure should remain unchanged")
end

do
  local original = { "cat <<-A <<-B", "", "}" }
  local buf = set_buffer(original)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  assert(not plugin.process_buffer(buf, { start_row = 0, end_row = 2 }, false),
    "multiple queued openers must not fall through to document-wide Return recovery")
  local actual = lines(buf)
  assert(#actual == #original and actual[1] == original[1]
    and actual[2] == original[2] and actual[3] == original[3],
    "unsupported multiple-queue Return placement must leave the buffer unchanged")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\t  already", "  pasted", "" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[2] == "\t\t  already", "existing structural prefix must not duplicate")
  assert(actual[3] == "\t\t  pasted", "body spaces must remain after structural TAB; lines=" .. vim.inspect(actual))
  assert(actual[4] == "\t\t", "empty body line must receive the deeper body prefix")
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
  assert(actual[3] == "\t\t  changed", "only the supplied changed range should receive the structural prefix")
  local cursor = vim.api.nvim_win_get_cursor(0)
  assert(cursor[1] == 3 and cursor[2] == 4, "cursor should remain on the same payload byte after prefix insertion")
  assert(not plugin.process_buffer(buf, { start_row = 2, end_row = 3 }, false), "repeated changed-range processing must be idempotent")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\tuntouched", "  changed", "\tEOF" })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "  changed by API" })
  assert(vim.wait(1000, function()
    return lines(buf)[3] == "\t\t  changed by API"
  end, 10), "on_lines should schedule prefixing for the changed body range; snapshot="
    .. vim.inspect(plugin._snapshot_for_test(buf)))
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
    return actual[2] == "\t\t  first changed" and actual[4] == "\t\t  third changed"
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
    return actual[2] == "\t\t  inserted before first"
      and actual[5] == "\t\t  third changed"
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
    return actual[3] == "\t\t  third changed"
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
    return actual[3] == "\t\t  replacement one"
      and actual[4] == "\t\t  replacement two"
      and actual[5] == "\t\t  replacement three"
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
    return actual[2] == "\t\t  merged one" and actual[3] == "\t\t  merged two"
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
    return actual[3] == "\t\t  inserted at range start"
      and actual[4] == "\t\t  changed"
  end, 10), "insertion at a pending range boundary should retain both changed lines")
  local actual = lines(buf)
  assert(actual[2] == "\tbefore" and actual[5] == "\tafter",
    "boundary insertion must not widen into adjacent unchanged lines")
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
  local buf = set_buffer({ "  cat <<-EOF", "  ", "payload", "    nested" })
  vim.bo[buf].tabstop = 2
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[1] == "  cat <<-EOF", "the opener must retain its original visual indentation bytes")
  assert(actual[2] == "\t\t  ", "pre-existing whitespace-only payload must retain its spaces after structural TAB")
  assert(actual[3] == "\t\tpayload", "body must be indented one literal TAB beyond the opener")
  assert(actual[4] == "\t\t    nested", "additional payload spaces must remain unchanged")
  assert(actual[5] == "\tEOF", "the closer must align with the opener and omit the extra body TAB")
end

do
  local buf = set_buffer({ "\tcat <<-EOF", "\t  existing", "\tEOF" })
  assert(plugin.process_buffer(buf))
  local actual = lines(buf)
  assert(actual[2] == "\t\t  existing",
    "an existing opener-aligned body prefix must gain exactly one additional TAB")
  assert(actual[3] == "\tEOF", "the closing delimiter must retain only opener alignment")
end

do
  local buf = set_buffer({ "   cat <<-EOF", "body" })
  vim.bo[buf].tabstop = 2
  assert(not plugin.process_buffer(buf), "unrepresentable visual columns must not be silently shifted")
  local actual = lines(buf)
  assert(#actual == 2 and actual[1] == "   cat <<-EOF" and actual[2] == "body")
end

do
  local buf = set_buffer({
    "\tcat <<-'EOF'",
    "\t\tpayload",
    "\t\t  nested",
    "\t\t",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\tcat <<'EOF'" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[2] == "payload"
      and actual[3] == "  nested"
      and actual[4] == ""
      and actual[5] == "EOF"
  end, 10), "removing <<- should remove the structural body and closer TABs")

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\tcat <<-'EOF'" })
  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[2] == "\t\tpayload"
      and actual[3] == "\t\t  nested"
      and actual[4] == "\t\t"
      and actual[5] == "\tEOF"
  end, 10), "restoring <<- should reapply the structural body and closer TABs")
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
  assert(actual[5] == "\t\tsecond")
  assert(actual[6] == "\tB")
end

do
  local original = {
    "conf_print_test1() {",
    "  cat <<'EOF'",
    "hello1",
    " hello2",
    "EOF",
    "}",
  }
  local buf = set_buffer(original)
  vim.bo[buf].tabstop = 2
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()

  -- Model creating a new function above the existing function. The new
  -- function's autoclose brace is already present; Enter after the heredoc
  -- opener has created its first blank body line.
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "conf_print_test2() {",
    "  cat <<-'EOF'",
    "  ",
    "  }",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  assert(plugin.process_buffer(buf, { start_row = 1, end_row = 3 }, false),
    "the new function heredoc should reserve its closer before the autoclose brace")

  local actual = lines(buf)
  assert(actual[2] == "  cat <<-'EOF'", "the new opener must remain unchanged")
  assert(actual[3] == "\t\t", "the first body line must receive the structural body prefix")
  assert(actual[4] == "\tEOF", "the new closer must be inserted before the new function's brace; lines="
    .. vim.inspect(actual))
  assert(actual[5] == "  }", "the new function autoclose brace must remain outside the heredoc")
  for index, line in ipairs(original) do
    assert(actual[index + 5] == line,
      "the existing function-wrapped heredoc must remain byte-identical at original line " .. index)
  end
end

do
  local original = {
    "conf_print_test1() {",
    "  cat <<'EOF'",
    "hello1",
    "EOF",
    "}",
  }
  local buf = set_buffer(original)
  vim.bo[buf].tabstop = 2
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()

  -- Removing the function's autoclose brace withdraws the boundary. The
  -- following source is then allowed to remain inside the new heredoc.
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "conf_print_test2() {",
    "  cat <<-'EOF'",
    "  ",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  assert(vim.wait(1000, function()
    return lines(buf)[3] == "\t\t"
  end, 10), "the first body line should still receive its structural prefix")

  local actual = lines(buf)
  assert(actual[3] == "\t\t", "the body line should be prefixed without a function boundary")
  assert(actual[4] == "conf_print_test1() {",
    "deleting the autoclose brace must not cause a synthetic closer before following code")
end


-- Regression: function-wrapped managed heredocs must keep heredoc-looking
-- payload opaque and match the actual delimiter/<<- terminator rules.
do
  local cases = {
    {
      name = "function-wrapped EOF with spaces rejected and TAB accepted",
      source = {
        "conf_print_test4() {",
        "  cat <<-'EOF'",
        "  cat <<'EOF'",
        "      hello1",
        "          hello2",
        "              hello3",
        "                  hello4",
        "    EOF",
        "\tEOF",
        "}",
      },
      terminator = "\tEOF",
      terminator_index = 9,
      payload = "\t\t  cat <<'EOF'",
    },
    {
      name = "function-wrapped FOE delimiter",
      source = {
        "conf_print_test3() {",
        "  cat <<-'FOE'",
        "hello1",
        "hello2",
        "hello3",
        "hello4",
        "\tFOE",
        "}",
      },
      terminator = "\tFOE",
      terminator_index = 7,
      payload = nil,
    },
    {
      name = "function-wrapped payload opener does not queue",
      source = {
        "conf_print_test2() {",
        "  cat <<-'EOF'",
        "cat <<-'EOF'",
        "hello1",
        "hello2",
        "hello3",
        "hello4",
        "EOF",
        "  EOF",
        "}",
      },
      terminator = "EOF",
      terminator_index = 8,
      payload = "\t\tcat <<-'EOF'",
    },
  }

  for _, case in ipairs(cases) do
    local buf = set_buffer(case.source)
    vim.bo[buf].tabstop = 2
    assert(plugin.process_buffer(buf), case.name .. ": managed body should be processed")
    local actual = lines(buf)
    assert(actual[#actual] == "}", case.name .. ": function boundary must remain last")
    assert(actual[case.terminator_index] == case.terminator,
      case.name .. ": expected terminator at its source position; lines=" .. vim.inspect(actual))
    if case.payload then
      assert(actual[3] == case.payload,
        case.name .. ": heredoc-looking payload must remain payload; lines=" .. vim.inspect(actual))
    end
  end
end




do
  local buf = set_buffer({
    "\tcat <<-'EOF'",
    "\t\tpayload",
    "\t\t  nested",
    "\t\t",
    "\tEOF",
  })
  vim.api.nvim_set_current_buf(buf)
  plugin.setup()

  -- Change the operator while introducing a payload line that exactly
  -- matches the previous opener. It must not be mistaken for a displaced
  -- opener: inside the heredoc it is payload, not a shell command.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "\tcat <<'EOF'",
    "\tcat <<-'EOF'",
    "\t\tpayload",
    "\t\t  nested",
    "\t\t",
    "\tEOF",
  })

  assert(vim.wait(1000, function()
    local actual = lines(buf)
    return actual[3] == "payload"
      and actual[4] == "  nested"
      and actual[5] == ""
      and actual[6] == "EOF"
  end, 10), "an opener-looking payload line must not suppress managed-prefix removal")
end

print("buffer integration tests: PASS")
