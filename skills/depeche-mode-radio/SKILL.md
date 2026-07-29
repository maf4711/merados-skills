---
name: depeche-mode-radio
description: >
  80s80s Depeche Mode Radio — HomePod-Siri ohne Mac, Multi-Room wo möglich.
  Trigger: "Hey Siri, Macaro", "Macaro", "Macaro Car", "/depeche".
  Macaro: Apple-Music-Sender + AirPlay-2 zu allen bekannten HomePods.
  Macaro Car: Sender auf iPhone/CarPlay. CarPlay+HomePods gleichzeitig
  als eine Gruppe kann Apple nicht — siehe Doku.
---

# Macaro — 80s80s Depeche Mode (ohne Mac)

## Was du sagst

| Phrase | Wirkung |
|--------|---------|
| **Hey Siri, Macaro** | Sender starten + **alle konfigurierten HomePods** (AirPlay 2 Add) |
| **Hey Siri, Macaro Car** | Sender auf **iPhone / CarPlay** (Auto) |

Sender: [80s80s Depeche Mode](https://music.apple.com/de/station/80s80s-depeche-mode/ra.1461987621) (`ra.1461987621`)

## CarPlay + alle HomePods — ehrliche Grenze

**Apple kann nicht:** eine einzige Wiedergabe gleichzeitig auf **CarPlay und allen HomePods** als Multi-Room-Gruppe (Auto ist kein AirPlay-2-Mitglied wie HomePods).

| Situation | Was „Macaro“ macht |
|-----------|-------------------|
| **Zuhause** (iPhone oder HomePod) | Station + HomePods per AirPlay 2 bündeln |
| **Im Auto** (CarPlay) | **Macaro Car** → Ton im Auto |
| **Auto und Wohnung gleichzeitig** | **Nicht** als ein Stream — zwei getrennte Sessions bräuchten zwei Geräte/Streams (Abo-Limits) |

**Ohne Mac** ist der realistische Setup:

1. Zuhause: **Macaro** → alle HomePods  
2. Auto: **Macaro Car** → CarPlay  

## Einmalig auf dem iPhone (wichtig)

Der Kurzbefehl enthält eure HomePod-Namen:

`Küche` (primär), dann Add: `Back`, `Badezimmer`, `Büro`, `Schlafzimmer`, `Wohnzimmer`

**Küche** und **Wohnzimmer** haben echte Route-IDs aus deinem System.  
Die anderen können beim ersten Mal leer sein → einmal im Kurzbefehl nachziehen:

1. iPhone → **Kurzbefehle** → **Macaro** öffnen  
2. Jede Aktion **„Wiedergabeziel festlegen“** antippen  
3. Den passenden **HomePod** wählen (Add bleibt Add)  
4. Speichern → iCloud → HomePods  

Ohne diesen Schritt hören oft nur die HomePods mit gültiger Route (Küche/Wohnzimmer) bzw. nur das Gerät, das Siri hört.

### Optional: Home-App-Gruppe „Überall“

Zusätzlich (oder als Fallback):

1. App **Home** → Lautsprecher → Gruppe mit allen HomePods  
2. Siri: *„Spiel 80s80s Depeche Mode auf Überall“*

## Kurzbefehl-Inhalt (Macaro)

1. Kommentar (Doku)  
2. URL = Apple-Music-Station  
3. URL öffnen  
4. Wiedergabeziel **Set** → Küche  
5. Wiedergabeziel **Add** → Back, Badezimmer, Büro, Schlafzimmer, Wohnzimmer  

Läuft auf **iPhone / HomePod** (iCloud), **kein Mac** zur Laufzeit.

## Dateien

| Datei | Zweck |
|-------|--------|
| `shortcuts/Macaro.wflow` | Multi-HomePod |
| `shortcuts/Macaro Car.wflow` | CarPlay/iPhone |
| `shortcuts/build/*.shortcut` | signiert, importierbar |
| `shortcuts/Macaro-Mac.wflow` | alter Mac-AirPlay-Weg (optional) |

Neu signieren / importieren:

```bash
cd ~/Developer/merados-skills/skills/depeche-mode-radio/shortcuts
shortcuts sign -m anyone -i Macaro.wflow -o build/Macaro.shortcut
shortcuts sign -m anyone -i "Macaro Car.wflow" -o "build/Macaro Car.shortcut"
open build/Macaro.shortcut
open "build/Macaro Car.shortcut"
```

## Agent-Verhalten

- „Macaro“ / HomePods / ohne Mac → **nicht** `depeche-mode-radio` (Mac-AirPlay) starten  
- User will **explizit** Mac-AirPlay → CLI `depeche-mode-radio` / `Macaro-Mac`  
- CarPlay-Fragen → Grenze erklären + **Macaro Car**

## Nicht tun

- Nicht behaupten, CarPlay + alle HomePods liefen als **ein** Stream ohne Mac  
- Offline-HomePods nicht erzwingen  
- Mac nicht als Default-Orchestrierung nutzen, wenn User „ohne Mac“ will  
