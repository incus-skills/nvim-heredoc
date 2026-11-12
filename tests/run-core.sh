#!/usr/bin/env bash
set -euo pipefail
nvim --headless -u NONE -c 'lua dofile("tests/lua/scanner_spec.lua")' -c 'qa!'
