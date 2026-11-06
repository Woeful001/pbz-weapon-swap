"""Commit local changes straight to GitHub through the Git Data API.

GitHub's git endpoint (github.com:443) is often blocked here while api.github.com
still answers, so this recreates the commit on the server instead of pushing:

    python tools/api_commit.py "commit message" [version]

It reads the token from GH_TOKEN or %TEMP%\\ghtok.txt, takes HEAD's tree as the base,
uploads every file that differs from origin/main as a blob, commits, and fast-forwards
refs/heads/main. Afterwards tools/make_release.py can publish the zip.
"""
import base64
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
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    sys.exit("no GH_TOKEN / %TEMP%\\ghtok.txt")


TOK = token()


def call(method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOK)
    req.add_header("Accept", "application/vnd.github+json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        sys.exit("%s %s -> %s %s" % (method, path, e.code, e.read().decode("utf-8", "replace")[:400]))


def git(*args):
    return subprocess.check_output(["git"] + list(args), text=True).strip()


def main():
    msg = sys.argv[1] if len(sys.argv) > 1 else "update"
    head = git("rev-parse", "HEAD")
    base = call("GET", "/repos/%s/%s/git/ref/heads/main" % (OWNER, REPO))
    base_sha = base["object"]["sha"]
    base_commit = call("GET", "/repos/%s/%s/git/commits/%s" % (OWNER, REPO, base_sha))

    # 服务端提交在本地没有对象，只能拿“上次推送时的本地 HEAD”来算差异
    state_path = os.path.join(git("rev-parse", "--absolute-git-dir"), "api_commit_state.json")
    prev_local = None
    if os.path.exists(state_path):
        with open(state_path, encoding="utf-8") as f:
            st = json.load(f)
        if st.get("remote") == base_sha:
            prev_local = st.get("local")
    diff_base = prev_local if prev_local and subprocess.call(
        ["git", "cat-file", "-e", prev_local + "^{commit}"], stderr=subprocess.DEVNULL) == 0 else base_sha

    changed = git("diff", "--name-only", diff_base, head).splitlines()
    if not changed:
        sys.exit("nothing to commit")
    print("changed:", ", ".join(changed))

    entries = {}
    for path in changed:
        full = os.path.join(git("rev-parse", "--show-toplevel"), path)
        if not os.path.exists(full):
            entries[path] = None
            continue
        with open(full, "rb") as f:
            content = f.read()
        blob = call("POST", "/repos/%s/%s/git/blobs" % (OWNER, REPO),
                    {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        entries[path] = blob["sha"]
        print("blob %s %s" % (blob["sha"][:10], path))

    tree = call("POST", "/repos/%s/%s/git/trees" % (OWNER, REPO),
                {"base_tree": base_commit["tree"]["sha"],
                 "tree": [{"path": p, "mode": "100644", "type": "blob", "sha": s}
                          for p, s in entries.items() if s]})
    author = {"name": "woeful001", "email": "2123982910@qq.com",
              "date": git("show", "-s", "--format=%cI", head)}
    commit = call("POST", "/repos/%s/%s/git/commits" % (OWNER, REPO),
                  {"message": msg, "tree": tree["sha"], "parents": [base_sha],
                   "author": author, "committer": author})
    call("PATCH", "/repos/%s/%s/git/refs/heads/main" % (OWNER, REPO),
         {"sha": commit["sha"], "force": False})
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump({"local": head, "remote": commit["sha"]}, f)
    print("pushed %s -> %s" % (base_sha[:10], commit["sha"]))
    print("https://github.com/%s/%s/commit/%s" % (OWNER, REPO, commit["sha"]))


if __name__ == "__main__":
    main()
