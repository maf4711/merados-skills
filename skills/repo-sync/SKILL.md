---
name: repo-sync
description: Repos zwischen mehreren Macs via GitHub synchron halten. Trigger auf "/repo-sync", "repos syncen", "sync repos", "vor dem bearbeiten syncen", "anderes macbook", "zweiter mac", "repos abgleichen", "was ist unpushed", "fehlende repos klonen". Pusht lokale Commits, holt Remote-Stand, klont fehlende Repos, meldet Konflikte BEVOR gearbeitet wird.
---

# repo-sync

Hält `~/Developer` über mehrere Macs synchron. GitHub ist die einzige Wahrheit —
nichts wird per Netzwerk-Share oder Cloud-Ordner kopiert.

Motor ist `~/.claude/skills/repo-sync/devsync.sh`. Der Skill entscheidet, *was* wann läuft,
und übersetzt das Ergebnis für den User.

## Ablauf vor dem Bearbeiten

Immer in dieser Reihenfolge — sonst überschreibst du Arbeit vom anderen Mac:

1. **Lage feststellen**
   ```bash
   ~/.claude/skills/repo-sync/devsync.sh status
   ```
   Zeigt dirty / unpushed / fehlende Repos.

2. **Uncommitted Changes klären** — NICHT automatisch committen.
   Bei dirty Repos: dem User die Diffs zeigen (`git -C <repo> status --short`)
   und fragen, ob committen, stashen oder verwerfen. Erst danach weiter.
   Begründung: uncommitted Arbeit ist der einzige Zustand, der beim Sync
   unwiederbringlich verloren gehen kann.

3. **Eigene Commits raufschieben**
   ```bash
   ~/.claude/skills/repo-sync/devsync.sh push
   ```

4. **Fremden Stand holen**
   ```bash
   ~/.claude/skills/repo-sync/devsync.sh pull
   ```
   `--ff-only`. Schlägt ein Pull fehl, ist der Branch divergiert → nicht blind
   mergen, sondern dem User Branch + beide Commit-Listen zeigen und fragen.

5. **Fehlende Repos holen** (nur wenn der User auf einem frischen Mac ist
   oder explizit danach fragt)
   ```bash
   ~/.claude/skills/repo-sync/devsync.sh clone
   ```

Kurzform, wenn alles sauber ist: `devsync.sh sync` (= push, pull, clone).

## Beim Verlassen eines Macs

Vor dem Zuklappen: Schritt 2 + 3. Was nicht auf GitHub liegt, existiert auf dem
anderen Mac nicht.

## Was NICHT gesynct wird

Ehrlich ansagen, statt Vollständigkeit zu suggerieren:

- **Repos ohne Remote** — `status` listet sie unter „kein Remote". Wenn der User
  sie syncen will: `gh repo create <name> --private --source=. --push` im Repo.
- **Gitignorierte Dateien** — `.env`, Credentials, `node_modules`, lokale DBs.
  Secrets gehören in 1Password/Keychain, nicht ins Repo. Niemals `.env` committen,
  um „Sync zu ermöglichen".
- **Uncommitted Changes** — per Definition.

## Nützliche Einzelabfragen

```bash
# Was liegt in Repo X unpushed?
git -C ~/Developer/<repo> log --branches --not --remotes --oneline

# Divergenz gegen origin prüfen
git -C ~/Developer/<repo> rev-list --left-right --count HEAD...@{u}

# Andere Owner einbeziehen
DEVSYNC_OWNERS="maf4711 MeradosUG NeuerOrg" ~/.claude/skills/repo-sync/devsync.sh status
```

## Installation auf einem neuen Mac

Der Skill ist selbst-enthaltend — `devsync.sh` liegt neben dieser Datei.

```bash
# 1. Voraussetzungen
gh auth login                       # SSH als Protokoll wählen
ssh -T git@github.com               # muss "Hi <user>!" sagen

# 2. Skill-Repo holen und verlinken
mkdir -p ~/Developer ~/.claude/skills
git clone git@github.com:maf4711/merados-skills.git ~/Developer/merados-skills
ln -sfn ~/Developer/merados-skills/skills/repo-sync ~/.claude/skills/repo-sync

# 3. Prüfen
~/.claude/skills/repo-sync/devsync.sh status
```

Symlink statt Kopie — sonst driften die Macs auseinander. Skill-Updates kommen
danach per `git -C ~/Developer/merados-skills pull`.

Alle Skills auf einmal verlinken:
```bash
for s in ~/Developer/merados-skills/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```
