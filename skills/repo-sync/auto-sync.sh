#!/usr/bin/env bash
# auto-sync – periodischer Multi-Mac Sync (LaunchAgent).
# Push + Pull alle 30 min. Commitet nie. Notification bei dirty/unpushed/Fehler.
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

# Push + Pull (kein clone alle 30 min — zu teuer; clone bei open-mac / täglich)
if ! bash "$DEVSYNC" push; then
  log "push returned non-zero"
fi
if ! bash "$DEVSYNC" pull; then
  log "pull returned non-zero"
fi

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

if [ "$dirty" -gt 0 ] || [ "$unpushed" -gt 0 ]; then
  body=""
  [ "$dirty" -gt 0 ] && body="${dirty} dirty (${dirty_names[*]})"
  if [ "$unpushed" -gt 0 ]; then
    [ -n "$body" ] && body="$body · "
    body="${body}${unpushed} unpushed (${unpushed_names[*]})"
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
