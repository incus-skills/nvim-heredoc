vim.opt.rtp:prepend("/opt/nvim-plugins/lazy.nvim")
vim.opt.rtp:prepend("/opt/nvim-plugins/LazyVim")
vim.opt.rtp:prepend("/opt/nvim-plugins/mini.pairs")
vim.opt.rtp:prepend("/opt/nvim-plugins/blink.cmp")
vim.opt.rtp:prepend("/opt/nvim-plugins/conform.nvim")

-- Load the pinned LazyVim core with its user configuration hooks disabled.
-- The relevant integration plugin defaults are configured explicitly in the tests.
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

-- Exercise the same lazy.nvim loading contract users will use. The repository
-- is deliberately NOT placed on runtimepath here: lazy.nvim must add it only
-- after the first supported FileType event.
require("lazy").setup({
  spec = {
    {
      "incus-skills/nvim-heredoc",
      name = "nvim-heredoc",
      dir = "/workspace",
      main = "nvim-heredoc",
      ft = { "bash", "sh", "zsh" },
      opts = {},
    },
  },
  root = vim.fn.stdpath("data") .. "/lazy",
  lockfile = false,
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  performance = { rtp = { reset = false } },
})

assert(package.loaded["nvim-heredoc"] == nil,
  "nvim-heredoc must remain unloaded until a supported filetype is opened")
