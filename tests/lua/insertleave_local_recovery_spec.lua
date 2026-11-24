package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function attach(initial)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)
  vim.bo[buf].filetype = "bash"
  vim.api.nvim_set_current_buf(buf)
  assert(plugin.setup_buffer(buf), "the bash buffer should attach")
  return buf
end

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, 20)
end

local function assert_mode(expected, message)
  local actual = vim.api.nvim_get_mode().mode:sub(1, 1)
  assert(actual == expected, message .. "; mode=" .. actual)
end

local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

-- A genuinely typed opener that is abandoned without Return must remain
-- incomplete after the real InsertLeave event.
local first = attach({ "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_input("Acat <<-NEW")
defer(function()
  assert_mode("i", "the opener should be typed in real Insert mode")
  assert(lines(first)[1] == "cat <<-NEW", "the typed opener should be present")
  vim.api.nvim_input(escape)
  defer(function()
    assert_mode("n", "Escape should trigger the real InsertLeave event")
    vim.wait(100, function() return false end, 10)
    local actual = lines(first)
    assert(#actual == 1 and actual[1] == "cat <<-NEW",
      "real InsertLeave must not commit an opener typed during the same session")

    -- A pre-existing incomplete region may be recovered when the real Insert
    -- session begins and ends in its body. Only that region is formatted/closed.
    local second = attach({ "cat <<-LOCAL", "body" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_input("A!")
    defer(function()
      assert_mode("i", "the body edit should occur in real Insert mode")
      assert(lines(second)[2] == "body!", "the body edit should be present")
      vim.api.nvim_input(escape)
      defer(function()
        assert_mode("n", "Escape should leave the local recovery session")
        local final = lines(second)
        assert(#final == 3 and final[2] == "\tbody!" and final[3] == "LOCAL",
          "real InsertLeave should locally recover the pre-existing incomplete region; lines="
            .. vim.inspect(final))
        print("live InsertLeave local-recovery tests: PASS")
        vim.cmd("qa!")
      end)
    end)
  end)
end)
