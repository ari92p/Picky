# Picky

Rogue lockpicking helper for WoW Forever.

Languages: English, German (automatic, by game client language).

## Install
Copy the `Picky` folder to:
`World of Warcraft\_forever_\Interface\AddOns\`

## Use
- **Right-click** a locked box in your bags or in the trade window to pick it.
- Locked boxes in your bags sparkle: green = your skill is enough, red = too low.
- **Shift-click** the minimap button to post your announcement. The game only allows channel posts from a click, so there is no automatic timed announcement.
- Turn **Duty** on in the window (`/picky`). It finds players asking for a rogue in chat, invites them, thanks for tips and leaves the group afterwards.
- Channel menu next to **Announce**: tick the channels to announce in (trade in cities, General elsewhere); a click anywhere else closes it. The choice is remembered per channel name, so it applies again when you return to a city.

- The **Requests** page has two tabs: **Open** and **Done**. Every order is saved permanently (it survives `/reload` and restarts) until you delete it (x per row, or "Delete finished"). Each order shows boxes picked, tip received and how long the customer stayed.
- While a customer is in the group, the Requests page shows a countdown to the automatic leave and a **Leave** button (thanks + leave immediately).

## Commands
`/picky` window · `/picky duty` · `/picky ad` · `/picky stats` · `/picky skill [number]` · `/picky ignore <name>` · `/picky reset`
(`/lp` and `/schloss` work too)

## Test mode
- The **Test** tab has one big switch. On: everything is only simulated (no real invites, whispers or announcements), a log is kept, and the tools below the switch work: simulate requests (chat / whisper), customer joins, tip, pick, leave, and a **right-click test area** (a simulated box plus your real locked boxes). Off: Picky works normally.
- `/picky debug` toggles the test mode too.

## For developers
- `/picky dev` shows a hidden **Developer** tab: self tests, hover inspector, skill diagnostics, state dump, client info.
- `/picky test` runs the self tests (chat detection, skill/gear parsing, decisions, translations, full simulated flow; they restore your state afterwards). `/picky hover` explains what is under the mouse in 3 seconds. `/picky log` prints the last log lines.

## Notes
- The skill is read from the game; if that fails, set it with `/picky skill <number>`.
- Chat detection understands English and German requests.
- Box list, skill values and the guide are in `Data.lua`, all texts in `Locale.lua`.
- Saved default messages follow the client language unless you changed them.

## Support

If this app is useful to you, you can buy me a coffee:

<p>
  <a href="https://ko-fi.com/ari92p"><img alt="Support me on Ko-fi" src="https://ko-fi.com/img/githubbutton_sm.svg" height="36"></a>
  <a href="https://buymeacoffee.com/ari92p"><img alt="Buy Me a Coffee" src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="36"></a>
</p>

## License
MIT, see `LICENSE`.
