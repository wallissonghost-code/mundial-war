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
assert(#cells==W*H)
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

check(core + r'''
-- Controlled two-island map tests transport independently of continent art.
for i=1,#cells do cells[i]=-1 end
for k in pairs(nations) do nations[k]=nil end
for k in pairs(buildings) do buildings[k]=nil end
for k in pairs(coastal) do coastal[k]=nil end
local origin,target=1910,1980
cells[origin]=0 cells[target]=0
coastal[origin]=true coastal[target]=true
assert(spawn(101,"Sailor",origin))
local n=nations[101]
n.gold=3000 n.troops=2000
assert(not embark(101,target,.5),"Requires port")
local gold=n.gold
coastal[origin]=nil
assert(not build(101,origin,"port"),"Inland port rejected")
coastal[origin]=true
assert(build(101,origin,"port"))
assert(n.gold==gold-900)
assert(not embark(101,target,0/0),"NaN rejected")
assert(not embark(101,target,2),"Invalid percent rejected")
assert(not embark(101,origin,.5),"Own target rejected")
assert(not embark(101,1,.5),"Water target rejected")
local route=seaRoute(101,target)
assert(route and route[#route]==target)
for i=1,#route-1 do
 assert(cells[route[i]]==-1,"Route crosses water only")
 if i>1 then
  local adjacent=false
  for _,j in ipairs(neighbors(route[i-1])) do if j==route[i] then adjacent=true end end
  assert(adjacent,"Continuous route")
 end
end
n.gold=249
assert(not embark(101,target,.5),"Insufficient gold rejected")
n.gold=1000 n.troops=100
assert(not embark(101,target,.5),"Minimum expedition troops")
n.troops=2000
assert(embark(101,target,.5))
assert(n.gold==750 and n.troops==1000,"Deduct once at launch")
assert(not embark(101,target,.5),"One active fleet")
local duration=fleets[101].duration
assert(duration>=3)
for i=1,duration-1 do advanceFleets() assert(cells[target]==0) end
advanceFleets()
assert(cells[target]==101 and n.land==2 and n.troops==1930)
assert(not fleets[101])
-- An inaccessible inland target cannot be reached.
local inland=2050
cells[inland]=0
assert(not seaRoute(101,inland))
-- Failed landing damages a defender without changing land ownership.
cells[target]=202 n.land=1
nations[202]={name="Defender",troops=1000,land=1,gold=0}
n.troops=400 n.gold=1000
assert(embark(101,target,.5))
for i=1,fleets[101].duration do advanceFleets() end
assert(cells[target]==202 and nations[202].troops==900 and n.land==1)
-- If allies' own troops already captured the destination, troops return.
n.troops=1000 n.gold=1000
assert(embark(101,target,.5))
cells[target]=101 n.land=2 nations[202].land=0
for i=1,fleets[101].duration do advanceFleets() end
assert(n.troops==1000)
-- Elimination cancels the fleet.
cells[target]=0 n.land=1 n.gold=1000
assert(embark(101,target,.5))
n.land=0
advanceFleets()
assert(not fleets[101] and cells[target]==0)
print("PASS: coastal ports, sea routes, resources, travel time, landing, failure and elimination")
''', True)


check(core + r'''
local function at(lon,lat)
 local x=math.floor((lon+180)/360*W)+1
 local y=math.floor((85-lat)/150*H)+1
 return cells[(y-1)*W+x]
end
for _,p in ipairs({{-55,-10},{20,0},{135,-25},{-100,40},{25,50},{47,-19}}) do
 assert(at(p[1],p[2])~=-1,"Known land location")
end
for _,p in ipairs({{-30,0},{-140,0},{80,-30}}) do
 assert(at(p[1],p[2])==-1,"Known ocean location")
end
assert(W==240 and H==100 and total>6500 and total<8000)
print("PASS: map dimensions, land area and geographic land/ocean reference points")
''', True)
