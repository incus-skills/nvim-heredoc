-- Bounded scan attempts and atomic scan-snapshot reconciliation.
-- This module deliberately does not own event routing or buffer callbacks.
local planner = require("nvim-heredoc.planner")
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

local function source(lines)
  return table.concat(lines, "\n")
end

local function has_trailing_continuation(lines)
  local line = lines[#lines]
  if not line then return false end
  local count = 0
  for index = #line, 1, -1 do
    if line:sub(index, index) ~= "\\" then break end
    count = count + 1
  end
  return count % 2 == 1
end

local function attempt_confirmed(result, lines)
  return result.complete == true
    and #(result.diagnostics or {}) == 0
    and not has_trailing_continuation(lines)
end

local function offset_attempt(result, start_pos)
  local shifted = copy(result)
  for _, region in ipairs(shifted.heredocs or {}) do
    for _, field in ipairs(line_fields) do
      if type(region[field]) == "number" then
        region[field] = region[field] + start_pos - 1
      end
    end
    if type(region.group_key) == "number" then
      region.group_key = region.group_key + start_pos - 1
    end
    region.command_end_line = region.command_end_line
      or region.group_key
  end
  -- Scanner regions are aliases into heredocs; rebuild that view after
  -- translating each underlying record exactly once.
  shifted.regions = {}
  for _, region in ipairs(shifted.heredocs or {}) do
    if region.operator == "<<-" then
      shifted.regions[#shifted.regions + 1] = region
    end
  end
  for _, checkpoint in ipairs(shifted.checkpoints or {}) do
    checkpoint.pos = checkpoint.pos + start_pos - 1
    checkpoint.group_key = checkpoint.group_key + start_pos - 1
  end
  for _, diagnostic in ipairs(shifted.diagnostics or {}) do
    if type(diagnostic.line) == "number" then
      diagnostic.line = diagnostic.line + start_pos - 1
    end
  end
  return shifted
end

local function checkpoint_keys(result)
  local keys = {}
  for _, checkpoint in ipairs(result.checkpoints or {}) do
    keys[checkpoint.group_key] = true
  end
  return keys
end

local function mark_uncertain(region)
  region.editable = false
  region.opener_safe = false
  region.confidence = "uncertain"
end

local function group_key(region)
  return region.command_end_line or region.group_key
end

local function group_invalidated(plan, key)
  for _, item in ipairs(plan.invalidated_groups or {}) do
    if item.group_key == key then return true end
  end
  return false
end

local function surviving_old_group_keys(plan)
  local keys = {}
  for _, checkpoint in ipairs(plan.surviving_checkpoints or {}) do
    if checkpoint.group_key ~= nil then keys[checkpoint.group_key] = true end
  end
  return keys
end

local function records_for_scope(records, lower, upper, side, plan, valid_keys)
  local result = {}
  for _, record in ipairs(records or {}) do
    local key = group_key(record)
    local keep = key ~= nil and valid_keys[key] == true
      and not group_invalidated(plan, record.old_group_key or key)
    if keep then
      if side == "prefix" then
        keep = key < lower
      else
        keep = upper ~= nil and key >= upper
      end
    end
    if keep then result[#result + 1] = copy(record) end
  end
  return result
end

local function merge_records(old, fresh, start_pos, end_pos, plan)
  local old_heredocs = old.heredocs or old.regions or {}
  local valid_keys = surviving_old_group_keys(plan)
  local prefix = records_for_scope(old_heredocs, start_pos, nil, "prefix", plan, valid_keys)
  local suffix = records_for_scope(old_heredocs, nil, end_pos, "suffix", plan, valid_keys)
  local heredocs = {}
  for _, region in ipairs(prefix) do heredocs[#heredocs + 1] = region end
  for _, region in ipairs(fresh.heredocs or {}) do
    heredocs[#heredocs + 1] = copy(region)
  end
  for _, region in ipairs(suffix) do heredocs[#heredocs + 1] = region end

  local checkpoints = {}
  for _, checkpoint in ipairs(old.checkpoints or {}) do
    if valid_keys[checkpoint.group_key] then
      if checkpoint.pos <= start_pos or (end_pos and checkpoint.pos > end_pos) then
        checkpoints[#checkpoints + 1] = copy(checkpoint)
      end
    end
  end
  for _, checkpoint in ipairs(fresh.checkpoints or {}) do
    checkpoints[#checkpoints + 1] = copy(checkpoint)
  end

  table.sort(heredocs, function(a, b)
    if a.opener_line == b.opener_line then
      return (a.queue_position or 0) < (b.queue_position or 0)
    end
    return a.opener_line < b.opener_line
  end)
  table.sort(checkpoints, function(a, b) return a.pos < b.pos end)

  local regions = {}
  for _, region in ipairs(heredocs) do
    if region.operator == "<<-" then regions[#regions + 1] = region end
  end
  return regions, heredocs, checkpoints
end

local function scan_scope(scan, all_lines, start_pos, end_pos, opts)
  local scope = {}
  for index = start_pos, end_pos - 1 do
    scope[#scope + 1] = all_lines[index]
  end
  local result = scan(source(scope), opts)
  return result, scope
end

local function next_candidate(checkpoints, after, eof)
  for _, checkpoint in ipairs(checkpoints) do
    if checkpoint.pos > after and checkpoint.pos < eof then
      return checkpoint.pos
    end
  end
  return eof
end

-- Reconcile one planner result. scan(source, opts) must be the scanner used
-- for the source snapshot. No caller-visible state is mutated.
function M.reconcile(opts)
  assert(type(opts) == "table", "options are required")
  assert(type(opts.snapshot) == "table", "snapshot is required")
  assert(type(opts.plan) == "table", "planner result is required")
  assert(type(opts.lines) == "table", "current buffer lines are required")
  assert(type(opts.scan) == "function", "scan function is required")

  local old, plan, all_lines = opts.snapshot, opts.plan, opts.lines
  local scan_opts = opts.scan_opts or {}
  local eof = #all_lines + 1
  local start_pos = plan.S or 1

  if not plan.requires_rescan then
    local unchanged = copy(plan.mapped_snapshot or old)
    unchanged.complete = old.complete
    return {
      outcome = "commit",
      snapshot = unchanged,
      attempts = 0,
      fallback = false,
      changed = false,
    }
  end

  if plan.fallback_required then
    local full = opts.scan(source(all_lines), scan_opts)
    return {
      outcome = "commit",
      snapshot = full,
      attempts = 1,
      fallback = true,
      changed = true,
    }
  end

  local candidates = plan.surviving_checkpoints or {}
  local end_pos = plan.E or eof
  local attempts, final_result, final_scope, confirmed = 0, nil, nil, false

  while true do
    attempts = attempts + 1
    local result, scope = scan_scope(opts.scan, all_lines, start_pos, end_pos, scan_opts)
    final_result, final_scope = result, scope
    confirmed = attempt_confirmed(result, scope)
    if confirmed or end_pos == eof then break end
    end_pos = next_candidate(candidates, end_pos, eof)
  end

  local fresh = offset_attempt(final_result, start_pos)
  local observed = checkpoint_keys(fresh)
  for _, region in ipairs(fresh.heredocs or {}) do
    if not observed[group_key(region)] then
      mark_uncertain(region)
    else
      -- scanner.scan() conservatively downgrades every region when a later
      -- group fails. The attempt-local checkpoint restores confidence only
      -- for groups independently observed as complete.
      region.opener_safe = region.structural_tabs_only == true
      region.editable = region.terminator_line ~= nil and region.structural_tabs_only == true
      region.confidence = region.terminator_line
        and (region.structural_tabs_only and "lexical" or "unsupported-indent")
        or "incomplete"
    end
  end

  local regions, heredocs, checkpoints = merge_records(
    plan.mapped_snapshot or old, fresh, start_pos,
    confirmed and end_pos or nil, plan
  )

  local merged_complete
  if confirmed then
    merged_complete = end_pos == eof
      or (plan.mapped_snapshot or old).complete == true
  else
    merged_complete = false
  end

  return {
    outcome = "commit",
    snapshot = {
      regions = regions,
      heredocs = heredocs,
      checkpoints = checkpoints,
      diagnostics = copy(fresh.diagnostics or {}),
      complete = merged_complete,
    },
    attempts = attempts,
    fallback = false,
    changed = true,
    confirmed = confirmed,
    S = start_pos,
    E = confirmed and end_pos or nil,
    unresolved = not confirmed,
  }
end

-- Execute the transaction around reconciliation. is_entitled is checked
-- before scanning and again immediately before the single publication.
function M.transact(opts)
  assert(type(opts) == "table", "options are required")
  assert(type(opts.is_entitled) == "function", "is_entitled callback is required")
  assert(type(opts.publish) == "function", "publish callback is required")
  local function entitled()
    return opts.is_entitled(opts.base_generation, opts.owner)
  end

  if not entitled() then return { outcome = "discard", reason = "stale-entitlement" } end

  local result = M.reconcile(opts)
  if not entitled() then return { outcome = "discard", reason = "lost-entitlement" } end

  local next_generation = (opts.base_generation or 0) + 1
  local snapshot = copy(result.snapshot)
  snapshot.generation = next_generation
  opts.publish(snapshot, next_generation)
  if opts.clear_pending then opts.clear_pending(opts.owner) end

  result.snapshot = snapshot
  result.generation = next_generation
  return result
end

return M
