"""Core regression tests using system Lua 5.4; Roblox engine testing is still required."""
import ctypes
from pathlib import Path
lib = ctypes.CDLL("liblua5.4.so.0")
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
def check(code, execute=False):
    state = lib.luaL_newstate()
    lib.luaL_openlibs(state)
    try:
        result = lib.luaL_loadstring(state, code.encode())
        if not result and execute:
            result = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if result:
            raise AssertionError(lib.lua_tolstring(state, -1, None).decode())
    finally:
        lib.lua_close(state)
root = Path(__file__).resolve().parents[1]
for file in (root / "src").glob("*.lua"):
    check(file.read_text())
    print("Syntax OK:", file.name)
source = (root / "src/server.server.lua").read_text()
core = source[source.index("local W,H"):source.index("local winner=nil")]
check(core + r'''
assert(#cells==5000)
local bots=0
for _,n in pairs(nations) do bots=bots+1 end
assert(bots==6)
local seed
for i,owner in ipairs(cells) do
 if owner==0 and #neighbors(i)==4 then
  local free=true
  for _,j in ipairs(neighbors(i)) do if cells[j]~=0 then free=false end end
  if free then seed=i break end
 end
end
assert(spawn(123,"Test",seed))
assert(not spawn(456,"Overlap",seed))
local n=nations[123]
assert(not build(123,seed,"city"),"Cannot spend missing gold")
n.gold=500
assert(not build(123,seed,"unknown"))
assert(not build(123,seed+1,"city"),"Must own land")
assert(build(123,seed,"city"))
assert(n.gold==0)
n.gold=1000
assert(not build(123,seed,"factory"),"One building per cell")
assert(n.gold==1000)
local t,cap,g=bonuses(123)
assert(t==30 and cap==2000 and g==0)
local previous=n.troops
step(123,n)
assert(n.troops==previous+117)
n.target=0
previous=n.troops
step(123,n)
assert(n.land>1 and n.troops<previous+117)
local free=frontier(123,0)[1]
assert(free)
cells[free]=456
nations[456]={name="Enemy",troops=0,gold=1000,land=1,ratio=.25}
assert(build(456,free,"factory"))
local beforeGold=nations[456].gold
step(456,nations[456])
assert(nations[456].gold==beforeGold+41)
n.target=456 n.troops=10000
step(123,n)
assert(cells[free]==123 and nations[456].land==0)
local _,_,income=bonuses(123)
assert(income==35,"Captured factory must transfer income")
local b=frontier(123,0)[1]
cells[b]=789
nations[789]={name="Bunker",troops=0,gold=400,land=1,ratio=.25}
assert(build(789,b,"bunker"))
n.troops=100 n.ratio=.1 n.target=789
step(123,n)
assert(cells[b]==789,"Insufficient attack budget")
n.troops=1000 n.ratio=1
local growth=85+n.land*2+30
step(123,n)
assert(cells[b]==123 and n.troops==1000+growth-70,"Bunker doubles conquest cost")
for round=1,50 do
 for id,m in pairs(nations) do m.target=0 step(id,m) end
end
local counts={}
for _,id in ipairs(cells) do
 if id~=0 and id~=-1 then counts[id]=(counts[id] or 0)+1 end
end
for id,m in pairs(nations) do
 assert(m.land==(counts[id] or 0),"Land accounting")
 assert(m.troops>=0 and m.gold>=0,"No negative balances")
end
print("PASS: spawn, expansion, costs, city, factory, bunker, capture and land accounting")
''', True)
