package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")

-- Return-local recognition parses the completed opener without searching
-- later buffer lines for a candidate terminator.
do
  local openers = assert(scanner.parse_openers("  cat <<-'CUSTOM'"))
  assert(#openers == 1)
  local opener = openers[1]
  assert(opener.operator == "<<-" and opener.delimiter == "CUSTOM")
  assert(opener.structural_prefix == "\t" and opener.body_prefix == "\t\t")
  assert(opener.opener_safe and not opener.editable)
  local tab_indented = assert(scanner.parse_openers("\tcat <<-LIVE", { tabstop = 2 }))
  assert(tab_indented[1].structural_prefix == "\t" and tab_indented[1].body_prefix == "\t\t")
  assert(editing.closer_line(tab_indented[1]) == "\tLIVE")
  local plain = assert(scanner.parse_openers("  cat <<'PLAIN'"))
  assert(#plain == 1 and plain[1].operator == "<<")
  assert(editing.closer_line(plain[1]) == "PLAIN",
    "ordinary << closers are normalised to column zero regardless of opener indentation")
  assert(editing.closer_line(plain[1]) == "PLAIN",
    "ordinary << closers are normalised to column zero regardless of opener indentation")
  local unsupported = assert(scanner.parse_openers("   cat <<-EOF", { tabstop = 2 }))
  assert(#unsupported == 1 and not unsupported[1].opener_safe)
  local none = assert(scanner.parse_openers("cat <<<VALUE"))
  assert(#none == 0, "here-strings are not managed heredoc openers")
end

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
  local result = scanner.scan("  cat <<'EOF'\n  body\n    EOF\n")
  assert(#result.regions == 0, "ordinary heredocs remain outside the managed body-formatting region list")
  assert(#result.heredocs == 1 and result.heredocs[1].operator == "<<",
    "the scanner should expose ordinary heredoc structure for closer recovery")
  local r = result.heredocs[1]
  assert(r.terminator_line == 3)
  assert(editing.closer_line(r) == "EOF",
    "a recovered ordinary << closer must be left-justified")
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


-- Regression cases: heredoc-looking payload is opaque, delimiter identity is
-- per opener, and editor-side closer recovery tolerates leading spaces/TABs
-- for both operators. This recovery rule is distinct from native shell
-- terminator syntax; body adoption remains limited to <<-.
do
  local source = table.concat({
    "conf_print_test4() {",
    "  cat <<'EOF'",
    "  cat <<='EOF'",
    "      hello1",
    "          hello2",
    "              hello3",
    "                  hello4",
    "    EOF",
    "\tEOF",
    "}",
  }, "\n") .. "\n"
  local result = scanner.scan(source)
  assert(result.complete, "an indented matching delimiter is recoverable for ordinary <<")
  assert(#result.heredocs == 1 and #result.regions == 0,
    "ordinary << is recognised for closer recovery but its body is not adopted")
  local r = result.heredocs[1]
  assert(r.delimiter == "EOF" and r.terminator_line == 8 and r.body_end_line == 7,
    "leading spaces are tolerated for recognition, and the first matching delimiter closes the body")
  assert(editing.closer_line(r) == "EOF",
    "ordinary << recovery must remove all leading closer indentation")
  assert(source:find("      hello1", 1, true) and source:find("          hello2", 1, true),
    "ordinary heredoc body indentation remains present and unchanged")
end

do
  local source = table.concat({
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
  }, "\n") .. "\n"
  local result = scanner.scan(source)
  assert(result.complete, "a space-indented matching delimiter is recoverable for <<-")
  assert(#result.heredocs == 1 and #result.regions == 1,
    "the heredoc-looking body line must not create a second opener")
  local r = result.regions[1]
  assert(r.delimiter == "EOF" and r.terminator_line == 8 and r.body_end_line == 7,
    "leading spaces are tolerated for editor recognition, independently of shell <<- semantics")
  assert(editing.closer_line(r) == "\tEOF",
    "the recovered <<- closer is rewritten with the opener's structural TAB prefix")
end

do
  local source = table.concat({
    "conf_print_test3() {",
    "  cat <<-'FOE'",
    "hello1",
    "hello2",
    "hello3",
    "hello4",
    "\tFOE",
    "}",
  }, "\n") .. "\n"
  local result = scanner.scan(source)
  assert(result.complete and #result.heredocs == 1 and #result.regions == 1)
  assert(result.regions[1].delimiter == "FOE"
    and result.regions[1].terminator_line == 7,
    "the terminator must match the opener's actual delimiter, not a fixed EOF")
end

do
  local source = table.concat({
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
  }, "\n") .. "\n"
  local result = scanner.scan(source)
  assert(result.complete and #result.heredocs == 1 and #result.regions == 1,
    "an opener-looking payload line must not enqueue another heredoc")
  assert(result.regions[1].delimiter == "EOF"
    and result.regions[1].terminator_line == 8,
    "the first valid EOF at column zero must terminate the outer <<- heredoc")
end

-- A realistic ordinary heredoc with a front-matter/Markdown payload. The
-- closer is misindented, but only that closer is eligible for repair; the
-- ordinary body remains outside the managed formatting region.
do
  local source = table.concat({
    "skill_calibrate() {",
    "cat <<'OE_SKILL_CALIBRATE_V2_EOF'",
    "---",
    "",
    "name: calibrate",
    'description: "Refine calibration thresholds from session evidence."',
    "metadata:",
    "  hermes:",
    "    tags: [oe, calibration, threshold]",
    "",
    "      OE_SKILL_CALIBRATE_V2_EOF",
    "      }",
  }, "\n") .. "\n"
  local result = scanner.scan(source)
  assert(result.complete and #result.heredocs == 1 and #result.regions == 0)
  local r = result.heredocs[1]
  assert(r.operator == "<<" and r.terminator_line == 11)
  assert(editing.closer_line(r) == "OE_SKILL_CALIBRATE_V2_EOF")
  assert(source:find("  hermes:", 1, true) and source:find("    tags:", 1, true),
    "front-matter indentation remains body content, not adopted formatting")
end

-- Ordinary << recovery also tolerates a TAB-indented candidate, then removes
-- that indentation from the repaired closer.
do
  local result = scanner.scan("  cat <<TAB_END\nbody\n\tTAB_END\n")
  assert(result.complete and #result.heredocs == 1 and #result.regions == 0)
  assert(result.heredocs[1].terminator_line == 3)
  assert(editing.closer_line(result.heredocs[1]) == "TAB_END")
end

-- A closer with a different delimiter or trailing whitespace is not a match.
do
  local result = scanner.scan("cat <<-EOF\n  payload\n  EOF \n  EOF-extra\n")
  assert(not result.complete and result.heredocs[1].terminator_line == nil,
    "recovery must retain exact delimiter identity and must not trim trailing whitespace")
end

-- TAB-indented <<- closers remain normalised to the opener's structural prefix.
do
  local result = scanner.scan("\tcat <<-TAB_END\n\t\tbody\n  TAB_END\n")
  assert(result.complete and result.regions[1].terminator_line == 3)
  assert(editing.closer_line(result.regions[1]) == "\tTAB_END")
end

-- A non-colliding inner heredoc is cargo within the established outer region.
do
  local file = assert(io.open("tests/fixtures/heredoc-cargo-distinct-delimiters.sh", "rb"))
  local source = file:read("*a")
  file:close()
  local result = scanner.scan(source)
  assert(result.complete, "distinct-delimiter heredoc cargo should leave the outer region complete")
  assert(#result.heredocs == 1 and #result.regions == 1,
    "the inner heredoc opener must remain payload, not a second shell heredoc")
  local region = result.regions[1]
  assert(region.delimiter == "EOF" and region.terminator_line == 9
    and region.body_end_line == 8,
    "the outer EOF alone should close the non-colliding cargo fixture")
end


-- Command-group observations are passive scanner output. A checkpoint exists
-- only after the complete heredoc queue has been consumed.
do
  local result = scanner.scan("cat <<EOF\nbody\nEOF\necho after\n")
  assert(result.complete and #result.checkpoints == 1)
  local region = result.heredocs[1]
  local checkpoint = result.checkpoints[1]
  assert(region.command_start_line == 1)
  assert(region.command_end_line == 1 and region.is_final_in_queue)
  assert(checkpoint.group_key == region.command_end_line)
  assert(checkpoint.pos == 4, "checkpoint is the boundary after the terminator")
end

do
  local result = scanner.scan("cat <<A <<B\none\nA\ntwo\nB\necho after\n")
  assert(result.complete and #result.heredocs == 2 and #result.checkpoints == 1)
  local first, final = result.heredocs[1], result.heredocs[2]
  assert(first.command_start_line == 1 and final.command_start_line == 1)
  assert(first.command_end_line == final.command_end_line)
  assert(first.command_end_line == result.checkpoints[1].group_key)
  assert(not first.is_final_in_queue and final.is_final_in_queue)
  assert(result.checkpoints[1].pos == 6,
    "a multi-heredoc group checkpoints only after its final terminator")
end

do
  local result = scanner.scan("cat <<A <<B\none\nA\ntwo\n")
  assert(not result.complete and #result.heredocs == 2)
  assert(result.heredocs[1].terminator_line == 3)
  assert(result.heredocs[2].terminator_line == nil)
  assert(#result.checkpoints == 0,
    "a completed earlier queue member must not checkpoint an incomplete group")
end

do
  local result = scanner.scan("cat <<A\nx\nA\necho ok\ncat <<B\ny\n")
  assert(not result.complete and #result.checkpoints == 1)
  assert(result.checkpoints[1].group_key == result.heredocs[1].command_end_line)
  assert(result.checkpoints[1].pos == 4,
    "a later incomplete group must preserve an earlier completed group's checkpoint")
  assert(result.heredocs[2].terminator_line == nil)
end

do
  local source = "cat <<A\nx\nA\necho " .. string.char(96) .. "unsupported" .. string.char(96) .. "\n"
  local result = scanner.scan(source)
  assert(not result.complete and #result.checkpoints == 1)
  assert(result.checkpoints[1].pos == 4,
    "lexical early return must retain checkpoints from earlier completed groups")
end

do
  local source = table.concat({ "prefix", "cat \\", "<<-X", "body", "X", "" }, "\n")
  local result = scanner.scan(source)
  assert(result.complete and #result.heredocs == 1 and #result.checkpoints == 1)
  local region, checkpoint = result.heredocs[1], result.checkpoints[1]
  assert(region.command_start_line == 2 and region.opener_line == 3)
  assert(region.command_end_line == 3 and region.is_final_in_queue)
  assert(checkpoint.group_key == 3 and checkpoint.pos == 6,
    "group keys and checkpoint positions remain scan-local, 1-based coordinates")
end

print("scanner tests: PASS")
