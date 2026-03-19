---
name: elon-algo
description: Elon Musks 5-Schritt-Algorithmus auf jede Aufgabe anwenden - Requirements hinterfragen, loeschen, vereinfachen, beschleunigen, automatisieren. Nutze diesen Skill wenn der User nach First Principles, Vereinfachung, Optimierung oder dem Elon-Ansatz fragt.
---

# The Algorithm - Elon Musks 5-Schritt-Ingenieur-Algorithmus

Wende die folgenden 5 Schritte STRIKT IN DIESER REIHENFOLGE an. Ueberspringe keinen Schritt. Gehe nie zurueck zu einem frueheren Schritt bevor der aktuelle abgeschlossen ist.

## Schritt 1: Make Requirements Less Dumb

**Jede Anforderung ist potenziell dumm - auch wenn sie von smarten Leuten kommt.**

- Hinterfrage JEDE Anforderung. Frage: "Wer hat das verlangt? Warum?"
- Jede Anforderung braucht einen konkreten Namen (Person), keine anonyme Quelle
- Wenn du eine Anforderung nicht mindestens einmal zurueckgewiesen hast, nimmst du sie nicht ernst genug
- Die gefaehrlichsten Anforderungen kommen von smarten Leuten - weil niemand sie hinterfragt
- Frage dich: "Was passiert wenn wir das NICHT machen?" - oft ist die Antwort: nichts

**Output:** Liste welche Anforderungen bleiben, welche gestrichen werden, und warum.

## Schritt 2: Delete the Part or Process

**Loeschen ist wichtiger als optimieren.**

- Loesche jeden Teil, jeden Schritt, jede Komponente die nicht ABSOLUT notwendig ist
- Wenn du am Ende nicht mindestens 10% von dem was du geloescht hast wieder zurueckfuegen musst, hast du nicht genug geloescht
- Loesche zuerst, frage spaeter - es ist einfacher etwas zurueckzufuegen als es nie zu loeschen
- Jede Zeile Code die nicht existiert hat keine Bugs, braucht kein Review, keine Tests, keine Doku
- "Fuer den Fall dass wir es brauchen" ist KEIN Grund etwas zu behalten

**Output:** Was wurde geloescht und was bleibt uebrig. Begruende nur was BLEIBT, nicht was weg ist.

## Schritt 3: Simplify and Optimize

**Erst NACHDEM geloescht wurde. Optimiere NIE etwas das nicht existieren sollte.**

- Reduziere Komplexitaet auf das Minimum
- Weniger Abstraktionsebenen, weniger Indirektionen, weniger Konfiguration
- Wenn eine Loesung erklaert werden muss ist sie zu komplex
- Bevorzuge langweilige, bewaehrte Loesungen gegenueber cleveren
- 3 Zeilen kopierter Code sind besser als eine vorzeitige Abstraktion

**Output:** Vereinfachte Loesung mit Begruendung was sich gegenueber dem Ausgangszustand geaendert hat.

## Schritt 4: Accelerate Cycle Time

**Erst NACHDEM vereinfacht wurde. Beschleunige NIE etwas das geloescht werden sollte.**

- Mach jeden Zyklus schneller: Build, Test, Deploy, Feedback
- Parallelisiere was parallel laufen kann
- Eliminiere Wartezeiten und Handoffs
- Kuerzere Feedback-Loops = schnelleres Lernen
- Frage: "Kann das in Minuten statt Stunden passieren? Sekunden statt Minuten?"

**Output:** Wo wurden Zyklen beschleunigt und um welchen Faktor.

## Schritt 5: Automate

**Erst NACHDEM beschleunigt wurde. Automatisiere NIE einen kaputten Prozess.**

- Automatisiere erst wenn Schritte 1-4 abgeschlossen sind
- Einen schlechten Prozess zu automatisieren macht ihn nur schneller schlecht
- Automatisierung ist der LETZTE Schritt, nie der erste
- Teste die Automatisierung gegen den manuellen Prozess

**Output:** Was wird automatisiert, was bleibt bewusst manuell.

---

## Denkweise

- **First Principles:** Reduziere jedes Problem auf physikalische/logische Grundwahrheiten. Ignoriere Konventionen.
- **Physik, nicht Analogie:** "So macht man das ueblicherweise" ist kein Argument. "Das sind die physikalischen Grenzen" schon.
- **Pessimismus loeschen:** "Das geht nicht" hinterfragen. "Das ging noch nie" ist irrelevant. Was ist MOEGLICH?
- **Speed:** Geschwindigkeit ist eine Eigenschaft. Lieber schnell und 80% richtig als langsam und 100%.
- **Idiot Index:** Verhaeltnis von Kosten zu Materialwert. Je hoeher, desto mehr Verschwendung im Prozess.
