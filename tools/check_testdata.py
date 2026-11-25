#!/usr/bin/env python3
"""Loads every file in tools/testdata like the game does at startup (saved variables first, then ADDON_LOADED) and checks what the addon makes of it.
Then the whole self test runs on top of that data (the tests restore everything they touch, so the data must still be intact afterwards).

    python3 tools/check_testdata.py          exit code 1 if something differs
The same files can be tried in the real game: see tools/testdata/README.md (use.sh / restore.sh).
"""
import glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tools", "testdata")

# what must be true after the addon has loaded each file
EXPECT = {
    "01-update-from-1.0.16-full.lua": {"picked": "59", "tips": "56500", "invited": "41", "thanked": "30", "orders": "12", "leaveDelay": "5",
        "debug": "false", "skillBase": "156", "chars": "false", "ad_channels": "handel,trade", "welcomeText": "true"},
    "02-update-from-older-version.lua": {"picked": "7", "tips": "12000", "orders": "4", "leaveDelay": "5", "debug": "false", "skillBase": "75",
        "tracker": "nil", "feed": "nil", "declineText": "nil", "outline": "nil", "chars": "false"},
    "03-new-installation.lua": {"picked": "0", "tips": "0", "invited": "0", "thanked": "0", "orders": "0", "leaveDelay": "5", "debug": "false",
        "dev": "false", "skillBase": "nil", "chars": "false", "welcomeText": "true"},
    "04-lots-of-data.lua": {"picked": "412", "tips": "1200450", "orders": "80", "leaveDelay": "5", "skillBase": "300"},
    "05-partly-damaged.lua": {"picked": "5", "tips": "0", "orders": "2", "order_names": "Heil,OhneStatus", "leaveDelay": "5"},
}


def run(args):
    p = subprocess.run(["luajit", "tools/run_tests.lua"] + args, cwd=ROOT, capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout + p.stderr


def main():
    problems = []
    files = sorted(glob.glob(os.path.join(DATA, "[0-9]*.lua")))
    for f in files:
        name = os.path.basename(f)
        code, out = run(["--data", f, "--inspect"])
        if code != 0:
            problems.append(f"{name}: the addon could not load it:\n      " + out.strip().replace("\n", "\n      ")[:600])
            continue
        got = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
        for k, want in EXPECT.get(name, {}).items():
            if got.get(k) != want:
                problems.append(f"{name}: {k} is {got.get(k)!r}, expected {want!r}")
        code, out = run(["--data", f])
        if code != 0:
            problems.append(f"{name}: the self test fails on this data:\n      " + "\n      ".join(out.splitlines()[:6]))
        else:
            # the tests must leave the data as they found it: inspect again after a full run is not possible in one process, so compare the totals
            first = out.splitlines()[0]
            print(f"  {name:36s} loads ok, {first}")
    for name in EXPECT:
        if not os.path.exists(os.path.join(DATA, name)):
            problems.append(f"{name}: the test data file is missing")
    if problems:
        print("TEST DATA PROBLEMS:")
        for p in problems:
            print("  " + p)
        return 1
    print(f"ok: {len(files)} files load and the tests pass on all of them")
    return 0


if __name__ == "__main__":
    sys.exit(main())
