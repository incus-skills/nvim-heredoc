local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")

local M = {}
local group_name = "NvimHeredoc"
local processing = {}
local attached = {}
local pending_ranges = {}
local scan_snapshots = {}

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

local function position_insert_cursor(buf, row, col)
  if active_cursor_row(buf) ~= row or vim.api.nvim_get_mode().mode ~= "i" then
    return
  end

  -- Buffer API edits do not reliably advance Neovim's Insert-mode insertion
  -- point across a newly inserted TAB prefix. Set the byte column explicitly.
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
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
  local prefixed, changed = editing.prefix_lines(region, lines, { normalize_autoindent = changed_range ~= nil })
  if not prefixed then
    return false
  end

  if changed then
    local cursor_row = active_cursor_row(buf)
    for index = #lines, 1, -1 do
      if prefixed[index] ~= lines[index] then
        local row = first_row + index - 1
        local structural_prefix = region.structural_prefix or ""
        local insert_col, insert_text = 0, region.body_prefix
        if structural_prefix ~= "" and lines[index]:sub(1, #structural_prefix) == structural_prefix then
          insert_col, insert_text = #structural_prefix, "\t"
        end
        local cursor_col = row == cursor_row and vim.api.nvim_win_get_cursor(0)[2] or nil
        local body_prefix = region.body_prefix or (structural_prefix .. "\t")
        if lines[index]:match("^[ \t]*$") and prefixed[index] == body_prefix then
          -- Blank-line autoindent is replaced as a whole; inserting a prefix
          -- would leave the generated spaces behind it.
          vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { prefixed[index] })
          if row == cursor_row then
            position_insert_cursor(buf, row, #prefixed[index])
          end
        else
          vim.api.nvim_buf_set_text(buf, row, insert_col, row, insert_col, { insert_text })
          if row == cursor_row then
            local target_col = cursor_col >= insert_col and (cursor_col + #insert_text) or cursor_col
            position_insert_cursor(buf, row, target_col)
          end
        end
      end
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
  local prefix = region.body_prefix or ((region.structural_prefix or "") .. "\t")
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
      position_insert_cursor(buf, body_row, #prefix)
    end
  end
end

-- A Return edit can make an earlier completed heredoc appear to be the
-- terminator for a newly opened managed heredoc. Reserve the new command's
-- managed closers at the first body row before boundary recovery sees that
-- misleading complete scan.
local function insert_return_local_closers(buf, current, changed_range)
  local cursor_row = active_cursor_row(buf)
  if not cursor_row or not changed_range
    or changed_range.start_row >= cursor_row
    or changed_range.end_row <= cursor_row then
    return false
  end

  local lines = get_lines(buf)
  local body_line = lines[cursor_row + 1]
  if not body_line or not body_line:match("^[ \t]*$") then
    return false
  end

  local first
  for _, region in ipairs(current.regions) do
    if region.body_start_line - 1 == cursor_row and region.terminator_line
      and region.opener_safe then
      first = region
      break
    end
  end
  if not first then
    return false
  end

  -- Mixed managed/unmanaged queues need distinct body positions and remain
  -- on the existing conservative path.
  local queued = {}
  for _, heredoc in ipairs(current.heredocs) do
    if heredoc.opener_line == first.opener_line then
      if heredoc.operator ~= "<<-" or not heredoc.terminator_line or not heredoc.opener_safe then
        return false
      end
      queued[#queued + 1] = heredoc
    end
  end
  table.sort(queued, function(a, b)
    return a.queue_position < b.queue_position
  end)
  if #queued == 0 then
    return false
  end

  local closers = {}
  for index, heredoc in ipairs(queued) do
    local closer = editing.closer_line(heredoc)
    if not closer then
      return false
    end
    closers[index] = closer
  end

  -- An earlier pass may already have reserved the leading queued closer
  -- before Return. Keep that prefix and add only the remaining obligations.
  local already_reserved = 0
  for index, closer in ipairs(closers) do
    if lines[cursor_row + 2 + index - 1] == closer then
      already_reserved = index
    else
      break
    end
  end
  if already_reserved == #closers then
    return false
  end

  local missing = {}
  for index = already_reserved + 1, #closers do
    missing[#missing + 1] = closers[index]
  end
  -- One buffer edit reserves all remaining obligations in declaration order.
  local insert_row = cursor_row + 1 + already_reserved
  vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, missing)
  ensure_body_prefix(buf, first, cursor_row)
  return true
end

local function is_function_header(line)
  line = line or ""
  return line:match("^[ \t]*[A-Za-z_][A-Za-z0-9_]*%(%)[ \t]*{[ \t]*$")
    or line:match("^[ \t]*function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*{[ \t]*$")
end
local function function_header_before(lines, opener_line)
  for row = opener_line - 1, 1, -1 do
    if is_function_header(lines[row]) then
      return row
    end
  end
  return nil
end

local function preserve_function_heredoc_boundary(previous, current, lines)
  if not previous or not previous.heredocs then
    return false
  end

  for _, new in ipairs(current.regions) do
    local terminator = new.terminator_line
    if terminator then
      local header = function_header_before(lines, new.opener_line)
      if header then
        for _, old in ipairs(previous.heredocs) do
          if old.terminator_line and old.delimiter == new.delimiter and old.opener_text then
            for old_opener = new.body_start_line, terminator - 1 do
              if lines[old_opener] == old.opener_text then
                -- The old completed heredoc is now lexically inside the new
                -- region. A standalone brace between the new body and that
                -- old opener is the containing function's still-present
                -- autoclose boundary. Preserve both facts: the old heredoc
                -- is known from the previous scan, and the brace determines
                -- where the new heredoc must close.
                for boundary = new.body_start_line, old_opener - 1 do
                  if lines[boundary] and lines[boundary]:match("^[ \\t]*}$") then
                    new.terminator_line = nil
                    new.body_end_line = nil
                    new.boundary_line = boundary
                    new.editable = false
                    new.confidence = "incomplete"
                    current.complete = false
                    return true
                  end
                end
                -- The old opener is inside the apparent new body even when
                -- its function brace has been removed. In that case the old
                -- EOF is intentionally available as the new heredoc's
                -- terminator, but this must not be mistaken for an operator
                -- transition on the old opener's former line.
                return true
              end
            end
          end
        end
      end
    end
  end
  return false
end

local function reconcile_managed_transition(buf, previous, current)
  if not previous or not previous.heredocs or not current.heredocs then
    return false
  end

  local lines = get_lines(buf)
  local changed = false
  for _, old in ipairs(previous.heredocs) do
    local target_operator = old.operator == "<<-" and "<<" or old.operator == "<<" and "<<-" or nil
    if target_operator then
      local replacement
      for _, new in ipairs(current.heredocs) do
        if new.operator == target_operator
          and new.opener_line == old.opener_line
          and new.queue_position == old.queue_position
          and new.delimiter == old.delimiter
          and new.delimiter_original == old.delimiter_original then
          replacement = new
          break
        end
      end

      if replacement then
        local closer_row = replacement.terminator_line
        if not closer_row then
          local expected = (old.structural_prefix or "") .. old.delimiter
          local prior_row = old.terminator_line
          if prior_row and (lines[prior_row] == expected or lines[prior_row] == old.delimiter) then
            closer_row = prior_row
          else
            for row = replacement.body_start_line, #lines do
              if lines[row] == expected or lines[row] == old.delimiter then
                closer_row = row
                break
              end
            end
          end
        end

        if closer_row then
          local first = replacement.body_start_line - 1
          local body = {}
          for row = first + 1, closer_row - 1 do
            local line = lines[row]
            if old.operator == "<<-" then
              local prefix = old.body_prefix or ""
              if prefix ~= "" and line:sub(1, #prefix) == prefix then
                line = line:sub(#prefix + 1)
                changed = true
              end
            else
              local prefixed = editing.prefix_lines(replacement, { line })
              if prefixed and prefixed[1] ~= line then
                line = prefixed[1]
                changed = true
              end
            end
            body[#body + 1] = line
          end
          if #body > 0 then
            vim.api.nvim_buf_set_lines(buf, first, closer_row - 1, false, body)
          end

          local closer = lines[closer_row]
          if old.operator == "<<-" then
            local structural = old.structural_prefix or ""
            if structural ~= "" and closer:sub(1, #structural) == structural then
              closer = closer:sub(#structural + 1)
              changed = true
            end
          else
            local structural = replacement.structural_prefix or ""
            if structural ~= "" and closer:sub(1, #structural) ~= structural then
              closer = structural .. closer
              changed = true
            end
          end
          if closer ~= lines[closer_row] then
            vim.api.nvim_buf_set_lines(buf, closer_row - 1, closer_row, false, { closer })
          end
        end
      end
    end
  end
  return changed
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
  local previous_scan = scan_snapshots[buf]
  local success, err = pcall(function()
    -- Each pass can close one pending heredoc. Re-scan so multiple queued
    -- heredocs are resolved in declaration order rather than guessed.
    for _ = 1, 32 do
      local lines = get_lines(buf)
      local result = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
      if result.complete and insert_return_local_closers(buf, result, changed_range) then
        changed = true
        lines = get_lines(buf)
        result = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
      end
      local preserved_existing_heredoc =
        preserve_function_heredoc_boundary(previous_scan, result, lines)
      if not preserved_existing_heredoc and reconcile_managed_transition(buf, previous_scan, result) then
        changed = true
        lines = get_lines(buf)
        result = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
      end
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
        if pending.boundary_line then
          -- Keep the function's existing autoclose brace outside the
          -- heredoc. Scanner line numbers are 1-based; buffer insertion rows
          -- are 0-based.
          inserted = insert_closer(buf, pending, pending.boundary_line - 1)
        elseif cursor_row == body_row and changed_body_line then
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
          if region.editable and (region.body_prefix or ((region.structural_prefix or "") .. "\t")) ~= "" then
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
  if success then
    local snapshot_lines = get_lines(buf)
    scan_snapshots[buf] = scanner.scan(get_source(snapshot_lines), { tabstop = vim.bo[buf].tabstop })
  end
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
  scan_snapshots[buf] = scanner.scan(get_source(get_lines(buf)), { tabstop = vim.bo[buf].tabstop })
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, firstline, lastline, new_lastline)
      schedule_changed_range(changed_buf, firstline, lastline, new_lastline)
    end,
    on_detach = function(_, detached_buf)
      attached[detached_buf] = nil
      pending_ranges[detached_buf] = nil
      scan_snapshots[detached_buf] = nil
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

function M.setup()
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
