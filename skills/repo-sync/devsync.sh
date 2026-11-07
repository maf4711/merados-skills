#!/usr/bin/env bash
# devsync – ~/Developer über mehrere Macs via GitHub synchron halten.
# Bash 3.2-kompatibel (LaunchAgent nutzt /bin/bash).
#
#   devsync status   Übersicht: dirty / unpushed / fehlende Repos
#   devsync clone    fehlende GitHub-Origins parallel klonen
#                    (gleicher Name, zwei Orgs → $DEV/<owner>--<name>)
#   devsync pull     Fetch + Merge (kein ff-only, kein Rebase)
#   devsync push     lokale Commits parallel pushen
#   devsync ship     Commit (ohne Secrets) + Merge + Push + Remote anlegen
#   devsync cpr      Alias für ship
#   devsync sync     ship + clone  (schnellster voller Lauf)
#
# Voraussetzung: gh auth login, SSH-Key. Hängt nie auf Credentials.

set -uo pipefail

DEV="${DEVSYNC_ROOT:-$HOME/Developer}"
OWNERS="${DEVSYNC_OWNERS:-maf4711 MeradosUG FinfuxUG}"
CREATE_OWNER="${DEVSYNC_CREATE_OWNER:-maf4711}"
JOBS="${DEVSYNC_JOBS:-}"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new}"
GIT_FAST="-c protocol.version=2 -c fetch.parallel=8 -c submodule.fetchJobs=0"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

njobs() {
  local n="$JOBS"
  if [ -z "$n" ]; then
    n=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)
  fi
  [ "$n" -gt 16 ] && n=16
  [ "$n" -lt 1 ] && n=1
  echo "$n"
}

# Batch-parallel (bash 3.2: wait -n gibt es nicht).
run_pool() {
  local func="$1" running=0 r jobs
  jobs=$(njobs)
  while read -r r; do
    [ -z "$r" ] && continue
    "$func" "$r" </dev/null &
    running=$((running + 1))
    if [ "$running" -ge "$jobs" ]; then
      wait
      running=0
    fi
  done
  wait
}

gitx() {
  local r="$1"; shift
  git $GIT_FAST -C "$r" "$@"
}

local_repos() {
  local d
  for d in "$DEV"/*/; do
    if [ -d "$d/.git" ] || [ -f "$d/.git" ]; then
      echo "${d%/}"
    fi
  done
  if [ -d "$DEV/meradOS/Skill-Suite/.git" ] || [ -f "$DEV/meradOS/Skill-Suite/.git" ]; then
    echo "$DEV/meradOS/Skill-Suite"
  fi
}

nwo_norm() {
  printf '%s' "$1" | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##' | tr '[:upper:]' '[:lower:]'
  printf '\n'
}

remote_repos() {
  local o flags
  flags="--no-archived"
  [ "${DEVSYNC_ARCHIVED:-0}" = 1 ] && flags=""
  for o in $OWNERS; do
    # shellcheck disable=SC2086
    gh repo list "$o" --limit 500 $flags \
      --json nameWithOwner,sshUrl --jq '.[] | "\(.nameWithOwner)\t\(.sshUrl)"'
  done
}

local_remotes() {
  local r
  while read -r r; do
    nwo_norm "$(gitx "$r" remote get-url origin 2>/dev/null || true)"
  done < <(local_repos)
}

dirty_count() { gitx "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '; }
unpushed_count() { gitx "$1" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' '; }

nwo_of() {
  gitx "$1" remote get-url origin 2>/dev/null \
    | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##'
}

branch_of() { gitx "$1" branch --show-current 2>/dev/null; }

is_skip_path() {
  local f="$1" base
  base=$(basename "$f")
  case "$f" in
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
    *.pem|*.p8|*.key|*.pfx|*.p12) return 0 ;;
    *id_rsa*|*id_ed25519*|*id_ecdsa*) return 0 ;;
    */AuthKey_*.p8|AuthKey_*.p8) return 0 ;;
    */credentials.json|credentials.json) return 0 ;;
    */secrets.json|secrets.json|*/secret.json|secret.json) return 0 ;;
    *.xcarchive|*.xcarchive/*|*/build/testflight/*) return 0 ;;
    */.build/*|.build/*|*/DerivedData/*) return 0 ;;
    *.app/*|*.dSYM/*) return 0 ;;
    ruvector.db|*/ruvector.db) return 0 ;;
    *.rvf|*/*.rvf) return 0 ;;
    _fabrik/attach.json|*/_fabrik/attach.json|_fabrik/state.json|*/_fabrik/state.json) return 0 ;;
    */.claude-flow/*|.claude-flow/*) return 0 ;;
  esac
  case "$base" in
    .env|.env.*|*.pem|*.p8|*.key) return 0 ;;
  esac
  return 1
}

unstage_skips() {
  local r="$1" f
  gitx "$r" diff --cached --name-only -z 2>/dev/null | while IFS= read -r -d '' f; do
    if is_skip_path "$f"; then
      gitx "$r" reset -q HEAD -- "$f" 2>/dev/null || true
      warn "  skip: $f"
    fi
  done
}

cmd_status() {
  local dirty=0 unpushed=0 noremote=0
  bold "Lokale Repos in $DEV  (jobs=$(njobs))"
  while read -r r; do
    local name s u
    name=$(basename "$r")
    if ! gitx "$r" remote get-url origin >/dev/null 2>&1; then
      warn "  ~ $name – kein Remote"
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
  local missing=0 have nwo want name owner
  have=$(local_remotes)
  while IFS=$'\t' read -r nwo _; do
    want=$(printf '%s' "$nwo" | tr '[:upper:]' '[:lower:]')
    grep -qxF "$want" <<<"$have" && continue
    name="${nwo##*/}"
    owner="${nwo%%/*}"
    if [ -e "$DEV/$name" ]; then
      echo "  + $nwo → ${owner}--${name}"
    else
      echo "  + $nwo"
    fi
    missing=$((missing + 1))
  done < <(remote_repos)
  [ "$missing" = 0 ] && ok "  – keine" || echo "  $missing fehlend → devsync clone"
}

# Empty dest = already present. owner--name if $DEV/<repo> is taken by another origin.
clone_dest() {
  local nwo="$1" owner name dest existing want
  owner="${nwo%%/*}"
  name="${nwo##*/}"
  want=$(printf '%s' "$nwo" | tr '[:upper:]' '[:lower:]')
  dest="$DEV/$name"
  if [ -e "$dest" ]; then
    if [ -d "$dest/.git" ] || [ -f "$dest/.git" ]; then
      existing=$(nwo_norm "$(gitx "$dest" remote get-url origin 2>/dev/null || true)")
      [ "$existing" = "$want" ] && { echo ""; return 0; }
    fi
    dest="$DEV/${owner}--${name}"
  fi
  if [ -e "$dest" ]; then
    if [ -d "$dest/.git" ] || [ -f "$dest/.git" ]; then
      existing=$(nwo_norm "$(gitx "$dest" remote get-url origin 2>/dev/null || true)")
      [ "$existing" = "$want" ] && { echo ""; return 0; }
    fi
    err "  kein Pfad frei für $nwo"
    echo ""
    return 1
  fi
  echo "$dest"
}

clone_one() {
  local nwo="$1" ssh="$2" target
  target=$(clone_dest "$nwo") || return 1
  [ -z "$target" ] && return 0
  bold "clone $nwo → $target"
  git $GIT_FAST clone --jobs=8 "$ssh" "$target" || err "  fehlgeschlagen: $nwo"
}

clone_line() {
  local line="$1" nwo ssh
  nwo="${line%%	*}"
  ssh="${line#*	}"
  clone_one "$nwo" "$ssh"
}

cmd_clone() {
  local have
  have=$(local_remotes)
  run_pool clone_line < <(
    while IFS=$'\t' read -r nwo ssh; do
      [ -z "$nwo" ] && continue
      want=$(printf '%s' "$nwo" | tr '[:upper:]' '[:lower:]')
      grep -qxF "$want" <<<"$have" && continue
      printf '%s\t%s\n' "$nwo" "$ssh"
    done < <(remote_repos)
  )
}

diagnose() {
  local r="$1" name="$2" out="$3" nwo
  nwo=$(nwo_of "$r")

  if grep -qiE 'repository not found|could not read from remote' <<<"$out"; then
    if ! gh repo view "$nwo" >/dev/null 2>&1; then
      err "$name – Remote $nwo existiert nicht mehr"
      echo "     neu anlegen: cd $r && gh repo create $nwo --private --source=. --push"
      return
    fi
    err "$name – kein Zugriff auf $nwo"
    return
  fi

  if grep -qiE 'CONFLICT|Merge conflict' <<<"$out"; then
    err "$name – Merge-Konflikt"
    echo "     lösen: git -C $r status"
    return
  fi

  if grep -qiE 'bad object|fehlerhaftem Namen|malformed|broken' <<<"$out"; then
    err "$name – beschädigte Refs"
    return
  fi

  if grep -qiE "does not exist|no such ref|couldn't find remote ref|Konfiguration gibt an|your configuration specifies" <<<"$out"; then
    if [ -z "$(gitx "$r" ls-remote --heads origin 2>/dev/null)" ]; then
      warn "$name – Remote ist leer"
      return
    fi
    err "$name – Branch '$(branch_of "$r")' existiert remote nicht"
    return
  fi

  err "$name – $(head -1 <<<"$out")"
}

pull_one() {
  local r="$1" name br out
  name=$(basename "$r")
  gitx "$r" remote get-url origin >/dev/null 2>&1 || return 0
  br=$(branch_of "$r")
  [ -z "$br" ] && return 0
  if ! out=$(gitx "$r" fetch --jobs=8 --prune origin 2>&1); then
    diagnose "$r" "$name" "$out"
    return
  fi
  if [ -n "$(gitx "$r" status --porcelain)" ] && [ "${DEVSYNC_SHIP:-0}" != 1 ]; then
    warn "skip $name – uncommitted changes"
    return
  fi
  if gitx "$r" rev-parse --verify "origin/$br" >/dev/null 2>&1; then
    if out=$(gitx "$r" merge --no-edit "origin/$br" 2>&1); then
      echo "$out" | grep -qE 'Already up to date|Bereits aktuell' || echo "  merge $name: $(echo "$out" | tail -1)"
    else
      diagnose "$r" "$name" "$out"
    fi
  fi
}

cmd_pull() { run_pool pull_one < <(local_repos); }

diagnose_push() {
  local r="$1" name="$2" nwo meta
  nwo=$(nwo_of "$r")
  meta=$(gh repo view "$nwo" --json isArchived,viewerPermission \
    --jq '"\(.isArchived) \(.viewerPermission)"' 2>/dev/null) || {
    err "  $name – $nwo nicht lesbar"; return; }

  case "$meta" in
    "true "*)
      err "  $name – $nwo ist archiviert (read-only)" ;;
    *" READ"|*" NONE")
      err "  $name – nur Lesezugriff auf $nwo" ;;
    *)
      err "  $name – Push abgelehnt (Branch-Protection?)"
      echo "       Details: git -C $r push --all" ;;
  esac
}

push_one() {
  local r="$1" name u
  name=$(basename "$r")
  gitx "$r" remote get-url origin >/dev/null 2>&1 || return 0
  if ! on_default_branch "$r"; then
    return 0
  fi
  u=$(unpushed_count "$r")
  [ "$u" = 0 ] && return 0
  bold "push $name ($u)"
  # Nur die aktuelle Branch: "--all" hat lokale Wegwerf-Branches nach GitHub
  # getragen, wo sie neben echten Feature-Branches stehen.
  if gitx "$r" push -u origin HEAD --tags 2>/dev/null; then
    ok "  $name"
  else
    diagnose_push "$r" "$name"
  fi
}

cmd_push() { run_pool push_one < <(local_repos); }

ensure_remote() {
  local r="$1" name nwo email
  name=$(basename "$r")
  gitx "$r" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  if gitx "$r" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "$(gitx "$r" rev-list --all --max-count=1 2>/dev/null)" ]; then
    warn "  $name – kein Commit, kein Remote"
    return 1
  fi
  email=$(git config --global user.email 2>/dev/null || true)
  if [ -n "$email" ] && ! gitx "$r" log --format='%ae' | grep -Fqx "$email"; then
    warn "  $name – kein eigenes Commit, Remote nicht angelegt"
    return 1
  fi
  nwo="$CREATE_OWNER/$name"
  bold "create $nwo"
  if gh repo create "$nwo" --private --source="$r" --remote=origin --push 2>/dev/null; then
    ok "  $nwo angelegt"
    return 0
  fi
  if gh repo view "$nwo" >/dev/null 2>&1; then
    gitx "$r" remote add origin "git@github.com:$nwo.git" 2>/dev/null || true
    gitx "$r" push -u origin HEAD --tags 2>/dev/null && return 0
  fi
  err "  $name – Remote konnte nicht angelegt werden"
  return 1
}

commit_msg_for() {
  case "$(basename "$1")" in
    Skill-Suite|merados-skills)
      echo "feat(repo-sync): fastest ship/merge and publish cpr" ;;
    *)
      echo "chore(sync): ship local work $(date +%Y-%m-%d)" ;;
  esac
}

# Ist das Repo mitten in einer Operation? Dann ist nichts davon shipbar.
repo_busy() {
  local r="$1" g
  g=$(gitx "$r" rev-parse --git-dir 2>/dev/null) || return 1
  [ -d "$r/$g/rebase-merge" ] || [ -d "$r/$g/rebase-apply" ] && return 0
  [ -f "$r/$g/MERGE_HEAD" ] || [ -f "$r/$g/CHERRY_PICK_HEAD" ] || [ -f "$r/$g/BISECT_LOG" ] && return 0
  gitx "$r" symbolic-ref -q HEAD >/dev/null 2>&1 || return 0   # detached HEAD
  return 1
}

# Auf welchem Branch darf die Automation ueberhaupt arbeiten?
#
# Nur der Default-Branch. Feature-Branches gehoeren dem Menschen: ein
# automatischer Commit dort kippt den Inhalt eines offenen PR um oder schiebt
# fremde Dateien hinein, die zufaellig im Baum lagen. Am 27.08.2026 wurden so
# drei Mal Aenderungen veroeffentlicht, bevor jemand sie ansehen konnte.
default_branch() {
  local r="$1" b c
  b=$(gitx "$r" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  b="${b#origin/}"
  if [ -n "$b" ]; then echo "$b"; return 0; fi
  for c in main master; do
    if gitx "$r" show-ref -q --verify "refs/heads/$c"; then echo "$c"; return 0; fi
  done
  echo main
}

on_default_branch() {
  local r="$1" cur def
  cur=$(gitx "$r" symbolic-ref -q --short HEAD 2>/dev/null) || return 1
  def=$(default_branch "$r")
  [ "$cur" = "$def" ]
}

commit_one() {
  local r="$1" name n staged msg untracked
  name=$(basename "$r")
  gitx "$r" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [ "$(dirty_count "$r")" = 0 ] && return 0
  if repo_busy "$r"; then
    warn "  $name – Rebase/Merge/detached HEAD, kein Commit"
    return 0
  fi
  if ! on_default_branch "$r"; then
    warn "  $name – auf $(gitx "$r" symbolic-ref -q --short HEAD 2>/dev/null), nicht $(default_branch "$r"): kein Commit"
    return 0
  fi
  # add -u statt add -A: nur bereits getrackte Dateien. Ungetracktes ist
  # Zwischenstand oder Zufall — am 30.05.2026 waren es IBKR-PII-PDFs, am
  # 26.08.2026 verworfene Scratch-Module. Wer eine neue Datei versionieren
  # will, macht "git add" selbst.
  gitx "$r" add -u
  untracked=$(gitx "$r" ls-files --others --exclude-standard | wc -l | tr -d ' ')
  [ "$untracked" != 0 ] && warn "  $name – $untracked ungetrackte Datei(en) NICHT committet"
  unstage_skips "$r"
  staged=$(gitx "$r" diff --cached --name-only | wc -l | tr -d ' ')
  if [ "$staged" = 0 ]; then
    warn "  $name – nur Skip-Pfade, kein Commit"
    return 0
  fi
  msg=$(commit_msg_for "$r")
  if gitx "$r" commit -m "$msg"; then
    n=$(gitx "$r" log -1 --oneline)
    ok "  commit $name: $n"
  else
    warn "  $name – Commit fehlgeschlagen (Hook? leer?)"
  fi
}

suite_release() {
  local r="$1" nwo tag notes
  nwo=$(nwo_of "$r")
  case "$nwo" in
    MeradosUG/Skill-Suite|maf4711/merados-skills) ;;
    *) return 0 ;;
  esac
  if [ -f "$r/CHANGELOG.md" ]; then
    tag=$(grep -m1 -E '^## \[[0-9.]+\]' "$r/CHANGELOG.md" | sed -E 's/^## \[([^]]+)\].*/v\1/')
  fi
  [ -n "${tag:-}" ] || return 0
  if gitx "$r" rev-parse "$tag" >/dev/null 2>&1; then
    return 0
  fi
  notes=$(awk -v t="${tag#v}" '
    $0 ~ "^## \\[" t "\\]" {p=1; next}
    p && $0 ~ /^## \[/ {exit}
    p {print}
  ' "$r/CHANGELOG.md" 2>/dev/null)
  gitx "$r" tag -a "$tag" -m "$tag" 2>/dev/null || gitx "$r" tag "$tag" 2>/dev/null || true
  gitx "$r" push origin "$tag" 2>/dev/null || true
  if [ -n "$notes" ]; then
    gh release create "$tag" -R "$nwo" --title "$tag" --notes "$notes" 2>/dev/null \
      && ok "  release $nwo $tag" || true
  else
    gh release create "$tag" -R "$nwo" --title "$tag" --generate-notes 2>/dev/null \
      && ok "  release $nwo $tag" || true
  fi
}

ship_one() {
  local r="$1" name br out
  name=$(basename "$r")
  DEVSYNC_SHIP=1
  commit_one "$r"
  ensure_remote "$r" || return 0
  br=$(branch_of "$r")
  [ -z "$br" ] && br=main
  if out=$(gitx "$r" fetch --jobs=8 --prune origin 2>&1); then
    if gitx "$r" rev-parse --verify "origin/$br" >/dev/null 2>&1; then
      if ! out=$(gitx "$r" merge --no-edit "origin/$br" 2>&1); then
        diagnose "$r" "$name" "$out"
        return 0
      fi
    fi
  else
    diagnose "$r" "$name" "$out"
  fi
  # Nur die aktuelle Branch. "push --all" hat Wegwerf-Branches mit
  # Zwischenstaenden auf GitHub geschoben, wo sie wie Arbeitsergebnis aussehen.
  if gitx "$r" push -u origin HEAD --tags 2>/dev/null; then
    ok "  ship $name"
    suite_release "$r"
  else
    diagnose_push "$r" "$name"
  fi
}

cmd_ship() {
  bold "ship → GitHub  jobs=$(njobs)  root=$DEV"
  run_pool ship_one < <(local_repos)
}

cmd_sync() {
  cmd_ship
  cmd_clone
}

case "${1:-status}" in
  status) cmd_status ;;
  clone)  cmd_clone ;;
  pull)   cmd_pull ;;
  push)   cmd_push ;;
  ship|cpr|release) cmd_ship ;;
  sync)   cmd_sync ;;
  *) err "Unbekannt: $1"; sed -n '2,16p' "$0"; exit 1 ;;
esac
