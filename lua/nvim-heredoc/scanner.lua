-- Buffer-independent, conservative shell heredoc scanner.
-- This is a lexical prototype, not a complete Bash/sh/Zsh parser.
local M = {}

local function split_lines(source)
  local lines = {}
  source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (source .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

local function continued(line)
  local count, pos = 0, #line
  while pos > 0 and line:sub(pos, pos) == "\\" do
    count = count + 1
    pos = pos - 1
  end
  return count % 2 == 1
end

local function line_at_offset(chunk, offset)
  local line = 1
  for i = 1, math.min(offset - 1, #chunk) do
    if chunk:sub(i, i) == "\n" then line = line + 1 end
  end
  return line
end

local function parse_delimiter(s, pos)
  while s:sub(pos, pos):match("[ \t\r\n]") do pos = pos + 1 end
  local start, value, quote = pos, {}, nil
  local quoted, escaped = false, false

  while pos <= #s do
    local c = s:sub(pos, pos)
    if quote == "'" then
      if c == "'" then quote = nil else value[#value + 1] = c end
    elseif quote == '"' then
      if c == '"' then
        quote = nil
      elseif c == "\\" and pos < #s then
        local n = s:sub(pos + 1, pos + 1)
        if n == "$" or n == "`" or n == '"' or n == "\\" then
          value[#value + 1] = n
          pos = pos + 1
          escaped = true
        else
          value[#value + 1] = c
        end
      else
        value[#value + 1] = c
      end
    elseif c == "'" or c == '"' then
      quote, quoted = c, true
    elseif c == "\\" then
      if s:sub(pos + 1, pos + 1) == "\n" then
        pos = pos + 1
      else
        if pos == #s then return nil, pos, "delimiter ends with an escape" end
        value[#value + 1] = s:sub(pos + 1, pos + 1)
        pos, quoted, escaped = pos + 1, true, true
      end
    elseif c:match("[ \t\r\n]") or c:match("[;|&()<>]") then
      break
    else
      value[#value + 1] = c
    end
    pos = pos + 1
  end

  if quote then return nil, pos, "unterminated quoted delimiter" end
  if pos == start or #value == 0 then return nil, pos, "missing delimiter word" end
  return {
    original = s:sub(start, pos - 1),
    value = table.concat(value),
    quoted = quoted or escaped,
  }, pos
end

local function scan_command(chunk, first_line)
  local queue, diagnostics = {}, {}
  local i, quote, word_boundary = 1, nil, true
  local arithmetic_depth, test_depth = 0, 0

  while i <= #chunk do
    local c, n = chunk:sub(i, i), chunk:sub(i + 1, i + 1)
    if quote == "'" then
      if c == "'" then quote = nil end
      i = i + 1
    elseif quote == '"' then
      if c == "\\" then i = i + 2
      elseif c == '"' then quote = nil; i = i + 1
      elseif c == "$" and n == "(" then
        diagnostics[#diagnostics + 1] = "command substitution inside double quotes is outside the lexical prototype"
        return queue, diagnostics
      else i = i + 1 end
    elseif c == "\\" then
      if n == "\n" then
        i = i + 2
      elseif chunk:sub(i + 1, i + 3) == "<<<" then
        i = i + 4
      else
        i = i + 2
      end
      word_boundary = false
    elseif c == "'" or c == '"' then
      quote = c
      word_boundary = false
      i = i + 1
    elseif c == "`" or (c == "$" and n == "(") then
      diagnostics[#diagnostics + 1] = "command substitution is outside the lexical prototype"
      return queue, diagnostics
    elseif c == "#" and word_boundary then
      break
    elseif c == "(" and n == "(" then
      arithmetic_depth = arithmetic_depth + 1
      i = i + 2
    elseif c == ")" and n == ")" and arithmetic_depth > 0 then
      arithmetic_depth = arithmetic_depth - 1
      i = i + 2
    elseif c == "[" and n == "[" then
      test_depth = test_depth + 1
      i = i + 2
    elseif c == "]" and n == "]" and test_depth > 0 then
      test_depth = test_depth - 1
      i = i + 2
    elseif arithmetic_depth == 0 and test_depth == 0 and c == "<" and n == "<" then
      local op = chunk:sub(i, i + 2)
      if op == "<<<" then
        i = i + 3
      else
        local kind = op == "<<-" and "<<-" or "<<"
        local delimiter, next_pos, err = parse_delimiter(chunk, i + (kind == "<<-" and 3 or 2))
        if not delimiter then
          diagnostics[#diagnostics + 1] = err
          return queue, diagnostics
        end
        queue[#queue + 1] = {
          operator = kind,
          delimiter_original = delimiter.original,
          delimiter = delimiter.value,
          delimiter_quoted = delimiter.quoted,
          opener_offset = i,
          opener_line = first_line + line_at_offset(chunk, i) - 1,
        }
        i = next_pos
      end
      word_boundary = false
    else
      if c:match("[ \t\r\n]") or c:match("[;|&()]") then
        word_boundary = true
      else
        word_boundary = false
      end
      i = i + 1
    end
  end

  if quote then
    diagnostics[#diagnostics + 1] = "multiline or unterminated quote is outside the lexical prototype"
  end
  if arithmetic_depth > 0 or test_depth > 0 then
    diagnostics[#diagnostics + 1] = "unterminated arithmetic or conditional test context"
  end
  return queue, diagnostics
end

function M.scan(source)
  local lines = split_lines(source or "")
  local result = { regions = {}, diagnostics = {}, complete = true }
  local i = 1

  while i <= #lines do
    local first = i
    local parts = {}
    repeat
      parts[#parts + 1] = lines[i]
      local more = continued(lines[i])
      i = i + 1
      if not more or i > #lines then break end
    until false

    local chunk = table.concat(parts, "\n")
    local queue, diagnostics = scan_command(chunk, first)
    for _, message in ipairs(diagnostics) do
      result.complete = false
      result.diagnostics[#result.diagnostics + 1] = {
        line = first,
        message = message,
      }
    end

    for q, item in ipairs(queue) do
      item.queue_position = q
      item.command_end_line = i - 1
      if item.operator == "<<-" then
        local opener = lines[item.opener_line] or ""
        local prefix = opener:match("^([ \t]*)") or ""
        item.structural_prefix = prefix
        item.structural_tabs_only = not prefix:find(" ", 1, true)
      end

      local body_start, terminator = i, nil
      while i <= #lines do
        local candidate = lines[i]
        local match_line = item.operator == "<<-" and candidate:gsub("^\t+", "") or candidate
        if match_line == item.delimiter then
          terminator = i
          break
        end
        i = i + 1
      end

      if not terminator then
        result.complete = false
        result.diagnostics[#result.diagnostics + 1] = {
          line = item.opener_line,
          message = "heredoc terminator not found for " .. item.delimiter_original,
        }
        if item.operator == "<<-" then
          result.regions[#result.regions + 1] = {
            operator = item.operator,
            opener_line = item.opener_line,
            command_end_line = item.command_end_line,
            queue_position = q,
            delimiter_original = item.delimiter_original,
            delimiter = item.delimiter,
            delimiter_quoted = item.delimiter_quoted,
            body_start_line = body_start,
            body_end_line = nil,
            terminator_line = nil,
            structural_prefix = item.structural_prefix,
            structural_tabs_only = item.structural_tabs_only,
            confidence = "incomplete",
            editable = false,
          }
        end
        break
      end

      if item.operator == "<<-" then
        local safe = item.structural_tabs_only
        result.regions[#result.regions + 1] = {
          operator = item.operator,
          opener_line = item.opener_line,
          command_end_line = item.command_end_line,
          queue_position = q,
          delimiter_original = item.delimiter_original,
          delimiter = item.delimiter,
          delimiter_quoted = item.delimiter_quoted,
          body_start_line = body_start,
          body_end_line = terminator - 1,
          terminator_line = terminator,
          structural_prefix = item.structural_prefix,
          structural_tabs_only = safe,
          confidence = safe and (#diagnostics == 0 and "lexical" or "uncertain") or "unsupported-indent",
          editable = safe and #diagnostics == 0,
        }
      end
      i = terminator + 1
    end
  end

  return result
end

return M
