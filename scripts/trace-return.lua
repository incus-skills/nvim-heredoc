-- Trace successive Return operations through Neovim's normal event loop.
--
-- Run inside the affected Neovim instance:
--   :luafile /path/to/nvim-heredoc/scripts/trace-return.lua
--
-- Each input is queued in one scheduled callback and inspected in a later
-- callback, after Neovim has had an opportunity to process it. The test aborts
-- on any unexpected mode or missing text. Cleanup always restores the original
-- buffer and removes the scratch buffer. No options or plugin source are changed.

local api = vim.api
local fn = vim.fn
local original_buf = api.nvim_get_current_buf()
local original_win = api.nvim_get_current_win()
local report = {}
local scratch
local finished = false

local function add(label, value)
  report[#report + 1] = label .. ": " .. tostring(value)
end

local function inspect(value)
  return vim.inspect(value, { newline = "\n", indent = "  " })
end

local function mode()
  return api.nvim_get_mode().mode
end

local function assert_insert(stage)
  local current = mode()
  if current:sub(1, 1) ~= "i" then
    error(stage .. ": expected Insert mode, got " .. inspect(current))
  end
end

local function snapshot(stage)
  assert_insert("snapshot " .. stage)
  report[#report + 1] = ""
  report[#report + 1] = "===== " .. stage .. " ====="
  for index, line in ipairs(api.nvim_buf_get_lines(scratch, 0, -1, false)) do
    report[#report + 1] = string.format("%04d %q", index, line)
  end
  add("mode", mode())
  add("cursor", inspect(api.nvim_win_get_cursor(original_win)))
end

local function cleanup(ok, err)
  if finished then return end
  finished = true

  pcall(function()
    if api.nvim_get_current_win() == original_win and mode():sub(1, 1) == "i" then
      vim.cmd("stopinsert")
    end
  end)
  pcall(function()
    if api.nvim_win_is_valid(original_win) and api.nvim_buf_is_valid(original_buf) then
      api.nvim_win_set_buf(original_win, original_buf)
    end
  end)
  pcall(function()
    if scratch and api.nvim_buf_is_valid(scratch) then
      api.nvim_buf_delete(scratch, { force = true })
    end
  end)

  report[#report + 1] = ""
  add("trace_result", ok and "PASS" or "ABORTED")
  if not ok then add("trace_error", err) end

  local path = fn.stdpath("state") .. "/nvim-heredoc-return-trace.txt"
  local write_ok, write_err = pcall(fn.writefile, report, path)
  if not write_ok then
    vim.notify("nvim-heredoc trace could not write report: " .. tostring(write_err), vim.log.levels.ERROR)
  elseif ok then
    vim.notify("nvim-heredoc Return trace written to " .. path, vim.log.levels.INFO)
  else
    vim.notify("nvim-heredoc trace aborted; report written to " .. path, vim.log.levels.ERROR)
  end
end

local function stage(label, keys, verify)
  -- Queue input only after the previous stage's inspection has completed.
  if keys then
    assert_insert("before " .. label)
    local encoded = api.nvim_replace_termcodes(keys, true, false, true)
    local accepted = api.nvim_feedkeys(encoded, "mt", false)
    add("queued input (" .. label .. ")", accepted)
  end

  vim.defer_fn(function()
    local ok, err = xpcall(function()
      assert_insert("after " .. label)
      if verify then verify() end
      snapshot(label)
    end, debug.traceback)
    if not ok then cleanup(false, err) end
  end, 100)
end

local function run()
  scratch = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(original_win, scratch)
  api.nvim_buf_set_lines(scratch, 0, -1, false, {
    "# nvim-heredoc Return trace",
    "conf_print_test() {",
    "  cat <<-'TRACE'",
  })
  vim.bo[scratch].filetype = "sh"
  vim.defer_fn(function()
    local ok, err = xpcall(function()
      report[#report + 1] = "nvim-heredoc configured Return trace"
      add("timestamp", os.date("%Y-%m-%d %H:%M:%S %z"))
      add("nvim_version", inspect(vim.version()))
      add("scratch_filetype", vim.bo[scratch].filetype)
      add("plugin_attached", inspect(vim.b[scratch].nvim_heredoc_attached))
      for _, name in ipairs({
        "expandtab", "tabstop", "softtabstop", "shiftwidth", "autoindent",
        "smartindent", "cindent", "indentexpr", "indentkeys", "formatoptions",
      }) do
        local got, value = pcall(api.nvim_get_option_value, name, { buf = scratch })
        add(name, inspect(got and value or ("<unavailable: " .. tostring(value) .. ">")))
      end

      local maps = {}
      for _, map in ipairs(api.nvim_get_keymap("i")) do
        if map.lhs == "<CR>" or map.lhs == "<Enter>" then maps[#maps + 1] = map end
      end
      for _, map in ipairs(api.nvim_buf_get_keymap(scratch, "i")) do
        if map.lhs == "<CR>" or map.lhs == "<Enter>" then maps[#maps + 1] = map end
      end
      add("Insert Return mappings", inspect(maps))

      api.nvim_win_set_cursor(original_win, { 3, #"  cat <<-'TRACE'" })
      vim.cmd("startinsert")
    end, debug.traceback)
    if not ok then cleanup(false, err); return end

    -- Startinsert takes effect after this callback yields to the editor.
    vim.defer_fn(function()
      local started, start_err = xpcall(function()
        assert_insert("initial Insert-mode entry")
        snapshot("before first Return")
      end, debug.traceback)
      if not started then cleanup(false, start_err); return end

      local steps = {
        { "after first Return (first body line)", "<CR>", function()
            assert(#api.nvim_buf_get_lines(scratch, 0, -1, false) >= 4, "first Return did not create body line")
          end },
        { "after typing first payload", "hello1", function()
            assert((api.nvim_buf_get_lines(scratch, 3, 4, false)[1] or ""):find("hello1", 1, true), "hello1 missing")
          end },
        { "after second Return (new body line)", "<CR>", function()
            assert(#api.nvim_buf_get_lines(scratch, 0, -1, false) >= 5, "second Return did not create line")
          end },
        { "after typing second payload", "hello2", function()
            assert((api.nvim_buf_get_lines(scratch, 4, 5, false)[1] or ""):find("hello2", 1, true), "hello2 missing")
          end },
        { "after third Return (new body line)", "<CR>", function()
            assert(#api.nvim_buf_get_lines(scratch, 0, -1, false) >= 6, "third Return did not create line")
          end },
        { "after typing third payload", "hello3", function()
            assert((api.nvim_buf_get_lines(scratch, 5, 6, false)[1] or ""):find("hello3", 1, true), "hello3 missing")
          end },
        { "after fourth Return (new body line)", "<CR>", function()
            assert(#api.nvim_buf_get_lines(scratch, 0, -1, false) >= 7, "fourth Return did not create line")
          end },
        { "after typing fourth payload", "hello4", function()
            assert((api.nvim_buf_get_lines(scratch, 6, 7, false)[1] or ""):find("hello4", 1, true), "hello4 missing")
          end },
      }

      local function advance(index)
        if index > #steps then cleanup(true); return end
        local step = steps[index]
        local ok_queue, queue_err = xpcall(function()
          assert_insert("before " .. step[1])
          local encoded = api.nvim_replace_termcodes(step[2], true, false, true)
          api.nvim_feedkeys(encoded, "mt", false)
        end, debug.traceback)
        if not ok_queue then cleanup(false, queue_err); return end

        vim.defer_fn(function()
          local ok_check, check_err = xpcall(function()
            assert_insert("after " .. step[1])
            step[3]()
            snapshot(step[1])
          end, debug.traceback)
          if not ok_check then cleanup(false, check_err); return end
          advance(index + 1)
        end, 100)
      end

      advance(1)
    end, 100)
  end, 100)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then cleanup(false, err) end
