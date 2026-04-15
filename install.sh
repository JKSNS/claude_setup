#!/usr/bin/env bash
# install.sh - install statusline, hooks, and settings into ~/.claude.
# Idempotent. Backs up anything it would replace with .bak.<timestamp>.
#
# Usage:
#   bash install.sh                       # full install, merge settings
#   bash install.sh --check               # diagnose existing install, no changes
#   SETTINGS_MODE=overwrite bash install.sh
#   SETTINGS_MODE=skip bash install.sh    # leave settings.json alone
#   CLAUDE_DIR=/custom/.claude bash install.sh
#
# Merge behavior:
#   - statusLine, hooks, and effortLevel are FORCE-OVERWRITTEN. They reference
#     our file paths and have no meaning without our scripts. Without this,
#     a pre-existing settings.json (e.g. one Claude Code created on first run)
#     keeps its stale statusLine and our scripts get installed but never used.
#   - All other keys (env, permissions, model, mcpServers, etc.) merge
#     non-destructively: existing keys win, new keys are added.

set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%s)"
SETTINGS_MODE="${SETTINGS_MODE:-merge}"
MODE="${1:-install}"

# --- diagnostic mode -----------------------------------------------------
if [ "$MODE" = "--check" ] || [ "$MODE" = "check" ]; then
  echo "[check] inspecting $CLAUDE_DIR"
  fail=0
  for f in statusline-command.sh hooks/protect-critical-files.sh \
           hooks/pre-bash-firewall.sh hooks/post-edit-quality.sh; do
    if [ -x "$CLAUDE_DIR/$f" ]; then
      echo "  ok    $f"
    else
      echo "  MISS  $f"; fail=1
    fi
  done
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if python3 -c "import json; json.load(open('$CLAUDE_DIR/settings.json'))" 2>/dev/null; then
      echo "  ok    settings.json (parses)"
      python3 - "$CLAUDE_DIR/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sl = d.get("statusLine", {})
sl_cmd = sl.get("command", "")
print(f"  {'ok   ' if 'statusline-command.sh' in sl_cmd else 'WRONG'} statusLine.command -> {sl_cmd or '(unset)'}")
hk = d.get("hooks", {})
expected = {"PreToolUse", "PostToolUse"}
have = set(hk.keys())
missing = expected - have
print(f"  {'ok   ' if not missing else 'WRONG'} hooks events: {sorted(have)} (missing: {sorted(missing)})")
print(f"  info  effortLevel: {d.get('effortLevel', '(unset)')}")
PY
    else
      echo "  FAIL  settings.json does not parse"; fail=1
    fi
  else
    echo "  MISS  settings.json"; fail=1
  fi
  command -v python3 >/dev/null && echo "  ok    python3: $(python3 --version)" || { echo "  MISS  python3"; fail=1; }
  if [ "$fail" -eq 0 ]; then
    echo "[check] all required pieces present. If statusline still does not show, restart Claude Code or open /hooks once."
  else
    echo "[check] something is broken. Run: bash install.sh"
  fi
  exit "$fail"
fi

# --- install mode --------------------------------------------------------
echo "[install] target: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/hooks"

backup_if_exists() {
  local f="$1"
  if [ -e "$f" ]; then
    cp "$f" "$f.bak.$TS"
    echo "[install] backed up $f -> $f.bak.$TS"
  fi
}

# 1. statusline
backup_if_exists "$CLAUDE_DIR/statusline-command.sh"
cp "$HERE/global/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
echo "[install] statusline-command.sh installed"

# 2. hooks
for h in "$HERE/hooks/"*.sh; do
  name="$(basename "$h")"
  backup_if_exists "$CLAUDE_DIR/hooks/$name"
  cp "$h" "$CLAUDE_DIR/hooks/$name"
  chmod +x "$CLAUDE_DIR/hooks/$name"
  echo "[install] hook installed: $name"
done

# 3. settings.json
SETTINGS="$CLAUDE_DIR/settings.json"
case "$SETTINGS_MODE" in
  skip)
    echo "[install] SETTINGS_MODE=skip, leaving $SETTINGS untouched"
    ;;
  merge)
    if [ -f "$SETTINGS" ]; then
      backup_if_exists "$SETTINGS"
      python3 - "$SETTINGS" "$HERE/global/settings.json" <<'PY'
import json, sys
target_path, source_path = sys.argv[1], sys.argv[2]
with open(target_path) as f: target = json.load(f)
with open(source_path) as f: source = json.load(f)

# Force-overwrite keys that reference our installed scripts. Without this,
# a pre-existing settings.json keeps its stale statusLine/hooks and our
# scripts get installed but never used.
FORCE_OVERWRITE = {"statusLine", "hooks", "effortLevel"}

def merge(dst, src, path=()):
    for k, v in src.items():
        full = path + (k,)
        # Top-level force-overwrite
        if not path and k in FORCE_OVERWRITE:
            dst[k] = v
            print(f"[install] force-overwrote: {k}")
            continue
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            merge(dst[k], v, full)
        elif isinstance(v, list) and isinstance(dst.get(k), list):
            for item in v:
                if item not in dst[k]:
                    dst[k].append(item)
        else:
            dst.setdefault(k, v)

merge(target, source)
with open(target_path, "w") as f: json.dump(target, f, indent=2)
print(f"[install] merged settings into {target_path}")
PY
    else
      cp "$HERE/global/settings.json" "$SETTINGS"
      echo "[install] new settings.json created at $SETTINGS"
    fi
    ;;
  overwrite)
    backup_if_exists "$SETTINGS"
    cp "$HERE/global/settings.json" "$SETTINGS"
    echo "[install] settings.json overwritten with template"
    ;;
  *)
    echo "[install] unknown SETTINGS_MODE=$SETTINGS_MODE (use merge|overwrite|skip)"; exit 1
    ;;
esac

# 4. validate
python3 -c "import json; json.load(open('$SETTINGS')); print('[install] settings.json valid JSON')" || {
  echo "[install] WARNING: settings.json failed to parse"; exit 1; }

# 5. dependency check
echo "[install] checking dependencies"
command -v python3 >/dev/null || { echo "  MISSING: python3 (required by statusline + hooks)"; exit 1; }
echo "  python3: $(python3 --version)"
if command -v jq >/dev/null; then
  echo "  jq: $(jq --version) (optional, scripts also work without it)"
else
  echo "  jq: not installed (optional, scripts fall back to python3)"
fi

# 6. smoke test the statusline
echo "[install] smoke test"
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"test"},"context_window":{"used_percentage":42,"tokens_used":85000,"tokens_limit":200000},"cost":{"total_cost_usd":0.42,"total_duration_ms":120000}}' \
  | bash "$CLAUDE_DIR/statusline-command.sh"
echo
echo "[install] done"
echo
echo "===================================================================="
echo "  Reload semantics:"
echo "    - Statusline script content: live, no reload needed (Claude Code"
echo "      re-executes the command on each render)."
echo "    - Hook script content: live, no reload needed."
echo "    - settings.json edits when the file existed at session start:"
echo "      picked up by the watcher automatically."
echo "    - settings.json CREATED from nothing during an active session:"
echo "      the watcher may not see it. Open /hooks once or restart."
echo "  In most cases there is nothing to do; just keep working."
echo "===================================================================="
