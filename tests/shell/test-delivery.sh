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
printf 'leading-tab\n  leading-spaces\n' > "$tmp/expected"
cmp "$tmp/expected" "$tmp/bash.out"
cmp "$tmp/expected" "$tmp/dash.out"

# Leading spaces do not make a <<- delimiter match.
{
  printf 'cat <<-EOF\npayload\n  EOF\n'
} > "$tmp/invalid.sh"
if bash "$tmp/invalid.sh" >"$tmp/invalid.out" 2>"$tmp/invalid.err"; then
  echo "expected Bash to reject a space-prefixed terminator" >&2
  exit 1
fi

echo "shell delivery tests: PASS (bash, dash)"
