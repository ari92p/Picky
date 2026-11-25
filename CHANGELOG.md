# Changelog

## Unreleased
- The guide page is rebuilt. Every skill stage lists several places with zone, coordinates and a "Map" button that opens the world map and sets a pin (TomTom if you have it, otherwise the game's own pin). Horde and Alliance have their own places, a button switches between Alliance, Horde and both. Box icons show the game's own icons with a tooltip, locked ones are greyed out. New tabs "Boxes" (all boxes by required skill) and "Tips". Tips are now colored call-outs: red warnings, green tips, blue notes. A warning appears when your level holds your skill back.
- The skill bar always shows its scale (the number in the bar, e.g. "165 +12 / 300"). Green = bonus from gear and buffs, white mark = limit of your rank, orange mark = limit of your level. Mouse over the bar for all numbers.
- Map coordinates are taken from other guides and still need checking in the game.

## 1.0.22
- A request that a player splits into several short messages is now recognised, in any order: "LF rogue", "for", then the item link; or the link first and "LF rogue" after it; or "LF", "chest", "open it". Picky remembers the last few messages of each player for 5 seconds and checks them together, with the same rules as a single message (advertisements and sales words still block it, and a general question plus a box link is no request).
- Fixed: running the self tests (Developer tab) no longer replaces game functions. Doing so tainted them and made Blizzard's own code (nameplates, unit frames) fail with errors like "execution tainted by 'Picky'" until the next /reload. Normal use of Picky was not affected.
- More self tests for these cases, and tests for the tests (deliberately built-in mistakes that the tests must catch, a check that no test touches a game function, and a check that the tests leave no data behind).

## 1.0.21
- A customer who uses an offer word is no longer taken for an advertisement: "Kann mir jemand umsonst meine Kisten öffnen?", "can someone open my lockbox for free pls" and "any rogue available to open a lockbox?" are requests again. Words like "free", "gratis", "kostenlos", "umsonst", "available" and "service" only mark an advertisement when nobody is being asked.
- More self tests for these messages.

## 1.0.20
- Advertisements of other rogues that say they are looking for work ("Rogue LFW Locking!", "looking for work", "for hire") are no longer taken as requests, so Picky does not invite them. "umsonst" (German for "for free") counts as an offer word too, like "free", "gratis" and "kostenlos".
- More self tests for these messages.

## 1.0.19
- Guild chat can be read: "Guild" is in the "Listen in" menu (on by default, like every other source).
- "Advertise in" can include the guild: the Announce button then also posts into guild chat. It is never part of the default.
- The two menus only list what your character really has: the channels it joined, and the guild only when it is in a guild.
- More self tests (guild chat, the menus, announcing in the guild).

## 1.0.18
- Statistics, orders and the stored skill are shared by the whole account again, as before 1.0.16. The per-character storage of the withdrawn 1.0.17 was taken back. If your saved data still has per-character entries, they are merged into the account data once.
- A rogue who has not learned Pick Lock yet now shows "Lockpicking: not learned yet" with skill 0 instead of a guess from the level. The stored skill is no longer used for a character without Pick Lock, so an alt does not inherit the skill of your main. It switches to the real value as soon as you learn the spell.
- A request that is split into two messages ("LF rogue for", then only the item link a few seconds later) is now taken as one request. The second message has to come from the same player within 5 seconds.
- The wait before leaving the group after the last trade is now 5 seconds by default (was 10). If you still had the old default of 10, it moves to 5.
- Characters that are not rogues see a small saying in the empty requests list.
- Developer tab: Copy all (both logs in one list), logs keep up to 3000 lines, and "Announce (test only)" no longer posts to any channel. The self test can be run twice in a row.
- The slash command is now only `/picky` (`/lp` and `/schloss` were removed).
- About 120 new self tests (box values, chat detection, channels, skill and the merge of older data).

## 1.0.17 (withdrawn)
- Everything is now stored per character: statistics, orders and the stored lockpicking skill. Settings, the ignore list and the channel choices stay shared. The first rogue that logs in after this update takes over the existing statistics, orders and skill; other characters start empty. Characters that are not rogues get no stored profile at all.
- A rogue who has not learned Pick Lock yet now shows "Lockpicking: not learned yet" with skill 0 instead of a guess from the level. It switches to the real value as soon as you learn the spell.
- A request that is split into two messages ("LF rogue for", then only the item link a few seconds later) is now taken as one request. The second message has to come from the same player within 5 seconds.
- The wait before leaving the group after the last trade is now 5 seconds by default (was 10). If you still had the old default of 10, it moves to 5.
- Characters that are not rogues see a small saying in the empty requests list.
- Developer tab: Copy all (both logs in one list), logs keep up to 3000 lines, and "Announce (test only)" no longer posts to any channel. The self test can be run twice in a row.
- About 120 new self tests (box values, chat detection, channels, per-character data and the upgrade from older versions).

## 1.0.16
- New "Channels" section in the settings: "Listen in" chooses which chats Picky reads for requests (say, yell and your channels; whispers are always read), "Advertise in" chooses where the Announce button posts. Both lists update when you join or leave a channel. The channel button moved out of the main window.
- By default Picky advertises in the normal trade channel, not in the local one (TradeLocal / Handel Lokal).
- Advertisements of other rogues ("Rogue 300 lockpicking, PM me", "offering ... tips welcome", "free lockbox opening", "Schurke öffnet Kisten für Trinkgeld") are no longer taken as requests, so Picky does not invite other rogues. Such messages are noted in the log.
- New installs start with "Invite players automatically" and "Also invite when no box is mentioned" switched off.
- Developer tab: Copy and Clear output sit above the output field.
## 1.0.15
- The Battered Chest (only from pickpocketing) has no lockpicking requirement, so it is never refused for a too low skill.

## 1.0.14
- Box skill values checked against the item tooltips in WoW Forever and corrected: Ornate Bronze Lockbox 1 (was 25), Heavy Bronze Lockbox 25 (was 50), Eternium Lockbox 225 (was 300) and Reinforced Locked Chest 250 (was 225). The word guesses "bronze" and "eternium" in chat follow these values.

## 1.0.13
- Fixed: the Thorium Lockbox needs lockpicking 225 (not 250), so requests for it are no longer refused at skill 225 to 249.
- Fixed: the word "iron" in chat is only taken as a box hint when it stands alone, so "ironforge" no longer gives a skill estimate of 125.

## 1.0.12
- Fixed: at a vendor you could not sell a locked box, because Picky's right-click area covered it. While a vendor, bank, mail, auction house or guild bank window is open, the click area is no longer placed on boxes, so the normal right-click works there.
- An empty amount (for example the tips at the start) now shows "0g" instead of "0k".

## 1.0.11
- Fixed a false positive in public chat: a message like "suche ... sitze auf den Kisten" was taken for a request. Without the word "rogue/Schurke", a public message now also needs an open/pick word (open, unlock, lockpick, öffnen, aufmachen, knacken ...). Whispers are unchanged.
- Added self tests for this case.

## 1.0.10
- Fixed: on clients that only have the newer skill API, a fresh install did not find your lockpicking skill and fell back to the level estimate. Picky now reads the skill list through `C_SkillInfo` as well, including the bonus.
- Fixed: the lockpicking bonus from equipment (for example gloves with +4) is now also read through a hidden tooltip when the normal tooltip data is empty.
- The skill diagnostics (Developer tab) now show the raw skill line and the gear bonus lines.

## 1.0.9
- Slash commands trimmed to what players need: `/lp` (window), `/lp duty` and `/lp stats`. The other commands were removed; the self tests, hover check, skill diagnostics and test mode are available in the Developer and Test tabs.
- Developer tab: language switch (Auto / English / Deutsch).
- Updated the CurseForge description.

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
