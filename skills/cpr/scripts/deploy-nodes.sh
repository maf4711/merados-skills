#!/usr/bin/env bash
# cprd — roll the released Skill-Suite onto every available cluster node.
#
# Usage: deploy-nodes.sh [--repo DIR] [--cluster FILE] [--dry-run]
#
# For every node in ~/.config/maccluster/cluster.toml (except this machine):
#   ssh <node> 'cd <repo> && git fetch --tags && git pull --ff-only origin <branch> && ./install.sh'
# then compares the node's tag/HEAD with the local one. Also runs install.sh locally.
# Unreachable nodes are NAMED in the result, never skipped silently.
# Exit 0 only when every reachable node reports the local HEAD.
set -u

REPO="${REPO_DIR:-$HOME/Developer/Skill-Suite}"
CLUSTER="${CLUSTER_TOML:-$HOME/.config/maccluster/cluster.toml}"
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --cluster) CLUSTER="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$REPO/.git" ] || { echo "no git repo at $REPO" >&2; exit 2; }
[ -f "$CLUSTER" ] || { echo "no cluster file at $CLUSTER" >&2; exit 2; }

REL_REPO="${REPO/#$HOME\//}"           # path relative to $HOME, reused on peers
BRANCH="$(git -C "$REPO" branch --show-current)"
LOCAL_HEAD="$(git -C "$REPO" rev-parse --short HEAD)"
LOCAL_TAG="$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || echo none)"

# own addresses → skip self; own bridge IP → explicit BindAddress (the generated
# ~/.ssh/config.d/maccluster may still carry the bind IP of the node that wrote it)
MY_IPS="$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | tr '\n' ' ')"
BIND_IP="$(ifconfig bridge0 2>/dev/null | awk '/inet /{print $2}' | head -1)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
[ -n "$BIND_IP" ] && SSH_OPTS+=(-o "BindAddress=$BIND_IP")

# id<TAB>ip<TAB>ssh_target  (ssh_target falls back to ip)
NODES="$(python3 - "$CLUSTER" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
for n in cfg.get("nodes", []):
    print(f'{n.get("id","?")}\t{n.get("ip","")}\t{n.get("ssh_target") or n.get("ip","")}')
PY
)"

echo "cprd: $REPO @ $LOCAL_HEAD ($LOCAL_TAG) branch=$BRANCH"
echo "local: $(cd "$REPO" && ./install.sh 2>&1 | grep -E '^done' || echo 'install.sh failed')"

REMOTE_CMD="cd \"\$HOME/$REL_REPO\" 2>/dev/null || { echo NOREPO; exit 3; }
git fetch --tags origin >/dev/null 2>&1 || { echo FETCHFAIL; exit 4; }
git pull --ff-only origin $BRANCH >/dev/null 2>&1 || { echo PULLFAIL; exit 5; }
./install.sh >/dev/null 2>&1 || { echo INSTALLFAIL; exit 6; }
echo \"OK \$(git rev-parse --short HEAD) \$(git describe --tags --abbrev=0 2>/dev/null || echo none) \$(hostname)\""

fail=0; rows=()
while IFS=$'\t' read -r id ip target; do
  [ -z "$id" ] && continue
  if [[ " $MY_IPS " == *" $ip "* ]]; then
    rows+=("$id|$ip|self|$LOCAL_HEAD|$LOCAL_TAG|installed locally"); continue
  fi
  if [ "$DRY" = 1 ]; then rows+=("$id|$ip|dry-run|-|-|would run on $target"); continue; fi
  out="$(ssh "${SSH_OPTS[@]}" "$target" "$REMOTE_CMD" 2>&1)"; rc=$?
  last="$(printf '%s\n' "$out" | tail -1)"
  case "$last" in
    OK*)
      set -- $last; head="$2"; tag="$3"; host="$4"
      if [ "$head" = "$LOCAL_HEAD" ]; then rows+=("$id|$ip|ok|$head|$tag|$host")
      else rows+=("$id|$ip|MISMATCH|$head|$tag|$host (local $LOCAL_HEAD)"); fail=1; fi ;;
    NOREPO|FETCHFAIL|PULLFAIL|INSTALLFAIL)
      rows+=("$id|$ip|FAILED|-|-|$last"); fail=1 ;;
    *)
      rows+=("$id|$ip|UNREACHABLE|-|-|$(printf '%s' "$last" | cut -c1-70)"); fail=1 ;;
  esac
done <<< "$NODES"

echo
printf '%-8s %-12s %-12s %-9s %-9s %s\n' node ip state head tag note
for r in "${rows[@]}"; do IFS='|' read -r a b c d e f <<< "$r"; printf '%-8s %-12s %-12s %-9s %-9s %s\n' "$a" "$b" "$c" "$d" "$e" "$f"; done
exit $fail
