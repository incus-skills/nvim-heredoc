#!/usr/bin/env bash
set -euo pipefail

label="$1"
marker="$2"
shift 2
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if "$@" >"$tmp" 2>&1; then
  cat "$tmp" >&2
  echo "FAIL: $label unexpectedly succeeded; the forbidden behaviour may have appeared" >&2
  exit 1
fi

if ! grep -Fq "$marker" "$tmp"; then
  cat "$tmp" >&2
  echo "FAIL: $label failed for an unexpected reason (missing marker: $marker)" >&2
  exit 1
fi

echo "PASS: $label rejected the expected forbidden behaviour"
