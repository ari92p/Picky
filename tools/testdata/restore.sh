#!/bin/bash
# Put your real Picky.lua back (the copy Picky.lua.real made by use.sh).   Usage:  ./testdata/restore.sh
SV="/Applications/World of Warcraft/_forever_/WTF/Account/119654420#4/SavedVariables"
if pgrep -f "World of Warcraft.app/Contents/MacOS" >/dev/null; then echo "WoW is still running. Please quit it completely and try again."; exit 1; fi
if [ ! -f "$SV/Picky.lua.real" ]; then echo "There is no Picky.lua.real. Nothing restored."; exit 1; fi
cp -p "$SV/Picky.lua" "$SV/Picky.lua.after-test-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
cp -p "$SV/Picky.lua.real" "$SV/Picky.lua" && rm "$SV/Picky.lua.real" && echo "Your real Picky.lua is back."
