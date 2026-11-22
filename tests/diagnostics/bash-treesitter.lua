local parser_path = assert(vim.env.NVIM_HEREDOC_BASH_PARSER, "NVIM_HEREDOC_BASH_PARSER is not set")
local query_runtime = assert(vim.env.NVIM_TREESITTER_RUNTIME, "NVIM_TREESITTER_RUNTIME is not set")

vim.opt.runtimepath:prepend(query_runtime)
assert(vim.treesitter.language.add("bash", { path = parser_path }))

local function node_range(node)
  local sr, sc, er, ec = node:range()
  return string.format("%d:%d-%d:%d", sr + 1, sc, er + 1, ec)
end

local function node_text(node, bufnr)
  return vim.treesitter.get_node_text(node, bufnr) or ""
end

local function walk(node, visit)
  visit(node)
  for child in node:iter_children() do
    walk(child, visit)
  end
end

local function inspect_nodes(root, bufnr)
  local bodies, ends, errors, missing = {}, {}, {}, {}
  walk(root, function(node)
    local kind = node:type()
    if kind == "heredoc_body" then
      bodies[#bodies + 1] = node
    elseif kind == "heredoc_end" then
      ends[#ends + 1] = node
    elseif kind == "ERROR" then
      errors[#errors + 1] = node
    end
    if node:missing() then
      missing[#missing + 1] = node
    end
  end)
  print("parse_has_error=" .. tostring(root:has_error()))
  print("ERROR_nodes=" .. #errors .. " MISSING_nodes=" .. #missing)
  for _, node in ipairs(errors) do
    print("  ERROR " .. node_range(node) .. " " .. vim.inspect(node_text(node, bufnr)))
  end
  for _, node in ipairs(missing) do
    print("  MISSING " .. node_range(node) .. " " .. node:type())
  end
  for _, node in ipairs(bodies) do
    print("  heredoc_body " .. node_range(node) .. " " .. vim.inspect(node_text(node, bufnr)))
  end
  for _, node in ipairs(ends) do
    print("  heredoc_end  " .. node_range(node) .. " " .. vim.inspect(node_text(node, bufnr)))
  end
  return bodies, ends, errors, missing
end

local function inspect_query(query_name, root, bufnr)
  local query = assert(vim.treesitter.query.get("bash", query_name),
    "missing Bash " .. query_name .. " query")
  local captures = {}
  for id, node, metadata in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    captures[#captures + 1] = { name = name, node = node, metadata = metadata }
    print(string.format("  %s capture @%s %s %s",
      query_name, name, node_range(node), vim.inspect(node_text(node, bufnr))))
  end
  return captures
end

local function find_capture(captures, name)
  local found = {}
  for _, capture in ipairs(captures) do
    if capture.name == name then
      found[#found + 1] = capture.node
    end
  end
  return found
end

local fixtures = {
  {
    name = "distinct-inner-delimiter",
    path = "tests/fixtures/treesitter/distinct-inner-delimiter.sh",
    body_must_contain = { "cat <<'INNER'", "inner-payload", "INNER", "outer-after" },
    body_must_not_contain = {},
    terminator = "OUTER",
  },
  {
    name = "same-delimiter-collision",
    path = "tests/fixtures/treesitter/same-delimiter-collision.sh",
    body_must_contain = { "cat <<'OUTER'", "collision-payload" },
    body_must_not_contain = { "after-outer" },
    terminator = "OUTER",
  },
}

for _, fixture in ipairs(fixtures) do
  print("\n===== " .. fixture.name .. " =====")
  local lines = vim.fn.readfile(fixture.path)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "bash"

  local parser = vim.treesitter.get_parser(bufnr, "bash")
  local trees = parser:parse()
  assert(trees and trees[1], "Bash parser returned no syntax tree for " .. fixture.name)
  local root = trees[1]:root()
  local bodies, ends, errors, missing = inspect_nodes(root, bufnr)

  assert(#bodies == 1, fixture.name .. ": expected exactly one heredoc_body, got " .. #bodies)
  assert(#ends == 1, fixture.name .. ": expected exactly one heredoc_end, got " .. #ends)
  local body_text = node_text(bodies[1], bufnr)
  local end_text = node_text(ends[1], bufnr)
  assert(end_text == fixture.terminator,
    fixture.name .. ": unexpected terminator text " .. vim.inspect(end_text))
  for _, expected in ipairs(fixture.body_must_contain) do
    assert(body_text:find(expected, 1, true),
      fixture.name .. ": body did not contain " .. vim.inspect(expected))
  end
  for _, unexpected in ipairs(fixture.body_must_not_contain) do
    assert(not body_text:find(unexpected, 1, true),
      fixture.name .. ": body unexpectedly contained " .. vim.inspect(unexpected))
  end

  local highlights = inspect_query("highlights", root, bufnr)
  local highlight_bodies = find_capture(highlights, "string")
  assert(#highlight_bodies == 1, fixture.name .. ": expected one @string body highlight")

  local injections = inspect_query("injections", root, bufnr)
  local injection_bodies = find_capture(injections, "injection.content")
  assert(#injection_bodies == 1, fixture.name .. ": expected one @injection.content capture")
  assert(node_range(injection_bodies[1]) == node_range(bodies[1]),
    fixture.name .. ": injection content range differs from heredoc_body")

  local injection_languages = find_capture(injections, "injection.language")
  assert(#injection_languages == 1, fixture.name .. ": expected one @injection.language capture")
  assert(node_range(injection_languages[1]) == node_range(ends[1]),
    fixture.name .. ": injection language capture differs from heredoc_end")
  print("injection.language captures=" .. #injection_languages)

  -- Ask Neovim's active highlighter for effective captures at payload and
  -- terminator positions. This is a headless capture diagnostic, not a
  -- screenshot or a claim about terminal colour rendering.
  local start_row = select(1, bodies[1]:range())
  local end_row = select(1, ends[1]:range())
  vim.treesitter.start(bufnr, "bash")
  vim.cmd("redraw!")
  if vim.treesitter.get_captures_at_pos then
    for _, position in ipairs({ { start_row, 0 }, { end_row, 0 } }) do
      local ok, active = pcall(vim.treesitter.get_captures_at_pos,
        bufnr, position[1], position[2])
      print("active_highlighter@" .. (position[1] + 1) .. ": "
        .. (ok and vim.inspect(active) or ("unavailable: " .. tostring(active))))
    end
  else
    print("active_highlighter captures API unavailable in this Neovim build")
  end

  print("fixture_result=PASS")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

print("\nBash Tree-sitter boundary diagnostics passed.")
