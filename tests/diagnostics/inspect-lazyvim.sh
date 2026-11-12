#!/usr/bin/env bash
set -eo pipefail

config_home="$XDG_CONFIG_HOME"
[ -n "$config_home" ] || config_home="$HOME/.config"
data_home="$XDG_DATA_HOME"
[ -n "$data_home" ] || data_home="$HOME/.local/share"
config_root="$config_home/nvim"
data_root="$data_home/nvim/lazy"

printf '%s\n' "== Runtime =="
if command -v nvim >/dev/null 2>&1; then
  nvim --version | head -n 1
else
  echo "Neovim not found"
fi

printf '\n%s\n' "== Plugin revisions =="
for plugin in LazyVim mini.pairs blink.cmp conform.nvim lazy.nvim nvim-treesitter; do
  path="$data_root/$plugin"
  if [ -d "$path" ]; then
    if git -C "$path" rev-parse --verify HEAD >/dev/null 2>&1; then
      printf '%-18s %s\n' "$plugin" "$(git -C "$path" rev-parse --short=12 HEAD)"
      printf '%-18s %s\n' "" "$(git -C "$path" describe --tags --always --dirty 2>/dev/null || true)"
    else
      printf '%-18s %s\n' "$plugin" "present; revision unavailable"
    fi
  else
    printf '%-18s %s\n' "$plugin" "not found"
  fi
done

printf '\n%s\n' "== Lazy lock entries =="
lockfile="$config_root/lazy-lock.json"
if [ -f "$lockfile" ]; then
  grep -nE '"(LazyVim|mini\.pairs|blink\.cmp|conform\.nvim|lazy\.nvim|nvim-treesitter)"' "$lockfile" || true
else
  echo "No lazy-lock.json found"
fi

printf '\n%s\n' "== Relevant local configuration =="
for relative in \
  "lua/plugins/conform.lua" \
  "lua/plugins/mini-pairs.lua" \
  "lua/plugins/blink.lua" \
  "after/ftplugin/bash.lua" \
  "after/ftplugin/sh.lua" \
  "after/ftplugin/zsh.lua"; do
  file="$config_root/$relative"
  if [ -f "$file" ]; then
    echo "--- $relative"
    grep -nE 'mini\.pairs|blink|completion|shfmt|formatters_by_ft|format_on_save|indent|tabstop|expandtab' "$file" || true
  fi
done

printf '\n%s\n' "== Candidate buffer-local controls in installed plugin source =="
for plugin in mini.pairs blink.cmp conform.nvim; do
  path="$data_root/$plugin"
  if [ -d "$path" ]; then
    echo "--- $plugin"
    grep -RInE --include='*.lua' \
      'minipairs_disable|vim\.b\.|b\.completion|completion\.enabled|formatters_by_ft|format_on_save|disable' \
      "$path/lua" 2>/dev/null | sed -n '1,80p' || true
  fi
done

printf '\n%s\n' "Inventory complete. Review output before sharing; it may include local configuration details."
