#!/usr/bin/env bash
# pre-bash-firewall.sh - Block destructive shell commands.
# PreToolUse hook on Bash calls.
#
# Set PREFLIGHT_UNSAFE=1 in your environment to bypass for CTF/security research.

set -euo pipefail

# Bypass mode for CTF challenges and security research
if [ "${PREFLIGHT_UNSAFE:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

# Extract command field. Prefer jq, fall back to python3 because jq is not
# always installed (this was the root cause of silent hook no-ops in fresh
# containers; python3 is universally available).
if command -v jq >/dev/null 2>&1; then
    CMD=$(echo "$INPUT" | jq -r '.command // empty' 2>/dev/null || echo "")
else
    CMD=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))" 2>/dev/null || echo "")
fi

[ -z "$CMD" ] && exit 0

BLOCKED_PATTERNS=(
  # Filesystem destruction
  "rm -rf /"
  "rm -rf ~"
  "rm -rf \."
  "rm -rf \*"
  # Git destruction
  "git reset --hard"
  "git push.*--force"
  "git push.*-f"
  "git clean -fd"
  "git checkout -- \."
  "git stash drop"
  # Database destruction
  "DROP TABLE"
  "DROP DATABASE"
  "TRUNCATE TABLE"
  "DELETE FROM.*WHERE 1"
  # System destruction
  "mkfs\."
  "dd if=.*of=/dev/"
  ":(){:|:&};:"
  # Credential exposure
  "curl.*ANTHROPIC_API_KEY"
  "echo.*API_KEY"
  "cat.*\.env"
  "printenv.*KEY"
  "printenv.*SECRET"
  "printenv.*TOKEN"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qiE "$pattern"; then
    echo "BLOCKED: Dangerous command detected (pattern: $pattern)" >&2
    exit 2
  fi
done
exit 0
