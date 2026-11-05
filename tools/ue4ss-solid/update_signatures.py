#!/usr/bin/env python3
"""Regenerate the two UE4SS Lua signatures for Phantom Blade Zero after a game patch.

UE4SS ships no generic AOB table for PBZ; the loader needs `UE4SS_Signatures/GNatives.lua`
and `UE4SS_Signatures/GUObjectArray.lua`, and both hard-code absolute RVAs plus the EXE
fingerprint (TimeDateStamp / SizeOfImage). Every PBZ patch moves those values, the checks
fail, the scan reports "Was unable to find AOB for 'GNatives'" and UE4SS aborts.

This script re-derives everything from the current PBZ.exe:
  1. locate the dispatch loop / object-iterator patterns (unique hit required),
  2. follow the RIP-relative references inside the hit to the native table and FUObjectArray,
  3. validate section flags, alignment and every slot pointer,
  4. rewrite both signature files (old ones backed up next to them).

Usage:
  python update_signatures.py --check        # report only, write nothing
  python update_signatures.py                # write, after backing up existing files
  python update_signatures.py --out-dir DIR  # write into DIR instead (dry run with files)

Exit codes: 0 ok, 1 nothing written because a validation failed (old files untouched).
"""

import argparse
import datetime
import hashlib
import os
import re
import shutil
import struct
import sys

EXE_NAME = "PBZ.exe"
ENTRY_COUNT = 0xFF

DEFAULT_GNATIVES_PATTERN = (
    "48 89 5C 24 20 56 57 41 56 48 83 EC 70 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 44 24 60 "
    "48 8B 42 20 4C 8D 35 ?? ?? ?? ?? 48 8B 72 10 49 8B F8 48 8B DA 80 38 04 74 40 48 8B D0 "
    "0F 1F 80 00 00 00 00 80 BB A1 00 00 00 00 48 8B C2 75 5C 0F B6 0A 48 8D 42 01 48 89 43 20 "
    "4C 8D 44 24 20 48 8B D3 4D 8B 0C CE 48 8B 4B 18 41 FF D1 48 8B 43 20 48 8B D0 80 38 04 75 CA "
    "80 BB A1 00 00 00 00 75 29 48 FF C0 48 89 43 20 0F B6 08 48 FF C0 48 89 43 20 80 F9 0B 74 7F "
    "4D 8B 0C CE 4C 8B C7 48 8B 4B 18 48 8B D3 41 FF D1 EB 6C"
)

DEFAULT_GUOBJECTARRAY_PATTERN = (
    "48 89 5C 24 08 57 48 83 EC 20 48 C7 41 10 00 00 00 00 48 8D 05 ?? ?? ?? ?? 48 89 01 "
    "B8 FF FF FF FF 89 41 08 4C 8B D2 48 8B D9 45 84 C0 74 0F 8B 05 ?? ?? ?? ?? 89 41 08 "
    "8B 05 ?? ?? ?? ?? 44 8D 40 01 44 89 41 08 44 3B 05 ?? ?? ?? ?? 7D 3D 90 41 0F B7 C0 "
    "41 8B C8 48 C1 E9 10 48 8D 14 40 48 8B 05 ?? ?? ?? ?? 48 8B 0C C8 48 83 7C D1 08 00 "
    "48 8D 04 D1 75 12 41 FF C0 44 89 43 08 44 3B 05 ?? ?? ?? ?? 7C CA EB 04 48 89 43 10 "
    "4C 89 53 18 44 89 4B 20"
)

# RIP-relative sites: (offset of the disp32 inside the match, offset just past the instruction).
GNATIVES_TABLE_SITE = (0x23, 0x27)
GUOBJECT_SITES = [(21, 25), (49, 53), (58, 62), (73, 77), (98, 102), (128, 132)]


class PE:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as handle:
            self.data = handle.read()
        self.sha256 = hashlib.sha256(self.data).hexdigest()
        if self.data[:2] != b"MZ":
            raise SystemExit("not a PE file: " + path)
        pe = self.u32(0x3C)
        if self.data[pe:pe + 4] != b"PE\0\0":
            raise SystemExit("missing PE signature")
        self.machine, self.nsections = struct.unpack_from("<HH", self.data, pe + 4)
        self.timestamp = self.u32(pe + 8)
        opt_size = struct.unpack_from("<H", self.data, pe + 20)[0]
        self.opt_size = opt_size
        self.opt = pe + 24
        self.magic = self.u16(self.opt)
        self.image_base = struct.unpack_from("<Q", self.data, self.opt + 24)[0]
        self.image_size = self.u32(self.opt + 56)
        self.sections = []
        header = self.opt + opt_size
        for index in range(self.nsections):
            base = header + index * 40
            name = self.data[base:base + 8].rstrip(b"\0").decode("latin1")
            vsize, va, raw_size, raw_ptr = struct.unpack_from("<IIII", self.data, base + 8)
            flags = self.u32(base + 36)
            self.sections.append({
                "name": name, "vsize": vsize, "va": va, "raw_size": raw_size,
                "raw_ptr": raw_ptr, "flags": flags,
                "executable": bool(flags & 0x20000000),
                "writable": (flags & 0xC0000000) == 0xC0000000,
            })

    def u16(self, offset):
        return struct.unpack_from("<H", self.data, offset)[0]

    def u32(self, offset):
        return struct.unpack_from("<I", self.data, offset)[0]

    def u64(self, offset):
        return struct.unpack_from("<Q", self.data, offset)[0]

    def find(self, pattern):
        tokens = pattern.split()
        regex = b"".join(b"." if token == "??" else re.escape(bytes([int(token, 16)])) for token in tokens)
        hits = []
        for section in self.sections:
            if not section["executable"] or not section["raw_size"]:
                continue
            blob = self.data[section["raw_ptr"]:section["raw_ptr"] + section["raw_size"]]
            for match in re.finditer(regex, blob, re.DOTALL):
                hits.append(section["va"] + match.start())
        return hits

    def section_of(self, rva):
        for section in self.sections:
            if section["va"] <= rva < section["va"] + max(section["vsize"], section["raw_size"]):
                return section
        return None

    def file_offset(self, rva):
        section = self.section_of(rva)
        if section is None:
            return None
        delta = rva - section["va"]
        if delta >= section["raw_size"]:
            return None
        return section["raw_ptr"] + delta

    def read_u64(self, rva):
        offset = self.file_offset(rva)
        return None if offset is None else self.u64(offset)

    def to_rva(self, address):
        # Table slots hold image-base-relative VAs for a fixed-base PE.
        return address - self.image_base if address >= self.image_base else address

    def in_executable(self, address):
        va = self.to_rva(address)
        section = self.section_of(va)
        return bool(section and section["executable"] and va < section["va"] + section["vsize"])

    def in_writable(self, address, span):
        va = self.to_rva(address)
        section = self.section_of(va)
        if not section or not section["writable"]:
            return False
        return va + span <= section["va"] + max(section["vsize"], section["raw_size"])


def displacement_at(pe, hit_rva, disp_offset):
    offset = pe.file_offset(hit_rva + disp_offset)
    if offset is None:
        return None
    return struct.unpack_from("<i", pe.data, offset)[0]


def rip_target(pe, hit_rva, site):
    disp_offset, next_offset = site
    disp = displacement_at(pe, hit_rva, disp_offset)
    if disp is None:
        return None
    return hit_rva + next_offset + disp


def pattern_from(path, fallback):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return fallback
    match = re.search(r'local Pattern = "([0-9A-F? ]+)"', text)
    return match.group(1) if match else fallback


def build_id(pe):
    """PBZ appmanifest buildid when the file sits in a normal Steam library."""
    here = os.path.abspath(pe.path)
    for _ in range(6):
        here = os.path.dirname(here)
        candidate = os.path.join(here, "steamapps", "appmanifest_4115450.acf")
        if os.path.isfile(candidate):
            text = open(candidate, encoding="utf-8", errors="replace").read()
            found = re.search(r'"buildid"\s+"(\d+)"', text)
            if found:
                return found.group(1)
    return "ts%d" % pe.timestamp


GNATIVES_TEMPLATE = '''-- Generated by update_signatures.py for PBZ build @BUILD@ (Steam app 4115450).
-- EXE SHA-256: @SHA@
-- TimeDateStamp @TIMESTAMP@ / SizeOfImage @IMAGE_SIZE@ / @SECTIONS@ sections.
-- Re-run the script after a game patch; do not hand-edit the RVAs.
-- Resolve the real bytecode dispatch table, not ProcessLocalScriptFunction.
-- EX_Max is 0xFF: 255 eight-byte entries; index 255 is outside this array.

local Pattern = "@PATTERN@"
local FunctionRVA = @FUNCTION_RVA@
local TableRVA = @TABLE_RVA@
local EntryCount = 0xFF

local function u32(address)
    local value = DerefToInt32(address)
    if value == nil then return nil end
    return value & 0xFFFFFFFF
end

local function rip(address, displacement_offset, next_offset)
    -- DerefToInt32 returns a signed displacement; retain its sign.
    local displacement = DerefToInt32(address + displacement_offset)
    if displacement == nil then return nil end
    return address + next_offset + displacement
end

local function contains(ranges, address, span)
    for _, range in ipairs(ranges) do
        if address >= range[1] and address + span <= range[2] then return true end
    end
    return false
end

function Register()
    return Pattern
end

function OnMatchFound(address)
    local module_base = address - FunctionRVA
    if module_base <= 0 or module_base >= 0x800000000000 or module_base % 0x10000 ~= 0 then return nil end
    local mz, nt_offset = u32(module_base), u32(module_base + 0x3C)
    if mz == nil or (mz & 0xFFFF) ~= 0x5A4D or nt_offset == nil or nt_offset < 0x40 or nt_offset > 0x1000 then return nil end
    local nt = module_base + nt_offset
    if u32(nt) ~= 0x4550 or u32(nt + 8) ~= @TIMESTAMP@ then return nil end
    local machine_sections, optional_size = u32(nt + 4), u32(nt + 20)
    if machine_sections == nil or optional_size == nil or (machine_sections & 0xFFFF) ~= 0x8664 then return nil end
    local count = machine_sections >> 16
    if count ~= @SECTIONS@ or (optional_size & 0xFFFF) ~= @OPTIONAL_SIZE@ then return nil end
    local magic = u32(nt + 24)
    if magic == nil or (magic & 0xFFFF) ~= 0x20B or u32(nt + 24 + 56) ~= @IMAGE_SIZE@ then return nil end

    local executable, writable = {}, {}
    local first_section = nt + 24 + @OPTIONAL_SIZE@
    for index = 0, count - 1 do
        local header = first_section + index * 40
        local size, start, flags = u32(header + 8), u32(header + 12), u32(header + 36)
        if size == nil or start == nil or flags == nil or start + size > @IMAGE_SIZE@ then return nil end
        local range = {module_base + start, module_base + start + size}
        if (flags & 0x20000000) ~= 0 and (flags & 0x40000000) ~= 0 then
            executable[#executable + 1] = range
        elseif (flags & 0xC0000000) == 0xC0000000 then
            writable[#writable + 1] = range
        end
    end
    if not contains(executable, address, @MATCH_SPAN@) then return nil end

    local native_table = rip(address, 0x23, 0x27)
    if native_table == nil or native_table % 8 ~= 0 or native_table - module_base ~= TableRVA then return nil end
    if not contains(writable, native_table, EntryCount * 8) then return nil end

    -- The mapped table may still contain valid undefined-opcode handlers during
    -- startup. Check every slot's pointer, without pretending registration ran.
    for index = 0, EntryCount - 1 do
        local slot = native_table + index * 8
        local low, high = u32(slot), u32(slot + 4)
        if low == nil or high == nil then return nil end
        local handler = (high << 32) | low
        if not contains(executable, handler, 1) then return nil end
    end

    print(string.format("[PBZ @BUILD@] GNatives resolved: 0x%X (255 executable entries)", native_table))
    return native_table
end
'''

GUOBJECT_TEMPLATE = '''-- Generated by update_signatures.py for PBZ build @BUILD@ (Steam app 4115450).
-- EXE SHA-256: @SHA@
-- TimeDateStamp @TIMESTAMP@ / SizeOfImage @IMAGE_SIZE@.
-- Derived from the PBZ object iterator and corroborated by startup/shutdown code.
-- RIP-relative references return the FUObjectArray global itself.
-- The global is in zero-filled virtual data: no file-backed-data requirement.

local Pattern = "@PATTERN@"
local FunctionRVA = @FUNCTION_RVA@
local GlobalRVA = @GLOBAL_RVA@

local function u32(address)
    local value = DerefToInt32(address)
    if value == nil then return nil end
    return value & 0xFFFFFFFF
end

local function rip(address, displacement_offset, next_offset)
    local displacement = DerefToInt32(address + displacement_offset)
    if displacement == nil then return nil end
    return address + next_offset + displacement
end

local function mapped_section(module_base, first_section, count, address, span, executable)
    local rva = address - module_base
    for index = 0, count - 1 do
        local header = first_section + index * 40
        local size, start, flags = u32(header + 8), u32(header + 12), u32(header + 36)
        if size ~= nil and start ~= nil and flags ~= nil and rva >= start and rva + span <= start + size then
            if executable then return (flags & 0x20000000) ~= 0 end
            return (flags & 0x80000000) ~= 0 and (flags & 0x20000000) == 0
        end
    end
    return false
end

function Register()
    return Pattern
end

function OnMatchFound(address)
    local module_base = address - FunctionRVA
    if module_base <= 0 or module_base % 0x10000 ~= 0 then return nil end
    local mz, nt_offset = u32(module_base), u32(module_base + 0x3C)
    if mz == nil or (mz & 0xFFFF) ~= 0x5A4D or nt_offset == nil or nt_offset > 0x1000 then return nil end
    local nt = module_base + nt_offset
    if u32(nt) ~= 0x4550 or u32(nt + 8) ~= @TIMESTAMP@ then return nil end
    local machine_sections, optional_size = u32(nt + 4), u32(nt + 20)
    if machine_sections == nil or optional_size == nil or (machine_sections & 0xFFFF) ~= 0x8664 then return nil end
    local count = machine_sections >> 16
    if count < 1 or count > 64 or u32(nt + 24 + 56) ~= @IMAGE_SIZE@ then return nil end
    local first_section = nt + 24 + (optional_size & 0xFFFF)
    if not mapped_section(module_base, first_section, count, address, @MATCH_SPAN@, true) then return nil end

    local global = rip(address, 21, 25)
    if global == nil or global % 8 ~= 0 or global - module_base ~= GlobalRVA then return nil end
    if not mapped_section(module_base, first_section, count, global, 0xE8, false) then return nil end
    -- Independent instructions agree on last non-GC index, object count and chunk table.
    if rip(address, 49, 53) ~= global + 4 then return nil end
    if rip(address, 58, 62) ~= global + 4 then return nil end
    if rip(address, 73, 77) ~= global + 0x20 then return nil end
    if rip(address, 98, 102) ~= global + 0x18 then return nil end
    if rip(address, 128, 132) ~= global + 0x20 then return nil end
    print(string.format("[PBZ @BUILD@] GUObjectArray resolved: 0x%X", global))
    return global
end
'''


def derive(pe, gnat_pattern, gobj_pattern):
    errors = []

    hits = pe.find(gnat_pattern)
    if len(hits) != 1:
        errors.append("GNatives pattern matched %d times (need exactly 1)" % len(hits))
        gnat_hit = None
    else:
        gnat_hit = hits[0]

    hits2 = pe.find(gobj_pattern)
    if len(hits2) != 1:
        errors.append("GUObjectArray pattern matched %d times (need exactly 1)" % len(hits2))
        gobj_hit = None
    else:
        gobj_hit = hits2[0]

    table_rva = target_rva = None
    if gnat_hit is not None:
        table_rva = rip_target(pe, gnat_hit, GNATIVES_TABLE_SITE)
        section = pe.section_of(table_rva) if table_rva is not None else None
        if table_rva is None or table_rva % 8 or not pe.in_writable(table_rva, ENTRY_COUNT * 8):
            errors.append("native table 0x%X is not 8-aligned inside a writable section" % (table_rva or 0))
        else:
            bad = 0
            for index in range(ENTRY_COUNT):
                slot = table_rva + index * 8
                value = pe.read_u64(slot)
                if value is None or not pe.in_executable(value):
                    bad += 1
            if bad:
                errors.append("%d of %d native table slots do not point into executable code" % (bad, ENTRY_COUNT))

    if gobj_hit is not None:
        target_rva = rip_target(pe, gobj_hit, GUOBJECT_SITES[0])
        if target_rva is None or target_rva % 8 or not pe.in_writable(target_rva, 0xE8):
            errors.append("FUObjectArray global 0x%X is not 8-aligned in writable data" % (target_rva or 0))
        else:
            expect = {1: 4, 2: 4, 3: 0x20, 4: 0x18, 5: 0x20}
            for index, delta in expect.items():
                got = rip_target(pe, gobj_hit, GUOBJECT_SITES[index])
                if got != target_rva + delta:
                    errors.append("cross-check %d: 0x%X != 0x%X (+0x%X)" % (index, got or 0, target_rva, delta))

    return gnat_hit, table_rva, gobj_hit, target_rva, errors


def render(template, values):
    text = template
    for key, value in values.items():
        text = text.replace("@" + key + "@", str(value))
    return text


def check_lua(path):
    try:
        from luaparser import ast
    except ImportError:
        return "luaparser not installed, skipped"
    ast.parse(open(path, encoding="utf-8").read())
    return "syntax ok"


def main():
    parser = argparse.ArgumentParser(description="Regenerate PBZ UE4SS signatures")
    parser.add_argument("--exe", help="path to PBZ.exe (default: two levels above this script)")
    parser.add_argument("--out-dir", help="write here instead of ue4ss/UE4SS_Signatures")
    parser.add_argument("--check", action="store_true", help="report only, never write")
    parser.add_argument("--force", action="store_true", help="write even though files look current")
    args = parser.parse_args()

    root = os.path.dirname(os.path.abspath(__file__))
    ue4ss_dir = os.path.dirname(root)
    steam_dir = os.path.dirname(ue4ss_dir)
    exe = args.exe or os.path.join(steam_dir, EXE_NAME)
    sig_dir = os.path.join(ue4ss_dir, "UE4SS_Signatures")
    out_dir = args.out_dir or sig_dir

    if not os.path.isfile(exe):
        raise SystemExit("PBZ.exe not found: " + exe)
    pe = PE(exe)
    build = build_id(pe)
    print("exe        %s" % exe)
    print("build      %s" % build)
    print("fingerprint TimeDateStamp %d / SizeOfImage %d / %d sections" % (pe.timestamp, pe.image_size, pe.nsections))
    print("sha256     %s" % pe.sha256)

    gnat_pattern = pattern_from(os.path.join(sig_dir, "GNatives.lua"), DEFAULT_GNATIVES_PATTERN)
    gobj_pattern = pattern_from(os.path.join(sig_dir, "GUObjectArray.lua"), DEFAULT_GUOBJECTARRAY_PATTERN)

    gnat_hit, table_rva, gobj_hit, target_rva, errors = derive(pe, gnat_pattern, gobj_pattern)
    if gnat_hit is not None:
        print("GNatives   fn 0x%08X  table 0x%08X" % (gnat_hit, table_rva or 0))
    if gobj_hit is not None:
        print("GUObject   fn 0x%08X  global 0x%08X" % (gobj_hit, target_rva or 0))

    if errors:
        print()
        for line in errors:
            print("FAIL " + line)
        print("\nnothing written; the game code changed, fresh patterns are needed")
        return 1

    common = {
        "BUILD": build,
        "SHA": pe.sha256,
        "TIMESTAMP": pe.timestamp,
        "IMAGE_SIZE": pe.image_size,
        "SECTIONS": pe.nsections,
        "OPTIONAL_SIZE": "0x%X" % pe.opt_size,
        "MATCH_SPAN": "0x%X" % len(gnat_pattern.split()),
    }
    gnat_text = render(GNATIVES_TEMPLATE, dict(common, PATTERN=gnat_pattern,
                                              FUNCTION_RVA="0x%08X" % gnat_hit,
                                              TABLE_RVA="0x%08X" % table_rva))
    gobj_text = render(GUOBJECT_TEMPLATE, dict(common, PATTERN=gobj_pattern,
                                              FUNCTION_RVA="0x%08X" % gobj_hit,
                                              GLOBAL_RVA="0x%08X" % target_rva,
                                              MATCH_SPAN="0x%X" % len(gobj_pattern.split())))

    if args.check:
        print("\n--check: not writing anything")
        return 0

    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    for name, text in (("GNatives.lua", gnat_text), ("GUObjectArray.lua", gobj_text)):
        target = os.path.join(out_dir, name)
        if os.path.isfile(target) and not args.out_dir:
            backup = "%s.bak-%s" % (target, stamp)
            shutil.copy2(target, backup)
            print("backup     %s" % backup)
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("written    %s (%d bytes)" % (target, len(text.encode("utf-8"))))
        print("           %s" % check_lua(target))

    print("\nnow start the game and check ue4ss/UE4SS.log for")
    print("  [PBZ %s] GNatives resolved: 0x..." % build)
    print("  [PBZ %s] GUObjectArray resolved: 0x..." % build)
    return 0


if __name__ == "__main__":
    sys.exit(main())
