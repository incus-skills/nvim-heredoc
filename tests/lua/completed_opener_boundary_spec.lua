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

local function scan(source)
  return scanner.scan(source, { tabstop = 2 })
end

-- A standalone old heredoc is already known before a new opener is inserted
-- above it. Both use the same delimiter, so a plain forward scan mistakes the
-- old heredoc's terminator for the new opener's terminator.
local standalone_baseline = scan(table.concat({
  "cat <<'EOF'",
  "old payload",
  "EOF",
}, "\n"))
assert(standalone_baseline.complete and #standalone_baseline.heredocs == 1)
local standalone_lines = {
  "cat <<-'EOF'",
  "cat <<'EOF'",
  "old payload",
  "EOF",
}
local standalone_current = scan(table.concat(standalone_lines, "\n"))
assert(standalone_current.complete and #standalone_current.heredocs == 1)
assert(standalone_current.heredocs[1].opener_line == 1)
assert(standalone_current.heredocs[1].terminator_line == 4,
  "the current scanner consumes the old standalone heredoc's terminator")
assert(not preserve_boundary(standalone_baseline, standalone_current, standalone_lines),
  "the current function-only recovery helper does not protect a standalone intervening opener")

-- The function-wrapped shape has the same old-opener/terminator collision,
-- plus an explicit closing-brace boundary. The existing helper recognises
-- this narrower case when the prior completed scan is available.
local wrapped_baseline = scan(table.concat({
  "old_function() {",
  "  cat <<'EOF'",
  "old payload",
  "EOF",
  "}",
}, "\n"))
assert(wrapped_baseline.complete and #wrapped_baseline.heredocs == 1)

local wrapped_lines = {
  "new_function() {",
  "  cat <<-'EOF'",
  "}",
  "old_function() {",
  "  cat <<'EOF'",
  "old payload",
  "EOF",
  "}",
}
local wrapped_current = scan(table.concat(wrapped_lines, "\n"))
assert(wrapped_current.complete and #wrapped_current.regions == 1)
assert(wrapped_current.regions[1].terminator_line == 7,
  "before boundary recovery, the new opener appears to consume the old terminator")
assert(preserve_boundary(wrapped_baseline, wrapped_current, wrapped_lines),
  "the existing helper should recognise the previously known wrapped heredoc")
assert(wrapped_current.regions[1].boundary_line == 3,
  "the function close brace is the boundary before the old heredoc opener")
assert(wrapped_current.regions[1].terminator_line == nil,
  "the old terminator must not be assigned to the new opener across the function boundary")

-- A heredoc-looking line inside a body is not, by itself, an intervening
-- opener. This negative control preserves the scanner's body-opacity rule.
local opaque = scan(table.concat({
  "cat <<-'OUTER'",
  "cat <<'INNER'",
  "OUTER",
}, "\n"))
assert(opaque.complete and #opaque.heredocs == 1)
assert(opaque.heredocs[1].delimiter == "OUTER")
assert(opaque.heredocs[1].terminator_line == 3,
  "payload that resembles an opener must not create another closer obligation")


-- Exercise the standalone collision through process_buffer at the Return-time
-- buffer shape: the new opener has a blank first body line, followed by the
-- previously recognised heredoc command and its payload/terminator.
local function replace_buffer(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "sh"
vim.bo[buf].tabstop = 2
vim.bo[buf].shiftwidth = 2
vim.bo[buf].expandtab = false

replace_buffer(buf, {
  "sentinel",
  "cat <<'EOF'",
  "old payload",
  "EOF",
})
assert(plugin.setup_buffer(buf), "plugin failed to attach for standalone Return fixture")

replace_buffer(buf, {
  "cat <<-'EOF'",
  "",
  "sentinel",
  "cat <<'EOF'",
  "old payload",
  "EOF",
})
vim.api.nvim_win_set_cursor(0, { 2, 0 })
plugin.process_buffer(buf, nil, false)
local processed = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(processed[4] == "\tcat <<'EOF'",
  "current processing prefixes the intervening old opener as new-heredoc payload")
assert(processed[5] == "\told payload",
  "current processing also prefixes the old heredoc's payload")
assert(processed[6] == "\tEOF",
  "current processing treats the old terminator as the new heredoc's terminator")
vim.cmd("bwipeout! " .. buf)

print("completed-opener boundary characterization: PASS")
