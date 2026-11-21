# Picky

Rogue lockpicking helper for WoW Forever. / Schurken-Addon fürs Schlösserknacken für WoW Forever.

Languages / Sprachen: English, Deutsch (automatic, by game client language / automatisch nach Spielsprache).

## Install / Installation
Copy the `Picky` folder to / Ordner `Picky` kopieren nach:
`World of Warcraft\_forever_\Interface\AddOns\`

## Use / Benutzung
- **Right-click** a locked box in your bags or in the trade window to pick it. / **Rechtsklick** auf eine Schließkiste im Inventar oder im Handelsfenster knackt sie.
- Locked boxes in your bags sparkle: green = your skill is enough, red = too low. / Schließkisten in den Taschen funkeln: grün = Skill reicht, rot = zu niedrig.
- Turn **Duty** on in the window (`/picky`). It finds players asking for a rogue in chat, invites them, thanks for tips and leaves the group afterwards. / Den **Dienst** im Fenster einschalten: er findet Anfragen im Chat, lädt ein, bedankt sich für Trinkgeld und verlässt danach die Gruppe.
- Channel menu next to **Announce**: tick the channels to announce in (trade in cities, General elsewhere); a click anywhere else closes it. The choice is remembered per channel name, so it applies again when you return to a city. / Kanäle-Menü neben **Ankündigen**: Kanäle anhaken (Handel in Städten, Allgemein sonst); ein Klick woanders schließt es. Die Wahl gilt je Kanalname und ist wieder da, wenn du in eine Stadt zurückkehrst.

- The **Requests** page has two tabs: **Open** and **Done**. Every order is saved permanently (it survives `/reload` and restarts) until you delete it (x per row, or "Delete finished"). Each order shows boxes picked, tip received and how long the customer stayed. / Die **Anfragen**-Seite hat zwei Reiter: **Offen** und **Erledigt**. Jeder Auftrag wird dauerhaft gespeichert (übersteht `/reload` und Neustart), bis du ihn löschst (x je Zeile oder „Erledigte löschen“). Jeder Auftrag zeigt Kisten, Trinkgeld und wie lange der Kunde blieb.
- While a customer is in the group, the Requests page shows a countdown to the automatic leave and a **Leave** button (thanks + leave immediately). / Solange ein Kunde in der Gruppe ist, zeigt die Anfragen-Seite den Countdown bis zum automatischen Verlassen und einen Knopf **Gehen** (bedanken + sofort verlassen).
- At the bottom of the Requests page a countdown shows the next automatic announcement; the x stops it. / Unten auf der Anfragen-Seite zeigt ein Countdown die nächste automatische Ankündigung; das x bricht sie ab.

## Commands / Befehle
`/picky` window · `/picky duty` · `/picky ad` · `/picky lang en|de|auto` · `/picky stats` · `/picky skill [number]` · `/picky ignore <name>` · `/picky reset`
(`/lp` and `/schloss` work too / funktionieren ebenfalls)

## Test mode / Testmodus
- The **Test** tab has one big switch. On: everything is only simulated (no real invites, whispers or announcements), a log is kept, and the tools below the switch work: simulate requests (chat / whisper), customer joins, tip, pick, leave, and a **right-click test area** (a simulated box plus your real locked boxes). Off: Picky works normally. / Der **Test**-Tab hat einen großen Schalter. An: alles wird nur simuliert (keine echten Einladungen, Flüstern oder Ankündigungen), ein Protokoll läuft, und die Werkzeuge darunter funktionieren: Anfragen simulieren (Chat / Flüstern), Kunde tritt bei, Trinkgeld, Knacken, Kunde geht und ein **Testbereich für den Rechtsklick** (simulierte Kiste plus deine echten Schließkisten). Aus: Picky arbeitet normal.
- `/picky debug` toggles the test mode too. / `/picky debug` schaltet den Testmodus ebenfalls um.

## For developers / Für Entwickler
- `/picky dev` shows a hidden **Developer** tab: self tests, hover inspector, skill diagnostics, state dump, client info. / `/picky dev` zeigt einen versteckten **Developer**-Tab: Selbsttests, Maus-Prüfung, Skill-Diagnose, Zustandsabzug, Client-Infos.
- `/picky test` runs the self tests (chat detection, skill/gear parsing, decisions, translations, full simulated flow; they restore your state afterwards). `/picky hover` explains what is under the mouse in 3 seconds. `/picky log` prints the last log lines. / `/picky test` startet die Selbsttests, `/picky hover` erklärt in 3 Sekunden, was unter der Maus liegt, `/picky log` zeigt die letzten Protokollzeilen.

## Notes / Hinweise
- The skill is read from the game; if that fails, set it with `/picky skill <number>`. / Der Skill wird aus dem Spiel gelesen; klappt das nicht, mit `/picky skill <Zahl>` setzen.
- Chat detection understands English and German requests. / Die Chat-Erkennung versteht englische und deutsche Anfragen.
- Box list, skill values and the guide are in `Data.lua`, all texts in `Locale.lua`. / Kistenliste, Skill-Werte und Guide stehen in `Data.lua`, alle Texte in `Locale.lua`.
- Saved default messages follow the client language unless you changed them. / Gespeicherte Standardnachrichten folgen der Spielsprache, solange du sie nicht geändert hast.

## License / Lizenz
MIT, see `LICENSE`.
