# Claude Code Container Save & Shrink

Flattens Docker layers, reclaims dead space, and moves persistent data to named volumes so containers stay small permanently.

**Targets:** `claude_code_2` (`6843a8a938e7`) and `claude_code` (`722f10d02d6b`)

**Shell:** Git Bash on Windows (except the vhdx shrink step which requires admin PowerShell)

---

## 1. Snapshot (Rollback Safety Net)

```bash
docker commit claude_code_2 claude_code_2:snapshot_$(date +%Y%m%d)
docker commit claude_code claude_code:snapshot_$(date +%Y%m%d)
```

These preserve full metadata (ENV, CMD, ENTRYPOINT). Use these to roll back if anything breaks.

## 2. Save Original Configs

```bash
docker inspect claude_code_2 --format '{{json .Config}}' > claude_code_2_config.json
docker inspect claude_code --format '{{json .Config}}' > claude_code_config.json
```

Reference these if you need to reconstruct run flags later. `docker export/import` strips this metadata.

## 3. Stop + Flatten

```bash
docker stop claude_code_2 claude_code
docker export claude_code_2 | docker import - claude_code_2:clean
docker export claude_code | docker import - claude_code:clean
```

Flattening collapses all layers into one and purges deleted files that were still consuming space in intermediate layers.

## 4. Create Named Volumes

```bash
docker volume create cc2_home
docker volume create cc2_projects
docker volume create cc_home
docker volume create cc_projects
```

Named volumes start at ~0 bytes and grow on demand. Data lives outside the container layer, so future snapshots/exports stay small.

## 5. Seed Volumes via Temp Backup

```bash
mkdir -p /tmp/cc2_backup /tmp/cc_backup
docker cp claude_code_2:/home/claude/. /tmp/cc2_backup/
docker cp claude_code:/home/claude/. /tmp/cc_backup/
```

## 6. Launch Clean Containers with Volumes

```bash
docker run -dit --name claude_code_2_v2 \
  -v cc2_home:/home/claude \
  -v cc2_projects:/projects \
  claude_code_2:clean /bin/bash

docker run -dit --name claude_code_v2 \
  -v cc_home:/home/claude \
  -v cc_projects:/projects \
  claude_code:clean /bin/bash
```

## 7. Copy Data into New Containers

```bash
docker cp /tmp/cc2_backup/. claude_code_2_v2:/home/claude/
docker cp /tmp/cc_backup/. claude_code_v2:/home/claude/
```

## 8. Verify

```bash
docker exec claude_code_2_v2 ls -la /home/claude
docker exec claude_code_v2 ls -la /home/claude
```

Confirm your files are present before nuking anything.

## 9. Nuke Old Containers + Cleanup

```bash
docker rm claude_code_2 claude_code
docker image prune -f
rm -rf /tmp/cc2_backup /tmp/cc_backup
```

## 10. Check Sizes

```bash
docker system df -v
```

## 11. Shrink the WSL2 vhdx (Admin PowerShell)

The vhdx virtual disk grows when data is written but never auto-shrinks on delete. This reclaims that dead space.

```powershell
Get-ChildItem -Recurse "$env:LOCALAPPDATA\Docker" -Filter "*.vhdx" | Select FullName
wsl --shutdown
diskpart
```

Inside diskpart:

```
select vdisk file="<PATH_FROM_GET-CHILDITEM>"
compact vdisk
exit
```

---

## Browser-Test Snapshot Copy on Windows

When a Claude-managed project is already working inside a long-lived container, a common next step is to create a second copy with a published port so you can test the app from the Windows host browser without disturbing the original container.

Example use case:

- original container: `claude_code`
- snapshot image: `prism-app:latest`
- browser-capable copy: `claude_code_port`

One-liners:

```bash
docker commit claude_code prism-app:latest
MSYS_NO_PATHCONV=1 docker run -d --name claude_code_port -p 5000:5000 --entrypoint tail prism-app:latest -f /dev/null
docker exec -it claude_code_port bash
```

Inside the copied container, start the app manually when you are ready:

```bash
cd /home/perplexity_prism/platform
npm run start
```

If that app binds `0.0.0.0:5000`, the Windows host browser can use:

```text
http://localhost:5000
```

### Why `tail -f /dev/null`

This keeps the copied container alive as an idle sandbox. It is the safest default when you want a comprehensive snapshot that you can later `docker exec -it` into, rather than a container that immediately tries to run an app on startup.

### Git Bash / MSYS Path Conversion Trap

In Git Bash on Windows, `/dev/null` can be rewritten before Docker receives it. The symptom is a broken container command like:

```text
"tail -f nul"
```

Then the container exits immediately and may enter a restart loop if a restart policy is set.

Check:

```bash
docker ps -a
```

Fix by recreating it with path conversion disabled:

```bash
docker rm -f claude_code_port
MSYS_NO_PATHCONV=1 docker run -d --name claude_code_port -p 5000:5000 --entrypoint tail prism-app:latest -f /dev/null
```

Verify:

```bash
docker ps --filter "name=claude_code_port"
docker exec -it claude_code_port bash
docker inspect claude_code_port --format '{{json .HostConfig.PortBindings}}'
```

## Notes

- `docker commit` (step 1) preserves image metadata. `docker export/import` (step 3) does not. That's why you do both.
- If the new containers are broken, roll back: `docker run -dit --name claude_code_2 claude_code_2:snapshot_YYYYMMDD /bin/bash`
- Volumes have no size cap by default. Use `docker system df -v` periodically to monitor growth.
- To add more volume mounts later (e.g., Ollama cache, Wraith results), stop the container, `docker rm` it, and re-run with additional `-v` flags. Volume data persists across container deletion.
