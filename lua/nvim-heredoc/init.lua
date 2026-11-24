local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")
local planner = require("nvim-heredoc.planner")
local merge = require("nvim-heredoc.merge")

local M = {}
local group_name = "NvimHeredoc"
local processing = {}
local attached = {}
local pending_ranges = {}
local scan_snapshots = {}
local insert_sessions = {}

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

-- Heredoc bodies are lexical payload, including lines that resemble shell
-- commands or further heredoc openers. Use the scanner's existing lexical
-- boundary to prevent Return from interpreting payload as active shell code.
local function cursor_in_heredoc_payload(buf, row)
  local result = scanner.scan(get_source(get_lines(buf)), { tabstop = vim.bo[buf].tabstop })
  local line = row + 1
  for _, heredoc in ipairs(result.heredocs) do
    if line >= heredoc.body_start_line
      and (not heredoc.terminator_line or line < heredoc.terminator_line) then
      return true
    end
  end
  return false
end

-- Split payload literally. Do not delegate to shell indentexpr, autoindent,
-- or pair plugins: the containing heredoc must not format embedded content.
local function split_payload_line(buf, win, row, col, line)
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, {
    line:sub(1, col),
    line:sub(col + 1),
  })
  vim.api.nvim_win_set_cursor(win, { row + 2, 0 })
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
  -- The planner may invalidate a body-line coordinate when that exact line
  -- was replaced. The stable opener/terminator still delimit the body, so
  -- recover its half-open range from those surviving structural boundaries.
  local body_start = region.body_start_line
    or (type(region.opener_line) == "number" and region.opener_line + 1)
  local body_end = region.body_end_line
    or (type(region.terminator_line) == "number" and region.terminator_line - 1)
  if type(body_start) ~= "number" or type(body_end) ~= "number" then
    return false
  end
  local first_row = body_start - 1
  local last_row = body_end
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

-- Return is the commitment point for a new managed heredoc. Recognise
-- only the completed opener line and establish its body boundary locally;
-- no later buffer text or document-wide scan participates in this decision.
local function insert_return_local_closers(buf, changed_range)
  local cursor_row = active_cursor_row(buf)
  if not cursor_row or not changed_range
    or changed_range.start_row ~= cursor_row - 1
    or changed_range.end_row < cursor_row
    or changed_range.end_row > cursor_row + 1 then
    return nil
  end

  -- The line before the cursor is the candidate opener for this Return
  -- transition. If it is already inside another heredoc body, it is payload.
  if cursor_in_heredoc_payload(buf, cursor_row - 1) then
    return nil
  end

  local lines = get_lines(buf)
  local opener_line = lines[cursor_row]
  local body_line = lines[cursor_row + 1]
  if not opener_line or not body_line or not body_line:match("^[ \t]*$") then
    return nil
  end

  local openers = scanner.parse_openers(opener_line, { tabstop = vim.bo[buf].tabstop })
  if not openers then
    -- Do not let the document-wide recovery path reinterpret an unsupported
    -- managed-looking opener after this Return transition.
    if opener_line:find("<<%-") then
      return false
    end
    return nil
  end
  -- Multiple queued heredocs require multiple body/terminator boundaries.
  -- Keep that case conservative rather than guessing their placement here.
  if not openers or #openers == 0 then
    return nil
  end
  if #openers ~= 1 then
    return false
  end
  local opener = openers[1]
  if opener.operator ~= "<<-" or not opener.opener_safe then
    return false
  end

  local expected_closer = editing.closer_line(opener)
  if not expected_closer or lines[cursor_row + 2] == expected_closer then
    return false
  end
  if not insert_closer(buf, opener, cursor_row + 1) then
    return false
  end
  ensure_body_prefix(buf, opener, cursor_row)
  return true
end

local function normalize_heredoc_operators(line)
  return (line or ""):gsub("<<%-", "<<"):gsub("<<", "<")
end

local function opener_was_displaced(old, lines, edits)
  if not old.opener_line or not old.opener_text or not edits then
    return false
  end

  -- Track only the previous opener's line through the edits in this batch.
  -- An edit strictly before it moves the original line; an edit touching it
  -- means a later identical line cannot establish that it survived.
  local row = old.opener_line - 1
  for _, edit in ipairs(edits) do
    if edit.lastline <= row then
      row = row + edit.new_lastline - edit.lastline
    elseif edit.firstline <= row and row < edit.lastline then
      return false
    end
  end

  return row >= 0 and lines[row + 1] == old.opener_text
end

local function reconcile_managed_transition(buf, previous, current, edits)
  if not previous or not previous.heredocs or not current.heredocs then
    return false
  end

  local lines = get_lines(buf)
  local changed = false
  for _, old in ipairs(previous.heredocs) do
    local target_operator = old.operator == "<<-" and "<<" or old.operator == "<<" and "<<-" or nil
    local displaced = opener_was_displaced(old, lines, edits)
    if target_operator and not displaced then
      local replacement
      for _, new in ipairs(current.heredocs) do
        if new.operator == target_operator
          and new.opener_line == old.opener_line
          and new.queue_position == old.queue_position
          and new.delimiter == old.delimiter
          and new.delimiter_original == old.delimiter_original
          and normalize_heredoc_operators(new.opener_text)
            == normalize_heredoc_operators(old.opener_text) then
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

function M.process_buffer(buf, changed_range, close_incomplete, edits)
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
    -- A completed opener followed by Return is handled before any
    -- document-wide scan. The inserted closer immediately bounds this body.
    local return_result = insert_return_local_closers(buf, changed_range)
    if return_result == true then
      changed = true
    elseif return_result == nil then
      -- Existing-buffer recovery and managed-operator compatibility remain
      -- separate from establishing a new Return-local scope. A recognised
      -- but unsupported Return candidate is left untouched.
      for _ = 1, 32 do
        local lines = get_lines(buf)
        local result = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
        if reconcile_managed_transition(buf, previous_scan, result, edits) then
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
          -- below it so the closer is reserved before following source.
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
      end
  end)

  processing[buf] = nil
  if success then
    local snapshot_lines = get_lines(buf)
    local snapshot = scanner.scan(get_source(snapshot_lines), { tabstop = vim.bo[buf].tabstop })
    snapshot.tabstop = vim.bo[buf].tabstop
    snapshot.generation = ((previous_scan and previous_scan.generation) or 0) + 1
    scan_snapshots[buf] = snapshot
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

local function process_pending_ranges(buf)
  local pending = pending_ranges[buf]
  if not pending then
    -- TextChanged/other deferred callbacks are not permission to perform an
    -- un-ranged whole-buffer scan when there is no owned on_lines batch.
    return false
  end
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf)
    or not supported(vim.bo[buf].filetype) then
    if pending_ranges[buf] == pending then pending_ranges[buf] = nil end
    return false
  end

  local snapshot = scan_snapshots[buf]
  if not snapshot then
    snapshot = scanner.scan(get_source(get_lines(buf)), { tabstop = vim.bo[buf].tabstop })
    snapshot.generation = 0
    snapshot.tabstop = vim.bo[buf].tabstop
    scan_snapshots[buf] = snapshot
    pending.base_generation = 0
  end

  local current_lines = get_lines(buf)
  local current_tabstop = vim.bo[buf].tabstop
  local plan = planner.plan(snapshot, pending.edits, current_lines)
  if snapshot.tabstop ~= current_tabstop then
    -- A buffer-local indentation-option change invalidates the scanner's
    -- structural-prefix observations even when no source boundary changed.
    -- Rebuild the current post-edit buffer as this owned batch's fallback.
    plan.requires_rescan = true
    plan.fallback_required = true
  end
  -- Body bounds are derivable from surviving opener/terminator lines. A
  -- payload-line replacement can consume the old body-line coordinate while
  -- leaving both structural boundaries intact; restore those derived fields
  -- before this mapped snapshot becomes the next transaction's base state.
  local mapped_records = plan.mapped_snapshot.heredocs
  if type(mapped_records) ~= "table" or #mapped_records == 0 then
    mapped_records = plan.mapped_snapshot.regions or {}
  end
  local previous_terminators = {}
  for index, region in ipairs(mapped_records) do
    -- Some transitional records have no surviving command/opener identity.
    -- Keep those records isolated rather than indexing the grouping table
    -- with nil; only records with a shared structural identity can contribute
    -- predecessor terminators to one another.
    local group = region.command_end_line or region.group_key or region.opener_line
      or ("unkeyed-region-" .. index)
    local queue = region.queue_position or 1
    local prior = previous_terminators[group]
    if queue > 1 and prior and prior[queue - 1] then
      region.body_start_line = prior[queue - 1] + 1
    elseif type(region.opener_line) == "number" then
      region.body_start_line = region.opener_line + 1
    end
    if type(region.terminator_line) == "number" then
      region.body_end_line = region.terminator_line - 1
      previous_terminators[group] = prior or {}
      previous_terminators[group][queue] = region.terminator_line
    else
      region.body_end_line = nil
    end
  end
  local result = merge.transact({
    snapshot = snapshot,
    plan = plan,
    lines = current_lines,
    scan = scanner.scan,
    scan_opts = { tabstop = vim.bo[buf].tabstop },
    base_generation = pending.base_generation,
    owner = pending,
    is_entitled = function(base_generation, owner)
      local current = scan_snapshots[buf]
      return pending_ranges[buf] == owner
        and current ~= nil
        and (current.generation or 0) == base_generation
    end,
    publish = function(next_snapshot)
      next_snapshot.tabstop = current_tabstop
      scan_snapshots[buf] = next_snapshot
    end,
    clear_pending = function(owner)
      if pending_ranges[buf] == owner then
        pending_ranges[buf] = nil
      end
    end,
  })

  if result.outcome ~= "commit" then
    -- A stale batch must not publish, but it must also not remain queued
    -- indefinitely. Clear only this batch; a newer owner is untouched.
    if pending_ranges[buf] == pending then pending_ranges[buf] = nil end
    return false
  end

  -- Apply payload prefixing from the single committed snapshot. These edits
  -- are presentation/maintenance only: they do not create heredoc scopes,
  -- and their on_lines notifications are suppressed while this batch owns
  -- the buffer.
  processing[buf] = true
  local ok, err = pcall(function()
    -- Preserve the existing managed << / <<- compatibility transition as
    -- part of this owned batch; it does not create a new scope.
    reconcile_managed_transition(buf, snapshot, result.snapshot, pending.edits)
    for _, region in ipairs(result.snapshot.heredocs or {}) do
      if region.editable
        and (region.body_prefix or ((region.structural_prefix or "") .. "\t")) ~= "" then
        for _, range in ipairs(pending.ranges) do
          prefix_region_range(buf, region, range)
        end
      end
    end
  end)
  processing[buf] = nil
  if not ok then
    vim.notify("nvim-heredoc: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return true
end

local function schedule_changed_range(buf, firstline, lastline, new_lastline)
  if processing[buf] then
    return
  end
  local current_generation = (scan_snapshots[buf] and scan_snapshots[buf].generation) or 0
  local pending = pending_ranges[buf]
  if pending and pending.base_generation ~= current_generation then
    -- A full-scan publication superseded the previous batch. Start a fresh
    -- owner from that generation; the old scheduled closure will fail its
    -- identity check and cannot consume the new event history.
    pending_ranges[buf] = nil
    pending = nil
  end
  if not pending then
    pending = {
      ranges = {},
      edits = {},
      base_generation = current_generation,
    }
    pending_ranges[buf] = pending
  end
  pending.edits[#pending.edits + 1] = {
    firstline = firstline,
    lastline = lastline,
    new_lastline = new_lastline,
  }
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
      process_pending_ranges(buf)
    else
      pending_ranges[buf] = nil
    end
  end)
end

local function process_text_changed(buf)
  -- TextChanged is not a commitment event for an incomplete opener. Only
  -- Return may create a new heredoc scope; generic text changes must not
  -- append a closer before the user has completed the opener and pressed CR.
  process_pending_ranges(buf)
end

-- InsertLeave recovery is limited to an incomplete managed region that was
-- already present when this Insert session began. Keep its edit history
-- independently of pending_ranges: scheduled batch processing may consume
-- that queue before InsertLeave, but it must not erase the session's scope.
local function begin_insert_session(buf)
  local row = active_cursor_row(buf)
  local snapshot = scan_snapshots[buf]
  local candidate

  -- A pending pre-session batch means the committed snapshot may not describe
  -- the text at InsertEnter. Decline recovery rather than guessing its scope.
  if row ~= nil and snapshot and not pending_ranges[buf] then
    for _, region in ipairs(snapshot.regions or {}) do
      if region.operator == "<<-" and region.opener_safe
        and not region.terminator_line
        and type(region.body_start_line) == "number"
        and row + 1 >= region.body_start_line then
        if candidate then
          candidate = nil
          break
        end
        candidate = {
          opener_line = region.opener_line,
          opener_text = region.opener_text,
          delimiter = region.delimiter,
          body_start_line = region.body_start_line,
        }
      end
    end
  end

  insert_sessions[buf] = {
    candidate = candidate,
    edits = {},
  }
end

local function finish_insert_session(buf)
  local session = insert_sessions[buf]
  insert_sessions[buf] = nil
  local candidate = session and session.candidate
  if not candidate then
    return false
  end

  local cursor_row = active_cursor_row(buf)
  local body_start_row = candidate.body_start_line - 1
  if cursor_row == nil or cursor_row < body_start_row then
    return false
  end

  -- Every user edit in this Insert session must remain inside the same
  -- pre-existing incomplete body. In particular, an edit in another region
  -- cannot be hidden by the final cursor position.
  for _, edit in ipairs(session.edits) do
    if edit.firstline < body_start_row or edit.lastline < edit.firstline then
      return false
    end
  end

  local lines = get_lines(buf)
  if lines[candidate.opener_line] ~= candidate.opener_text then
    return false
  end

  -- Re-observe current text before mutation. The original opener must still
  -- be the same safe, incomplete managed region; a newly typed opener or an
  -- opener completed by a delimiter line is not eligible for recovery.
  local current = scanner.scan(get_source(lines), { tabstop = vim.bo[buf].tabstop })
  local pending
  for _, region in ipairs(current.regions or {}) do
    if region.operator == "<<-" and region.opener_safe
      and region.opener_line == candidate.opener_line
      and region.opener_text == candidate.opener_text
      and region.delimiter == candidate.delimiter
      and not region.terminator_line then
      if pending then
        return false
      end
      pending = region
    end
  end
  if not pending then
    return false
  end

  -- This is local recovery only: close and format this one established
  -- region. Suppress its own on_lines notifications, then publish the
  -- resulting snapshot so an older scheduled batch cannot replay stale work.
  processing[buf] = true
  local success, err = pcall(function()
    assert(insert_closer(buf, pending, vim.api.nvim_buf_line_count(buf)),
      "could not insert the locally authorised heredoc closer")
    local recovered_lines = get_lines(buf)
    local recovered = scanner.scan(get_source(recovered_lines), { tabstop = vim.bo[buf].tabstop })
    for _, region in ipairs(recovered.regions or {}) do
      if region.opener_line == candidate.opener_line
        and region.opener_text == candidate.opener_text
        and region.delimiter == candidate.delimiter
        and region.terminator_line then
        prefix_region_range(buf, region, nil)
        break
      end
    end
    local final_lines = get_lines(buf)
    local final_snapshot = scanner.scan(get_source(final_lines), { tabstop = vim.bo[buf].tabstop })
    final_snapshot.tabstop = vim.bo[buf].tabstop
    final_snapshot.generation = ((scan_snapshots[buf] and scan_snapshots[buf].generation) or 0) + 1
    scan_snapshots[buf] = final_snapshot
    pending_ranges[buf] = nil
  end)
  processing[buf] = nil
  if not success then
    vim.notify("nvim-heredoc: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return true
end

-- Insert-mode Return is the commitment event. Buffer-change notifications are
-- deferred and may coalesce several Returns with later typing into one range,
-- so they cannot reliably identify this transition. Intercept Return itself:
-- for one safe managed opener, create the first body line and closer before
-- returning to Neovim's input loop. Other lines retain MiniPairs' mapping (when
-- present) or native Return behaviour.
local function return_key(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf
    or vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
    vim.api.nvim_feedkeys("\r", "ni", false)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

  if cursor_in_heredoc_payload(buf, row) then
    -- Keep Blink's explicit completion acceptance, but do not pass payload
    -- Return through shell indentation or MiniPairs.
    local blink = package.loaded["blink.cmp"]
    if blink and type(blink.is_menu_visible) == "function"
      and blink.is_menu_visible() and type(blink.accept) == "function"
      and blink.accept() then
      return
    end
    split_payload_line(buf, win, row, col, line)
    return
  end

  if col == #line then
    local openers = scanner.parse_openers(line, { tabstop = vim.bo[buf].tabstop })
    if openers and #openers == 1 then
      local opener = openers[1]
      if opener.operator == "<<-" and opener.opener_safe then
        local closer = editing.closer_line(opener)
        if closer then
          local body_prefix = opener.body_prefix or ((opener.structural_prefix or "") .. "\t")
          -- Insert the bounded scope in one synchronous edit. Native Return
          -- must not run as well, or it would create a second body line.
          vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, {
            body_prefix,
            closer,
          })
          vim.api.nvim_win_set_cursor(win, { row + 2, #body_prefix })
          return
        end
      end
    end
  end

  -- Preserve Blink's default <CR> completion acceptance while its menu
  -- is visible. Its accept() result indicates whether it consumed the key;
  -- otherwise continue with the normal Insert-mode Return behaviour.
  local blink = package.loaded["blink.cmp"]
  if blink and type(blink.is_menu_visible) == "function"
    and blink.is_menu_visible() and type(blink.accept) == "function"
    and blink.accept() then
    return
  end

  -- MiniPairs' Insert-mode Return mapping is the common non-native mapping
  -- used by LazyVim. Resolve it at invocation time because MiniPairs may load
  -- after this buffer's FileType event.
  local mini_pairs = rawget(_G, "MiniPairs")
  local keys = "\r"
  if mini_pairs and type(mini_pairs.cr) == "function" then
    keys = mini_pairs.cr() or keys
  end
  -- This is a non-expression mapping so buffer edits above are permitted.
  -- Put the delegated Return sequence before the remaining typeahead: rapid
  -- nvim_input() bursts must observe the same key order as ordinary typing.
  keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(keys, "ni", false)
end

local function install_return_mapping(buf)
  vim.keymap.set("i", "<CR>", function()
    return_key(buf)
  end, {
    buffer = buf,
    expr = false,
    noremap = true,
    silent = true,
    desc = "nvim-heredoc: commit managed heredoc on Return",
  })
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
  install_return_mapping(buf)
  scan_snapshots[buf] = scanner.scan(get_source(get_lines(buf)), { tabstop = vim.bo[buf].tabstop })
  scan_snapshots[buf].tabstop = vim.bo[buf].tabstop
  scan_snapshots[buf].generation = 0
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, firstline, lastline, new_lastline)
      local session = insert_sessions[changed_buf]
      if session then
        session.edits[#session.edits + 1] = {
          firstline = firstline,
          lastline = lastline,
          new_lastline = new_lastline,
        }
      end
      schedule_changed_range(changed_buf, firstline, lastline, new_lastline)
    end,
    on_detach = function(_, detached_buf)
      attached[detached_buf] = nil
      pending_ranges[detached_buf] = nil
      scan_snapshots[detached_buf] = nil
      insert_sessions[detached_buf] = nil
    end,
  })

  local buffer_group = vim.api.nvim_create_augroup(group_name .. "Buffer" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = buffer_group,
    buffer = buf,
    callback = function()
      if supported(vim.bo[buf].filetype) then
        begin_insert_session(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = buffer_group,
    buffer = buf,
    callback = function()
      if supported(vim.bo[buf].filetype) then
        finish_insert_session(buf)
      else
        insert_sessions[buf] = nil
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

-- Read-only snapshot access for diagnostics and integration tests.
function M._snapshot_for_test(buf)
  return scan_snapshots[buf or vim.api.nvim_get_current_buf()]
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
