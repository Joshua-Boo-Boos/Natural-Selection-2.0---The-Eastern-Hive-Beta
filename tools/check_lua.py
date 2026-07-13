"""Offline Lua 5.1 syntax check for NS2 mod files. Usage: python tools/check_lua.py file1.lua [file2.lua ...]"""
import sys
from luaparser import ast

fail = False
for path in sys.argv[1:]:
    src = open(path, encoding="utf-8", errors="replace").read()
    try:
        ast.parse(src)
        print("OK  ", path)
    except Exception as e:
        print("FAIL", path, "--", e)
        fail = True
sys.exit(1 if fail else 0)
