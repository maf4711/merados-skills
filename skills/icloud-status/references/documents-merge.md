# Dokumentenbestände mehrerer Macs zusammenführen

## Gewünschtes Ergebnis

Ein kanonischer Dokumentenbaum unter `~/Documents`. Die **Inhalte** ausgewählter
Geräteordner gehen in dessen bestehende Unterordner ein. Kein neuer oberster
Ordner pro Rechner und keine pauschale Neuordnung der vorhandenen Kategorien.

Beispiel: `Dokumente-MacBook/Finanzen/2025.pdf` wird zu
`~/Documents/Finanzen/2025.pdf`. Ist dieser Dateiname bereits belegt, bleibt die
zusätzliche Kopie als `2025 (von MacBook).pdf` erhalten. Auch inhaltsgleiche Dateien
behalten: **Der Nutzer sortiert Duplikate selbst aus.** Keine Hash-Deduplizierung,
kein Überschreiben, keine automatische Auswahl der „neueren“ Version.

## Quellen erkennen und eingrenzen

```bash
/usr/bin/python3 ~/.codex/skills/icloud-status/scripts/documents_merge.py discover
```

Die Suche ist begrenzt und klassifiziert Kandidaten, nicht automatisch autorisierte
Quellen. Apple kann den Importordner **nur nach dem Rechner** benennen, ohne
„Documents“ im Namen. Bekannte Namen mit `discover --machine-name 'Anna Büro'`
übergeben und die ebenfalls ausgegebenen übrigen direkten Unterordner prüfen.
Maschinenähnliche Namen allein sind kein Beweis für einen Dokumentenimport.
Prüfe tatsächliche Verzeichnisse und ihre Herkunft. `Documents`,
`Documents 2` oder ähnliche Einträge können lediglich auf denselben `~/Documents`
zeigen; solche Aliase niemals gegeneinander mergen. Links in Vaults und
Projektablagen sind ebenfalls keine eigenständigen Dokumentenbestände.

Archive, Backups, `_Alt-Documents-*` und `Dubletten` nicht ungefragt wieder in die
aktive Ablage aufnehmen. Eine Zustimmung zu mehreren Geräteordnern umfasst nicht
automatisch deren historischen Backups. Sind Quellen unklar, zeige die konkreten
Pfade und kläre nur diese Auswahl; Skill-Implementierung und Vorschau fortsetzen.

Bestände anderer Macs müssen über iCloud auf diesem Mac sichtbar sein. Dieser
Skill eröffnet keine SSH-Verbindungen und aktiviert keine iCloud-Einstellungen.
Nicht sichtbare Rechnerbestände ausdrücklich als nicht erfasst nennen.

## Konkreten Plan erstellen

Pro Quelle einen Plan erzeugen, nacheinander. Dadurch sieht jeder weitere Plan
die tatsächlich entstandene Zielstruktur und berücksichtigt neue Kollisionen.

```bash
/usr/bin/python3 ~/.codex/skills/icloud-status/scripts/documents_merge.py plan \
  --source '/absoluter/Pfad/Dokumente-MacBook' --label 'MacBook'
```

Standardziel ist `~/Documents`; `--target` nur für ein ausdrücklich anderes Ziel
oder isolierte Tests verwenden. **Das echte gemeinsame Ziel muss als iCloud-Ordner
bestätigt sein.** Der Helfer prüft dies beim Planen und erneut beim Ausführen.
Ein deaktiviertes oder nicht bestätigtes `~/Documents` ist ein Blocker; Dateien
aus iCloud dürfen nicht versehentlich in einen nur lokalen Ordner herausgezogen
werden. Lokale Testbestände außerhalb der echten Dokumentenordner sind zulässig.
`--seconds` (Standard 60) und `--max-entries`
(Standard 100000) begrenzen die Planung. Ein erreichtes Limit erzeugt keinen
ausführbaren Teilplan. Der Plan liegt lokal unter
`~/.local/state/icloud-status/merges/`, außerhalb der synchronisierten Dokumente.

Zeige Quelle, Ziel, Anzahl Verschiebeeinträge, Namenskollisionen, Blocker und
repräsentative Zielpfade. Ein Eintrag kann einen vollständigen Unterordner samt
Inhalt darstellen: **Verschiebeeinträge nicht als Gesamtdateizahl ausgeben**.
Der JSON-Plan enthält die vollständige Liste und seine SHA-256-Prüfsumme.

Ordner mit gleichem Namen werden rekursiv zusammengeführt. App-/Dokumentpakete und
`.git` bleiben unteilbar; bei Konflikten bleibt das zusätzliche Paket mit
Herkunftszusatz bestehen. Die vorhandene Zielordner-Metadatenstruktur hat Vorrang.
Direkte Symlinks bleiben als Link erhalten, wenn ihr unverändertes absolutes Ziel
innerhalb des kanonischen Dokumentenbaums und außerhalb der Quelle liegt. Es muss
bereits als Datei oder Ordner existieren, ohne weitere Symlinks im Zielpfad.
Der Helfer prüft das vor der Planung und erneut beim Verschieben. Das Linkziel
wird dabei weder geöffnet noch verändert; Schleifen werden abgewiesen.
Relative/externe Links, Spezialdateien und alte `.icloud`-Platzhalter sind Blocker
zur Prüfung; ganze verschobene Unterordner behalten ihren Inhalt
unverändert, einschließlich interner Links. Relative Verweise auf Ziele außerhalb
des verschobenen Unterbaums können durch den neuen Ort ungültig werden; solche
bekannten Projekt-/Aliasbestände vorab gesondert prüfen.

## Ausführen und verifizieren

Bei einem tatsächlichen Merge-Auftrag und klar ausgewählten Quellen den geprüften
Plan ausführen. Bestehende Zustimmung gilt weiter. Falls der Nutzer bislang nur
eine Skill-Erweiterung beauftragt hat, zunächst den konkreten Plan liefern.

```bash
/usr/bin/python3 ~/.codex/skills/icloud-status/scripts/documents_merge.py apply \
  --plan '/lokaler/Pfad/plan-….json' --sha256 'Prüfsumme-aus-der-Planung'
```

Der native Helfer koordiniert Verschiebungen mit macOS und verwendet atomare
Umbenennungen, die ein vorhandenes Ziel **nicht ersetzen**. Quelle und Ziel müssen
auf demselben Volume liegen. Kein Rückfall auf „kopieren und anschließend löschen“.
Metadaten und Dateiinhalt bleiben beim Verschieben erhalten; reine Cloud-Dateien
werden nicht absichtlich heruntergeladen. Erlaubt sind ausschließlich die
planmäßig ausgewählten Verschiebungen und das Entfernen danach leerer Quellordner.
Keine Inhalte löschen, keine Cloud-Dienste neu starten, keine Konten umstellen.

Vor jeder Operation wird ein lokaler Journaleintrag dauerhaft geschrieben, danach
das Ergebnis. Bei veränderten Quellen, neu belegten Zielen, Pfadumleitungen oder
einem Fehler sofort stoppen und das Journal nennen. Bereits ausgeführte Operationen
nicht zurückbehaupten oder blind wiederholen. Für eine Fortsetzung die verbliebene
Quelle neu planen und aktuelle Kollisionen erneut berücksichtigen. Das Journal
ermöglicht eine gezielte Rückführung; ein automatischer Undo-Befehl existiert nicht.

Nach erfolgreicher lokaler Zusammenführung Status prüfen. „Lokal zusammengeführt“
und „auf allen Macs angekommen“ getrennt berichten. Letzteres erst behaupten,
wenn Upload und die Zielgeräte tatsächlich geprüft wurden. Bei Providerfehlern
die lokalen Änderungen und ausstehende Synchronisierung präzise melden.

Ein Skill kann Apples Erzeugung von Geräteordnern beim Hinzufügen eines Macs nicht
abschalten. Ziel ist: erkannte, ausgewählte Gerätebestände wieder in den gemeinsamen
Dokumentenbaum integrieren. Weitere Macs verwenden diesen Baum über dieselbe
iCloud-Drive-/Schreibtisch-und-Dokumente-Konfiguration; keine neuen Geräteordner
als dauerhaftes Arbeitsziel anlegen.

Quellen:
- [Apple: Geräteordner beim Hinzufügen eines weiteren Macs](https://support.apple.com/en-sg/118443)
- [Apple: Dateien verschieben, vorhandene Ziele werden nicht ersetzt](https://developer.apple.com/documentation/foundation/filemanager/moveitem(at:to:))
- [Apple: Koordination einer Verschiebung](https://developer.apple.com/documentation/foundation/nsfilecoordinator/writingoptions/formoving)
