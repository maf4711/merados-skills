---
name: open-mac
description: Use when the user says /open-mac, open-mac, leave-mac, Mac aufmachen, Mac zuklappen, booten, reboot, LLM sessions beenden, Grok/Claude/Codex Sessions schliessen, anderen Mac, zweiter Mac, Repos syncen, vor dem arbeiten syncen, Arbeit rüberschieben, auto-sync.
---

# open-mac

Lifecycle für mehrere Macs. GitHub ist die einzige Wahrheit.

**REQUIRED SUB-SKILL:** `repo-sync`.

- **OPEN:** `devsync.sh status && sync`
- **LEAVE:** `~/.claude/skills/open-mac/leave-mac.sh` — SIGTERM andere grok/claude/codex CLIs, dann `ship`. Session-Dateien bleiben. Kein SIGKILL, kein `sessions delete`.
- **REBOOT:** dasselbe mit `--reboot` nur wenn der User booten/reboot gesagt hat.

LaunchAgent committet nicht. Secrets nie committen. Nicht fragen, nicht ff-only, nicht rebase, nicht force-push.
