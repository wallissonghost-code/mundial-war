-- Mundial War · strategic weapons fired from air bases or silos: air strike, cluster, fire
-- bomb, EMP, atomic, hydrogen, End of an Era (multiple warheads) and the air bridge.
-- Air defence stops missiles and aircraft; the flak building stops aircraft only; nothing
-- stops the End of an Era.
local StrategicService = {}

local ctx, Config, Map, Territory
local missiles = {}
local fires = {}         -- { id, nation, center, radius, max, grow, endsAt, troopBurn, pulse }
local nextId = 1

function StrategicService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
end

function StrategicService.reset()
	missiles, fires, nextId = {}, {}, 1
end

function StrategicService.fires()
	return fires
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

local function addMissile(nid, kind, from, to, speed)
	local m = { id = nextId, kind = kind, nation = nid, from = from, to = to, progress = 0,
		distance = math.max(1, Map:distance(from, to)), speed = speed }
	nextId = nextId + 1
	missiles[#missiles + 1] = m
	ctx.emit(nil, { k = ctx.Protocol.Events.Impact, launch = { m.id, kind, nid, m.from, m.to, m.speed } })
	return m
end

-- End of an Era: besides the chosen target, the capitals of up to (warheads-1) other
-- nations at war with the launcher, nearest first.
local function extraTargets(nid, cell, count, skip)
	local list = {}
	for id, other in pairs(ctx.Nations.all()) do
		if other.alive and id ~= nid and id ~= skip and ctx.Diplomacy.relation(nid, id) == "war"
			and Territory.ownerOf(other.capital) == id then
			list[#list + 1] = { cell = other.capital, d = Map:distance(other.capital, cell) }
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local out = {}
	for k = 1, math.min(count, #list) do out[k] = list[k].cell end
	return out
end

function StrategicService.launch(nid, cell, kind, percent)
	local weapon = Config.Weapons[kind]
	local n = ctx.Nations.get(nid)
	if not weapon then return false, "Arma inválida." end
	if weapon.mode and weapon.mode ~= ctx.mode then return false, weapon.name .. " só existe na Conquista Extrema." end
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not Map:valid(cell) then return false, "Alvo inválido." end
	local owner = Territory.ownerOf(cell)
	if owner == nid then return false, "Esse alvo é seu." end
	if owner > 0 and ctx.Diplomacy.allied(nid, owner) then return false, "Não é possível atacar um aliado." end
	if kind == "airstrike" and owner <= 0 then return false, "Ataque aéreo precisa de um alvo inimigo." end
	if weapon.troops and owner == -1 then return false, "As tropas precisam pousar em terra." end
	if ctx.Buildings.count(nid, weapon.launcher) <= 0 then
		return false, "Requer " .. Config.Buildings[weapon.launcher].name .. "."
	end
	local launcher, distance, why = pickLauncher(nid, weapon, cell)
	if not launcher then return false, why end
	local oil = ctx.mode == "extreme" and weapon.oil or 0
	if n.gold < weapon.gold then return false, weapon.name .. " custa " .. weapon.gold .. " de ouro." end
	if oil > 0 and (n.oil or 0) < oil then return false, weapon.name .. " precisa de " .. oil .. " de petróleo." end
	local troops = 0
	if weapon.troops then
		if type(percent) ~= "number" or percent ~= percent or percent < 0.01 or percent > 1 then return false, "Percentual inválido." end
		local N = Config.Naval
		local cap = N.AirliftMaxTroops + N.AirliftMaxPerLevel * (launcher.level - 1)
		troops = math.min(cap, math.floor(n.troops * percent))
		if troops < N.MinTroops then return false, "A ponte aérea precisa de pelo menos " .. N.MinTroops .. " tropas." end
	end
	n.gold = n.gold - weapon.gold
	if oil > 0 then n.oil = n.oil - oil end
	local factor = ctx.Buildings.stat(launcher, "cooldownFactor") or 1
	launcher.readyAt = ctx.now() + weapon.cooldown * factor
	if weapon.troops then
		n.troops = n.troops - troops
		ctx.Naval.launchAir(nid, launcher.cell, cell, troops)
		return true, "Ponte aérea: " .. troops .. " tropas a caminho."
	end
	if owner > 0 then ctx.Diplomacy.ensureWar(nid, owner) end
	addMissile(nid, kind, launcher.cell, cell, weapon.speed)
	if weapon.warheads then
		for _, extra in ipairs(extraTargets(nid, cell, weapon.warheads - 1, owner)) do
			addMissile(nid, kind, launcher.cell, extra, weapon.speed)
			local victim = Territory.ownerOf(extra)
			if victim > 0 then ctx.notify(victim, weapon.icon .. " " .. weapon.name .. " de " .. n.name .. " a caminho!", "war") end
		end
	end
	if owner > 0 then
		ctx.notify(owner, weapon.icon .. " " .. weapon.name .. " de " .. n.name .. " a caminho!", "war")
	end
	return true, weapon.name .. " lançada."
end

-- Kept for older callers: the atomic bomb and the air strike.
function StrategicService.launchNuke(nid, cell) return StrategicService.launch(nid, cell, "atomic") end
function StrategicService.launchAirstrike(nid, cell) return StrategicService.launch(nid, cell, "airstrike") end

-- Anti-air of the target's owner (and allies) may shoot it down: air defence stops missiles
-- and aircraft, flak stops aircraft only, the End of an Era cannot be stopped.
function StrategicService.intercepts(attacker, targetCell, aircraft)
	local owner = Territory.ownerOf(targetCell)
	if owner <= 0 then return false end
	local defenders = ctx.Diplomacy.allies(owner)
	defenders[#defenders + 1] = owner
	local isDefender = {}
	for _, d in ipairs(defenders) do isDefender[d] = true end
	local hit = false
	local tx, ty = Map:xy(targetCell)
	local reach = math.max(ctx.Stats.maxStat(Config, "airdefense", "radius"), ctx.Stats.maxStat(Config, "flak", "radius"))
	ctx.Buildings.near(targetCell, reach, function(b)
		if (b.kind == "airdefense" or (b.kind == "flak" and aircraft)) and b.active and isDefender[b.owner] and b.owner ~= attacker then
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

local function intercepted(m)
	local w = Config.Weapons[m.kind]
	if w.unstoppable then return false end
	return StrategicService.intercepts(m.nation, m.to, w.aircraft == true)
end

local function startFire(nid, cell, spec)
	fires[#fires + 1] = { id = nextId, nation = nid, center = cell, radius = 1, max = spec.radius, grow = spec.grow,
		endsAt = ctx.now() + spec.seconds, troopBurn = spec.troopBurn, pulse = 0 }
	nextId = nextId + 1
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
	if w.destroys and w.disable then
		-- End of an Era: the EMP ring reaches beyond the blast
		ctx.Buildings.near(m.to, radius * 1.6, function(b)
			if b.owner ~= m.nation and not ctx.Diplomacy.allied(m.nation, b.owner) then
				ctx.Buildings.disable(b.cell, ctx.now() + w.disable)
			end
		end)
	end
	if w.fire then startFire(m.nation, m.to, w.fire) end
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
	if w.fire then
		local o = Territory.ownerOf(m.to)
		if o > 0 then ctx.notify(o, "🔥 Incêndio no seu território!", "war") end
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
	-- fires spread slowly, burn troops every second and destroy structures they reach
	local now = ctx.now()
	k = 1
	for i = 1, #fires do
		local f = fires[i]
		f.radius = math.min(f.max, f.radius + f.grow * dt)
		f.pulse = f.pulse + dt
		if f.pulse >= 1 then
			f.pulse = f.pulse - 1
			local hits = {}
			Map:disc(f.center, f.radius, function(c)
				local o = Territory.ownerOf(c)
				if o > 0 and o ~= f.nation and not ctx.Diplomacy.allied(f.nation, o) then hits[o] = (hits[o] or 0) + 1 end
			end)
			for o, count in pairs(hits) do
				local victim = ctx.Nations.get(o)
				if victim then
					local density = victim.troops / math.max(1, victim.land)
					victim.troops = math.max(0, victim.troops - density * count * f.troopBurn)
				end
			end
			local burned = {}
			ctx.Buildings.near(f.center, f.radius, function(b)
				if b.owner ~= f.nation and not ctx.Diplomacy.allied(f.nation, b.owner) then burned[#burned + 1] = b.cell end
			end)
			for _, c in ipairs(burned) do ctx.Buildings.destroy(c) end
			for _, o in ipairs(ctx.Expansion.activeOrders()) do
				if o.front and o.nation ~= f.nation and Map:distance(o.front, f.center) <= f.radius then
					o.troops = o.troops * (1 - f.troopBurn * 0.5)
				end
			end
		end
		if now < f.endsAt then
			fires[k] = f
			k = k + 1
		end
	end
	for i = k, #fires do fires[i] = nil end
end

-- Fire rows for clients: { id, centerCell, radius }
function StrategicService.fireView()
	local out = {}
	for _, f in ipairs(fires) do out[#out + 1] = { f.id, f.center, math.floor(f.radius * 10) / 10 } end
	return out
end

function StrategicService.snapshot()
	local out = {}
	for _, m in ipairs(missiles) do
		out[#out + 1] = { m.id, m.kind, m.nation, m.from, m.to, m.speed, m.progress }
	end
	return out
end

return StrategicService
