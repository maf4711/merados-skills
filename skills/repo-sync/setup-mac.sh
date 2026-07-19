#!/usr/bin/env bash
# setup-mac – einen zweiten Mac auf denselben Stand bringen.
#
#   Aus dem Netz (nichts vorinstalliert ausser git):
#     curl -fsSL https://raw.githubusercontent.com/maf4711/merados-skills/main/skills/repo-sync/setup-mac.sh | bash
#
#   Lokal, wenn das Repo schon da ist:
#     bash setup-mac.sh          # einrichten
#     bash setup-mac.sh --check  # nur zeigen, was passieren würde
#
# Idempotent: mehrfaches Ausführen ist gefahrlos.

set -uo pipefail

DEV="${DEVSYNC_ROOT:-$HOME/Developer}"
SKILLS_REPO="https://github.com/maf4711/merados-skills.git"
SKILLS_DIR="$DEV/merados-skills"
CHECK_ONLY=0

# Per "curl | bash" gibt es kein Skript-Verzeichnis – BASH_SOURCE zeigt dann
# auf stdin. In dem Fall wird das Repo unten geklont und HERE nachgezogen.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  HERE=""
fi

[ "${1:-}" = "--check" ] && CHECK_ONLY=1

ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
err()  { printf '\033[31m  ✗ %s\033[0m\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
do_it() { [ "$CHECK_ONLY" = 1 ] && { warn "würde tun: $*"; return 1; }; return 0; }

# --------------------------------------------------------------------------- #
step "1/5  Voraussetzungen"
# git genügt für Schritte 1–4. gh und ein SSH-Key braucht erst Schritt 5,
# weil die eigentlichen Projekt-Repos privat sind. Darum hier nur warnen,
# nicht abbrechen: Skills einrichten geht auch ohne Anmeldung.

command -v git >/dev/null 2>&1 && ok "git vorhanden" || {
  err "git fehlt – Xcode Command Line Tools installieren: xcode-select --install"; exit 1; }

CAN_CLONE_REPOS=1
if command -v gh >/dev/null 2>&1; then
  ok "gh vorhanden"
else
  warn "gh fehlt – brew install gh   (nur für Schritt 5 nötig)"
  CAN_CLONE_REPOS=0
fi

if [ "$CAN_CLONE_REPOS" = 1 ]; then
  if gh auth status >/dev/null 2>&1; then
    ok "gh angemeldet als $(gh api user --jq .login 2>/dev/null)"
  else
    warn "gh nicht angemeldet – später: gh auth login   (SSH als Protokoll)"
    CAN_CLONE_REPOS=0
  fi
fi

# ssh -T beendet sich immer mit Status 1 – unter pipefail würde das die
# ganze Pipe fehlschlagen lassen. Darum Ausgabe erst einfangen, dann prüfen.
ssh_out=$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)
if grep -q "successfully authenticated" <<<"$ssh_out"; then
  ok "SSH-Key funktioniert"
else
  warn "SSH zu GitHub schlägt fehl – private Repos bleiben aus."
  echo "     Key erzeugen:  ssh-keygen -t ed25519"
  echo "     Hinterlegen:   gh ssh-key add ~/.ssh/id_ed25519.pub"
  CAN_CLONE_REPOS=0
fi

# --------------------------------------------------------------------------- #
step "2/5  Skill-Repo"
# Muss vor der .gitignore laufen: per "curl | bash" liegt noch nichts lokal,
# HERE wird erst hier gesetzt.

if [ -d "$SKILLS_DIR/.git" ]; then
  ok "merados-skills vorhanden"
  do_it "pull" && git -C "$SKILLS_DIR" pull --ff-only -q 2>/dev/null
else
  if do_it "merados-skills klonen"; then
    mkdir -p "$DEV"
    git clone -q "$SKILLS_REPO" "$SKILLS_DIR" && ok "geklont" || { err "Clone fehlgeschlagen"; exit 1; }
  fi
fi
[ -z "$HERE" ] && HERE="$SKILLS_DIR/skills/repo-sync"

# --------------------------------------------------------------------------- #
step "3/5  Globale .gitignore"
# Verhindert, dass Cloud-Sync-Artefakte (.nosync) und .DS_Store je wieder
# in Repos landen – die Ursache der Massenlöschungen auf dem ersten Mac.

if [ -f "$HERE/gitignore_global" ]; then
  if do_it "gitignore_global installieren"; then
    cp "$HERE/gitignore_global" "$HOME/.gitignore_global"
    git config --global core.excludesfile "$HOME/.gitignore_global"
    ok "~/.gitignore_global gesetzt"
  fi
else
  warn "gitignore_global nicht gefunden, übersprungen"
fi

# --------------------------------------------------------------------------- #
step "4/5  Skills verlinken"
# Symlinks statt Kopien – sonst driften die Macs auseinander und ein
# "git pull" im Skill-Repo bliebe ohne Wirkung.

mkdir -p "$HOME/.claude/skills"
for s in "$SKILLS_DIR"/skills/*/; do
  [ -d "$s" ] || continue
  name=$(basename "$s")
  target="$HOME/.claude/skills/$name"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "${s%/}" ]; then
    ok "$name verlinkt"
  elif [ -e "$target" ] && [ ! -L "$target" ]; then
    warn "$name existiert als echtes Verzeichnis – wird NICHT überschrieben"
    echo "       manuell: rm -rf '$target' && ln -s '${s%/}' '$target'"
  else
    do_it "$name verlinken" && ln -sfn "${s%/}" "$target" && ok "$name verlinkt"
  fi
done

# --------------------------------------------------------------------------- #
step "5/5  Repos holen"

if [ "$CHECK_ONLY" = 1 ]; then
  warn "würde tun: devsync.sh clone"
elif [ "$CAN_CLONE_REPOS" = 0 ]; then
  warn "übersprungen – gh/SSH nicht bereit. Die Skills stehen trotzdem."
  echo "     Nachholen:  gh auth login && $HERE/devsync.sh clone"
else
  bash "$HERE/devsync.sh" clone
  echo
  bash "$HERE/devsync.sh" status
fi

step "Fertig."
echo "  Claude Code neu starten, damit die Skills geladen werden."
echo "  Danach:  /repo-sync   oder   ~/.claude/skills/repo-sync/devsync.sh status"
