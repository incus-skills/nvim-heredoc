#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Literal TAB bytes before body lines and delimiter are stripped by <<-.
{
  printf 'cat <<-EOF\n\tleading-tab\n  leading-spaces\n\tEOF\n'
} > "$tmp/input.sh"

bash "$tmp/input.sh" > "$tmp/bash.out"
dash "$tmp/input.sh" > "$tmp/dash.out"
if command -v zsh >/dev/null 2>&1; then
  zsh "$tmp/input.sh" > "$tmp/zsh.out"
else
  echo "SKIP: zsh is not installed"
fi
printf 'leading-tab\n  leading-spaces\n' > "$tmp/expected"
cmp "$tmp/expected" "$tmp/bash.out"
cmp "$tmp/expected" "$tmp/dash.out"
if [ -f "$tmp/zsh.out" ]; then
  cmp "$tmp/expected" "$tmp/zsh.out"
fi

# A naturally space-indented opener remains in its surrounding code flow.
# At tabstop=2, the editor's one-TAB body/terminator prefix is visually
# aligned with the two-space opener and is stripped by <<- at runtime.
printf 'conf_print_test() {\n  cat <<-EOF\n\\talpha\n\\t  beta\n\\tEOF\n}\nconf_print_test\n' > "$tmp/nested.sh"
bash "$tmp/nested.sh" > "$tmp/nested.out"
printf 'alpha\n  beta\n' > "$tmp/nested.expected"
cmp "$tmp/nested.expected" "$tmp/nested.out"

# An empty quoted delimiter is a valid delimiter word.
printf 'cat <<-""\n\tempty-delimiter-body\n\t\n' > "$tmp/empty.sh"
bash "$tmp/empty.sh" > "$tmp/empty-bash.out"
dash "$tmp/empty.sh" > "$tmp/empty-dash.out"
printf 'empty-delimiter-body\n' > "$tmp/empty.expected"
cmp "$tmp/empty.expected" "$tmp/empty-bash.out"
cmp "$tmp/empty.expected" "$tmp/empty-dash.out"
if command -v zsh >/dev/null 2>&1; then
  zsh "$tmp/empty.sh" > "$tmp/empty-zsh.out"
  cmp "$tmp/empty.expected" "$tmp/empty-zsh.out"
fi

# Leading spaces do not make a <<- delimiter match.
{
  printf 'cat <<-EOF\npayload\n  EOF\n'
} > "$tmp/invalid.sh"
bash "$tmp/invalid.sh" >"$tmp/invalid.out" 2>"$tmp/invalid.err" || true
if ! grep -qi "here-document" "$tmp/invalid.err"; then
  echo "expected Bash to report the unmatched space-prefixed terminator" >&2
  exit 1
fi

echo "shell delivery tests: PASS (bash, dash; zsh when installed)"
