vim.opt.rtp:prepend("/workspace")
vim.opt.rtp:prepend("/opt/nvim-plugins/lazy.nvim")
vim.opt.rtp:prepend("/opt/nvim-plugins/LazyVim")
vim.opt.rtp:prepend("/opt/nvim-plugins/mini.pairs")
vim.opt.rtp:prepend("/opt/nvim-plugins/blink.cmp")
vim.opt.rtp:prepend("/opt/nvim-plugins/conform.nvim")

-- LazyVim's utility layer depends on lazy.nvim's runtime modules. We add the
-- pinned checkout to runtimepath but deliberately do not resolve a plugin graph:
-- each integration plugin is already checked out at its exact recorded revision.
-- Load the pinned LazyVim core with its user configuration hooks disabled.
-- The relevant plugin defaults are configured explicitly in the test below.
require("lazyvim").setup({
  colorscheme = function() end,
  defaults = {
    autocmds = false,
    keymaps = false,
  },
  news = {
    lazyvim = false,
    neovim = false,
  },
})
