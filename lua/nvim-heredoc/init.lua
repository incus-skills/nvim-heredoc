local scanner = require("nvim-heredoc.scanner")
local editing = require("nvim-heredoc.editing")

local M = {}
local group_name = "NvimHeredoc"

local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function get_source(lines)
  return table.concat(lines, "\n")
end

local function insert_prefixes(buf, region)
  local first = region.body_start_line
  local last = region.body_end_line
  if not last or last < first then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local prefixed, changed = editing.prefix_lines(region, lines)
  if not prefixed or not changed then
    return false
  end

  -- Prefix from the bottom so row positions remain stable for future
  -- range-tracking integrations and extmarks.
  for index = #lines, 1, -1 do
    if prefixed[index] ~= lines[index] then
      local row = first + index - 2
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

function M.process_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end

  local ok, busy = pcall(vim.api.nvim_buf_get_var, buf, "_nvim_heredoc_processing")
  if ok and busy then
    return false
  end
  vim.api.nvim_buf_set_var(buf, "_nvim_heredoc_processing", true)

  local changed = false
  local success, err = pcall(function()
    -- Each pass can close one pending heredoc. Re-scan so multiple queued
    -- heredocs are resolved in declaration order rather than guessed.
    for _ = 1, 32 do
      local lines = get_lines(buf)
      local result = scanner.scan(get_source(lines))
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
        local inserted = append_closer(buf, pending)
        if not inserted then
          break
        end
        changed = true
      else
        local pass_changed = false
        for _, region in ipairs(result.regions) do
          if region.editable and region.structural_prefix ~= "" then
            if insert_prefixes(buf, region) then
              pass_changed = true
            end
          end
        end
        changed = changed or pass_changed
        break
      end
    end
  end)

  pcall(vim.api.nvim_buf_del_var, buf, "_nvim_heredoc_processing")
  if not success then
    vim.notify("nvim-heredoc: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return changed
end

local function supported(ft)
  return ft == "bash" or ft == "sh" or ft == "zsh"
end

local function attach(buf)
  local ft = vim.bo[buf].filetype
  if not supported(ft) then
    return
  end
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
    group = vim.api.nvim_create_augroup(group_name .. "Buffer" .. buf, { clear = true }),
    buffer = buf,
    callback = function()
      if supported(vim.bo[buf].filetype) then
        M.process_buffer(buf)
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
