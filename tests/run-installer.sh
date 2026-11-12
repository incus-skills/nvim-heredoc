#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
config="$tmp/nvim"
fake_bin="$tmp/bin"

mkdir -p -- "$fake_bin"
cat > "$fake_bin/glow" <<'GLOW'
#!/usr/bin/env bash
cat >/dev/null
GLOW
chmod +x "$fake_bin/glow"

export PATH="$fake_bin:$PATH"
export NVIM_CONFIG_DIR="$config"

bash -n "$repo_root/scripts/install.sh"
bash "$repo_root/scripts/install.sh"

for module in init.lua scanner.lua editing.lua; do
  cmp "$repo_root/lua/nvim-heredoc/$module" "$config/lua/nvim-heredoc/$module"
done

for ft in bash sh zsh; do
  test -f "$config/after/ftplugin/$ft.lua"
  grep -Fx 'require("nvim-heredoc").setup_buffer()' "$config/after/ftplugin/$ft.lua"
done

before="$(find "$config" -type f -print0 | sort -z | xargs -0 sha256sum)"
bash "$repo_root/scripts/install.sh"
after="$(find "$config" -type f -print0 | sort -z | xargs -0 sha256sum)"
test "$before" = "$after"

printf 'Provisioning installer tests: PASS\n'
