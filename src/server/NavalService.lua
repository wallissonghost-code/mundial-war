-- Mundial War · ports, troop transports across water, warships, amphibious landings.
local NavalService = {}

local ctx, Config, Map, Territory
local fleets = {}        -- list of { id, nation, troops, path, progress, target }
local warships = {}      -- list of { id, nation, port, cell }
local nextId = 1
local visit, prev, vstamp = {}, {}, 0
local nb = {}

function NavalService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
end

function NavalService.reset()
	fleets, warships, nextId = {}, {}, 1
end

function NavalService.fleets()
	return fleets
end

function NavalService.warships()
	return warships
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
function NavalService.route(nid, targetCell)
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

function NavalService.launch(nid, cell, percent)
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
	local path, why = NavalService.route(nid, cell)
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

function NavalService.buyWarship(nid, portCell)
	local N = Config.Naval
	local n = ctx.Nations.get(nid)
	if not ctx.Match.isPlaying() then return false, "Aguarde o início da partida." end
	if not n or not n.alive then return false, "Você não tem nação." end
	local b = ctx.Buildings.at(portCell)
	if not b or b.kind ~= "port" or b.owner ~= nid then return false, "Selecione um porto seu." end
	local here = 0
	for _, w in ipairs(warships) do
		if w.port == portCell then here = here + 1 end
	end
	if here >= N.WarshipsPerPort then return false, "Este porto já tem " .. N.WarshipsPerPort .. " navios." end
	if n.gold < N.WarshipGold then return false, "Navio de guerra custa " .. N.WarshipGold .. " de ouro." end
	local water = waterNeighbor(portCell)
	if not water then return false, "Porto sem acesso à água." end
	n.gold = n.gold - N.WarshipGold
	warships[#warships + 1] = { id = nextId, nation = nid, port = portCell, cell = water }
	nextId = nextId + 1
	return true, "Navio de guerra em patrulha."
end

function NavalService.onPortLost(portCell)
	local k = 1
	for i = 1, #warships do
		local w = warships[i]
		local b = ctx.Buildings.at(portCell)
		if w.port == portCell and (not b or b.owner ~= w.nation) then
			-- sunk with its port
		else
			warships[k] = w
			k = k + 1
		end
	end
	for i = k, #warships do warships[i] = nil end
end

function NavalService.removeNation(nid)
	local k = 1
	for i = 1, #fleets do
		if fleets[i].nation ~= nid then fleets[k] = fleets[i] k = k + 1 end
	end
	for i = k, #fleets do fleets[i] = nil end
	k = 1
	for i = 1, #warships do
		if warships[i].nation ~= nid then warships[k] = warships[i] k = k + 1 end
	end
	for i = k, #warships do warships[i] = nil end
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
	if f.troops >= cost then
		if owner > 0 then
			local d = ctx.Nations.get(owner)
			d.troops = math.max(0, d.troops - loss)
			ctx.notify(owner, n.name .. " desembarcou no seu litoral!", "war")
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
	local r2 = N.WarshipRadius * N.WarshipRadius
	for i = 1, #fleets do
		local f = fleets[i]
		local n = ctx.Nations.get(f.nation)
		local keep = n ~= nil and n.alive
		if keep then
			f.progress = f.progress + N.Speed * dt
			local pos = f.path[math.min(#f.path, math.floor(f.progress))]
			local px, py = Map:xy(pos)
			for _, w in ipairs(warships) do
				if w.nation ~= f.nation and ctx.Diplomacy.relation(w.nation, f.nation) == "war" then
					local wx, wy = Map:xy(w.cell)
					if (wx - px) * (wx - px) + (wy - py) * (wy - py) <= r2 then
						f.troops = f.troops * (1 - N.WarshipDamagePerSecond * dt)
					end
				end
			end
			if f.troops < 1 then
				ctx.notify(f.nation, "Sua frota foi afundada.", "bad")
				keep = false
			elseif f.progress >= #f.path then
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
		fl[#fl + 1] = { f.id, f.nation, math.floor(f.troops), f.path, Config.Naval.Speed, f.target, f.progress }
	end
	for _, w in ipairs(warships) do
		ws[#ws + 1] = { w.id, w.nation, w.cell }
	end
	return fl, ws
end

return NavalService
