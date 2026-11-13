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

local function active_cursor_row(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return nil
  end
  return vim.api.nvim_win_get_cursor(win)[1] - 1
end

local function advance_insert_cursor(buf, row)
  if active_cursor_row(buf) ~= row or vim.api.nvim_get_mode().mode ~= "i" then
    return
  end

  -- Buffer API insertion at column zero does not move Neovim's Insert-mode
  -- insertion point past the newly inserted TAB. Queue a literal Right key
  -- at the front of typeahead so it is consumed before the next user key.
  local right = vim.api.nvim_replace_termcodes("<Right>", true, false, true)
  vim.api.nvim_feedkeys(right, "ni", false)
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
  if not prefixed then
    return false
  end

  if changed then
    local cursor_row = active_cursor_row(buf)
    local cursor_line_prefixed = false
    for index = #lines, 1, -1 do
      if prefixed[index] ~= lines[index] then
        local row = first_row + index - 1
        vim.api.nvim_buf_set_text(buf, row, 0, row, 0, { region.structural_prefix })
        if row == cursor_row then
          cursor_line_prefixed = true
        end
      end
    end
    if cursor_line_prefixed then
      advance_insert_cursor(buf, cursor_row)
    end
  end

  return changed
end

local function insert_closer(buf, region, row)
  local closer, err = editing.closer_line(region)
  if not closer then
    return false, err
  end
  row = math.max(0, math.min(row, vim.api.nvim_buf_line_count(buf)))
  vim.api.nvim_buf_set_lines(buf, row, row, false, { closer })
  return true
end

local function ensure_body_prefix(buf, region, body_row)
  local prefix = region.structural_prefix or ""
  if prefix == "" then
    return
  end

  local line = vim.api.nvim_buf_get_lines(buf, body_row, body_row + 1, false)[1]
  if not line then
    return
  end
  if line:sub(1, #prefix) ~= prefix then
    local prefixed = editing.prefix_lines(region, { line }, { normalize_autoindent = true })
    if prefixed and prefixed[1] then
      vim.api.nvim_buf_set_text(buf, body_row, 0, body_row, #line, { prefixed[1] })
      advance_insert_cursor(buf, body_row)
    end
  end
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
      local result = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
      if not result.complete then
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

        local body_row = pending.body_start_line - 1
        local cursor_row = active_cursor_row(buf)
        local changed_body_line = not changed_range
          or (changed_range.start_row <= body_row and changed_range.end_row > body_row)
        local inserted = false

        -- Enter after the opener creates the first body line. Insert directly
        -- below it so the closer is reserved before an enclosing brace.
        if cursor_row == body_row and changed_body_line then
          inserted = insert_closer(buf, pending, body_row + 1)
          if inserted then
            -- Complete the Enter transition synchronously: Neovim may have
            -- auto-indented the new line already, but can leave the cursor
            -- before that TAB. Ensure both the prefix and insertion point
            -- are correct before the user types the first payload byte.
            ensure_body_prefix(buf, pending, body_row)
          end
        elseif close_incomplete then
          -- Retain the fallback for buffers opened with an incomplete region.
          inserted = insert_closer(buf, pending, vim.api.nvim_buf_line_count(buf))
        end

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

local function add_changed_range(ranges, firstline, lastline, new_lastline)
  local delta = new_lastline - lastline
  local current = {
    start_row = firstline,
    end_row = new_lastline,
  }
  local transformed = {}

  -- on_lines reports coordinates in the buffer *after* this edit. Rebase
  -- earlier pending ranges through the line-count delta before coalescing.
  for _, existing in ipairs(ranges) do
    local start_row, end_row = existing.start_row, existing.end_row
    local overlaps = false

    if lastline == firstline then
      -- Insertion: ranges after the insertion move; a range spanning the
      -- insertion point expands to include the inserted lines.
      if start_row >= firstline then
        start_row = start_row + delta
        end_row = end_row + delta
      elseif end_row > firstline then
        end_row = end_row + delta
        overlaps = true
      end
    elseif end_row <= firstline then
      -- Existing range is before this edit.
    elseif start_row >= lastline then
      start_row = start_row + delta
      end_row = end_row + delta
    else
      -- The edit intersects an earlier pending range. Map its surviving
      -- boundaries into the new buffer and merge the affected intervals.
      overlaps = true
      if start_row >= firstline then
        start_row = firstline
      end
      if end_row > lastline then
        end_row = end_row + delta
      else
        end_row = new_lastline
      end
    end

    transformed[#transformed + 1] = {
      start_row = start_row,
      end_row = end_row,
      overlaps = overlaps,
    }
  end

  if current.end_row > current.start_row then
    transformed[#transformed + 1] = current
  end
  table.sort(transformed, function(a, b)
    if a.start_row == b.start_row then
      return a.end_row < b.end_row
    end
    return a.start_row < b.start_row
  end)

  local merged = {}
  for _, range in ipairs(transformed) do
    local previous = merged[#merged]
    if previous and range.start_row <= previous.end_row then
      previous.end_row = math.max(previous.end_row, range.end_row)
    else
      merged[#merged + 1] = {
        start_row = range.start_row,
        end_row = range.end_row,
      }
    end
  end

  for index = #ranges, 1, -1 do
    ranges[index] = nil
  end
  for _, range in ipairs(merged) do
    ranges[#ranges + 1] = range
  end
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

local function schedule_changed_range(buf, firstline, lastline, new_lastline)
  if processing[buf] then
    return
  end
  local pending = pending_ranges[buf]
  if not pending then
    pending = { ranges = {} }
    pending_ranges[buf] = pending
  end
  add_changed_range(pending.ranges, firstline, lastline, new_lastline)

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
  vim.b[buf].nvim_heredoc_attached = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, firstline, lastline, new_lastline)
      schedule_changed_range(changed_buf, firstline, lastline, new_lastline)
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

function M.setup_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  attach(buf)
  return attached[buf] == true
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
