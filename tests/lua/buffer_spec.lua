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
