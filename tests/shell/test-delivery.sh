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

# A space-indented opener uses TAB-only structural indentation.
# <<- removes all structural TABs, so opener indentation does not leak
# into the delivered payload.
{
  printf '    cat <<-EOF\n\t\tpasted\n\tEOF\n'
} > "$tmp/space-indented.sh"
bash "$tmp/space-indented.sh" > "$tmp/space-indented-bash.out"
dash "$tmp/space-indented.sh" > "$tmp/space-indented-dash.out"
printf 'pasted\n' > "$tmp/space-indented.expected"
cmp "$tmp/space-indented.expected" "$tmp/space-indented-bash.out"
cmp "$tmp/space-indented.expected" "$tmp/space-indented-dash.out"
if command -v zsh >/dev/null 2>&1; then
  zsh "$tmp/space-indented.sh" > "$tmp/space-indented-zsh.out"
  cmp "$tmp/space-indented.expected" "$tmp/space-indented-zsh.out"
fi

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
