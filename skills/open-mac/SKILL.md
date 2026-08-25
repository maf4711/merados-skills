---
name: open-mac
description: Use when the user says /open-mac, open-mac, leave-mac, Mac aufmachen, Mac zuklappen, anderen Mac, zweiter Mac, Repos syncen, vor dem arbeiten syncen, Arbeit rüberschieben, auto-sync.
---

# open-mac

Lifecycle für mehrere Macs. GitHub ist die einzige Wahrheit.

**REQUIRED SUB-SKILL:** `repo-sync`. OPEN/LEAVE = `devsync.sh sync` / `ship` (Commit ohne Secrets, Merge, Push). LaunchAgent committet nicht.

```bash
~/.claude/skills/repo-sync/devsync.sh status
~/.claude/skills/repo-sync/devsync.sh sync    # OPEN / alles rauf
~/.claude/skills/repo-sync/devsync.sh ship    # LEAVE
```

Nicht fragen, nicht ff-only, nicht rebase, nicht force-push. Secrets nie committen.
