-- Mundial War · structures: placement rules, ownership on capture, area effects.
local BuildingService = {}

local ctx, Config, Map
local buildings = {}       -- cell -> { kind, owner, cell, readyAt }
local totals = {}          -- nid -> { growth, capacity, gold, count = { kind = n } }
local chunks = {}          -- chunk key -> { cell = true }
local CHUNK = 16
local changes = {}         -- cell -> kind or false (for replication)
local EMPTY = { growth = 0, capacity = 0, gold = 0, count = {} }

function BuildingService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
end

function BuildingService.reset()
	buildings, totals, chunks, changes = {}, {}, {}, {}
end

local function chunkKey(cell)
	local x, y = Map:xy(cell)
	return math.floor(x / CHUNK) * 1000 + math.floor(y / CHUNK)
end

local function account(nid, kind, sign)
	if nid <= 0 then return end
	local t = totals[nid]
	if not t then
		t = { growth = 0, capacity = 0, gold = 0, count = {} }
		totals[nid] = t
	end
	local def = Config.Buildings[kind]
	t.growth = t.growth + sign * (def.growth or 0)
	t.capacity = t.capacity + sign * (def.capacity or 0)
	t.gold = t.gold + sign * (def.gold or 0)
	t.count[kind] = (t.count[kind] or 0) + sign
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

-- True when `owner` has a `kind` building whose own radius covers `cell`.
function BuildingService.covered(cell, kind, ownerNid)
	if BuildingService.count(ownerNid, kind) <= 0 then return false end
	local found = false
	BuildingService.near(cell, Config.Buildings[kind].radius, function(b)
		if b.kind == kind and b.owner == ownerNid then
			found = true
			return true
		end
	end)
	return found
end

function BuildingService.canBuild(nid, cell, kind)
	local n = ctx.Nations.get(nid)
	local def = Config.Buildings[kind]
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not def then return false, "Construção inválida." end
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

local function place(cell, kind, nid)
	buildings[cell] = { kind = kind, owner = nid, cell = cell, readyAt = 0 }
	local key = chunkKey(cell)
	chunks[key] = chunks[key] or {}
	chunks[key][cell] = true
	account(nid, kind, 1)
	changes[cell] = { kind, nid }
end

function BuildingService.build(nid, cell, kind)
	local ok, costOrWhy = BuildingService.canBuild(nid, cell, kind)
	if not ok then return false, costOrWhy end
	local n = ctx.Nations.get(nid)
	n.gold = n.gold - costOrWhy
	place(cell, kind, nid)
	return true, Config.Buildings[kind].name .. " construída."
end

function BuildingService.destroy(cell)
	local b = buildings[cell]
	if not b then return end
	buildings[cell] = nil
	local set = chunks[chunkKey(cell)]
	if set then set[cell] = nil end
	account(b.owner, b.kind, -1)
	changes[cell] = false
	if b.kind == "port" then ctx.Naval.onPortLost(cell) end
end

-- Territory calls this for every ownership change: captured structures change hands,
-- structures on land that becomes neutral are destroyed.
function BuildingService.onOwnerChanged(cell, old, new)
	local b = buildings[cell]
	if not b then return end
	if new <= 0 then
		BuildingService.destroy(cell)
		return
	end
	account(b.owner, b.kind, -1)
	b.owner = new
	account(new, b.kind, 1)
	changes[cell] = { b.kind, new }
	if b.kind == "port" then ctx.Naval.onPortLost(cell) end
end

function BuildingService.drainChanges()
	if next(changes) == nil then return nil end
	local out = {}
	for cell, v in pairs(changes) do
		out[#out + 1] = { cell, v and v[1] or false, v and v[2] or 0 }
	end
	changes = {}
	return out
end

function BuildingService.snapshot()
	local out = {}
	for cell, b in pairs(buildings) do
		out[#out + 1] = { cell, b.kind, b.owner }
	end
	return out
end

function BuildingService.ofKind(nid, kind)
	local list = {}
	if BuildingService.count(nid, kind) <= 0 then return list end
	for cell, b in pairs(buildings) do
		if b.owner == nid and b.kind == kind then list[#list + 1] = b end
	end
	return list
end

return BuildingService
