local function make_buffer(source)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  return buf
end

local function track(buf, records)
  local attached = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, firstline, lastline, new_lastline)
      local delta = new_lastline - lastline
      for _, record in ipairs(records) do
        if record.valid then
          if record.row < firstline then
            -- Edit is strictly after the tracked source line.
          elseif record.row >= lastline then
            record.row = record.row + delta
          else
            record.valid = false
          end
        end
      end
    end,
  })
  assert(attached)
end

local function assert_row(buf, record, expected, message)
  assert(record.valid and record.row == expected, message)
  local actual = vim.api.nvim_buf_get_lines(buf, record.row, record.row + 1, false)[1]
  assert(actual == record.text, message .. ": tracked row no longer contains its source line")
end

-- Inserting immediately after an opener must not move its identity.
do
  local buf = make_buffer({ "head", "cat <<'A'", "body", "A" })
  local records = { { row = 1, valid = true, text = "cat <<'A'" } }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "inserted after opener" })
  assert_row(buf, records[1], 1, "insertion after opener")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Deleting a range entirely before the opener shifts it by the exact delta.
do
  local buf = make_buffer({ "remove one", "remove two", "head", "cat <<'B'", "body", "B" })
  local records = { { row = 3, valid = true, text = "cat <<'B'" } }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 0, 2, false, { "replacement" })
  assert_row(buf, records[1], 2, "replacement before opener")
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
  assert_row(buf, records[1], 1, "deletion before opener")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- nvim_buf_set_lines() reports a replacement of the selected range even
-- when the replacement bytes are identical. The edit tracker therefore
-- invalidates the tracked source identity rather than guessing continuity
-- from matching text.
do
  local buf = make_buffer({ "head", "cat <<'C'", "body", "C" })
  local records = { { row = 1, valid = true, text = "cat <<'C'" } }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "cat <<'C'" })
  assert(not records[1].valid,
    "replacing the opener with identical text must still invalidate its source identity")

  -- A later insertion must not resurrect an invalidated identity.
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "later insertion" })
  assert(not records[1].valid,
    "later edits must not resurrect an invalidated opener identity")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Deleting the opener itself invalidates it; the following source line must
-- not be silently promoted to the old opener identity.
do
  local buf = make_buffer({ "head", "cat <<'D'", "body", "D" })
  local records = { { row = 1, valid = true, text = "cat <<'D'" } }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})
  assert(not records[1].valid, "deleting the opener must invalidate its identity")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- In a multi-line replacement, identities before the edit remain fixed,
-- identities after it shift, and identities inside it are invalidated.
do
  local buf = make_buffer({
    "cat <<'FIRST'",
    "first body",
    "FIRST",
    "middle",
    "cat <<'SECOND'",
    "second body",
    "SECOND",
  })
  local records = {
    { row = 0, valid = true, text = "cat <<'FIRST'" },
    { row = 4, valid = true, text = "cat <<'SECOND'" },
  }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 1, 3, false, { "replacement one", "replacement two", "replacement three" })
  assert_row(buf, records[1], 0, "opener before multi-line replacement")
  assert_row(buf, records[2], 5, "opener after multi-line replacement")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Two source identities: deleting the first invalidates only it and rebases
-- the second, preserving source order without relying on delimiter spelling.
do
  local buf = make_buffer({
    "cat <<'SAME'",
    "first",
    "SAME",
    "cat <<'SAME'",
    "second",
    "SAME",
  })
  local records = {
    { row = 0, valid = true, text = "cat <<'SAME'" },
    { row = 3, valid = true, text = "cat <<'SAME'" },
  }
  track(buf, records)
  vim.api.nvim_buf_set_lines(buf, 0, 3, false, {})
  assert(not records[1].valid, "deleted first opener must be invalidated")
  assert_row(buf, records[2], 0, "second opener after first heredoc deletion")
  vim.api.nvim_buf_delete(buf, { force = true })
end

print("opener identity edit-boundary characterization: PASS")
