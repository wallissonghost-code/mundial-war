-- Mundial War · ports, troop transports across water, defence boats, amphibious landings.
local NavalService = {}

local ctx, Config, Map, Territory
local fleets = {}        -- list of { id, nation, troops, path, progress, target }
local boats = {}         -- list of { id, nation, port, level, x, y, hp, center, path, step, waypoint }
local cargos = {}        -- list of { id, nation, port, path, progress, value }
local portTimers = {}    -- port cell -> next time it sends a cargo ship
local cargoClock = 0
local waterBody = nil    -- cell -> connected water body id
local nextId = 1
local visit, prev, vstamp = {}, {}, 0
local nb = {}

function NavalService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
	-- connected water bodies, so a boat is only sent where it can actually sail
	waterBody = {}
	local id, scratch = 0, {}
	for start = 1, Map.N do
		if not Map.land[start] and not waterBody[start] then
			id = id + 1
			local queue, head = { start }, 1
			waterBody[start] = id
			while head <= #queue do
				local i = queue[head]
				head = head + 1
				local n = Map:neighbors(i, scratch)
				for k = 1, n do
					local j = scratch[k]
					if not Map.land[j] and not waterBody[j] then
						waterBody[j] = id
						queue[#queue + 1] = j
					end
				end
			end
		end
	end
end

function NavalService.reset()
	fleets, boats, cargos, portTimers, nextId, cargoClock = {}, {}, {}, {}, 1, 0
end

function NavalService.cargos()
	return cargos
end

function NavalService.fleets()
	return fleets
end

function NavalService.boats()
	return boats
end

local function waterNeighbor(cell)
	local n = Map:neighbors(cell, nb)
	for k = 1, n do
		if not Map.land[nb[k]] then return nb[k] end
	end
	return nil
end

-- Breadth-first search over water from the target shore back to any of the nation's ports.
-- Returns the water path ordered port -> target, or nil.
function NavalService.route(nid, targetCell, limit)
	local ports = ctx.Buildings.ofKind(nid, "port")
	if #ports == 0 then return nil, "Construa um porto no litoral primeiro." end
	vstamp = vstamp + 1
	local goal = {}
	for _, p in ipairs(ports) do
		local n = Map:neighbors(p.cell, nb)
		for k = 1, n do
			if not Map.land[nb[k]] then goal[nb[k]] = true end
		end
	end
	local queue, head = {}, 1
	local n = Map:neighbors(targetCell, nb)
	for k = 1, n do
		local j = nb[k]
		if not Map.land[j] and visit[j] ~= vstamp then
			visit[j] = vstamp
			prev[j] = 0
			queue[#queue + 1] = j
		end
	end
	local scratch = {}
	while head <= #queue do
		if limit and head > limit then break end
		local i = queue[head]
		head = head + 1
		if goal[i] then
			local path = {}
			while i ~= 0 do
				path[#path + 1] = i
				i = prev[i]
			end
			return path
		end
		local m = Map:neighbors(i, scratch)
		for k = 1, m do
			local j = scratch[k]
			if not Map.land[j] and visit[j] ~= vstamp then
				visit[j] = vstamp
				prev[j] = i
				queue[#queue + 1] = j
			end
		end
	end
	return nil, "Nenhuma rota marítima a partir dos seus portos."
end

function NavalService.launch(nid, cell, percent, searchLimit)
	local N = Config.Naval
	local n = ctx.Nations.get(nid)
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	if not Map:valid(cell) or not Map.land[cell] then return false, "Escolha uma costa como destino." end
	if not Map.coast[cell] then return false, "O desembarque precisa ser numa célula de litoral." end
	if type(percent) ~= "number" or percent ~= percent or percent < 0.01 or percent > 1 then
		return false, "Percentual inválido."
	end
	local owner = Territory.ownerOf(cell)
	if owner == nid then return false, "Essa costa já é sua." end
	if owner > 0 and not ctx.Diplomacy.canAttack(nid, owner) then return false, "Não é possível invadir um aliado." end
	local active = 0
	for _, f in ipairs(fleets) do
		if f.nation == nid then active = active + 1 end
	end
	if active >= N.MaxFleetsPerNation then return false, "Limite de frotas em viagem atingido." end
	local troops = math.floor(n.troops * percent)
	if troops < N.MinTroops then return false, "A frota precisa de pelo menos " .. N.MinTroops .. " tropas." end
	if n.gold < N.TransportGold then return false, "Transporte custa " .. N.TransportGold .. " de ouro." end
	local path, why = NavalService.route(nid, cell, searchLimit)
	if not path then return false, why end
	n.gold = n.gold - N.TransportGold
	n.troops = n.troops - troops
	if owner > 0 then ctx.Diplomacy.ensureWar(nid, owner) end
	local fleet = { id = nextId, nation = nid, troops = troops, path = path, progress = 1, target = cell }
	nextId = nextId + 1
	fleets[#fleets + 1] = fleet
	ctx.emit(nil, { k = ctx.Protocol.Events.Orders, fleet = { fleet.id, nid, troops, path, N.Speed, cell } })
	return true, "Frota a caminho com " .. troops .. " tropas."
end

local function boatCell(b)
	return Map:index(math.floor(b.x), math.floor(b.y))
end

-- Water path between two water cells (BFS, nil when not connected).
local function waterPath(from, to)
	if waterBody[from] ~= waterBody[to] then return nil end
	vstamp = vstamp + 1
	local queue, head = { from }, 1
	visit[from] = vstamp
	prev[from] = 0
	local scratch = {}
	while head <= #queue do
		local i = queue[head]
		head = head + 1
		if i == to then
			local rev = {}
			while i ~= 0 do rev[#rev + 1] = i i = prev[i] end
			local path = {}
			for k = #rev, 1, -1 do path[#path + 1] = rev[k] end
			return path
		end
		local m = Map:neighbors(i, scratch)
		for k = 1, m do
			local j = scratch[k]
			if not Map.land[j] and visit[j] ~= vstamp then
				visit[j] = vstamp
				prev[j] = i
				queue[#queue + 1] = j
			end
		end
	end
	return nil
end

function NavalService.boatsAt(portCell)
	local c = 0
	for _, b in ipairs(boats) do if b.port == portCell then c = c + 1 end end
	return c
end

-- Defence boat: bought at one of your ports; patrols around that port until you send it elsewhere.
-- Air bridge: troops fly in a straight line from an air base, ignoring water.
function NavalService.launchAir(nid, fromCell, targetCell, troops)
	local ax, ay = Map:xy(fromCell)
	local bx, by = Map:xy(targetCell)
	local steps = math.max(1, math.floor(math.max(math.abs(bx - ax), math.abs(by - ay))))
	local path = {}
	for k = 0, steps do
		local t = k / steps
		path[#path + 1] = Map:index(math.floor(ax + (bx - ax) * t + 0.5), math.floor(ay + (by - ay) * t + 0.5))
	end
	local fleet = { id = nextId, nation = nid, troops = troops, path = path, progress = 1, target = targetCell,
		air = true, speed = Config.Naval.AirliftSpeed }
	nextId = nextId + 1
	fleets[#fleets + 1] = fleet
	local owner = Territory.ownerOf(targetCell)
	if owner > 0 then ctx.Diplomacy.ensureWar(nid, owner) end
	ctx.emit(nil, { k = ctx.Protocol.Events.Orders, fleet = { fleet.id, nid, troops, path, fleet.speed, targetCell, true } })
	return fleet
end

function NavalService.buyBoat(nid, portCell)
	local N = Config.Naval
	local n = ctx.Nations.get(nid)
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	local port = ctx.Buildings.at(portCell)
	if not port or port.kind ~= "port" or port.owner ~= nid then return false, "Selecione um porto seu." end
	local limit = ctx.Buildings.stat(port, "boats")
	if NavalService.boatsAt(portCell) >= limit then return false, "Este porto já tem " .. limit .. " barcos. Melhore o porto para ter mais." end
	if n.gold < N.BoatGold then return false, "Barco de defesa custa " .. N.BoatGold .. " de ouro." end
	local water = waterNeighbor(portCell)
	if not water then return false, "Porto sem acesso à água." end
	n.gold = n.gold - N.BoatGold
	local x, y = Map:xy(water)
	boats[#boats + 1] = {
		id = nextId, nation = nid, port = portCell, level = port.level, x = x + 0.5, y = y + 0.5,
		hp = N.BoatHealth, center = water, path = nil, step = 1, waypoint = nil,
	}
	nextId = nextId + 1
	return true, "Barco de defesa lançado. Clique nele e depois na água para escolher onde patrulhar."
end

function NavalService.patrol(nid, boatId, cell)
	if not Map:valid(cell) or Map.land[cell] then return false, "Escolha um ponto na água." end
	for _, b in ipairs(boats) do
		if b.id == boatId then
			if b.nation ~= nid then return false, "Esse barco não é seu." end
			local here = boatCell(b)
			local path = here and waterPath(here, cell)
			if not path then return false, "O barco não alcança esse ponto por água." end
			b.center, b.path, b.step, b.waypoint = cell, path, 1, nil
			return true, "Barco a caminho da nova patrulha."
		end
	end
	return false, "Barco não encontrado."
end

function NavalService.onPortLost(portCell)
	-- boats already at sea keep fighting for their nation; the port just stops building more
end

function NavalService.removeNation(nid)
	local k = 1
	for i = 1, #fleets do
		if fleets[i].nation ~= nid then fleets[k] = fleets[i] k = k + 1 end
	end
	for i = k, #fleets do fleets[i] = nil end
	k = 1
	for i = 1, #boats do
		if boats[i].nation ~= nid then boats[k] = boats[i] k = k + 1 end
	end
	for i = k, #boats do boats[i] = nil end
	k = 1
	for i = 1, #cargos do
		if cargos[i].nation ~= nid then cargos[k] = cargos[i] k = k + 1 end
	end
	for i = k, #cargos do cargos[i] = nil end
end

local function boatRange(b) return Config.Naval.BoatRange + (b.level - 1) end
local function boatDamage(b) return Config.Naval.BoatDamage + 4 * (b.level - 1) end

local function moveBoat(b, dt)
	local N = Config.Naval
	local tx, ty
	if b.path and b.step <= #b.path then
		local x, y = Map:xy(b.path[b.step])
		tx, ty = x + 0.5, y + 0.5
	else
		b.path = nil
		if not b.waypoint then
			-- pick a nearby water cell on the patrol circle
			local cx, cy = Map:xy(b.center)
			for _ = 1, 8 do
				local a = ctx.random() * math.pi * 2
				local r = N.BoatOrbit * (0.5 + ctx.random() * 0.5)
				local c = Map:index(math.floor(cx + 0.5 + math.cos(a) * r), math.floor(cy + 0.5 + math.sin(a) * r))
				if c and not Map.land[c] and waterBody[c] == waterBody[b.center] then b.waypoint = c break end
			end
			b.waypoint = b.waypoint or b.center
		end
		local x, y = Map:xy(b.waypoint)
		tx, ty = x + 0.5, y + 0.5
	end
	local dx, dy = tx - b.x, ty - b.y
	local d = math.sqrt(dx * dx + dy * dy)
	local stepLen = N.BoatSpeed * dt
	if d <= stepLen then
		b.x, b.y = tx, ty
		if b.path then b.step = b.step + 1 else b.waypoint = nil end
	else
		b.x, b.y = b.x + dx / d * stepLen, b.y + dy / d * stepLen
	end
end

-- Boats fight enemy boats, wear down enemy transports and raid gold from enemy ports in reach.
-- Boats fight enemy boats (every tick) and, once per second, wear down transports, raid
-- enemy ports and take fire from anti-naval batteries. The slow checks run on a 1 s pulse
-- against short lists (ports, batteries) instead of a spatial query per boat per tick.
local slowPulse = 0
local function boatCombat(dt)
	local N = Config.Naval
	local Diplomacy = ctx.Diplomacy
	for _, b in ipairs(boats) do
		local range = boatRange(b)
		local r2 = range * range
		local target, best = nil, math.huge
		for _, o in ipairs(boats) do
			if o.nation ~= b.nation and o.hp > 0 then
				local d = (o.x - b.x) ^ 2 + (o.y - b.y) ^ 2
				if d <= r2 and d < best and Diplomacy.relation(b.nation, o.nation) == "war" then target, best = o, d end
			end
		end
		if target then target.hp = target.hp - boatDamage(b) * dt end
	end
	slowPulse = slowPulse + dt
	if slowPulse >= 1 and #boats + #fleets > 0 then
		local step = slowPulse
		slowPulse = 0
		local ports, batteries = {}, {}
		for _, bld in pairs(ctx.Buildings.all()) do
			if bld.active then
				if bld.kind == "port" then
					local x, y = Map:xy(bld.cell)
					ports[#ports + 1] = { owner = bld.owner, x = x + 0.5, y = y + 0.5 }
				elseif bld.kind == "antinaval" then
					local x, y = Map:xy(bld.cell)
					local r = ctx.Buildings.stat(bld, "radius")
					batteries[#batteries + 1] = { owner = bld.owner, x = x + 0.5, y = y + 0.5, r2 = r * r, damage = ctx.Buildings.stat(bld, "damage") }
				end
			end
		end
		for _, b in ipairs(boats) do
			local range = boatRange(b)
			local r2 = range * range
			for _, f in ipairs(fleets) do
				if not f.air and f.nation ~= b.nation then
					local px, py = Map:xy(f.path[math.min(#f.path, math.floor(f.progress))])
					if (px + 0.5 - b.x) ^ 2 + (py + 0.5 - b.y) ^ 2 <= r2 and Diplomacy.relation(b.nation, f.nation) == "war" then
						f.troops = f.troops * (1 - N.BoatTransportDamage * step)
					end
				end
			end
			local owner = ctx.Nations.get(b.nation)
			for _, p in ipairs(ports) do
				if p.owner ~= b.nation and (p.x - b.x) ^ 2 + (p.y - b.y) ^ 2 <= r2 and Diplomacy.relation(b.nation, p.owner) == "war" then
					local victim = ctx.Nations.get(p.owner)
					if victim and owner then
						local take = math.min(victim.gold, N.BoatGoldSteal * step)
						victim.gold = victim.gold - take
						owner.gold = owner.gold + take
					end
				end
			end
			local dmg = 0
			for _, a in ipairs(batteries) do
				if a.owner ~= b.nation and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= a.r2 and Diplomacy.relation(a.owner, b.nation) == "war" then
					if a.damage > dmg then dmg = a.damage end
				end
			end
			if dmg > 0 then b.hp = b.hp - dmg * step end
		end
		if #batteries > 0 then
			for _, f in ipairs(fleets) do
				if not f.air then
					local px, py = Map:xy(f.path[math.min(#f.path, math.floor(f.progress))])
					for _, a in ipairs(batteries) do
						if a.owner ~= f.nation and (a.x - px - 0.5) ^ 2 + (a.y - py - 0.5) ^ 2 <= a.r2 and Diplomacy.relation(a.owner, f.nation) == "war" then
							f.troops = f.troops * (1 - N.BoatTransportDamage * step)
							break
						end
					end
				end
			end
		end
	end
	local k = 1
	for i = 1, #boats do
		local b = boats[i]
		if b.hp > 0 then
			boats[k] = b
			k = k + 1
		else
			ctx.notify(b.nation, "Um barco de defesa seu foi afundado.", "bad")
		end
	end
	for i = k, #boats do boats[i] = nil end
end

-- Trade run for a cargo ship: out to a water cell about CargoTripCells away and back.
local function tradeRoute(portCell)
	local start = waterNeighbor(portCell)
	if not start then return nil end
	local N = Config.Naval
	vstamp = vstamp + 1
	local queue, head = { start }, 1
	visit[start] = vstamp
	prev[start] = 0
	local far, farD = start, 0
	local sx, sy = Map:xy(start)
	local scratch = {}
	local limit = math.floor(math.pi * N.CargoTripCells * N.CargoTripCells)
	while head <= #queue and #queue < limit do
		local i = queue[head]
		head = head + 1
		local x, y = Map:xy(i)
		local d = (x - sx) ^ 2 + (y - sy) ^ 2
		if d > farD and ctx.random() < 0.6 then far, farD = i, d end
		local m = Map:neighbors(i, scratch)
		for k = 1, m do
			local j = scratch[k]
			if not Map.land[j] and visit[j] ~= vstamp then
				visit[j] = vstamp
				prev[j] = i
				queue[#queue + 1] = j
			end
		end
	end
	if far == start then return nil end
	local back = {}
	local i = far
	while i ~= 0 do back[#back + 1] = i i = prev[i] end
	local path = {}
	for k = #back, 1, -1 do path[#path + 1] = back[k] end      -- port -> far
	for k = 2, #back do path[#path + 1] = back[k] end          -- far -> port
	return path
end

local capturePulse = 0
local NO_BOATS = {}
local function cargoTick(dt)
	local N = Config.Naval
	cargoClock = cargoClock + dt
	if cargoClock >= 1 then
		cargoClock = 0
		local now = ctx.now()
		local atSea = {}
		for _, c in ipairs(cargos) do atSea[c.port] = (atSea[c.port] or 0) + 1 end
		for cell, b in pairs(ctx.Buildings.all()) do
			if b.kind == "port" and b.active and b.owner > 0 then
				local nextAt = portTimers[cell]
				if not nextAt then
					portTimers[cell] = now + N.CargoInterval * (0.3 + ctx.random() * 0.7)
				elseif now >= nextAt and (atSea[cell] or 0) < b.level * N.CargoPerPortLevel then
					portTimers[cell] = now + N.CargoInterval
					local path = tradeRoute(cell)
					if path then
						cargos[#cargos + 1] = { id = nextId, nation = b.owner, port = cell, path = path, progress = 1,
							value = N.CargoValue + N.CargoValuePerLevel * (b.level - 1) }
						nextId = nextId + 1
					end
				end
			end
		end
	end
	local k = 1
	capturePulse = capturePulse + dt
	local checkCaptures = capturePulse >= 0.5 and #boats > 0
	if capturePulse >= 0.5 then capturePulse = 0 end
	for i = 1, #cargos do
		local c = cargos[i]
		local keep = ctx.Nations.alive(c.nation)
		if keep then
			c.progress = c.progress + N.CargoSpeed * dt
			local pos = c.path[math.min(#c.path, math.floor(c.progress))]
			local px, py = Map:xy(pos)
			-- an enemy defence boat in reach captures the cargo (checked twice a second)
			for _, b in ipairs(checkCaptures and boats or NO_BOATS) do
				if b.nation ~= c.nation and ctx.Diplomacy.relation(b.nation, c.nation) == "war" then
					local r = boatRange(b)
					if (px + 0.5 - b.x) ^ 2 + (py + 0.5 - b.y) ^ 2 <= r * r then
						local captor = ctx.Nations.get(b.nation)
						local prize = math.floor(c.value * N.CargoCaptureFactor)
						if captor then captor.gold = captor.gold + prize end
						ctx.notify(b.nation, "💰 Navio de carga capturado: +" .. prize .. " de ouro.", "good")
						ctx.notify(c.nation, "Um navio de carga seu foi capturado.", "bad")
						keep = false
						break
					end
				end
			end
			if keep and c.progress >= #c.path then
				local n = ctx.Nations.get(c.nation)
				local port = ctx.Buildings.at(c.port)
				if n and port and port.owner == c.nation then n.gold = n.gold + c.value end
				keep = false
			end
		end
		if keep then
			cargos[k] = c
			k = k + 1
		end
	end
	for i = k, #cargos do cargos[i] = nil end
end

-- Cargo rows for clients: { id, nation, cell }
function NavalService.cargoView()
	local out = {}
	for _, c in ipairs(cargos) do
		out[#out + 1] = { c.id, c.nation, c.path[math.min(#c.path, math.floor(c.progress))] }
	end
	return out
end

local function land(f)
	local C = Config.Combat
	local n = ctx.Nations.get(f.nation)
	local owner = Territory.ownerOf(f.target)
	if owner == f.nation then
		n.troops = n.troops + f.troops
		return
	end
	if owner > 0 and not ctx.Diplomacy.canAttack(f.nation, owner) then
		n.troops = n.troops + f.troops
		ctx.notify(f.nation, "A frota voltou: o destino virou aliado.", "info")
		return
	end
	local cost, loss = ctx.Combat.cellCost(f.nation, f.target, f.troops, nil)
	cost = cost * C.LandingCostFactor
	if owner > 0 and not f.air then
		local battery = ctx.Buildings.covered(f.target, "antinaval", owner, "landing")
		if battery then cost = cost * battery end
	end
	if f.troops >= cost then
		if owner > 0 then
			local d = ctx.Nations.get(owner)
			d.troops = math.max(0, d.troops - loss)
			ctx.notify(owner, n.name .. (f.air and " lançou paraquedistas no seu território!" or " desembarcou no seu litoral!"), "war")
		end
		Territory.setOwner(f.target, f.nation)
		local remaining = math.floor(f.troops - cost)
		if remaining >= Config.Expansion.MinTroopsToSend then
			ctx.Expansion.start(f.nation, owner, f.target, remaining)
		elseif remaining > 0 then
			n.troops = n.troops + remaining
		end
		ctx.notify(f.nation, "Desembarque concluído.", "good")
	else
		if owner > 0 then
			local d = ctx.Nations.get(owner)
			d.troops = math.max(0, d.troops - f.troops * C.MinFailedLandingDamage)
		end
		ctx.notify(f.nation, "O desembarque fracassou: a defesa era forte demais.", "bad")
	end
end

function NavalService.tick(dt)
	if not ctx.Match.isPlaying() then return end
	local N = Config.Naval
	local k = 1
	for i = 1, #fleets do
		local f = fleets[i]
		local n = ctx.Nations.get(f.nation)
		local keep = n ~= nil and n.alive
		if keep then
			f.progress = f.progress + (f.speed or N.Speed) * dt
			if f.troops < 1 then
				ctx.notify(f.nation, "Sua frota foi afundada.", "bad")
				keep = false
			elseif f.progress >= #f.path then
				if f.air and ctx.Strategic.intercepts(f.nation, f.target, true) then
					f.troops = f.troops * (1 - N.AirliftInterceptLoss)
					ctx.notify(f.nation, "A antiaérea inimiga atingiu sua ponte aérea.", "bad")
				end
				land(f)
				keep = false
			end
		end
		if keep then
			fleets[k] = f
			k = k + 1
		else
			ctx.emit(nil, { k = ctx.Protocol.Events.Orders, fleetEnd = f.id })
		end
	end
	for i = k, #fleets do fleets[i] = nil end
	for _, b in ipairs(boats) do
		if ctx.Nations.alive(b.nation) then moveBoat(b, dt) end
	end
	boatCombat(dt)
	cargoTick(dt)
end

-- Boat rows for clients: { id, nation, x, y, health, patrolCell, level }
function NavalService.boatView()
	local out = {}
	for _, b in ipairs(boats) do
		out[#out + 1] = { b.id, b.nation, math.floor(b.x * 10) / 10, math.floor(b.y * 10) / 10, math.floor(b.hp), b.center, b.level }
	end
	return out
end

function NavalService.publicView()
	local out = {}
	for _, f in ipairs(fleets) do
		out[#out + 1] = { f.id, f.nation, math.floor(f.troops), f.progress }
	end
	return out
end

function NavalService.snapshot()
	local fl, ws = {}, {}
	for _, f in ipairs(fleets) do
		fl[#fl + 1] = { f.id, f.nation, math.floor(f.troops), f.path, f.speed or Config.Naval.Speed, f.target, f.progress, f.air == true }
	end
	return fl, NavalService.boatView()
end

return NavalService
