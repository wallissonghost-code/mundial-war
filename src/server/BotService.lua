-- Mundial War · AI nations (real countries at their capitals) and small tribes.
-- Each bot thinks on its own staggered schedule; nothing runs per frame for every bot.
local BotService = {}

local ctx, Config, Map, Territory
local bots = {}              -- nid -> { nid, kind, nextThink, state, lastNaval, lastBuild }
local countryCells = nil     -- country index -> list of cells
local coastCells = nil

BotService.States = {
	Expanding = "EXPANDING", Consolidating = "CONSOLIDATING", Defending = "DEFENDING",
	Attacking = "ATTACKING", Building = "BUILDING", Naval = "NAVAL", Recovering = "RECOVERING",
}
local S = BotService.States

function BotService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
	countryCells, coastCells = {}, {}
	for i = 1, Map.N do
		local c = Map.country[i]
		if c > 0 then
			local list = countryCells[c]
			if not list then list = {} countryCells[c] = list end
			list[#list + 1] = i
			if Map.coast[i] then coastCells[#coastCells + 1] = i end
		end
	end
end

function BotService.reset()
	bots = {}
end

function BotService.all()
	return bots
end

local function findSpawn(countryIndex, preferred)
	if ctx.Nations.canSpawnAt(preferred) then return preferred end
	local best, bestD = nil, math.huge
	for _, i in ipairs(countryCells[countryIndex] or {}) do
		local d = Map:distance(i, preferred)
		if d < bestD and ctx.Nations.canSpawnAt(i) then best, bestD = i, d end
	end
	return best
end

local function thinkInterval(kind)
	if kind == "tribe" then return Config.Bots.TribeThinkInterval end
	if ctx.mode == "extreme" then return Config.Bots.ExtremeThinkInterval end
	return Config.Bots.ThinkInterval
end

local function register(n, kind, index, total)
	local interval = thinkInterval(kind)
	bots[n.id] = {
		nid = n.id, kind = kind, state = S.Expanding,
		nextThink = ctx.now() + interval * (index / math.max(1, total)),
		lastNaval = -1e9, lastAttack = -1e9,
	}
end

-- AI nations take the largest countries; tribes take random other countries.
function BotService.spawnAll()
	local list = {}
	for index, c in ipairs(Map.countries) do
		list[#list + 1] = { index = index, cells = c.cells }
	end
	table.sort(list, function(a, b) return a.cells > b.cells end)
	local made = 0
	local plan = {}
	for _, entry in ipairs(list) do
		if made >= Config.Bots.Nations then break end
		plan[#plan + 1] = { kind = "bot", index = entry.index }
		made = made + 1
	end
	local rest = {}
	for k = made + 1, #list do
		if list[k].cells >= 12 then rest[#rest + 1] = list[k].index end
	end
	for k = #rest, 2, -1 do
		local j = math.floor(ctx.random() * k) + 1
		rest[k], rest[j] = rest[j], rest[k]
	end
	for k = 1, math.min(Config.Bots.Tribes, #rest) do
		plan[#plan + 1] = { kind = "tribe", index = rest[k] }
	end
	for order, p in ipairs(plan) do
		local country = Map.countries[p.index]
		local cell = findSpawn(p.index, country.capital)
		if cell then
			local name = p.kind == "bot" and country.name or ("Tribos de " .. country.name)
			local n = ctx.Nations.create(p.kind, name, cell, { country = p.index })
			if n then register(n, p.kind, order, #plan) end
		end
	end
end

-- Conquista Extrema: every country big enough starts as an AI nation that owns all of it.
function BotService.spawnCountries()
	local E = Config.Extreme
	local list = {}
	for index, c in ipairs(Map.countries) do
		if countryCells[index] and #countryCells[index] >= E.MinCountryCells then list[#list + 1] = index end
	end
	for order, index in ipairs(list) do
		local c = Map.countries[index]
		local cells = countryCells[index]
		local n = ctx.Nations.create("bot", c.name, c.capital, {
			country = index, cells = cells, troops = E.BaseTroops + #cells * E.TroopsPerCell,
			gold = E.StartGold, oil = E.StartOil,
		})
		if n then register(n, "bot", order, #list) end
	end
end

-- A player left a country in Conquista Extrema: the AI governs it again.
function BotService.adopt(nid)
	local n = ctx.Nations.get(nid)
	if n and n.alive then register(n, "bot", 0, 1) end
end

-- A player took this nation over: stop its AI.
function BotService.release(nid)
	bots[nid] = nil
end

-- Alliance policy when someone asks a bot.
function BotService.considerAlliance(botId, requesterId)
	local bot, other = ctx.Nations.get(botId), ctx.Nations.get(requesterId)
	if not bot or not other then return false end
	local allies = #ctx.Diplomacy.allies(botId)
	if allies >= 3 then return false end
	local b = bots[botId]
	if b and ctx.now() - b.lastAttack < 20 and b.lastTarget == requesterId then return false end
	if bot.kind == "tribe" then return other.troops >= bot.troops end
	return other.troops >= bot.troops * 0.6 or ctx.random() < 0.3
end

local function pickNeutralAnchor(n)
	-- prefer free land inside the bot's own country; sample instead of scanning everything
	local list = countryCells[n.country]
	if list and #list > 0 then
		for _ = 1, 12 do
			local i = list[math.floor(ctx.random() * #list) + 1]
			if Territory.ownerOf(i) == 0 and ctx.Expansion.sameLandmass(n.id, i) then
				return i
			end
		end
	end
	local frontier, count = Territory.frontier(n.id, 0, {})
	if count == 0 then return nil end
	return frontier[math.floor(ctx.random() * count) + 1]
end

local function hasOrderAgainst(nid, target)
	for _, o in ipairs(ctx.Expansion.ordersOf(nid)) do
		if o.target == target then return true end
	end
	return false
end

local function underAttack(nid)
	local fronts = {}
	for _, o in ipairs(ctx.Expansion.activeOrders()) do
		if o.target == nid and o.front then fronts[#fronts + 1] = o end
	end
	return fronts
end

local function tryBuild(n, b, attacked)
	local Buildings = ctx.Buildings
	local wants = {}
	if Buildings.count(n.id, "city") < 1 + math.floor(n.land / 400) then wants[#wants + 1] = "city" end
	if Buildings.count(n.id, "factory") < 1 + math.floor(n.land / 600) then wants[#wants + 1] = "factory" end
	if attacked then
		if Buildings.count(n.id, "bunker") < 1 + math.floor(n.land / 300) then wants[#wants + 1] = "bunker" end
		if Buildings.count(n.id, "tower") < 1 + math.floor(n.land / 800) then wants[#wants + 1] = "tower" end
	end
	if Buildings.count(n.id, "port") < 1 and b.landlocked then wants[#wants + 1] = "port" end
	if n.land > 800 and Buildings.count(n.id, "artillery") < 1 then wants[#wants + 1] = "artillery" end
	if n.land > 1200 and Buildings.count(n.id, "airdefense") < 1 then wants[#wants + 1] = "airdefense" end
	if n.kind == "bot" and n.land > 1500 and Buildings.count(n.id, "tankfactory") < 2 then wants[#wants + 1] = "tankfactory" end
	if ctx.mode == "extreme" then
		if Buildings.count(n.id, "oilwell") < 1 + math.floor(n.land / 500) then wants[#wants + 1] = "oilwell" end
		if attacked then
			if Buildings.count(n.id, "wall") < 2 + math.floor(n.land / 200) then table.insert(wants, 1, "wall") end
			if Buildings.count(n.id, "trench") < 1 + math.floor(n.land / 400) then wants[#wants + 1] = "trench" end
		end
		if Buildings.count(n.id, "port") > 0 and Buildings.count(n.id, "antinaval") < 1 then wants[#wants + 1] = "antinaval" end
		if n.land > 600 and Buildings.count(n.id, "flak") < 1 then wants[#wants + 1] = "flak" end
	end
	for _, kind in ipairs(wants) do
		local cost = Buildings.cost(n.id, kind)
		if n.gold >= cost then
			-- pick a spot: front-line kinds near the enemy, ports on the coast, others inland
			local owned = Territory.owned(n.id)
			local tries = 0
			for i in pairs(owned) do
				tries = tries + 1
				if tries > 60 then break end
				local good
				if kind == "port" or kind == "antinaval" then good = Map.coast[i]
				elseif kind == "bunker" or kind == "tower" or kind == "wall" or kind == "trench" then good = Territory.borderCells(n.id)[i] and attacked ~= nil
				else good = not Territory.borderCells(n.id)[i] end
				if good and Buildings.canBuild(n.id, i, kind) then
					Buildings.build(n.id, i, kind)
					return true
				end
			end
		end
	end
	-- rich bots improve what they have, and coastal ones keep a defence boat
	if n.kind == "bot" then
		if Buildings.count(n.id, "port") > 0 and n.gold > Config.Naval.BoatGold * 3 and #ctx.Naval.boats() < 400 then
			local mine = 0
			for _, boat in ipairs(ctx.Naval.boats()) do if boat.nation == n.id then mine = mine + 1 end end
			if mine < 1 + math.floor(n.land / 1500) then
				local port = Buildings.ofKind(n.id, "port")[1]
				if ctx.Naval.buyBoat(n.id, port.cell) then return true end
			end
		end
		for _, kind in ipairs({ "city", "factory", "bunker", "airdefense", "port" }) do
			for _, building in ipairs(Buildings.ofKind(n.id, kind)) do
				local cost = Buildings.upgradeCost(building)
				if cost and n.gold > cost * 2.5 then
					Buildings.upgrade(n.id, building.cell)
					return true
				end
			end
		end
	end
	return false
end

local function tryNaval(n, b)
	if ctx.now() - b.lastNaval < 25 then return false end
	if ctx.Buildings.count(n.id, "port") <= 0 then return false end
	if n.gold < Config.Naval.TransportGold or n.troops < 800 then return false end
	b.lastNaval = ctx.now()
	local ports = ctx.Buildings.ofKind(n.id, "port")
	local best, bestD = nil, math.huge
	for _ = 1, 40 do
		local i = coastCells[math.floor(ctx.random() * #coastCells) + 1]
		local o = Territory.ownerOf(i)
		if o ~= n.id and (o == 0 or (ctx.Diplomacy.canAttack(n.id, o) and ctx.Nations.get(o).troops < n.troops * 0.5)) then
			local d = Map:distance(i, ports[1].cell)
			-- nearby shores only: a short search, and a realistic invasion
			if d < bestD and d < 120 then best, bestD = i, d end
		end
	end
	if best then
		local ok = ctx.Naval.launch(n.id, best, n.kind == "tribe" and 0.3 or 0.4, Config.Bots.NavalSearchLimit)
		return ok
	end
	return false
end

local function think(b)
	local n = ctx.Nations.get(b.nid)
	if not n or not n.alive then bots[b.nid] = nil return end
	local B = Config.Bots
	local percent = b.kind == "tribe" and B.TribeSendPercent or B.SendPercent
	local fullness = n.troops / math.max(1, n.maxTroops)
	local attacked = underAttack(n.id)
	local attackedBy = #attacked > 0 and attacked[1].nation or nil

	-- building happens alongside any other state
	if ctx.now() >= (b.nextBuild or 0) then
		b.nextBuild = ctx.now() + B.BuildInterval
		if n.gold > 0 and tryBuild(n, b, attackedBy) then b.state = S.Building end
	end

	if attackedBy and n.troops < (ctx.Nations.get(attackedBy) or n).troops then
		b.state = S.Defending
		-- counter-attack the invader if we can afford it
		if fullness > 0.4 and not hasOrderAgainst(n.id, attackedBy) and ctx.Diplomacy.canAttack(n.id, attackedBy) then
			local front = attacked[1].front
			ctx.Expansion.issue(n.id, front, percent)
		end
		return
	end
	if fullness < B.RecoverBelow then
		b.state = S.Recovering
		return
	end

	local neutralTouch = Territory.touches(n.id, 0)
	if neutralTouch and not hasOrderAgainst(n.id, 0) then
		local anchor = pickNeutralAnchor(n)
		local issued = anchor and ctx.Expansion.issue(n.id, anchor, percent)
		if not issued then
			-- the preferred spot is behind someone else: take any free land on our border
			local frontier, count = Territory.frontier(n.id, 0, {})
			if count > 0 then
				issued = ctx.Expansion.issue(n.id, frontier[math.floor(ctx.random() * count) + 1], percent)
			end
		end
		if issued then
			b.state = S.Expanding
			return
		end
	end
	b.landlocked = not neutralTouch

	if not neutralTouch or fullness > 0.8 then
		-- pick the weakest neighbour by troop density
		local best, bestScore = nil, math.huge
		for other in pairs(Territory.neighborsOf(n.id)) do
			local o = ctx.Nations.get(other)
			if o and o.alive and ctx.Diplomacy.canAttack(n.id, other) then
				local density = o.troops / math.max(1, o.land)
				if density < bestScore then best, bestScore = other, density end
			end
		end
		if best and b.kind ~= "tribe" then
			local o = ctx.Nations.get(best)
			local sending = n.troops * percent
			if (n.troops >= o.troops * B.AttackWhenStronger or sending / math.max(1, bestScore) > 25)
				and not hasOrderAgainst(n.id, best) then
				local cell = Territory.frontier(n.id, best, {})[1]
				if cell then
					ctx.Expansion.issue(n.id, cell, percent)
					b.state = S.Attacking
					b.lastAttack = ctx.now()
					b.lastTarget = best
					return
				end
			end
		end
		if not neutralTouch and tryNaval(n, b) then
			b.state = S.Naval
			return
		end
	end
	if not neutralTouch then b.state = S.Consolidating end
end

function BotService.tick()
	if not ctx.Match.isPlaying() then return end
	local now = ctx.now()
	for _, b in pairs(bots) do
		if now >= b.nextThink then
			b.nextThink = now + thinkInterval(b.kind)
			think(b)
		end
	end
end

function BotService.debugView()
	local out = {}
	for nid, b in pairs(bots) do out[#out + 1] = { nid, b.state } end
	return out
end

return BotService
