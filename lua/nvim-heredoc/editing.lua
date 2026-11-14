-- Pure helpers for structural heredoc edits.
-- Callers must pass only a scanner-confirmed region and a complete changed range.
local M = {}

function M.closer_line(region)
  if not region or not region.opener_safe then
    return nil, "heredoc opener is not safe to edit"
  end
  if type(region.delimiter) ~= "string" or type(region.delimiter_original) ~= "string"
    or region.delimiter_original == "" then
    return nil, "heredoc delimiter is unavailable"
  end
  return (region.structural_prefix or "") .. region.delimiter
end

function M.prefix_lines(region, lines, opts)
  opts = opts or {}
  if not region or not region.opener_safe then
    return nil, "heredoc opener is not safe to edit"
  end
  if type(lines) ~= "table" then
    return nil, "changed lines must be a table"
  end

  local structural_prefix = region.structural_prefix or ""
  local body_prefix = region.body_prefix or (structural_prefix .. "\t")
  local output, changed = {}, false
  local function visual_width(value)
    local column, tabstop = 0, region.tabstop or 2
    for index = 1, #value do
      local byte = value:sub(index, index)
      if byte == "\t" then
        column = column + tabstop - (column % tabstop)
      elseif byte == " " then
        column = column + 1
      else
        return nil
      end
    end
    return column
  end
  for index, line in ipairs(lines) do
    if type(line) ~= "string" then
      return nil, "every changed line must be a string"
    end

    if line:sub(1, #body_prefix) == body_prefix then
      output[index] = line
    elseif structural_prefix ~= "" and line:sub(1, #structural_prefix) == structural_prefix then
      -- Existing opener-aligned indentation needs exactly one additional
      -- literal TAB to become body indentation.
      output[index] = body_prefix .. line:sub(#structural_prefix + 1)
      changed = true
    else
      local width = opts.normalize_autoindent and line:match("^[ \t]*$") and visual_width(line) or nil
      if width ~= nil and width == region.structural_column then
        -- Neovim may copy the opener's indentation onto a newly-created
        -- blank line. Replace it with the deeper body prefix.
        output[index] = body_prefix
      else
        output[index] = body_prefix .. line
      end
      changed = true
    end
  end
  return output, changed
end

return M
