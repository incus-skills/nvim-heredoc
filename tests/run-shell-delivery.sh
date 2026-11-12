#!/usr/bin/env bash
set -euo pipefail
bash tests/shell/test-delivery.sh
bash tests/expect-failure.sh "shell delivery negative control" \
  "NEGATIVE_CONTROL: <<- unexpectedly preserved the leading TAB" \
  bash tests/negative/shell-delivery.sh
