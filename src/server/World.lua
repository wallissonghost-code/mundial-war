-- Mundial War · wires the services together and runs the fixed-step scheduler.
-- Pure Lua: init.server.lua feeds it Roblox time and players; tests feed it a fake clock.
local World = {}
World.__index = World

local SERVICE_ORDER = {
	"Territory", "Nations", "Economy", "Combat", "Buildings", "Expansion", "Naval",
	"Strategic", "Diplomacy", "Bots", "Match", "Commands",
}

-- deps: { Config, MapData, MapGrid, Palette, Protocol, Services = { Territory = module, ... }, random }
function World.new(deps)
	local self = setmetatable({}, World)
	local ctx = {
		Config = deps.Config, Palette = deps.Palette, Protocol = deps.Protocol,
		Map = deps.Map or deps.MapGrid.new(deps.MapData),
		Stats = deps.BuildingStats,
		random = deps.random or math.random,
		outbox = {},
		fullResync = false,
		mode = deps.mode,
	}
	self.time = 0
	ctx.now = function() return self.time end
	ctx.Landmass = deps.Landmass or ctx.Map:landmasses()
	-- emit(nil, payload) broadcasts; emit(nationId, payload) targets that nation's player
	ctx.emit = function(to, payload)
		ctx.outbox[#ctx.outbox + 1] = { to = to, payload = payload }
	end
	ctx.notify = function(to, text, kind)
		ctx.emit(to, { k = ctx.Protocol.Events.Notice, text = text, kind = kind or "info" })
	end
	ctx.Territory = deps.Services.Territory
	ctx.Nations = deps.Services.Nations
	ctx.Economy = deps.Services.Economy
	ctx.Combat = deps.Services.Combat
	ctx.Buildings = deps.Services.Buildings
	ctx.Expansion = deps.Services.Expansion
	ctx.Naval = deps.Services.Naval
	ctx.Strategic = deps.Services.Strategic
	ctx.Diplomacy = deps.Services.Diplomacy
	ctx.Bots = deps.Services.Bots
	ctx.Match = deps.Services.Match
	ctx.Commands = deps.Services.Commands
	for _, name in ipairs(SERVICE_ORDER) do
		ctx[name].init(ctx)
	end
	for _, name in ipairs({ "Nations", "Buildings", "Expansion", "Naval", "Strategic", "Diplomacy", "Combat", "Bots" }) do
		ctx[name].reset()
	end
	self.ctx = ctx
	self.timers = { sim = 0, econ = 0, comp = 0, encl = 0 }
	self.enclaveQueue, self.analyzeQueue = {}, {}
	self.stats = { simTime = 0, simCount = 0, worst = 0 }
	return self
end

-- Advances the world by dt seconds. `clock` (optional) measures CPU time for stats.
function World:step(dt, humanCount, clock)
	local ctx, T = self.ctx, self.ctx.Config.Tick
	self.time = self.time + dt
	ctx.Match.tick(humanCount or 0)
	local t = self.timers
	t.sim = t.sim + dt
	t.econ = t.econ + dt
	t.comp = t.comp + dt
	t.encl = t.encl + dt
	local started = clock and clock()
	while t.sim >= T.Simulation do
		t.sim = t.sim - T.Simulation
		ctx.Expansion.tick(T.Simulation)
		ctx.Combat.tick(T.Simulation)
		ctx.Naval.tick(T.Simulation)
		ctx.Strategic.tick(T.Simulation)
		ctx.Buildings.tick()
		ctx.Bots.tick()
	end
	if t.econ >= T.Economy then
		ctx.Economy.tick(t.econ)
		ctx.Diplomacy.tick()
		t.econ = 0
	end
	-- territory analysis is spread over several steps (a few nations per step) so a world
	-- with dozens of empires never produces a long single frame
	if t.encl >= T.EnclaveFill then
		t.encl = 0
		if ctx.Match.isPlaying() then
			for id, n in pairs(ctx.Nations.all()) do
				if n.alive then self.enclaveQueue[#self.enclaveQueue + 1] = id end
			end
		end
	end
	if t.comp >= T.Components then
		t.comp = 0
		for id, n in pairs(ctx.Nations.all()) do
			if n.alive then self.analyzeQueue[#self.analyzeQueue + 1] = id end
		end
	end
	for _ = 1, 3 do
		local id = table.remove(self.enclaveQueue)
		if not id then break end
		if ctx.Nations.alive(id) then ctx.Territory.fillEnclaves(id) end
	end
	for _ = 1, 3 do
		local id = table.remove(self.analyzeQueue)
		if not id then break end
		if ctx.Nations.alive(id) then ctx.Territory.analyze(id) end
	end
	if started then
		local spent = clock() - started
		self.stats.simTime = self.stats.simTime + spent
		self.stats.simCount = self.stats.simCount + 1
		if spent > self.stats.worst then self.stats.worst = spent end
	end
end

function World:drainOutbox()
	local out = self.ctx.outbox
	self.ctx.outbox = {}
	return out
end

-- Everything a client needs when it joins (or after a new round).
function World:initPayload(userId)
	local ctx = self.ctx
	local nations = {}
	for _, n in pairs(ctx.Nations.all()) do
		if n.alive then nations[#nations + 1] = ctx.Nations.publicInfo(n) end
	end
	local you = ctx.Nations.forUser(userId)
	local fleets, boats = ctx.Naval.snapshot()
	return {
		k = ctx.Protocol.Events.Init,
		owners = ctx.Territory.snapshotRuns(),
		nations = nations,
		buildings = ctx.Buildings.snapshot(),
		relations = ctx.Diplomacy.snapshot(),
		fleets = fleets, boats = boats,
		missiles = ctx.Strategic.snapshot(),
		fires = ctx.Strategic.fireView(),
		cargos = ctx.Naval.cargoView(),
		match = ctx.Match.publicView(),
		you = you and you.alive and you.id or nil,
		debug = ctx.Config.DEBUG_MODE,
	}
end

-- Frequent public payload: territory delta + building changes (batched).
function World:deltaPayload()
	local ctx = self.ctx
	local cells = ctx.Territory.drainChanges()
	local builds = ctx.Buildings.drainChanges()
	if not cells and not builds then return nil end
	return { k = ctx.Protocol.Events.Tick, d = cells, b = builds }
end

-- Per-nation public numbers: { id, troops, land, labelCell, labelSize, capital }
function World:nationsPayload()
	local ctx = self.ctx
	local list = {}
	for _, n in pairs(ctx.Nations.all()) do
		if n.alive then
			list[#list + 1] = { n.id, math.floor(n.troops), n.land, n.labelCell or n.capital, n.labelSize or 1, n.capital }
		end
	end
	return { k = ctx.Protocol.Events.Nations, list = list, match = ctx.Match.publicView() }
end

function World:ordersPayload()
	local ctx = self.ctx
	local payload = {
		k = ctx.Protocol.Events.Orders,
		orders = ctx.Expansion.publicView(),
		fleets = ctx.Naval.publicView(),
		boats = ctx.Naval.boatView(),
		cargos = ctx.Naval.cargoView(),
		fires = ctx.Strategic.fireView(),
	}
	if ctx.Config.DEBUG_MODE then payload.bots = ctx.Bots.debugView() end
	return payload
end

-- Private numbers for one player's HUD.
function World:privatePayload(userId)
	local ctx = self.ctx
	local n = ctx.Nations.forUser(userId)
	if not n or not n.alive then return nil end
	local costs = {}
	for kind in pairs(ctx.Config.Buildings) do costs[kind] = ctx.Buildings.cost(n.id, kind) end
	local cooldowns = {}
	for _, kind in ipairs({ "silo", "airfield" }) do
		local best = nil
		for _, b in ipairs(ctx.Buildings.ofKind(n.id, kind)) do
			local left = math.max(0, b.readyAt - ctx.now())
			if not best or left < best then best = left end
		end
		cooldowns[kind] = best
	end
	return {
		k = "me", id = n.id, troops = math.floor(n.troops), max = math.floor(n.maxTroops),
		rate = n.troopRate, gold = math.floor(n.gold), goldRate = n.goldRate, land = n.land,
		oil = math.floor(n.oil or 0), oilRate = n.oilRate or 0, mode = ctx.mode,
		share = n.land / ctx.Map.landCount, costs = costs, cooldowns = cooldowns,
		requests = ctx.Diplomacy.pendingFor(n.id),
	}
end

return World
