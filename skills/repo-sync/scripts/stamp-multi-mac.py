#!/usr/bin/env python3
"""Write MULTI-MAC.md into every owned ~/Developer repo.

The file is the checkout and release contract for any Mac. It names key
paths and public identifiers. It never contains key material.

  python3 stamp-multi-mac.py            # dry-run
  python3 stamp-multi-mac.py --write    # write, git add, commit that file
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

DEV = Path.home() / "Developer"
OWNERS = {"maf4711", "meradosug", "finfuxug"}
ORG_SLUG = {
    "team_IUxcUMLFPZ8priEjxQQhELMV": "merad-os",
    "team_5jCZvKWdsJFJEjzTthY1ZcLA": "marco-3586s-projects",
}
COMMIT_MSG = """docs(multi-mac): edit and release this repo from any Mac

MULTI-MAC.md records the GitHub remote, the release command, and the shared
Apple, Vercel, and devsync facts required on every Mac.
"""


def git(repo: Path, *args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=check,
        capture_output=True,
        text=True,
    )


def nwo_of(url: str) -> tuple[str, str] | None:
    raw = url.strip()
    for prefix in (
        "git@github.com:",
        "ssh://git@github.com/",
        "https://github.com/",
        "http://github.com/",
    ):
        if raw.startswith(prefix):
            raw = raw[len(prefix) :]
            break
    else:
        return None
    if raw.endswith(".git"):
        raw = raw[:-4]
    if "/" not in raw:
        return None
    owner, name = raw.split("/", 1)
    return owner, name


def local_repos() -> list[Path]:
    repos = [p for p in sorted(DEV.iterdir()) if (p / ".git").exists()]
    extra = DEV / "meradOS" / "Skill-Suite"
    if (extra / ".git").exists() and extra not in repos:
        repos.append(extra)
    return repos


def branch_of(repo: Path) -> str:
    proc = git(repo, "branch", "--show-current")
    return proc.stdout.strip() or "DETACHED"


def default_branch(repo: Path) -> str:
    proc = git(repo, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
    name = proc.stdout.strip()
    if name.startswith("origin/"):
        return name.split("/", 1)[1]
    for candidate in ("main", "master"):
        if git(repo, "show-ref", "-q", "--verify", f"refs/heads/{candidate}").returncode == 0:
            return candidate
    return "main"


def busy(repo: Path) -> bool:
    proc = git(repo, "rev-parse", "--git-path", "MERGE_HEAD")
    if proc.returncode == 0 and Path(proc.stdout.strip()).exists() and not proc.stdout.strip().startswith("/"):
        # git-path may be relative to repo
        pass
    markers = ("MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD", "BISECT_LOG")
    git_dir = git(repo, "rev-parse", "--git-dir").stdout.strip()
    base = Path(git_dir)
    if not base.is_absolute():
        base = repo / base
    if any((base / name).exists() for name in markers):
        return True
    if (base / "rebase-merge").is_dir() or (base / "rebase-apply").is_dir():
        return True
    if git(repo, "symbolic-ref", "-q", "HEAD").returncode != 0:
        return True
    return False


def vercel_targets(repo: Path) -> list[Path]:
    found: list[Path] = []
    if (repo / "vercel.json").exists():
        found.append(repo)
    for sub in ("landing", "app", "web", "frontend"):
        candidate = repo / sub
        if (candidate / "vercel.json").exists():
            found.append(candidate)
    return found


def workflow_names(repo: Path) -> list[str]:
    folder = repo / ".github" / "workflows"
    if not folder.is_dir():
        return []
    return sorted(
        path.name
        for path in folder.iterdir()
        if path.suffix in {".yml", ".yaml"} and path.is_file()
    )


def apple_dirs(repo: Path) -> list[str]:
    hits: list[str] = []
    for rel in (".", "ios", "ios-native", "app"):
        base = repo if rel == "." else repo / rel
        if not base.is_dir():
            continue
        if (base / "project.yml").exists() or any(base.glob("*.xcodeproj")):
            hits.append(rel)
    return hits


def release_lines(repo: Path, default: str) -> list[str]:
    lines: list[str] = []
    formula = any((repo / name).is_dir() for name in ("Formula", "formula", "Casks"))
    if (repo / "release.sh").is_file() and formula:
        lines.append(
            "Homebrew: im Repo-Root `./release.sh`. Das Skript liest die Version aus der Quelle, "
            "legt den GitHub-Release-Tag an, pusht `main` und installiert die Formula lokal. "
            "Ein schon veröffentlichter Tag bleibt liegen; dafür zuerst die Version erhöhen. "
            "`cpr` ohne Versionsbump pusht den Branch und schneidet keinen neuen Tag."
        )
    elif (repo / "release.sh").is_file():
        lines.append("Release-Skript im Root: `./release.sh`.")
    if (repo / "ios" / "release.sh").is_file():
        lines.append(
            "iOS-Skript: `cd ios && ./release.sh`. TestFlight gehört zu `mcprt`, nicht zu `cpr`."
        )
    for target in vercel_targets(repo):
        rel = "." if target == repo else str(target.relative_to(repo))
        project = target / ".vercel" / "project.json"
        if project.is_file():
            try:
                meta = json.loads(project.read_text())
            except json.JSONDecodeError:
                meta = {}
            org = str(meta.get("orgId") or "")
            slug = ORG_SLUG.get(org, "unbekannt")
            name = meta.get("projectName") or "unbekannt"
            lines.append(
                f"Vercel: Verzeichnis `{rel}`, Projekt `{name}`, Team-Slug `{slug}` "
                f"(org `{org}`). Production: `vercel deploy --prod --yes --scope {slug}` "
                "in diesem Verzeichnis. `.vercel/` ist lokal; auf einem anderen Mac dasselbe "
                "Projekt mit `vercel link` verbinden."
            )
        else:
            lines.append(
                f"Vercel-Datei `{rel}/vercel.json` ohne `.vercel/project.json` auf diesem Mac. "
                "Vor dem Production-Deploy `vercel link` auf das bestehende Projekt, Scope nicht raten."
            )
    if apple_dirs(repo):
        where = ", ".join(f"`{item}`" for item in apple_dirs(repo))
        lines.append(
            f"Apple-Projekt unter {where}. Archive und Upload mit "
            "`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` und Team "
            "`K63X3ZTV3Q`. TestFlight: `~/.grok/skills/testflight/scripts/ship.sh --dir <checkout>`. "
            "`cpr` stoppt vor TestFlight. `mcprt` liefert die Gruppen `intern` und `Extern`."
        )
    names = workflow_names(repo)
    if names:
        listed = ", ".join(f"`{name}`" for name in names)
        lines.append(f"GitHub Actions: {listed}. Der Default-Branch bleibt der auslieferbare Stand.")
    if (repo / "Package.swift").is_file() and not lines:
        lines.append(
            "Swift-Package. Andere Macs ziehen es über die Git-URL des Default-Branches."
        )
    if not lines:
        lines.append(
            f"Produktion ist der Default-Branch `{default}` auf `origin`. "
            "`devsync.sh ship` (Commit, Merge, Push) ist das Release. "
            "Kein Vercel-, Homebrew- oder TestFlight-Skript im Root erkannt."
        )
    return lines


def contract(repo: Path, owner: str, name: str, folder: str, default: str, remote: str) -> str:
    ssh = f"git@github.com:{owner}/{name}.git"
    rel = "\n".join(f"- {line}" for line in release_lines(repo, default))
    text = f"""# Multi-Mac

Dieses Repo wird auf mehreren Macs bearbeitet und von jedem Mac released, der als `maf4711` bei GitHub angemeldet ist. GitHub ist die einzige Wahrheit. `~/Developer` liegt nicht in iCloud oder Dropbox.

Stand der Fakten: 2026-09-25, aufgenommen auf `mbpM5MaxMF-6.local` (User `a321`). Pfade sind `$HOME`-relativ.

## Dieses Repo

| | |
|---|---|
| GitHub | `{owner}/{name}` |
| SSH | `{ssh}` |
| Remote dieses Checkouts | `{remote}` |
| Ordner | `~/Developer/{folder}` |
| Default-Branch | `{default}` |

### Release

{rel}

Sync dieses Stands auf die anderen Macs:

```bash
~/.claude/skills/repo-sync/devsync.sh ship
```

## Auf einem weiteren Mac bearbeiten

1. `git`, GitHub CLI, SSH-Key. `gh auth login` mit Protokoll SSH. `ssh -T git@github.com` antwortet `Hi maf4711`.
2. Einmal einrichten:

```bash
git clone git@github.com:maf4711/merados-skills.git ~/Developer/merados-skills
bash ~/Developer/merados-skills/skills/repo-sync/setup-mac.sh
```

Das klont `maf4711`, `MeradosUG` und `FinfuxUG` nach `~/Developer`, verlinkt die Skill-Suite nach `~/.claude`, `~/.grok`, `~/.codex` und `~/.agents` und lädt den LaunchAgent `com.merados.devsync`.

3. Dieser Checkout liegt danach unter `~/Developer/{folder}`. Weicht der Ordner vom Repo-Namen ab, weil zwei Orgs denselben Namen haben, heißt er `~/Developer/<owner>--<name>`.
4. Vor und nach der Arbeit: `devsync.sh status`, dann `devsync.sh sync`.
5. Identität: `marco` / `foellmer@mac.com`. Merge mit `git merge --no-edit`, kein Rebase, kein Force-Push.
6. `devsync` committet auf dem Default-Branch nur bereits getrackte Dateien. Neue Dateien vorher `git add`. Feature-Branches, Rebase, Merge und detached HEAD lässt es liegen.

## Von jedem Mac releasen

Gemeinsame Identität. Dateiinhalt der Schlüssel steht hier nicht.

| | |
|---|---|
| GitHub-Login | `maf4711` (Marco Föllmer) |
| Orgs | `maf4711`, `MeradosUG`, `FinfuxUG`. Neue Remotes: `maf4711/<name>`, privat |
| Apple ID | `foellmer@mac.com` |
| Team | `K63X3ZTV3Q` |
| ASC Key-ID | `5BXD2V69GS` |
| ASC Issuer | `18daeaec-9343-4c57-9b01-481a7da981c6` |
| ASC Key-Datei | `~/.appstoreconnect/private_keys/AuthKey_5BXD2V69GS.p8` |
| Weitere Key-Dateien | `AuthKey_DLC56TFN8B.p8`, `AuthKey_AA42M2D5C8.p8`, `AuthKey_QCCHWPHR8X.p8`, `AuthKey_WA46CWAG8B.p8` im selben Ordner |
| Developer ID | `B6EAF16C978F2AC019070F04C3B0C6052ED0342E` (CN ist doppelt; zweites Zertifikat `F588A236CBD8DF58BE4FADEB194F0EDEDBD6EFF4`) |
| Apple Distribution | `B534280F66FFD01FE031AD3E5A648E433ACA070E` |
| Apple Development | `C656D0B3D14E9436C2004CEFB67A47502880287A` |
| Release-Xcode | `/Applications/Xcode.app` (auf dem Aufnahme-Mac Xcode 27.0, Build 27A266a) |
| Ausgewählte Xcode-Beta | `xcode-select` zeigte auf Xcode 27.2 unter `/Applications/Xcode-27.2.0-beta.app`. Upload setzt `DEVELOPER_DIR` auf `/Applications/Xcode.app/Contents/Developer` |
| Vercel-Teams | `merad-os` (`team_IUxcUMLFPZ8priEjxQQhELMV`), `marco-3586s-projects` (`team_5jCZvKWdsJFJEjzTthY1ZcLA`) |
| Homebrew | `/opt/homebrew`. Nach einem Meister-Release `brew update && brew reinstall maf4711/meister/meister` |
| Skill-Suite | Changelog-Tag, `gh release`, dann `~/Developer/Skill-Suite/install.sh` |
| CPR | `cpr` = Commit + Merge `origin` + Push + Production. `mcprt` zusätzlich TestFlight `intern` und `Extern` |

Einmal pro Mac, außerhalb von Git: den Ordner `~/.appstoreconnect/private_keys/` von einem Mac kopieren, der die `.p8`-Dateien schon hat (AirDrop oder `scp`). In Xcode mit `foellmer@mac.com` anmelden, damit Team `K63X3ZTV3Q` im Schlüsselbund liegt. `vercel login` auf beiden Teams.

Export von Archiven: `/usr/bin` vor dem Homebrew-`rsync` im `PATH`.

## Macs

| Maschine | Zugang | Rolle |
|---|---|---|
| `mbpM5MaxMF-6.local` | lokal, User `a321` | Aufnahme-Mac, `~/Developer` |
| `CM-CFMQ2D029F` | Thunderbolt `10.42.0.1` | Cluster node-a |
| `CM-KWFVR7JGW3` | `a321@10.42.0.2` | Cluster node-b |
| `mbpM5MaxMF` | `a321@10.42.0.3` | Cluster node-c |
| `mos1` `mos2` `mos3` `mos4` | SSH, Konten `jmerados1..4` | bekommen den Branch per `devsync` Node-Push. GitHub-Release läuft auf einem Mac mit Login `maf4711` |

`mos1`–`mos4` lesen private GitHub-Repos nicht. Der Code kommt vom Mac mit `maf4711` per fast-forward, ohne `--force`.

## Nie committen

`.env`, `*.p8`, `*.pem`, `*.key`, `AuthKey_*`, `credentials.json`, `secrets.json`, `*.xcarchive`, `.build/`, `DerivedData`.

Neu stempeln: `python3 ~/Developer/Skill-Suite/skills/repo-sync/scripts/stamp-multi-mac.py --write`.
"""
    if "BEGIN PRIVATE KEY" in text or "-----BEGIN" in text:
        raise RuntimeError("refusing to write key material")
    return text


def score(path: Path, branch: str, default: str, repo_name: str) -> tuple[int, int, str]:
    points = 0
    if branch == default:
        points += 100
    if path.name == repo_name:
        points += 40
    if path.parent == DEV:
        points += 20
    if branch != "DETACHED":
        points += 5
    return (points, -len(str(path)), str(path))


def ensure_ssh(repo: Path, owner: str, name: str) -> None:
    ssh = f"git@github.com:{owner}/{name}.git"
    current = git(repo, "remote", "get-url", "origin").stdout.strip()
    parsed = nwo_of(current)
    if parsed is None:
        return
    if current == ssh:
        return
    if parsed[0].lower() not in OWNERS:
        return
    git(repo, "remote", "set-url", "origin", ssh)


def commit_file(repo: Path, path: Path) -> str:
    rel = "MULTI-MAC.md"
    git(repo, "add", "--", rel)
    staged = git(repo, "diff", "--cached", "--name-only", "--", rel).stdout.strip()
    if not staged:
        return "unchanged"
    proc = git(repo, "commit", "-m", COMMIT_MSG)
    if proc.returncode != 0:
        return "commit-failed: " + (proc.stderr or proc.stdout).strip().splitlines()[-1:][0] if (proc.stderr or proc.stdout).strip() else "commit-failed"
    return "committed"


def commit_via_worktree(repo: Path, default: str, body: str) -> str:
    safe = repo.name.replace("/", "-")
    work = Path("/tmp/multi-mac-wt") / safe
    git(repo, "worktree", "remove", "--force", str(work))
    if work.exists():
        return f"worktree-blocked: {work}"
    work.parent.mkdir(parents=True, exist_ok=True)
    local = git(repo, "show-ref", "-q", "--verify", f"refs/heads/{default}")
    if local.returncode == 0:
        add = git(repo, "worktree", "add", str(work), default)
    else:
        fetched = git(repo, "fetch", "--prune", "origin")
        if fetched.returncode != 0:
            return "fetch-failed: " + (fetched.stderr or "").strip().splitlines()[-1:][0]
        add = git(repo, "worktree", "add", "--track", "-b", default, str(work), f"origin/{default}")
    if add.returncode != 0:
        detail = (add.stderr or add.stdout).strip().splitlines()
        return "worktree-failed: " + (detail[-1] if detail else "unknown")
    target = work / "MULTI-MAC.md"
    target.write_text(body)
    result = commit_file(work, target)
    if result != "committed":
        git(repo, "worktree", "remove", "--force", str(work))
        return result
    git(work, "fetch", "--prune", "origin")
    if git(work, "rev-parse", "--verify", f"origin/{default}").returncode == 0:
        merged = git(work, "merge", "--no-edit", f"origin/{default}")
        if merged.returncode != 0:
            git(work, "merge", "--abort")
            git(repo, "worktree", "remove", "--force", str(work))
            return "merge-failed"
    pushed = git(work, "push", "-u", "origin", f"HEAD:{default}")
    git(repo, "worktree", "remove", "--force", str(work))
    if pushed.returncode != 0:
        detail = (pushed.stderr or pushed.stdout).strip().splitlines()
        return "push-failed: " + (detail[-1] if detail else "unknown")
    return "pushed-default"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    groups: dict[str, list[Path]] = {}
    remotes: dict[Path, str] = {}
    for repo in local_repos():
        url = git(repo, "remote", "get-url", "origin").stdout.strip()
        parsed = nwo_of(url)
        if parsed is None or parsed[0].lower() not in OWNERS:
            print(f"skip-foreign\t{repo}")
            continue
        key = f"{parsed[0]}/{parsed[1]}"
        groups.setdefault(key, []).append(repo)
        remotes[repo] = url

    failures = 0
    for key, repos in sorted(groups.items()):
        owner, name = key.split("/", 1)
        ranked = []
        for repo in repos:
            branch = branch_of(repo)
            default = default_branch(repo)
            ranked.append((score(repo, branch, default, name), repo, branch, default))
        ranked.sort(reverse=True)
        _, writer, branch, default = ranked[0]
        folder = writer.name
        if writer.parent != DEV:
            folder = str(writer.relative_to(DEV))
        body = contract(writer, owner, name, folder, default, f"git@github.com:{owner}/{name}.git")
        action = "dry-run"
        if args.write:
            if busy(writer) and branch == default:
                action = "skip-busy"
                failures += 1
            else:
                ensure_ssh(writer, owner, name)
                if branch == default:
                    (writer / "MULTI-MAC.md").write_text(body)
                    action = commit_file(writer, writer / "MULTI-MAC.md")
                else:
                    action = commit_via_worktree(writer, default, body)
            if action.startswith(("commit-failed", "push-failed", "merge-failed", "worktree", "fetch-failed", "skip-busy")):
                failures += 1
        else:
            action = f"would-write branch={branch} default={default}"
        print(f"{action}\t{key}\t{writer}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
