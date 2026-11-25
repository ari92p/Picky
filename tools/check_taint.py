#!/usr/bin/env python3
"""Static taint check: the addon (and above all its tests) must not write to game globals.

An addon that assigns to a game global or a Blizzard table (even to put the original value back) taints it. When Blizzard's own code reads it
afterwards, it runs "tainted by 'Picky'" and fails with errors like "attempt to compare ... a secret number value" (nameplates, unit frames).

Allowed writes: PickyDB (saved variables), SLASH_PICKY1, SlashCmdList["PICKY"], _G.Picky, _G.BINDING_*_PICKY*, and adding frame names to UISpecialFrames.
Tests may write nothing at all (they replace the fields of LP.Game instead).
Usage: python3 tools/check_taint.py       exit code 1 on a violation
"""
import glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED_GSET = {"PickyDB", "SLASH_PICKY1"}
ALLOWED_G = re.compile(r'^_G\.(Picky|BINDING_(HEADER|NAME)_PICKY\w*)$')
BLIZZARD_TABLE_WRITE = re.compile(r'\b(SlashCmdList|StaticPopupDialogs|UISpecialFrames|C_[A-Za-z]+|[A-Z][A-Za-z]*Frame|[A-Z_]{4,})\s*(\[[^\]]+\]|\.\w+)\s*=[^=]')
ALLOWED_TABLE_WRITE = re.compile(r'SlashCmdList\["PICKY"\]')


def strip(src):
    src = re.sub(r'--\[=*\[.*?\]=*\]', '', src, flags=re.S)
    src = re.sub(r'--[^\n]*', '', src)
    return src


def main():
    problems = []
    for path in sorted(glob.glob(os.path.join(ROOT, "*.lua"))):
        name = os.path.basename(path)
        is_test = name.startswith("Tests")
        out = subprocess.run(["luajit", "-bl", path], capture_output=True, text=True).stdout
        for g in sorted(set(re.findall(r'GSET.*?;\s*"([^"]+)"', out))):
            if is_test or g not in ALLOWED_GSET:
                problems.append(f"{name}: assigns the global {g}")
        src = strip(open(path, encoding="utf-8").read())
        for lineno, line in enumerate(src.split("\n"), 1):
            for m in re.finditer(r'\b_G(\.\w+|\[[^\]]+\])\s*=[^=]', line):
                target = "_G" + m.group(1)
                if is_test or not ALLOWED_G.match(target):
                    problems.append(f"{name}:{lineno}: writes {target}")
            m = BLIZZARD_TABLE_WRITE.search(line)
            if m and not ALLOWED_TABLE_WRITE.search(line) and not re.match(r'\s*(local|function)\b', line) and "LP." not in line[:m.start()]:
                if is_test or True:
                    problems.append(f"{name}:{lineno}: writes into a game table: {m.group(0).strip()[:50]}")
    if problems:
        print("TAINT RISK:")
        for p in problems:
            print("  " + p)
        return 1
    print("ok: no game global is written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
