"""Run Lua test files with the system Lua 5.4 library (no lua binary needed).

Usage: python tests/run_lua.py tests/lua/test_*.lua
Also syntax-checks every .lua file under src/ (Lua 5.4 parser; the code avoids
Luau-only syntax so both parsers accept it).
"""
import ctypes, sys, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lib = ctypes.CDLL("liblua5.4.so.0")
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]


def syntax(path):
    state = lib.luaL_newstate()
    try:
        if lib.luaL_loadfilex(state, str(path).encode(), None):
            return lib.lua_tolstring(state, -1, None).decode()
    finally:
        lib.lua_close(state)
    return None


def run(path):
    state = lib.luaL_newstate()
    lib.luaL_openlibs(state)
    try:
        code = lib.luaL_loadfilex(state, str(path).encode(), None)
        if not code:
            code = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if code:
            return lib.lua_tolstring(state, -1, None).decode()
    finally:
        lib.lua_close(state)
    return None


def main():
    os.chdir(ROOT)
    failed = False
    for f in sorted((ROOT / "src").rglob("*.lua")):
        err = syntax(f)
        if err:
            print("SYNTAX FAIL", err)
            failed = True
    print("syntax checked", len(list((ROOT / "src").rglob("*.lua"))), "files")
    for arg in sys.argv[1:]:
        sys.stdout.flush()
        err = run(Path(arg))
        sys.stdout.flush()
        if err:
            print("FAIL", arg, "\n ", err)
            failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
