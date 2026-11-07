---
name: icloud-status
description: Prüft den iCloud-Drive-Sync von Dateien, Schreibtisch und Dokumenten auf macOS. Führt auf ausdrücklichen Merge-Auftrag Dokumentenbestände mehrerer Macs in ~/Documents zusammen, mit Vorschau, Schutz vor Überschreiben und Erhalt aller Duplikate. Für Status und Dokumenten-Merge, nicht iCloud-Fotos.
---

# iCloud-Status

## Modus wählen

- `$icloud-status` oder eine Statusfrage: nur den lesenden Prüfer unten ausführen.
- `$icloud-status merge-documents`, „Dokumente zusammenführen“, „Documents-Mac-Ordner mergen“ oder „ein Documents
  für alle Macs“: [Dokumenten-Merge](references/documents-merge.md) lesen und den
  Plan-/Ausführungsablauf verwenden. Kanonisches Ziel ist `~/Documents`.
- Ein Auftrag, den **Skill zu erweitern**, erlaubt die Implementierung und eine
  Vorschau. Nur ein tatsächlicher Merge-Auftrag erlaubt Datenverschiebungen.
  Bereits klar autorisierte Quellen nicht erneut freigeben lassen. Mehrdeutige
  Archiv-/Dublettenordner vor ihrer Einbeziehung klären.

## Status prüfen

Führe den mitgelieferten, rein lesenden Prüfer aus:

```bash
/usr/bin/python3 ~/.codex/skills/icloud-status/scripts/icloud_status.py
```

Für eine ausführliche Auswertung mit Dateipfaden:

```bash
/usr/bin/python3 ~/.codex/skills/icloud-status/scripts/icloud_status.py --json --details 20
```

`--seconds 20` begrenzt die Dateiprüfung pro Bereich; `--max-files 100000`
begrenzt die Anzahl pro Bereich. Beide Grenzen sind konfigurierbar. Der Prozess
für native Metadaten hat zusätzlich ein hartes Zeitlimit. Voraussetzung ist
macOS mit `xcrun swift` (Xcode oder Command Line Tools).

## Auswertung

- Nenne zuerst Zeitpunkt, Status von iCloud Drive und ob **Schreibtisch und
  Dokumente tatsächlich in iCloud aktiviert** sind. Ein Ordner namens Desktop
  oder Documents in Drive kann eine alte Kopie sein und belegt diese Einstellung
  nicht. Bei deaktivierter Einstellung werden die lokalen Ordner nicht gescannt.
- Berichte für jeden geprüften Bereich Dateianzahl, bereits hochgeladene Dateien,
  aktive Uploads/Downloads, wartende Uploads, angeforderte Downloads, Konflikte,
  Fehler und unbekannte Statuswerte. Zeige relevante Dateibeispiele aus `details`.
- Die Zähler beschreiben verschiedene Eigenschaften und können sich überschneiden.
  Drive kann Schreibtisch/Dokumente enthalten; Bereichssummen nicht addieren.
- **Nur in der Cloud** ist bei optimiertem Speicher normal und bedeutet keinen
  fehlgeschlagenen Sync. **Lokal vorhanden** beweist keinen erfolgreichen Upload.
- `observed_uploaded_no_transfers` bedeutet ausschließlich: Alle in diesem
  Bereich geprüften Dateien melden hochgeladen, ohne beobachteten Transfer oder
  Konflikt. Es ist eine zeitlich verteilte Momentaufnahme der lokalen Providerdaten,
  kein unabhängiger Vergleich mit Apples Servern oder anderen Geräten. Löschungen,
  Umbenennungen und reine Verzeichnisänderungen werden nicht vollständig erfasst.
- Leere Ergebnisse, Fehler, Zeitlimits, unbekannte Schlüssel oder nicht lesbare
  Unterordner sind **kein Beleg für „alles synchronisiert“**. Berichte die erfasste
  Teilmenge und `coverage_complete`/`stop_reason` ausdrücklich.
- `last_sync_raw` stammt aus `brctl`; dessen Zeitzone ist nicht angegeben.
  `caught_up` ist ein Containersignal und keine Bestätigung jedes Datei-Uploads.
- Bei `NSCocoaErrorDomain` bedeutet Code 4353: Datei momentan nicht verfügbar,
  4354: Upload wegen iCloud-Speicherlimit gescheitert, 4355: Verbindung zu den
  iCloud-Servern fehlgeschlagen (FoundationErrors.h im macOS-SDK). Ein gespeicherter
  Dateifehler beweist keine aktuell andauernde oder weltweite Apple-Störung;
  laufende Wiederholungsversuche können gleichzeitig gemeldet werden.
- Gib Prozentwerte, Geschwindigkeit oder Restzeit nur aus, wenn eine zusätzliche
  Quelle sie direkt liefert. Dieser Prüfer schätzt sie nicht aus Dateigrößen oder
  lokalen Blöcken. Für Verlauf/Live-Wunsch führe begrenzte weitere Messungen aus
  und vergleiche Zähler; starte keinen dauerhaften Dienst.

## Grenzen und Diagnose

Der Prüfer kombiniert `brctl status com.apple.CloudDocs`, `brctl quota` und
Foundation-URL-Metadaten. `NSMetadataQuery` kann trotz vorhandener Drive-Dateien
leer zurückkommen; deshalb dient eine leere Suchabfrage nicht als Erfolgsbeweis.
Die native Prüfung liest ausschließlich Metadaten und folgt keinen Symlinks.
Umgeleitete Wurzelordner werden mit `redirected_root_not_scanned` ausdrücklich
ausgelassen. Symlinks innerhalb eines Bereichs und Finder-Systemdateien werden
gezählt, aber nicht als synchronisierte reguläre Dateien bewertet.

Diese Grenzen gelten für den Statusmodus. Der ausdrücklich beauftragte Merge
verwendet stattdessen die Verschiebe- und Prüfregeln der Merge-Referenz.

Bei Zugriffsfehlern nenne den betroffenen Bereich. Prüfe die Ausgabe, bevor du
fehlende macOS-Berechtigungen als Ursache behauptest. Falls nötig kann der Nutzer
Codex bzw. dem ausführenden Terminal Zugriff auf Dateien oder Festplattenvollzugriff
gewähren. Berechtigungen, iCloud-Einstellungen und Sync-Dienste nicht verändern.
Keine Downloads/Uploads erzwingen, keine Dateien öffnen, verschieben oder evicten,
keine Daemons beenden und keine iCloud-Datenbanken bearbeiten.

`brctl status/accounts` kann Kontodaten und Tokens enthalten. Niemals ungefilterte
Ausgaben ausgeben oder speichern; der Prüfer übernimmt nur ausgewählte Statusfelder.

Quellen für die Bedeutung der Zustände:
- [Apple: iCloud-Dateistatus im Finder](https://support.apple.com/de-de/guide/mac-help/mchlc994344b/mac)
- [Apple: Upload-Status](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemisuploadedkey)
- [Apple: Download-Status](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus)
