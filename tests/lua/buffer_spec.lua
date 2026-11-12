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
  local changed = plugin.process_buffer(buf, { start_row = 2, end_row = 3 }, false)
  assert(changed)
  local actual = lines(buf)
  assert(actual[2] == "\tfirst", "unmodified body lines must remain untouched by a changed-range operation")
  assert(actual[3] == "\t  changed", "only the supplied changed range should receive the structural prefix")
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
