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

function M.prefix_lines(region, lines)
  if not region or not region.opener_safe then
    return nil, "heredoc opener is not safe to edit"
  end
  if type(lines) ~= "table" then
    return nil, "changed lines must be a table"
  end

  local prefix = region.structural_prefix or ""
  local output, changed = {}, false
  local function visual_width(value)
    local column, tabstop = 0, region.tabstop or 2
    for index = 1, #value do
      local byte = value:sub(index, index)
      if byte == "\\t" then
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
    if prefix ~= "" and line:sub(1, #prefix) ~= prefix then
      local width = line:match("^[ \\t]*$") and visual_width(line) or nil
      if width ~= nil and width == region.structural_column then
        -- Neovim may copy the opener's indentation onto a newly-created
        -- blank line. Convert that structural autoindent to TABs instead of
        -- retaining it as payload whitespace after <<- strips the TABs.
        output[index] = prefix
      else
        output[index] = prefix .. line
      end
      changed = true
    else
      output[index] = line
    end
  end
  return output, changed
end

return M
