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
  if pos == start then return nil, pos, "missing delimiter word" end
  return {
    original = s:sub(start, pos - 1),
    value = table.concat(value),
    quoted = quoted or escaped,
  }, pos
end


local function skip_arithmetic_expansion(s, start)
  local depth, quote, i = 2, nil, start + 3
  while i <= #s do
    local c = s:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 2
      elseif c == quote then
        quote = nil
        i = i + 1
      else
        i = i + 1
      end
    elseif c == "'" or c == '"' then
      quote = c
      i = i + 1
    elseif c == "\\" then
      i = i + 2
    elseif c == "(" then
      depth = depth + 1
      i = i + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 then return i + 1 end
      i = i + 1
    else
      i = i + 1
    end
  end
  return nil, "unterminated arithmetic expansion"
end

local function skip_command_substitution(s, start)
  local depth, quote, word_boundary = 1, nil, true
  local arithmetic_depth, test_depth = 0, 0
  local substitution_contexts = {}
  local i = start + 2

  while i <= #s do
    local c, n = s:sub(i, i), s:sub(i + 1, i + 1)
    if quote == "'" then
      if c == "'" then quote = nil end
      i = i + 1
    elseif quote == '"' then
      if c == "\\" then
        i = i + 2
      elseif c == '"' then
        quote = nil
        i = i + 1
      elseif c == "$" and s:sub(i, i + 2) == "$((" then
        local next_pos, err = skip_arithmetic_expansion(s, i)
        if not next_pos then return nil, err end
        i = next_pos
      elseif c == "$" and n == "(" then
        depth = depth + 1
        substitution_contexts[depth] = { quote = quote }
        quote = nil
        i = i + 2
      elseif c == "`" then
        return nil, "backtick substitution inside command substitution is unsupported"
      else
        i = i + 1
      end
    elseif c == "\\" then
      i = i + 2
      word_boundary = false
    elseif c == "'" or c == '"' then
      quote = c
      word_boundary = false
      i = i + 1
    elseif c == "`" then
      return nil, "backtick substitution inside command substitution is unsupported"
    elseif c == "$" and s:sub(i, i + 2) == "$((" then
      local next_pos, err = skip_arithmetic_expansion(s, i)
      if not next_pos then return nil, err end
      i = next_pos
      word_boundary = false
    elseif c == "$" and n == "(" then
      depth = depth + 1
      substitution_contexts[depth] = { quote = quote }
      quote = nil
      i = i + 2
      word_boundary = false
    elseif c == "#" and word_boundary then
      local newline = s:find("\n", i, true)
      if not newline then return nil, "unterminated command substitution comment" end
      i = newline + 1
      word_boundary = true
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
      if s:sub(i, i + 2) == "<<<" then
        i = i + 3
      else
        return nil, "heredoc redirection inside command substitution is unsupported"
      end
    elseif c == "(" then
      depth = depth + 1
      i = i + 1
    elseif c == ")" then
      if depth == 1 then return i + 1 end
      local context = substitution_contexts[depth]
      depth = depth - 1
      if context then
        quote = context.quote
        substitution_contexts[depth + 1] = nil
      end
      i = i + 1
    else
      if c:match("[ \t\r\n]") or c:match("[;|&]") then
        word_boundary = true
      else
        word_boundary = false
      end
      i = i + 1
    end
  end
  return nil, "unterminated command substitution"
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
      elseif c == "$" and chunk:sub(i, i + 2) == "$((" then
        local next_pos, err = skip_arithmetic_expansion(chunk, i)
        if not next_pos then
          diagnostics[#diagnostics + 1] = err
          return queue, diagnostics
        end
        i = next_pos
      elseif c == "$" and n == "(" then
        local next_pos, err = skip_command_substitution(chunk, i)
        if not next_pos then
          diagnostics[#diagnostics + 1] = err
          return queue, diagnostics
        end
        i = next_pos
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
    elseif c == "$" and chunk:sub(i, i + 2) == "$((" then
      local next_pos, err = skip_arithmetic_expansion(chunk, i)
      if not next_pos then
        diagnostics[#diagnostics + 1] = err
        return queue, diagnostics
      end
      i = next_pos
      word_boundary = false
    elseif c == "$" and n == "(" then
      local next_pos, err = skip_command_substitution(chunk, i)
      if not next_pos then
        diagnostics[#diagnostics + 1] = err
        return queue, diagnostics
      end
      i = next_pos
      word_boundary = false
    elseif c == "`" then
      diagnostics[#diagnostics + 1] = "backtick substitution is outside the lexical prototype"
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

function M.scan(source, opts)
  opts = opts or {}
  local tabstop = math.max(1, tonumber(opts.tabstop) or 2)
  local shiftwidth = math.max(1, tonumber(opts.shiftwidth) or tabstop)
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
    if #diagnostics > 0 then
      result.complete = false
      for _, message in ipairs(diagnostics) do
        result.diagnostics[#result.diagnostics + 1] = {
          line = first,
          message = message,
        }
      end
      -- Once lexical state is uncertain, later physical lines may still be
      -- heredoc payload. Do not continue scanning them as shell source.
      for _, region in ipairs(result.regions) do
        region.editable = false
        region.opener_safe = false
        region.confidence = "uncertain"
      end
      return result
    end

    for q, item in ipairs(queue) do
      item.queue_position = q
      item.command_end_line = i - 1
      if item.operator == "<<-" then
        local opener = lines[item.opener_line] or ""
        local prefix = opener:match("^([ \t]*)") or ""
        local has_spaces = prefix:find(" ", 1, true) ~= nil
        local has_tabs = prefix:find("\\t", 1, true) ~= nil
        -- The editor-only body indentation must be entirely TABs: <<-
        -- strips every leading TAB, so no structural spaces may leak into
        -- the delivered payload. Convert the opener's visual indentation
        -- plus one shiftwidth of body indentation into TABs. Decline mixed
        -- prefixes and columns that cannot be represented exactly.
        local column = 0
        for char in prefix:gmatch(".") do
          if char == "\\t" then
            column = column + tabstop - (column % tabstop)
          else
            column = column + 1
          end
        end
        local body_column = column + shiftwidth
        item.structural_safe = not (has_spaces and has_tabs)
          and body_column % tabstop == 0
        item.space_indented = has_spaces and not has_tabs
        item.opener_prefix = prefix
        item.closer_prefix = has_spaces and "\\t" or prefix
        item.structural_prefix = item.structural_safe
          and string.rep("\\t", body_column / tabstop) or ""
        item.structural_tabs_only = true
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
            closer_prefix = item.closer_prefix,
            opener_prefix = item.opener_prefix,
            space_indented = item.space_indented,
            structural_tabs_only = item.structural_tabs_only,
            opener_safe = item.structural_safe,
            confidence = "incomplete",
            editable = false,
          }
        end
        break
      end

      if item.operator == "<<-" then
        local safe = item.structural_safe
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
          closer_prefix = item.closer_prefix,
          opener_prefix = item.opener_prefix,
          space_indented = item.space_indented,
          structural_tabs_only = item.structural_tabs_only,
          opener_safe = safe,
          confidence = safe and "lexical" or "unsupported-indent",
          editable = safe and #diagnostics == 0,
        }
      end
      i = terminator + 1
    end
  end

  if not result.complete then
    for _, region in ipairs(result.regions) do
      region.editable = false
      if region.confidence ~= "incomplete" then
        region.opener_safe = false
        region.confidence = "uncertain"
      end
    end
  end

  return result
end

return M
