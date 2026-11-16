package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")

local function one(source)
  local result = scanner.scan(source)
  if #result.regions ~= 1 then
    local messages = {}
    for _, diagnostic in ipairs(result.diagnostics) do
      messages[#messages + 1] = diagnostic.message
    end
    error("expected one managed region, got " .. #result.regions .. "; complete=" .. tostring(result.complete) .. "; diagnostics=" .. table.concat(messages, " | "))
  end
  return result, result.regions[1]
end

do
  local _, r = one("if true; then\n\tcat <<-'END'\n  payload\n\tEND\nfi\n")
  assert(r.operator == "<<-")
  assert(r.delimiter == "END" and r.delimiter_quoted)
  assert(r.opener_line == 2 and r.body_start_line == 3 and r.terminator_line == 4)
  assert(r.structural_prefix == "\t" and r.body_prefix == "\t\t" and r.editable and r.opener_safe)
  assert(editing.closer_line(r) == "\tEND")
end

do
  local _, r = one("cat <<A <<-'B'\nfirst\nA\nsecond\nB\n")
  assert(r.delimiter == "B" and r.queue_position == 2)
  assert(r.body_start_line == 4 and r.terminator_line == 5)
end

do
  local result = scanner.scan("cat <<'PLAIN'\n<<-NOT_CODE\nPLAIN\n")
  assert(#result.regions == 0, "ordinary heredoc body must not be scanned as shell")
end

do
  local result = scanner.scan("echo '<<-NO' # <<-COMMENT\ncat <<<VALUE\necho \\<<<literal\n")
  assert(#result.regions == 0, "quoted/comment/here-string/escaped operators must be ignored")
end

do
  local _, r = one("cat \\\n<<-E\\OF\nbody\nEOF\n")
  assert(r.opener_line == 2 and r.delimiter == "EOF")
  assert(r.terminator_line == 4)
  assert(editing.closer_line(r) == "EOF")
end

do
  local _, r = one("\tcat <<-''\nbody\n\t\n")
  assert(r.delimiter == "" and r.delimiter_original == "''" and r.delimiter_quoted)
  assert(r.terminator_line == 3 and editing.closer_line(r) == "\t")
end

do
  local _, r = one("cat <<-EOF\n  payload\nEOF\n")
  assert(r.structural_tabs_only and r.editable)
  assert(r.body_start_line == 2 and r.terminator_line == 3)
end

do
  local result = scanner.scan("cat <<'EOF'\nbody\nEOF\n")
  assert(#result.regions == 0, "ordinary heredocs remain outside the managed region list")
  assert(#result.heredocs == 1 and result.heredocs[1].operator == "<<",
    "the scanner should expose ordinary heredoc structure for transition detection")
  assert(result.heredocs[1].terminator_line == 3)
end

do
  local result = scanner.scan("cat <<-EOF\nbody\n")
  assert(not result.complete)
  assert(#result.regions == 1 and not result.regions[1].editable)
end

do
  local result, r = one("cat <<-OPEN\nbody\n")
  assert(r.confidence == "incomplete" and r.opener_safe and not r.editable)
  assert(editing.closer_line(r) == "OPEN", "safe incomplete opener may supply an auto-closer")
end

do
  local _, r = one("\tcat <<-END\nbody\n\tEND\n")
  local pasted = { "  alpha", "", "   ", "\tbeta", "\t\tgamma" }
  local once, changed = editing.prefix_lines(r, pasted)
  assert(changed)
  assert(once[1] == "\t\t  alpha" and once[2] == "\t\t" and once[3] == "\t\t   ")
  assert(once[4] == "\t\tbeta" and once[5] == "\t\tgamma")
  local twice, changed_again = editing.prefix_lines(r, once)
  assert(not changed_again, "repeated paste notifications must not duplicate structural prefix")
  for i, line in ipairs(once) do assert(twice[i] == line) end
end

do
  local _, r = one('value=$(printf "x" "$(printf x)")\necho "$((8 << 1))"\ncat <<-EOF\npayload\nEOF\n')
  assert(r.delimiter == "EOF", "ordinary command and arithmetic substitutions should not hide later heredocs")
end

do
  local result = scanner.scan('value=$(cat <<-INNER)\nINNER\ncat <<-OUTER\nbody\nOUTER\n')
  assert(not result.complete and #result.regions == 0, "nested heredoc in command substitution must remain explicitly unsupported")
end

do
  local _, r = one('echo "$(nested)" <<-REAL\n<<-FALSE_POSITIVE\nREAL\n')
  assert(r.delimiter == "REAL" and r.body_start_line == 2 and r.terminator_line == 3)
end

do
  local result = scanner.scan("(( value << 2 ))\n")
  assert(#result.regions == 0, "shift operator in arithmetic context is not a heredoc")
end

do
  local _, r = one("  cat <<-EOF\nbody\nEOF\n")
  assert(r.opener_prefix == "  ", "the opener's original spaces must be recorded unchanged")
  assert(r.structural_prefix == "\t" and r.body_prefix == "\t\t" and r.structural_column == 2)
  assert(r.structural_tabs_only and r.editable and r.opener_safe)
  assert(editing.closer_line(r) == "\tEOF")
  local normalized = editing.prefix_lines(r, { "  ", "payload", "    nested" }, { normalize_autoindent = true })
  assert(normalized[1] == "\t\t", "copied blank-line autoindent must become a structural TAB")
  assert(normalized[2] == "\t\tpayload")
  assert(normalized[3] == "\t\t    nested", "additional payload spaces must remain unchanged")
  local pasted = editing.prefix_lines(r, { "  " })
  assert(pasted[1] == "\t\t  ", "pasted whitespace-only payload must retain its spaces")
end

do
  local result = scanner.scan("    cat <<-EOF\nbody\nEOF\n", { tabstop = 2 })
  local r = result.regions[1]
  assert(r and r.structural_prefix == "\t\t", "four spaces must map to two structural TABs at tabstop=2")
  assert(editing.closer_line(r) == "\t\tEOF")
end

do
  local result = scanner.scan("    cat <<-EOF\nbody\nEOF\n", { tabstop = 4 })
  assert(result.regions[1].structural_prefix == "\t", "four spaces must map to one structural TAB at tabstop=4")
end

do
  local result = scanner.scan("   cat <<-EOF\nbody\nEOF\n", { tabstop = 2 })
  local r = result.regions[1]
  assert(not r.opener_safe and not r.editable and r.confidence == "unsupported-indent",
    "a visual column not representable by leading TABs must remain untouched")
end

-- mvdan/sh (through shfmt --to-json in CI) validates these as legal Bash
-- programs. The Lua scanner intentionally declines them until their lexical
-- constructs have explicit support; parser validity must not imply edit safety.
for _, path in ipairs({
  "tests/fixtures/grammar/backtick-substitution.sh",
  "tests/fixtures/grammar/nested-heredoc-command-substitution.sh",
}) do
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local result = scanner.scan(source)
  assert(not result.complete, path .. ": unsupported valid grammar must remain uncertain")
  for _, region in ipairs(result.regions) do
    assert(not region.editable, path .. ": uncertain scan must not authorise edits")
  end
end

print("scanner tests: PASS")


-- Cycle 6: characterize heredoc closing obligations without changing the
-- production scanner. An opener is represented as an individual record;
-- delimiter text alone must not identify or merge obligations.
do
  local result = scanner.scan(
    "command <<-'EOF' <<-'EOF'\\nfirst body\\nEOF\\nsecond body\\nEOF\\n"
  )
  if not result.complete then
    local details = {}
    for _, item in ipairs(result.heredocs) do
      details[#details + 1] = string.format(
        "opener=%s queue=%s delimiter=%q terminator=%s",
        tostring(item.opener_line), tostring(item.queue_position), item.delimiter,
        tostring(item.terminator_line)
      )
    end
    for _, diagnostic in ipairs(result.diagnostics) do
      details[#details + 1] = diagnostic.message
    end
    error("same-delimiter scan incomplete: " .. table.concat(details, " | "))
  end
  assert(#result.heredocs == 2, "same delimiter text must not collapse distinct heredoc obligations")
  local first, second = result.heredocs[1], result.heredocs[2]
  assert(first.delimiter == second.delimiter and first.delimiter == "EOF")
  assert(first.opener_line == 1 and second.opener_line == 1)
  assert(first.queue_position == 1 and second.queue_position == 2,
    "same-command heredocs must retain independent queue identities")
  assert(first.terminator_line == 3 and second.terminator_line == 5,
    "each same-delimiter obligation must consume its own terminator in queue order")
end

-- Heredoc-looking syntax inside an active body is payload, not a new shell
-- opener. This holds both at top level and inside an enclosing function.
do
  local fixtures = {
    { source = "command <<-'OUTER'\\ninner() {\\n  command <<-'INNER'\\n}\\nOUTER\\n", opener_line = 1 },
    { source = "function wrapped() {\\n  command <<-'OUTER'\\n  inner() {\\n    command <<-'INNER'\\n  }\\nOUTER\\n}\\n", opener_line = 2 },
  }
  for _, fixture in ipairs(fixtures) do
    local result = scanner.scan(fixture.source)
    assert(result.complete, "outer heredoc with nested-looking payload should scan completely")
    assert(#result.heredocs == 1 and result.heredocs[1].delimiter == "OUTER",
      "a heredoc opener inside an active heredoc body must remain opaque payload")
    assert(result.heredocs[1].opener_line == fixture.opener_line)
  end
end

-- Record what the current scanner can see during delimiter entry. The same
-- lexical progression is exercised standalone and within a function; scope
-- does not alter opener recognition. The unterminated quote is deliberately
-- a candidate opener, not yet a parsed heredoc record.
do
  local progressions = {
    { suffix = "<<-", count = 0, complete = false },
    { suffix = "<<-'", count = 0, complete = false },
    { suffix = "<<-'E'", count = 1, delimiter = "E", complete = false },
    { suffix = "<<-'EO'", count = 1, delimiter = "EO", complete = false },
    { suffix = "<<-'EOF'", count = 1, delimiter = "EOF", complete = false },
  }
  for _, context in ipairs({
    { prefix = "", opener_line = 1 },
    { prefix = "function wrapped() {\\n  ", opener_line = 2 },
  }) do
    for _, step in ipairs(progressions) do
      local result = scanner.scan(context.prefix .. "command " .. step.suffix .. "\\n")
      assert(result.complete == step.complete,
        "unexpected completeness for delimiter progression " .. step.suffix)
      assert(#result.heredocs == step.count,
        "unexpected record count for delimiter progression " .. step.suffix)
      if step.count == 1 then
        local record = result.heredocs[1]
        assert(record.opener_line == context.opener_line)
        assert(record.delimiter == step.delimiter)
        assert(record.terminator_line == nil,
          "a recognised opener without body terminator must retain an outstanding closer obligation")
        assert(record.confidence == "incomplete" and not record.editable)
      end
    end
  end
end

-- Empty delimiter is a syntactically complete opener with a real, distinct
-- terminator obligation; its empty delimiter must not be treated as absence.
do
  local result = scanner.scan("command <<-''\\n")
  assert(not result.complete and #result.heredocs == 1)
  assert(result.heredocs[1].delimiter == "")
  assert(result.heredocs[1].delimiter_original == "''")
  assert(result.heredocs[1].terminator_line == nil)
end
