-- Game modes (vote, Conquista Extrema), cargo ships, air bridge, fire bomb, End of an Era.
local H = dofile("tests/lua/helpers.lua")
local ok = H.ok

local fast = { Network = { CommandsPerSecond = 1000, CommandBurst = 1000 } }
local clock = 0
local function Cmd(ctx, user, action, a, b, c)
	clock = clock + 0.01
	return ctx.Commands.handle(user, "U" .. user, action, a, b, clock, c)
end

-- Vote on the real map --------------------------------------------------------------------
do
	local cfg = H.configWith({ Network = fast.Network })
	local world, ctx = H.newWorld({ Config = cfg, vote = 10 })
	world:step(0.1, 1)
	ok(ctx.Match.phase() == "vote", "rounds open with a vote")
	ok(not Cmd(ctx, 1, "vote", "chess"), "unknown mode refused")
	ok(Cmd(ctx, 1, "vote", "extreme"), "vote accepted")
	world:step(0.1, 1)
	ok(ctx.Match.phase() == "spawn" and ctx.mode == "extreme", "vote closes early once everyone voted")
	local count, owned = 0, 0
	for _, n in pairs(ctx.Nations.all()) do count = count + 1 owned = owned + n.land end
	ok(count > 120, "every sizeable country is a nation (" .. count .. ")")
	ok(owned / ctx.Map.landCount > 0.95, "the world starts fully occupied")
	-- take over Brazil
	local brazil = H.cellOfCountry(ctx, "BRA")
	local okT, msg = Cmd(ctx, 1, "spawn", brazil + 3)
	ok(okT and msg:find("Brasil"), "player governs Brazil: " .. tostring(msg))
	local me = ctx.Nations.forUser(1)
	ok(me.kind == "player" and me.land > 2000, "the whole country is yours")
	ok(not Cmd(ctx, 2, "spawn", brazil), "a country has only one ruler")
	ctx.Match.startPlaying()
	-- world keeps running with ~180 AI countries
	local t0 = os.clock()
	H.run(world, 60, 1)
	print(string.format("  Conquista Extrema: 60 s with %d countries in %.2f s CPU", count, os.clock() - t0))
	ctx.Nations.returnToAI(me.id)
	ok(me.kind == "bot" and me.alive and not me.name:find("%("), "a player who leaves hands the country back to the AI")
	print("PASS mode vote and country takeover")
end

-- Small two-island world in Conquista Extrema -----------------------------------------------------
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
map.Countries[1].capital = 5 * 46 + 5 + 1
map.Countries[2].capital = 5 * 46 + 40 + 1

local function extreme()
	local cfg = H.configWith({ Network = fast.Network, Bots = { ThinkInterval = 1e9, ExtremeThinkInterval = 1e9 }, Match = { VictoryPercent = 0.99 } })
	local world, ctx = H.newWorld({ mapData = map, Config = cfg, mode = "extreme" })
	world:step(0.1, 1)
	ok(Cmd(ctx, 1, "spawn", ctx.Map:index(10, 5)), "take country A")
	ok(Cmd(ctx, 2, "spawn", ctx.Map:index(40, 5)), "take country B")
	ctx.Match.startPlaying()
	local a, b = ctx.Nations.forUser(1), ctx.Nations.forUser(2)
	a.gold, b.gold, a.oil, b.oil = 1e6, 1e6, 1e5, 1e5
	return world, ctx, a, b
end
local function cell(ctx, x, y) return ctx.Map:index(x, y) end

do
	local world, ctx, a, b = extreme()
	ok(a.land == 300 and b.land == 100, "countries start whole")
	-- extreme-only buildings
	ok(Cmd(ctx, 1, "build", cell(ctx, 10, 3), "oilwell"), "oil well")
	local oil = a.oil
	H.run(world, 2, 1)
	ok(a.oil > oil, "oil flows")
	-- walls and trenches make attacks dearer for the attacker / cheaper for the defender
	local probe = cell(ctx, 30, 5)
	local before = ctx.Combat.cellCost(b.id, probe, 1000)
	ok(Cmd(ctx, 1, "build", cell(ctx, 29, 5), "wall"), "wall")
	local after = ctx.Combat.cellCost(b.id, probe, 1000)
	ok(after > before * 2, "wall triples the cost near it")
	local _, lossBefore = ctx.Combat.cellCost(b.id, cell(ctx, 30, 9), 1000)
	ok(Cmd(ctx, 1, "build", cell(ctx, 28, 9), "trench"), "trench")
	local _, lossAfter = ctx.Combat.cellCost(b.id, cell(ctx, 30, 9), 1000)
	ok(lossAfter < lossBefore, "trench shelters the defender")
	ok(Cmd(ctx, 1, "build", cell(ctx, 30, 2), "antinaval"), "anti-naval on the coast")
	ok(not Cmd(ctx, 1, "build", cell(ctx, 15, 5), "antinaval"), "anti-naval needs the coast")
	-- air bridge: troops fly over the water and land on the other island
	ok(Cmd(ctx, 1, "build", cell(ctx, 20, 5), "airfield"), "air base")
	a.troops = 50000
	local okA, msgA = Cmd(ctx, 1, "weapon", cell(ctx, 41, 7), "airlift", 0.2)
	ok(okA, "air bridge launched: " .. tostring(msgA))
	H.run(world, 2, 1)
	ok(ctx.Territory.ownerOf(cell(ctx, 41, 7)) == a.id, "paratroopers took the landing cell")
	Cmd(ctx, 1, "cancel")
	-- fire bomb spreads and burns
	local cityCell
	for _, c in ipairs({ cell(ctx, 42, 3), cell(ctx, 43, 4), cell(ctx, 42, 5), cell(ctx, 44, 3), cell(ctx, 40, 2) }) do
		if ctx.Buildings.canBuild(b.id, c, "city") then cityCell = c break end
	end
	ok(cityCell and Cmd(ctx, 2, "build", cityCell, "city"), "city in B")
	H.run(world, 20, 1) -- the air base reloads after the air bridge
	b.troops = 20000
	local troops = b.troops
	local okF, msgF = Cmd(ctx, 1, "weapon", cityCell, "firebomb")
	ok(okF, "fire bomb launched: " .. tostring(msgF))
	H.run(world, 3, 1)
	local fires = ctx.Strategic.fires()
	ok(#fires == 1, "fire burning")
	local r0 = fires[1].radius
	H.run(world, 4, 1)
	ok(fires[1].radius > r0, "fire spreads slowly")
	ok(b.troops < troops, "fire burns troops")
	ok(ctx.Buildings.at(cityCell) == nil, "fire destroyed the city")
	print("PASS extreme buildings, oil, air bridge and fire bomb")
end

-- Flak stops aircraft, not missiles; nothing stops the End of an Era ---------------------------------
do
	local world, ctx, a, b = extreme()
	ok(Cmd(ctx, 2, "build", cell(ctx, 40, 5), "flak"), "flak")
	ctx.Config.Buildings.flak.intercept = 1
	ok(Cmd(ctx, 1, "build", cell(ctx, 25, 5), "airfield"), "air base")
	a.troops = 50000
	local bTroops = b.troops
	ok(Cmd(ctx, 1, "weapon", cell(ctx, 41, 5), "airstrike"), "air strike")
	H.run(world, 1.5, 1)
	ok(b.troops >= bTroops * 0.999, "flak shot the plane down")
	ctx.Config.Buildings.flak.intercept = 0.85
	ok(Cmd(ctx, 2, "build", cell(ctx, 41, 8), "airdefense"), "air defence")
	ctx.Config.Buildings.airdefense.intercept = 1
	ok(Cmd(ctx, 1, "build", cell(ctx, 10, 3), "factory"), "factory")
	ok(Cmd(ctx, 1, "build", cell(ctx, 10, 7), "silo"), "silo")
	ok(not Cmd(ctx, 1, "weapon", cell(ctx, 41, 5), "endofera"), "End of an Era needs silo level 5")
	for _ = 1, 4 do Cmd(ctx, 1, "upgrade", cell(ctx, 10, 7)) end
	b.troops = 30000
	local land = b.land
	local okE, msgE = Cmd(ctx, 1, "weapon", cell(ctx, 41, 5), "endofera")
	ok(okE, "End of an Era launched: " .. tostring(msgE))
	H.run(world, 3, 1)
	ok(b.troops < 30000 * 0.7, "it hits even with perfect air defence")
	ok(#ctx.Strategic.fires() >= 1, "and leaves fire")
	ctx.Config.Buildings.airdefense.intercept = 0.6
	print("PASS flak, air defence and the End of an Era")
end

-- Cargo ships (both modes) ----------------------------------------------------------------------
do
	local world, ctx, a, b = extreme()
	local N = ctx.Config.Naval
	ok(Cmd(ctx, 1, "build", cell(ctx, 30, 6), "port"), "port A")
	ok(Cmd(ctx, 2, "build", cell(ctx, 36, 6), "port"), "port B")
	H.run(world, N.CargoInterval + 2, 1)
	ok(#ctx.Naval.cargos() >= 1, "ports send cargo ships")
	local gold = a.gold
	H.run(world, 20, 1)
	ok(a.gold > gold, "cargo comes home with gold")
	-- at war, a defence boat captures enemy cargo
	ctx.Diplomacy.declareWar(a.id, b.id)
	ok(Cmd(ctx, 2, "warship", cell(ctx, 36, 6)), "B boat")
	local bBoat = ctx.Naval.boats()[1]
	bBoat.x, bBoat.y = 32.5, 6.5
	bBoat.center = cell(ctx, 32, 6)
	local bGold = b.gold
	local captured = false
	for _ = 1, 60 do
		H.run(world, 1, 1)
		if b.gold - bGold >= N.CargoValue then captured = true break end
	end
	ok(captured, "enemy boat captured a cargo ship worth gold")
	print("PASS cargo ships and captures")
end

-- Mode-only content is refused in the classic mode -------------------------------------------------
do
	local cfg = H.configWith({ Network = fast.Network, Bots = { Nations = 0, Tribes = 0 }, Spawn = { MinCapitalDistance = 8 } })
	local world, ctx = H.newWorld({ mapData = map, Config = cfg })
	world:step(0.1, 1)
	ok(ctx.mode == "classic", "classic by default")
	Cmd(ctx, 1, "spawn", cell(ctx, 5, 5))
	ctx.Match.startPlaying()
	ctx.Nations.forUser(1).gold = 1e6
	local okW, msgW = Cmd(ctx, 1, "build", cell(ctx, 5, 6), "wall")
	ok(not okW and msgW:find("Conquista Extrema"), "walls are extreme-only")
	ok(not Cmd(ctx, 1, "weapon", cell(ctx, 40, 5), "firebomb"), "fire bomb is extreme-only")
	print("PASS mode restrictions")
end
