#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
config="$tmp/nvim"
fake_bin="$tmp/bin"
mkdir -p -- "$fake_bin"
export GLOW_REPORT_PATH="$tmp/glow-report.md"
cat > "$fake_bin/glow" <<'GLOW'
#!/usr/bin/env bash
cat > "$GLOW_REPORT_PATH"
GLOW
chmod +x "$fake_bin/glow"
export PATH="$fake_bin:$PATH"
export NVIM_CONFIG_DIR="$config"
bash -n "$repo_root/scripts/install.sh"
bash "$repo_root/scripts/install.sh"
grep -F -- "- Configuration: $config" "$GLOW_REPORT_PATH"
grep -F -- "- Lua modules: lua/nvim-heredoc/" "$GLOW_REPORT_PATH"
grep -F -- "- Filetype entrypoints: after/ftplugin/{bash,sh,zsh}.lua" "$GLOW_REPORT_PATH"
grep -F -- "- Indentation: expandtab=false, tabstop=2, softtabstop=0, shiftwidth=2" "$GLOW_REPORT_PATH"
grep -F -- "- Runtime plugin-manager entrypoint: not required" "$GLOW_REPORT_PATH"
for module in init.lua scanner.lua editing.lua; do
  cmp "$repo_root/lua/nvim-heredoc/$module" "$config/lua/nvim-heredoc/$module"
done
for ft in bash sh zsh; do
  test -f "$config/after/ftplugin/$ft.lua"
  grep -Fx 'vim.opt_local.expandtab = false' "$config/after/ftplugin/$ft.lua"
  grep -Fx 'vim.opt_local.tabstop = 2' "$config/after/ftplugin/$ft.lua"
  grep -Fx 'vim.opt_local.softtabstop = 0' "$config/after/ftplugin/$ft.lua"
  grep -Fx 'vim.opt_local.shiftwidth = 2' "$config/after/ftplugin/$ft.lua"
  grep -Fx 'require("nvim-heredoc").setup_buffer()' "$config/after/ftplugin/$ft.lua"
done
before="$(find "$config" -type f -print0 | sort -z | xargs -0 sha256sum)"
bash "$repo_root/scripts/install.sh"
after="$(find "$config" -type f -print0 | sort -z | xargs -0 sha256sum)"
test "$before" = "$after"
printf 'Provisioning installer tests: PASS\n'
