---
name: repo-sync
description: Use when syncing ~/Developer git repos across Macs via GitHub, or when the user says /repo-sync, repos syncen, sync repos, ship to github, merge and cpr, fehlende repos klonen, lade alle remote repos, origin fehlt, anderes macbook, zweiter mac, leave-mac, open-mac, danach repo-sync.
---

# repo-sync

Hält `~/Developer` über mehrere Macs synchron. GitHub ist die einzige Wahrheit.

Motor: `~/.claude/skills/repo-sync/devsync.sh` (nach `install.sh` auch via Skill-Suite).

**Default für den Agenten: schnellster voller Lauf** — paralleles **Commit + Merge + Push + Release** alles, was lokal liegt. Nicht fragen, nicht ff-only, nicht rebase.

```bash
~/.claude/skills/repo-sync/devsync.sh sync
# = ship (commit ohne Secrets, merge origin, push, GitHub-Remote anlegen, Suite-Release) + clone
```

Kurzform nur Lage: `devsync.sh status`. Nur GitHub-Release der Suites: nach `ship` taggt `suite_release` `MeradosUG/Skill-Suite` und `maf4711/merados-skills`, wenn CHANGELOG eine ungetaggte Version hat.

**„lade alle remote repos lokal“ / fehlende klonen:** `devsync.sh clone` — nicht `ship`. Abgleich ist die GitHub-Origin (`owner/name`), nicht der Ordnername. Liegt `~/Developer/foo` schon als anderes Origin da, landet das zweite Repo in `~/Developer/<owner>--foo`. Default-Owner: `maf4711 MeradosUG FinfuxUG`. Archivierte mit `DEVSYNC_ARCHIVED=1`.

## Agent-Ablauf (OPEN / LEAVE / „alles rauf“)

1. `devsync.sh status` — einmal Lage zeigen.
2. Sofort `devsync.sh sync` (oder `ship` ohne Clone). **Nicht** auf User-Freigabe warten.
3. Divergenz: **mergen** (`git merge --no-edit origin/<branch>`). Kein Rebase, kein ff-only, kein Force-Push.
4. Repos ohne Remote: privates GitHub-Repo unter `maf4711/<name>` anlegen und pushen.
5. Skill-Suite / merados-skills: nach Push GitHub Release aus CHANGELOG.
6. App-CPR (Vercel; TestFlight only on **mcprt**) nur wenn das Repo das braucht — **REQUIRED SUB-SKILL:** `cpr`.

Parallel: `DEVSYNC_JOBS` (Default = CPU, max 16). SSH BatchMode, `protocol.version=2`, kein Credential-Hang.

## LaunchAgent (kein unattended Commit)

`auto-sync.sh` / `com.merados.devsync`: alle **2 min** `push` dann `pull` (Merge), danach **Node-Push**. **Kein** auto-commit, kein clone. Log: `~/.cache/devsync/auto-sync.log`.

**Node-Push:** die mos-Nodes haben keinen GitHub-Lesezugriff (`jmerados1..4` sind nicht auf `MeradosUG/agent-swarm` berechtigt), deshalb verteilt dieser Mac per SSH: fuer jedes Repo unter `~/Developer` auf dem Node wird der gleichnamige lokale Branch fast-forward gepusht. Kein `--force`; `receive.denyCurrentBranch=updateInstead` wird dabei gesetzt und aktualisiert nur saubere Worktrees. Node-Liste ueber `DEVSYNC_NODES` (Default `mos1 mos2 mos3 mos4`).

```bash
~/.claude/skills/repo-sync/auto-sync.sh --now
launchctl print "gui/$(id -u)/com.merados.devsync" | head -20
```

## Was nie ins Git geht

- `.env`, `*.pem` / `*.p8` / `*.key`, `AuthKey_*.p8`, `credentials.json`, `secrets.json`
- Build-Schrott: `*.xcarchive`, `.build/`, `DerivedData`, `ruvector.db`, `.claude-flow/`
- gitignorierte Artefakte (`node_modules`, lokale DBs)
- Force-Push auf main, `--no-verify`, Amend publizierter Commits
- Fremde Klone ohne Remote und ohne eigenen Commit — kein `gh repo create`

LaunchAgent committet nicht. Der Agent beim User-Befehl **ship/sync/cpr** schon — außer Secrets.

## Nützliche Knöpfe

```bash
~/.claude/skills/repo-sync/devsync.sh status
~/.claude/skills/repo-sync/devsync.sh ship     # commit+merge+push+release
~/.claude/skills/repo-sync/devsync.sh cpr      # Alias
DEVSYNC_JOBS=8 ~/.claude/skills/repo-sync/devsync.sh clone
DEVSYNC_ARCHIVED=1 ~/.claude/skills/repo-sync/devsync.sh clone   # inkl. archivierte
DEVSYNC_OWNERS="maf4711 MeradosUG FinfuxUG" ~/.claude/skills/repo-sync/devsync.sh sync
```

## Installation

`setup-mac.sh` — Voraussetzungen, globale gitignore, Skills verlinken, Repos klonen, LaunchAgent. Idempotent.

```bash
gh auth login    # SSH
git clone git@github.com:maf4711/merados-skills.git ~/Developer/merados-skills
bash ~/Developer/merados-skills/skills/repo-sync/setup-mac.sh
# oder Skill-Suite:
bash ~/Developer/Skill-Suite/install.sh
```

Skills **verlinken**, nicht kopieren. Open-mac / leave-mac: dieser Skill (Lifecycle in `references/merged-from-open-mac.md`).
