#!/usr/bin/env bash
# Save git (devsync ship), then SIGTERM other Grok/Claude/Codex CLIs.
# Sessions on disk stay. Never SIGKILL. Never ChatGPT.app / cpu-guard / sim-guard.
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEVSYNC="${LEAVE_MAC_DEVSYNC:-$HERE/../repo-sync/devsync.sh}"
WAIT_SECS="${LEAVE_MAC_WAIT_SECS:-8}"
SELF_PID="${LEAVE_MAC_SELF_PID:-$$}"

dry_run=0
do_ship=1
do_reboot=0
include_self=0

usage() {
  cat <<'EOF'
leave-mac.sh — save Developer git, drain other LLM CLIs, optionally reboot

  leave-mac.sh            SIGTERM other grok/claude/codex, then devsync ship
  leave-mac.sh --dry-run  inventory only
  leave-mac.sh --no-ship  drain CLIs, skip git
  leave-mac.sh --reboot   after save+drain, restart this Mac (not from dry-run)

Does not delete Grok/Claude session history. Does not SIGKILL.
Does not touch cpu-guard, sim-guard, Safari, or ChatGPT.app.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) dry_run=1 ;;
    --no-ship) do_ship=0 ;;
    --reboot) do_reboot=1 ;;
    --include-self) include_self=1 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ps_list() {
  if [ -n "${LEAVE_MAC_PS_FILE:-}" ]; then
    cat "$LEAVE_MAC_PS_FILE"
    return
  fi
  ps -ax -o pid=,ppid=,comm=,command=
}

emit_kill() {
  local sig="$1" pid="$2"
  if [ "$dry_run" -eq 1 ]; then
    echo "DRY-RUN kill -$sig $pid"
    return 0
  fi
  if [ -n "${LEAVE_MAC_KILL_LOG:-}" ]; then
    echo "$sig $pid" >>"$LEAVE_MAC_KILL_LOG"
    return 0
  fi
  kill -s "$sig" "$pid" 2>/dev/null || true
}

is_excluded_cmd() {
  case "$1" in
    *ChatGPT.app*|*Codex\ Framework*|*Codex\ \(Service\)*|*Codex\ \(Renderer\)*)
      return 0 ;;
    *SkyComputerUse*|*computer-use*|*cpu-guard*|*sim-guard*|*statusline-daemon*)
      return 0 ;;
  esac
  return 1
}

is_llm_comm() {
  case "$1" in
    grok|claude|codex) return 0 ;;
  esac
  return 1
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
ps_list >"$workdir/ps"
keepfile="$workdir/keep"

# Fields: pid ppid comm rest
ppid_of() {
  awk -v p="$1" '$1==p {print $2; exit}' "$workdir/ps"
}

comm_of() {
  awk -v p="$1" '$1==p {print $3; exit}' "$workdir/ps"
}

cmd_of() {
  awk -v p="$1" '$1==p {$1=$2=$3=""; sub(/^ +/,""); print; exit}' "$workdir/ps"
}

is_keep() {
  grep -qx "$1" "$keepfile" 2>/dev/null
}

: >"$keepfile"
echo "$SELF_PID" >>"$keepfile"
p="$SELF_PID"
n=0
while [ "$n" -lt 24 ]; do
  parent=$(ppid_of "$p" || true)
  [ -n "$parent" ] && [ "$parent" != "0" ] && [ "$parent" != "$p" ] || break
  echo "$parent" >>"$keepfile"
  p="$parent"
  n=$((n + 1))
done
sort -u -o "$keepfile" "$keepfile"

this_grok=""
p="$SELF_PID"
n=0
while [ "$n" -lt 24 ]; do
  c=$(comm_of "$p" || true)
  if [ "$c" = grok ]; then
    this_grok="$p"
    break
  fi
  parent=$(ppid_of "$p" || true)
  [ -n "$parent" ] && [ "$parent" != "0" ] && [ "$parent" != "$p" ] || break
  p="$parent"
  n=$((n + 1))
done

if [ -n "$this_grok" ]; then
  echo "$this_grok" >"$workdir/desc"
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    while read -r pid ppid _rest; do
      [ -n "${pid:-}" ] || continue
      if ! grep -qx "$pid" "$workdir/desc" && grep -qx "$ppid" "$workdir/desc"; then
        echo "$pid" >>"$workdir/desc"
        changed=1
      fi
    done <"$workdir/ps"
  done
  cat "$workdir/desc" >>"$keepfile"
  sort -u -o "$keepfile" "$keepfile"
fi

if [ "$include_self" -eq 1 ] && [ -n "$this_grok" ]; then
  grep -vx "$this_grok" "$keepfile" >"$workdir/keep2" || true
  mv "$workdir/keep2" "$keepfile"
fi

targets="$workdir/targets"
skipped="$workdir/skipped"
: >"$targets"
: >"$skipped"

while read -r pid ppid comm rest; do
  [ -n "${pid:-}" ] || continue
  is_llm_comm "$comm" || continue
  if is_excluded_cmd "$rest"; then
    echo "$pid $comm (app-helper)" >>"$skipped"
    continue
  fi
  if is_keep "$pid"; then
    echo "$pid $comm (this-session)" >>"$skipped"
    continue
  fi
  echo "$pid" >>"$targets"
done <"$workdir/ps"

target_count=$(grep -c . "$targets" 2>/dev/null || true)
[ -n "$target_count" ] || target_count=0

echo "══ leave-mac ════════════════════════════════"
echo "dry-run:  $dry_run   reboot: $do_reboot   ship: $do_ship"
if [ -n "$this_grok" ]; then
  echo "self grok: $this_grok"
else
  echo "self grok: (none — plain shell)"
fi
echo "LLM CLIs to close: $target_count"
if [ -s "$targets" ]; then
  while read -r pid; do
    echo "  TERM $pid $(comm_of "$pid")  $(cmd_of "$pid")"
  done <"$targets"
fi
if [ -s "$skipped" ]; then
  echo "kept/skipped:"
  sed 's/^/  /' "$skipped"
fi

if [ -s "$targets" ]; then
  while read -r pid; do
    emit_kill TERM "$pid"
  done <"$targets"
fi

if [ -s "$targets" ] && [ "$dry_run" -eq 0 ] && [ -z "${LEAVE_MAC_KILL_LOG:-}" ]; then
  slept=0
  while [ "$slept" -lt "$WAIT_SECS" ]; do
    alive=0
    while read -r pid; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        break
      fi
    done <"$targets"
    [ "$alive" -eq 0 ] && break
    sleep 1
    slept=$((slept + 1))
  done
  leftover=0
  while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "still running after SIGTERM: $pid $(comm_of "$pid") (left for reboot/OS; no SIGKILL)"
      leftover=1
    fi
  done <"$targets"
  if [ "$leftover" -eq 0 ]; then
    echo "LLM CLIs: all SIGTERM targets exited"
  fi
fi

if [ "$do_ship" -eq 1 ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "DRY-RUN ship: $DEVSYNC status && $DEVSYNC ship"
  else
    echo "git: $DEVSYNC status && ship"
    "$DEVSYNC" status
    "$DEVSYNC" ship
  fi
else
  echo "git: skipped (--no-ship)"
fi

echo "session files stay on disk (~/.grok/sessions, ~/.claude, ~/.codex)."
echo "not deleted, not memory-cleared."

if [ "$do_reboot" -eq 1 ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "DRY-RUN reboot: System Events restart"
  else
    echo "restarting this Mac"
    osascript -e 'tell application "System Events" to restart'
  fi
else
  echo "this Grok stays up. /quit here if you also want this session closed."
fi
echo "════════════════════════════════════════════"
