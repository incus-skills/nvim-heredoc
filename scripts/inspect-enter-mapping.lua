-- Read-only inventory of the effective Insert-mode <CR> mapping.
-- Run in the user's normal LazyVim instance on an ordinary shell line:
--   :luafile /path/to/nvim-heredoc/scripts/inspect-enter-mapping.lua

local mapping = vim.fn.maparg("<CR>", "i", false, true)
local maplist = vim.fn.maplist()
local matching = {}

for _, item in ipairs(maplist) do
  if item.lhs == "<CR>" and (item.mode == "i" or item.mode == "!" or item.mode == "") then
    matching[#matching + 1] = {
      lhs = item.lhs,
      rhs = item.rhs,
      expr = item.expr,
      callback = item.callback,
      buffer = item.buffer,
      mode = item.mode,
      noremap = item.noremap,
      script = item.script,
      sid = item.sid,
      desc = item.desc,
    }
  end
end

vim.print({
  current_buffer = vim.api.nvim_get_current_buf(),
  filetype = vim.bo.filetype,
  mode = vim.api.nvim_get_mode().mode,
  mini_pairs_loaded = package.loaded["mini.pairs"] ~= nil,
  blink_loaded = package.loaded["blink.cmp"] ~= nil,
  effective_insert_cr = {
    lhs = mapping.lhs,
    rhs = mapping.rhs,
    expr = mapping.expr,
    callback = mapping.callback,
    buffer = mapping.buffer,
    mode = mapping.mode,
    noremap = mapping.noremap,
    script = mapping.script,
    sid = mapping.sid,
  },
  matching_mappings = matching,
})
