#!/usr/bin/env bash
# devsync – ~/Developer über mehrere Macs via GitHub synchron halten.
#
#   devsync status   Übersicht: dirty / unpushed / fehlende Repos
#   devsync clone    alle GitHub-Repos klonen, die lokal fehlen
#   devsync pull     alle sauberen Repos aktualisieren (ff-only)
#   devsync push     alle lokalen Commits pushen (committet nichts)
#   devsync          = status
#
# Voraussetzung: gh auth login, SSH-Key auf beiden Macs.

set -uo pipefail

DEV="${DEVSYNC_ROOT:-$HOME/Developer}"
OWNERS="${DEVSYNC_OWNERS:-maf4711 MeradosUG}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

local_repos() {
  for d in "$DEV"/*/; do
    [ -d "$d/.git" ] && echo "${d%/}"
  done
}

remote_repos() {
  for o in $OWNERS; do
    gh repo list "$o" --limit 500 --no-archived \
      --json nameWithOwner,sshUrl --jq '.[] | "\(.nameWithOwner)\t\(.sshUrl)"'
  done
}

# Alle lokal bereits verdrahteten Remotes, normalisiert auf owner/name.
# Nötig, weil Verzeichnisname != Repo-Name sein kann (z.B. fabrik → agent-factory-fabrik).
local_remotes() {
  while read -r r; do
    git -C "$r" remote get-url origin 2>/dev/null \
      | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##'
  done < <(local_repos)
}

# Uncommitted-Count; 0 auch bei frischem Repo ohne Commits.
dirty_count() { git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '; }
unpushed_count() { git -C "$1" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' '; }

cmd_status() {
  local dirty=0 unpushed=0 noremote=0
  bold "Lokale Repos in $DEV"
  while read -r r; do
    local name s u
    name=$(basename "$r")
    if ! git -C "$r" remote get-url origin >/dev/null 2>&1; then
      warn "  ~ $name – kein Remote (wird nie gesynct)"
      noremote=$((noremote + 1))
      continue
    fi
    s=$(dirty_count "$r")
    u=$(unpushed_count "$r")
    [ "$s" != 0 ] && { err "  ! $name – $s uncommitted"; dirty=$((dirty + 1)); }
    [ "$u" != 0 ] && { warn "  ↑ $name – $u unpushed"; unpushed=$((unpushed + 1)); }
  done < <(local_repos)
  echo "  $dirty dirty, $unpushed unpushed, $noremote ohne Remote"

  bold "Auf GitHub, aber nicht lokal"
  local missing=0 have
  have=$(local_remotes)
  while IFS=$'\t' read -r nwo _; do
    grep -qxF "$nwo" <<<"$have" && continue
    [ -d "$DEV/${nwo##*/}" ] && continue
    echo "  + $nwo"; missing=$((missing + 1))
  done < <(remote_repos)
  [ "$missing" = 0 ] && ok "  – keine" || echo "  $missing fehlend → devsync clone"
}

cmd_clone() {
  local have
  have=$(local_remotes)
  while IFS=$'\t' read -r nwo ssh; do
    local target="$DEV/${nwo##*/}"
    grep -qxF "$nwo" <<<"$have" && continue
    [ -e "$target" ] && continue
    bold "clone $nwo"
    git clone "$ssh" "$target" || err "  fehlgeschlagen: $nwo"
  done < <(remote_repos)
}

cmd_pull() {
  while read -r r; do
    local name
    name=$(basename "$r")
    git -C "$r" remote get-url origin >/dev/null 2>&1 || continue
    if [ -n "$(git -C "$r" status --porcelain)" ]; then
      warn "skip $name – uncommitted changes"
      continue
    fi
    if out=$(git -C "$r" pull --ff-only --quiet 2>&1); then
      [ -n "$out" ] && echo "  $name: $out"
    else
      err "$name – pull fehlgeschlagen (divergiert?): $out"
    fi
  done < <(local_repos)
}

cmd_push() {
  while read -r r; do
    local name u
    name=$(basename "$r")
    git -C "$r" remote get-url origin >/dev/null 2>&1 || continue
    u=$(unpushed_count "$r")
    [ "$u" = 0 ] && continue
    bold "push $name ($u Commits)"
    git -C "$r" push --all || err "  fehlgeschlagen: $name"
    [ "$(dirty_count "$r")" != 0 ] && warn "  Achtung: $name hat noch uncommitted changes"
  done < <(local_repos)
}

case "${1:-status}" in
  status) cmd_status ;;
  clone)  cmd_clone ;;
  pull)   cmd_pull ;;
  push)   cmd_push ;;
  sync)   cmd_push; cmd_pull; cmd_clone ;;
  *) err "Unbekannt: $1"; sed -n '2,15p' "$0"; exit 1 ;;
esac
