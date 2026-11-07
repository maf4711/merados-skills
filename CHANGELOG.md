# Changelog

## [0.1.5] — 2026-11-08 — cpr: cprd-Skript Fix

### Fixed
- `deploy-nodes.sh`: `ssh -n` (Loop brach nach dem ersten Node ab) und lokaler Tag-Fetch vor dem Vergleich. Spiegel von Skill-Suite v0.9.20.

## [0.1.4] — 2026-11-08 — cpr: Token `cprd`

### Added
- `cpr` — neues Token **`cprd`**: `cpr` + Deploy der released Skill-Suite auf jeden erreichbaren Cluster-Node (`skills/cpr/scripts/deploy-nodes.sh`, liest `~/.config/maccluster/cluster.toml`, eine Ergebniszeile pro Node, nicht erreichbare Nodes werden benannt). Spiegel der kanonischen Skill-Suite v0.9.19.

## [0.1.3] — 2026-11-06 — Skill-Bereinigung

### Removed
- `depeche-mode-radio`, `dm80s80s`, `open-mac`, `projekt-loop` — in der kanonischen Skill-Suite (v0.9.0) als nie genutzt entfernt; der öffentliche Spiegel folgt.

## [0.1.2] — 2026-10-13 — iCloud-Status und Dokumenten-Merge

### Added
- `icloud-status` — lesende macOS-Prüfung von iCloud Drive, Schreibtisch und Dokumenten mit Upload-/Downloadzuständen, Fehlern und ausdrücklich ausgewiesener unvollständiger Abdeckung.
- `icloud-status merge-documents` — Gerätebestände rekursiv in einem gemeinsamen `~/Documents` zusammenführen; alle Dateikopien behalten, Namenskollisionen mit Herkunftszusatz auflösen, Vorschau und dauerhaftes Journal.
- Native macOS-Verschiebungen mit Schutz vor Überschreiben, veränderten Quellen, Pfadumleitungen und versehentlichem Verschieben aus iCloud in lokale Ordner; 15 Integrationstests mit isolierten Testdateien.

## [0.1.1] — 2026-09-25

### Added
- `repo-sync`: `MULTI-MAC.md` in jedem eigenen Repo (Checkout, Release, Apple, Vercel, devsync). `setup-mac.sh` installiert die Skill-Suite und prüft Release-Werkzeuge. LaunchAgent-Plist nutzt `__DEVSYNC_HOME__`.

## [0.1.0] — 2026-09-24

### Changed
- `cpr`: add explicit `cprt`; release every repository iOS app with separate App Store Connect identity, next build number and verified TestFlight groups.
