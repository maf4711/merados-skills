---
name: depeche-mode-radio
description: >
  80s80s Depeche Mode Radio auf alle adressierbaren, angeschalteten HomePods.
  Trigger: "/depeche", "/depeche-mode-radio", "Depeche Mode Radio", "80s80s Depeche",
  "Depeche Mode auf HomePods", "HomePod Radio Depeche", "spiel Depeche Mode Radio",
  "DM Radio HomePods". Spielt den Live-Stream 80s80s Depeche Mode und AirPlay nur
  auf HomePods mit kind=HomePod, available=true und erfolgreich selected.
---

# Depeche Mode Radio → HomePods

Spielt **80s80s Depeche Mode Radio** (Live-Stream) über Apple Music AirPlay auf
**alle erreichbaren HomePods**. Offline / nicht adressierbare Geräte werden
übersprungen (kein Fehler-Spam).

## Sofort ausführen

Bei Trigger **ohne** Extra-Anweisung direkt starten:

```bash
~/.agents/skills/depeche-mode-radio/scripts/depeche-mode-radio
```

Oder (gleicher Wrapper):

```bash
depeche-mode-radio
```

Skript: `scripts/play-depeche-mode-homepods.applescript` (osascript + Music).

## Filter-Regeln (nicht ändern)

Nur Geräte mit:

1. `kind = HomePod` (kein Computer, kein Apple TV)
2. `available = true` (an / im Netzwerk)
3. Nach `set selected … true` ist `selected` wirklich `true`

Sonst: **skip** mit Grund (`offline` / `nicht adressierbar`).

Stream-URL (80s80s Depeche Mode):

`https://streams.80s80s.de/dm/mp3-192/streams.80s80s.de/`

## Antwort an den User

Kurz melden, was das Skript zurückgibt, z.B.:

```
Playing: Back, Badezimmer, Büro, Küche, Schlafzimmer | playing
skip: Wohnzimmer (nicht adressierbar)
```

- **Playing:** aktiv AirPlay-HomePods  
- **skip:** offline oder nicht multi-room adressierbar  
- Bei Exit ≠ 0: Fehlertext zeigen (z.B. kein HomePod online)

## Optionale Varianten

| User sagt | Aktion |
|-----------|--------|
| (nur Trigger) | Radio starten (default) |
| „Status“ / „welche HomePods“ | `osascript -e 'tell application "Music" to get name of every AirPlay device whose selected is true and kind is HomePod'` + player state |
| „Stop“ / „stopp“ | `osascript -e 'tell application "Music" to pause'` |
| „nur Wohnzimmer“ | **Nicht** im Default-Skript — User darauf hinweisen, dass der Skill absichtlich **alle** adressierbaren HomePods nimmt; manuell in Music AirPlay ändern |

## Manuelle Shortcuts (User, kein Agent)

- App: `~/Applications/Depeche Mode Radio.app`
- Desktop: `~/Desktop/Depeche Mode Radio.command`
- CLI: `~/bin/depeche-mode-radio` → Skill-Skript
- Siri: Kurzbefehl mit Shell-Skript + Phrase „Depeche Mode Radio“ (iCloud → HomePod: „Hey Siri, Depeche Mode Radio“)

## Abhängigkeiten

- macOS, App **Musik** (Apple Music / Internet-Radio-Stream)
- HomePods im gleichen Apple-Account / Netzwerk
- Kein API-Key

## Nicht tun

- Keine Offline-HomePods erzwingen
- Mac (`computer`) nicht als AirPlay-Ziel setzen
- Stream-URL nicht ohne Grund ändern
- Nicht nachfragen, wenn der User klar „Radio starten“ meint — einfach ausführen
