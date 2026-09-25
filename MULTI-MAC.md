# Multi-Mac

Dieses Repo wird auf mehreren Macs bearbeitet und von jedem Mac released, der als `maf4711` bei GitHub angemeldet ist. GitHub ist die einzige Wahrheit. `~/Developer` liegt nicht in iCloud oder Dropbox.

Stand der Fakten: 2026-09-25, aufgenommen auf `mbpM5MaxMF-6.local` (User `a321`). Pfade sind `$HOME`-relativ.

## Dieses Repo

| | |
|---|---|
| GitHub | `maf4711/merados-skills` |
| SSH | `git@github.com:maf4711/merados-skills.git` |
| Remote dieses Checkouts | `git@github.com:maf4711/merados-skills.git` |
| Ordner | `~/Developer/merados-skills` |
| Default-Branch | `main` |

### Release

- GitHub Actions: `ci.yml`. Der Default-Branch bleibt der auslieferbare Stand.

Sync dieses Stands auf die anderen Macs:

```bash
~/.claude/skills/repo-sync/devsync.sh ship
```

## Auf einem weiteren Mac bearbeiten

1. `git`, GitHub CLI, SSH-Key. `gh auth login` mit Protokoll SSH. `ssh -T git@github.com` antwortet `Hi maf4711`.
2. Einmal einrichten:

```bash
git clone git@github.com:maf4711/merados-skills.git ~/Developer/merados-skills
bash ~/Developer/merados-skills/skills/repo-sync/setup-mac.sh
```

Das klont `maf4711`, `MeradosUG` und `FinfuxUG` nach `~/Developer`, verlinkt die Skill-Suite nach `~/.claude`, `~/.grok`, `~/.codex` und `~/.agents` und lädt den LaunchAgent `com.merados.devsync`.

3. Dieser Checkout liegt danach unter `~/Developer/merados-skills`. Weicht der Ordner vom Repo-Namen ab, weil zwei Orgs denselben Namen haben, heißt er `~/Developer/<owner>--<name>`.
4. Vor und nach der Arbeit: `devsync.sh status`, dann `devsync.sh sync`.
5. Identität: `marco` / `foellmer@mac.com`. Merge mit `git merge --no-edit`, kein Rebase, kein Force-Push.
6. `devsync` committet auf dem Default-Branch nur bereits getrackte Dateien. Neue Dateien vorher `git add`. Feature-Branches, Rebase, Merge und detached HEAD lässt es liegen.

## Von jedem Mac releasen

Gemeinsame Identität. Dateiinhalt der Schlüssel steht hier nicht.

| | |
|---|---|
| GitHub-Login | `maf4711` (Marco Föllmer) |
| Orgs | `maf4711`, `MeradosUG`, `FinfuxUG`. Neue Remotes: `maf4711/<name>`, privat |
| Apple ID | `foellmer@mac.com` |
| Team | `K63X3ZTV3Q` |
| ASC Key-ID | `5BXD2V69GS` |
| ASC Issuer | `18daeaec-9343-4c57-9b01-481a7da981c6` |
| ASC Key-Datei | `~/.appstoreconnect/private_keys/AuthKey_5BXD2V69GS.p8` |
| Weitere Key-Dateien | `AuthKey_DLC56TFN8B.p8`, `AuthKey_AA42M2D5C8.p8`, `AuthKey_QCCHWPHR8X.p8`, `AuthKey_WA46CWAG8B.p8` im selben Ordner |
| Developer ID | `B6EAF16C978F2AC019070F04C3B0C6052ED0342E` (CN ist doppelt; zweites Zertifikat `F588A236CBD8DF58BE4FADEB194F0EDEDBD6EFF4`) |
| Apple Distribution | `B534280F66FFD01FE031AD3E5A648E433ACA070E` |
| Apple Development | `C656D0B3D14E9436C2004CEFB67A47502880287A` |
| Release-Xcode | `/Applications/Xcode.app` (auf dem Aufnahme-Mac Xcode 27.0, Build 27A266a) |
| Ausgewählte Xcode-Beta | `xcode-select` zeigte auf Xcode 27.2 unter `/Applications/Xcode-27.2.0-beta.app`. Upload setzt `DEVELOPER_DIR` auf `/Applications/Xcode.app/Contents/Developer` |
| Vercel-Teams | `merad-os` (`team_IUxcUMLFPZ8priEjxQQhELMV`), `marco-3586s-projects` (`team_5jCZvKWdsJFJEjzTthY1ZcLA`) |
| Homebrew | `/opt/homebrew`. Nach einem Meister-Release `brew update && brew reinstall maf4711/meister/meister` |
| Skill-Suite | Changelog-Tag, `gh release`, dann `~/Developer/Skill-Suite/install.sh` |
| CPR | `cpr` = Commit + Merge `origin` + Push + Production. `mcprt` zusätzlich TestFlight `intern` und `Extern` |

Einmal pro Mac, außerhalb von Git: den Ordner `~/.appstoreconnect/private_keys/` von einem Mac kopieren, der die `.p8`-Dateien schon hat (AirDrop oder `scp`). In Xcode mit `foellmer@mac.com` anmelden, damit Team `K63X3ZTV3Q` im Schlüsselbund liegt. `vercel login` auf beiden Teams.

Export von Archiven: `/usr/bin` vor dem Homebrew-`rsync` im `PATH`.

## Macs

| Maschine | Zugang | Rolle |
|---|---|---|
| `mbpM5MaxMF-6.local` | lokal, User `a321` | Aufnahme-Mac, `~/Developer` |
| `CM-CFMQ2D029F` | Thunderbolt `10.42.0.1` | Cluster node-a |
| `CM-KWFVR7JGW3` | `a321@10.42.0.2` | Cluster node-b |
| `mbpM5MaxMF` | `a321@10.42.0.3` | Cluster node-c |
| `mos1` `mos2` `mos3` `mos4` | SSH, Konten `jmerados1..4` | bekommen den Branch per `devsync` Node-Push. GitHub-Release läuft auf einem Mac mit Login `maf4711` |

`mos1`–`mos4` lesen private GitHub-Repos nicht. Der Code kommt vom Mac mit `maf4711` per fast-forward, ohne `--force`.

## Nie committen

`.env`, `*.p8`, `*.pem`, `*.key`, `AuthKey_*`, `credentials.json`, `secrets.json`, `*.xcarchive`, `.build/`, `DerivedData`.

Neu stempeln: `python3 ~/Developer/Skill-Suite/skills/repo-sync/scripts/stamp-multi-mac.py --write`.
