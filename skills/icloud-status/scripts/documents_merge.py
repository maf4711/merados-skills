#!/usr/bin/env python3
"""Merge Mac document imports into one Documents tree, retaining every file."""
import argparse
from collections import deque
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import select
import stat
import subprocess
import sys
import time
import unicodedata
import uuid

NATIVE = Path(__file__).with_name("documents_move.swift")
STATE = Path.home() / ".local/state/icloud-status/merges"
ARCHIVE = re.compile(r"archiv|archive|dubletten|duplicates|_alt[-_ ]|backup", re.I)
DOCUMENTS = re.compile(r"(?:^|[-_ /])(?:documents|dokumente)(?:$|[\s_–—-])", re.I)
MACHINE = re.compile(r"\b(?:macbook|imac|mac\s*(?:mini|studio|pro)|macos)\b|^CM-", re.I)


def fingerprint(path):
    s = os.lstat(path)
    return dict(dev=s.st_dev, ino=s.st_ino, mode=s.st_mode, size=s.st_size, mtime_ns=s.st_mtime_ns)


def canonical(path):
    p = Path(os.path.abspath(os.path.expanduser(str(path))))
    if p != p.resolve(strict=True):
        raise ValueError("Symlink/umgeleiteter Pfad ist keine Merge-Quelle: " + str(p))
    if not p.is_dir():
        raise ValueError("Ordner erforderlich: " + str(p))
    return p


def inside(path, root):
    return path == root or root in path.parents


def normalized(name):
    return unicodedata.normalize("NFC", name).casefold()


def safe_link_target(path):
    """Accept an existing file/directory with no redirected path components."""
    try:
        if any(not stat.S_ISDIR(os.lstat(parent).st_mode) for parent in reversed(path.parents)):
            return False
        mode = os.lstat(path).st_mode
        return stat.S_ISREG(mode) or stat.S_ISDIR(mode)
    except OSError:
        return False


def label_for(source, explicit=None):
    label = explicit or re.sub(r"^(?:import[-_ ]*)?(?:documents|dokumente)[\s_–—-]*", "", source.name, flags=re.I)
    label = re.sub(r"[^\w .-]", "_", unicodedata.normalize("NFC", label)).strip(" .")
    return (label or "anderer Mac")[:48]


class PackageProbe:
    """One native process; package detection reads metadata, not file contents."""
    def __init__(self):
        self.proc = None

    def metadata(self, *paths):
        if self.proc is None:
            self.proc = subprocess.Popen(["/usr/bin/xcrun", "swift", str(NATIVE), "inspect"],
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.proc.stdin.write(json.dumps({"paths": list(map(str, paths))}) + "\n")
        self.proc.stdin.flush()
        if not select.select([self.proc.stdout], [], [], 30)[0]:
            raise RuntimeError("Zeitlimit bei Paket-Metadaten")
        data = json.loads(self.proc.stdout.readline())
        values = data.get("packages")
        if not isinstance(values, list) or len(values) != len(paths) or any(type(x) is not bool for x in values):
            raise RuntimeError("Paketstatus nicht sicher bestimmbar")
        return data

    def packages(self, *paths):
        values = self.metadata(*paths)["packages"]
        # Repositories are indivisible even if Foundation reports a plain directory.
        return [value or p.name == ".git" for p, value in zip(paths, values)]

    def close(self):
        if self.proc is not None:
            self.proc.stdin.close()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
            self.proc.stdout.close()


def make_plan(source, target, label=None, max_entries=100000, seconds=60, probe=None):
    source, target = canonical(source), canonical(target)
    if inside(target, source):
        raise ValueError("Quelle darf nicht das Ziel sein oder das Ziel enthalten")
    if os.stat(source).st_dev != os.stat(target).st_dev:
        raise ValueError("Verschiedene Volumes: kein automatisches Kopieren/Löschen")
    label = label_for(source, label)
    plan = dict(schema=1, created_at=dt.datetime.now().astimezone().isoformat(),
                source=str(source), target=str(target), label=label,
                directories={}, operations=[], blockers=[])
    cache = {}
    deadline = time.monotonic() + seconds
    visited = 0
    own_probe = probe is None
    probe = probe or PackageProbe()

    def snapshot(folder):
        value = fingerprint(folder)
        if not stat.S_ISDIR(value["mode"]):
            raise ValueError("Kein echter Ordner: " + str(folder))
        plan["directories"][str(folder)] = value

    def children(folder):
        if folder not in cache:
            snapshot(folder)
            names = {}
            with os.scandir(folder) as entries:
                for entry in entries:
                    key = normalized(entry.name)
                    if key in names:
                        raise ValueError("Mehrdeutige Groß-/Kleinschreibung im Ziel: " + str(folder))
                    names[key] = Path(entry.path)
            cache[folder] = names
        return cache[folder]

    def collision(path, occupied):
        suffix = path.suffix
        stem = path.name[:-len(suffix)] if suffix else path.name
        for number in range(1, 100001):
            tag = f" (von {label}" + (f" {number}" if number > 1 else "") + ")"
            name = stem + tag + suffix
            while len(name.encode("utf-8")) > 240 and stem:
                stem = stem[:-1]
                name = stem + tag + suffix
            if not stem or len(name.encode("utf-8")) > 240:
                raise ValueError("Konfliktname zu lang: " + str(path))
            candidate = path.with_name(name)
            if normalized(name) not in occupied and not os.path.lexists(candidate):
                return candidate
        raise ValueError("Zu viele Namenskollisionen: " + str(path))

    def visit(src, dst):
        nonlocal visited
        snapshot(src)
        occupied = children(dst)
        with os.scandir(src) as entries:
            entries = sorted(entries, key=lambda e: (normalized(e.name), e.name))
        for entry in entries:
            visited += 1
            if visited > max_entries or time.monotonic() > deadline:
                raise RuntimeError("Planlimit erreicht; kein ausführbarer Teilplan")
            item = Path(entry.path)
            expected = fingerprint(item)
            link_target = None
            if stat.S_ISLNK(expected["mode"]):
                link_target = os.readlink(item)
                link_path = Path(link_target)
                if not (link_path.is_absolute() and str(link_path) == link_target == os.path.normpath(link_target)
                        and link_path != target and inside(link_path, target) and not inside(link_path, source)):
                    plan["blockers"].append({"path": str(item), "reason": "relative_or_external_symlink_needs_review"})
                    continue
                if not safe_link_target(link_path):
                    plan["blockers"].append({"path": str(item), "reason": "symlink_target_missing_or_redirected"})
                    continue
            elif not (stat.S_ISREG(expected["mode"]) or stat.S_ISDIR(expected["mode"])):
                plan["blockers"].append({"path": str(item), "reason": "symlink_or_special_file"})
                continue
            if item.name.startswith(".") and item.name.endswith(".icloud"):
                plan["blockers"].append({"path": str(item), "reason": "legacy_placeholder_needs_review"})
                continue
            existing = occupied.get(normalized(item.name))
            desired = dst / item.name
            if existing and inside(existing, source):
                raise ValueError("Ziel würde wieder in die Merge-Quelle führen: " + str(existing))
            if existing and os.path.lexists(existing):
                target_info = fingerprint(existing)
                if stat.S_ISDIR(expected["mode"]) and stat.S_ISDIR(target_info["mode"]):
                    source_package, target_package = probe.packages(item, existing)
                    if not source_package and not target_package:
                        visit(item, existing)
                        continue
            if existing:
                desired = collision(desired, occupied)
            if inside(desired, source):
                raise ValueError("Ziel liegt innerhalb der Merge-Quelle: " + str(desired))
            if link_target is not None and inside(desired, Path(link_target)):
                plan["blockers"].append({"path": str(item), "reason": "symlink_would_create_cycle"})
                continue
            operation = dict(kind="move", source=str(item), destination=str(desired),
                                           expected=expected, collision=existing is not None,
                                           whole_directory=stat.S_ISDIR(expected["mode"]))
            if link_target is not None:
                operation["link_target"] = link_target
            plan["operations"].append(operation)
            occupied[normalized(desired.name)] = desired
        plan["operations"].append(dict(kind="rmdir", source=str(src), expected=fingerprint(src)))

    try:
        snapshot(source)
        snapshot(target)
        root_metadata = probe.metadata(source, target)
        if root_metadata["packages"] != [False, False] or source.name == ".git" or target.name == ".git":
            raise ValueError("Dokumenten-Wurzel darf kein App-/Dateipaket sein")
        membership = root_metadata.get("ubiquitous", [None, None])
        if not isinstance(membership, list) or len(membership) != 2:
            raise ValueError("iCloud-Mitgliedschaft nicht bestimmbar")
        cloud = Path.home() / "Library/Mobile Documents"
        required = (target == Path.home() / "Documents" or any(value is True for value in membership)
                    or inside(source, cloud) or inside(target, cloud))
        plan["requires_icloud_target"] = required
        plan["cloud_scope"] = dict(source_ubiquitous=membership[0], target_ubiquitous=membership[1])
        if required and membership[1] is not True:
            plan["blockers"].append({"path": str(target), "reason": "icloud_target_not_confirmed"})
        visit(source, target)
    finally:
        if own_probe:
            probe.close()
    moves = [op for op in plan["operations"] if op["kind"] == "move"]
    plan["summary"] = dict(move_entries=len(moves), whole_directories=sum(op["whole_directory"] for op in moves),
                           renamed_collisions=sum(op["collision"] for op in moves),
                           empty_directories_to_remove=len(plan["operations"]) - len(moves),
                           blockers=len(plan["blockers"]), executable=not plan["blockers"],
                           note="Ein Verzeichnis-Eintrag umfasst seinen gesamten Inhalt; keine Gesamtdateizahl. Alle Dateikopien bleiben erhalten.")
    return plan


def encode(plan):
    return (json.dumps(plan, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def save_private(path, data):
    path = Path(os.path.abspath(os.path.expanduser(str(path))))
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def discover(depth=4, max_dirs=1500, seconds=20, machine_names=(), roots=None):
    target = Path.home() / "Documents"
    drive = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs"
    queue = deque((root, 0, root) for root in (roots or (target, drive)))
    results, limits, other_top_level = [], [], []
    known_names = {normalized(name) for name in machine_names}
    deadline, examined = time.monotonic() + seconds, 0
    while queue:
        folder, level, root = queue.popleft()
        if examined >= max_dirs or time.monotonic() >= deadline:
            limits.append("directory_or_time_limit")
            break
        examined += 1
        try:
            with os.scandir(folder) as entries:
                for n, entry in enumerate(entries):
                    if n >= 10000:
                        limits.append("entry_limit: " + str(folder))
                        break
                    p = Path(entry.path)
                    if not (entry.is_dir(follow_symlinks=False) or entry.is_symlink()):
                        continue
                    named_documents = bool(DOCUMENTS.search(entry.name))
                    named_machine = bool(MACHINE.search(entry.name)) or normalized(entry.name) in known_names
                    if named_documents or named_machine:
                        archived = any(ARCHIVE.search(part) for part in p.relative_to(root).parts)
                        disposition = "alias" if entry.is_symlink() else "archive_review" if archived else "candidate" if named_documents else "machine_name_review"
                        results.append(dict(path=str(p), disposition=disposition))
                    elif level == 0:
                        other_top_level.append(str(p))
                    if level < depth and not entry.is_symlink() and not entry.name.startswith("."):
                        queue.append((p, level + 1, root))
        except OSError as error:
            limits.append(f"{folder}: {type(error).__name__}")
    return dict(candidates=results, other_top_level_directories=other_top_level,
                examined_directories=examined, bounded_depth=depth,
                limits=limits, note="Kandidaten sind keine automatische Quellenauswahl; Archive und Aliase separat prüfen.")


def apply_plan(path, digest):
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError("Plan-Prüfsumme stimmt nicht überein")
    plan = json.loads(raw)
    if plan.get("schema") != 1 or plan.get("blockers") or not plan.get("summary", {}).get("executable"):
        raise ValueError("Plan ist nicht ausführbar")
    canonical(plan["source"])
    canonical(plan["target"])
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    journal = STATE / ("journal-" + uuid.uuid4().hex + ".jsonl")
    # Pass the verified immutable bytes, not a plan filename that could change.
    result = subprocess.run(["/usr/bin/xcrun", "swift", str(NATIVE), "apply", str(journal)],
                            input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        summary = json.loads(result.stdout)
    except ValueError:
        summary = dict(ok=False, error="native_output_unavailable", exit_code=result.returncode)
    print(json.dumps(dict(result=summary, journal=str(journal), plan_sha256=digest), ensure_ascii=False, indent=2))
    return 0 if result.returncode == 0 and summary.get("ok") else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    discovery = subs.add_parser("discover", help="Begrenzte Suche nach Geräteordnern; keine Datenänderung")
    discovery.add_argument("--machine-name", action="append", default=[], help="Bekannter Rechnername, mehrfach möglich")
    plan_parser = subs.add_parser("plan", help="Merge planen, ohne Dokumente zu verändern")
    plan_parser.add_argument("--source", required=True)
    plan_parser.add_argument("--target", default=str(Path.home() / "Documents"))
    plan_parser.add_argument("--label", help="Herkunft für Namenskollisionen, z.B. MacBook")
    plan_parser.add_argument("--out", help="Neue lokale JSON-Plandatei außerhalb Quelle/Ziel")
    plan_parser.add_argument("--seconds", type=float, default=60)
    plan_parser.add_argument("--max-entries", type=int, default=100000)
    apply_parser = subs.add_parser("apply", help="Genau den zuvor geprüften Plan ausführen")
    apply_parser.add_argument("--plan", required=True)
    apply_parser.add_argument("--sha256", required=True)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS erforderlich")
    try:
        if args.command == "discover":
            print(json.dumps(discover(machine_names=args.machine_name), ensure_ascii=False, indent=2))
        elif args.command == "plan":
            if not 1 <= args.seconds <= 600 or not 1 <= args.max_entries <= 1000000:
                raise ValueError("seconds: 1–600; max-entries: 1–1000000")
            plan = make_plan(args.source, args.target, args.label, args.max_entries, args.seconds)
            raw = encode(plan)
            out = Path(args.out).expanduser().absolute() if args.out else STATE / ("plan-" + uuid.uuid4().hex + ".json")
            out = out.parent.resolve() / out.name
            cloud = Path.home() / "Library/Mobile Documents"
            if inside(out, Path(plan["source"])) or inside(out, Path(plan["target"])) or inside(out, cloud):
                raise ValueError("Plandatei muss außerhalb von Quelle und Ziel liegen")
            save_private(out, raw)
            print(json.dumps(dict(plan=str(out), sha256=hashlib.sha256(raw).hexdigest(),
                                  source=plan["source"], target=plan["target"], summary=plan["summary"],
                                  blockers=plan["blockers"][:20], preview=plan["operations"][:12]), ensure_ascii=False, indent=2))
        else:
            return apply_plan(args.plan, args.sha256)
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, RecursionError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
