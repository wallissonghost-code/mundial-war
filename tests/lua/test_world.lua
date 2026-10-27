-- Real world map: bots at their capitals, pacing, and performance with many nations.
local H = dofile("tests/lua/helpers.lua")
local ok = H.ok

-- Map sanity --------------------------------------------------------------------------
do
	local data = H.realMapData()
	local Map = H.MapGrid.new(data)
	ok(Map.W == 640 and Map.H == 320, "640x320")
	ok(Map.landCount > 60000, "land cells " .. Map.landCount)
	local sizes = {}
	for _, code in ipairs({ "RUS", "CAN", "USA", "CHN", "BRA", "AUS", "ARG", "FRA", "PRT", "URY" }) do
		local index, c = Map:countryByCode(code)
		ok(index, "country " .. code)
		ok(Map.country[c.capital] == index, code .. " capital inside its country")
		sizes[code] = c.cells
	end
	ok(sizes.BRA > sizes.ARG * 2 and sizes.ARG > sizes.URY * 5 and sizes.FRA > sizes.PRT, "proportional sizes")
	print(string.format("PASS map: %d land cells, %d countries", Map.landCount, #Map.countries))
end

-- Pacing ----------------------------------------------------------------------------------
do
	local cfg = H.configWith({ Bots = { Nations = 0, Tribes = 0 } })
	local world, ctx = H.newWorld({ Config = cfg })
	world:step(0.1, 1)
	local brasilia = H.cellOfCountry(ctx, "BRA")
	ok(ctx.Commands.handle(1, "Ghost", "spawn", brasilia, nil, 1), "spawn in Brazil")
	ctx.Match.startPlaying()
	local n = ctx.Nations.forUser(1)
	-- one early expansion, then pure growth
	ctx.Commands.handle(1, "Ghost", "target", brasilia - 30, 0.25, 2)
	H.run(world, 10, 1)
	local land = n.land
	n.troops = 2500
	H.run(world, 60, 1)
	print(string.format("  growth: 2500 -> %d troops in 60 s with %d cells (max %d)", math.floor(n.troops), n.land, math.floor(n.maxTroops)))
	ok(n.troops > 8000 and n.troops < 13000, "about 10k after 60 s")
	ok(land > 100, "first order conquered " .. land .. " cells")
	-- a big order must take visible time, not 0.2 s
	n.troops = 40000
	local start = n.land
	local okBig, msgBig = ctx.Commands.handle(1, "Ghost", "target", (H.cellOfCountry(ctx, "ARG")), 0.75, 3)
	ok(okBig, "order toward Argentina: " .. tostring(msgBig))
	world:step(0.2, 1)
	local firstTick = n.land - start
	H.run(world, 5, 1)
	print(string.format("  big order: %d cells in the first tick, %d after 5 s", firstTick, n.land - start))
	ok(firstTick > 0 and firstTick <= 40, "visible pace")
	ok(n.land - start < 1500, "big order still takes time")
	print("PASS pacing")
end

-- Bots, full match, performance -------------------------------------------------------------
local function simulate(players, seconds)
	local cfg = H.configWith({ Bots = { Nations = math.min(36, players), Tribes = math.max(0, players - 36) } })
	local world, ctx = H.newWorld({ Config = cfg, seed = 11 })
	world:step(0.1, 1)
	ctx.Match.startPlaying()
	local t0 = os.clock()
	local worst = 0
	for _ = 1, math.floor(seconds / 0.1) do
		local s = os.clock()
		world:step(0.1, 1)
		world:deltaPayload()
		local e = os.clock() - s
		if e > worst then worst = e end
	end
	local total = os.clock() - t0
	return world, ctx, total, worst
end

do
	local world, ctx = simulate(36, 1)
	for _, n in pairs(ctx.Nations.all()) do
		local index = n.country
		ok(ctx.Map.country[n.capital] == index, n.name .. " spawned inside its own country")
	end
	local names = {}
	for _, n in pairs(ctx.Nations.all()) do names[n.name] = true end
	ok(names["Brasil"] and names["Rússia"] and names["China"], "major countries are AI nations")
	print("PASS bots spawn in their own countries")
end

for _, count in ipairs({ 5, 10, 20, 30, 55 }) do
	local world, ctx, total, worst = simulate(count, 120)
	local alive, land, owned = 0, 0, 0
	for _, n in pairs(ctx.Nations.all()) do
		if n.alive then alive = alive + 1 owned = owned + n.land end
	end
	-- accounting: nation land counts match the ownership array
	local counted = 0
	for i = 1, ctx.Map.N do if ctx.Territory.ownerOf(i) > 0 then counted = counted + 1 end end
	ok(counted == owned, "land accounting " .. counted .. " vs " .. owned)
	print(string.format("  %2d nations: 120 s simulated in %.2f s CPU (%.1f ms per 0.1 s step, worst %.1f ms), %d alive, %.1f%% of land owned",
		count, total, total / 1200 * 1000, worst * 1000, alive, owned / ctx.Map.landCount * 100))
end
print("PASS performance runs")
