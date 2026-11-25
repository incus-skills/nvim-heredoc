package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")
local scanner = require("nvim-heredoc.scanner")
local api = vim.api

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function attach(initial)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_lines(buf, 0, -1, false, initial)
  vim.bo[buf].filetype = "bash"
  vim.bo[buf].expandtab = false
  vim.bo[buf].tabstop = 2
  vim.bo[buf].softtabstop = 0
  vim.bo[buf].shiftwidth = 0
  vim.bo[buf].autoindent = false
  vim.bo[buf].smartindent = false
  vim.bo[buf].cindent = false
  vim.bo[buf].indentexpr = ""
  vim.bo[buf].formatoptions = ""
  api.nvim_set_current_buf(buf)
  assert(plugin.setup_buffer(buf), "the bash buffer should attach")
  return buf
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      print(err)
      vim.cmd("cquit 1")
    end
  end, 20)
end

local function run_payload_case(initial, expected_complete, label, done)
  local source = table.concat(initial, "\n")
  local result = scanner.scan(source)
  assert(result.complete == expected_complete,
    label .. ": unexpected scanner completeness")
  assert(result.heredocs[1] and result.heredocs[1].terminator_line == 3,
    label .. ": the earlier outer heredoc region must remain present")

  local buf = attach(initial)
  local mini_pairs_calls = 0
  _G.MiniPairs = {
    cr = function()
      mini_pairs_calls = mini_pairs_calls + 1
      return "\r"
    end,
  }

  api.nvim_win_set_cursor(0, { 2, #initial[2] })
  api.nvim_input("A\r")

  defer(function()
    assert(vim.wait(1000, function()
      return api.nvim_get_mode().mode == "i"
        and #lines(buf) == #initial + 1
    end, 10), label .. ": Return did not split the payload line")

    local actual = lines(buf)
    assert(mini_pairs_calls == 0,
      label .. ": confirmed payload Return must not delegate to MiniPairs")
    assert(actual[2] == "\tcat <<-INNER",
      label .. ": payload text must remain intact with its outer structural TAB; lines="
        .. vim.inspect(actual))
    assert(actual[4] == "OUTER",
      label .. ": the original outer terminator must remain in place")
    local inner_closers = 0
    for _, line in ipairs(actual) do
      if line == "INNER" or line == "\tINNER" then
        inner_closers = inner_closers + 1
      end
    end
    assert(inner_closers == 0,
      label .. ": payload text must not acquire an inner managed closer")

    _G.MiniPairs = nil
    done()
  end)
end

-- A complete scan must classify an existing payload as inside.
run_payload_case({
  "cat <<-OUTER",
  "cat <<-INNER",
  "OUTER",
}, true, "complete-scan payload", function()
  -- The same established region remains inside even when a later command
  -- group makes the overall scan incomplete.
  local unsupported = "echo " .. string.char(96) .. "unsupported" .. string.char(96)
  run_payload_case({
    "cat <<-OUTER",
    "cat <<-INNER",
    "OUTER",
    unsupported,
  }, false, "earlier region with later incomplete command", function()
    -- Exercise the retained M.process_buffer() entry point. In an uncertain
    -- quoted context, its local Return candidate must decline commitment and
    -- must not fall through to the document-wide incomplete-region fallback.
    local uncertain = {
      "printf '%s\n' \"",
      "cat <<-EOF",
      "",
    }
    local uncertain_scan = scanner.scan(table.concat(uncertain, "\n"))
    assert(not uncertain_scan.complete,
      "unterminated quote fixture must produce an incomplete scanner result")

    local buf = attach(uncertain)
    api.nvim_win_set_cursor(0, { 3, 0 })
    local changed = plugin.process_buffer(buf, {
      start_row = 1,
      end_row = 3,
    })
    assert(changed == false,
      "uncertain containment must decline Return-local closer insertion")
    local actual = lines(buf)
    assert(#actual == 3
      and actual[1] == uncertain[1]
      and actual[2] == uncertain[2]
      and actual[3] == uncertain[3],
      "M.process_buffer() must not insert a closer when containment is uncertain; lines="
        .. vim.inspect(actual))

    -- A fresh, positively recognised opener is outside even though the
    -- scanner marks the missing terminator as incomplete before Return.
    local fresh_source = "anchor\ncat <<-FRESH"
    local fresh_scan = scanner.scan(fresh_source)
    assert(not fresh_scan.complete
      and fresh_scan.heredocs[1]
      and fresh_scan.heredocs[1].opener_line == 2,
      "fresh opener fixture must be recorded by the incomplete scanner result")

    local fresh_buf = attach({ "anchor" })
    api.nvim_win_set_cursor(0, { 1, #"anchor" })
    api.nvim_input("ocat <lt><lt>-FRESH\r")
    defer(function()
      assert(vim.wait(1000, function()
        local actual = lines(fresh_buf)
        return api.nvim_get_mode().mode == "i"
          and #actual == 4
          and actual[1] == "anchor"
          and actual[2] == "cat <<-FRESH"
          and actual[3] == "\t"
          and actual[4] == "FRESH"
      end, 10), "fresh opener Return must create one body TAB and matching closer; mode="
        .. vim.inspect(api.nvim_get_mode()) .. "; lines=" .. vim.inspect(lines(fresh_buf)))
      print("Return containment regression tests: PASS")
      vim.cmd("qa!")
    end)
  end)
end)
