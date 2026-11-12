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

local function add_changed_range(ranges, firstline, new_lastline)
  local range = { start_row = firstline, end_row = new_lastline }
  local index = 1
  while index <= #ranges do
    local existing = ranges[index]
    -- Merge only overlapping or adjacent ranges. A bounding interval across
    -- disjoint edits would incorrectly authorise changes to untouched lines.
    if range.start_row <= existing.end_row and range.end_row >= existing.start_row then
      range.start_row = math.min(range.start_row, existing.start_row)
      range.end_row = math.max(range.end_row, existing.end_row)
      table.remove(ranges, index)
      index = 1
    else
      index = index + 1
    end
  end
  ranges[#ranges + 1] = range
end

local function process_pending_ranges(buf, close_incomplete)
  local pending = pending_ranges[buf]
  pending_ranges[buf] = nil
  if not pending then
    M.process_buffer(buf, nil, close_incomplete)
    return
  end
  for _, range in ipairs(pending.ranges) do
    M.process_buffer(buf, range, close_incomplete)
  end
end

local function schedule_changed_range(buf, firstline, new_lastline)
  if processing[buf] then
    return
  end
  local pending = pending_ranges[buf]
  if not pending then
    pending = { ranges = {} }
    pending_ranges[buf] = pending
  end
  add_changed_range(pending.ranges, firstline, new_lastline)

  if pending.scheduled then
    return
  end
  pending.scheduled = true
  vim.schedule(function()
    local current = pending_ranges[buf]
    if current ~= pending then
      return
    end
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
      and supported(vim.bo[buf].filetype) then
      process_pending_ranges(buf, false)
    else
      pending_ranges[buf] = nil
    end
  end)
end

local function process_text_changed(buf)
  process_pending_ranges(buf, true)
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
