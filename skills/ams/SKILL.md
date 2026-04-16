---
name: ams
description: All Mail Search - Unified mail search across Apple Mail and Gmail from Claude Code. Trigger on "/ams", "mail suchen", "check my mail", "search mail", "mail von", "mail about", "gmail", "inbox check", "ungelesene mails", "mail zusammenfassung", "followup mails", "anhaenge finden", "attachments". Searches both Apple Mail (local) and Gmail (cloud) with one command. Supports summaries, attachment search, and follow-up detection.
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

1. Prefix, Modus und Backend parsen
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

## Modus: Zusammenfassung

Trigger: "zusammenfassung", "summary", "tldr", "fasse zusammen" im Befehl.

1. Suche ausfuehren (beide Backends)
2. Top 5 Mails automatisch lesen (nicht einzeln nachfragen)
3. Kompakte Zusammenfassung liefern

Format:

### Mail-Zusammenfassung: "<suchbegriff>"

**Von sender@example.com** (15. Apr) -- Betreff
Kernaussage in 1-2 Saetzen. Action: Was zu tun ist.

**Von other@example.com** (14. Apr) -- Betreff
Kernaussage. Wartet auf Antwort.

---
**Action Items:**
- [ ] Aufgabe 1 (von wem, bis wann)
- [ ] Aufgabe 2

## Modus: Anhaenge

Trigger: "anhang", "attachment", "anhaenge", "attachments" im Befehl.

Sucht Mails die Anhaenge enthalten zu einem bestimmten Thema.

1. Gmail: Query mit "has:attachment" kombiniert mit dem Suchbegriff
2. Apple Mail: Normale Suche ausfuehren, dann jede Mail einzeln lesen und pruefen ob Anhaenge erwaehnt werden (Apple Mail MCP liefert Anhang-Info im Mail-Body wenn vorhanden)
3. Ergebnisse als Tabelle mit Anhang-Spalte:

| # | Quelle | Von | Betreff | Datum | Anhaenge |
|---|--------|-----|---------|-------|----------|
| 1 | Gmail | sender@example.com | Rechnung Q1 | 2026-04-15 | rechnung_q1.pdf |
| 2 | Apple | other@example.com | Vertrag | 2026-04-10 | vertrag_v2.docx |

Wenn keine Anhang-Info verfuegbar ist, zeige "(Anhang vorhanden)" statt Dateinamen.

## Modus: Follow-up

Trigger: "followup", "follow-up", "nachfassen", "offen", "unbeantwortete" im Befehl.

Findet Mails auf die der User noch nicht geantwortet hat.

Strategie:
1. **Gmail**: Suche mit dem Suchbegriff + "is:unread" oder "in:inbox" eingehende Mails
2. **Gmail Gegenprobe**: Fuer jeden Sender/Thread pruefen ob im selben Thread eine Antwort vom User existiert (get_thread und Messages durchgehen - wenn die letzte Nachricht nicht vom User ist, ist es ein offener Follow-up)
3. **Apple Mail**: Suche in inbox, dann suche in sent nach Antworten zum gleichen Betreff. Wenn keine Antwort gefunden -> Follow-up offen

Ergebnis-Format:

### Offene Follow-ups

| # | Von | Betreff | Erhalten | Tage offen |
|---|-----|---------|----------|------------|
| 1 | kunde@firma.de | Angebot Projekt X | 12. Apr | 4 |
| 2 | partner@co.com | Review Feedback | 10. Apr | 6 |

> "lies 1" fuer Details, "antwort 1" fuer Antwort-Entwurf

Wenn der User "antwort <nummer>" sagt:
- Mail lesen
- Kontext zusammenfassen
- Hoeflichen Antwort-Entwurf vorschlagen (nicht senden, nur vorschlagen)

## Beispiele

- /ams quarterly report -> Sucht in Apple Mail + Gmail
- /ams von:tim@apple.com @apple -> Nur Apple Mail
- /ams invoice @gmail -> Nur Gmail
- /ams ungelesen -> Alle ungelesenen Mails
- /ams zusammenfassung von:chef -> Liest und fasst Mails vom Chef zusammen
- /ams summary after:2026/04/01 @gmail -> Gmail-Zusammenfassung seit April
- /ams anhang rechnung -> Findet Mails mit Anhaengen zum Thema Rechnung
- /ams attachment invoice @gmail -> Nur Gmail-Anhaenge
- /ams followup von:kunde -> Offene Mails von Kunden ohne Antwort
- /ams nachfassen -> Alle offenen Follow-ups

## Sprache

Match die Sprache des Users.

## Was zu vermeiden ist

- Keine langen Erklaerungen, direkt zur Tabelle
- Keine Nachfragen wenn der Suchbegriff klar ist
- Nicht alle Mails vorlesen ausser bei Zusammenfassung
- Keine doppelten Ergebnisse wenn gleiche Mail in beiden Backends
- Niemals Mails senden oder loeschen, nur lesen und vorschlagen
