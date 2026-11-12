-- Diagnose whether TextChangedI can repair a heredoc body line before
-- the next payload character when <CR> and that character are already queued.
--
-- Run inside the target LazyVim instance from Normal mode:
--   :luafile /path/to/nvim-heredoc/scripts/diagnose-textchangedi-order.lua
--
-- This is observation-only. It does not install a <CR> mapping or change the
-- plugin implementation. It uses a disposable Bash buffer and reports the
-- event order plus the plugin's existing trace.

if vim.api.nvim_get_mode().mode ~= "n" then
  vim.notify("nvim-heredoc ordering diagnostic: switch to Normal mode, then rerun", vim.log.levels.WARN)
  return
end

local ok_module, heredoc = pcall(require, "nvim-heredoc")
if not ok_module then
  vim.notify("nvim-heredoc ordering diagnostic: cannot load module: " .. tostring(heredoc), vim.log.levels.ERROR)
  return
end

local win = vim.api.nvim_get_current_win()
local original_buf = vim.api.nvim_win_get_buf(win)
local original_cursor = vim.api.nvim_win_get_cursor(win)
local original_bufhidden = vim.bo[original_buf].bufhidden
vim.bo[original_buf].bufhidden = "hide"

local old_trace_setting = vim.g.nvim_heredoc_trace
vim.g.nvim_heredoc_trace = true
heredoc.clear_trace()

local buf = vim.api.nvim_create_buf(false, true)
local group = vim.api.nvim_create_augroup("NvimHeredocTextChangedIDiagnostic", { clear = true })
local events = {}
local finished = false
local function snapshot(event, details)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1]
  local current = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  events[#events + 1] = {
    order = #events + 1,
    event = event,
    mode = vim.api.nvim_get_mode().mode,
    row = row,
    byte_col = cursor[2],
    line = current,
    time_ns = (vim.uv or vim.loop).hrtime(),
    buffer_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    details = details,
  }
end

local function finish()
  if finished then
    return
  end
  finished = true
  local mode_at_capture = vim.api.nvim_get_mode().mode
  if mode_at_capture == "i" then
    vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
  end
  vim.schedule(function()
    local report = {
      result = "OBSERVED",
      hypothesis = "TextChangedI after newline but before InsertCharPre for queued x",
      input = "<CR>x queued together via nvim_input",
      buffer = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or {},
      mode_at_capture = mode_at_capture,
      events = events,
      plugin_trace = heredoc.get_trace(),
      interpretation = nil,
    }
    local text_changed_i_order
    local payload_pre_order
    for _, event in ipairs(events) do
      if event.event == "TextChangedI" and not text_changed_i_order then
        text_changed_i_order = event.order
      elseif event.event == "InsertCharPre" and event.details and event.details.char == "x"
        and not payload_pre_order then
        payload_pre_order = event.order
      end
    end
    if not text_changed_i_order then
      report.interpretation = "No TextChangedI callback was observed in the capture window."
    elseif not payload_pre_order then
      report.interpretation = "No InsertCharPre for x was observed; inspect mode and input delivery."
    elseif text_changed_i_order < payload_pre_order then
      report.interpretation = "TextChangedI preceded InsertCharPre for x in this run; inspect line snapshots to determine whether repair could act in time."
    else
      report.interpretation = "InsertCharPre for x preceded TextChangedI; TextChangedI is too late for this batched-input case."
    end

    pcall(vim.api.nvim_del_augroup_by_id, group)
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(original_buf) then
      vim.api.nvim_win_set_buf(win, original_buf)
      vim.bo[original_buf].bufhidden = original_bufhidden
      pcall(vim.api.nvim_win_set_cursor, win, original_cursor)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    vim.g.nvim_heredoc_trace = old_trace_setting
    vim.notify("nvim-heredoc ordering diagnostic: complete (report follows)", vim.log.levels.INFO)
    vim.print(report)
  end)
end

vim.api.nvim_create_autocmd("TextChangedI", {
  group = group,
  buffer = buf,
  callback = function()
    snapshot("TextChangedI")
  end,
})
vim.api.nvim_create_autocmd("InsertCharPre", {
  group = group,
  buffer = buf,
  callback = function()
    snapshot("InsertCharPre", { char = vim.v.char })
  end,
})

-- Populate before attaching the Bash filetype so setup edits cannot be
-- mistaken for an Enter transition.
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "    cat <<-DIAG" })
vim.bo[buf].filetype = "bash"
vim.api.nvim_win_set_buf(win, buf)

assert(vim.b[buf].nvim_heredoc_attached == true,
  "the installed Bash ftplugin did not attach nvim-heredoc")
vim.api.nvim_win_set_cursor(win, { 1, #"    cat <<-DIAG" })
vim.api.nvim_input("A")

-- Let Insert mode begin before queueing Enter and x as one input batch.
vim.defer_fn(function()
  if finished or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  events = {}
  heredoc.clear_trace()
  vim.api.nvim_input(vim.api.nvim_replace_termcodes("<CR>x", true, false, true))
  -- Capture after Neovim has drained the submitted input. The event callbacks
  -- above preserve the order at the point each event actually ran.
  vim.defer_fn(finish, 150)
end, 30)
