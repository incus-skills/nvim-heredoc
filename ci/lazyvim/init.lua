vim.opt.rtp:prepend("/workspace")
vim.opt.rtp:prepend("/opt/nvim-plugins/lazy.nvim")
vim.opt.rtp:prepend("/opt/nvim-plugins/LazyVim")
vim.opt.rtp:prepend("/opt/nvim-plugins/mini.pairs")
vim.opt.rtp:prepend("/opt/nvim-plugins/blink.cmp")
vim.opt.rtp:prepend("/opt/nvim-plugins/conform.nvim")

-- Initialise lazy.nvim's runtime services without installing a moving plugin
-- graph. The fixture adds the exact plugin checkouts above directly to runtimepath.
require("lazy").setup({}, {
  root = "/tmp/lazy-root",
  lockfile = false,
})

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
