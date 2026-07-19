#!/usr/bin/env bash
# setup-mac – einen zweiten Mac auf denselben Stand bringen.
#
#   bash setup-mac.sh          # prüfen und einrichten
#   bash setup-mac.sh --check  # nur prüfen, nichts ändern
#
# Idempotent: mehrfaches Ausführen ist gefahrlos.

set -uo pipefail

DEV="${DEVSYNC_ROOT:-$HOME/Developer}"
SKILLS_REPO="git@github.com:maf4711/merados-skills.git"
SKILLS_DIR="$DEV/merados-skills"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
err()  { printf '\033[31m  ✗ %s\033[0m\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
do_it() { [ "$CHECK_ONLY" = 1 ] && { warn "würde tun: $*"; return 1; }; return 0; }

# --------------------------------------------------------------------------- #
step "1/5  Voraussetzungen"

for c in git gh; do
  command -v "$c" >/dev/null 2>&1 && ok "$c vorhanden" || {
    err "$c fehlt – brew install $c"; exit 1; }
done

if gh auth status >/dev/null 2>&1; then
  ok "gh angemeldet als $(gh api user --jq .login 2>/dev/null)"
else
  err "gh nicht angemeldet – führe aus: gh auth login   (SSH als Protokoll wählen)"
  exit 1
fi

# ssh -T beendet sich immer mit Status 1 – unter pipefail würde das die
# ganze Pipe fehlschlagen lassen. Darum Ausgabe erst einfangen, dann prüfen.
ssh_out=$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)
if grep -q "successfully authenticated" <<<"$ssh_out"; then
  ok "SSH-Key funktioniert"
else
  err "SSH zu GitHub schlägt fehl."
  echo "     Key erzeugen:  ssh-keygen -t ed25519 -C \"\$(gh api user --jq .email)\""
  echo "     Hinterlegen:   gh ssh-key add ~/.ssh/id_ed25519.pub"
  exit 1
fi

# --------------------------------------------------------------------------- #
step "2/5  Globale .gitignore"
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
step "3/5  Skill-Repo"

if [ -d "$SKILLS_DIR/.git" ]; then
  ok "merados-skills vorhanden"
  do_it "pull" && git -C "$SKILLS_DIR" pull --ff-only -q 2>/dev/null
else
  if do_it "merados-skills klonen"; then
    mkdir -p "$DEV"
    git clone -q "$SKILLS_REPO" "$SKILLS_DIR" && ok "geklont" || { err "Clone fehlgeschlagen"; exit 1; }
  fi
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
else
  bash "$HERE/devsync.sh" clone
  echo
  bash "$HERE/devsync.sh" status
fi

step "Fertig."
echo "  Claude Code neu starten, damit die Skills geladen werden."
echo "  Danach:  /repo-sync   oder   ~/.claude/skills/repo-sync/devsync.sh status"
