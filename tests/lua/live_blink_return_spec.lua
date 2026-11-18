package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function fail(err)
  print("live Blink Return test: FAIL: " .. tostring(err))
  vim.cmd("cquit 1")
end

local function defer(fn, delay)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then fail(err) end
  end, delay or 50)
end

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "if true; then",
  "\tcat <<-EOF",
  "\t\tpayloadcandidate",
  "\t\tpay",
  "\tEOF",
  "fi",
})
vim.bo[buf].filetype = "bash"
assert(vim.b[buf].nvim_heredoc_attached == true,
  "nvim-heredoc did not attach to the managed shell buffer")

require("mini.pairs").setup({
  modes = { insert = true, command = true, terminal = false },
  skip_ts = { "string" },
  skip_unbalanced = true,
  markdown = true,
})

local blink = require("blink.cmp")
blink.setup({
  sources = { default = { "buffer" } },
  completion = {
    menu = { auto_show = false },
    list = { selection = { preselect = false, auto_insert = false } },
  },
})

vim.api.nvim_win_set_cursor(0, { 4, 3 })
vim.api.nvim_input("A")

defer(function()
  assert(vim.api.nvim_get_mode().mode:sub(1, 1) == "i",
    "test did not enter Insert mode: " .. vim.inspect(vim.api.nvim_get_mode()))
  local mapping = vim.fn.maparg("<CR>", "i", false, true)
  assert(mapping.buffer == 1
    and mapping.desc == "nvim-heredoc: commit managed heredoc on Return",
    "nvim-heredoc Return wrapper is not active: " .. vim.inspect(mapping))

  blink.show({ providers = { "buffer" }, initial_selected_item_idx = 1 })
  assert(vim.wait(5000, function()
    return blink.is_menu_visible() and #blink.get_items() > 0
  end, 20), "Blink did not display buffer completion in the heredoc body")

  local selected = blink.get_selected_item()
  assert(selected ~= nil, "Blink did not select a completion item")
  local label = selected.label
  local before = vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1]
  assert(not before:find(label, 1, true),
    "completion was inserted before Return; expected a selection only")

  vim.api.nvim_input(vim.api.nvim_replace_termcodes("<CR>", true, false, true))
  defer(function()
    assert(vim.wait(1000, function()
      local line = vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1] or ""
      return line:find(label, 1, true) ~= nil
    end, 10), "Return wrapper did not delegate to Blink acceptance; line="
      .. vim.inspect(vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1])
      .. "; selected=" .. vim.inspect(blink.get_selected_item())
      .. "; menu_visible=" .. tostring(blink.is_menu_visible()))
    assert(not blink.is_menu_visible(),
      "Blink completion menu remained visible after Return acceptance")
    print("live Blink Return delegation test: PASS")
    vim.cmd("qa!")
  end, 50)
end, 50)
