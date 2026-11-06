"""Delete a GitHub release (and its tag) for this repo.

Usage:
    python tools/delete_release.py 4.5.1

Token comes from GH_TOKEN, %TEMP%\\ghtok.txt, or the Windows credential manager
(the same classic PAT git itself uses).
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

OWNER = "Woeful001"
REPO = "pbz-weapon-swap"
API = "https://api.github.com"


def token():
    tok = os.environ.get("GH_TOKEN", "").strip()
    if tok:
        return tok
    p = os.path.join(os.environ.get("TEMP", ""), "ghtok.txt")
    if p and os.path.exists(p):
        with open(p, "r", encoding="utf-8") as f:
            v = f.read().strip()
        if v:
            return v
    out = subprocess.run(
        ["git", "-c", "credential.helper=manager", "credential", "fill"],
        input="protocol=https\nhost=github.com\nusername=Woeful001\n\n",
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1].strip()
    sys.exit("no token")


def call(url, tok, method="GET", data=None, ctype="application/json"):
    body = json.dumps(data).encode() if (data is not None and ctype == "application/json") else data
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": "Bearer " + tok,
        "User-Agent": "pbz-weapon-swap",
        "Accept": "application/vnd.github+json",
        "Content-Type": ctype,
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        if not raw:
            return r.status, None
        return r.status, raw


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python tools/delete_release.py <version>")
    ver = sys.argv[1].lstrip("v")
    tag = "v" + ver
    tok = token()

    try:
        st, rel = call("%s/repos/%s/%s/releases/tags/%s" % (API, OWNER, REPO, tag), tok)
        rel = json.loads(rel)
        print("found release:", rel["html_url"], "id", rel["id"])
        call("%s/repos/%s/%s/releases/%d" % (API, OWNER, REPO, rel["id"]), tok, "DELETE")
        print("deleted release", tag)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            sys.exit("release lookup failed %s %s" % (e.code, e.read().decode()[:300]))
        print("no release for", tag)

    try:
        call("%s/repos/%s/%s/git/refs/tags/%s" % (API, OWNER, REPO, tag), tok, "DELETE")
        print("deleted tag", tag)
    except urllib.error.HTTPError as e:
        if e.code != 404 and e.code != 422:
            sys.exit("tag delete failed %s %s" % (e.code, e.read().decode()[:300]))
        print("no tag", tag)


if __name__ == "__main__":
    main()
