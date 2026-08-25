---
name: cpr
description: Use when the user says cpr, /cpr, commit push release, commit+push+release, ship including TestFlight, Skill Suite CPR, CPR Skill Suite, or wants commit then merge then push then release in one go.
---

# cpr

`cpr` = **commit + merge + push + release**. Not a question. Run all of them.

**REQUIRED SUB-SKILL:** `repo-sync` for multi-repo / `~/Developer` ship. `git-commit` for message shape.

## Sequence

1. **Commit** — conventional message, no `--no-verify`, no force, no amend of published commits. Skip `.env`, `*.pem` / `*.p8` / `*.key`, `AuthKey_*.p8`, `credentials.json`, `secrets.json`, xcarchive/`.build`. For „alles was lokal liegt“: `devsync.sh ship`. Single-repo: stage the intended paths, not unrelated dumps.
2. **Merge** — `git fetch` then `git merge --no-edit origin/<branch>`. Not rebase, not ff-only. Never force-push main.
3. **Push** — current branch + tags to `origin`. If rejected: merge again, push again.
4. **Release** — production, not preview, not simulator:
   - **Skill-Suite** (`MeradosUG/Skill-Suite`): save skills here, bump `CHANGELOG.md`, `python3 scripts/generate_index.py`, commit, merge, push, `gh release create vX.Y.Z`, then `./install.sh`.
   - **merados-skills** (`maf4711/merados-skills`): same ship for the npx-public subset.
   - **Web/API** (Vercel): `npx vercel deploy --prod --yes --scope merad-os` so `alpha.merados.com` moves. Confirm the alias, then smoke the changed endpoint.
   - **iOS** (`ios-native/`): TestFlight. Next build = latest App Store Connect version + 1. Then `./scripts/release-ios.sh --build-number N`. Internal group is `intern`; `push-beta.sh` adds to `Extern`. There is no group named `Beta`.

## Skill Suite + CPR Skill Suite

Publishing a skill **is** CPR of both suites:

1. Write `~/Developer/Skill-Suite/skills/<name>/` (canonical).
2. Copy public/runtime skills that merados-skills ships (`repo-sync`, `cpr`, …) into `~/Developer/merados-skills/skills/<name>/`.
3. CHANGELOG + INDEX in Skill-Suite.
4. `devsync.sh ship` (or commit/merge/push each suite).
5. GitHub Release from CHANGELOG tag (`devsync` `suite_release` does this for those two remotes).
6. `~/Developer/Skill-Suite/install.sh` so `~/.claude`, `~/.grok`, `~/.agents`, `~/.codex` point at the suite.

Do not leave a real copy in `~/.grok/skills/<name>` that blocks the symlink.

## alpha-merados TestFlight (what actually works)

- ASC key: `~/.appstoreconnect/private_keys/AuthKey_WA46CWAG8B.p8` (issuer in `ios-native/scripts/archive.sh`).
- Homebrew `rsync` 3.5 breaks `exportArchive`. Export with `PATH` putting `/usr/bin` first.
- **Xcode beta cannot upload** (App Store Connect 90534). Need Release/RC Xcode at `/Applications/Xcode.app`. If only beta: still commit + push + Vercel; say TestFlight is blocked. Do not call the simulator the release.
- Query ASC for the next build number; do not trust `project.yml`.
- `asc.py` needs PyJWT (`/Users/a321/kubera-venv/bin/python3` if PATH is `/usr/bin`).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Done when

- Commit is on the remote (merge completed or conflict reported, never silent skip).
- Skill Suite: tag + GitHub Release + `install.sh` if this was a skill publish.
- Production URL serves the change when the repo is a web/API app (verified).
- TestFlight has the new build **or** TestFlight is blocked by a stated Xcode/ASC error.
