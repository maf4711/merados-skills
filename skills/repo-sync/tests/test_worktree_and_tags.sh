#!/usr/bin/env bash
# Linked worktrees are not separate repos. A tag that already exists on
# origin must not fail a branch push and must not be force-updated.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEVSYNC="$HERE/devsync.sh"
TMP=$(mktemp -d /tmp/devsync-wt-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

git init -q --bare "$TMP/origin.git"
git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/main
git init -q "$TMP/main"
git -C "$TMP/main" config user.email t@t
git -C "$TMP/main" config user.name t
git -C "$TMP/main" remote add origin "$TMP/origin.git"
echo a >"$TMP/main/README"
git -C "$TMP/main" add README
git -C "$TMP/main" commit -q -m a
git -C "$TMP/main" branch -M main
git -C "$TMP/main" push -q -u origin HEAD
git -C "$TMP/main" tag v1.0.0
git -C "$TMP/main" push -q origin v1.0.0

# Move the local tag. The remote tag stays. No force.
git -C "$TMP/main" tag -d v1.0.0 >/dev/null
echo b >"$TMP/main/README"
git -C "$TMP/main" commit -q -am b
git -C "$TMP/main" tag v1.0.0

DEV="$TMP/Developer"
mkdir -p "$DEV"
git clone -q "$TMP/origin.git" "$DEV/widget"
git -C "$DEV/widget" config user.email t@t
git -C "$DEV/widget" config user.name t
git -C "$DEV/widget" fetch -q origin tag v1.0.0
git -C "$DEV/widget" worktree add --detach "$DEV/widget-wt" HEAD
echo scratch >"$DEV/widget-wt/scratch.txt"

export DEVSYNC_ROOT="$DEV"
export DEVSYNC_OWNERS="nobody"
export DEVSYNC_JOBS=1
export PATH="/usr/bin:/bin:$PATH"

status_out=$("$DEVSYNC" status 2>&1 || true)
echo "$status_out" | grep -q 'widget-wt' && {
  echo "FAIL: status listed linked worktree"
  echo "$status_out"
  exit 1
}

# Ship the checkout whose local tag moved. Remote tag must stay put.
git -C "$DEV/widget" worktree remove --force "$DEV/widget-wt"
rm -rf "$DEV/widget"
git clone -q "$TMP/main" "$DEV/widget"
git -C "$DEV/widget" remote set-url origin "$TMP/origin.git"
ship_out=$("$DEVSYNC" ship 2>&1 || true)
echo "$ship_out"
echo "$ship_out" | grep -q 'Push abgelehnt' && {
  echo "FAIL: colliding tag reported as a rejected push"
  exit 1
}
echo "$ship_out" | grep -q 'Tags kollidieren' || {
  echo "FAIL: expected tag-collision warning"
  exit 1
}
remote_tag=$(git -C "$TMP/origin.git" rev-parse v1.0.0^{commit})
moved_tag=$(git -C "$TMP/main" rev-parse v1.0.0^{commit})
if [ "$remote_tag" = "$moved_tag" ]; then
  echo "FAIL: remote tag was force-moved"
  exit 1
fi
echo "OK worktree skipped and tag not forced"
