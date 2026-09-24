---
name: cpr
description: Use when the user says cpr, /cpr, mcpr, /mcpr, cprt, /cprt, mcprt, /mcprt, crpa, /crpa, merge cpr, merge and cpr, commit push release, commit+push+release, Skill Suite CPR, or CPR Skill Suite.
---

# cpr / cprt / mcpr / mcprt / crpa

Not a question. Run the matching row. Do not ask whether to push or release.

| Token | Means | TestFlight |
|---|---|---|
| **cpr** | commit + merge `origin` + push + production release | no |
| **mcpr** | merge the open PR (or current branch) into the production branch, then **cpr** | no |
| **cprt** | **cpr** + TestFlight for **every iOS app in the release repository** (`intern` + `Extern`) | all iOS apps |
| **mcprt** | **mcpr** + the same complete iOS TestFlight release | all iOS apps |
| **crpa** | **cpr** + release rolled out to **every cluster member** (see below) | no |

Aliases: `merge cpr` / `merge and cpr` → **mcpr**. `merge cpr tf` → **mcprt**. `cpr tf` / `ship including TestFlight` → **cprt**. `maccluster-castle` → **crpa**.

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
6. **TestFlight (cprt / mcprt)** — release **every independent iOS application in the scoped repository**, even if its native source did not change. Discover iOS application targets and validate the release manifest against them before uploads; never silently ship only the default scheme. App extensions, test bundles and embedded watch companions are not separate iOS apps; archive them with their owning app. tvOS, visionOS and unrelated repositories are outside this default unless requested.
   - Use each app’s own scheme, bundle ID and App Store Connect app ID. Query that app’s iOS builds and choose its highest numeric build number + 1; API errors must stop that app, not fall back to a local number. Never reuse one app’s number/identity across all apps.
   - Prefer a repository multi-app entry point. In alpha-merados: `./scripts/release-ios.sh --submit-review` releases AlphaMerados and MeradosAnalysis. `--app <scheme>` is for an explicitly requested subset or retrying a named failed app; it does not satisfy the full cprt by itself. Do not pass a global `--build-number` to an all-app release.
   - Process archives sequentially when sharing generated Xcode project/build paths. Continue/report independent apps if one fails; return failure until every requested app is accounted for.
   - Verify VALID processing, export compliance, localized test notes and membership/access in both `intern` and `Extern` for every app. `intern` may have automatic access to all builds. There is no group named `Beta`. Submit a required TestFlight beta review as part of the authorized external release; do not publish to the live App Store. Distinguish group assignment, review pending and actual `IN_BETA_TESTING`.
   - **cpr** and **mcpr** stop after production web/suite release.

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

## alpha-merados TestFlight (cprt / mcprt — all iOS apps)

- Required app inventory: `AlphaMerados` / `com.merados.alpha` / ASC `6762538440`; `MeradosAnalysis` / `com.merados.analysis` / ASC `6804377601`. Keep the repository manifest and iOS targets in sync.
- ASC key: `~/.appstoreconnect/private_keys/AuthKey_WA46CWAG8B.p8` (issuer in `ios-native/scripts/archive.sh`).
- Homebrew `rsync` 3.5 breaks `exportArchive`. Export with `PATH` putting `/usr/bin` first. `asc.py` needs a Python interpreter with PyJWT; verify the installed interpreter instead of assuming a machine-specific virtualenv path.
- **Xcode beta cannot upload** (App Store Connect 90534). Need Release/RC Xcode at `/Applications/Xcode.app`. If only beta: still commit + push + Vercel; say TestFlight is blocked. Do not call the simulator the release.
- Query ASC for the next build number; do not trust `project.yml`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After `xcodegen`, restore `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"` if it froze to a literal. Keep `ITSAppUsesNonExemptEncryption` in `project.yml` and Info.plist.

## Done when

- Commit is on the remote (merge completed or conflict reported, never silent skip).
- Skill Suite: tag + GitHub Release + `install.sh` if this was a skill publish.
- Production URL serves the change when the repo is a web/API app (verified).
- **cprt / mcprt:** report one row per discovered iOS app: bundle, build number, upload/processing, internal state and external state. No all-app success if an app was omitted or failed. Pending Apple review is explicitly pending, not available. A named Xcode/ASC blocker must identify the affected app; successful sibling releases remain reported.
- **crpa only:** every reachable cluster member reports the released version; unreachable members are named.
