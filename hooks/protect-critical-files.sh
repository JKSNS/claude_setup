#!/usr/bin/env bash
# protect-critical-files.sh - Prevent writes to sensitive files.
# PreToolUse hook on Edit/Write calls.

set -euo pipefail

PROTECTED_PATTERNS=(
  # Credentials and secrets
  ".env"
  "credentials"
  "api_key"
  "api_keys"
  "secrets/"
  # SSH and crypto keys
  ".pem"
  ".key"
  "id_rsa"
  "id_ed25519"
  # Auth tokens
  "token.json"
  "client_secrets"
  "oauth"
  # CI/CD (prevent accidental pipeline changes)
  ".github/workflows"
  # Docker secrets
  "docker-compose.override"
)

INPUT=$(cat)

# Extract file_path. Prefer jq, fall back to python3 because jq is not always
# installed (silent hook no-ops in fresh containers; python3 is universally
# available).
if command -v jq >/dev/null 2>&1; then
    FILE=$(echo "$INPUT" | jq -r '.file_path // empty' 2>/dev/null || echo "")
else
    FILE=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null || echo "")
fi

[ -z "$FILE" ] && exit 0

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE" == *"$pattern"* ]]; then
    echo "BLOCKED: Write to protected file: $FILE" >&2
    exit 2
  fi
done
exit 0
