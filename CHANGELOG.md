# Changelog

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
