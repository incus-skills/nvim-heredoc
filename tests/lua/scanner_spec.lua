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
  assert(r.structural_prefix == "\t" and r.editable and r.opener_safe)
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
  assert(once[1] == "\t  alpha" and once[2] == "\t" and once[3] == "\t   ")
  assert(once[4] == "\tbeta" and once[5] == "\t\tgamma")
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
  local _, r = one("    cat <<-EOF\nbody\nEOF\n")
  assert(not r.structural_tabs_only and not r.editable and not r.opener_safe)
  assert(r.confidence == "unsupported-indent")
  local closer = editing.closer_line(r)
  assert(closer == nil, "space-indented opener must not authorise closer placement")
end

print("scanner tests: PASS")
