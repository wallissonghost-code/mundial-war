-- Mundial War · strategic weapons (air strike, cluster, EMP, atomic, hydrogen), fired from
-- air bases or silos and possibly intercepted by air defence.
local StrategicService = {}

local ctx, Config, Map, Territory
local missiles = {}
local nextId = 1

function StrategicService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
end

function StrategicService.reset()
	missiles, nextId = {}, 1
end

function StrategicService.missiles()
	return missiles
end

-- Nearest ready launcher of the right kind (and level) that reaches the target.
local function pickLauncher(nid, weapon, target)
	local best, bestD = nil, math.huge
	local now = ctx.now()
	local why = "Aguarde a recarga do lançador."
	for _, b in ipairs(ctx.Buildings.ofKind(nid, weapon.launcher)) do
		if not b.active then
			why = "Seu lançador está desligado por um EMP."
		elseif weapon.minLevel and b.level < weapon.minLevel then
			why = "Requer " .. Config.Buildings[weapon.launcher].name .. " nível " .. weapon.minLevel .. "."
		elseif b.readyAt <= now then
			local d = Map:distance(b.cell, target)
			local range = ctx.Buildings.stat(b, "range")
			if range and d > range then
				why = "Alvo fora do alcance da base aérea (" .. math.floor(range) .. " células)."
			elseif d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best, bestD, why
end

function StrategicService.launch(nid, cell, kind)
	local weapon = Config.Weapons[kind]
	local n = ctx.Nations.get(nid)
	if not weapon then return false, "Arma inválida." end
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not Map:valid(cell) then return false, "Alvo inválido." end
	local owner = Territory.ownerOf(cell)
	if owner == nid then return false, "Esse alvo é seu." end
	if owner > 0 and ctx.Diplomacy.allied(nid, owner) then return false, "Não é possível atacar um aliado." end
	if kind == "airstrike" and owner <= 0 then return false, "Ataque aéreo precisa de um alvo inimigo." end
	if ctx.Buildings.count(nid, weapon.launcher) <= 0 then
		return false, "Requer " .. Config.Buildings[weapon.launcher].name .. "."
	end
	local launcher, distance, why = pickLauncher(nid, weapon, cell)
	if not launcher then return false, why end
	if n.gold < weapon.gold then return false, weapon.name .. " custa " .. weapon.gold .. " de ouro." end
	n.gold = n.gold - weapon.gold
	local factor = ctx.Buildings.stat(launcher, "cooldownFactor") or 1
	launcher.readyAt = ctx.now() + weapon.cooldown * factor
	if owner > 0 then ctx.Diplomacy.ensureWar(nid, owner) end
	local m = {
		id = nextId, kind = kind, nation = nid, from = launcher.cell, to = cell,
		progress = 0, distance = math.max(1, distance), speed = weapon.speed,
	}
	nextId = nextId + 1
	missiles[#missiles + 1] = m
	ctx.emit(nil, { k = ctx.Protocol.Events.Impact, launch = { m.id, kind, nid, m.from, m.to, m.speed } })
	if owner > 0 then
		ctx.notify(owner, weapon.icon .. " " .. weapon.name .. " de " .. n.name .. " a caminho!", "war")
	end
	return true, weapon.name .. " lançada."
end

-- Kept for older callers: the atomic bomb and the air strike.
function StrategicService.launchNuke(nid, cell) return StrategicService.launch(nid, cell, "atomic") end
function StrategicService.launchAirstrike(nid, cell) return StrategicService.launch(nid, cell, "airstrike") end

local function intercepted(m)
	local owner = Territory.ownerOf(m.to)
	if owner <= 0 then return false end
	local defenders = ctx.Diplomacy.allies(owner)
	defenders[#defenders + 1] = owner
	local isDefender = {}
	for _, d in ipairs(defenders) do isDefender[d] = true end
	local hit = false
	local tx, ty = Map:xy(m.to)
	ctx.Buildings.near(m.to, ctx.Stats.maxStat(Config, "airdefense", "radius"), function(b)
		if b.kind == "airdefense" and b.active and isDefender[b.owner] and b.owner ~= m.nation then
			local r = ctx.Buildings.stat(b, "radius")
			local bx, by = Map:xy(b.cell)
			if (bx - tx) ^ 2 + (by - ty) ^ 2 <= r * r and ctx.random() < ctx.Buildings.stat(b, "intercept") then
				hit = true
				return true
			end
		end
	end)
	return hit
end

local function impact(m)
	local w = Config.Weapons[m.kind]
	local radius = w.radius
	-- structures
	local struck = {}
	ctx.Buildings.near(m.to, radius, function(b)
		if b.owner ~= m.nation and not ctx.Diplomacy.allied(m.nation, b.owner) then struck[#struck + 1] = b.cell end
	end)
	for _, cell in ipairs(struck) do
		if w.destroys then
			ctx.Buildings.destroy(cell)
		elseif w.disable then
			ctx.Buildings.disable(cell, ctx.now() + w.disable)
		end
	end
	-- troops
	if w.troopKill then
		local hits, fallout = {}, {}
		Map:disc(m.to, radius, function(i)
			local o = Territory.ownerOf(i)
			if o > 0 and o ~= m.nation and not ctx.Diplomacy.allied(m.nation, o) then
				hits[o] = (hits[o] or 0) + 1
				if w.fallout and Map:distance(i, m.to) <= w.fallout then fallout[#fallout + 1] = i end
			end
		end)
		for o, count in pairs(hits) do
			local victim = ctx.Nations.get(o)
			if victim then
				local density = victim.troops / math.max(1, victim.land)
				victim.troops = math.max(0, victim.troops - density * count * w.troopKill)
				ctx.notify(o, w.icon .. " " .. w.name .. " atingiu seu território!", "war")
			end
		end
		for _, i in ipairs(fallout) do Territory.setOwner(i, 0) end
		for _, o in ipairs(ctx.Expansion.activeOrders()) do
			if o.front and o.nation ~= m.nation and Map:distance(o.front, m.to) <= radius then
				o.troops = o.troops * (w.fallout and 0.2 or 0.5)
			end
		end
	elseif w.troopShare then
		local o = Territory.ownerOf(m.to)
		local victim = o > 0 and ctx.Nations.get(o)
		if victim then victim.troops = victim.troops * (1 - w.troopShare) end
	end
	if w.disable then
		local o = Territory.ownerOf(m.to)
		if o > 0 then ctx.notify(o, "⚡ EMP: construções desligadas por " .. w.disable .. " s.", "war") end
	end
end

function StrategicService.tick(dt)
	if not ctx.Match.isPlaying() then return end
	local k = 1
	for i = 1, #missiles do
		local m = missiles[i]
		m.progress = m.progress + m.speed * dt
		if m.progress >= m.distance then
			local stopped = intercepted(m)
			if stopped then
				ctx.notify(m.nation, "Seu ataque foi interceptado pela defesa antiaérea.", "bad")
			else
				impact(m)
			end
			ctx.emit(nil, { k = ctx.Protocol.Events.Impact, hit = { m.id, m.kind, m.to, stopped } })
		else
			missiles[k] = m
			k = k + 1
		end
	end
	for i = k, #missiles do missiles[i] = nil end
end

function StrategicService.snapshot()
	local out = {}
	for _, m in ipairs(missiles) do
		out[#out + 1] = { m.id, m.kind, m.nation, m.from, m.to, m.speed, m.progress }
	end
	return out
end

return StrategicService
