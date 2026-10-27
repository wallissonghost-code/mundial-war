-- Mundial War · nuclear missiles (silo) and air strikes (air base), intercepted by air defence.
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

local function pickLauncher(nid, kind, target, range)
	local best, bestD = nil, math.huge
	local now = ctx.now()
	local anyReady = false
	for _, b in ipairs(ctx.Buildings.ofKind(nid, kind)) do
		if b.readyAt <= now then
			anyReady = true
			local d = Map:distance(b.cell, target)
			if (not range or d <= range) and d < bestD then best, bestD = b, d end
		end
	end
	return best, bestD, anyReady
end

local function validTarget(nid, cell)
	if not Map:valid(cell) then return false, "Alvo inválido." end
	local owner = Territory.ownerOf(cell)
	if owner == nid then return false, "Esse alvo é seu." end
	if owner > 0 and ctx.Diplomacy.allied(nid, owner) then return false, "Não é possível atacar um aliado." end
	return true, owner
end

local function launch(nid, kind, cell)
	local S = Config.Strategic
	local n = ctx.Nations.get(nid)
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	local ok, ownerOrWhy = validTarget(nid, cell)
	if not ok then return false, ownerOrWhy end
	local owner = ownerOrWhy
	local isNuke = kind == "nuke"
	local launcherKind = isNuke and "silo" or "airfield"
	local gold = isNuke and S.NukeGold or S.AirstrikeGold
	if ctx.Buildings.count(nid, launcherKind) <= 0 then
		return false, "Requer " .. Config.Buildings[launcherKind].name .. "."
	end
	if not isNuke and owner <= 0 then return false, "Bombardeio aéreo precisa de um alvo inimigo." end
	local launcher, distance, anyReady = pickLauncher(nid, launcherKind, cell, (not isNuke) and Config.Buildings.airfield.range or nil)
	if not launcher then
		if anyReady then return false, "Alvo fora do alcance da base aérea." end
		return false, "Aguarde a recarga do lançador."
	end
	if n.gold < gold then return false, "Custa " .. gold .. " de ouro." end
	n.gold = n.gold - gold
	launcher.readyAt = ctx.now() + (isNuke and S.NukeCooldown or S.AirstrikeCooldown)
	if owner > 0 then ctx.Diplomacy.ensureWar(nid, owner) end
	local m = {
		id = nextId, kind = kind, nation = nid, from = launcher.cell, to = cell,
		progress = 0, distance = math.max(1, distance), speed = isNuke and S.NukeSpeed or S.AirstrikeSpeed,
	}
	nextId = nextId + 1
	missiles[#missiles + 1] = m
	ctx.emit(nil, { k = ctx.Protocol.Events.Impact, launch = { m.id, kind, nid, m.from, m.to, m.speed } })
	if owner > 0 then
		ctx.notify(owner, (isNuke and "☢ Míssil nuclear" or "✈ Ataque aéreo") .. " de " .. n.name .. " a caminho!", "war")
	end
	return true, isNuke and "Míssil nuclear lançado." or "Ataque aéreo a caminho."
end

function StrategicService.launchNuke(nid, cell)
	return launch(nid, "nuke", cell)
end

function StrategicService.launchAirstrike(nid, cell)
	return launch(nid, "airstrike", cell)
end

local function intercepted(m)
	local owner = Territory.ownerOf(m.to)
	if owner <= 0 then return false end
	local defenders = ctx.Diplomacy.allies(owner)
	defenders[#defenders + 1] = owner
	local isDefender = {}
	for _, d in ipairs(defenders) do isDefender[d] = true end
	local def = Config.Buildings.airdefense
	local hit = false
	ctx.Buildings.near(m.to, def.radius, function(b)
		if b.kind == "airdefense" and isDefender[b.owner] and b.owner ~= m.nation then
			if ctx.random() < def.intercept then
				hit = true
				return true
			end
		end
	end)
	return hit
end

local function impact(m)
	local S = Config.Strategic
	local radius = m.kind == "nuke" and S.NukeRadius or S.AirstrikeRadius
	local destroyed = {}
	ctx.Buildings.near(m.to, radius, function(b)
		if b.owner ~= m.nation and not ctx.Diplomacy.allied(m.nation, b.owner) then
			destroyed[#destroyed + 1] = b.cell
		end
	end)
	for _, cell in ipairs(destroyed) do ctx.Buildings.destroy(cell) end
	if m.kind == "nuke" then
		local hits = {}
		local fallout = {}
		Map:disc(m.to, S.NukeRadius, function(i)
			local o = Territory.ownerOf(i)
			if o > 0 and o ~= m.nation then
				hits[o] = (hits[o] or 0) + 1
				if Map:distance(i, m.to) <= S.NukeFalloutRadius then fallout[#fallout + 1] = i end
			end
		end)
		for o, count in pairs(hits) do
			local victim = ctx.Nations.get(o)
			if victim then
				local density = victim.troops / math.max(1, victim.land)
				victim.troops = math.max(0, victim.troops - density * count * 2)
				ctx.notify(o, "☢ Ataque nuclear em seu território!", "war")
			end
		end
		for _, i in ipairs(fallout) do Territory.setOwner(i, 0) end
		-- fronts passing through the blast are wiped out
		for _, o in ipairs(ctx.Expansion.activeOrders()) do
			if o.front and o.nation ~= m.nation and Map:distance(o.front, m.to) <= S.NukeRadius then
				o.troops = o.troops * 0.2
			end
		end
	else
		local o = Territory.ownerOf(m.to)
		local victim = o > 0 and ctx.Nations.get(o)
		if victim then victim.troops = victim.troops * (1 - S.AirstrikeTroopDamage) end
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
