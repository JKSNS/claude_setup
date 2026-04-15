#!/usr/bin/env bash
# Claude Code statusLine
# Line 1: user@host:cwd  (git branch suffix if cwd is in a repo)
# Line 2: model | ctx X% (tok used/limit) | $cost | wall | api | +N/-N | 5h X% | wk X% | plan
#
# Reads JSON from stdin (Claude Code statusline hook contract).
# Uses python3 for JSON parsing because jq is not always installed.
# Edit this file directly to change layout. Test with:
#   echo '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"total_duration_ms":600000}}' | bash /home/claude/.claude/statusline-command.sh

input=$(cat)

# Parse with python; emit shell-quoted KEY=VAL lines for `eval`.
# Pass the JSON via env var because the heredoc takes python's stdin.
parsed=$(STATUS_INPUT="$input" python3 - <<'PY'
import json, os, shlex

def g(d, *keys, default=""):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur if cur is not None else default

try:
    d = json.loads(os.environ.get("STATUS_INPUT", "{}") or "{}")
except Exception:
    d = {}

cwd = g(d, "workspace", "current_dir") or g(d, "cwd") or ""
model = g(d, "model", "display_name") or g(d, "model", "id") or "?"
pct = g(d, "context_window", "used_percentage", default=0)
try: pct = int(float(pct))
except: pct = 0
tokens_used = g(d, "context_window", "tokens_used", default=0)
tokens_limit = g(d, "context_window", "tokens_limit", default=0)
cost = g(d, "cost", "total_cost_usd", default=0)
try: cost = float(cost)
except: cost = 0.0
wall_ms = g(d, "cost", "total_duration_ms", default=0)
api_ms = g(d, "cost", "total_api_duration_ms", default=0)
lines_add = g(d, "cost", "total_lines_added", default=0)
lines_del = g(d, "cost", "total_lines_removed", default=0)
# Usage rate limits (Pro/Max plans). Field name varies across CLI versions.
five_h_pct = (g(d, "usage_limit", "five_hour", "used_pct", default=None)
              or g(d, "rate_limit", "five_hour", "used_pct", default=None)
              or g(d, "limits", "five_hour_pct", default=None))
weekly_pct = (g(d, "usage_limit", "weekly", "used_pct", default=None)
              or g(d, "rate_limit", "weekly", "used_pct", default=None))
plan = g(d, "usage_limit", "plan") or g(d, "plan", "name") or ""

def ms_to_str(ms):
    try: ms = int(ms)
    except: return ""
    if ms <= 0: return ""
    s = ms // 1000
    if s < 60: return f"{s}s"
    m, s = divmod(s, 60)
    if m < 60: return f"{m}m{s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h{m:02d}m"

def shorten_tokens(n):
    try: n = int(n)
    except: return str(n)
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000:     return f"{n/1_000:.1f}k"
    return str(n)

tok_str = ""
if tokens_limit:
    tok_str = f"{shorten_tokens(tokens_used)}/{shorten_tokens(tokens_limit)}"

out = {
    "CWD":   cwd,
    "MODEL": model,
    "PCT":   pct,
    "TOK":   tok_str,
    "COST":  f"{cost:.4f}" if cost else "0",
    "WALL":  ms_to_str(wall_ms),
    "API":   ms_to_str(api_ms),
    "LADD":  str(lines_add or 0),
    "LDEL":  str(lines_del or 0),
    "FIVEH": "" if five_h_pct in (None, "") else f"{int(float(five_h_pct))}",
    "WEEK":  "" if weekly_pct in (None, "") else f"{int(float(weekly_pct))}",
    "PLAN":  plan or "",
}
for k, v in out.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
)
eval "$parsed"

# Git branch (best-effort, silent on failure)
branch=""
if [ -n "${CWD:-}" ]; then
    branch=$(cd "$CWD" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# ANSI colors (ANSI-C $'...' so the bytes are real escapes, not the literal four chars).
RST=$'\033[00m'; DIM=$'\033[02m'
GRN=$'\033[01;32m'; YLW=$'\033[01;33m'; RED=$'\033[01;31m'
BLU=$'\033[01;34m'; CYN=$'\033[01;36m'; MAG=$'\033[01;35m'

# Color the context %
if   [ "${PCT:-0}" -ge 80 ] 2>/dev/null; then PCT_COLOR="$RED"
elif [ "${PCT:-0}" -ge 50 ] 2>/dev/null; then PCT_COLOR="$YLW"
else                                            PCT_COLOR="$GRN"; fi

# Color 5h usage if present
fiveh_seg=""
if [ -n "${FIVEH:-}" ]; then
    if   [ "$FIVEH" -ge 80 ] 2>/dev/null; then C="$RED"
    elif [ "$FIVEH" -ge 50 ] 2>/dev/null; then C="$YLW"
    else                                        C="$GRN"; fi
    fiveh_seg=" | 5h: ${C}${FIVEH}%${RST}"
fi
week_seg=""; [ -n "${WEEK:-}" ] && week_seg=" | wk: ${WEEK}%"
plan_seg=""; [ -n "${PLAN:-}" ] && plan_seg=" | ${DIM}${PLAN}${RST}"

# Line 1
printf "${GRN}%s@%s${RST}:${BLU}%s${RST}" "$(whoami)" "$(hostname -s)" "${CWD:-?}"
[ -n "$branch" ] && printf " ${MAG}(%s)${RST}" "$branch"

# Line 2
printf "\n${CYN}%s${RST} | ctx: ${PCT_COLOR}%s%%${RST}" "${MODEL:-?}" "${PCT:-0}"
[ -n "${TOK:-}" ] && printf " ${DIM}(%s)${RST}" "$TOK"
printf " | \$%s" "${COST:-0}"
[ -n "${WALL:-}" ] && printf " | wall: %s" "$WALL"
[ -n "${API:-}" ]  && printf " | api: %s" "$API"
if [ "${LADD:-0}" != "0" ] || [ "${LDEL:-0}" != "0" ]; then
    printf " | ${GRN}+%s${RST}/${RED}-%s${RST}" "${LADD:-0}" "${LDEL:-0}"
fi
printf "%s%s%s" "$fiveh_seg" "$week_seg" "$plan_seg"
