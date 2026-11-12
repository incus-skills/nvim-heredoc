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
  return (region.closer_prefix or region.structural_prefix or "") .. region.delimiter
end

function M.prefix_lines(region, lines)
  if not region or not region.opener_safe then
    return nil, "heredoc opener is not safe to edit"
  end
  if type(lines) ~= "table" then
    return nil, "changed lines must be a table"
  end

  local prefix = region.structural_prefix or ""
  local opener_prefix = region.closer_prefix or ""
  local output, insertions, changed = {}, {}, false
  for index, line in ipairs(lines) do
    if type(line) ~= "string" then
      return nil, "every line must be a string"
    end
    if line:sub(1, #prefix) == prefix then
      output[index] = line
    else
      local column, insertion
      if opener_prefix ~= "" and line:sub(1, #opener_prefix) == opener_prefix then
        -- Neovim may already have copied the opener indentation onto the
        -- new line. Add only the body-level TAB after that indentation.
        column, insertion = #opener_prefix, "\t"
      else
        -- Unindented or differently indented content needs the complete
        -- opener-relative body prefix at column zero.
        column, insertion = 0, prefix
      end
      output[index] = line:sub(1, column) .. insertion .. line:sub(column + 1)
      insertions[index] = { column = column, text = insertion }
      changed = true
    end
  end
  return output, changed, insertions
end

return M
