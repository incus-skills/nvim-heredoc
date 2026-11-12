package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local scanner = require("nvim-heredoc.scanner")

local function one(source)
  local result = scanner.scan(source)
  assert(#result.regions == 1, "expected one managed region, got " .. #result.regions)
  return result, result.regions[1]
end

do
  local _, r = one("if true; then\n\tcat <<-'END'\n  payload\n\tEND\nfi\n")
  assert(r.operator == "<<-")
  assert(r.delimiter == "END" and r.delimiter_quoted)
  assert(r.opener_line == 2 and r.body_start_line == 3 and r.terminator_line == 4)
  assert(r.structural_prefix == "\t" and r.editable)
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
  local _, r = one("cat \\\n  <<-E\\OF\nbody\nEOF\n")
  assert(r.opener_line == 2 and r.delimiter == "EOF")
  assert(r.terminator_line == 4)
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
  local result = scanner.scan('echo "$(nested)" <<-REAL\n<<-FALSE_POSITIVE\nREAL\n')
  assert(not result.complete)
  assert(#result.regions == 0, "scanner must not parse possible heredoc payload as shell after ambiguity")
end

do
  local result = scanner.scan("(( value << 2 ))\n")
  assert(#result.regions == 0, "shift operator in arithmetic context is not a heredoc")
end

do
  local _, r = one("    cat <<-EOF\nbody\nEOF\n")
  assert(not r.structural_tabs_only and not r.editable)
  assert(r.confidence == "unsupported-indent")
end

print("scanner tests: PASS")
