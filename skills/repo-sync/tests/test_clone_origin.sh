#!/usr/bin/env bash
# Prove clone/status match GitHub origin, not folder basename.
# Regression: same-name remotes (maf4711/foo + MeradosUG/foo) were skipped.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEVSYNC="$HERE/devsync.sh"
TMP=$(mktemp -d /tmp/devsync-clone-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

DEV="$TMP/Developer"
mkdir -p "$DEV" "$TMP/bin" "$TMP/bA" "$TMP/bB"

git -C "$TMP/bA" init -q --bare
git -C "$TMP/bB" init -q --bare
work=$(mktemp -d /tmp/devsync-work-XXXXXX)
git -C "$work" init -q
git -C "$work" config user.email t@t
git -C "$work" config user.name t
echo A >"$work/README"
git -C "$work" add README
git -C "$work" commit -q -m a
git -C "$work" branch -M main
git -C "$work" remote add origin "$TMP/bA"
git -C "$work" push -q origin HEAD:main
echo B >"$work/README"
git -C "$work" commit -q -am b
git -C "$work" remote set-url origin "$TMP/bB"
git -C "$work" push -q origin HEAD:main
rm -rf "$work"

# Local checkout of ownerA/foo occupying the basename.
git clone -q "$TMP/bA" "$DEV/foo"
git -C "$DEV/foo" remote set-url origin "git@github.com:ownerA/foo.git"

cat >"$TMP/bin/gh" <<'EOF'
#!/bin/sh
# $1=repo $2=list $3=<owner>
owner="$3"
case "$owner" in
  ownerA) printf '%s\n' "ownerA/foo	BARE_A" ;;
  ownerB) printf '%s\n' "ownerB/foo	BARE_B" ;;
esac
EOF
chmod +x "$TMP/bin/gh"
sed -i '' -e "s|BARE_A|$TMP/bA|" -e "s|BARE_B|$TMP/bB|" "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export DEVSYNC_ROOT="$DEV"
export DEVSYNC_OWNERS="ownerA ownerB"
export DEVSYNC_JOBS=2

status_out=$("$DEVSYNC" status 2>&1 || true)
echo "$status_out"
echo "$status_out" | grep -q 'ownerB/foo' || {
  echo "FAIL: status hid ownerB/foo because $DEV/foo exists"
  exit 1
}

"$DEVSYNC" clone
if [ ! -d "$DEV/ownerB--foo/.git" ]; then
  echo "FAIL: expected collision clone at $DEV/ownerB--foo"
  ls -la "$DEV"
  exit 1
fi
got=$(git -C "$DEV/ownerB--foo" remote get-url origin)
echo "$got" | grep -q "$TMP/bB" || {
  echo "FAIL: ownerB--foo origin is $got"
  exit 1
}

# Second clone is idempotent.
"$DEVSYNC" clone
count=$(find "$DEV" -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "OK clone-by-origin ($count dirs under DEV)"
