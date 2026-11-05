"""打包发布用的 zip：python tools/build_zip.py 4.9.0

只做本地打包，不联网、不提交 git。zip 结构（与 4.8.0 起的发布包一致）：
    PBZWeaponSwap/config.txt
    PBZWeaponSwap/README.txt
    PBZWeaponSwap/snapshot.txt
    PBZWeaponSwap/Scripts/main.lua
    PBZWeaponSwap/Scripts/vendor/ModMenu.lua
    PBZWeaponSwap/Scripts/vendor/UEHelpers.lua
"""
import os
import re
import sys
import zipfile

LOCAL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(LOCAL, "src", "PBZWeaponSwap")

CONFIG_TMPL = """version={ver}
lang=auto
target=main
cd=0
main.mode=cycle
shaqi.mode=cycle
"""

SNAPSHOT = b"1\r\nIronBlade\r\nZhanMaBlade\r\n"


def version_from_source():
    src = open(os.path.join(MOD, "Scripts", "main.lua"), encoding="utf-8").read()
    m = re.search(r'local VERSION = "([^"]+)"', src)
    return m.group(1) if m else None


def main():
    ver = sys.argv[1] if len(sys.argv) > 1 else version_from_source()
    src_ver = version_from_source()
    if src_ver != ver:
        raise SystemExit(f"版本不一致：main.lua 里是 {src_ver}，参数是 {ver}")
    out = os.path.join(LOCAL, "dist", f"PBZWeaponSwap-{ver}.zip")
    members = [
        ("PBZWeaponSwap/config.txt", CONFIG_TMPL.format(ver=ver).replace("\n", "\r\n").encode()),
        ("PBZWeaponSwap/README.txt", open(os.path.join(MOD, "README.txt"), "rb").read()),
        ("PBZWeaponSwap/snapshot.txt", SNAPSHOT),
        ("PBZWeaponSwap/Scripts/main.lua", open(os.path.join(MOD, "Scripts", "main.lua"), "rb").read()),
        ("PBZWeaponSwap/Scripts/vendor/ModMenu.lua",
         open(os.path.join(MOD, "Scripts", "vendor", "ModMenu.lua"), "rb").read()),
        ("PBZWeaponSwap/Scripts/vendor/UEHelpers.lua",
         open(os.path.join(MOD, "Scripts", "vendor", "UEHelpers.lua"), "rb").read()),
    ]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in members:
            z.writestr(name, data)
    print("wrote", out, os.path.getsize(out), "bytes")
    for name, data in members:
        print(f"  {len(data):>8}  {name}")


if __name__ == "__main__":
    main()
