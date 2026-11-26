<!--
CurseForge project page text for Picky. Paste the part below the line into the project description.

Summary (short field, paste separately):
Lockpicking for other players, made fast. Right-click boxes, find customers in chat, invite, thank and leave the group - all from one small window. For WoW Forever.

Images in the description: all linked from the project gallery (media.forgecdn.net), nothing to upload.
The three settings images sit side by side via an HTML <p><img width="32%"> block. If the editor shows that as raw text,
use the markdown version (one image per line) or a collage image instead.
Gallery (carousel): the eight single images, cover = requests.webp. Captions:
  requests "Requests: every order with skill needed, time and tip"; guide "Leveling guide with spots, maps and boxes per skill range";
  toast-new-request "Pop-up for a new request: click to invite"; toast-trade-complete "Pop-up after a trade: click to thank and leave the group";
  settings-duty "Settings: duty, channels and group behaviour"; settings-display "Settings: pop-ups, sounds and window size";
  settings-messages "Settings: editable greeting, thanks and reply texts"; test-mode "Test mode: simulate requests safely, with a copyable log"
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

![Picky pop-up for a new request](https://media.forgecdn.net/attachments/2279/743/toast-new-request-png.png)

_Pop-up for a new request: click to invite_

![Picky pop-up after a completed trade](https://media.forgecdn.net/attachments/2279/744/toast-trade-complete-png.png)

_Pop-up after a trade: click to thank and leave the group_

Getting started
---------------

1. Type `/picky` to open the window.
2. Turn on **Duty**. That's it.
3. To announce yourself, **Shift-click the minimap button** or press **Announce** in the window. The game only allows channel posts from a click, so there is no automatic timed announcement.

Chat commands
-------------

| Command | What it does |
|---|---|
| `/picky` | Opens or closes the window |
| `/picky duty` | Turns Duty mode on or off |
| `/picky stats` | Prints your totals (orders, boxes, tips) |

Leveling guide
--------------

Picky shows you where to level lockpicking for your current skill: the best spots, map buttons and the boxes you can open there.

![Lockpicking leveling guide with map buttons](https://media.forgecdn.net/attachments/2279/702/guide-webp.webp)

_Leveling guide: spots, map buttons and the boxes for each skill range_

Settings
--------

Everything can be changed: what Duty does, which channels to listen and advertise in, sounds, pop-ups, window size and all message texts.

<p>
<img src="https://media.forgecdn.net/attachments/2279/705/settings-duty-webp.webp" alt="Picky settings for duty, channels and group" width="32%">
<img src="https://media.forgecdn.net/attachments/2279/704/settings-display-webp.webp" alt="Picky settings for pop-ups, sounds and window size" width="32%">
<img src="https://media.forgecdn.net/attachments/2279/706/settings-messages-webp.webp" alt="Picky settings for greeting, thanks and reply texts" width="32%">
</p>

_Settings: duty, channels and group (left), pop-ups, sounds and window size (middle), editable message texts (right)_

Test mode
---------

Try everything without sending a single real whisper or invite: simulate requests, joins, tips and picks, and copy the log if something looks wrong.

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
