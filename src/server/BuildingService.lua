-- Mundial War · structures: placement, levels, ownership on capture, area effects, EMP shutdown.
local BuildingService = {}

local ctx, Config, Map, Stats
local buildings = {}       -- cell -> { kind, owner, cell, level, readyAt, active, disabledUntil }
local totals = {}          -- nid -> { growth, capacity, gold, count = { kind = n } }
local chunks = {}          -- chunk key -> { cell = true }
local disabled = {}        -- cell -> true while an EMP keeps it off
local CHUNK = 16
local changes = {}         -- cell -> building or false (for replication)
local EMPTY = { growth = 0, capacity = 0, gold = 0, oil = 0, attack = 0, count = {} }

function BuildingService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Stats = ctx.Stats
end

function BuildingService.reset()
	buildings, totals, chunks, changes, disabled = {}, {}, {}, {}, {}
end

local function chunkKey(cell)
	local x, y = Map:xy(cell)
	return math.floor(x / CHUNK) * 1000 + math.floor(y / CHUNK)
end

local function bucket(nid)
	local t = totals[nid]
	if not t then
		t = { growth = 0, capacity = 0, gold = 0, oil = 0, attack = 0, count = {} }
		totals[nid] = t
	end
	return t
end

-- Economic effect of one building (only while it is active).
local function economy(b, sign)
	if b.owner <= 0 or not b.active then return end
	local t = bucket(b.owner)
	local level = b.level
	t.growth = t.growth + sign * (Stats.stat(Config, b.kind, level, "growth") or 0)
	t.capacity = t.capacity + sign * (Stats.stat(Config, b.kind, level, "capacity") or 0)
	t.gold = t.gold + sign * (Stats.stat(Config, b.kind, level, "gold") or 0)
	t.attack = t.attack + sign * (Stats.stat(Config, b.kind, level, "attackBonus") or 0)
	t.oil = t.oil + sign * (Stats.stat(Config, b.kind, level, "oil") or 0)
end

local function count(b, sign)
	if b.owner <= 0 then return end
	local t = bucket(b.owner)
	t.count[b.kind] = (t.count[b.kind] or 0) + sign
end

local function changed(b)
	changes[b.cell] = b
end

function BuildingService.totals(nid)
	return totals[nid] or EMPTY
end

function BuildingService.count(nid, kind)
	local t = totals[nid]
	return t and t.count[kind] or 0
end

function BuildingService.at(cell)
	return buildings[cell]
end

function BuildingService.all()
	return buildings
end

function BuildingService.stat(b, field)
	return Stats.stat(Config, b.kind, b.level, field)
end

function BuildingService.cost(nid, kind)
	local def = Config.Buildings[kind]
	if not def then return nil end
	return math.floor(def.cost * (1 + Config.CostGrowth * BuildingService.count(nid, kind)))
end

-- Calls fn(building) for every structure within `radius` of `cell` (chunked lookup).
function BuildingService.near(cell, radius, fn)
	local x, y = Map:xy(cell)
	local r2 = radius * radius
	for cx = math.floor((x - radius) / CHUNK), math.floor((x + radius) / CHUNK) do
		for cy = math.floor((y - radius) / CHUNK), math.floor((y + radius) / CHUNK) do
			local set = chunks[cx * 1000 + cy]
			if set then
				for c in pairs(set) do
					local bx, by = Map:xy(c)
					if (bx - x) * (bx - x) + (by - y) * (by - y) <= r2 then
						if fn(buildings[c]) then return end
					end
				end
			end
		end
	end
end

-- Strongest value of `field` among active `kind` buildings of `ownerNid` whose own reach
-- (radius at their level) covers `cell`; nil when none does. `lowest` picks the smallest
-- value instead (for multipliers where lower is stronger).
function BuildingService.covered(cell, kind, ownerNid, field, lowest)
	if BuildingService.count(ownerNid, kind) <= 0 then return nil end
	local best = nil
	local cx, cy = Map:xy(cell)
	BuildingService.near(cell, Stats.maxStat(Config, kind, "radius"), function(b)
		if b.kind == kind and b.owner == ownerNid and b.active then
			local r = BuildingService.stat(b, "radius")
			local bx, by = Map:xy(b.cell)
			if (bx - cx) * (bx - cx) + (by - cy) * (by - cy) <= r * r then
				local v = field and BuildingService.stat(b, field) or 1
				if best == nil or (lowest and v < best) or (not lowest and v > best) then best = v end
			end
		end
	end)
	return best
end

function BuildingService.canBuild(nid, cell, kind)
	local n = ctx.Nations.get(nid)
	local def = Config.Buildings[kind]
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not def then return false, "Construção inválida." end
	if def.mode and def.mode ~= ctx.mode then return false, def.name .. " só existe na Conquista Extrema." end
	if not Map:valid(cell) or ctx.Territory.ownerOf(cell) ~= nid then
		return false, "Construa em uma célula do seu território."
	end
	if buildings[cell] then return false, "Já existe uma construção aqui." end
	if def.coastal and not Map.coast[cell] then return false, "Porto só pode ficar no litoral." end
	if def.requires and BuildingService.count(nid, def.requires) <= 0 then
		return false, "Requer " .. Config.Buildings[def.requires].name .. "."
	end
	local crowded = false
	BuildingService.near(cell, Config.MinBuildingSpacing, function()
		crowded = true
		return true
	end)
	if crowded then return false, "Muito perto de outra construção." end
	local cost = BuildingService.cost(nid, kind)
	if n.gold < cost then return false, "Ouro insuficiente (" .. cost .. ")." end
	return true, cost
end

local function place(cell, kind, nid, level)
	local b = { kind = kind, owner = nid, cell = cell, level = level or 1, readyAt = 0, active = true }
	buildings[cell] = b
	local key = chunkKey(cell)
	chunks[key] = chunks[key] or {}
	chunks[key][cell] = true
	count(b, 1)
	economy(b, 1)
	changed(b)
	return b
end

function BuildingService.build(nid, cell, kind)
	local ok, costOrWhy = BuildingService.canBuild(nid, cell, kind)
	if not ok then return false, costOrWhy end
	local n = ctx.Nations.get(nid)
	n.gold = n.gold - costOrWhy
	place(cell, kind, nid, 1)
	return true, "Construção pronta: " .. Config.Buildings[kind].name .. "."
end

function BuildingService.upgradeCost(b)
	return Stats.upgradeCost(Config, b.kind, b.level)
end

function BuildingService.upgrade(nid, cell)
	local n = ctx.Nations.get(nid)
	local b = buildings[cell]
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not b or b.owner ~= nid then return false, "Selecione uma construção sua." end
	local cost = BuildingService.upgradeCost(b)
	if not cost then return false, "Já está no nível máximo." end
	if n.gold < cost then return false, "Ouro insuficiente (" .. cost .. ")." end
	n.gold = n.gold - cost
	economy(b, -1)
	b.level = b.level + 1
	economy(b, 1)
	changed(b)
	return true, Config.Buildings[b.kind].name .. " agora é nível " .. b.level .. "."
end

function BuildingService.destroy(cell)
	local b = buildings[cell]
	if not b then return end
	economy(b, -1)
	count(b, -1)
	buildings[cell] = nil
	disabled[cell] = nil
	local set = chunks[chunkKey(cell)]
	if set then set[cell] = nil end
	changes[cell] = false
	if b.kind == "port" then ctx.Naval.onPortLost(cell) end
end

-- EMP: the building stops working until `untilTime`.
function BuildingService.disable(cell, untilTime)
	local b = buildings[cell]
	if not b then return end
	if b.active then
		economy(b, -1)
		b.active = false
	end
	b.disabledUntil = math.max(b.disabledUntil or 0, untilTime)
	disabled[cell] = true
	changed(b)
end

function BuildingService.tick()
	local now = ctx.now()
	for cell in pairs(disabled) do
		local b = buildings[cell]
		if not b then
			disabled[cell] = nil
		elseif now >= (b.disabledUntil or 0) then
			b.active = true
			b.disabledUntil = nil
			economy(b, 1)
			disabled[cell] = nil
			changed(b)
		end
	end
end

-- Territory calls this for every ownership change: captured structures change hands
-- (keeping their level), structures on land that becomes neutral are destroyed.
function BuildingService.onOwnerChanged(cell, old, new)
	local b = buildings[cell]
	if not b then return end
	if new <= 0 then
		BuildingService.destroy(cell)
		return
	end
	economy(b, -1)
	count(b, -1)
	b.owner = new
	count(b, 1)
	economy(b, 1)
	changed(b)
	if b.kind == "port" then ctx.Naval.onPortLost(cell) end
end

local function row(cell, b)
	if not b then return { cell, false, 0, 0, false } end
	return { cell, b.kind, b.owner, b.level, not b.active }
end

-- Replication rows: { cell, kind | false, owner, level, disabled }
function BuildingService.drainChanges()
	if next(changes) == nil then return nil end
	local out = {}
	for cell, b in pairs(changes) do
		out[#out + 1] = row(cell, b ~= false and buildings[cell] or nil)
	end
	changes = {}
	return out
end

function BuildingService.snapshot()
	local out = {}
	for cell, b in pairs(buildings) do out[#out + 1] = row(cell, b) end
	return out
end

function BuildingService.ofKind(nid, kind)
	local list = {}
	if BuildingService.count(nid, kind) <= 0 then return list end
	for _, b in pairs(buildings) do
		if b.owner == nid and b.kind == kind then list[#list + 1] = b end
	end
	return list
end

return BuildingService
