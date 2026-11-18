#!/usr/bin/env bash
# The 120 s auto-sync loop must not start a `git fsmonitor--daemon` per repo.
# Regression 2026-11-18: 260 daemons, load ~170 on 14 cores.
# Asserts with `git fsmonitor--daemon status` (exit != 0 = not running).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEVSYNC="$HERE/devsync.sh"
AUTOSYNC="$HERE/auto-sync.sh"

if ! git version --build-options 2>/dev/null | grep -q 'fsmonitor--daemon'; then
  echo "SKIP unsupported"
  exit 0
fi

TMP=$(mktemp -d /tmp/devsync-fsm-XXXXXX)
DEV="$TMP/dev root"
R1="$DEV/r1"
R2="$DEV/r2"
WT="$DEV/r1-wt"

cleanup() {
  local p
  for p in "$R1" "$WT" "$R2"; do
    [ -d "$p" ] && git -C "$p" fsmonitor--daemon stop >/dev/null 2>&1 || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

# Own global config: the user's core.fsmonitor=true must not start daemons
# for the fixture during setup. The global file itself is never touched.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@t
git config --global user.name t
git config --global init.defaultBranch main

mkdir -p "$DEV" "$TMP/bin" "$TMP/log"
for n in r1 r2; do
  git init -q --bare "$TMP/$n.git"
  git -C "$TMP/$n.git" symbolic-ref HEAD refs/heads/main
  git init -q "$DEV/$n"
  echo a >"$DEV/$n/README"
  git -C "$DEV/$n" add README
  git -C "$DEV/$n" commit -q -m a
  git -C "$DEV/$n" remote add origin "$TMP/$n.git"
  git -C "$DEV/$n" push -q -u origin main
done
git -C "$R1" worktree add -q -b wt "$WT"
git -C "$R1" config core.fsmonitor true
git -C "$R2" config core.fsmonitor true

running() { git -C "$1" fsmonitor--daemon status >/dev/null 2>&1; }

# r2: daemon already running before the loop → must stay as it is.
git -C "$R2" fsmonitor--daemon start >/dev/null
running "$R2" || { echo "FAIL: could not start daemon for r2"; exit 1; }
r2_pid_before=$(git -C "$R2" fsmonitor--daemon status 2>&1 || true)

printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
# Hermetic: never reach the real mos nodes. The stub leaves a marker.
printf '#!/bin/sh\ntouch "%s"\nexit 255\n' "$TMP/ssh-called" >"$TMP/bin/ssh"
chmod +x "$TMP/bin/ssh"
export PATH="$TMP/bin:$PATH"
export DEVSYNC_ROOT="$DEV"
export DEVSYNC_OWNERS="ownerA"
export DEVSYNC_JOBS=2

assert_none() {
  local label="$1" p
  sleep 1
  for p in "$R1" "$WT"; do
    if running "$p"; then
      echo "FAIL: $label started fsmonitor daemon for $p"
      tail -20 "$TMP/log/auto-sync.log" 2>/dev/null || true
      exit 1
    fi
  done
  running "$R2" || { echo "FAIL: $label stopped the pre-existing r2 daemon"; exit 1; }
  [ "$(git -C "$R2" fsmonitor--daemon status 2>&1 || true)" = "$r2_pid_before" ] \
    || { echo "FAIL: $label changed the r2 daemon"; exit 1; }
}

# (a) auto-sync: push + pull + status loop, no node pushes.
DEVSYNC_BIN="$DEVSYNC" DEVSYNC_LOG_DIR="$TMP/log" DEVSYNC_HOLD="$TMP/no.hold" \
  DEVSYNC_NODES="" bash "$AUTOSYNC"
if [ -e "$TMP/ssh-called" ]; then
  echo "FAIL: DEVSYNC_NODES=\"\" did not disable node pushes"
  exit 1
fi
grep -q 'result: dirty=0 unpushed=0' "$TMP/log/auto-sync.log" || {
  echo "FAIL: auto-sync status loop did not run"
  cat "$TMP/log/auto-sync.log"
  exit 1
}
assert_none "auto-sync"
echo "OK fsmonitor-off auto-sync"

# (b) devsync status on the same root.
bash "$DEVSYNC" status >/dev/null 2>&1
assert_none "devsync status"
echo "OK fsmonitor-off devsync"

# (c) control: plain git status with core.fsmonitor=true starts a daemon.
git -C "$R1" status --porcelain >/dev/null
sleep 1
running "$R1" || { echo "FAIL: control – fixture cannot start a daemon"; exit 1; }
echo "OK fsmonitor-off control"
