"""Create (or update) a GitHub release and upload the packaged zip.

Usage:
    set GH_TOKEN=...            (or write %TEMP%\\ghtok.txt)
    python tools/make_release.py 4.5.0

Repo: Woeful001/pbz-weapon-swap, tag: v<version>, asset: dist/PBZWeaponSwap-<version>.zip
Talks to api.github.com only (the git host may be blocked while the API is reachable).
"""
import json
import os
import sys
import urllib.error
import urllib.request

OWNER = "Woeful001"
REPO = "pbz-weapon-swap"
API = "https://api.github.com"

NOTES = {
    "4.5.12": (
        "**4.5.12**\n\n"
        "- 优化了部分代码\n\n"
        "下载 `PBZWeaponSwap-4.5.12.zip`，解压到游戏的 `platform/steam/ue4ss/Mods/` 目录。"
    ),
    "4.5.5": (
        "**4.5.5**\n\n"
        "- 修复已知的崩溃 bug，优化部分逻辑\n\n"
        "下载 `PBZWeaponSwap-4.5.5.zip`，解压到游戏的 `platform/steam/ue4ss/Mods/` 目录。"
    ),
    "4.5.0": (
        "**4.5.0**\n\n"
        "- 优化了 UI：菜单重排为 目标 → 模式 → 冷却 → 武器池 → 操作按钮，状态分三行显示，武器列表按拼音排序\n"
        "- 新增开关武器冷却功能（菜单复选框，或 config.txt 里的 cd=）\n"
        "- 移除自选（暂停弹面板选武器）与单槽实验代码，包内不再带 pickpanel.lua\n\n"
        "下载 `PBZWeaponSwap-4.5.0.zip`，解压到游戏的 `platform/steam/ue4ss/Mods/` 目录。"
    ),
}


def token():
    tok = os.environ.get("GH_TOKEN", "").strip()
    if tok:
        return tok
    for p in (os.path.join(os.environ.get("TEMP", ""), "ghtok.txt"), os.path.expanduser("~/.ghtok")):
        if p and os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                v = f.read().strip()
            if v:
                return v
    # 兜底：直接从 Windows 凭据管理器取 git 用的那种 classic PAT
    import subprocess
    out = subprocess.run(
        ["git", "-c", "credential.helper=manager", "credential", "fill"],
        input="protocol=https\nhost=github.com\nusername=Woeful001\n\n",
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1].strip()
    sys.exit("no GH_TOKEN")


def call(url, tok, method="GET", data=None, ctype="application/json"):
    body = data
    if data is not None and ctype == "application/json":
        body = json.dumps(data).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + tok,
            "User-Agent": "pbz-weapon-swap",
            "Accept": "application/vnd.github+json",
            "Content-Type": ctype,
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
        if not raw:
            return r.status, {}
        if "json" in (r.headers.get("Content-Type") or ""):
            return r.status, json.loads(raw)
        return r.status, raw


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python tools/make_release.py <version>")
    ver = sys.argv[1].lstrip("v")
    tag = "v" + ver
    tok = token()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    zpath = os.path.join(here, "dist", "PBZWeaponSwap-%s.zip" % ver)
    if not os.path.exists(zpath):
        sys.exit("missing %s (run tools/build_zip.py %s first)" % (zpath, ver))

    notes = NOTES.get(ver, "**%s**" % ver)
    payload = {"tag_name": tag, "name": "PBZWeaponSwap " + ver, "body": notes,
               "draft": False, "prerelease": False}

    rel = None
    try:
        st, rel = call("%s/repos/%s/%s/releases/tags/%s" % (API, OWNER, REPO, tag), tok)
        print("existing release:", rel["html_url"])
        st, rel = call("%s/repos/%s/%s/releases/%d" % (API, OWNER, REPO, rel["id"]), tok,
                       "PATCH", payload)
        print("updated release")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            sys.exit("lookup failed %s %s" % (e.code, e.read().decode()[:300]))
        st, rel = call("%s/repos/%s/%s/releases" % (API, OWNER, REPO), tok, "POST", payload)
        print("created release:", rel["html_url"])

    name = os.path.basename(zpath)
    existing = {a["name"]: a for a in rel.get("assets", [])}
    if name in existing:
        call("%s/repos/%s/%s/releases/assets/%d" % (API, OWNER, REPO, existing[name]["id"]), tok, "DELETE")
        print("deleted old asset", name)

    with open(zpath, "rb") as f:
        blob = f.read()
    up = rel["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(name)
    st, asset = call(up, tok, "POST", blob, "application/zip")
    print("asset %s: %d bytes -> %s" % (asset["name"], asset["size"], asset["browser_download_url"]))


if __name__ == "__main__":
    import urllib.parse  # noqa: E402  (used in main)

    main()
