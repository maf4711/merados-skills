---
name: dm8080s
description: >
  Use when the user mentions dm8080s, 80s80s, Depeche Mode Radio on HomePods
  from the Mac, radio an/aus, überall spielen, Besuchsmodus, Gäste, AirPlay stall,
  watchdog restart loop, Music pause-loop, /dm8080s, or the DM8080s menu-bar app.
  Mac-as-source house radio (Music + AirPlay). Not Macaro/Siri — that is
  depeche-mode-radio.
---

# DM8080s — Mac-Radio, kleinste sichere Aktion

Repo: `~/Developer/DM8080s` · CLI: `dm8080s` (`~/bin/dm8080s`) · App: `~/Applications/DM8080s.app`  
Stream: HTTP `https://streams.80s80s.de/dm/mp3-192/streams.80s80s.de/`  
**Nie** Apple-Music-Sender `ra.1461987621` — der lädt async und pausiert den HTTP-Stream.

Default: **status → kleinste Aktion → verify**. Nicht blind `play` / Full-Reselect.

## Zuerst live lesen

```bash
dm8080s status
tail -n 40 ~/Library/Logs/dm8080s.log
```

Webhook-Status (LAN, **nicht** localhost — `:8787` auf `127.0.0.1` ist oft fabrik):

```bash
curl -sS --max-time 3 "http://$(ipconfig getifaddr en0):8787/status"
```

Token nie im Chat ausgeben. `dm8080s presence` zeigt URLs mit `?token=` — Token redigieren.

## Intent

| User | Befehl | Warum |
|------|--------|--------|
| an / on / spiel / überall | `dm8080s on` nur wenn **nicht** schon HTTP-playing | `on` = presence home + LaunchAgent. Läuft der Stream schon → nichts anfassen |
| aus / radio aus | `dm8080s off --keep-http` | Watchdog + Music weg, **Webhook bleibt** (App/Handy) |
| alles tot / wirklich aus | `dm8080s off` | killt auch Presence-Server |
| pause / stop | `dm8080s stop` | Watchdog weg, Presence bleibt, Music pause |
| Besuch / Gäste an | `dm8080s besuch on` | Override Handy-away |
| Besuch aus | `dm8080s besuch off` | wenn presence=away → Radio aus |
| lauter / leiser | `dm8080s lauter` / `leiser` | HomePod-Volume, nicht Mac-Speaker |
| Status / warum still | status + log, dann heilen | nicht raten |

App-Buttons = dieselben Webhook-Pfade (`/on`, `/off` = `--keep-http`, `/stop`, `/besuch/on|off`, `/lauter|/leiser`).

## Heal (auto, lokal, sicher)

1. `dm8080s status` + letzte Logzeilen.
2. Track `ra.1461987621` / `music.apple.com` → HTTP wieder öffnen: `dm8080s once` **nur wenn paused/stopped**. Wenn schon `playing` + `dm/mp3` → nichts.
3. Watchdog tot, User will Radio → `dm8080s on` (LaunchAgent only, kein zweites nohup).
4. Mehrere Watchdogs / Doppel-Play → **nicht** `pkill -f watchdog.sh` (trifft den launchd-Wrapper). Nur LaunchAgent-PID / `dm8080s stop` dann `on`.
5. False stall `position=0` bei `kind=url` / `dur≤0` → **kein** Restart. Messung, kein toter Stream.
6. Pause-Loop (an/aus alle paar Sekunden) → meist Full-Reselect oder Station. Soft-Play, Gruppe nicht zerlegen.
7. Webhook down auf LAN, localhost antwortet HTML → fabrik, nicht dm8080s. Presence-LaunchAgent prüfen, App nutzt LAN-IP.

Danach erneut `dm8080s status`. Beweis: `playing` + Track enthält `dm/mp3` + ein Watchdog + keine `RESTART` in den nächsten ~30s.

## Grenzen (nicht erzwingen)

- **Wohnzimmer** ist vom Mac oft sichtbar, aber nicht selektierbar. 4–5/6 Pods = Erfolg.
- **Back** flaky. Nicht in einer Endlosschleife reselecten.
- CarPlay + HomePods als **eine** Gruppe kann Apple nicht. Auto = Macaro Car; Wohnung = dieser Skill.
- Ohne laufenden Mac kein Mac-AirPlay.

## Nie

- `open location` auf `ra.1461987621` / `music.apple.com`
- Alle AirPlay-Geräte deselektieren (hörbarer Stop auf jedem Pod)
- Full-Play / Gruppe neu bauen, wenn HTTP schon spielt
- Token, `presence.token`, volle Webhook-URLs mit Secret loggen
- `127.0.0.1:8787` als dm8080s behandeln
- `pkill -f …watchdog.sh`
- Tests skippen / `--no-verify` als Heal verkaufen

## Routing

- „Hey Siri, Macaro“ / ohne Mac / CarPlay → **depeche-mode-radio**
- Alles mit Mac als Quelle, Watchdog, Besuch, Stall, App → **dieser Skill**
