#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'cat <<-EOF\n\tpayload\n\tEOF\n' > "$tmp/input.sh"
bash "$tmp/input.sh" > "$tmp/actual"
# This is the forbidden, unstripped payload. A correct <<- execution must
# differ from it because the leading TAB is removed before delivery.
printf '\tpayload\n' > "$tmp/forbidden"
echo "NEGATIVE_CONTROL: <<- unexpectedly preserved the leading TAB"
cmp -s "$tmp/actual" "$tmp/forbidden"
