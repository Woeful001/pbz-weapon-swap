import base64, json, os, time, urllib.request, urllib.error

TEMP = os.environ.get("TEMP", ".")
TOKEN = os.environ.get("GH_TOKEN", "").strip() or open(os.path.join(TEMP, "ghtok.txt"), "r", encoding="utf-8").read().strip()
REPO = "Woeful001/pbz-weapon-swap"
API = "https://api.github.com"
LOCAL = r"D:\Projects\pbz-weapon-swap"
ZIP = os.path.join(LOCAL, "dist", "PBZWeaponSwap-3.1.0.zip")

FILES = [
    "README.md",
    "install.ps1",
    "src/PBZWeaponSwap/README.txt",
    "src/PBZWeaponSwap/Scripts/main.lua",
    "src/PBZWeaponSwap/Scripts/vendor/ModMenu.lua",
    "src/PBZWeaponSwap/Scripts/vendor/UEHelpers.lua",
]


def call(method, path, payload=None, raw=None, ctype="application/json", tries=5):
    data = raw if raw is not None else (json.dumps(payload).encode() if payload is not None else None)
    last = None
    for attempt in range(tries):
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + TOKEN)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("User-Agent", "pbz-release-script")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if data is not None:
            req.add_header("Content-Type", ctype)
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                b = r.read()
                return r.status, (json.loads(b) if b else None)
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")[:400]
        except Exception as e:  # 连接被重置等，重试
            last = e
            print("retry", method, path, attempt + 1, type(e).__name__)
            time.sleep(1.5 * (attempt + 1))
    raise SystemExit(f"network failed: {method} {path}: {last}")


st, ref = call("GET", f"/repos/{REPO}/git/ref/heads/main")
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
        print("blob fail", rel, st, blob)
        raise SystemExit(1)
    entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    print("blob", rel, len(raw))

st, tree = call("POST", f"/repos/{REPO}/git/trees", {"base_tree": base_tree, "tree": entries})
if st != 201:
    print("tree fail", st, tree)
    raise SystemExit(1)
print("tree", tree["sha"][:10])

st, commit = call("POST", f"/repos/{REPO}/git/commits", {
    "message": "3.1.0: split the mode explanation into one line per mode",
    "tree": tree["sha"],
    "parents": [head],
})
if st != 201:
    print("commit fail", st, commit)
    raise SystemExit(1)
print("commit", commit["sha"][:10])

st, upd = call("PATCH", f"/repos/{REPO}/git/refs/heads/main", {"sha": commit["sha"], "force": True})
print("ref update", st)

st, rel = call("GET", f"/repos/{REPO}/releases/tags/v3.1.0")
rid = rel["id"]
for a in rel["assets"]:
    if a["name"] == os.path.basename(ZIP):
        st, _ = call("DELETE", f"/repos/{REPO}/releases/assets/{a['id']}")
        print("delete old asset", st)

raw = open(ZIP, "rb").read()
st, asset = call(
    "POST",
    f"https://uploads.github.com/repos/{REPO}/releases/{rid}/assets?name={os.path.basename(ZIP)}",
    raw=raw,
    ctype="application/zip",
)
print("asset upload", st, (asset or {}).get("name"), (asset or {}).get("size"))
print("release url", rel["html_url"])
