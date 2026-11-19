package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function wait_for(predicate, message, buf)
  assert(vim.wait(2000, predicate, 10),
    message .. "; lines=" .. vim.inspect(lines(buf))
      .. "; cursor=" .. vim.inspect(api.nvim_win_get_cursor(0))
      .. "; mode=" .. vim.api.nvim_get_mode().mode)
end

local function send(keys)
  api.nvim_input(api.nvim_replace_termcodes(keys, true, false, true))
end

local function new_buffer(source)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_lines(buf, 0, -1, false, source)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "bash"
  vim.bo[buf].expandtab = true
  vim.bo[buf].tabstop = 2
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].softtabstop = 0
  vim.bo[buf].autoindent = true
  vim.bo[buf].smartindent = true
  vim.bo[buf].cindent = false
  plugin.setup()
  wait_for(function()
    return vim.b[buf].nvim_heredoc_attached == true
  end, "plugin should attach to the shell buffer", buf)
  return buf
end

-- A managed-looking opener inside an existing payload is literal text. Return
-- must split the line without creating a second active closer.
do
  local buf = new_buffer({
    "  cat <<-'OUTER'",
    "\t\tcat <<-'EOF'",
    "\t\tpayload",
    "\t\tEOF",
    "\tOUTER",
  })
  local original = lines(buf)
  api.nvim_win_set_cursor(0, { 2, #original[2] })
  send("A")
  wait_for(function()
    return api.nvim_get_mode().mode:sub(1, 1) == "i"
  end, "enter Insert mode on the embedded opener", buf)

  send("<CR>")
  wait_for(function()
    local actual = lines(buf)
    return #actual == #original + 1 and actual[3] == "\t\t"
  end, "Return should split the payload without inserting an embedded closer", buf)

  local actual = lines(buf)
  assert(actual[2] == original[2], "the embedded opener text must remain unchanged")
  assert(actual[4] == original[3] and actual[5] == original[4],
    "the embedded script payload must remain in place")
  assert(actual[6] == "\tOUTER", "the containing heredoc closer must remain the only active boundary")
  assert(#actual == 6, "no nested EOF closer may be inserted")
  send("<Esc>")
  vim.wait(100, function() return vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" end, 10)
end

-- An ordinary << opener inside payload is equally opaque. Successive Returns
-- must not inherit shell indentation from the preceding payload line.
do
  local buf = new_buffer({
    "  cat <<-'OUTER'",
    "  cat <<'EOF'",
    "\tOUTER",
  })
  local original = lines(buf)
  api.nvim_win_set_cursor(0, { 2, #original[2] })
  send("A")
  wait_for(function()
    return api.nvim_get_mode().mode:sub(1, 1) == "i"
  end, "enter Insert mode on the ordinary embedded opener", buf)

  send("<CR>")
  wait_for(function()
    return lines(buf)[3] == "\t\t"
  end, "Return should create an unindented payload line", buf)

  send("hello1")
  wait_for(function()
    return lines(buf)[3] == "\t\thello1"
  end, "first payload line should retain only the structural TAB prefix", buf)

  send("<CR>")
  wait_for(function()
    return lines(buf)[4] == "\t\t"
  end, "second payload line should not inherit indentation", buf)
  send("hello2")
  wait_for(function()
    return lines(buf)[4] == "\t\thello2"
  end, "second payload line should not staircase", buf)

  send("<CR>")
  wait_for(function()
    return lines(buf)[5] == "\t\t"
  end, "third payload line should not inherit indentation", buf)
  send("hello3")
  wait_for(function()
    return lines(buf)[5] == "\t\thello3"
  end, "third payload line should not staircase", buf)

  local actual = lines(buf)
  assert(actual[2] == "\t\t" .. original[2],
    "the ordinary embedded opener must remain literal after the fixed outer structural prefix")
  assert(actual[3] == "\t\thello1"
    and actual[4] == "\t\thello2"
    and actual[5] == "\t\thello3",
    "successive payload lines must not acquire cumulative spaces; lines=" .. vim.inspect(actual))
  assert(actual[6] == "\tOUTER", "the containing heredoc closer must remain in place")
  assert(#actual == 6, "an ordinary embedded heredoc must not create an EOF closer")

  send("<Esc>")
  vim.wait(100, function() return vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" end, 10)
end

print("live heredoc payload Return tests: PASS")
vim.cmd("qa!")
