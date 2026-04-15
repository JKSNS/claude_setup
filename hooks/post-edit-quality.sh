#!/usr/bin/env bash
set -euo pipefail

if [ -f pyproject.toml ] || [ -f setup.py ]; then
  ruff check --fix . 2>/dev/null || true
  ruff format . 2>/dev/null || true
fi

if [ -f package.json ]; then
  npx prettier -w . 2>/dev/null || true
fi

exit 0
