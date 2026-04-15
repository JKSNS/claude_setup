# AGENTS.md

Instructions for an AI coding agent (Claude Code, Codex, Aider, or similar) asked to "fix the environment" or "set up Claude Code" using this repo. Read the user's intent first; only run the bootstrap if the user actually wants their global Claude Code config changed.

## What this repo is

A drop-in Claude Code environment: statusline, hooks, settings template, idempotent installer. Designed for fresh containers where common tools may be missing. The statusline and two of the hooks parse JSON with python3 instead of jq because jq is often absent.

Repo layout:

```
claude_setup/
  install.sh                  config installer (idempotent)
  global/
    settings.json             template, merged into ~/.claude/settings.json
    statusline-command.sh     python-based, no jq dependency
  hooks/
    protect-critical-files.sh    PreToolUse on Edit|Write
    pre-bash-firewall.sh         PreToolUse on Bash
    post-edit-quality.sh         PostToolUse on Edit|MultiEdit|Write
  README.md                   human-facing setup guide
  container_health.md         Docker volume + image management
  AGENTS.md                   this file
```

## Canonical fix sequence

If asked to apply this repo to fix or set up the user's Claude Code environment, run these in order. Stop and report if any step fails.

1. Verify the repo is already on disk. If not, clone with the user's SSH key:
   ```bash
   git clone git@github.com:JKSNS/claude_setup.git /tmp/claude_setup
   ```

2. Check runtime dependencies. Install only what is missing.
   - `python3`: required. Without it install.sh exits and the statusline cannot run.
   - `git`: required for the statusline branch suffix and almost everything else.
   - `tmux`: required if the user keeps `CLAUDE_CODE_SPAWN_BACKEND=tmux` in settings.
   - `jq`: optional, scripts fall back to python3 if absent.
   - `ruff`, `npx prettier`: optional, post-edit-quality.sh skips silently if absent.

   Detect the package manager and install the missing required ones. Examples:
   ```bash
   # Debian / Ubuntu
   apt-get update && apt-get install -y python3 git tmux

   # Fedora
   dnf install -y python3 git tmux

   # Arch
   pacman -S --noconfirm python git tmux

   # macOS
   brew install python git tmux
   ```

3. Run the installer:
   ```bash
   bash /tmp/claude_setup/install.sh
   ```
   Default mode merges into the user's existing `~/.claude/settings.json`. Most keys are preserved (env, permissions, model, mcpServers, etc.). The keys `statusLine`, `hooks`, and `effortLevel` are FORCE-OVERWRITTEN because they reference our installed scripts and have no meaning without them. This is the fix for the silent-failure mode where Claude Code's default-created settings.json had a stale statusLine pointing nowhere and the merge preserved it. Anything overwritten gets a `.bak.<timestamp>` next to it.

4. Confirm the smoke test at the end of install.sh printed colored statusline output. If it printed errors, re-read the install.sh output and address the failure (likely missing python3).

5. Reload semantics (more nuanced than "always restart"):
   - Statusline script content edits go live on the next render. No reload required.
   - Hook script content edits go live on the next invocation. No reload required.
   - `settings.json` edits when the file existed at session start are picked up by the watcher automatically.
   - `settings.json` CREATED during an active session (no prior file) may not be seen by the watcher. In that specific case, tell the user to open `/hooks` once or restart Claude Code.

   In most cases no reload is needed. Do not tell the user to restart unless you actually created their settings.json from nothing.

## Diagnosing a failed or partial install

If the user reports the statusline does not show, or hooks do not fire, or anything looks off, run the diagnostic mode FIRST before re-installing:

```bash
bash /tmp/claude_setup/install.sh --check
```

This inspects the existing install without changing anything. It reports which files are present, whether settings.json parses, whether `statusLine.command` actually points at our script, which hook events are wired, the current effortLevel, and whether python3 is available. Exit code is 0 if everything looks right, 1 otherwise.

Common findings:

- `WRONG statusLine.command -> echo old_thing` means a stale value survived a previous merge. Re-run `bash install.sh` (the new merge force-overwrites this key).
- `WRONG hooks events: ['Stop'] (missing: ['PreToolUse', 'PostToolUse'])` same as above.
- `MISS statusline-command.sh` means install.sh never ran or failed early. Re-run it and read the output.
- `ok` everything but statusline still does not show: settings watcher needs a reload. Tell the user to restart Claude Code or open `/hooks` once.

## Verification commands

After install:

```bash
# settings.json parses
python3 -c "import json; json.load(open(\"$HOME/.claude/settings.json\")); print('settings ok')"

# statusline produces output
echo '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"test"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.0,"total_duration_ms":60000}}' \
  | bash "$HOME/.claude/statusline-command.sh"

# pre-bash-firewall blocks a known-bad command
echo '{"command":"rm -rf /"}' | bash "$HOME/.claude/hooks/pre-bash-firewall.sh"
echo "exit=$?  (expect 2)"

# protect-critical-files blocks a write to .env
echo '{"file_path":"/tmp/.env"}' | bash "$HOME/.claude/hooks/protect-critical-files.sh"
echo "exit=$?  (expect 2)"
```

If exit codes are wrong or output is missing, the install was incomplete.

## Modes

`install.sh` honors three settings modes:

```bash
SETTINGS_MODE=merge bash install.sh       # default, preserves existing keys
SETTINGS_MODE=overwrite bash install.sh   # replace settings.json with template
SETTINGS_MODE=skip bash install.sh        # only install statusline + hooks
```

Override the install root for non-standard layouts:

```bash
CLAUDE_DIR=/custom/path bash install.sh
```

## Editing rules for any agent that touches this repo

- Do not introduce em-dashes or en-dashes anywhere. Use commas, hyphens, or periods. Same for emojis: do not add any.
- Commit author and committer must be the human owner (Jackson Stephens, JKSNS@users.noreply.github.com), not the agent. Set `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` if not already exported, or pass `-c user.name=... -c user.email=...` to git.
- Push using the user's SSH key. The remote is configured as `git@github.com:JKSNS/claude_setup.git`. Do not switch to HTTPS or attempt to use a bot account.
- Force pushes to main are allowed in this repo when the user explicitly asks for a history stomp. Do not force push without that explicit instruction. Default to fast-forward pushes.
- Keep the commit message style minimal (`init` for full history stomps, otherwise short imperative). Do not add `Co-Authored-By` lines for AI agents.
- Do not add any plugin-specific or personal config (Git author email, MCP servers, ralph/codex paths) to `global/settings.json`. That file is a public template.

## What this repo intentionally does not do

- It does not install the Claude Code CLI itself. The user installs that separately (`npm install -g @anthropic-ai/claude-code`).
- It does not configure git (user.name, user.email, SSH keys). Those are personal and live outside this repo.
- It does not install the user's plugins (ralph-loop, codex, etc.). Those are managed by Claude Code's plugin system.
- It does not snapshot or restore Docker containers. See `container_health.md` for that.
- It does not check that the active Claude Code session has reloaded hooks. The user has to restart or open `/hooks` once.

## Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `install.sh` exits with `MISSING: python3` | python3 not installed | Install via the package manager step above |
| Statusline blank in active session | Settings watcher did not reload | Restart Claude Code or open `/hooks` once |
| Hooks do not fire on Edit or Bash | Same as above | Same as above |
| `settings.json` failed to parse after install | Existing file had invalid JSON | Restore from `.bak.<timestamp>` and fix manually before rerunning |
| Statusline shows literal `\033` characters | Shell does not honor ANSI escapes | Switch to a terminal that supports ANSI (xterm, tmux, modern Windows Terminal) |
