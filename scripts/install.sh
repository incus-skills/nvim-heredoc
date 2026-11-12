#!/usr/bin/env bash
# Provision nvim-heredoc into an existing Neovim configuration.
# Usage: ./scripts/install.sh
# Override the destination with NVIM_CONFIG_DIR=/path/to/nvim.

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
require("nvim-heredoc").setup_buffer()
LUA
}

mkdir -p -- "$MODULE_DEST" "$FTPLUGIN_DEST"

# The repository Lua modules remain the canonical implementation source.
for source in init.lua scanner.lua editing.lua; do
  install -m 0644 -- "$MODULE_SOURCE/$source" "$MODULE_DEST/$source"
done

# These generated ftplugins replace the previous function-wrapped heredoc
# implementation. Re-running this provisioner deterministically replaces
# only the three owned ftplugin paths.
for filetype in bash sh zsh; do
  conf_print_nvim_heredoc_ftplugin | write_file "$FTPLUGIN_DEST/$filetype.lua"
done

glow - <<REPORT
## nvim-heredoc provisioned

- Configuration: `$NVIM_CONFIG_DIR`
- Lua modules: `lua/nvim-heredoc/`
- Filetype entrypoints: `after/ftplugin/{bash,sh,zsh}.lua`
- Write behaviour: replace the three owned ftplugins and implementation modules
- Runtime plugin-manager entrypoint: not required
REPORT
