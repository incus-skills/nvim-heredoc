-- Load the buffer integration when this plugin enters runtimepath.
if vim.g.loaded_nvim_heredoc then
  return
end

vim.g.loaded_nvim_heredoc = true

require("nvim-heredoc").setup()
