#!/usr/bin/env bash
set -euo pipefail
command -v shfmt >/dev/null 2>&1 || {
  echo "shfmt is required for formatter negative control" >&2
  exit 2
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fixture.sh" <<'SCRIPT'
if true; then
	cat <<-EOF
	  payload with leading spaces
	EOF
fi
SCRIPT
bash "$tmp/fixture.sh" > "$tmp/before"
shfmt -i 0 -p -w "$tmp/fixture.sh"
bash "$tmp/fixture.sh" > "$tmp/after"

if cmp -s "$tmp/before" "$tmp/after"; then
  echo "NEGATIVE_CONTROL: formatter unexpectedly changed delivered payload"
  exit 1
fi
# If the formatter ever changes delivered bytes, this control succeeds and
# the expect-failure harness will correctly fail the CI job.
