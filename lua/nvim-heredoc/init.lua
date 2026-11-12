local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")

local M = {}
local group_name = "NvimHeredoc"
local processing = {}
local attached = {}
local pending_ranges = {}

local function supported(ft)
  return ft == "bash" or ft == "sh" or ft == "zsh"
end

local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function get_source(lines)
  return table.concat(lines, "\n")
end

local function prefix_region_range(buf, region, changed_range)
  local first_row = region.body_start_line - 1
  local last_row = region.body_end_line
  if last_row <= first_row then
    return false
  end

  if changed_range then
    first_row = math.max(first_row, changed_range.start_row)
    last_row = math.min(last_row, changed_range.end_row)
  end
  if last_row <= first_row then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buf, first_row, last_row, false)
  local prefixed, changed = editing.prefix_lines(region, lines)
  if not prefixed or not changed then
    return false
  end

  for index = #lines, 1, -1 do
    if prefixed[index] ~= lines[index] then
      local row = first_row + index - 1
      vim.api.nvim_buf_set_text(buf, row, 0, row, 0, { region.structural_prefix })
    end
  end
  return true
end

local function append_closer(buf, region)
  local closer, err = editing.closer_line(region)
  if not closer then
    return false, err
  end
  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, count, count, false, { closer })
  return true
end

function M.process_buffer(buf, changed_range, close_incomplete)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  if processing[buf] then
    return false
  end
  if close_incomplete == nil then
    close_incomplete = true
  end

  processing[buf] = true
  local changed = false
  local success, err = pcall(function()
    -- Each pass can close one pending heredoc. Re-scan so multiple queued
    -- heredocs are resolved in declaration order rather than guessed.
    for _ = 1, 32 do
      local lines = get_lines(buf)
      local result = scanner.scan(get_source(lines))
      if not result.complete then
        if not close_incomplete then
          break
        end
        local pending
        for _, region in ipairs(result.regions) do
          if not region.terminator_line and region.opener_safe then
            pending = region
            break
          end
        end
        if not pending then
          break
        end
        local inserted = append_closer(buf, pending)
        if not inserted then
          break
        end
        changed = true
      else
        local pass_changed = false
        for _, region in ipairs(result.regions) do
          if region.editable and region.structural_prefix ~= "" then
            if prefix_region_range(buf, region, changed_range) then
              pass_changed = true
            end
          end
        end
        changed = changed or pass_changed
        break
      end
    end
  end)

  processing[buf] = nil
  if not success then
    vim.notify("nvim-heredoc: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return changed
end

local function schedule_changed_range(buf, firstline, new_lastline)
  if processing[buf] then
    return
  end
  local pending = pending_ranges[buf]
  if pending then
    pending.start_row = math.min(pending.start_row, firstline)
    pending.end_row = math.max(pending.end_row, new_lastline)
    return
  end

  pending = {
    start_row = firstline,
    end_row = new_lastline,
  }
  pending_ranges[buf] = pending
  vim.schedule(function()
    local range = pending_ranges[buf]
    pending_ranges[buf] = nil
    if range and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
      and supported(vim.bo[buf].filetype) then
      M.process_buffer(buf, range, false)
    end
  end)
end

local function process_text_changed(buf)
  local range = pending_ranges[buf]
  pending_ranges[buf] = nil
  M.process_buffer(buf, range, true)
end

local function attach(buf)
  if attached[buf] then
    return
  end
  if not supported(vim.bo[buf].filetype) then
    return
  end

  attached[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, firstline, _, new_lastline)
      schedule_changed_range(changed_buf, firstline, new_lastline)
    end,
    on_detach = function(_, detached_buf)
      attached[detached_buf] = nil
      pending_ranges[detached_buf] = nil
    end,
  })

  local buffer_group = vim.api.nvim_create_augroup(group_name .. "Buffer" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = buffer_group,
    buffer = buf,
    callback = function()
      if supported(vim.bo[buf].filetype) then
        M.process_buffer(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = buffer_group,
    buffer = buf,
    callback = function()
      if supported(vim.bo[buf].filetype) then
        process_text_changed(buf)
      end
    end,
  })
end

function M.setup(opts)
  opts = opts or {}
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "bash", "sh", "zsh" },
    callback = function(args)
      attach(args.buf)
    end,
  })

  -- setup() may be called after the current buffer's FileType event.
  local current = vim.api.nvim_get_current_buf()
  if supported(vim.bo[current].filetype) then
    attach(current)
  end
end

return M
