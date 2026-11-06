import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text(encoding="utf-8")
try:
    from luaparser import ast
except ImportError:
    print("luaparser not installed")
    raise SystemExit(2)
try:
    ast.parse(src)
    print("syntax OK: %s (%d lines, %d bytes)" % (p.name, src.count("\n"), len(src.encode("utf-8"))))
except Exception as e:
    print("syntax FAIL: %s" % e)
    raise SystemExit(1)
