#!/usr/bin/env python3
"""Strip the pick feature out of main.lua -> 4.5.0 (marker based)."""
import shutil
import sys
from pathlib import Path

ROOT = Path(r"D:\Projects\pbz-weapon-swap")
SRC = ROOT / "src" / "PBZWeaponSwap" / "Scripts" / "main.lua"
BAK = ROOT / "archive" / "main-4.8.26.lua"

CUTS = [
    ("local modCalling = false", "local runSwitchSelfTest = nil"),
    ("        -- \u81ea\u9009\u6a21\u5f0f\u4e0d\u63a5\u7ba1\u6309\u952e", "        -- \u539f\u751f\u5207\u6362\u65e0\u6cd5\u53d6\u6d88"),
    ("-- \u2500\u2500 \u81ea\u9009\u6a21\u5f0f\uff1a\u65f6\u505c", "-- \u5355\u69fd\uff1a\u69fd\u4f4d\u5199\u5165\u5fc5\u987b\u8d70"),
    ("-- \u628a\u67d0\u4e00\u683c\u5199\u6210\u201c\u7a7a\u201d\u3002", "-- \u628a\u67d0\u4e2a\u69fd\u6e05\u7a7a\uff1a\u6210\u529f\u540e\u539f\u751f\u5207\u6362"),
    ("-- \u627e\u5230\u6e38\u620f\u81ea\u5df1\u7684\u201c\u5207\u6362\u6b66\u5668\u201d\u5165\u53e3", "local cfgDiagDone = false"),
    ("-- 4.8.7\uff1a\u53ea\u8d70\u7eaf\u6570\u636e\u5199\u5165", "-- \u5173\u952e\u6000\u7591\uff1aSetSlotWeapon \u5bf9"),
    ("local function expFullTest", "-- F3 \u8bca\u65ad\uff1a\u627e\u51fa\u771f\u6b63\u80fd"),
    ("-- F3 \u8bca\u65ad\uff1a\u627e\u51fa\u771f\u6b63\u80fd", "-- \u2500\u2500 F9 \u83dc\u5355"),
    ("-- F3 \u63a2\u9488\u5df2\u505c\u7528", "local function labelOf(kind)"),
]

HEADER = """-- PBZWeaponSwap v4.5.0
-- \u7528\u6e38\u620f\u539f\u751f\u7684\u6362\u6b66\u5668\u952e\u9a71\u52a8\u4e24\u5957\u6b66\u5668\uff1a
--   \u4e3b\u6b66\u5668   \u952e\u76d8 1 / \u624b\u67c4\u5341\u5b57\u952e\u5de6   -> SetCurrentWeaponByIndex(idx, true)
--   \u5f71\u4e4b\u6b66\u88c5 \u952e\u76d8 2 / \u624b\u67c4\u5341\u5b57\u952e\u53f3   -> SetCurrentWeaponByIndex(idx, false)
-- \u6bcf\u5957\u5404\u81ea\u6709 \u5173\u95ed / \u5faa\u73af / \u968f\u673a / \u81ea\u5b9a\u4e49\u6c60 \u56db\u79cd\u6a21\u5f0f\uff0cF9 \u6253\u5f00\u83dc\u5355\uff0c\u9996\u884c\u9009\u62e9\u8981\u914d\u7f6e\u54ea\u4e00\u5957\u3002
-- 4.5.0\uff1a\u91cd\u505a\u83dc\u5355\u9762\u677f\u6392\u7248\u4e0e\u72b6\u6001\u884c\uff1b\u6b66\u5668\u5217\u8868\u6309\u62fc\u97f3\u6392\u5e8f\u3001\u652f\u6301\u81ea\u5b9a\u4e49\u6c60\uff1b
--        \u65b0\u589e\u201c\u6b66\u5668\u5207\u6362\u51b7\u5374\u201d\u5f00\u5173\uff08cd=1 \u4fdd\u7559\u6e38\u620f\u539f\u751f\u51b7\u5374\uff0ccd=0 \u7531\u6a21\u7ec4\u5207\u6362\u540e\u7acb\u5373\u6e05\u51b7\u5374\uff09\u3002
"""


def cut(text, start_marker, end_marker):
    i = text.find(start_marker)
    if i < 0:
        raise SystemExit("FAIL start: " + repr(start_marker))
    line_start = text.rfind("\n", 0, i) + 1
    j = text.find(end_marker, line_start + len(start_marker))
    if j < 0:
        raise SystemExit("FAIL end: " + repr(end_marker))
    line_end = text.rfind("\n", 0, j) + 1
    return text[:line_start] + text[line_end:]


def main():
    if not BAK.exists():
        shutil.copy2(SRC, BAK)
        print("backup ->", BAK)
    text = SRC.read_text(encoding="utf-8")
    print("before:", text.count("\n") + 1, "lines", len(text.encode("utf-8")), "bytes")
    for a, b in CUTS:
        text = cut(text, a, b)
    text = HEADER + "\n" + text[text.index("local SRC = debug.getinfo"):]
    text = text.replace('local VERSION = "4.8.26"', 'local VERSION = "4.5.0"')
    reps = [
        ('-- Cfg[kind] = { mode = "off"|"cycle"|"random"|"pick", cd = bool, pool = { [id]=true } | nil }',
         '-- Cfg[kind] = { mode = "off"|"cycle"|"random", cd = bool, pool = { [id]=true } | nil }'),
        ('        { label = L("\u81ea\u9009\uff08\u6682\u505c\u6e38\u620f\uff0c\u5f39\u51fa\u9762\u677f\u9009\u62e9\uff09", "Pick (pause and choose from a panel)"), value = "pick" },\n', ''),
        ('-- \u65e7\u683c\u5f0f\uff1a\u7b49 cmode \u884c\u5347\u7ea7\u6210 pick/random/cycle', '-- \u65e7\u683c\u5f0f\uff1a\u7b49 cmode \u884c\u5347\u7ea7\u6210 random/cycle'),
        ('        if picking then finishPick(true); return end\n', ''),
        ('        if picking then log("world changed while picking: closing panel"); pcall(finishPick, true) end\n', ''),
        ('        singleSlotDone = false\n', ''),
        ('        -- \u5207\u56fe\u65f6\u52a1\u5fc5\u628a\u65f6\u505c\u653e\u6389\uff0c\u5426\u5219\u65b0\u573a\u666f\u4f1a\u5e26\u7740 0.02 \u7684\u65f6\u95f4\u81a8\u80c0\u8fdb\u6765\n', ''),
        ('        if PAUSE_HELD then pcall(setPaused, false) end\n', ''),
        ('        ExecuteInGameThreadWithDelay(5000, function() pcall(autoSelfTest) end)\n', ''),
        ('            if not nameCtorLogged then pcall(logNameCtor) end\n', ''),
        ('    if picking then return end\n', ''),
        ('        if picking then idleTicks = 0; return end\n', ''),
        ('local singleSlotDone = false\n', ''),
        ('if v == "off" or v == "cycle" or v == "random" or v == "pick" then return v end',
         'if v == "off" or v == "cycle" or v == "random" then return v end'),
    ]
    for old, new in reps:
        if old not in text:
            print("WARN missing:", old.strip()[:60])
        text = text.replace(old, new)
    SRC.write_text(text, encoding="utf-8")
    print("after:", text.count("\n") + 1, "lines", len(text.encode("utf-8")), "bytes")


main()
