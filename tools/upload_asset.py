import json, os, socket, ssl, sys, time, urllib.request, urllib.error

TEMP = os.environ.get("TEMP", ".")
TOKEN = os.environ.get("GH_TOKEN", "").strip() or open(os.path.join(TEMP, "ghtok.txt"), "r", encoding="utf-8").read().strip()
REPO = "Woeful001/pbz-weapon-swap"
RID = 433583869
ZIP = r"D:\Projects\pbz-weapon-swap\dist\PBZWeaponSwap-3.1.0.zip"
NAME = os.path.basename(ZIP)
PIN = os.environ.get("PIN_IP", "").strip()

if PIN:
    _orig = socket.getaddrinfo

    def patched(host, port, *a, **kw):
        if host and "uploads.github.com" in str(host):
            host = PIN
        return _orig(host, port, *a, **kw)

    socket.getaddrinfo = patched
    print("pinned uploads.github.com ->", PIN)

# 先看 release 现有资产
req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/{RID}", headers={
    "Authorization": "Bearer " + TOKEN, "User-Agent": "pbz", "Accept": "application/vnd.github+json"})
rel = json.load(urllib.request.urlopen(req, timeout=60))
for a in rel["assets"]:
    if a["name"] == NAME:
        d = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/assets/{a['id']}", method="DELETE",
                                   headers={"Authorization": "Bearer " + TOKEN, "User-Agent": "pbz"})
        print("delete existing", a["id"], urllib.request.urlopen(d, timeout=60).status)

raw = open(ZIP, "rb").read()
url = f"https://uploads.github.com/repos/{REPO}/releases/{RID}/assets?name={NAME}"
last = None
for attempt in range(5):
    req = urllib.request.Request(url, data=raw, method="POST")
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "application/zip")
    req.add_header("User-Agent", "pbz")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            a = json.loads(r.read())
            print("uploaded", r.status, a["name"], a["size"], a["browser_download_url"])
            break
    except Exception as e:
        last = e
        print("retry", attempt + 1, type(e).__name__, e)
        time.sleep(2)
else:
    raise SystemExit(f"upload failed: {last}")
