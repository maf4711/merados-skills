#!/usr/bin/env python3
"""Real filesystem merge checks, exclusively in isolated temporary directories."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import documents_merge as merge


@unittest.skipUnless(sys.platform == "darwin", "macOS Foundation required")
class MergeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="icloud-merge-test-")
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "Documents-MacBook"
        self.target = self.root / "Documents"
        self.source.mkdir()
        self.target.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def write(self, root, path, data):
        p = root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        return p

    def apply(self, plan):
        journal = self.root / "journal.jsonl"
        result = subprocess.run(["/usr/bin/xcrun", "swift", str(merge.NATIVE), "apply", str(journal)],
                                input=merge.encode(plan), capture_output=True, timeout=45)
        summary = json.loads(result.stdout)
        return result.returncode, summary, journal

    def test_recursive_merge_preserves_identical_duplicates_and_metadata(self):
        self.write(self.target, "Finanzen/Rechnung.pdf", b"same bytes")
        duplicate = self.write(self.source, "Finanzen/Rechnung.pdf", b"same bytes")
        subprocess.run(["/usr/bin/xattr", "-w", "user.merge-test", "preserved", str(duplicate)], check=True)
        self.write(self.source, "Finanzen/neu.pdf", b"new")
        self.write(self.source, "NeueKategorie/nested.txt", b"nested")
        plan = merge.make_plan(self.source, self.target)
        self.assertTrue(duplicate.exists(), "planning must not mutate source")
        self.assertEqual(plan["summary"]["renamed_collisions"], 1)
        code, summary, journal = self.apply(plan)
        self.assertEqual(code, 0, summary)
        self.assertFalse(self.source.exists())
        self.assertEqual((self.target / "Finanzen/Rechnung.pdf").read_bytes(), b"same bytes")
        preserved = self.target / "Finanzen/Rechnung (von MacBook).pdf"
        self.assertEqual(preserved.read_bytes(), b"same bytes")
        attribute = subprocess.run(["/usr/bin/xattr", "-p", "user.merge-test", str(preserved)], check=True, capture_output=True)
        self.assertEqual(attribute.stdout.strip(), b"preserved")
        self.assertEqual((self.target / "NeueKategorie/nested.txt").read_bytes(), b"nested")
        rows = [json.loads(line) for line in journal.read_text().splitlines()]
        self.assertTrue(rows)
        self.assertEqual(os.stat(journal).st_mode & 0o777, 0o600)

    def test_child_source_can_merge_into_parent(self):
        self.source.rmdir()
        self.source = self.target / "Dokumente-MacMini"
        self.source.mkdir()
        self.write(self.source, "report.pdf", b"report")
        code, summary, _ = self.apply(merge.make_plan(self.source, self.target))
        self.assertEqual(code, 0, summary)
        self.assertEqual((self.target / "report.pdf").read_bytes(), b"report")
        self.assertFalse(self.source.exists())

    def test_package_and_file_directory_collisions_keep_both(self):
        self.write(self.source, "Demo.app/Contents/source.txt", b"source")
        self.write(self.target, "Demo.app/Contents/target.txt", b"target")
        self.write(self.target, "Reports", b"file")
        self.write(self.source, "Reports/document.txt", b"doc")
        plan = merge.make_plan(self.source, self.target)
        self.assertEqual(plan["summary"]["renamed_collisions"], 2)
        code, summary, _ = self.apply(plan)
        self.assertEqual(code, 0, summary)
        self.assertTrue((self.target / "Demo (von MacBook).app/Contents/source.txt").exists())
        self.assertFalse((self.target / "Demo.app/Contents/source.txt").exists())
        self.assertEqual((self.target / "Reports").read_bytes(), b"file")
        self.assertTrue((self.target / "Reports (von MacBook)/document.txt").exists())

    def test_new_destination_is_not_overwritten(self):
        self.write(self.source, "new.pdf", b"source")
        plan = merge.make_plan(self.source, self.target)
        self.write(self.target, "new.pdf", b"concurrent")
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertEqual((self.target / "new.pdf").read_bytes(), b"concurrent")
        self.assertEqual((self.source / "new.pdf").read_bytes(), b"source")

    def test_source_changed_after_plan_is_not_moved(self):
        file = self.write(self.source, "new.pdf", b"source")
        plan = merge.make_plan(self.source, self.target)
        file.write_bytes(b"changed after planning")
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertTrue(file.exists())
        self.assertFalse((self.target / "new.pdf").exists())

    def test_cleanup_keeps_new_unplanned_file(self):
        self.write(self.source, "planned.pdf", b"planned")
        plan = merge.make_plan(self.source, self.target)
        self.write(self.source, "new-after-plan.pdf", b"keep me")
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertEqual((self.source / "new-after-plan.pdf").read_bytes(), b"keep me")
        self.assertEqual((self.target / "planned.pdf").read_bytes(), b"planned")

    def test_symlink_and_overlap_guards(self):
        (self.source / "external").symlink_to(self.target, target_is_directory=True)
        plan = merge.make_plan(self.source, self.target)
        self.assertFalse(plan["summary"]["executable"])
        with self.assertRaises(ValueError):
            merge.make_plan(self.root, self.target)
        alias = self.root / "Documents 2"
        alias.symlink_to(self.target, target_is_directory=True)
        with self.assertRaises(ValueError):
            merge.make_plan(alias, self.target)

    def test_changed_destination_parent_cannot_redirect_merge(self):
        self.write(self.source, "Finanzen/new.pdf", b"source")
        self.write(self.target, "Finanzen/existing.pdf", b"existing")
        plan = merge.make_plan(self.source, self.target)
        real = self.target / "Finanzen"
        moved = self.root / "original-finances"
        real.rename(moved)
        real.symlink_to(moved, target_is_directory=True)
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertFalse((moved / "new.pdf").exists())
        self.assertTrue((self.source / "Finanzen/new.pdf").exists())

    def test_plan_digest_must_match(self):
        path = self.root / "plan.json"
        path.write_bytes(b"{}")
        with self.assertRaises(ValueError):
            merge.apply_plan(path, "0" * 64)

    def test_absolute_internal_link_is_preserved_without_touching_target(self):
        original = self.write(self.target, "exports/2026.csv", b"original")
        (self.source / "latest").symlink_to(original)
        plan = merge.make_plan(self.source, self.target)
        self.assertTrue(plan["summary"]["executable"])
        code, summary, _ = self.apply(plan)
        self.assertEqual(code, 0, summary)
        self.assertTrue((self.target / "latest").is_symlink())
        self.assertEqual(os.readlink(self.target / "latest"), str(original))
        self.assertEqual(original.read_bytes(), b"original")

    def test_machine_only_names_are_discoverable(self):
        (self.target / "MacBook Pro").mkdir()
        (self.target / "Anna Büro").mkdir()
        report = merge.discover(roots=[self.target], machine_names=["Anna Büro"])
        found = {Path(item["path"]).name for item in report["candidates"]}
        self.assertIn("MacBook Pro", found)
        self.assertIn("Anna Büro", found)

    def test_dangling_links_cannot_form_cycle_after_merge(self):
        (self.source / "a").symlink_to(self.target / "b")
        (self.source / "b").symlink_to(self.target / "a")
        plan = merge.make_plan(self.source, self.target)
        self.assertFalse(plan["summary"]["executable"])
        self.assertEqual(plan["summary"]["blockers"], 2)
        self.assertEqual(plan["summary"]["move_entries"], 0)

    def test_link_target_cannot_redirect_through_parent_or_leaf(self):
        external = self.write(self.root, "external/file.txt", b"keep")
        (self.target / "alias").symlink_to(external.parent, target_is_directory=True)
        (self.target / "file-link").symlink_to(external)
        (self.source / "through-parent").symlink_to(self.target / "alias/file.txt")
        (self.source / "through-leaf").symlink_to(self.target / "file-link")
        plan = merge.make_plan(self.source, self.target)
        self.assertFalse(plan["summary"]["executable"])
        self.assertEqual(plan["summary"]["blockers"], 2)

    def test_link_target_redirected_after_plan_stops_execution(self):
        original = self.write(self.target, "exports/file.txt", b"keep")
        link = self.source / "latest"
        link.symlink_to(original)
        plan = merge.make_plan(self.source, self.target)
        self.assertTrue(plan["summary"]["executable"])
        exports = self.target / "exports"
        outside = self.root / "moved-exports"
        exports.rename(outside)
        exports.symlink_to(outside, target_is_directory=True)
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertTrue(link.is_symlink())
        self.assertFalse((self.target / "latest").is_symlink())
        self.assertEqual((outside / "file.txt").read_bytes(), b"keep")

    def test_cloud_merge_cannot_use_local_only_target(self):
        self.write(self.source, "cloud-file.pdf", b"keep")
        plan = merge.make_plan(self.source, self.target)
        plan["requires_icloud_target"] = True
        code, summary, _ = self.apply(plan)
        self.assertNotEqual(code, 0, summary)
        self.assertEqual(summary["error"], "icloud_target_not_confirmed")
        self.assertTrue((self.source / "cloud-file.pdf").exists())
        self.assertFalse((self.target / "cloud-file.pdf").exists())


if __name__ == "__main__":
    unittest.main()
