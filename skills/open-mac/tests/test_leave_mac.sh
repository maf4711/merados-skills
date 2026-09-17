#!/usr/bin/env bash
# Inventory + SIGTERM targeting for leave-mac.sh (no live processes).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/leave-mac.sh"
TMP=$(mktemp -d /tmp/leave-mac-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/ps" <<'EOF'
    1     0 launchd /sbin/launchd
   10     1 ghostty /Applications/Ghostty.app/Contents/MacOS/ghostty
   20    10 zsh -zsh
  100    20 grok grok
  200   100 zsh /bin/zsh -c tool
   30    10 zsh -zsh
  300    30 grok grok
  400     1 grok grok
  500     1 claude claude
  600     1 codex /Applications/ChatGPT.app/Contents/Resources/codex app-server
  700     1 python3 /Users/a321/Developer/dotfiles/grok/hooks/cpu-guard.py
EOF

cat >"$TMP/devsync" <<'EOF'
#!/bin/sh
echo "devsync $*" >>"${LEAVE_MAC_SHIP_LOG:?}"
EOF
chmod +x "$TMP/devsync" "$SCRIPT"

run() {
  LEAVE_MAC_PS_FILE="$TMP/ps" \
  LEAVE_MAC_SELF_PID=200 \
  LEAVE_MAC_DEVSYNC="$TMP/devsync" \
  LEAVE_MAC_SHIP_LOG="$TMP/ship.log" \
  LEAVE_MAC_KILL_LOG="$TMP/kill.log" \
  LEAVE_MAC_WAIT_SECS=0 \
    "$SCRIPT" "$@"
}

: >"$TMP/kill.log"
: >"$TMP/ship.log"
out=$(run --no-ship)
echo "$out"

echo "$out" | grep -q 'self grok: 100' || { echo FAIL: self grok; exit 1; }
echo "$out" | grep -q 'TERM 300 grok' || { echo FAIL: missing sibling grok 300; exit 1; }
echo "$out" | grep -q 'TERM 400 grok' || { echo FAIL: missing other grok 400; exit 1; }
echo "$out" | grep -q 'TERM 500 claude' || { echo FAIL: missing claude; exit 1; }
echo "$out" | grep -q 'TERM 100 ' && { echo FAIL: SIGTERM self grok; exit 1; }
echo "$out" | grep -q 'TERM 600 ' && { echo FAIL: SIGTERM ChatGPT helper; exit 1; }
echo "$out" | grep -q 'TERM 700 ' && { echo FAIL: SIGTERM cpu-guard; exit 1; }
echo "$out" | grep -q '600 codex (app-helper)' || { echo FAIL: ChatGPT not skipped; exit 1; }

printf '%s\n' "TERM 300" "TERM 400" "TERM 500" | sort >"$TMP/want"
sort "$TMP/kill.log" | uniq >"$TMP/got"
cmp -s "$TMP/want" "$TMP/got" || {
  echo FAIL: kill log
  echo want:; cat "$TMP/want"
  echo got:; cat "$TMP/got"
  exit 1
}
grep -q . "$TMP/ship.log" && { echo FAIL: ship ran with --no-ship; exit 1; }

: >"$TMP/kill.log"
: >"$TMP/ship.log"
out=$(run --dry-run)
echo "$out" | grep -q 'DRY-RUN kill -TERM 300' || { echo FAIL: dry-run kill; exit 1; }
echo "$out" | grep -q 'DRY-RUN ship:' || { echo FAIL: dry-run ship; exit 1; }
grep -q . "$TMP/kill.log" && { echo FAIL: dry-run wrote kill log; exit 1; }
grep -q . "$TMP/ship.log" && { echo FAIL: dry-run shipped; exit 1; }

: >"$TMP/kill.log"
: >"$TMP/ship.log"
out=$(run --no-ship --include-self)
echo "$out" | grep -q 'TERM 100 grok' || { echo FAIL: include-self missed 100; exit 1; }
grep -q 'TERM 100' "$TMP/kill.log" || { echo FAIL: include-self kill log; exit 1; }

: >"$TMP/kill.log"
: >"$TMP/ship.log"
out=$(run --dry-run --reboot)
echo "$out" | grep -q 'DRY-RUN reboot' || { echo FAIL: dry-run reboot; exit 1; }

echo OK leave-mac targeting
