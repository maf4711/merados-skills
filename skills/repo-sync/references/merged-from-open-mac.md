---
name: open-mac
description: Multi-Mac Arbeitsstart und -ende. Erzwingt Repo-Sync über GitHub (status → ship/sync). Trigger auf "/open-mac", "open-mac", "leave-mac". Agent: merge + CPR. LaunchAgent 2 min, kein auto-commit.
---

# open-mac

Du hilfst dem User, **mehrere Macs** über GitHub synchron zu halten.
GitHub ist die einzige Wahrheit. Agent-Default: `devsync.sh sync` (commit ohne Secrets, merge, push). LaunchAgent committet nicht.

Motor (Scripts, nicht neu erfinden):

| Script | Pfad |
|--------|------|
| devsync | `~/.claude/skills/repo-sync/devsync.sh` |
| auto-sync | `~/.claude/skills/repo-sync/auto-sync.sh` |
| setup | `~/.claude/skills/repo-sync/setup-mac.sh` |

Shell-Aliases (in Dotfiles / `~/.zshrc`):

```zsh
alias devsync='~/.claude/skills/repo-sync/devsync.sh'
alias leave-mac='devsync status && devsync ship'
alias open-mac='devsync status && devsync sync'   # sync = ship + clone
```

---

## Intent erkennen

| User sagt ungefähr | Modus |
|--------------------|--------|
| open-mac, Mac auf, ankommen, vor dem Arbeiten, Sync erzwingen | **OPEN** |
| leave-mac, zuklappen, fertig hier, Arbeit rüberschieben | **LEAVE** |
| Status, was ist unpushed, dirty?, Sync-Lage | **STATUS** |
| auto-sync, LaunchAgent, 2 min, Notification | **AGENT** |
| neuer Mac, setup, Skills installieren | **INSTALL** |

Unklar → **STATUS**, dann fragen.

---

## OPEN (Repo-Sync erzwingen)

Immer in dieser Reihenfolge ausführen und dem User die Ausgabe zeigen:

```bash
~/.claude/skills/repo-sync/devsync.sh status
```

Dirty oder divergiert: nicht fragen. `devsync.sh sync` (= ship: commit ohne Secrets, merge origin, push, Suite-Release, clone).

```bash
~/.claude/skills/repo-sync/devsync.sh sync
```

Kurzform, wenn User explizit „einfach open-mac / nur sync“ und Status schon sauber:

```bash
~/.claude/skills/repo-sync/devsync.sh status && ~/.claude/skills/repo-sync/devsync.sh sync
```

---

## LEAVE (vor dem Zuklappen)

```bash
~/.claude/skills/repo-sync/devsync.sh status
```

```bash
~/.claude/skills/repo-sync/devsync.sh ship
```

Am Ende klar sagen: **Was nicht auf GitHub liegt, existiert auf dem anderen Mac nicht.**

---

## STATUS

```bash
~/.claude/skills/repo-sync/devsync.sh status
```

Optional Agent:

```bash
launchctl print "gui/$(id -u)/com.merados.devsync" 2>/dev/null | head -25
tail -20 ~/.cache/devsync/auto-sync.log 2>/dev/null
```

Übersetze für den User: dirty / unpushed / archiviert / divergiert / Agent an/aus.

---

## AGENT (30-Min Auto-Sync + Notification)

Erwartung:

- alle **2 min**: `push` dann `pull` (Merge)
- **Notification** nur bei dirty/unpushed (Sound Glass)
- **kein** auto-commit, **kein** periodisches clone

Prüfen / steuern:

```bash
# Sofort + Notification erzwingen
~/.claude/skills/repo-sync/auto-sync.sh --now

# Status
launchctl print "gui/$(id -u)/com.merados.devsync" | head -25

# Log
tail -50 ~/.cache/devsync/auto-sync.log

# Aus
launchctl bootout "gui/$(id -u)/com.merados.devsync"

# An (Plist muss existieren)
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.merados.devsync.plist
```

Fehlt der Agent → **INSTALL** Schritt 6 bzw. `setup-mac.sh` vorschlagen.

---

## INSTALL (neuer Mac / reparieren)

```bash
# Dry-run
bash ~/Developer/merados-skills/skills/repo-sync/setup-mac.sh --check

# Einrichten: Skills verlinken, gitignore_global, Repos clone, LaunchAgent
bash ~/Developer/merados-skills/skills/repo-sync/setup-mac.sh
```

Voraussetzungen: `git`, `gh auth login` (SSH), SSH-Key bei GitHub.

Danach Shell-Aliases prüfen (`open-mac` / `leave-mac` / `devsync` in `~/.zshrc` oder Dotfiles pull).

---

## Harte Regeln

1. LaunchAgent: kein Commit. Agent bei OPEN/LEAVE/ship: `devsync.sh ship`.
2. **Nie** force-push. Merge, nicht rebase, nicht ff-only.
3. Divergenz mergen (`--no-edit`). Konflikt melden, nicht force.
4. Secrets / `.env` nie committen „für Sync“.
5. Archivierte Repos mit unpushed Commits sind Normalzustand (❄), kein Alarm.
6. iCloud/Dropbox auf `~/Developer` ablehnen — Ursache von Massenproblemen.

---

## Output-Format (kurz)

```
══ open-mac ════════════════════════════════
Modus:    OPEN | LEAVE | STATUS | AGENT | INSTALL
Dirty:    N  (liste)
Unpushed: N  (liste)
Sync:     push ✓/✗  pull ✓/✗  clone +N
Agent:    an|aus  (nächster Lauf / Log)
Aktion:   was der User als Nächstes tun sollte
════════════════════════════════════════════
```

---

## Abgrenzung

- Tiefes Setup / Multi-Mac-Doku der Scripts → Skill **repo-sync**
- Desktop-Tuning, Brew, Claude Settings → **merados-desktop**
- Dieser Skill = **Lifecycle** (ankommen, gehen, Lage, Agent)
