# Test data for updates

**These files are also checked automatically** by `python3 tools/check_testdata.py` (part of `tools/check_all.sh`): the addon loads each of them like the game does,
the result is compared with the table below, and the whole self test runs on top of that data. Trying them in the real game is the extra step that also shows the real windows.

Steps for the real game: quit WoW completely, run `./tools/testdata/use.sh 01`, start WoW, log in with a rogue, look at the result, quit WoW,
take the next file or run `./tools/testdata/restore.sh` for your real data. Always test with a rogue (other classes only show a saying).

| File | State | What must be right after logging in |
|---|---|---|
| 01 | as of 1.0.16, full | Header "Picked 59 · Tips 5g 65s". "Done (12)" shows 12 orders from 21.11. Settings: wait before leaving **5** (was 10). "Advertise in": only Trade ticked. Skill display "Lockpicking 156" (only if the character has the skill). No test mode. |
| 02 | old state (1.0.0 to 1.0.5) | Wait before leaving **5** (was 2). No test mode (was on, dryRun was off). Statistics 7 boxes, 4 orders. No Lua errors because of the old leftovers. |
| 03 | new installation | Statistics 0, no orders, wait before leaving 5, "No requests yet". All settings on default. |
| 04 | lots of material | "Picked 412 · Tips 120g 4s 50k", "Done" with many orders and several pages, paging works, no stutter when opening. |
| 05 | partly damaged | No Lua errors. Statistics "Picked 5". Orders: "Heil" and "OhneStatus" (the invalid entries are gone). |

For every test: no red Lua error message, Picky opens with `/picky`, a simulated run in the Test tab goes through.
All characters share the data of the account.
