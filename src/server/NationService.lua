-- Mundial War · players, AI nations and tribes: identity, colour, capital, life cycle.
local NationService = {}

local ctx
local nations = {}       -- id -> nation
local byUser = {}        -- userId -> nation id
local nextId = 1
local lastDeath = {}     -- userId -> time of elimination (respawn cooldown)

function NationService.init(context)
	ctx = context
end

function NationService.reset()
	nations, byUser, nextId = {}, {}, 1
	lastDeath = {}
end

function NationService.get(id)
	return nations[id]
end

function NationService.all()
	return nations
end

function NationService.forUser(userId)
	local id = byUser[userId]
	return id and nations[id] or nil
end

function NationService.alive(id)
	local n = nations[id]
	return n ~= nil and n.alive
end

local function pickColor(capital)
	local Palette, Map = ctx.Palette, ctx.Map
	local used = {}
	local nearby = {}
	for _, n in pairs(nations) do
		if n.alive then
			used[n.color] = (used[n.color] or 0) + 1
			if Map:distance(n.capital, capital) < 120 then
				nearby[#nearby + 1] = Palette.Nations[n.color]
			end
		end
	end
	local best, bestScore = 1, -math.huge
	for index, c in ipairs(Palette.Nations) do
		local score = 0
		local minD = 1000
		for _, other in ipairs(nearby) do
			minD = math.min(minD, Palette.distance(c, other))
		end
		score = minD - (used[index] or 0) * 400 + ctx.random() * 5
		if score > bestScore then best, bestScore = index, score end
	end
	return best
end

-- Checks a spawn cell: land, neutral and far enough from every other capital.
function NationService.canSpawnAt(cell)
	local Map, Territory = ctx.Map, ctx.Territory
	if not Map:valid(cell) or not Map.land[cell] then
		return false, "Escolha uma célula de terra."
	end
	if Territory.ownerOf(cell) ~= 0 then
		return false, "Essa terra já tem dono."
	end
	local minD = ctx.Config.Spawn.MinCapitalDistance
	for _, n in pairs(nations) do
		if n.alive and Map:distance(n.capital, cell) < minD then
			return false, "Muito perto da capital de " .. n.name .. "."
		end
	end
	return true
end

function NationService.canRespawn(userId)
	local t = lastDeath[userId]
	if not t then return true end
	return ctx.now() - t >= ctx.Config.Match.RespawnCooldown
end

-- Creates a nation with its capital and a small starting disc of neutral land.
-- Creates a nation with its capital and starting land: a small disc of neutral land, or
-- (Conquista Extrema) a whole country passed as info.cells with its own troops/gold/oil.
function NationService.create(kind, name, cell, info)
	local Config = ctx.Config
	info = info or {}
	if not info.cells then
		local ok, why = NationService.canSpawnAt(cell)
		if not ok then return nil, why end
	end
	local id = nextId
	nextId = nextId + 1
	local troops = info.troops or (kind == "player" and Config.Spawn.PlayerStartTroops
		or kind == "bot" and Config.Spawn.BotStartTroops or Config.Spawn.TribeStartTroops)
	local n = {
		id = id, kind = kind, name = name, userId = info.userId,
		country = info.country or ctx.Map.country[cell],
		troops = troops, gold = info.gold or Config.Gold.StartGold, oil = info.oil or 0, land = 0, capital = cell,
		labelCell = cell, labelSize = 1, alive = true, color = pickColor(cell),
		built = {}, spawnedAt = ctx.now(), maxTroops = Config.Troops.BaseCapacity,
		troopRate = 0, goldRate = 0, oilRate = 0, kills = 0,
	}
	nations[id] = n
	if n.userId then byUser[n.userId] = id end
	ctx.Territory.register(id)
	if info.cells then
		for _, i in ipairs(info.cells) do
			if ctx.Territory.ownerOf(i) == 0 then ctx.Territory.setOwner(i, id) end
		end
	else
		ctx.Map:disc(cell, Config.Spawn.StartRadius, function(i)
			if ctx.Territory.ownerOf(i) == 0 then
				ctx.Territory.setOwner(i, id)
			end
		end)
	end
	ctx.emit(nil, { k = ctx.Protocol.Events.Nations, add = NationService.publicInfo(n) })
	return n
end

-- Conquista Extrema: when a player leaves, the AI takes the country back instead of erasing it.
function NationService.returnToAI(id)
	local n = nations[id]
	if not n or not n.alive or not n.userId then return end
	byUser[n.userId] = nil
	n.userId = nil
	n.kind = "bot"
	n.name = string.gsub(n.name, " %(.*%)$", "")
	ctx.Bots.adopt(id)
	ctx.emit(nil, { k = ctx.Protocol.Events.Nations, add = NationService.publicInfo(n) })
end

-- Conquista Extrema: a player takes command of the AI country that owns `cell`.
function NationService.takeover(userId, displayName, cell)
	local Map = ctx.Map
	if not Map:valid(cell) or not Map.land[cell] then return nil, "Clique num país." end
	local id = ctx.Territory.ownerOf(cell)
	local n = nations[id]
	if not n or not n.alive then return nil, "Esse lugar não pertence a nenhum país. Escolha um país colorido." end
	if n.kind == "player" then return nil, n.name .. " já é governado por outro jogador." end
	ctx.Bots.release(id)
	n.kind = "player"
	n.userId = userId
	n.name = n.name .. " (" .. displayName .. ")"
	byUser[userId] = id
	ctx.emit(nil, { k = ctx.Protocol.Events.Nations, add = NationService.publicInfo(n) })
	return n
end

function NationService.publicInfo(n)
	return {
		id = n.id, kind = n.kind, name = n.name, userId = n.userId, color = n.color,
		capital = n.capital, country = n.country, alive = n.alive,
	}
end

-- Called when a nation reaches zero land or its player leaves.
function NationService.eliminate(id, reason)
	local n = nations[id]
	if not n or not n.alive then return end
	n.alive = false
	n.troops = 0
	ctx.Expansion.cancelAll(id, false)
	ctx.Naval.removeNation(id)
	ctx.Diplomacy.removeNation(id)
	ctx.Territory.releaseAll(id)
	if n.userId then
		lastDeath[n.userId] = ctx.now()
		byUser[n.userId] = nil
	end
	ctx.emit(nil, { k = ctx.Protocol.Events.Nations, remove = id, reason = reason })
end

function NationService.checkEliminations()
	for id, n in pairs(nations) do
		if n.alive and n.land <= 0 then
			NationService.eliminate(id, "conquered")
		end
	end
end

function NationService.countAlive(kind)
	local c = 0
	for _, n in pairs(nations) do
		if n.alive and (kind == nil or n.kind == kind) then c = c + 1 end
	end
	return c
end

return NationService
