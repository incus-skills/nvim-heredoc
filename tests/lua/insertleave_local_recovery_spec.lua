package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function attach(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "bash"
  vim.api.nvim_set_current_buf(buf)
  assert(plugin.setup_buffer(buf), "the bash buffer should attach")
  return buf
end

local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

-- A genuinely typed opener that is abandoned without Return must remain
-- incomplete after the real InsertLeave event.
do
  local buf = attach({ "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_input("Acat <<-NEW" .. escape)
  assert(vim.wait(1500, function()
    return vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i"
      and lines(buf)[1] == "cat <<-NEW"
  end, 10), "the typed opener should be entered and Insert mode should end")
  vim.wait(100, function() return false end, 10)
  local actual = lines(buf)
  assert(#actual == 1 and actual[1] == "cat <<-NEW",
    "real InsertLeave must not commit an opener typed during the same session")
end

-- A pre-existing incomplete region may be recovered when the real Insert
-- session begins and ends in its body. Only that region is formatted/closed.
do
  local buf = attach({ "cat <<-LOCAL", "body" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.api.nvim_input("A!" .. escape)
  assert(vim.wait(1500, function()
    local actual = lines(buf)
    return vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i"
      and #actual == 3 and actual[2] == "\tbody!"
      and actual[3] == "LOCAL"
  end, 10), "real InsertLeave should locally recover the pre-existing incomplete region")
end

print("live InsertLeave local-recovery tests: PASS")
vim.cmd("qa!")
