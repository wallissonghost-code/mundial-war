-- Gameplay rules on small hand-made maps.
local H = dofile("tests/lua/helpers.lua")
local ok = H.ok

-- Two islands separated by water; island A is 30x10, island B 10x10.
local map = H.asciiMap({
	"..............................................",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.....BBBBBBBBBB.",
	"..............................................",
})
local cfg = H.configWith({ Bots = { Nations = 0, Tribes = 0 }, Spawn = { MinCapitalDistance = 8 } })

local function fresh()
	local world, ctx = H.newWorld({ mapData = map, Config = cfg })
	world:step(0.1, 1) -- waiting -> spawn phase
	return world, ctx
end

local function cell(ctx, x, y) return ctx.Map:index(x, y) end
local Cmd = function(ctx, user, action, a, b, t)
	return ctx.Commands.handle(user, "U" .. user, action, a, b, t or (os.clock() + user * 100))
end

-- Spawn ------------------------------------------------------------------------
do
	local world, ctx = fresh()
	ok(ctx.Match.phase() == "spawn", "spawn phase")
	local ok1, msg = Cmd(ctx, 1, "spawn", cell(ctx, 0, 0))
	ok(not ok1, "water spawn rejected: " .. tostring(msg))
	ok1 = Cmd(ctx, 1, "spawn", cell(ctx, 5, 5))
	ok(ok1, "land spawn works")
	local n = ctx.Nations.forUser(1)
	ok(n.troops == 2500, "player starts with 2500 troops")
	ok(n.land >= 9 and n.land <= 13, "small starting disc, got " .. n.land)
	local ok2, msg2 = Cmd(ctx, 2, "spawn", cell(ctx, 5, 5))
	ok(not ok2, "occupied spawn rejected")
	ok2, msg2 = Cmd(ctx, 2, "spawn", cell(ctx, 9, 5))
	ok(not ok2 and msg2:find("perto"), "spawn too close rejected: " .. tostring(msg2))
	ok(Cmd(ctx, 2, "spawn", cell(ctx, 25, 5)), "far spawn ok")
	ok(not Cmd(ctx, 1, "target", cell(ctx, 15, 5), 0.5), "no expansion during spawn phase")
	print("PASS spawn rules")
end

-- Expansion ----------------------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 3, 5))
	ctx.Match.startPlaying()
	local n = ctx.Nations.forUser(1)
	local before = n.troops
	local okT, msg = Cmd(ctx, 1, "target", cell(ctx, 20, 5), 0.25)
	ok(okT, "neutral order: " .. tostring(msg))
	ok(n.troops == before - math.floor(before * 0.25), "troops leave reserve once")
	local land0 = n.land
	world:step(0.2, 1)
	local land1 = n.land
	ok(land1 > land0 and land1 - land0 < 20, "progressive: a few cells per tick (" .. (land1 - land0) .. ")")
	H.run(world, 3, 1)
	-- territory must stay one connected block (no islands) and have no neutral holes inside
	ctx.Territory.analyze(n.id)
	ok(n.labelSize == n.land, "territory connected: " .. n.labelSize .. "/" .. n.land)
	-- the front moved toward the target (east) rather than west/north at random
	local sumX, count = 0, 0
	for i in pairs(ctx.Territory.owned(n.id)) do
		local x = ctx.Map:xy(i)
		sumX = sumX + x
		count = count + 1
	end
	ok(sumX / count > 5, "expanded toward the click (mean x " .. sumX / count .. ")")
	-- water is never owned
	for i = 1, ctx.Map.N do
		if not ctx.Map.land[i] then ok(ctx.Territory.ownerOf(i) == -1, "water stays unowned") end
	end
	print("PASS organic expansion, connectivity, water")
end

-- No teleport / water barrier --------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 3, 5))
	ctx.Match.startPlaying()
	local okT, msg = Cmd(ctx, 1, "target", cell(ctx, 40, 5), 0.5)
	ok(not okT and msg:find("porto"), "other island needs a port: " .. tostring(msg))
	okT, msg = Cmd(ctx, 1, "target", cell(ctx, 33, 5), 0.5)
	ok(not okT and msg:find("água"), "water target rejected: " .. tostring(msg))
	-- fill island A completely, expansion must stop at the coast
	ctx.Nations.forUser(1).troops = 100000
	for _ = 1, 6 do Cmd(ctx, 1, "target", cell(ctx, 29, 9), 1.0) H.run(world, 5, 1) end
	local n = ctx.Nations.forUser(1)
	ok(n.land == 300, "island A fully conquered (" .. n.land .. ")")
	for x = 36, 45 do ok(ctx.Territory.ownerOf(cell(ctx, x, 5)) == 0, "island B untouched") end
	print("PASS water barrier and anti-teleport")
end

-- PvP ------------------------------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 3, 5))
	Cmd(ctx, 2, "spawn", cell(ctx, 26, 5))
	ctx.Match.startPlaying()
	local a, b = ctx.Nations.forUser(1), ctx.Nations.forUser(2)
	a.troops, b.troops = 20000, 20000
	Cmd(ctx, 1, "target", cell(ctx, 15, 5), 0.5)
	Cmd(ctx, 2, "target", cell(ctx, 15, 5), 0.5)
	H.run(world, 8, 1)
	ok(ctx.Territory.touches(a.id, b.id), "nations meet")
	a.troops = 50000
	local bTroops = b.troops
	local bLand = b.land
	local okT, msg = Cmd(ctx, 1, "target", cell(ctx, 27, 5), 0.5)
	ok(okT, "attack order: " .. tostring(msg))
	ok(ctx.Diplomacy.relation(a.id, b.id) == "war", "attack declares war")
	world:step(0.2, 1)
	local lost = bLand - b.land
	ok(lost > 0 and lost < 20, "front advances progressively (" .. lost .. ")")
	H.run(world, 2, 1)
	ok(b.troops < bTroops, "defender loses troops")
	local orders = ctx.Expansion.ordersOf(a.id)
	ok(#orders == 0 or orders[1].troops < 25000, "attacker spends troops")
	-- alliance stops the war
	ok(Cmd(ctx, 1, "ally", b.id), "alliance requested")
	ok(Cmd(ctx, 2, "ally", a.id), "alliance accepted")
	ok(ctx.Diplomacy.allied(a.id, b.id), "allied")
	ok(#ctx.Expansion.ordersOf(a.id) == 0 or ctx.Expansion.ordersOf(a.id)[1].target ~= b.id, "attack cancelled")
	local okA, msgA = Cmd(ctx, 1, "target", cell(ctx, 27, 5), 0.5)
	ok(not okA and msgA:find("Aliados"), "allies cannot attack: " .. tostring(msgA))
	ok(Cmd(ctx, 1, "breakAlliance", b.id), "break alliance")
	ok(Cmd(ctx, 1, "target", cell(ctx, 27, 5), 0.5), "can attack after breaking")
	print("PASS PvP combat and diplomacy")
end

-- Buildings, ports, naval --------------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 28, 5))
	Cmd(ctx, 2, "spawn", cell(ctx, 40, 5))
	ctx.Match.startPlaying()
	local a = ctx.Nations.forUser(1)
	a.gold, a.troops = 100000, 30000
	ok(not Cmd(ctx, 1, "build", cell(ctx, 28, 5), "port"), "port not inland")
	local okP, msgP = Cmd(ctx, 1, "build", cell(ctx, 30, 5), "port")
	ok(okP, "port on coast: " .. tostring(msgP))
	ok(not Cmd(ctx, 1, "build", cell(ctx, 30, 6), "city"), "spacing enforced")
	ok(Cmd(ctx, 1, "build", cell(ctx, 28, 7), "city"), "city built")
	local cost2 = ctx.Buildings.cost(a.id, "city")
	ok(cost2 > H.Config.Buildings.city.cost, "repeat buildings cost more")
	ok(not Cmd(ctx, 1, "build", cell(ctx, 28, 2), "silo"), "silo requires factory")
	local okN, msgN = Cmd(ctx, 1, "target", cell(ctx, 36, 3), 0.25)
	ok(okN and msgN:find("Frota"), "naval invasion launched: " .. tostring(msgN))
	H.run(world, 4, 1)
	ok(ctx.Territory.ownerOf(cell(ctx, 36, 3)) == a.id, "beachhead taken")
	H.run(world, 3, 1)
	local b = ctx.Nations.forUser(2)
	ok(b.land < 100, "invasion keeps fighting on the island")
	print("PASS buildings, ports and naval landing")
end

-- Anti-cheat ---------------------------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 3, 5))
	ctx.Match.startPlaying()
	ok(not Cmd(ctx, 1, "target", 0 / 0, 0.5), "NaN cell")
	ok(not Cmd(ctx, 1, "target", 1e12, 0.5), "out of range")
	ok(not Cmd(ctx, 1, "target", cell(ctx, 10, 5), 5), "percent > 1")
	ok(not Cmd(ctx, 1, "target", cell(ctx, 10, 5), "x"), "percent type")
	ok(not Cmd(ctx, 1, "build", cell(ctx, 3, 5), "rocket"), "unknown building")
	ok(not Cmd(ctx, 1, "build", cell(ctx, 20, 5), "city"), "build on neutral land")
	ok(not Cmd(ctx, 9, "target", cell(ctx, 10, 5), 0.5), "no nation, no orders")
	ok(not Cmd(ctx, 1, {}, 1, 1), "bad action type")
	-- rate limit: a burst far above the limit is cut
	local accepted = 0
	for _ = 1, 100 do
		local r = ctx.Commands.handle(1, "U1", "cancel", nil, nil, 5000)
		if r then accepted = accepted + 1 end
	end
	ok(accepted <= H.Config.Network.CommandBurst, "rate limited (" .. accepted .. ")")
	print("PASS anti-cheat validation and rate limit")
end

-- Strategic weapons -------------------------------------------------------------------------
do
	local world, ctx = fresh()
	Cmd(ctx, 1, "spawn", cell(ctx, 4, 5))
	Cmd(ctx, 2, "spawn", cell(ctx, 24, 5))
	ctx.Match.startPlaying()
	local a, b = ctx.Nations.forUser(1), ctx.Nations.forUser(2)
	a.gold, b.gold = 1e6, 1e6
	a.troops, b.troops = 50000, 50000
	for _, x in ipairs({ 10, 18 }) do
		Cmd(ctx, 1, "target", cell(ctx, x, 5), 0.2)
		Cmd(ctx, 2, "target", cell(ctx, x + 2, 5), 0.2)
		H.run(world, 4, 1)
	end
	ok(not Cmd(ctx, 1, "nuke", cell(ctx, 24, 5)), "nuke needs a silo")
	ok(Cmd(ctx, 1, "build", cell(ctx, 4, 2), "factory"), "factory")
	local okS, msgS = Cmd(ctx, 1, "build", cell(ctx, 4, 8), "silo")
	ok(okS, "silo after factory: " .. tostring(msgS))
	local bLand, bTroops = b.land, b.troops
	ok(Cmd(ctx, 1, "nuke", cell(ctx, 24, 5)), "nuke launched")
	ok(not Cmd(ctx, 1, "nuke", cell(ctx, 24, 5)), "silo cooldown prevents spam")
	H.run(world, 2, 1)
	ok(b.land < bLand and b.troops < bTroops, "nuke hit: land " .. bLand .. "->" .. b.land)
	ok(ctx.Diplomacy.relation(a.id, b.id) == "war", "nuke means war")
	-- air defence intercepts air strikes
	local adCell
	for i in pairs(ctx.Territory.owned(b.id)) do
		if ctx.Buildings.canBuild(b.id, i, "airdefense") then adCell = i break end
	end
	ok(adCell and Cmd(ctx, 2, "build", adCell, "airdefense"), "air defence built")
	ok(Cmd(ctx, 1, "build", cell(ctx, 7, 5), "airfield"), "airfield")
	local cfg2 = ctx.Config.Buildings.airdefense
	cfg2.intercept = 1.0
	local strikeCell = adCell
	local okA, msgA = Cmd(ctx, 1, "airstrike", strikeCell)
	ok(okA, "air strike launched: " .. tostring(msgA))
	local troopsBefore = b.troops
	H.run(world, 2, 1)
	ok(b.troops >= troopsBefore * 0.99, "air strike intercepted")
	cfg2.intercept = 0.6
	print("PASS nukes, air strikes, air defence and cooldowns")
end

-- Victory and new round ---------------------------------------------------------------------
do
	local small = H.configWith({ Bots = { Nations = 0, Tribes = 0 }, Match = { VictoryPercent = 0.5, EndScreenSeconds = 2, SpawnPhaseSeconds = 1 } })
	local world, ctx = H.newWorld({ mapData = map, Config = small })
	world:step(0.1, 1)
	Cmd(ctx, 1, "spawn", cell(ctx, 4, 5))
	H.run(world, 1.5, 1)
	ok(ctx.Match.isPlaying(), "spawn phase ends by itself")
	local n = ctx.Nations.forUser(1)
	n.troops = 1e6
	Cmd(ctx, 1, "target", cell(ctx, 29, 9), 0.5)
	for _ = 1, 100 do
		world:step(0.1, 1)
		if ctx.Match.phase() == "ended" then break end
	end
	ok(ctx.Match.phase() == "ended" and ctx.Match.winner().id == n.id, "victory at the configured share (" .. ctx.Match.phase() .. ", land " .. n.land .. "/" .. ctx.Map.landCount .. ")")
	local round = ctx.Match.round()
	H.run(world, 2.5, 1)
	ok(ctx.Match.round() == round + 1 and ctx.Match.phase() == "spawn", "new round starts")
	ok(ctx.Nations.forUser(1) == nil, "fresh world after the round")
	print("PASS victory and round reset")
end

-- A neutral click behind another nation is refused (no jumping over territory) ---------------
do
	local corridor = H.asciiMap({
		"..............................",
		".AAAAAAAAAAAAAAAAAAAAAAAAAAAA.",
		".AAAAAAAAAAAAAAAAAAAAAAAAAAAA.",
		".AAAAAAAAAAAAAAAAAAAAAAAAAAAA.",
		"..............................",
	})
	local world, ctx = H.newWorld({ mapData = corridor, Config = cfg })
	world:step(0.1, 1)
	Cmd(ctx, 1, "spawn", ctx.Map:index(2, 2))
	Cmd(ctx, 2, "spawn", ctx.Map:index(12, 2))
	ctx.Match.startPlaying()
	local okT, msg = Cmd(ctx, 1, "target", ctx.Map:index(24, 2), 0.5)
	ok(not okT and msg:find("bloqueado"), "blocked by another nation: " .. tostring(msg))
	ok(Cmd(ctx, 1, "target", ctx.Map:index(6, 2), 0.5), "free land on our side still works")
	print("PASS land route required")
end

-- Levels, defence boats and new bombs ---------------------------------------------------------
do
	local fast = H.configWith({ Bots = { Nations = 0, Tribes = 0 }, Spawn = { MinCapitalDistance = 8 }, Network = { CommandsPerSecond = 1000, CommandBurst = 1000 } })
	local world, ctx = H.newWorld({ mapData = map, Config = fast })
	world:step(0.1, 1)
	Cmd(ctx, 1, "spawn", cell(ctx, 28, 5))
	Cmd(ctx, 2, "spawn", cell(ctx, 40, 5))
	ctx.Match.startPlaying()
	local a, b = ctx.Nations.forUser(1), ctx.Nations.forUser(2)
	a.gold, b.gold, a.troops, b.troops = 1e6, 1e6, 50000, 50000
	local S = H.BuildingStats
	-- upgrades
	ok(Cmd(ctx, 1, "build", cell(ctx, 27, 4), "bunker"), "bunker")
	local bunker = ctx.Buildings.at(cell(ctx, 27, 4))
	local r1 = ctx.Buildings.stat(bunker, "radius")
	local gold0 = a.gold
	ok(Cmd(ctx, 1, "upgrade", cell(ctx, 27, 4)), "upgrade to level 2")
	ok(bunker.level == 2 and ctx.Buildings.stat(bunker, "radius") > r1, "level raises reach")
	ok(gold0 - a.gold == S.upgradeCost(ctx.Config, "bunker", 1), "upgrade cost charged")
	for _ = 1, 3 do Cmd(ctx, 1, "upgrade", cell(ctx, 27, 4)) end
	ok(bunker.level == ctx.Config.MaxBuildingLevel, "max level")
	ok(not Cmd(ctx, 1, "upgrade", cell(ctx, 27, 4)), "no upgrade past max")
	ok(not Cmd(ctx, 2, "upgrade", cell(ctx, 27, 4)), "cannot upgrade someone else's")
	local lines = S.lines(ctx.Config, "bunker", 5)
	ok(lines[1]:find("Alcance"), "description lists the reach: " .. lines[1])
	-- city levels feed the economy
	ok(Cmd(ctx, 1, "build", cell(ctx, 28, 7), "city"), "city")
	local g1 = ctx.Buildings.totals(a.id).growth
	Cmd(ctx, 1, "upgrade", cell(ctx, 28, 7))
	ok(ctx.Buildings.totals(a.id).growth > g1, "upgraded city grows faster")
	-- defence boats
	ok(Cmd(ctx, 1, "build", cell(ctx, 30, 5), "port"), "port A")
	for x = 36, 39 do ctx.Territory.setOwner(cell(ctx, x, 5), b.id) end
	ok(Cmd(ctx, 2, "build", cell(ctx, 36, 5), "port"), "port B")
	ok(Cmd(ctx, 1, "warship", cell(ctx, 30, 5)), "boat A")
	ok(Cmd(ctx, 2, "warship", cell(ctx, 36, 5)), "boat B")
	ok(Cmd(ctx, 1, "warship", cell(ctx, 30, 5)), "second boat A")
	ok(not Cmd(ctx, 1, "warship", cell(ctx, 30, 5)), "port limit")
	local boats = ctx.Naval.boats()
	ok(#boats == 3, "three boats")
	ok(not Cmd(ctx, 1, "patrol", boats[1].id, cell(ctx, 10, 5)), "patrol on land refused")
	ok(not Cmd(ctx, 2, "patrol", boats[1].id, cell(ctx, 33, 5)), "cannot command another nation's boat")
	ok(Cmd(ctx, 1, "patrol", boats[1].id, cell(ctx, 33, 6)), "patrol set")
	-- at war, boats fight and raid gold from the enemy port
	ctx.Diplomacy.declareWar(a.id, b.id)
	local bGold = b.gold
	H.run(world, 12, 1)
	local alive = {}
	for _, boat in ipairs(ctx.Naval.boats()) do alive[boat.nation] = (alive[boat.nation] or 0) + 1 end
	ok((alive[b.id] or 0) == 0 and (alive[a.id] or 0) >= 1, "two boats sink one")
	ok(b.gold < bGold + 12 * 100, "enemy port raided")
	-- bombs
	local function spot(nation, kind)
		for i in pairs(ctx.Territory.owned(nation.id)) do
			if ctx.Buildings.canBuild(nation.id, i, kind) then return i end
		end
		ctx.Nations.get(nation.id).troops = 1e6
	end
	a.troops = 1e6
	Cmd(ctx, 1, "target", cell(ctx, 12, 5), 0.3)
	H.run(world, 4, 1)
	ok(not Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "cluster"), "cluster needs an air base")
	ok(Cmd(ctx, 1, "build", spot(a, "airfield"), "airfield"), "air base")
	local troops = b.troops
	ok(Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "cluster"), "cluster launched")
	H.run(world, 1.5, 1)
	ok(b.troops < troops, "cluster kills troops")
	ok(Cmd(ctx, 1, "build", spot(a, "factory"), "factory"), "factory")
	local siloCell = spot(a, "silo")
	local okSilo, msgSilo = Cmd(ctx, 1, "build", siloCell, "silo")
	ok(okSilo, "silo: " .. tostring(msgSilo) .. " " .. tostring(siloCell))
	ok(not Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "hydrogen"), "hydrogen needs silo level 3")
	local bCity = spot(b, "city")
	ok(Cmd(ctx, 2, "build", bCity, "city"), "enemy city")
	ok(Cmd(ctx, 1, "weapon", bCity, "emp"), "EMP launched")
	H.run(world, 1.5, 1)
	local hit = ctx.Buildings.at(bCity)
	ok(hit and not hit.active, "EMP switches buildings off")
	H.run(world, 46, 1)
	ok(hit.active, "and they come back")
	Cmd(ctx, 1, "upgrade", siloCell) Cmd(ctx, 1, "upgrade", siloCell)
	H.run(world, 15, 1)
	local okH, msgH = Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "hydrogen")
	ok(okH, "hydrogen at silo level 3: " .. tostring(msgH))
	ok(not Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "rocket"), "unknown weapon")
	print("PASS building levels, defence boats and new bombs")
end
