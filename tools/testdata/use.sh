#!/bin/bash
# Copy a test data file into the game as Picky.lua.   Usage:  ./testdata/use.sh 01
# - WoW must be completely closed (otherwise the game overwrites the file when it quits)
# - Your real file is saved once as Picky.lua.real (and with a time stamp) and is never overwritten
SV="/Applications/World of Warcraft/_forever_/WTF/Account/119654420#4/SavedVariables"
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$1" ]; then echo "Usage: $0 01|02|03|04|05"; ls "$DIR"/[0-9]*.lua | xargs -n1 basename; exit 1; fi
if pgrep -f "World of Warcraft.app/Contents/MacOS" >/dev/null; then echo "WoW is still running. Please quit it completely and try again."; exit 1; fi
SRC=$(ls "$DIR"/"$1"-*.lua 2>/dev/null | head -1)
if [ -z "$SRC" ]; then echo "No test data file $1 found."; exit 1; fi
if [ -f "$SV/Picky.lua" ]; then
  cp -p "$SV/Picky.lua" "$SV/Picky.lua.before-test-$(date +%Y%m%d-%H%M%S)"
  [ -f "$SV/Picky.lua.real" ] || cp -p "$SV/Picky.lua" "$SV/Picky.lua.real"
fi
cp "$SRC" "$SV/Picky.lua"
echo "$(basename "$SRC") is now Picky.lua. Start WoW and log in with a rogue."
echo "Afterwards quit WoW and run ./testdata/restore.sh to get your real data back."
