#!/usr/bin/env bash
# auto-sync – periodischer Multi-Mac Sync (LaunchAgent).
# Push + Pull (Merge) alle 2 min, danach Fast-Forward-Push in die mos-Nodes
# (die haben keinen GitHub-Zugang). Commitet nie.
# Notification bei dirty/unpushed/Node-Fehler.
#
#   auto-sync.sh           # normaler Lauf
#   auto-sync.sh --now     # gleich + immer Status-Notification (Debug)

set -uo pipefail

DEV="${DEVSYNC_ROOT:-$HOME/Developer}"
DEVSYNC="${DEVSYNC_BIN:-$HOME/.claude/skills/repo-sync/devsync.sh}"
LOG_DIR="${DEVSYNC_LOG_DIR:-$HOME/.cache/devsync}"
LOG="$LOG_DIR/auto-sync.log"
FORCE_NOTIFY=0
[ "${1:-}" = "--now" ] && FORCE_NOTIFY=1

mkdir -p "$LOG_DIR"
exec >>"$LOG" 2>&1

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*"; }

notify() {
  local title="$1" body="$2"
  # AppleScript: Strings escapen, dann display notification.
  title=${title//\\/\\\\}; title=${title//\"/\\\"}
  body=${body//\\/\\\\}; body=${body//\"/\\\"}
  /usr/bin/osascript <<EOF 2>/dev/null || true
display notification "$body" with title "$title" sound name "Glass"
EOF
}

# Offline? Nichts tun.
if ! /usr/bin/nc -z -G 3 github.com 443 2>/dev/null; then
  log "skip: github.com unreachable"
  exit 0
fi

if [ ! -x "$DEVSYNC" ] && [ ! -f "$DEVSYNC" ]; then
  log "error: devsync not found at $DEVSYNC"
  notify "devsync" "Script fehlt: $DEVSYNC"
  exit 1
fi

log "=== auto-sync start ==="

# Push + Pull-Merge (kein clone, kein commit — ship bleibt beim Agenten / User)
if ! bash "$DEVSYNC" push; then
  log "push returned non-zero"
fi
if ! bash "$DEVSYNC" pull; then
  log "pull returned non-zero"
fi

# ── Cluster-Nodes versorgen ───────────────────────────────────────────────
# Die mos-Nodes haben keinen GitHub-Lesezugriff (jmerados1..4 sind nicht auf
# MeradosUG/agent-swarm berechtigt). Statt vier GitHub-Zugaenge zu verwalten
# verteilt dieser Mac: Fast-Forward-Push per SSH in ihre Repos.
# Kein --force — git lehnt Nicht-Fast-Forward selbst ab, und
# receive.denyCurrentBranch=updateInstead aktualisiert nur saubere Worktrees.
NODES="${DEVSYNC_NODES:-mos1 mos2 mos3 mos4}"
NODE_FAILS=$(mktemp "${TMPDIR:-/tmp}/devsync-nodefail.XXXXXX")

push_node() {
  local h="$1" repos name br r out fail=0
  repos=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$h" '
    for d in ~/Developer/*/.git; do
      [ -e "$d" ] || continue
      r=${d%/.git}
      git -C "$r" config receive.denyCurrentBranch updateInstead 2>/dev/null
      echo "$(basename "$r") $(git -C "$r" branch --show-current 2>/dev/null)"
    done' 2>/dev/null) || { log "node $h: nicht erreichbar"; return 0; }

  while read -r name br; do
    [ -n "$name" ] && [ -n "$br" ] || continue
    r="$DEV/$name"
    [ -d "$r/.git" ] || continue
    git -C "$r" rev-parse --verify -q "$br" >/dev/null 2>&1 || continue
    if out=$(git -C "$r" push "$h:Developer/$name" "$br:$br" 2>&1); then
      grep -qiE 'up-to-date|aktuell' <<<"$out" || log "node $h: $name $br aktualisiert"
    else
      log "node $h: $name $br FEHLER – $(grep -m1 -iE 'rejected|error|fatal' <<<"$out")"
      fail=$((fail + 1))
    fi
  done <<<"$repos"

  [ "$fail" != 0 ] && echo "$h" >>"$NODE_FAILS"
  return 0
}

for h in $NODES; do push_node "$h" & done
wait
node_fail_names=$(tr '\n' ' ' <"$NODE_FAILS" | sed 's/ *$//')
rm -f "$NODE_FAILS"
[ -n "$node_fail_names" ] && log "node-push fehlgeschlagen: $node_fail_names"

# Status auswerten (kurz, ohne volle gh-remote-Liste — nur lokal)
dirty=0
unpushed=0
dirty_names=()
unpushed_names=()

for d in "$DEV"/*/; do
  [ -d "$d/.git" ] || continue
  name=$(basename "$d")
  git -C "$d" remote get-url origin >/dev/null 2>&1 || continue

  s=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  u=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [ "$s" != 0 ]; then
    dirty=$((dirty + 1))
    dirty_names+=("$name")
  fi
  if [ "$u" != 0 ]; then
    # Archivierte Repos stillschweigend ignorieren (wie devsync)
    nwo=$(git -C "$d" remote get-url origin 2>/dev/null \
      | sed -E 's#^(ssh://)?git@github\.com[:/]##; s#^https://github\.com/##; s#\.git$##')
    archived=$(gh repo view "$nwo" --json isArchived --jq '.isArchived' 2>/dev/null || echo false)
    if [ "$archived" = "true" ]; then
      continue
    fi
    unpushed=$((unpushed + 1))
    unpushed_names+=("$name")
  fi
done

log "result: dirty=$dirty unpushed=$unpushed"

if [ "$dirty" -gt 0 ] || [ "$unpushed" -gt 0 ] || [ -n "$node_fail_names" ]; then
  body=""
  [ "$dirty" -gt 0 ] && body="${dirty} dirty (${dirty_names[*]})"
  if [ "$unpushed" -gt 0 ]; then
    [ -n "$body" ] && body="$body · "
    body="${body}${unpushed} unpushed (${unpushed_names[*]})"
  fi
  if [ -n "$node_fail_names" ]; then
    [ -n "$body" ] && body="$body · "
    body="${body}node-push failed: ${node_fail_names}"
  fi
  # Notification-Body kürzen (macOS limit ~256)
  body=$(printf '%.200s' "$body")
  notify "devsync – Aktion nötig" "$body"
  log "notified: $body"
elif [ "$FORCE_NOTIFY" = 1 ]; then
  notify "devsync" "Alles sauber (push+pull ok)"
  log "notified: clean"
else
  log "clean – no notification"
fi

log "=== auto-sync done ==="
