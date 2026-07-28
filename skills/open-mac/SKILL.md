---
name: open-mac
description: Multi-Mac Arbeitsstart und -ende. Erzwingt Repo-Sync über GitHub (status → push → pull → clone). Trigger auf "/open-mac", "open-mac", "leave-mac", "Mac aufmachen", "Mac zuklappen", "anderen Mac", "zweiter Mac", "Repos syncen", "vor dem arbeiten syncen", "Arbeit rüberschieben", "auto-sync". Nutzt devsync; commitet nie. Installation des 30-Min-LaunchAgents.
---

# open-mac

Du hilfst dem User, **mehrere Macs** über GitHub synchron zu halten.
GitHub ist die einzige Wahrheit. **Nie auto-committen.**

Motor (Scripts, nicht neu erfinden):

| Script | Pfad |
|--------|------|
| devsync | `~/.claude/skills/repo-sync/devsync.sh` |
| auto-sync | `~/.claude/skills/repo-sync/auto-sync.sh` |
| setup | `~/.claude/skills/repo-sync/setup-mac.sh` |

Shell-Aliases (in Dotfiles / `~/.zshrc`):

```zsh
alias devsync='~/.claude/skills/repo-sync/devsync.sh'
alias leave-mac='devsync status && devsync push'
alias open-mac='devsync status && devsync sync'   # sync = push + pull + clone
```

---

## Intent erkennen

| User sagt ungefähr | Modus |
|--------------------|--------|
| open-mac, Mac auf, ankommen, vor dem Arbeiten, Sync erzwingen | **OPEN** |
| leave-mac, zuklappen, fertig hier, Arbeit rüberschieben | **LEAVE** |
| Status, was ist unpushed, dirty?, Sync-Lage | **STATUS** |
| auto-sync, LaunchAgent, 30 min, Notification | **AGENT** |
| neuer Mac, setup, Skills installieren | **INSTALL** |

Unklar → **STATUS**, dann fragen.

---

## OPEN (Repo-Sync erzwingen)

Immer in dieser Reihenfolge ausführen und dem User die Ausgabe zeigen:

```bash
~/.claude/skills/repo-sync/devsync.sh status
```

**Wenn dirty Repos:**

1. Pro Repo: `git -C ~/Developer/<repo> status --short` (und bei Bedarf `diff --stat`).
2. User fragen: committen / stashen / ignorieren / verwerfen.
3. **Nicht** selbst committen, außer der User gibt Message + Freigabe.
4. Erst wenn geklärt (oder User sagt „trotzdem weiter“): weiter.

```bash
~/.claude/skills/repo-sync/devsync.sh sync
# = push → pull --ff-only → clone fehlender Remotes
```

**Nach dem Lauf melden:**

- was gepusht wurde
- was gepullt wurde / geskippt (dirty)
- Divergenzen (ff-only fail) → Branch + `git log --oneline --left-right HEAD...@{u}` zeigen, **nicht** blind mergen
- fehlende Repos die geklont wurden
- verbleibende dirty / unpushed

Kurzform, wenn User explizit „einfach open-mac / nur sync“ und Status schon sauber:

```bash
~/.claude/skills/repo-sync/devsync.sh status && ~/.claude/skills/repo-sync/devsync.sh sync
```

---

## LEAVE (vor dem Zuklappen)

```bash
~/.claude/skills/repo-sync/devsync.sh status
```

Dirty → gleiche Klärung wie OPEN (commit nur mit Freigabe).

```bash
~/.claude/skills/repo-sync/devsync.sh push
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

- alle **30 min** + Login: `push` dann `pull`
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

1. **Nie** unattended `git commit` / `git add -A && commit`.
2. **Nie** force-push, **nie** `pull` mit merge-Strategie ändern (devsync nutzt ff-only).
3. Divergierte Branches dem User vorlegen, nicht „fix“.
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
