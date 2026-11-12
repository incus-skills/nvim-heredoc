#!/usr/bin/env bash
set -euo pipefail

command -v shfmt >/dev/null 2>&1 || {
  echo "shfmt is required for formatter tests" >&2
  exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for dialect in bash posix; do
  fixture="$tmp/$dialect.sh"
  before="$tmp/$dialect.before"
  after="$tmp/$dialect.after"

  cat > "$fixture" <<'SCRIPT'
if true; then
	cat <<-EOF
	  payload with two leading spaces
		leading tab is stripped by the shell
	EOF
fi
SCRIPT

  case "$dialect" in
    bash)
      bash "$fixture" > "$before"
      shfmt -ln bash -i 0 -p -w "$fixture"
      bash "$fixture" > "$after"
      ;;
    posix)
      dash "$fixture" > "$before"
      shfmt -ln posix -i 0 -p -w "$fixture"
      dash "$fixture" > "$after"
      ;;
  esac

  if ! cmp -s "$before" "$after"; then
    echo "shfmt changed the delivered heredoc payload for $dialect" >&2
    diff -u "$before" "$after" || true
    exit 1
  fi
done

echo "formatter tests: PASS (Bash and POSIX sh payload bytes preserved)"
