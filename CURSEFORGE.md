<!--
CurseForge project page text for Picky. Paste the part below the line into the project description.

Summary (short field, paste separately):
Lockpicking for other players, made fast. Right-click boxes, find customers in chat, invite, thank and leave the group - all from one small window. For WoW Forever.

Images: the screenshots are in assets/screenshots/. Upload them to the project's Images page (turn the carousel on)
in this order, with these captions. The description below shows them via their gallery URLs (media.forgecdn.net):
  1. requests.webp            "Requests: every order with skill needed, time and tip"   (first = carousel cover)
  2. toast-new-request.png    "Pop-up for a new request: click to invite"
  3. toast-trade-complete.png "Pop-up after a trade: click to thank and leave the group"
  4. guide.webp               "Leveling guide with spots, maps and boxes per skill range"
  5. settings-duty.webp       "Settings: duty, channels and group behaviour"
  6. settings-display.webp    "Settings: pop-ups, sounds and window size"
  7. settings-messages.webp   "Settings: editable greeting, thanks and reply texts"
  8. test-mode.webp           "Test mode: simulate requests safely, with a copyable log"
-->

Picky
=====

**Lockpicking for other players, made fast. Right-click a box, let Duty mode find customers in chat, and keep track of every order. For WoW Forever.**

![Picky requests window with open and finished orders](https://media.forgecdn.net/attachments/2279/703/requests-webp.webp)

_Requests: every order with the skill needed, time and tip_

Features
--------

* **Right-click to pick:** click a locked box in your bags or in the trade window. No macros, no dragging.
* **Duty mode:** finds players asking for a rogue in chat (English and German), invites them, greets them, thanks once for tips and leaves the group afterwards. Customers who invite you directly are accepted too. If someone you invited never joins but trades with you anyway, the order still counts.
* **Smart pop-ups:** a new request, a completed trade (click to thank and leave the group) and a box that is too high for you. Each one stays only while it is relevant, and you can choose the request sound in the settings.
* **Skill too high:** whispers that need a higher skill than yours get an automatic reply. The text is editable and uses the placeholders `{need}` and `{skill}`. Public chat is never answered.
* **Announcements** in trade chat with channel selection and the placeholders `{skill}`, `{pick}` and `{city}`.
* **Order history:** boxes picked, tips and time spent, saved until you delete them.
* **Leveling guide** for lockpicking in WoW Forever.
* **Test mode:** a full simulation with a copyable log, so you can try everything without sending a single real whisper or invite.
* English and German interface (follows your game client).
* **Lightweight:** one small addon, no libraries, no other addons required.

![Picky pop-up for a new request](https://media.forgecdn.net/attachments/2279/708/toast-new-request-png.png)

_Pop-up for a new request: click to invite_

![Picky pop-up after a completed trade](https://media.forgecdn.net/attachments/2279/709/toast-trade-complete-png.png)

_Pop-up after a trade: click to thank and leave the group_

Getting started
---------------

1. Type `/picky` to open the window.
2. Turn on **Duty**. That's it.
3. To announce yourself, **Shift-click the minimap button** or press **Announce** in the window. The game only allows channel posts from a click, so there is no automatic timed announcement.

![Lockpicking leveling guide with map buttons](https://media.forgecdn.net/attachments/2279/702/guide-webp.webp)

_Leveling guide: spots, map buttons and the boxes for each skill range_

Chat commands
-------------

| Command | What it does |
|---|---|
| `/picky` | Opens or closes the window |
| `/picky duty` | Turns Duty mode on or off |
| `/picky stats` | Prints your totals (orders, boxes, tips) |

Settings
--------

Everything can be changed: what Duty does, which channels to listen and advertise in, sounds, pop-ups, window size and all message texts.

![Picky settings for duty, channels and group](https://media.forgecdn.net/attachments/2279/705/settings-duty-webp.webp)

_Duty, channels and group behaviour_

![Picky settings for pop-ups, sounds and window size](https://media.forgecdn.net/attachments/2279/704/settings-display-webp.webp)

_Pop-ups, sounds and window size_

![Picky settings for greeting, thanks and reply texts](https://media.forgecdn.net/attachments/2279/706/settings-messages-webp.webp)

_Editable greeting, thanks and reply texts_
Test mode
---------

Try everything without sending a single real whisper or invite: simulate requests, joins, tips and picks, and copy the log if something looks wrong.

![Picky test mode with simulated request and log](https://media.forgecdn.net/attachments/2279/707/test-mode-webp.webp)

_Test mode: simulated requests with a copyable log_

Good to know
------------

* Picky needs **Pick Lock** in your spellbook. A rogue who has not learned it yet counts as skill 0, Picky never guesses from your level.
* Orders, statistics and your skill are saved **once per account**, not per character.
* Picky never sends channel posts on its own. Announcements always need your click.
* Picky does not move or replace any of Blizzard's frames.
* Not sure it does what you want? Switch on **Test mode** first. Nothing real is sent while it is on.

Questions and feedback
----------------------

Found a bug or have an idea? Leave a comment here or open an issue on GitHub. Please include the addon version and what happened. In the Test tab you can copy the log with one click, which helps a lot.

Source code and bug reports: https://github.com/ari92p/Picky

If Picky saves you time, you can support me on Ko-fi: https://ko-fi.com/ari92p

**AI disclosure:** Claude helped write the code. I designed, test and maintain the addon.
