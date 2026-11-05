import base64, json, os, socket, time, urllib.request, urllib.error

TEMP = os.environ.get("TEMP", ".")
TOKEN = os.environ.get("GH_TOKEN", "").strip() or open(os.path.join(TEMP, "ghtok.txt"), "r", encoding="utf-8").read().strip()
REPO = "Woeful001/pbz-weapon-swap"
API = "https://api.github.com"
LOCAL = r"D:\Projects\pbz-weapon-swap"
ZIP = os.path.join(LOCAL, "dist", "PBZWeaponSwap-4.1.0.zip")
TAG = "v4.1.0"
NAME = "PBZ Weapon Swap 4.1.0"
BODY = """## 4.1.0

- 连点 F9 崩溃修复：菜单开关加入 0.45 秒防抖，并对菜单框架做失效控件加固（切图或重开后遇到已销毁的控件不再操作，只重置状态）
- 打开背包时自动关闭模组菜单，避免两套 UI 同时抢输入模式导致崩溃

安装：把 PBZWeaponSwap 放进 ue4ss/Mods/，在 mods.txt 里加 PBZWeaponSwap : 1（或在该文件夹放一个空的 enabled.txt）。详见 README。
"""

FILES = [
    "README.md", "install.ps1",
    "src/PBZWeaponSwap/README.txt",
    "src/PBZWeaponSwap/Scripts/main.lua",
    "src/PBZWeaponSwap/Scripts/vendor/ModMenu.lua",
    "src/PBZWeaponSwap/Scripts/vendor/UEHelpers.lua",
]

_orig_gai = socket.getaddrinfo
def _gai(host, port, *a, **kw):
    if host == "uploads.github.com":
        try:
            return _orig_gai("20.205.243.161", port, *a, **kw)
        except Exception:
            pass
    return _orig_gai(host, port, *a, **kw)
socket.getaddrinfo = _gai


def call(method, url, payload=None, raw=None, ctype="application/json", tries=5):
    full = url if url.startswith("http") else API + url
    data = raw if raw is not None else (json.dumps(payload).encode() if payload is not None else None)
    last = None
    for attempt in range(tries):
        req = urllib.request.Request(full, data=data, method=method)
        req.add_header("Authorization", "Bearer " + TOKEN)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("User-Agent", "pbz-release-script")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if data is not None:
            req.add_header("Content-Type", ctype)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                b = r.read()
                return r.status, (json.loads(b) if b else None)
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")[:400]
        except Exception as e:
            last = e
            print("retry", method, full[:70], attempt + 1, type(e).__name__)
            time.sleep(1.5 * (attempt + 1))
    raise SystemExit(f"network failed: {method} {full}: {last}")


st, ref = call("GET", f"/repos/{REPO}/git/ref/heads/main")
if st != 200:
    raise SystemExit(f"ref fail {st} {ref}")
head = ref["object"]["sha"]
print("head", head[:10])
st, base = call("GET", f"/repos/{REPO}/git/commits/{head}")
base_tree = base["tree"]["sha"]

entries = []
for rel in FILES:
    p = os.path.join(LOCAL, rel.replace("/", os.sep))
    raw = open(p, "rb").read()
    st, blob = call("POST", f"/repos/{REPO}/git/blobs", {"content": base64.b64encode(raw).decode(), "encoding": "base64"})
    if st != 201:
        print("blob fail", rel, st, blob); raise SystemExit(1)
    entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    print("blob", rel, len(raw))

st, tree = call("POST", f"/repos/{REPO}/git/trees", {"base_tree": base_tree, "tree": entries})
if st != 201:
    print("tree fail", st, tree); raise SystemExit(1)
print("tree", tree["sha"][:10])

st, commit = call("POST", f"/repos/{REPO}/git/commits", {
    "message": "4.1.0: fix crash on spamming F9 toggle and on opening inventory",
    "tree": tree["sha"], "parents": [head]})
if st != 201:
    print("commit fail", st, commit); raise SystemExit(1)
print("commit", commit["sha"][:10])

st, upd = call("PATCH", f"/repos/{REPO}/git/refs/heads/main", {"sha": commit["sha"], "force": True})
print("ref update", st)

st, rel = call("GET", f"/repos/{REPO}/releases/tags/{TAG}")
if st == 200:
    rid = rel["id"]
    st2, _ = call("PATCH", f"/repos/{REPO}/releases/{rid}", {"name": NAME, "body": BODY})
    print("release exists, patched", st2)
else:
    st, rel = call("POST", f"/repos/{REPO}/releases", {
        "tag_name": TAG, "name": NAME, "body": BODY, "target_commitish": commit["sha"]})
    if st != 201:
        print("release create fail", st, rel); raise SystemExit(1)
    rid = rel["id"]
    print("release created", rid)

for a in rel.get("assets", []):
    if a["name"] == os.path.basename(ZIP):
        st, _ = call("DELETE", f"/repos/{REPO}/releases/assets/{a['id']}")
        print("delete old asset", st)

raw = open(ZIP, "rb").read()
st, asset = call("POST", f"https://uploads.github.com/repos/{REPO}/releases/{rid}/assets?name={os.path.basename(ZIP)}", raw=raw, ctype="application/zip")
print("asset upload", st, (asset or {}).get("name"), (asset or {}).get("size"))
print("url", f"https://github.com/{REPO}/releases/tag/{TAG}")
