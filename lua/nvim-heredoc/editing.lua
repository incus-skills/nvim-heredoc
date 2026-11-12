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
  for index, line in ipairs(lines) do
    if type(line) ~= "string" then
      return nil, "every changed line must be a string"
    end
    if prefix ~= "" and line:sub(1, #prefix) ~= prefix then
      output[index] = prefix .. line
      changed = true
    else
      output[index] = line
    end
  end
  return output, changed
end

return M
