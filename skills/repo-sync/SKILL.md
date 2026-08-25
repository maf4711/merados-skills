---
name: repo-sync
description: Use when syncing ~/Developer across Macs via MacCluster Thunderbolt then GitHub, or when the user says /repo-sync, repos syncen, TB sync, thunderbolt, maccluster, inventarisieren, neueste daten, ship to github, merge and cpr, anderes macbook, leave-mac, open-mac.
---

# repo-sync

Hält `~/Developer` über mehrere Macs synchron.

**Transport-Reihenfolge (Agent-Default):** erst **MacCluster + Thunderbolt** (Inventar, dann nur neueste Dateien), danach GitHub ship. Motor TB: `maccluster`. Motor GitHub: `devsync.sh`.

```bash
~/.claude/skills/repo-sync/devsync.sh sync
# 1) maccluster tb/status + sync home --compare --preset developer
# 2) maccluster sync home --preset developer --conflict-policy newer
# 3) GitHub ship + clone
```

Nur TB: `devsync.sh tb inventory` dann `devsync.sh tb sync`.  
Nur GitHub: `devsync.sh ship`.

**REQUIRED:** `maccluster` auf PATH (`~/.local/bin/maccluster`), `~/.config/maccluster/cluster.toml`, TB-Mesh (`sudo maccluster up`), SSH-Key auf `10.42.0.x`. Siehe maccluster-status.

## Agent-Ablauf

1. **Inventarisieren** — `maccluster config validate`, `tb`, `status`, `doctor`, dann `maccluster sync home --compare --preset developer --conflict-policy newer`. Kein Write. Tabelle: only_local / only_remote / local_newer / remote_newer.
2. **Nur neueste Daten über TB** — `maccluster sync home --preset developer --conflict-policy newer`. Apple `ditto` über die Bridge, **kein Delete**. Newest-wins. Nicht WLAN, nicht 169.254-Fallback als Default.
3. **GitHub ship** — paralleles Commit (ohne Secrets) + Merge + Push + Suite-Release. **REQUIRED SUB-SKILL:** `cpr` für Vercel; TestFlight only on **mcprt**.
4. Mesh isolated / Peers DOWN: Inventar trotzdem zeigen, dann `sudo maccluster up` nennen. GitHub-Ship nicht skippen.

Nicht fragen, nicht ff-only, nicht rebase, nicht force-push.

## LaunchAgent

`auto-sync.sh`: alle **2 min** nur GitHub push+pull-merge. **Kein** auto-commit, **kein** TB-Home-Sync (dafür `maccluster service sync-install`).

## Was nie ins Git geht

- `.env`, Keys, xcarchive, `.build`, `ruvector.db`, `.claude-flow`
- Force-Push, `--no-verify`, Amend publizierter Commits

TB-Kopie **darf** `.env` und dirty Work (gleiches LAN, `maccluster` Preset developer). GitHub nicht.

## Knöpfe

```bash
export PATH="$HOME/.local/bin:$PATH"
maccluster tb && maccluster status
~/.claude/skills/repo-sync/devsync.sh tb inventory
~/.claude/skills/repo-sync/devsync.sh tb sync
~/.claude/skills/repo-sync/devsync.sh ship
```

Mesh bringen: `sudo maccluster up` (einmal, Admin).
