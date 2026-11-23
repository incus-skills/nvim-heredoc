-- Pure coordinate and scope planner for incremental scan snapshots.
-- Edit records use Neovim on_lines coordinates; snapshot/result lines are 1-based.
local M = {}

local line_fields = {
  "opener_line", "body_start_line", "body_end_line",
  "terminator_line", "command_start_line", "command_end_line",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function delta(edit)
  return edit.new_lastline - edit.lastline
end

local function map_line(line, edit)
  if type(line) ~= "number" or line < 1 then return line end
  local row = line - 1
  if row < edit.firstline then return line end
  if row >= edit.lastline then return line + delta(edit) end
  return nil
end

-- A checkpoint boundary has before affinity. An insertion at the boundary
-- leaves it before inserted content; a consumed boundary cannot survive.
local function map_checkpoint(pos, edit)
  if type(pos) ~= "number" then return nil end
  local boundary = pos - 1
  if edit.firstline == edit.lastline then
    if boundary <= edit.firstline then return pos end
    return pos + delta(edit)
  end
  if boundary <= edit.firstline then return pos end
  if boundary >= edit.lastline then return pos + delta(edit) end
  return nil
end

-- Payload intervals are half-open. Start uses before affinity and end uses
-- after affinity, so insertions at either edge are included as payload.
-- If a replacement consumes an interval boundary, move that boundary outside
-- the replacement: changed lines are then treated conservatively as source.
local function map_payload_boundary(pos, edit, affinity)
  if type(pos) ~= "number" then return nil end
  local boundary = pos - 1
  local change = delta(edit)
  if edit.firstline == edit.lastline then
    if boundary < edit.firstline then return pos end
    if boundary > edit.firstline then return pos + change end
    return affinity == "after" and (pos + change) or pos
  end
  if boundary <= edit.firstline then return pos end
  if boundary >= edit.lastline then return pos + change end
  if affinity == "after" then return edit.firstline + 1 end
  return edit.new_lastline + 1
end


-- Structural anchors are positions, not checkpoint identities. If a later
-- edit consumes an anchor, retain it at that edit's first resulting position.
local function map_anchor(pos, edit)
  if type(pos) ~= "number" then return nil end
  local boundary = pos - 1
  if edit.firstline == edit.lastline then
    if boundary <= edit.firstline then return pos end
    return pos + delta(edit)
  end
  if boundary <= edit.firstline then return pos end
  if boundary >= edit.lastline then return pos + delta(edit) end
  return edit.firstline + 1
end

local function delimiter_matches(line, payload)
  if line == nil then return false end
  if payload.operator == "<<-" then
    return line:gsub("^\t+", "") == payload.delimiter
  end
  return line == payload.delimiter
end

local function sorted_unique(values)
  local seen, result = {}, {}
  for _, value in ipairs(values) do
    if type(value) == "number" and not seen[value] then
      seen[value] = true
      result[#result + 1] = value
    end
  end
  table.sort(result)
  return result
end

local function source_records(snapshot)
  if type(snapshot.heredocs) == "table" and #snapshot.heredocs > 0 then
    return snapshot.heredocs
  end
  return snapshot.regions or {}
end

local function make_groups(snapshot, old_line_count)
  local groups = {}
  for _, region in ipairs(source_records(snapshot)) do
    local key = region.command_end_line or region.group_key
    if key ~= nil then
      local group = groups[key]
      if not group then
        group = {
          old_group_key = key,
          current_group_key = key,
          command_start_line = nil,
          command_end_line = nil,
          structural_lines = {},
          payloads = {},
        }
        groups[key] = group
      end

      local first = region.command_start_line or region.opener_line
      local last = region.command_end_line or region.opener_line
      if first and last then
        group.command_start_line = group.command_start_line
          and math.min(group.command_start_line, first) or first
        group.command_end_line = group.command_end_line
          and math.max(group.command_end_line, last) or last
        for line = math.min(first, last), math.max(first, last) do
          group.structural_lines[line] = true
        end
      end
      if region.opener_line then group.structural_lines[region.opener_line] = true end
      if region.terminator_line then group.structural_lines[region.terminator_line] = true end

      if region.body_start_line then
        group.payloads[#group.payloads + 1] = {
          start_pos = region.body_start_line,
          end_pos = region.terminator_line or (old_line_count + 1),
          operator = region.operator,
          delimiter = region.delimiter,
        }
      end
    end
  end
  return groups
end

local function map_snapshot(snapshot, edit)
  local mapped = copy(snapshot)
  for _, name in ipairs({ "regions", "heredocs" }) do
    for _, region in ipairs(mapped[name] or {}) do
      region.old_group_key = region.old_group_key or region.command_end_line or region.group_key
      for _, field in ipairs(line_fields) do
        if region[field] ~= nil and region[field] > 0 then
          region[field] = map_line(region[field], edit)
        end
      end
      if region.group_key ~= nil then
        region.group_key = map_line(region.group_key, edit)
      end
    end
  end
  for _, checkpoint in ipairs(mapped.checkpoints or {}) do
    checkpoint.old_pos = checkpoint.old_pos or checkpoint.pos
    checkpoint.old_group_key = checkpoint.old_group_key or checkpoint.group_key
    checkpoint.pos = map_checkpoint(checkpoint.pos, edit)
    checkpoint.group_key = map_line(checkpoint.group_key, edit)
  end
  return mapped
end

local function map_groups(groups, edit)
  for _, group in pairs(groups) do
    group.current_group_key = map_line(group.current_group_key, edit)
    group.command_start_line = map_line(group.command_start_line, edit)
    group.command_end_line = map_line(group.command_end_line, edit)
    local structural = {}
    for line in pairs(group.structural_lines) do
      local mapped = map_line(line, edit)
      if mapped then structural[mapped] = true end
    end
    group.structural_lines = structural
    for _, payload in ipairs(group.payloads) do
      payload.start_pos = map_payload_boundary(payload.start_pos, edit, "before")
      payload.end_pos = map_payload_boundary(payload.end_pos, edit, "after")
      if payload.start_pos and payload.end_pos and payload.end_pos < payload.start_pos then
        payload.end_pos = payload.start_pos
      end
    end
  end
end

local function add_reason(reasons, key, reason)
  if key == nil then return end
  reasons[key] = reasons[key] or {}
  reasons[key][reason] = true
end

local function reasons_as_list(reasons)
  local result = {}
  for key, reason_set in pairs(reasons) do
    local names = {}
    for name in pairs(reason_set) do names[#names + 1] = name end
    table.sort(names)
    result[#result + 1] = { group_key = key, reasons = names }
  end
  table.sort(result, function(a, b) return a.group_key < b.group_key end)
  return result
end

-- Plan one ordered edit batch. current_lines is the complete post-edit buffer.
function M.plan(snapshot, edits, current_lines)
  assert(type(snapshot) == "table", "snapshot is required")
  assert(type(edits) == "table", "ordered edit records are required")
  assert(type(current_lines) == "table", "current buffer lines are required")

  local total_delta = 0
  for _, edit in ipairs(edits) do
    assert(type(edit.firstline) == "number"
      and type(edit.lastline) == "number"
      and type(edit.new_lastline) == "number", "invalid on_lines edit record")
    assert(edit.firstline >= 0 and edit.lastline >= edit.firstline
      and edit.new_lastline >= edit.firstline, "invalid on_lines coordinate interval")
    total_delta = total_delta + delta(edit)
  end

  local old_line_count = math.max(0, #current_lines - total_delta)
  local groups = make_groups(snapshot, old_line_count)
  local mapped = copy(snapshot)
  local reasons = {}
  local content_candidates, structural_anchors = {}, {}

  for _, edit in ipairs(edits) do
    local touched_structural = false

    -- Structural intersection is evaluated in this event's old coordinate
    -- space, after all preceding events have already been applied.
    if edit.lastline > edit.firstline then
      for _, group in pairs(groups) do
        for line in pairs(group.structural_lines) do
          local row = line - 1
          if row >= edit.firstline and row < edit.lastline then
            touched_structural = true
            add_reason(reasons, group.old_group_key, "structural-coordinate")
            break
          end
        end
      end
    elseif edit.firstline == edit.lastline then
      -- A line insertion between physical lines of a continued command
      -- changes the logical command structure even though no old line is
      -- consumed. The boundary after the final command line is the payload
      -- start, not an internal command-structure boundary.
      for _, group in pairs(groups) do
        if group.command_start_line and group.command_end_line
          and edit.firstline >= group.command_start_line
          and edit.firstline < group.command_end_line then
          touched_structural = true
          add_reason(reasons, group.old_group_key, "structural-insertion")
        end
      end
    end

    local moved_content = {}
    for _, pos in ipairs(content_candidates) do
      local mapped_pos = map_line(pos, edit)
      if mapped_pos then moved_content[#moved_content + 1] = mapped_pos end
    end
    content_candidates = moved_content

    local moved_anchors = {}
    for _, pos in ipairs(structural_anchors) do
      local mapped_pos = map_anchor(pos, edit)
      if mapped_pos then moved_anchors[#moved_anchors + 1] = mapped_pos end
    end
    structural_anchors = moved_anchors

    map_groups(groups, edit)
    mapped = map_snapshot(mapped, edit)

    for row = edit.firstline, edit.new_lastline - 1 do
      content_candidates[#content_candidates + 1] = row + 1
    end
    if touched_structural then
      structural_anchors[#structural_anchors + 1] = edit.firstline + 1
    end
  end

  local content_footprint = {}
  for _, pos in ipairs(sorted_unique(content_candidates)) do
    local line = current_lines[pos]
    local inside_payload = false
    for _, group in pairs(groups) do
      for _, payload in ipairs(group.payloads) do
        if payload.start_pos and payload.end_pos
          and pos >= payload.start_pos and pos < payload.end_pos then
          inside_payload = true
          if delimiter_matches(line, payload) then
            content_footprint[#content_footprint + 1] = pos
            add_reason(reasons, group.old_group_key, "payload-delimiter-match")
          end
        end
      end
    end
    if not inside_payload then content_footprint[#content_footprint + 1] = pos end
  end

  content_footprint = sorted_unique(content_footprint)
  structural_anchors = sorted_unique(structural_anchors)
  local all_positions = {}
  for _, pos in ipairs(content_footprint) do all_positions[#all_positions + 1] = pos end
  for _, pos in ipairs(structural_anchors) do all_positions[#all_positions + 1] = pos end
  local footprint = sorted_unique(all_positions)

  local invalidated_groups = {}
  for key in pairs(reasons) do invalidated_groups[key] = true end

  local invalidated_checkpoints, surviving_checkpoints = {}, {}
  for _, checkpoint in ipairs(mapped.checkpoints or {}) do
    local old_key = checkpoint.old_group_key
    local invalid = invalidated_groups[old_key] or checkpoint.pos == nil
      or checkpoint.group_key == nil
    checkpoint.invalidated = not not invalid
    if invalid then
      invalidated_checkpoints[#invalidated_checkpoints + 1] = checkpoint
    else
      surviving_checkpoints[#surviving_checkpoints + 1] = checkpoint
    end
  end
  table.sort(surviving_checkpoints, function(a, b) return a.pos < b.pos end)

  local start_pos, end_pos, fallback_required
  if #footprint > 0 then
    local first_pos, last_pos = footprint[1], footprint[#footprint]
    start_pos = 1
    for _, checkpoint in ipairs(surviving_checkpoints) do
      if checkpoint.pos <= first_pos and checkpoint.pos >= start_pos then
        start_pos = checkpoint.pos
      end
    end

    end_pos = #current_lines + 1
    for _, checkpoint in ipairs(surviving_checkpoints) do
      if checkpoint.pos >= last_pos + 1 and checkpoint.pos <= end_pos then
        end_pos = checkpoint.pos
      end
    end

    fallback_required = false
    if snapshot.complete == false then
      for _, checkpoint in ipairs(mapped.checkpoints or {}) do
        if checkpoint.pos ~= nil and checkpoint.pos >= end_pos then
          fallback_required = true
          break
        end
      end
    end
  end

  return {
    mapped_snapshot = mapped,
    invalidated_groups = reasons_as_list(reasons),
    invalidated_checkpoints = invalidated_checkpoints,
    surviving_checkpoints = surviving_checkpoints,
    I = invalidated_checkpoints,
    R_content = content_footprint,
    R_structural = structural_anchors,
    R = footprint,
    requires_rescan = #footprint > 0,
    S = start_pos,
    E = end_pos,
    fallback_required = fallback_required or false,
  }
end

return M
