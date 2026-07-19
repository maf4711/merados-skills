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

# Übersetzt einen fehlgeschlagenen Pull in Ursache + Fix-Befehl.
# Reihenfolge zählt: von der eindeutigsten Signatur zur unschärfsten.
diagnose() {
  local r="$1" name="$2" out="$3" nwo
  nwo=$(git -C "$r" remote get-url origin 2>/dev/null \
    | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##')

  # Remote gelöscht oder umbenannt
  if grep -qiE 'repository not found|could not read from remote' <<<"$out"; then
    if ! gh repo view "$nwo" >/dev/null 2>&1; then
      err "$name – Remote $nwo existiert nicht mehr"
      echo "     neu anlegen: cd $r && gh repo create $nwo --private --source=. --push"
      echo "     oder lösen:  git -C $r remote remove origin"
      return
    fi
    err "$name – kein Zugriff auf $nwo (Rechte? SSH-Key?)"
    echo "     prüfen: gh repo view $nwo --json viewerPermission"
    return
  fi

  # Kaputte Refs – typisch macOS-Duplikate „main 2" aus Finder-/Cloud-Kopien
  if grep -qiE 'bad object|fehlerhaftem Namen|malformed|broken' <<<"$out"; then
    err "$name – beschädigte Refs"
    find "$r/.git/refs" -name '* [0-9]*' 2>/dev/null | sed 's/^/     verwaist: /'
    echo "     prüfen ob enthalten: git -C $r merge-base --is-ancestor <ref-sha> HEAD"
    echo "     dann löschen + git -C $r fsck"
    return
  fi

  # Kein Upstream, oft weil lokal oder remote noch gar keine Commits existieren
  if grep -qiE "refs/heads/.*existiert nicht|does not exist|no such ref|couldn't find remote ref|Konfiguration gibt an|your configuration specifies" <<<"$out"; then
    if [ -z "$(git -C "$r" ls-remote --heads origin 2>/dev/null)" ]; then
      warn "$name – Remote ist leer, nichts zu pullen"
      return
    fi
    err "$name – Branch '$(git -C "$r" branch --show-current)' existiert remote nicht"
    echo "     auf Hauptbranch: git -C $r checkout main && git -C $r branch -u origin/main"
    return
  fi

  # Echte Divergenz: beide Seiten haben eigene Commits
  if counts=$(git -C "$r" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null); then
    err "$name – divergiert: $(cut -f1 <<<"$counts") lokal / $(cut -f2 <<<"$counts") remote"
    echo "     ansehen: git -C $r log --oneline --left-right HEAD...@{u}"
    echo "     dann:    git -C $r rebase @{u}   (oder merge)"
    return
  fi

  err "$name – Pull fehlgeschlagen: $(head -1 <<<"$out")"
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
      diagnose "$r" "$name" "$out"
    fi
  done < <(local_repos)
}

# Warum kam der Push nicht durch? GitHub meldet alle drei Fälle als
# "Konnte nicht vom Remote-Repository lesen" – erst gh trennt sie auf.
diagnose_push() {
  local r="$1" name="$2" nwo meta
  nwo=$(git -C "$r" remote get-url origin 2>/dev/null \
    | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##')
  meta=$(gh repo view "$nwo" --json isArchived,viewerPermission \
    --jq '"\(.isArchived) \(.viewerPermission)"' 2>/dev/null) || {
    err "  $name – $nwo nicht lesbar (gelöscht? kein Zugriff?)"; return; }

  case "$meta" in
    "true "*)
      err "  $name – $nwo ist archiviert (read-only)"
      echo "       gh repo unarchive $nwo   # braucht Admin/Owner in der Org" ;;
    *" READ"|*" NONE")
      err "  $name – nur Lesezugriff auf $nwo, Push unmöglich"
      echo "       forken: gh repo fork $nwo --remote" ;;
    *)
      err "  $name – Push abgelehnt trotz Schreibrecht (Branch-Protection? pre-receive hook?)"
      echo "       Details: git -C $r push --all" ;;
  esac
}

cmd_push() {
  while read -r r; do
    local name u
    name=$(basename "$r")
    git -C "$r" remote get-url origin >/dev/null 2>&1 || continue
    u=$(unpushed_count "$r")
    [ "$u" = 0 ] && continue
    bold "push $name ($u Commits)"
    git -C "$r" push --all 2>/dev/null || diagnose_push "$r" "$name"
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
