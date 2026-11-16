package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function attach_identity_tracker(buf, records)
  local attached = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, firstline, lastline, new_lastline)
      local delta = new_lastline - lastline
      for _, record in ipairs(records) do
        if record.valid then
          if record.row < firstline then
            -- The edit is after this source line.
          elseif record.row >= lastline then
            -- The edit is before this source line; preserve its identity while
            -- rebasing its current zero-based row.
            record.row = record.row + delta
          else
            -- The source line itself was replaced or deleted. Its prior
            -- identity can no longer be asserted from line coordinates.
            record.valid = false
          end
        end
      end
    end,
  })
  assert(attached, "Neovim should attach the edit-coordinate observer")
end

local function make_buffer(source)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  return buf
end

-- Case 1: insertion above a prior opener, followed by identical opener text
-- inserted before it as heredoc payload. The tracked row must continue to
-- point at the original source line, not the earlier duplicate.
do
  local buf = make_buffer({
    "old_function() {",
    "  cat <<'EOF'",
    "old payload",
    "EOF",
    "}",
  })
  local records = {
    { row = 1, valid = true, delimiter = "EOF" },
  }
  attach_identity_tracker(buf, records)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "new_function() {",
    "  cat <<-'NEW'",
    "}",
  })
  assert(records[1].valid and records[1].row == 4,
    "insertion above the prior opener should rebase its row")
  assert(lines(buf)[records[1].row + 1] == "  cat <<'EOF'")

  vim.api.nvim_buf_set_lines(buf, records[1].row, records[1].row, false, {
    "  cat <<'EOF'",
  })
  assert(records[1].valid and records[1].row == 5,
    "an identical payload line inserted at the tracked row must shift, not replace, the prior identity")
  local current = lines(buf)
  assert(current[5] == "  cat <<'EOF'" and current[6] == "  cat <<'EOF'",
    "fixture should contain payload duplicate immediately before the actual prior opener")
  assert(current[records[1].row + 1] == "  cat <<'EOF'",
    "tracked identity should resolve to the actual shifted prior opener")

  vim.api.nvim_buf_set_lines(buf, records[1].row, records[1].row + 1, false, {
    "  printf 'replacement'",
  })
  assert(not records[1].valid,
    "replacing the tracked source line must invalidate its prior identity")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Case 2: multiple prior opener identities must be ordered by their rebased
-- source positions, independently of delimiter equality or record iteration.
do
  local buf = make_buffer({
    "first() {",
    "  cat <<'SAME'",
    "first body",
    "SAME",
    "}",
    "second() {",
    "  printf x <<'SAME'",
    "second body",
    "SAME",
    "}",
  })
  local records = {
    { row = 6, valid = true, delimiter = "SAME" },
    { row = 1, valid = true, delimiter = "SAME" },
  }
  attach_identity_tracker(buf, records)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "new_function() {",
    "  cat <<-'SAME'",
    "}",
  })
  assert(records[1].row == 9 and records[2].row == 4,
    "both prior opener rows should follow inserted source lines")

  table.sort(records, function(a, b) return a.row < b.row end)
  assert(records[1].row == 4 and records[2].row == 9,
    "candidate boundaries should be considered in current source order")
  local current = lines(buf)
  assert(current[records[1].row + 1] == "  cat <<'SAME'")
  assert(current[records[2].row + 1] == "  printf x <<'SAME'")
  vim.api.nvim_buf_delete(buf, { force = true })
end

print("edit-mapped prior opener identity characterization: PASS")
