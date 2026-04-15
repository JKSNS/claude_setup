# claude_setup

Claude Code in a Docker container. Keeps it off your daily driver and inside a reproducible environment you can snapshot and restore.

## Statusline not showing? Run this:

```bash
git clone git@github.com:JKSNS/claude_setup.git /tmp/claude_setup 2>/dev/null || \
  (cd /tmp/claude_setup && git pull)
bash /tmp/claude_setup/install.sh --check   # diagnose first
bash /tmp/claude_setup/install.sh           # then fix
```

That is usually it. Statusline script changes go live on the next render. Hook script changes go live on the next invocation. Settings.json edits are picked up by the watcher when the file existed at session start. The only case that needs a manual reload is if `~/.claude/settings.json` did not exist before Claude Code started and `install.sh` had to create it from scratch; in that situation, open `/hooks` once or restart.

The merge preserves your existing settings (env, permissions, model, mcpServers) but force-overwrites `statusLine`, `hooks`, and `effortLevel` because those reference our installed scripts. Without the force-overwrite, a pre-existing settings.json with a stale `statusLine` keeps the stale value and our scripts get installed but never used. That was the silent-failure mode.

If you are an AI agent applying this repo for a user, read `AGENTS.md` first.

## Setup

### 1. Container

```bash
docker run -it --name claude_code ubuntu:latest
```

If you need localhost access for web development:

```bash
docker run -it --name claude_code \
  -p 3000:3000 -p 5000:5000 -p 8080:8080 \
  ubuntu:latest
```

To persist data across container rebuilds, mount a volume:

```bash
docker run -it --name claude_code \
  -v claude_home:/home/claude \
  ubuntu:latest
```

### 2. Install dependencies

```bash
apt-get update && apt-get install -y \
  git curl wget jq build-essential python3 python3-pip \
  python3-venv nodejs npm tmux openssh-client

useradd -m -s /bin/bash claude && su - claude

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
source ~/.bashrc && nvm install --lts
```

### 3. Git and GitHub

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

Generate an SSH key and add it to GitHub:

```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

Copy the output and add it at https://github.com/settings/ssh/new.

Install GitHub CLI for pull requests, issues, and repo management:

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update && apt-get install -y gh

gh auth login
```

### 4. Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude
```

Follow the OAuth flow or set `ANTHROPIC_API_KEY` in your environment. To persist the key across sessions, add it to `~/.bashrc`:

```bash
echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> ~/.bashrc
```

### 5. Apply config

One command:

```bash
git clone git@github.com:JKSNS/claude_setup.git /tmp/claude_setup
bash /tmp/claude_setup/install.sh
```

The installer drops `statusline-command.sh` and the three hooks into `~/.claude/`, merges `global/settings.json` into your existing settings (existing keys preserved), backs up anything it would overwrite as `.bak.<timestamp>`, and smoke-tests the statusline at the end.

Modes:

```bash
SETTINGS_MODE=overwrite bash /tmp/claude_setup/install.sh   # replace settings.json with the template
SETTINGS_MODE=skip bash /tmp/claude_setup/install.sh        # only touch statusline + hooks
CLAUDE_DIR=/custom/path bash /tmp/claude_setup/install.sh   # install elsewhere
```

Manual install (if you prefer):

```bash
cp /tmp/claude_setup/global/settings.json ~/.claude/settings.json
cp /tmp/claude_setup/global/statusline-command.sh ~/.claude/statusline-command.sh
mkdir -p ~/.claude/hooks
cp /tmp/claude_setup/hooks/* ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh ~/.claude/statusline-command.sh
```

### 6. Ollama (host side, optional)

[claude_preflight](https://github.com/JKSNS/claude_preflight) routes extraction and inference work to local Ollama models instead of burning Claude tokens. Install Ollama on your host machine so the container can reach it.

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama serve
ollama pull gemma4:26b
```

Preflight handles the routing configuration. This step just makes sure a model is available to route to.

### 7. Snapshot

```bash
docker commit claude_code claude_code:configured
```

### 8. Per-project optimization

Use [claude_preflight](https://github.com/JKSNS/claude_preflight) on each project to set up knowledge graph mapping, local model routing, and continuous sync.

```bash
git clone git@github.com:JKSNS/claude_preflight.git /tmp/claude_preflight
cd your-project
/tmp/claude_preflight/install.sh
```

## Working with containers

### Re-enter a stopped container

```bash
docker start claude_code
docker exec -it claude_code su - claude
```

### Run multiple containers

```bash
docker run -it --name claude_code_2 \
  -p 3001:3000 -p 5001:5000 \
  claude_code:configured
```

### Copy files in and out

```bash
docker cp ~/local/file.txt claude_code:/home/claude/file.txt
docker cp claude_code:/home/claude/output.txt ~/local/output.txt
```

## What's included

### Settings

Agent teams and tmux backend are enabled for multi-agent workflows. Credential and secret files are blocked from reads to prevent accidental exposure. Dangerous mode is enabled because the container itself is the sandbox. `effortLevel` is set to `max` for deepest reasoning on supported models.

### Statusline

Two-line, color-coded:

```
user@host:/path/to/cwd (git-branch)
Opus 4.6 | ctx: 42% (85.0k/200.0k) | $3.2100 | wall: 30m00s | api: 5m40s | +58/-12 | 5h: 67% | wk: 18% | max
```

Context % colored green / yellow / red at 50 / 80 thresholds. Same for the 5-hour rate-limit segment. Token usage, session cost, wall and API time, lines added/removed, and 5h/weekly rate-limit usage (if your plan reports it) all render only when the field is present in the hook payload, so older Claude Code versions degrade cleanly.

Implemented in Python rather than `jq`. The previous shell-only versions silently no-op'd in fresh containers because every `jq` call was wrapped in `2>/dev/null || echo ""`. Same fix applied to the two firewall hooks (`pre-bash-firewall.sh` and `protect-critical-files.sh`): they prefer `jq` if available and fall back to `python3` if not. `python3` is universally available; `jq` is not.

### Hooks

| File | Trigger | Purpose |
|---|---|---|
| `protect-critical-files.sh` | Pre Edit/Write | Blocks writes to .env, credentials, keys, SSH, OAuth, CI/CD workflows |
| `pre-bash-firewall.sh` | Pre Bash | Blocks destructive commands, credential exposure, filesystem/database destruction |
| `post-edit-quality.sh` | Post Edit/Write | Auto-format with ruff or prettier |

### Project configuration files

Claude Code reads several special files that shape how it works with your project. These are not included in this repo because they are project-specific, but knowing they exist is important for getting the most out of your setup.

**CLAUDE.md** is the primary configuration file. A global one at `~/.claude/CLAUDE.md` applies to every project and sets universal preferences like coding standards, environment defaults, and tool integrations. Each project gets its own `CLAUDE.md` at the repo root with architecture, directory structure, test commands, and project-specific conventions. Keep both under 300 lines. If Claude ignores a rule, the file is probably too long.

**AGENTS.md** is for multi-agent coordination. Platforms like Codex, Aider, and OpenClaw read this file to understand how agents should collaborate on a project. If you use multiple AI coding tools on the same repo, this is where shared conventions go.

**SECURITY.md** tells Claude about your project's security policy, supported versions, and vulnerability reporting process. Claude reads this before making changes that touch authentication, authorization, or data handling.

**.claude/settings.json** at the project level overrides global settings for that specific project. Use it for project-specific hooks, MCP servers, or permission overrides.

## Structure

```
claude_setup/
|-- install.sh                  idempotent installer (merge | overwrite | skip)
|-- global/
|   |-- settings.json           template, merged into ~/.claude/settings.json
|   +-- statusline-command.sh   python-based, no jq dependency
+-- hooks/
    |-- protect-critical-files.sh
    |-- pre-bash-firewall.sh
    +-- post-edit-quality.sh
```

## Maintenance

```bash
# Cache cleanup before snapshots
rm -rf ~/.cache/pip ~/.cache/huggingface ~/.npm /tmp/*
rm -rf ~/.claude/debug ~/.claude/telemetry ~/.claude/downloads

# Snapshot
docker commit claude_code claude_code:latest
```

See [container_health.md](./container_health.md) for troubleshooting.

## Related

- [claude_preflight](https://github.com/JKSNS/claude_preflight) - per-project optimization with persistent knowledge graph sync, local model routing, and repo cleanup
- [claude_plugins](https://github.com/JKSNS/claude_plugins) - autoresearch, project management, media generation, and custom MCP servers

## License

CC BY-NC 4.0. Free to use and fork. Credit required. No commercial use.
