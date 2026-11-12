-- Test-only prototype for a synchronous <CR> transition.
-- Run through tests/run-lazyvim.sh; no production module is modified.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local scanner = require("nvim-heredoc.scanner")
local prototype_events = {}

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function defer(fn, delay)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, delay or 25)
end

local function input(keys)
  vim.api.nvim_input(vim.api.nvim_replace_termcodes(keys, true, false, true))
end

local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function mapping_inventory(mapping)
  return {
    lhs = mapping.lhs,
    rhs = mapping.rhs,
    expr = mapping.expr,
    callback = mapping.callback,
    buffer = mapping.buffer,
    mode = mapping.mode,
    noremap = mapping.noremap,
    script = mapping.script,
    sid = mapping.sid,
  }
end

local function canonical_transition(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local lines = get_lines(buf)
  local opener = lines[row + 1]
  if not opener or col ~= #opener then
    prototype_events[#prototype_events + 1] = {
      event = "not-at-opener-eol", row = row, col = col, opener = opener,
    }
    return false
  end

  local result = scanner.scan(table.concat(lines, "\n"))
  if result.complete or #result.regions == 0 then
    prototype_events[#prototype_events + 1] = { event = "scanner-no-incomplete-region", result = result }
    return false
  end

  local region
  for _, candidate in ipairs(result.regions) do
    if candidate.opener_line == row + 1 and candidate.confidence == "incomplete"
      and candidate.opener_safe then
      region = candidate
      break
    end
  end
  if not region then
    prototype_events[#prototype_events + 1] = { event = "no-safe-region", regions = result.regions }
    return false
  end

  local body_prefix = region.structural_prefix or ""
  local closer_line = (region.closer_prefix or body_prefix) .. region.delimiter
  local body_row = row + 1

  -- Construct the complete canonical structure before returning from <CR>.
  vim.api.nvim_buf_set_lines(buf, body_row, body_row, false, {
    body_prefix,
    closer_line,
  })
  vim.api.nvim_win_set_cursor(win, { body_row + 1, #body_prefix })
  prototype_events[#prototype_events + 1] = {
    event = "heredoc-transition",
    prefix = body_prefix,
    closer = closer_line,
    mode = vim.api.nvim_get_mode().mode,
  }
  return true
end

local function install_wrapper(buf, original)
  -- Deliberately support only plain, non-expression string mappings here.
  -- The actual MiniPairs mapping is inventoried separately and is an expr map.
  local can_delegate = original
    and type(original.rhs) == "string"
    and original.rhs ~= ""
    and not original.callback
    and original.expr ~= 1

  vim.keymap.set("i", "<CR>", function()
    prototype_events[#prototype_events + 1] = {
      event = "wrapper-enter",
      mode = vim.api.nvim_get_mode().mode,
    }
    if canonical_transition(buf) then
      return
    end
    if can_delegate then
      local keys = vim.api.nvim_replace_termcodes(original.rhs, true, false, true)
      local flags = "i" .. (original.noremap == 1 and "n" or "")
      vim.api.nvim_feedkeys(keys, flags, false)
      return
    end
    error("prototype refuses ambiguous <CR> fallback: " .. vim.inspect(mapping_inventory(original or {})))
  end, {
    buffer = buf,
    desc = "Test-only synchronous heredoc Enter prototype",
  })
end

local function setup_plugins_and_inventory()
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
  end, 20), "blink.cmp did not finish initialising")

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "bash"
  local mapping = vim.fn.maparg("<CR>", "i", false, true)
  print("LazyVim <CR> mapping inventory: " .. vim.inspect(mapping_inventory(mapping)))
end

local function test_batched_heredoc_input(keys, payload, expected_col, done)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "    cat <<-PROTO" })
  vim.bo[buf].filetype = "bash"

  -- Capture the effective mapping before installing the buffer-local wrapper.
  local original = vim.fn.maparg("<CR>", "i", false, true)
  install_wrapper(buf, original)
  vim.api.nvim_win_set_cursor(0, { 1, #"    cat <<-PROTO" })

  -- Enter Insert mode first. Then submit <CR> and the payload in one input
  -- batch so the test exercises typeahead ordering rather than a settled edit.
  input("A")
  defer(function()
    assert(vim.api.nvim_get_mode().mode == "i",
      "could not enter Insert mode before batched input")
    input(keys)

    defer(function()
      local actual = get_lines(buf)
      assert(vim.deep_equal(actual, {
        "    cat <<-PROTO",
        "\t    " .. payload,
        "\tPROTO",
      }), "batched input failed for " .. vim.inspect(keys)
        .. "; lines=" .. vim.inspect(actual)
        .. "; cursor=" .. vim.inspect(vim.api.nvim_win_get_cursor(0))
        .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode())
        .. "; prototype_events=" .. vim.inspect(prototype_events))
      assert(vim.api.nvim_get_mode().mode == "i",
        "the direct heredoc transition must remain in Insert mode")
      assert(vim.api.nvim_win_get_cursor(0)[2] == expected_col,
        "cursor must be immediately after payload; cursor=" .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
      print("synchronous heredoc prototype PASS: " .. keys)

      input("<Esc>")
      defer(done)
    end)
  end)
end

local function test_controlled_string_fallback(done)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "text"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "seed" })

  vim.keymap.set("i", "<CR>", "<CR>OBSERVED_NORMAL_ENTER", { buffer = buf })
  local original = vim.fn.maparg("<CR>", "i", false, true)
  assert(type(original.rhs) == "string" and original.rhs ~= "" and not original.callback,
    "controlled fallback mapping was not captured as a string RHS: " .. vim.inspect(mapping_inventory(original)))

  install_wrapper(buf, original)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  input("A")
  defer(function()
    assert(vim.api.nvim_get_mode().mode == "i",
      "could not enter Insert mode before controlled fallback")
    input("<CR>world")

    defer(function()
      assert(vim.deep_equal(get_lines(buf), { "seed", "OBSERVED_NORMAL_ENTERworld" }),
        "controlled string-based <CR> mapping was not preserved; lines=" .. vim.inspect(get_lines(buf)))
      assert(vim.api.nvim_get_mode().mode == "i",
        "controlled fallback must remain in Insert mode")
      print("controlled string <CR> fallback PASS")
      input("<Esc>")
      defer(done)
    end)
  end)
end

local ok, err = xpcall(function()
  setup_plugins_and_inventory()

  test_batched_heredoc_input("<CR>x", "x", 6, function()
    test_batched_heredoc_input("<CR>abc", "abc", 8, function()
      test_controlled_string_fallback(function()
        print("LazyVim synchronous Enter prototype: PASS")
        vim.cmd("qa!")
      end)
    end)
  end)
end, debug.traceback)

if not ok then
  fail(err)
end
