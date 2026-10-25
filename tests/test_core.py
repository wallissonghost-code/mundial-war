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

import json
m=json.loads((root/'data/reference-mask.json').read_text())
def core(rows):
    return f"local W,H={len(rows[0])},{len(rows)}\nlocal landRows={{"+','.join(json.dumps(r) for r in rows)+"}\n"+(root/'engine/core.lua').read_text()
check(core(['1'*40]*20)+r'''
assert(spawn(101,"Test",401))
assert(not spawn(202,"Overlap",401))
local n=nations[101]
assert(order(101,431,.25))
local before=n.troops
step(101,n)
assert(n.land>1 and n.troops==before+87*.25)
assert(n.deployed==625-(n.land-1)*5)
for k=1,39 do step(101,n) end
assert(n.land==126,"Expansion should advance visibly")
n.target=nil n.gold=500
assert(build(101,401,"city"))
assert(n.gold==0 and not build(101,401,"factory"))
local t,c,g=bonuses(101) assert(t==30 and c==2000 and g==0)
n.troops=1e8 step(101,n) assert(n.troops==5000+n.land*250+2000)
local counts={} for _,id in ipairs(cells) do counts[id]=(counts[id] or 0)+1 end
assert(counts[101]==n.land)
resetRound()
assert(spawn(101,"Test",401) and spawn(-2,"Enemy",402))
claim(-2,441) nations[-2].troops=0 nations[-2].gold=400
assert(build(-2,402,"bunker"))
n=nations[101] n.troops=30
assert(not order(101,402,1))
assert(diplomacy(101,-2,"war") and order(101,402,1))
step(101,n)
assert(cells[402]==-2 and cells[441]==101,"Expensive candidate must not block cheap candidate")
assert(defense(402)==50)
n.troops=3000
assert(diplomacy(101,-2,"truce"))
assert(n.target==nil and cells[441]==101)
assert(not diplomacy(101,-2,"war") and not order(101,402,1))
clock=91 assert(relation(101,-2)=="neutral")
assert(diplomacy(101,-2,"ally"))
assert(not order(101,402,1))
assert(diplomacy(-2,101,"truce"))
assert(offers[101] and diplomacy(101,-2,"accept"))
assert(not offers[101])
resetRound() assert(not started and next(nations)==nil)
print("PASS: Lua expansion, affordable frontier, buildings, capacity, land accounting, diplomacy, reset")
''',True)
check(core(['000000000000','011000001100','011000001100','000000000000','000000000000'])+r'''
assert(spawn(101,"Sailor",14))
local n=nations[101] n.gold=3000 n.troops=2000
assert(not embark(101,21,.5))
assert(build(101,14,"port"))
assert(n.gold==2100)
assert(not embark(101,1,.5) and not embark(101,21,0/0))
assert(embark(101,21,.5))
assert(n.gold==1850 and n.troops==1000)
local f=fleets[101]
for k=1,#f.route-1 do
 assert(cells[f.route[k]]==-1)
 local adjacent=false
 for _,j in ipairs(adj[f.route[k]]) do if j==f.route[k+1] then adjacent=true end end
 assert(adjacent)
end
advanceFleets(f.duration-.25) assert(cells[21]==0)
advanceFleets(.25) assert(cells[21]==101 and n.troops==1945 and not fleets[101])
assert(spawn(-2,"Enemy",22)) nations[-2].troops=0
assert(diplomacy(101,-2,"war") and embark(101,22,.5))
assert(diplomacy(101,-2,"truce"))
advanceFleets(100) assert(cells[22]==-2 and n.troops==1945)
print("PASS: Lua ports, water routes, invalid input, travel time, landing, peace during naval travel")
''',True)
check(core(m['rows'])+r'''
assert(W==320 and H==180 and total==22043)
assert(next(nations)==nil) tick(.25) assert(next(nations)==nil)
assert(spawn(101,"Test",90*W+167)) seedBots() started=true
assert(order(101,frontier(101,0)[1],.25))
for k=1,240 do tick(.25) end
local counts={} for _,id in ipairs(cells) do counts[id]=(counts[id] or 0)+1 end
for id,n in pairs(nations) do assert(n.land==(counts[id] or 0) and n.troops>=0 and n.gold>=0) end
assert(nations[101].land>=126)
print("PASS: Lua real map 60-second simulation and accounting")
''',True)

check(core(['1'*40]*20)+r'''
assert(spawn(101,"Reserve",401)) local n=nations[101]
assert(order(101,402,.25)) assert(n.troops==1875 and n.deployed==625)
step(101,n) local before=n.troops+n.deployed
finish(n,"Parado") assert(n.troops==before and n.deployed==0)
finish(n,"Parado") assert(n.troops==before)
print("PASS: Lua expedition launch debit and refund exactly once")
''',True)
