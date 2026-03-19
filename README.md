# meradOS Skills

Agent Skills fuer Claude Code nach dem **Elon 5-Schritt-Algorithmus**: Hinterfragen → Loeschen → Vereinfachen → Beschleunigen → Automatisieren.

## Installation

```bash
# Alle Skills
npx skills add maf4711/merados-skills

# Einzeln
npx skills add maf4711/merados-skills@merados-desktop
npx skills add maf4711/merados-skills@merados-slack-advisor
npx skills add maf4711/merados-skills@elon-algo
```

---

## Skills

### meradOS Desktop (`/merados-desktop`)

Das komplette macOS-Setup fuer Entwickler. 1400+ Zeilen, 5 Phasen, 44 Sektionen. Analysiert den IST-Zustand, raeumt auf, optimiert und automatisiert - alles in strenger Reihenfolge.

#### Phase 1: HINTERFRAGEN - Was laeuft und warum?

| Sektion | Was wird gecheckt |
|---------|-------------------|
| **System-Analyse** | RAM, CPU, Disk, Uptime, Top 20 RAM/CPU-Fresser, Login Items, LaunchAgents |
| **Terminal-Analyse** | Shell-Startup-Zeit, 14 Dev-Tools-Check, Plugins, HISTSIZE, EDITOR, Init-Blocker, Nerd Font |
| **Security-Check** | FileVault, Firewall, Gatekeeper, SIP, Remote Login |
| **Hardware/Tool-Status** | Keyboard Speed, SSH Config, iTerm2, Docker, Raycast/Alfred |
| **Claude Code Status** | Version, MCP Servers, Settings (global vs projekt), Skills, GSD, Hooks |

#### Phase 2: LOESCHEN - Alles was nicht absolut noetig ist

| Sektion | Was wird entfernt |
|---------|-------------------|
| **Prozesse & Agents** | Verwaiste LaunchAgents, unnoetige Hintergrund-Agents (Adobe, Google, Spotify...) |
| **Apps** | Brew-Pakete ausmisten, autoremove, cleanup |
| **Speicherfresser** | Caches, Logs, DerivedData, CoreSimulator, Trash, alte Downloads |
| **Docker Cleanup** | Dangling Images, gestoppte Container, unbenutzte Volumes (oft 20-50 GB) |
| **Shell-Config** | Tote Aliases, doppelte/tote PATH-Eintraege |
| **Telemetrie** | Homebrew Analytics, VS Code Telemetrie, CrashReporter |

#### Phase 3: VEREINFACHEN - Weniger ist schneller

| Sektion | Was wird vereinfacht |
|---------|---------------------|
| **macOS-Defaults** | Dock/Finder/Mission Control Animationen deaktivieren |
| **Hidden Defaults** | Show hidden files, Finder Path-Bar, Screenshots-Ordner, .DS_Store auf Netzwerk |
| **Keyboard Speed** | KeyRepeat 1, InitialKeyRepeat 10, Auto-Korrektur aus, Smart Quotes aus |
| **Spotlight** | Dev-Verzeichnisse von Indexierung ausschliessen |
| **DNS** | Cloudflare 1.1.1.1 / Google 8.8.8.8 wenn >100ms |
| **SSH Config** | ControlMaster (Verbindungen wiederverwenden), KeepAlive, AddKeysToAgent, Compression |
| **Shell-Config** | Conda lazy-load (~200ms gespart), History 100k dedupliziert, Case-insensitive Completion |

#### Phase 4: BESCHLEUNIGEN - Jede Sekunde zaehlt

| Sektion | Was wird installiert/konfiguriert |
|---------|----------------------------------|
| **System-Metriken** | Memory Pressure, Thermal, SSD Health, WindowServer CPU |
| **Brew** | doctor, outdated |
| **Netzwerk** | Latenz zu github.com, google.com, cloudflare.com |
| **Nerd Font** | font-meslo-lg-nerd-font installieren + iTerm2 konfigurieren |
| **iTerm2 Profil** | Unlimited Scrollback, Natural Text Editing, Catppuccin Theme, Hotkey Window |
| **Dev-Tools** | eza, bat, fd, rg, fzf, zoxide, delta, jq, yq, lazygit, atuin, btop, tldr, gh |
| **Git-Config** | delta (side-by-side), rerere, autoStash, fsmonitor, histogram diff, pull.rebase |
| **Raycast** | Keyboard-First Launcher als Spotlight-Ersatz |
| **Aliases + Funktionen** | 20+ Git-Aliases, Docker-Aliases, fzf-Funktionen (f, fcd, fgl, fkill), pk, extract, big, headers |
| **Claude Code Settings** | 143 globale Permissions ohne Rueckfragen, rm/sudo bleibt gesperrt |
| **Claude Code MCPs** | GitHub, Slack, Playwright, Sequential Thinking |
| **Claude Code Skills** | GSD, Superpowers, VibeSec + Awesome-Listen |
| **Code-Quality** | 300-Zeilen-Regel, Modularitaet, CLAUDE.md Template, Scan-Befehl fuer grosse Dateien |
| **Command-Timer** | Ausfuehrungszeit >3s im Prompt, macOS-Notification >30s |

#### Phase 5: AUTOMATISIEREN - Aber nur was funktioniert

| Sektion | Was wird automatisiert |
|---------|----------------------|
| **Meister-Script** | Pruefen ob installiert + LaunchAgent aktiv |
| **Shell-Automationen** | zoxide init (smart cd), atuin init (History-Search) + import |
| **Brewfile** | Reproduzierbares Setup exportieren, ins Migration-Bundle |
| **Security Hardening** | FileVault, Firewall aktivieren, Analytics abschalten |
| **Weitere Automationen** | Auto-Backup, Cleanup, Update-Empfehlungen |
| **.zshrc Backup** | Automatisch vor jeder Aenderung |
| **Slack Advisor** | Projekt scannen, Slack-Integrationen vorschlagen, Utility generieren |

#### Extras

- **Report** mit vorher/nachher Metriken (RAM, Disk, Prozesse, Shell-Start, Tools, HISTSIZE, KeyRepeat, Security-Score, SSH, Nerd Font, Brewfile, Claude Code, Slack)
- **Philosophie** - Was Elon auf seinem Mac haette (und was nicht)
- **Cheat-Sheet** - Alle Shortcuts auf einen Blick (Navigation, History, Files, Git, System, macOS, Claude Code)
- **9 Regeln** - Nie destruktiv ohne Frage, Dry-Run first, Rollback-Info, Reihenfolge 1→5, .zshrc Backup, SSH Keys nie anzeigen

---

### meradOS Slack Advisor (`/merados-slack-advisor`)

Analysiert ein Projekt und schlaegt Slack-Integrationen + Automatisierungen vor. Standalone-Version mit 475 Zeilen fuer tiefere Analyse. Kompakt-Version ist in meradOS Desktop Phase 5g integriert.

#### Was der Skill macht

1. **Projekt scannen** - Framework, Dependencies, API-Routes, DB-Modelle, Cron-Jobs, CI/CD, bestehende Integrationen
2. **Elon-Filter** - Was NICHT nach Slack gehoert (jeden Commit, jeden erfolgreichen Build, Health-Checks die OK sind)
3. **Vereinfachen** - Webhook > Bot > App, max 4 Channels, Channel-Strategie
4. **Integrationen vorschlagen** - Nur was zum Projekt passt:
   - Deploy-Notifications (GitHub Actions)
   - Error-Spike-Alerts (Threshold-basiert)
   - Daily Digest (Business-Metriken)
   - Cron-Health-Monitoring
   - API-Uptime-Checks
   - Security-Anomalien
   - PR-Review-Reminders
   - DB-Alerts
5. **Automatisieren** - Minimale Slack-Utility (TypeScript + Python), ENV-Template, Impact/Aufwand-Matrix, Automatisierungs-Check jenseits Slack

#### Elon-Regeln fuer Slack

- Jede Nachricht braucht einen Empfaenger mit Namen
- Wenn niemand handeln muss → nicht senden
- Digest > Echtzeit fuer alles was nicht kritisch ist
- Failures > Successes - nur Abweichungen melden
- Thresholds > Absolutes - "Error-Spike" statt "Error aufgetreten"
- Max 4 automatisierte Channels

---

### Elon Algorithm (`/elon-algo`)

Der 5-Schritt-Algorithmus als eigenstaendiger Skill. Wendet die Methodik auf jede beliebige Aufgabe an.

1. **Make Requirements Less Dumb** - Jede Anforderung hinterfragen. Wer hat das verlangt? Was passiert wenn wir es NICHT machen?
2. **Delete the Part or Process** - Loeschen was nicht absolut noetig ist. Wenn du nicht 10% zurueckfuegen musst, hast du nicht genug geloescht.
3. **Simplify and Optimize** - Erst NACHDEM geloescht wurde. Nie optimieren was nicht existieren sollte.
4. **Accelerate Cycle Time** - Erst NACHDEM vereinfacht wurde. Kuerzere Feedback-Loops = schnelleres Lernen.
5. **Automate** - Erst NACHDEM beschleunigt wurde. Einen schlechten Prozess automatisieren macht ihn nur schneller schlecht.

---

## Philosophie

```
Minimaler Code, maximale Wirkung.
Keine Abstraktion ohne Grund.
Loeschen vor Refactoring.
Reihenfolge ist kritisch: 1→2→3→4→5, nie umgekehrt.
```
