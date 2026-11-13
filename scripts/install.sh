#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
NVIM_CONFIG_DIR="${NVIM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}"
MODULE_SOURCE="$SCRIPT_DIR/lua/nvim-heredoc"
MODULE_DEST="$NVIM_CONFIG_DIR/lua/nvim-heredoc"
FTPLUGIN_DEST="$NVIM_CONFIG_DIR/after/ftplugin"
for source in init.lua scanner.lua editing.lua; do
  if [[ ! -f "$MODULE_SOURCE/$source" ]]; then
    printf 'Missing implementation source: %s\n' "$MODULE_SOURCE/$source" >&2
    exit 1
  fi
done
command -v glow >/dev/null 2>&1 || {
  printf 'glow is required by the provisioning report convention\n' >&2
  exit 2
}
write_file() {
  local destination=$1
  mkdir -p -- "$(dirname -- "$destination")"
  tee "$destination" >/dev/null
}
conf_print_nvim_heredoc_ftplugin() {
  cat <<'LUA'
-- The opener is space-indented; the plugin inserts structural TABs explicitly.
-- <<- strips literal leading TAB bytes from body and closing-delimiter lines.
vim.opt_local.expandtab = true
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = 0
vim.opt_local.shiftwidth = 2

require("nvim-heredoc").setup_buffer()
LUA
}
mkdir -p -- "$MODULE_DEST" "$FTPLUGIN_DEST"
for source in init.lua scanner.lua editing.lua; do
  install -m 0644 -- "$MODULE_SOURCE/$source" "$MODULE_DEST/$source"
done
for filetype in bash sh zsh; do
  conf_print_nvim_heredoc_ftplugin | write_file "$FTPLUGIN_DEST/$filetype.lua"
done
glow - <<REPORT
## nvim-heredoc provisioned

- Configuration: $NVIM_CONFIG_DIR
- Lua modules: lua/nvim-heredoc/
- Filetype entrypoints: after/ftplugin/{bash,sh,zsh}.lua
- Indentation: expandtab=true, tabstop=2, softtabstop=0, shiftwidth=2
- Write behaviour: replace the three owned ftplugins and implementation modules
- Runtime plugin-manager entrypoint: not required
REPORT
