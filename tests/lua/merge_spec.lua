package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local merge = require("nvim-heredoc.merge")
local planner = require("nvim-heredoc.planner")
local scanner = require("nvim-heredoc.scanner")

local function result_plan(opts)
  local value = {
    requires_rescan = true, S = 1, E = 1,
    surviving_checkpoints = {}, invalidated_groups = {},
    invalidated_checkpoints = {}, mapped_snapshot = {
      regions = {}, heredocs = {}, checkpoints = {}, complete = true,
    },
  }
  for key, item in pairs(opts or {}) do value[key] = item end
  return value
end

local function run(plan, lines)
  return merge.reconcile({
    snapshot = plan.mapped_snapshot,
    plan = plan,
    lines = lines,
    scan = scanner.scan,
  })
end

-- Every extended candidate attempt starts again at the original S.
do
  local plan = result_plan({ E = 3, surviving_checkpoints = { { pos = 5 } } })
  local result = run(plan, {
    "cat <<-EOF", "payload", "EOF", "echo after",
  })
  assert(result.attempts == 2, "the unconfirmed first candidate should be extended")
  assert(result.confirmed and result.E == 5, "the extended candidate should be confirmed")
  assert(#result.snapshot.heredocs == 1)
  assert(result.snapshot.heredocs[1].opener_line == 1)
end

-- Attempt-local region, checkpoint, and group-key coordinates are all offset.
do
  local plan = result_plan({ S = 3, E = 7 })
  local result = run(plan, {
    "prefix", "prefix", "echo start", "cat <<-EOF", "payload", "EOF",
  })
  local region = result.snapshot.heredocs[1]
  local checkpoint = result.snapshot.checkpoints[1]
  assert(region.opener_line == 4 and region.command_start_line == 4)
  assert(region.command_end_line == 4, "the attempt group key must be offset")
  assert(checkpoint.pos == 7 and checkpoint.group_key == 4,
    "checkpoint boundary and group key must be offset")
end

-- A queue that fails between members is uncertain as one command group,
-- including the earlier member whose terminator was found.
do
  local plan = result_plan({ E = 5 })
  local result = run(plan, {
    "cat <<-A <<-B", "first body", "A", "second body",
  })
  assert(not result.confirmed and result.unresolved)
  assert(#result.snapshot.heredocs == 2)
  for _, region in ipairs(result.snapshot.heredocs) do
    assert(region.confidence == "uncertain" and not region.editable)
  end
  assert(#result.snapshot.checkpoints == 0, "an incomplete queue must have no checkpoint")
end

-- Earlier command groups are salvaged using their own checkpoint observations,
-- despite scanner.scan()'s document-wide confidence downgrade.
do
  local plan = result_plan({ E = 6 })
  local result = run(plan, {
    "cat <<-A", "first body", "A",
    "cat <<-B", "second body",
  })
  assert(not result.confirmed and #result.snapshot.heredocs == 2)
  assert(result.snapshot.heredocs[1].confidence == "lexical")
  assert(result.snapshot.heredocs[1].editable)
  assert(result.snapshot.heredocs[2].confidence == "uncertain")
  assert(not result.snapshot.heredocs[2].editable)
  assert(#result.snapshot.checkpoints == 1)
  assert(result.snapshot.checkpoints[1].pos == 4)
  assert(result.snapshot.complete == false)
end

-- Completed groups before and after the replaced scope remain independent.
do
  local old = scanner.scan(table.concat({
    "cat <<-PRE", "prefix body", "PRE",
    "cat <<-OLD", "old body", "OLD",
    "cat <<-SUF", "suffix body", "SUF",
  }, "\n"))
  local lines = {
    "cat <<-PRE", "prefix body", "PRE",
    "cat <<-NEW", "new body", "NEW",
    "cat <<-SUF", "suffix body", "SUF",
  }
  local plan = result_plan({
    S = 4, E = 7,
    mapped_snapshot = old,
    surviving_checkpoints = {
      { pos = 4, group_key = 1 },
      { pos = 7, group_key = 4 },
      { pos = 10, group_key = 7 },
    },
  })
  local result = merge.reconcile({
    snapshot = old, plan = plan, lines = lines, scan = scanner.scan,
  })
  assert(result.confirmed, "bounded suffix attempt was not confirmed: " .. vim.inspect(result))
  assert(result.snapshot.complete, "complete old suffix should preserve document completeness")
  assert(#result.snapshot.heredocs == 3)
  assert(result.snapshot.heredocs[1].delimiter == "PRE")
  assert(result.snapshot.heredocs[2].delimiter == "NEW")
  assert(result.snapshot.heredocs[3].delimiter == "SUF")
  assert(#result.snapshot.checkpoints == 3)
end

-- A lexical early return salvages earlier checkpointed groups only.
do
  local lines = {
    "cat <<-A", "body", "A",
    "echo " .. string.char(96) .. "unsupported" .. string.char(96),
  }
  local result = run(result_plan({ E = 5 }), lines)
  assert(not result.confirmed and #result.snapshot.heredocs == 1)
  assert(result.snapshot.heredocs[1].confidence == "lexical")
  assert(#result.snapshot.checkpoints == 1)
  assert(result.snapshot.complete == false)
end

-- The planner's incomplete-snapshot suffix guard selects full-buffer fallback.
do
  local old = {
    regions = {}, heredocs = {}, complete = false,
    checkpoints = { { pos = 8, group_key = 7 } },
  }
  local plan = {
    requires_rescan = true, S = 1, E = 4, fallback_required = true,
    mapped_snapshot = old, surviving_checkpoints = {},
    invalidated_groups = {}, invalidated_checkpoints = {},
  }
  local result = run(plan, { "echo one", "echo two", "echo three" })
  assert(result.fallback and result.attempts == 1)
  assert(result.snapshot.complete)
end

-- Compose the real planner and merge for a structural opener edit.
do
  local old_region = {
    operator = "<<-", delimiter = "EOF",
    command_start_line = 1, command_end_line = 1,
    opener_line = 1, body_start_line = 2, body_end_line = 2,
    terminator_line = 3, queue_position = 1, is_final_in_queue = true,
    structural_tabs_only = true, opener_safe = true, editable = true,
    confidence = "lexical",
  }
  local old = {
    regions = { old_region }, heredocs = { old_region },
    checkpoints = { { pos = 4, group_key = 1 } }, complete = true,
  }
  local lines = { "cat <<-NEW", "payload", "NEW", "echo after" }
  local planned = planner.plan(old, {
    { firstline = 0, lastline = 1, new_lastline = 1 },
  }, lines)
  local result = merge.reconcile({
    snapshot = old, plan = planned, lines = lines, scan = scanner.scan,
  })
  assert(result.confirmed and #result.snapshot.heredocs == 1)
  assert(result.snapshot.heredocs[1].delimiter == "NEW")
  assert(result.snapshot.complete)
end

-- A stale batch is discarded before scanning.
do
  local scans, publishes = 0, 0
  local result = merge.transact({
    snapshot = {}, plan = result_plan(), lines = { "echo" },
    scan = function() scans = scans + 1; return scanner.scan("echo") end,
    base_generation = 3, owner = "batch-a",
    is_entitled = function() return false end,
    publish = function() publishes = publishes + 1 end,
  })
  assert(result.outcome == "discard" and scans == 0 and publishes == 0)
end

-- Losing entitlement at the final check discards all provisional work.
do
  local checks, publishes, clears = 0, 0, 0
  local result = merge.transact({
    snapshot = {}, plan = result_plan({ E = 2 }), lines = { "echo" },
    scan = scanner.scan, base_generation = 4, owner = "batch-b",
    is_entitled = function()
      checks = checks + 1
      return checks == 1
    end,
    publish = function() publishes = publishes + 1 end,
    clear_pending = function() clears = clears + 1 end,
  })
  assert(result.outcome == "discard" and result.reason == "lost-entitlement")
  assert(checks == 2 and publishes == 0 and clears == 0)
end

-- One committed batch publishes once, clears only its owner, and advances once.
do
  local published, cleared = {}, {}
  local result = merge.transact({
    snapshot = { complete = true },
    plan = result_plan({ E = 3, surviving_checkpoints = { { pos = 5 } } }),
    lines = { "cat <<-EOF", "payload", "EOF", "echo after" },
    scan = scanner.scan,
    base_generation = 9, owner = "batch-c",
    is_entitled = function() return true end,
    publish = function(snapshot, generation)
      published[#published + 1] = { snapshot = snapshot, generation = generation }
    end,
    clear_pending = function(owner) cleared[#cleared + 1] = owner end,
  })
  assert(result.outcome == "commit" and result.generation == 10)
  assert(result.attempts == 2, "the transaction should have extended and rescanned")
  assert(#published == 1 and published[1].generation == 10)
  assert(published[1].snapshot.generation == 10)
  assert(#cleared == 1 and cleared[1] == "batch-c")
end

-- Empty R commits the mapped structural state without invoking the scanner.
do
  local scans = 0
  local old = { regions = {}, heredocs = {}, checkpoints = {}, complete = true }
  local result = merge.reconcile({
    snapshot = old,
    plan = { requires_rescan = false, mapped_snapshot = old },
    lines = { "payload" },
    scan = function() scans = scans + 1; return scanner.scan("payload") end,
  })
  assert(result.outcome == "commit" and not result.changed and scans == 0)
end

print("bounded snapshot merge tests: PASS")
