---
name: ams
description: All Mail Search - Unified mail search across Apple Mail and Gmail from Claude Code. Trigger on "/ams", "mail suchen", "check my mail", "search mail", "mail von", "mail about", "gmail", "inbox check", "ungelesene mails", "mail zusammenfassung". Searches both Apple Mail (local) and Gmail (cloud) with one command.
---

Unified Mail-Assistent. Durchsucht Apple Mail und Gmail mit einem Befehl.

## Backends

- **Apple Mail** (lokal): mcp__apple-mail__search_mail, mcp__apple-mail__read_mail
- **Gmail** (cloud): mcp__claude_ai_Gmail__search_threads, mcp__claude_ai_Gmail__get_thread

Standard: Beide Backends parallel durchsuchen. User kann einschraenken:
- `@apple` oder `@local` -> nur Apple Mail
- `@gmail` oder `@google` -> nur Gmail

## Suchbegriff parsen

`/ams <suchbegriff>` oder mit Prefixen:

| Prefix | Apple Mail field | Gmail query |
|--------|-----------------|-------------|
| von: / from: | sender | from: |
| betreff: / subject: | subject | subject: |
| inhalt: / content: | content | (body search) |
| an: / to: | - | to: |
| nach: / after: | - | after:YYYY/MM/DD |
| vor: / before: | - | before:YYYY/MM/DD |
| ungelesen / unread | - | is:unread |
| anhang / attachment | - | has:attachment |

Mailbox-Filter (Apple Mail):
- in:sent / in:gesendet -> mailbox: sent
- in:drafts / in:entwuerfe -> mailbox: drafts
- in:trash / in:papierkorb -> mailbox: trash
- in:junk -> mailbox: junk

## Ablauf

1. Prefix und Backend parsen
2. Beide Backends parallel abfragen (oder nur eins wenn @apple/@gmail angegeben)
   - Apple Mail: mcp__apple-mail__search_mail (limit: 10)
   - Gmail: mcp__claude_ai_Gmail__search_threads (pageSize: 10)
3. Ergebnisse zusammenfuehren als eine Tabelle, sortiert nach Datum:

| # | Quelle | Von | Betreff | Datum |
|---|--------|-----|---------|-------|
| 1 | Apple | sender@example.com | Subject | 2026-04-15 |
| 2 | Gmail | other@example.com | Subject | 2026-04-14 |

> Sag die Nummer um eine Mail zu lesen, z.B. "lies 1"

4. Mail lesen: Je nach Quelle das richtige Tool aufrufen
   - Apple: mcp__apple-mail__read_mail mit message_id
   - Gmail: mcp__claude_ai_Gmail__get_thread mit threadId

## Zusammenfassung

Wenn der User "zusammenfassung", "summary", "tldr" oder "fasse zusammen" im Befehl nutzt:

1. Suche ausfuehren (beide Backends)
2. Top 5 Mails lesen (automatisch, nicht einzeln nachfragen)
3. Kompakte Zusammenfassung liefern:
   - Wichtigste Punkte pro Mail (1-2 Saetze)
   - Action Items falls vorhanden
   - Wer wartet auf Antwort

Format:

## Mail-Zusammenfassung: "<suchbegriff>"

**Von sender@example.com** (15. Apr) -- Betreff
Kernaussage in 1-2 Saetzen. Action: Was zu tun ist.

**Von other@example.com** (14. Apr) -- Betreff
Kernaussage. Wartet auf Antwort.

## Beispiele

- /ams quarterly report -> Sucht in Apple Mail + Gmail
- /ams von:tim@apple.com @apple -> Nur Apple Mail
- /ams invoice @gmail -> Nur Gmail
- /ams ungelesen -> Alle ungelesenen (Gmail), alle Inbox (Apple Mail)
- /ams zusammenfassung von:chef -> Liest und fasst Mails vom Chef zusammen
- /ams summary after:2026/04/01 @gmail -> Gmail-Zusammenfassung seit April

## Sprache

Match die Sprache des Users.

## Was zu vermeiden ist

- Keine langen Erklaerungen, direkt zur Tabelle
- Keine Nachfragen wenn der Suchbegriff klar ist
- Nicht alle Mails vorlesen ausser bei Zusammenfassung
- Keine doppelten Ergebnisse wenn gleiche Mail in beiden Backends
