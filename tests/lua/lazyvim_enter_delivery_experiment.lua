-- Test-only synchronous Enter experiment for the actual provisioned indentation
-- model. Production modules remain untouched.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")
local events = {}

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function input(keys)
  vim.api.nvim_input(vim.api.nvim_replace_termcodes(keys, true, false, true))
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function wait_for(predicate, message)
  assert(vim.wait(1500, predicate, 10), message)
end

local function scan(buf)
  return scanner.scan(table.concat(lines(buf), "\n"), {
    tabstop = vim.bo[buf].tabstop,
    shiftwidth = vim.bo[buf].shiftwidth,
  })
end

local function direct_transition(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then return false end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local current = lines(buf)[row + 1]
  if not current or col ~= #current then return false end

  local result = scan(buf)
  for _, region in ipairs(result.regions) do
    if region.opener_line == row + 1
      and region.confidence == "incomplete"
      and region.opener_safe then
      local body_prefix = region.structural_prefix or ""
      local closer = (region.closer_prefix or "") .. region.delimiter
      vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, {
        body_prefix,
        closer,
      })
      vim.api.nvim_win_set_cursor(win, { row + 2, #body_prefix })
      events[#events + 1] = "opener-enter"
      return true
    end

    if region.editable and row + 1 >= region.body_start_line
      and row + 1 <= region.body_end_line then
      local prefix = region.structural_prefix or ""
      if prefix == "" then return false end
      -- Own the Enter transition: insert a fresh TAB-only structural prefix
      -- rather than allowing autoindent/indentexpr to copy spaces or payload.
      vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, { prefix })
      vim.api.nvim_win_set_cursor(win, { row + 2, #prefix })
      events[#events + 1] = "body-enter"
      return true
    end
  end
  return false
end

local function install_test_mapping(buf)
  local original = vim.fn.maparg("<CR>", "i", false, true)
  assert(type(original.rhs) == "string" and original.rhs ~= "" and not original.callback,
    "expected a string/expression Insert <CR> mapping; got " .. vim.inspect(original))

  vim.keymap.set("i", "<CR>", function()
    if direct_transition(buf) then return end
    if original.expr == 1 then
      local keys = vim.api.nvim_eval(original.rhs)
      assert(type(keys) == "string", "original expression mapping did not return keys")
      if original.replace_keycodes == 1 or original.replace_keycodes == true then
        keys = vim.api.nvim_replace_termcodes(keys, true, true, true)
      end
      vim.api.nvim_feedkeys(keys, "i", false)
    else
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes(original.rhs, true, false, true),
        "i", false
      )
    end
  end, { buffer = buf, desc = "test-only synchronous heredoc Enter" })
end

local function main()
  require("mini.pairs").setup({
    modes = { insert = true, command = true, terminal = false },
    skip_ts = { "string" },
    skip_unbalanced = true,
    markdown = true,
  })
  require("blink.cmp").setup({
    sources = { default = { "buffer" } },
    completion = { menu = { auto_show = false } },
  })
  assert(vim.wait(10000, function()
    return package.loaded["blink.cmp.fuzzy"] ~= nil
  end, 20), "Blink did not finish initialising")

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "bash"
  vim.bo[buf].expandtab = true
  vim.bo[buf].tabstop = 2
  vim.bo[buf].softtabstop = 0
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].autoindent = true
  vim.bo[buf].smartindent = false
  vim.bo[buf].cindent = false
  vim.bo[buf].indentexpr = ""
  vim.bo[buf].formatoptions = ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "    cat <<-PROTO" })
  require("nvim-heredoc").setup_buffer()
  assert(vim.b[buf].nvim_heredoc_attached == true)
  assert(vim.bo[buf].expandtab == true and vim.bo[buf].autoindent == true,
    "test must exercise expandtab plus active autoindent")
  install_test_mapping(buf)

  vim.api.nvim_win_set_cursor(0, { 1, #"    cat <<-PROTO" })
  input("A")

  local function defer(fn)
    vim.defer_fn(function()
      local ok, err = xpcall(fn, debug.traceback)
      if not ok then fail(err) end
    end, 25)
  end

  local function verify_delivery()
    local expected = "hello1\\n  hello2\\nhello3\\n"
    local script = table.concat(lines(buf), "\\n") .. "\\n"
    local path = vim.fn.tempname()
    local file = assert(io.open(path, "wb"))
    file:write(script)
    file:close()
    local output = vim.fn.system({ "bash", path })
    local status = vim.v.shell_error
    os.remove(path)
    assert(status == 0, "Bash execution failed: " .. output)
    assert(output == expected,
      "Bash delivery mismatch; expected=" .. vim.inspect(expected)
        .. "; actual=" .. vim.inspect(output)
        .. "; buffer=" .. vim.inspect(lines(buf)))
    print(\"synchronous Enter + provisioned indentation + Bash delivery: PASS\")
    print("transitions: " .. table.concat(events, ", "))
    vim.cmd("qa!")
  end

  defer(function()
    assert(vim.api.nvim_get_mode().mode == "i",
      "could not enter Insert mode; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
    input("<CR>hello1")
    defer(function()
      local actual = lines(buf)
      assert(actual[2] == "\\t\\t\\thello1" and actual[3] == "\\t\\tPROTO",
        "first body transition failed: " .. vim.inspect(actual))
      input("<CR>  hello2")
      defer(function()
        actual = lines(buf)
        assert(actual[2] == "\\t\\t\\thello1"
          and actual[3] == "\\t\\t\\t  hello2" and actual[4] == "\\t\\tPROTO",
          "second body transition failed: " .. vim.inspect(actual))
        input("<CR>hello3")
        defer(function()
          actual = lines(buf)
          assert(#actual == 5 and actual[2] == "\\t\\t\\thello1"
            and actual[3] == "\\t\\t\\t  hello2"
            and actual[4] == "\\t\\t\\thello3"
            and actual[5] == "\\t\\tPROTO",
            "third body transition failed: " .. vim.inspect(actual))
          input("<Esc>")
          defer(function()
            assert(vim.api.nvim_get_mode().mode ~= "i", "Escape did not leave Insert mode")
            verify_delivery()
          end)
        end)
      end)
    end)
  end)
end


  print("transitions: " .. table.concat(events, ", "))
  vim.cmd("qa!")
end

local ok, err = xpcall(main, debug.traceback)
if not ok then fail(err) end
