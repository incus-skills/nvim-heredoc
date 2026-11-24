package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local api = vim.api

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
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

local function wait_for(predicate, message, buf)
  assert(vim.wait(1000, predicate, 10),
    message .. "; lines=" .. vim.inspect(lines(buf))
      .. "; cursor=" .. vim.inspect(api.nvim_win_get_cursor(0))
      .. "; mode=" .. api.nvim_get_mode().mode
      .. "; snapshot=" .. vim.inspect(plugin._snapshot_for_test(buf)))
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

local function test_embedded_managed_opener()
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
  defer(function()
    assert(api.nvim_get_mode().mode:sub(1, 1) == "i",
      "should enter Insert mode on the embedded managed opener")
    send("<CR>")
    defer(function()
      wait_for(function()
        local actual = lines(buf)
        return #actual == #original + 1 and actual[3] == "\t\t"
      end, "Return should split payload without inserting an embedded closer", buf)

      local actual = lines(buf)
      assert(actual[2] == original[2], "the embedded opener text must remain unchanged")
      assert(actual[4] == original[3] and actual[5] == original[4],
        "the embedded script payload must remain in place")
      assert(actual[6] == "\tOUTER",
        "the containing heredoc closer must remain the only active boundary")
      assert(#actual == 6, "no nested EOF closer may be inserted")
      send("<Esc>")
      defer(test_embedded_ordinary_opener)
    end)
  end)
end

function test_embedded_ordinary_opener()
  local buf = new_buffer({
    "  cat <<-'OUTER'",
    "  cat <<'EOF'",
    "\tOUTER",
  })
  local original = lines(buf)
  api.nvim_win_set_cursor(0, { 2, #original[2] })
  send("A")
  defer(function()
    assert(api.nvim_get_mode().mode:sub(1, 1) == "i",
      "should enter Insert mode on the ordinary embedded opener")
    send("<CR>")
    defer(function()
      wait_for(function()
        return lines(buf)[3] == "\t\t"
      end, "Return should create a payload line without shell autoindent", buf)

      send("hello1")
      defer(function()
        wait_for(function()
          return lines(buf)[3] == "\t\thello1"
        end, "first payload line should retain only the fixed structural TAB prefix", buf)
        send("<CR>")
        defer(function()
          wait_for(function()
            return lines(buf)[4] == "\t\t"
          end, "second payload line should not inherit indentation", buf)
          send("hello2")
          defer(function()
            wait_for(function()
              return lines(buf)[4] == "\t\thello2"
            end, "second payload line should not staircase", buf)
            send("<CR>")
            defer(function()
              wait_for(function()
                return lines(buf)[5] == "\t\t"
              end, "third payload line should not inherit indentation", buf)
              send("hello3")
              defer(function()
                wait_for(function()
                  return lines(buf)[5] == "\t\thello3"
                end, "third payload line should not staircase", buf)

                local actual = lines(buf)
                assert(actual[2] == "\t\t" .. original[2],
                  "the ordinary embedded opener must remain literal after the fixed outer structural prefix")
                assert(actual[3] == "\t\thello1"
                  and actual[4] == "\t\thello2"
                  and actual[5] == "\t\thello3",
                  "successive payload lines must not acquire cumulative spaces; lines="
                    .. vim.inspect(actual))
                assert(actual[6] == "\tOUTER",
                  "the containing heredoc closer must remain in place")
                assert(#actual == 6,
                  "an ordinary embedded heredoc must not create an EOF closer")
                send("<Esc>")
                defer(function()
                  print("live heredoc payload Return tests: PASS")
                  vim.cmd("qa!")
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

test_embedded_managed_opener()
