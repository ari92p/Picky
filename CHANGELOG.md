# Changelog

## 1.0.8
- New: whispers that need a higher skill than yours get an automatic reply (never in public chat, once per request). The text is editable in the settings and uses `{need}` and `{skill}`; it can be switched off.
- New: if someone you invited never joins the group but trades with you anyway, the order counts as accepted (boxes and tip are counted, no "did not join" timeout).
- The request sound can be chosen in the settings (Whisper, Auction, Auction 2, Raid). The default is Auction and plays on the Master channel so it does not get drowned out.
- The Test tab log has a Copy button. Internal log lines (skill scans, hover checks, roster polling) now go to a separate developer log that is only shown in the Developer tab, which also got a Copy button, an announcement click/timer test and sound buttons.
- Removed the sparkle on locked boxes in the bags and its background timer.
- The leave timings moved into the Group section of the settings.
- The login message shows the real version (it was stuck on 1.0.0).
- The German announcement default now reads "Hi, biete ...".
- Added end-to-end tests with real trade events.

## 1.0.7
- Announcements are now click-only: Shift-click the minimap button (or use the Announce button or `/picky ad`). The game blocks addons from posting to a channel on a timer, so the automatic repeat, its countdown and its settings were removed.
- The log no longer repeats the same skill and gear lines; they appear only when something changes.
- Removed the `/picky adtest` diagnostic command.

## 1.0.6
- Removed the "Announcement due" popup from 1.0.5. A blocked announcement now only shows a red chat line (once per session for the automatic one) and a history entry.
- New `/picky adtest`: posts the announcement from a timer and reports whether the game allows that.

## 1.0.5
- Fixed the automatic announcement: the game blocks addons from posting to a channel on a timer, so it was silently never sent while Picky reported it as posted. Picky now detects the block and shows an "Announcement due" popup; one click posts it. A blocked manual announcement shows a red message in chat.

## 1.0.4
- No more sound, flash or popup for requests that need a higher skill than yours (nothing you can do about them); they still appear in the list.
- Added a chat detection test for German box names like "Thoriumschließkassette".

## 1.0.3
- Popups are now smart: only one at a time (the newest replaces the older), each stays only while it is still relevant and can always be closed with the X.
- New "Trade complete" popup after every trade with a customer (with or without tip): click to thank and leave the group. Picky now also leaves the group automatically after every completed trade.
- "Box too high" popup stays while the box is in the trade; click to tell the customer your skill is too low.
- New request popup stays until you invite, the customer invites you or joins, or the request expires. The "In the group" popup was removed.
- Test mode is now shown in the window title on every tab.
- The Invite button is also shown for requests that are already "invited" or timed out.
- Chat detection reads explicit skill numbers like "lockpick 175" or "skill 225+".
- Fixed a stale 60 s timer after inviting a customer again.

## 1.0.2
- Fixed the game version: Picky is for WoW Forever only and is no longer listed as Classic.
- All code comments, the README and the CurseForge page are now English.

## 1.0.1
- Fixed the German leveling guide: Angor Fortress is in Ödland (Badlands).
- Test tab: more room for the "As chat" / "As whisper" buttons.

## 1.0.0
- Right-click lockpicking on locked boxes in bags and the trade window.
- Duty mode: detects lockpicking requests in chat (English and German), auto-invites, greets, thanks once for tips, leaves the group automatically.
- Accepts invites from customers who invite you directly.
- Trade-chat announcements with channel selection, `{skill}`, `{pick}` and `{city}` placeholders.
- Order history (Open / Done) with boxes picked, tips and time spent; saved permanently.
- Warning when a customer's box needs a higher skill than yours.
- Leveling guide for WoW Forever, bilingual English / German window.
- Test mode, developer tab and built-in self tests.
