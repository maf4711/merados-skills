---
name: cpr
description: Use when the user says cpr, /cpr, mcpr, /mcpr, mcprt, /mcprt, crpa, /crpa, merge cpr, merge and cpr, commit push release, commit+push+release, Skill Suite CPR, or CPR Skill Suite.
---

# cpr / mcpr / mcprt / crpa

Not a question. Run the matching row. Do not ask whether to push or release.

| Token | Means | TestFlight |
|---|---|---|
| **cpr** | commit + merge `origin` + push + production release | no |
| **mcpr** | merge the open PR (or current branch) into the production branch, then **cpr** | no |
| **mcprt** | **mcpr** + TestFlight (`intern` + `Extern`) | yes |
| **crpa** | **cpr** + release rolled out to **every cluster member** (see below) | no |

Aliases: `merge cpr` / `merge and cpr` → **mcpr**. `merge cpr tf` / `cpr tf` / `ship including TestFlight` → **mcprt**. `maccluster-castle` → **crpa**.

**REQUIRED SUB-SKILL:** `repo-sync` for multi-repo / `~/Developer` ship. `git-commit` for message shape. TestFlight details: this file + `testflight`.

Canonical copy: `~/Developer/Skill-Suite/skills/cpr/SKILL.md`. Copy public subset to `~/Developer/merados-skills/skills/cpr/`. Keep `~/.grok/skills/cpr` a **symlink** (never a real copy).

## Sequence

1. **Merge (mcpr / mcprt only)** — if an open PR carries this work: `gh pr merge --squash --delete-branch`. Then `git fetch` and `git merge --no-edit origin/<production-branch>`. Not rebase, not ff-only. Never force-push main.
2. **Commit** — conventional message, no `--no-verify`, no force, no amend of published commits. Skip `.env`, `*.pem` / `*.p8` / `*.key`, `AuthKey_*.p8`, `credentials.json`, `secrets.json`, xcarchive/`.build`. For „alles was lokal liegt“: `devsync.sh ship`. Single-repo: stage the intended paths, not unrelated dumps.
3. **Merge origin** — `git fetch` then `git merge --no-edit origin/<branch>`. Same rules as step 1.
4. **Push** — current branch + tags to `origin`. If rejected: merge again, push again.
5. **Release** — production, not preview, not simulator:
   - **Skill-Suite** (`MeradosUG/Skill-Suite`): save skills here, bump `CHANGELOG.md`, `python3 scripts/generate_index.py`, commit, merge, push, `gh release create vX.Y.Z`, then `./install.sh`.
   - **merados-skills** (`maf4711/merados-skills`): same ship for the npx-public subset.
   - **Web/API** (Vercel): `npx vercel deploy --prod --yes --scope merad-os` so `alpha.merados.com` moves. Confirm the alias, then smoke the changed endpoint.
6. **TestFlight (mcprt only)** — iOS / `ios-native/`. Next build = latest App Store Connect version + 1. Then `./scripts/release-ios.sh --build-number N`. Internal group is `intern` (all builds); `push-beta.sh` adds to `Extern`. There is no group named `Beta`. **cpr** and **mcpr** stop after production web/suite release.

## crpa — cluster rollout (maccluster & friends)

After the normal **cpr** release, roll the release onto every cluster member. User definition 2026-08-29.

1. Local: `./install.sh`, then `maccluster --version` must equal the released tag.
2. For every `role=peer` node in `~/.config/maccluster/cluster.toml`:
   `MACCLUSTER_SRC=~/Developer/maccluster maccluster remote-install <peer-ip>`
   — `MACCLUSTER_SRC` is mandatory: without it the wheel is built from the stale
   fabrik overlay checkout (`~/Developer/fabrik/projects/maccluster`,
   maf4711/maccluster#15) and ships wrong code under a higher version number.
3. Verify per node over the TB bridge: `ssh <peer> 'maccluster --version'` must
   equal the released version.
4. Unreachable members (no TB link, powered off) are **named in the result**,
   never silently skipped.

## Skill Suite + CPR Skill Suite

Publishing a skill **is** CPR of both suites:

1. Write `~/Developer/Skill-Suite/skills/<name>/` (canonical).
2. Copy public/runtime skills that merados-skills ships (`repo-sync`, `cpr`, …) into `~/Developer/merados-skills/skills/<name>/`.
3. CHANGELOG + INDEX in Skill-Suite.
4. `devsync.sh ship` (or commit/merge/push each suite).
5. GitHub Release from CHANGELOG tag (`devsync` `suite_release` does this for those two remotes).
6. `~/Developer/Skill-Suite/install.sh` so `~/.claude`, `~/.grok`, `~/.agents`, `~/.codex` point at the suite.

## alpha-merados TestFlight (mcprt — what actually works)

- ASC key: `~/.appstoreconnect/private_keys/AuthKey_WA46CWAG8B.p8` (issuer in `ios-native/scripts/archive.sh`).
- Homebrew `rsync` 3.5 breaks `exportArchive`. Export with `PATH` putting `/usr/bin` first. Then `asc.py` needs PyJWT (`/Users/a321/kubera-venv/bin` **after** export, or call that `python3` explicitly).
- **Xcode beta cannot upload** (App Store Connect 90534). Need Release/RC Xcode at `/Applications/Xcode.app`. If only beta: still commit + push + Vercel; say TestFlight is blocked. Do not call the simulator the release.
- Query ASC for the next build number; do not trust `project.yml`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After `xcodegen`, restore `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"` if it froze to a literal. Keep `ITSAppUsesNonExemptEncryption` in `project.yml` and Info.plist.

## Done when

- Commit is on the remote (merge completed or conflict reported, never silent skip).
- Skill Suite: tag + GitHub Release + `install.sh` if this was a skill publish.
- Production URL serves the change when the repo is a web/API app (verified).
- **mcprt only:** TestFlight has the new build in `intern`+`Extern`, **or** TestFlight is blocked by a stated Xcode/ASC error.
- **crpa only:** every reachable cluster member reports the released version; unreachable members are named.
