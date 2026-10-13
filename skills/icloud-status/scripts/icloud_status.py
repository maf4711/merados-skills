#!/usr/bin/env python3
"""Read-only iCloud Drive snapshot; stdlib launcher with native Foundation metadata."""
import argparse
import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys


SWIFT = r'''
import Foundation
import Darwin

let config = try JSONSerialization.jsonObject(with: Data(ProcessInfo.processInfo.environment["ICLOUD_STATUS_CONFIG"]!.utf8)) as! [String: Any]
let seconds = config["seconds"] as! Double
let maximum = config["max_files"] as! Int
let detailLimit = config["details"] as! Int
let roots = config["roots"] as! [[String: Any]]
let keys: Set<URLResourceKey> = [
    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
    .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
    .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemDownloadRequestedKey, .ubiquitousItemHasUnresolvedConflictsKey,
    .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey
]
var reports: [[String: Any]] = []
for root in roots {
    let path = root["path"] as! String
    let requested = URL(fileURLWithPath: path).standardizedFileURL
    let url = requested.resolvingSymlinksInPath()
    var report: [String: Any] = ["name": root["name"]!, "path": path, "resolved_path": url.path]
    // Do not follow a redirected root into an unrelated directory.
    if requested.path != url.path {
        report["state"] = "unavailable"
        report["coverage_complete"] = false
        report["stop_reason"] = "redirected_root_not_scanned"
        reports.append(report)
        continue
    }
    let names = ["files_seen", "uploaded", "uploading", "waiting_upload", "downloading",
        "download_requested_idle", "cloud_only", "local_current", "local_older",
        "conflicts", "errors", "unknown", "metadata_read_errors", "ignored_system_files", "skipped_symlinks"]
    var counts = Dictionary(uniqueKeysWithValues: names.map { ($0, 0) })
    var details: [[String: Any]] = []
    var cloudExamples: [[String: Any]] = []
    var accessErrors: [[String: Any]] = []
    var complete = true
    var stopReason: String? = nil
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    var directory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) || !directory.boolValue {
        report["state"] = "unavailable"
        report["coverage_complete"] = false
        report["stop_reason"] = "root_missing_or_inaccessible"
        reports.append(report)
        continue
    }
    if let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]) {
        report["root_is_ubiquitous"] = v.isUbiquitousItem as Any? ?? NSNull()
    }
    // Read root directory once so an unreadable root is not misreported as empty.
    do { _ = try FileManager.default.contentsOfDirectory(atPath: url.path) }
    catch {
        report["state"] = "unavailable"
        report["coverage_complete"] = false
        report["stop_reason"] = "root_enumeration_failed"
        report["error_code"] = (error as NSError).code
        reports.append(report)
        continue
    }
    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { badURL, error in
        complete = false
        if accessErrors.count < detailLimit {
            accessErrors.append(["path": badURL.path, "domain": (error as NSError).domain, "code": (error as NSError).code])
        }
        return ProcessInfo.processInfo.systemUptime < deadline
    })
    if let enumerator = enumerator {
        for case let item as URL in enumerator {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                complete = false; stopReason = "time_limit"; break
            }
            if counts["files_seen"]! >= maximum {
                complete = false; stopReason = "file_limit"; break
            }
            if [".DS_Store", ".localized"].contains(item.lastPathComponent) {
                counts["ignored_system_files"]! += 1; continue
            }
            do {
                let v = try item.resourceValues(forKeys: keys)
                if v.isSymbolicLink == true {
                    counts["skipped_symlinks"]! += 1
                    enumerator.skipDescendants(); continue
                }
                if v.isDirectory == true { continue }
                guard v.isRegularFile == true else { continue }
                counts["files_seen"]! += 1
                var flags: [String] = []
                func mark(_ name: String) { counts[name]! += 1; flags.append(name) }
                let uploaded = v.ubiquitousItemIsUploaded
                let uploading = v.ubiquitousItemIsUploading
                let downloading = v.ubiquitousItemIsDownloading
                let status = v.ubiquitousItemDownloadingStatus
                if uploaded == true { counts["uploaded"]! += 1 }
                if uploading == true { mark("uploading") }
                if uploaded == false && uploading == false && v.isUbiquitousItem == true { mark("waiting_upload") }
                if downloading == true { mark("downloading") }
                if v.ubiquitousItemDownloadRequested == true && downloading == false && status != nil && status != .current {
                    mark("download_requested_idle")
                }
                var fileStat = stat()
                let statOK = item.path.withCString { lstat($0, &fileStat) == 0 }
                let dataless = statOK && (fileStat.st_flags & 0x40000000) != 0
                let legacy = item.lastPathComponent.hasPrefix(".") && item.pathExtension == "icloud"
                if status == .notDownloaded || dataless || legacy { mark("cloud_only") }
                if status == .current && !dataless && !legacy { counts["local_current"]! += 1 }
                if status == .downloaded { mark("local_older") }
                if v.ubiquitousItemHasUnresolvedConflicts == true { mark("conflicts") }
                let uploadError = v.ubiquitousItemUploadingError
                let downloadError = v.ubiquitousItemDownloadingError
                if uploadError != nil || downloadError != nil { mark("errors") }
                if v.isUbiquitousItem != true || uploaded == nil || uploading == nil || downloading == nil || status == nil || v.ubiquitousItemHasUnresolvedConflicts == nil {
                    mark("unknown")
                }
                if !flags.isEmpty {
                    var detail: [String: Any] = ["path": item.path, "states": flags]
                    if let error = uploadError as NSError? { detail["upload_error"] = ["domain": error.domain, "code": error.code] }
                    if let error = downloadError as NSError? { detail["download_error"] = ["domain": error.domain, "code": error.code] }
                    if flags.contains(where: { $0 != "cloud_only" }) {
                        if details.count < detailLimit { details.append(detail) }
                    } else if cloudExamples.count < detailLimit { cloudExamples.append(detail) }
                }
            } catch {
                complete = false
                counts["metadata_read_errors"]! += 1
                if accessErrors.count < detailLimit {
                    accessErrors.append(["path": item.path, "domain": (error as NSError).domain, "code": (error as NSError).code])
                }
            }
        }
    } else { complete = false; stopReason = "enumeration_failed" }
    var state = "unconfirmed"
    if counts["errors"]! + counts["conflicts"]! > 0 { state = "problems" }
    else if counts["uploading"]! + counts["downloading"]! > 0 { state = "active" }
    else if counts["waiting_upload"]! + counts["download_requested_idle"]! + counts["local_older"]! > 0 { state = "pending" }
    else if complete && counts["unknown"] == 0 && counts["files_seen"]! > 0 && counts["uploaded"] == counts["files_seen"] {
        state = "observed_uploaded_no_transfers"
    }
    report["state"] = state
    report["coverage_complete"] = complete
    report["stop_reason"] = stopReason as Any? ?? NSNull()
    report["counts"] = counts
    report["details"] = details + cloudExamples.prefix(max(0, detailLimit - details.count))
    report["access_errors"] = accessErrors
    reports.append(report)
}
let output = try JSONSerialization.data(withJSONObject: reports, options: [.sortedKeys])
print(String(data: output, encoding: .utf8)!)
'''


def run_command(command, timeout, **kwargs):
    """Never return raw stderr: provider diagnostics can contain credentials."""
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=timeout, **kwargs)
        if result.returncode:
            return {"ok": False, "reason": "command_failed", "exit_code": result.returncode}
        return {"ok": True, "output": result.stdout}
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": "timeout"}
    except OSError as error:
        return {"ok": False, "reason": "unavailable", "errno": error.errno}


def parse_status(result):
    if not result["ok"]:
        return dict(result, desktop_documents_enabled=None)
    raw = re.sub(r"\x1b\[[0-9;]*m", "", result["output"])
    setting = re.search(r"Desktop & Documents:\s*current=(YES|NO)\b", raw)
    matched = re.search(r"^(\d+) containers matching", raw, re.MULTILINE)
    last_sync = re.search(r"last-sync:(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)", raw)
    return {
        "ok": bool(matched and int(matched.group(1)) > 0),
        "reason": None if matched and int(matched.group(1)) > 0 else "container_not_confirmed",
        "desktop_documents_enabled": setting.group(1) == "YES" if setting else None,
        "caught_up": bool(re.search(r"\bcaught-up\b", raw)) if matched else None,
        "last_sync_raw": last_sync.group(1).strip() if last_sync else None,
    }


def parse_quota(result):
    if not result["ok"]:
        return result
    match = re.search(r"\b(\d+) bytes of quota remaining", result["output"])
    return {"ok": bool(match), "remaining_bytes": int(match.group(1)) if match else None}


def collect(args):
    started = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        status_future = pool.submit(run_command, ["/usr/bin/brctl", "status", "com.apple.CloudDocs"], 10)
        quota_future = pool.submit(run_command, ["/usr/bin/brctl", "quota"], 10)
        provider = parse_status(status_future.result())
        quota = parse_quota(quota_future.result())
    base = Path.home()
    roots = [{"name": "iCloud Drive", "path": str(base / "Library/Mobile Documents/com~apple~CloudDocs")}]
    skipped = []
    for name, folder in [("Schreibtisch", "Desktop"), ("Dokumente", "Documents")]:
        item = {"name": name, "path": str(base / folder)}
        if provider["desktop_documents_enabled"] is True:
            roots.append(item)
        else:
            skipped.append(dict(item, state="disabled" if provider["desktop_documents_enabled"] is False else "setting_unknown", coverage_complete=False))
    env = dict(os.environ, ICLOUD_STATUS_CONFIG=json.dumps({
        "seconds": args.seconds, "max_files": args.max_files, "details": args.details, "roots": roots,
    }))
    native = run_command(["/usr/bin/xcrun", "swift", "-"],
                         args.seconds * len(roots) + 30, input=SWIFT, env=env)
    reports = []
    native_error = None
    if native["ok"]:
        try:
            reports = json.loads(native["output"])
            if not isinstance(reports, list):
                raise ValueError("unexpected result")
        except (ValueError, TypeError):
            native_error = {"ok": False, "reason": "invalid_native_output"}
    else:
        native_error = native
    if native_error:
        reports = [dict(root, state="unavailable", coverage_complete=False,
                        stop_reason=native_error["reason"]) for root in roots]
    return {
        "started_at": started,
        "finished_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "provider": provider, "quota": quota, "areas": reports + skipped,
        "native_error": native_error,
        "scope": "Observed regular-file metadata; no server comparison or complete directory/deletion queue check.",
        "counts_overlap": True,
    }


def render(report):
    print("iCloud-Status — " + report["finished_at"])
    enabled = report["provider"]["desktop_documents_enabled"]
    print("Schreibtisch & Dokumente in iCloud: " + {True: "aktiviert", False: "AUS", None: "unbekannt"}[enabled])
    states = {
        "disabled": "Lokaler Ordner; iCloud-Synchronisierung ausgeschaltet",
        "setting_unknown": "iCloud-Einstellung nicht ermittelbar; lokaler Ordner ungeprüft",
        "unavailable": "Nicht prüfbar", "unconfirmed": "Status nicht vollständig bestimmbar",
        "problems": "Fehler oder Konflikte", "active": "Übertragung läuft", "pending": "Änderungen ausstehend",
        "observed_uploaded_no_transfers": "Alle geprüften Dateien melden hochgeladen; kein Transfer beobachtet",
    }
    for area in report["areas"]:
        print("\n" + area["name"] + ": " + states[area["state"]])
        c = area.get("counts")
        if c:
            print(f"  Geprüft: {c['files_seen']} | hochgeladen: {c['uploaded']} | Upload läuft/wartet: {c['uploading']}/{c['waiting_upload']}")
            print(f"  Download läuft/angefordert: {c['downloading']}/{c['download_requested_idle']} | nur Cloud: {c['cloud_only']} | lokal aktuell/älter: {c['local_current']}/{c['local_older']}")
            print(f"  Konflikte: {c['conflicts']} | Sync-Fehler: {c['errors']} | unbekannt: {c['unknown']} | Lesefehler: {c['metadata_read_errors']}")
            print("  Dateiprüfung: " + ("vollständig für lesbare reguläre Dateien" if area["coverage_complete"] else "TEILWEISE — " + (area.get("stop_reason") or "Zugriffsfehler")))
            print(f"  Ausgelassen: {c['skipped_symlinks']} Symlinks, {c['ignored_system_files']} Finder-Systemdateien")
        elif area.get("stop_reason"):
            print("  Ursache: " + area["stop_reason"])
        for item in area.get("details", []):
            print("  " + ", ".join(item["states"]) + ": " + json.dumps(item["path"], ensure_ascii=False))
            for key in ("upload_error", "download_error"):
                error = item.get(key)
                if error:
                    print(f"    {key}: {error['domain']}/{error['code']}")
        for item in area.get("access_errors", []):
            print("  Zugriffsfehler: " + json.dumps(item, ensure_ascii=False))
    quota = report["quota"].get("remaining_bytes")
    if quota is not None:
        print(f"\niCloud-Speicher frei: {quota / 1_000_000_000:.2f} GB")
    if report["provider"].get("last_sync_raw"):
        print("Letzter Container-Sync laut brctl (Zeitzone nicht angegeben): " + report["provider"]["last_sync_raw"])
    if not report["provider"]["ok"]:
        print("Containerstatus nicht bestätigt: " + str(report["provider"].get("reason")))
    print("Momentaufnahme lokaler Metadaten; kein unabhängiger Serverabgleich. Bereichszähler nicht addieren.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Strukturierte Ausgabe")
    parser.add_argument("--seconds", type=float, default=20.0, help="Scanzeit pro Bereich, 1–300 Sekunden")
    parser.add_argument("--max-files", type=int, default=100000, help="Maximale Dateien pro Bereich")
    parser.add_argument("--details", type=int, default=10, help="Maximale Dateibeispiele pro Bereich, 0–100")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300 or not 1 <= args.max_files <= 1000000 or not 0 <= args.details <= 100:
        parser.error("seconds: 1–300, max-files: 1–1000000, details: 0–100")
    if sys.platform != "darwin":
        parser.error("Dieser Skill benötigt macOS.")
    report = collect(args)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        render(report)
    return 2 if report["native_error"] else 0


if __name__ == "__main__":
    sys.exit(main())
