-- Diagnostic: successive Return behaviour in the repository's pinned LazyVim
-- environment, with MiniPairs' real Insert-mode <CR> mapping.
--
-- Run by tests/run-lazyvim.sh twice: once with the shell indentexpr intact and
-- once with it disabled. This is observational: it records bytes but does not
-- assert a preferred indentation result, so CI can report the regression
-- without masking the trace behind a failing test.

local api = vim.api
local report = {}
local buf
local finished = false

local function add(label, value)
  report[#report + 1] = label .. ": " .. tostring(value)
end

local function snapshot(label)
  report[#report + 1] = ""
  report[#report + 1] = "===== " .. label .. " ====="
  for index, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    report[#report + 1] = string.format("%04d %q", index, line)
  end
  add("mode", api.nvim_get_mode().mode)
  add("cursor", vim.inspect(api.nvim_win_get_cursor(0)))
end

local function assert_insert(label)
  local current = api.nvim_get_mode().mode
  assert(current:sub(1, 1) == "i",
    label .. ": expected Insert mode, got " .. vim.inspect(current))
end

local function finish(ok, err)
  if finished then return end
  finished = true
  add("trace_result", ok and "PASS" or "ABORTED")
  if not ok then add("trace_error", err) end
  print(table.concat(report, "\n"))
  if ok then
    vim.cmd("qa!")
  else
    vim.cmd("cquit 1")
  end
end

local function run()
  vim.cmd("filetype plugin indent on")

  buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  local column_zero = vim.env.NVIM_HEREDOC_COLUMN_ZERO == "1"
  local opener = column_zero and "cat <<-'TRACE'" or "  cat <<-'TRACE'"
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# nvim-heredoc CI Return trace",
    "conf_print_test() {",
    opener,
  })
  vim.bo[buf].filetype = "sh"

  assert(vim.b[buf].nvim_heredoc_attached == true,
    "lazy.nvim did not attach nvim-heredoc to the sh buffer")
  require("mini.pairs").setup({
    modes = { insert = true, command = true, terminal = false },
    skip_ts = { "string" },
    skip_unbalanced = true,
    markdown = true,
  })

  -- Match the user's reported Neovim indentation options.
  local provisioned_expandtab = vim.env.NVIM_HEREDOC_PROVISIONED_EXPANDTAB == "1"
  vim.bo[buf].expandtab = not provisioned_expandtab
  vim.bo[buf].tabstop = 2
  vim.bo[buf].softtabstop = 0
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].autoindent = true
  vim.bo[buf].smartindent = false
  vim.bo[buf].cindent = false
  vim.bo[buf].formatoptions = "jncroql"

  local original_indentexpr = vim.bo[buf].indentexpr
  local control = vim.env.NVIM_HEREDOC_DISABLE_INDENTEXPR == "1"
  if control then vim.bo[buf].indentexpr = "" end

  local native_cr = vim.env.NVIM_HEREDOC_NATIVE_CR == "1"
  local sync_feedkeys = vim.env.NVIM_HEREDOC_SYNC_FEEDKEYS == "1"
  if native_cr then
    -- A buffer-local, nonrecursive <CR> mapping whose RHS is the native
    -- <CR> keycode. This shadows MiniPairs without disabling autoindent or
    -- the plugin's buffer callbacks.
    vim.keymap.set("i", "<CR>", "<CR>", {
      buffer = buf,
      noremap = true,
      desc = "Diagnostic native <CR> (MiniPairs bypass)",
    })
  end

  local cr_mapping = vim.fn.maparg("<CR>", "i", false, true)
  add("scenario", (column_zero and "column-zero opener; " or "")
    .. (native_cr and "native Return; MiniPairs bypassed; " or "Return wrapper delegates MiniPairs; ")
    .. (sync_feedkeys and "synchronous feedkeys; " or "queued nvim_input; ")
    .. (provisioned_expandtab and "provisioning expandtab=false" or "expandtab=true")
    .. (control and "; indentexpr disabled" or "; shell indentexpr enabled"))
  add("nvim_version", vim.inspect(vim.version()))
  add("filetype", vim.bo[buf].filetype)
  add("plugin_attached", vim.inspect(vim.b[buf].nvim_heredoc_attached))
  add("indentexpr", vim.inspect(original_indentexpr))
  add("active_indentexpr", vim.inspect(vim.bo[buf].indentexpr))
  add("autoindent", vim.inspect(vim.bo[buf].autoindent))
  add("expandtab", vim.inspect(vim.bo[buf].expandtab))
  add("tabstop", vim.inspect(vim.bo[buf].tabstop))
  add("softtabstop", vim.inspect(vim.bo[buf].softtabstop))
  add("shiftwidth", vim.inspect(vim.bo[buf].shiftwidth))
  add("formatoptions", vim.inspect(vim.bo[buf].formatoptions))
  add("Insert Return mapping", vim.inspect(cr_mapping))
  if native_cr then
    assert(cr_mapping.buffer == 1 and cr_mapping.noremap == 1,
      "native <CR> buffer-local nonrecursive mapping is not active: "
        .. vim.inspect(cr_mapping))
    assert(cr_mapping.rhs == "<CR>",
      "native <CR> mapping should bypass the plugin wrapper: " .. vim.inspect(cr_mapping))
  else
    assert(cr_mapping.buffer == 1 and cr_mapping.callback ~= nil,
      "nvim-heredoc's synchronous buffer-local Return wrapper is not active: "
        .. vim.inspect(cr_mapping))
    assert(type(MiniPairs) == "table" and type(MiniPairs.cr) == "function",
      "MiniPairs' Return callback is unavailable for delegation")
  end

  api.nvim_win_set_cursor(0, { 3, #opener - 1 })
  snapshot("before first Return")

  local steps = {
    { "after first Return", "\n", function(lines)
        assert(#lines >= 4, "first Return did not create a body line")
      end },
    { "after first payload", "hello1", function(lines)
        assert((lines[4] or ""):find("hello1", 1, true), "hello1 missing")
      end },
    { "after second Return", "\n", function(lines)
        assert(#lines >= 5, "second Return did not create a body line")
      end },
    { "after second payload", "hello2", function(lines)
        assert((lines[5] or ""):find("hello2", 1, true), "hello2 missing")
      end },
    { "after third Return", "\n", function(lines)
        assert(#lines >= 6, "third Return did not create a body line")
      end },
    { "after third payload", "hello3", function(lines)
        assert((lines[6] or ""):find("hello3", 1, true), "hello3 missing")
      end },
    { "after fourth Return", "\n", function(lines)
        assert(#lines >= 7, "fourth Return did not create a body line")
      end },
    { "after fourth payload", "hello4", function(lines)
        assert((lines[7] or ""):find("hello4", 1, true), "hello4 missing")
      end },
  }

  local function advance(index)
    if index > #steps then
      finish(true)
      return
    end
    local step = steps[index]
    assert_insert("before " .. step[1])
    if sync_feedkeys then
      -- Process typed input synchronously before the deferred snapshot. This
      -- separates input-drain timing from the ordinary nvim_input path.
      api.nvim_feedkeys(step[2], "tx", false)
    else
      api.nvim_input(step[2])
    end
    vim.defer_fn(function()
      local ok, err = xpcall(function()
        assert_insert("after " .. step[1])
        local current = api.nvim_buf_get_lines(buf, 0, -1, false)
        step[3](current)
        local expected
        local scenario
        if vim.env.NVIM_HEREDOC_ASSERT_COLUMN_ZERO == "1" then
          scenario = "column-zero"
          expected = {
            ["after first Return"] = { 4, "\t" },
            ["after first payload"] = { 4, "\thello1" },
            ["after second Return"] = { 5, "\t" },
            ["after second payload"] = { 5, "\thello2" },
            ["after third Return"] = { 6, "\t" },
            ["after third payload"] = { 6, "\thello3" },
            ["after fourth Return"] = { 7, "\t" },
            ["after fourth payload"] = { 7, "\thello4" },
          }
        elseif vim.env.NVIM_HEREDOC_ASSERT_INDENTED == "1" then
          scenario = "indented-opener"
          expected = {
            ["after first Return"] = { 4, "\t\t" },
            ["after first payload"] = { 4, "\t\thello1" },
            ["after second Return"] = { 5, "\t\t" },
            ["after second payload"] = { 5, "\t\thello2" },
            ["after third Return"] = { 6, "\t\t" },
            ["after third payload"] = { 6, "\t\thello3" },
            ["after fourth Return"] = { 7, "\t\t" },
            ["after fourth payload"] = { 7, "\t\thello4" },
          }
          assert(current[3] == "  cat <<-'TRACE'",
            "indented-opener regression: original opener bytes were changed")
        end
        local assertion = expected and expected[step[1]]
        if assertion then
          assert(current[assertion[1]] == assertion[2],
            step[1] .. ": " .. scenario .. " expected exact body bytes "
              .. vim.inspect(assertion[2]) .. ", got "
              .. vim.inspect(current[assertion[1]]))
        end
        if step[1] == "after fourth payload" and scenario == "indented-opener" then
          assert(current[8] == "\tTRACE",
            "indented-opener regression: closer must use one structural TAB, got "
              .. vim.inspect(current[8]))
        end
        snapshot(step[1])
      end, debug.traceback)
      if not ok then finish(false, err); return end
      advance(index + 1)
    end, 80)
  end

  -- Start at the opener's EOL and use the actual mapped Return key.
  api.nvim_input("A")
  vim.defer_fn(function()
    local ok, err = xpcall(function()
      assert_insert("entering Insert mode at opener EOL")
      snapshot("at opener EOL")
      advance(1)
    end, debug.traceback)
    if not ok then finish(false, err) end
  end, 50)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then finish(false, err) end
