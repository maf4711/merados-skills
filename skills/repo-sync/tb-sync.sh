#!/usr/bin/env bash
# Developer über MacCluster + Thunderbolt.
# Motor ist NUR `maccluster` (Apple ditto, newest-wins). Kein eigenes rsync.
#
#   tb-sync.sh inventory   # maccluster tb/status + sync home --compare --preset developer
#   tb-sync.sh sync        # inventory, dann nur neueste Dateien (--conflict-policy newer)
#   tb-sync.sh push|pull   # eine Richtung, trotzdem compare zuerst
#
# Voraussetzung: maccluster auf PATH, ~/.config/maccluster/cluster.toml,
# TB-Mesh (`sudo maccluster up`), SSH-Key zu 10.42.0.x.

set -uo pipefail

export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
CACHE="${HOME}/.cache/devsync"
LOG="$CACHE/tb-sync.log"
mkdir -p "$CACHE"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

mc() {
  if command -v maccluster >/dev/null 2>&1; then
    maccluster "$@"
    return
  fi
  if [ -d "${MACCLUSTER_SRC:-$HOME/Developer/maccluster/src}/maccluster" ]; then
    PYTHONPATH="${MACCLUSTER_SRC:-$HOME/Developer/maccluster/src}${PYTHONPATH:+:$PYTHONPATH}" \
      python3 -m maccluster "$@"
    return
  fi
  err "maccluster fehlt — install: pipx install git+https://github.com/maf4711/maccluster.git"
  err "oder Wrapper: PYTHONPATH=\$HOME/Developer/maccluster/src python3 -m maccluster"
  return 127
}

ensure_mesh() {
  local st
  st=$(mc --json status 2>/dev/null) || true
  if echo "$st" | grep -q '"overall": "healthy"'; then
    return 0
  fi
  warn "Mesh nicht healthy (10.42.0.x). TB-Sync braucht: sudo maccluster up"
  return 1
}

cmd_inventory() {
  : >"$LOG"
  bold "inventory  maccluster + Thunderbolt  Developer/"
  echo "cli: $(command -v maccluster 2>/dev/null || echo 'python3 -m maccluster')"
  mc --version 2>&1 | tee -a "$LOG"
  echo "--- config ---"
  mc config validate 2>&1 | tee -a "$LOG" || return 1
  echo "--- tb ---"
  mc tb 2>&1 | tee -a "$LOG"
  echo "--- status ---"
  mc status 2>&1 | tee -a "$LOG"
  echo "--- doctor ---"
  mc doctor 2>&1 | tee -a "$LOG" || true
  echo "--- Developer compare (nur Diff, kein Write) ---"
  mc --json sync home --compare --preset developer --conflict-policy newer --no-speedtest \
    --timeout 3600 2>&1 | tee -a "$LOG"
  echo
  mc sync home --compare --preset developer --conflict-policy newer --no-speedtest \
    --timeout 3600 --no-progress 2>&1 | tee -a "$LOG"
  ok "inventory fertig — als Nächstes nur neueste Dateien"
}

cmd_sync() {
  cmd_inventory || true
  ensure_mesh || true
  bold "sync  nur neueste Dateien  (maccluster sync home --preset developer --conflict-policy newer)"
  mc sync home --preset developer --conflict-policy newer --no-speedtest \
    --timeout 3600 "$@" 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  echo "when $(date '+%Y-%m-%d %H:%M:%S')" >"$CACHE/tb-last.txt"
  echo "log  $LOG" >>"$CACHE/tb-last.txt"
  echo "rc   $rc" >>"$CACHE/tb-last.txt"
  [ "$rc" = 0 ] || [ "$rc" = 3 ] && ok "maccluster Developer-sync rc=$rc"
  return "$rc"
}

case "${1:-inventory}" in
  inventory|inv|compare) cmd_inventory ;;
  sync)
    shift
    cmd_sync "$@"
    ;;
  push)
    shift
    cmd_inventory || true
    ensure_mesh || true
    mc sync home --preset developer --conflict-policy newer --push-only --no-speedtest --timeout 3600 "$@"
    ;;
  pull)
    shift
    cmd_inventory || true
    ensure_mesh || true
    mc sync home --preset developer --conflict-policy newer --pull-only --no-speedtest --timeout 3600 "$@"
    ;;
  status) mc status ;;
  tb)     mc tb ;;
  doctor) mc doctor ;;
  *)
    err "Unbekannt: $1"
    echo "inventory | sync | push | pull | status | tb | doctor"
    exit 1
    ;;
esac
