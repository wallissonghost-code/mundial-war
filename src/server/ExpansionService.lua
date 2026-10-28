-- Mundial War · expansion orders: the "click → front advances → territory grows" loop.
--
-- An order holds troops taken from the reserve once. Every simulation tick it captures a
-- few cells of its target owner (0 = neutral) that touch the nation, chosen to form an
-- organic front: a fan that grows from the border point nearest the click, inside a cone
-- aimed at the click (wider with more troops), preferring cells already hugged by our
-- territory so no holes are left behind.
local ExpansionService = {}

local ctx, Config, Map, Territory
local orders = {}          -- list of active orders
local nextOrderId = 1
local candidates, scores = {}, {}

function ExpansionService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
	Territory = ctx.Territory
end

function ExpansionService.reset()
	orders = {}
	nextOrderId = 1
end

function ExpansionService.activeOrders()
	return orders
end

function ExpansionService.ordersOf(nid)
	local out = {}
	for _, o in ipairs(orders) do
		if o.nation == nid then out[#out + 1] = o end
	end
	return out
end

local function findOrder(nid, target)
	for _, o in ipairs(orders) do
		if o.nation == nid and o.target == target then return o end
	end
	return nil
end

local function finish(o, refund)
	o.done = true
	local n = ctx.Nations.get(o.nation)
	if refund and n and n.alive and o.troops > 0 then
		n.troops = n.troops + math.floor(o.troops)
	end
	o.troops = 0
end

local function sweep()
	local k = 1
	for i = 1, #orders do
		local o = orders[i]
		if not o.done then
			orders[k] = o
			k = k + 1
		end
	end
	for i = k, #orders do orders[i] = nil end
end

-- Nearest border cell of the nation to `cell` (where the arrow starts on the client).
local function nearestOwnBorder(nid, cell)
	local best, bestD = nil, math.huge
	for i in pairs(Territory.borderCells(nid) or {}) do
		local d = Map:distance(i, cell)
		if d < bestD then best, bestD = i, d end
	end
	return best
end

-- True when the nation owns land on the same landmass as `cell` (land path exists).
function ExpansionService.sameLandmass(nid, cell)
	local mass = ctx.Landmass[cell]
	if not mass then return false end
	for i in pairs(Territory.borderCells(nid) or {}) do
		if ctx.Landmass[i] == mass then return true end
	end
	local n = ctx.Nations.get(nid)
	return n ~= nil and ctx.Landmass[n.capital] == mass and Territory.ownerOf(n.capital) == nid
end

-- Validates a land order without changing anything. Returns ok, reasonOrTarget.
function ExpansionService.validate(nid, cell, percent)
	local n = ctx.Nations.get(nid)
	if not ctx.Match.isPlaying() then return false, "A expansão começa após a fase de escolha." end
	if not n or not n.alive then return false, "Você ainda não tem nação." end
	if not Map:valid(cell) then return false, "Célula inválida." end
	if type(percent) ~= "number" or percent ~= percent or percent < 0.01 or percent > 1 then
		return false, "Percentual inválido."
	end
	local target = Territory.ownerOf(cell)
	if target == -1 then return false, "A água não pode ser conquistada. Use um porto." end
	if target == nid then return false, "Esse território já é seu." end
	if target > 0 and not ctx.Diplomacy.canAttack(nid, target) then
		return false, "Aliados não podem se atacar. Cancele a aliança antes."
	end
	if not ExpansionService.sameLandmass(nid, cell) then
		return false, "Sem ligação por terra. Use um porto para atravessar o mar.", "naval"
	end
	if not Territory.touches(nid, target) then
		if target == 0 then return false, "Não há terra livre na sua fronteira.", "blocked" end
		return false, "Sem fronteira com essa nação. Use um porto.", "naval"
	end
	if not Territory.reachable(nid, cell, Config.Expansion.ReachSearchLimit) then
		if target == 0 then
			return false, "Caminho bloqueado por outra nação. Ataque-a ou escolha terra livre ligada à sua fronteira.", "blocked"
		end
		return false, "Essa parte de " .. ctx.Nations.get(target).name .. " não encosta em você. Use um porto.", "naval"
	end
	return true, target
end

-- Starts or reinforces an order with troops that already left the reserve.
function ExpansionService.start(nid, target, cell, troops)
	local existing = findOrder(nid, target)
	if existing then
		existing.troops = existing.troops + troops
		existing.anchor = cell
		existing.origin = nearestOwnBorder(nid, cell) or existing.origin
		existing.originCell = existing.origin or existing.originCell
		return existing
	end
	local o = {
		id = nextOrderId, nation = nid, target = target, troops = troops, sent = troops,
		anchor = cell, origin = nearestOwnBorder(nid, cell), front = nil, carry = 0,
		started = ctx.now(),
	}
	nextOrderId = nextOrderId + 1
	o.originCell = o.origin or cell
	o.front = o.origin
	orders[#orders + 1] = o
	if target > 0 then ctx.Diplomacy.ensureWar(nid, target) end
	return o
end

function ExpansionService.issue(nid, cell, percent)
	local ok, targetOrWhy, hint = ExpansionService.validate(nid, cell, percent)
	if not ok then return false, targetOrWhy, hint end
	local target = targetOrWhy
	local n = ctx.Nations.get(nid)
	local existing = findOrder(nid, target)
	if not existing then
		local count = 0
		for _, o in ipairs(orders) do
			if o.nation == nid then count = count + 1 end
		end
		if count >= Config.Expansion.MaxOrdersPerNation then
			return false, "Limite de " .. Config.Expansion.MaxOrdersPerNation .. " frentes ativas. Cancele uma."
		end
	end
	local troops = math.floor(n.troops * percent)
	if troops < Config.Expansion.MinTroopsToSend then
		return false, "Tropas insuficientes para enviar."
	end
	n.troops = n.troops - troops
	local o = ExpansionService.start(nid, target, cell, troops)
	local targetName = target == 0 and "terra livre" or ctx.Nations.get(target).name
	return true, (existing and "Reforço enviado: " or "Avanço iniciado: ") .. troops .. " tropas → " .. targetName, o
end

function ExpansionService.cancel(nid, orderId)
	for _, o in ipairs(orders) do
		if o.nation == nid and (orderId == nil or o.id == orderId) then
			finish(o, true)
		end
	end
	sweep()
end

function ExpansionService.cancelAll(nid, refund)
	for _, o in ipairs(orders) do
		if o.nation == nid then finish(o, refund) end
	end
	sweep()
end

function ExpansionService.cancelAgainst(nid, target)
	for _, o in ipairs(orders) do
		if o.nation == nid and o.target == target then finish(o, true) end
	end
	sweep()
end

local function advance(o, dt)
	local E = Config.Expansion
	local n = ctx.Nations.get(o.nation)
	if not n or not n.alive then finish(o, false) return end
	if o.target > 0 then
		local t = ctx.Nations.get(o.target)
		if not t or not t.alive or not ctx.Diplomacy.canAttack(o.nation, o.target) then
			finish(o, true)
			return
		end
	end
	if o.troops < E.MinTroopsToSend * 0.5 then finish(o, true) return end

	-- look only near the fan first; fall back to the whole border when that area is used up
	local sqTroops = math.sqrt(math.max(0, o.troops))
	local reach = Map:distance(o.originCell, o.anchor) + E.FrontSearchMargin + sqTroops / 4
	local _, count = Territory.frontierNear(o.nation, o.target, o.originCell, reach, candidates)
	if count == 0 then
		_, count = Territory.frontier(o.nation, o.target, candidates)
	end
	if count == 0 then finish(o, true) return end

	-- Fan-shaped front: grow outward from where the order left our border (origin), inside a
	-- cone aimed at the clicked point. Distance from the origin keeps the front even (no spear),
	-- the cone keeps it pointed at the target, own-neighbour bonus closes notches (no holes).
	local sq = math.sqrt(math.max(0, o.troops))
	local cone = math.rad(math.min(E.FrontConeMax, E.FrontConeBase + sq / E.FrontConeTroopDivisor))
	local W = Map.W
	local ox, oy = (o.originCell - 1) % W, ((o.originCell - 1) - (o.originCell - 1) % W) / W
	local tx, ty = (o.anchor - 1) % W - ox, ((o.anchor - 1) - (o.anchor - 1) % W) / W - oy
	local L = math.sqrt(tx * tx + ty * ty)
	local m = count
	for k = 1, count do
		local c = candidates[k]
		local vx, vy = (c - 1) % W - ox, ((c - 1) - (c - 1) % W) / W - oy
		local r = math.sqrt(vx * vx + vy * vy)
		local penalty = 0
		if L >= 1 and r >= 2 then
			local cosang = (vx * tx + vy * ty) / (r * L)
			if cosang < -1 then cosang = -1 elseif cosang > 1 then cosang = 1 end
			local excess = math.acos(cosang) - cone
			if excess > 0 then penalty = excess * r * E.ConePenalty end
		end
		scores[k] = r + penalty - E.OwnNeighborWeight * Territory.ownNeighborCount(c, o.nation)
			+ ctx.random() * E.Jitter
	end

	local rate = math.min(E.CellsPerTickMax, E.CellsPerTickBase + sq / E.CellsPerTickTroopDivisor)
	if o.target > 0 then rate = rate * E.EnemyRateFactor end
	o.carry = o.carry + rate * dt / Config.Tick.Simulation
	local want = math.floor(o.carry)
	o.carry = o.carry - want
	if want <= 0 then return end

	local taken = 0
	for t = 1, math.min(want, m) do
		-- partial selection: best remaining score
		local best = t
		for k = t + 1, m do
			if scores[k] < scores[best] then best = k end
		end
		candidates[t], candidates[best] = candidates[best], candidates[t]
		scores[t], scores[best] = scores[best], scores[t]
		local cell = candidates[t]
		if Territory.ownerOf(cell) == o.target then
			local cost, loss = ctx.Combat.cellCost(o.nation, cell, o.troops, o.front)
			if cost > o.troops then
				o.stalled = true
				break
			end
			o.troops = o.troops - cost
			if o.target > 0 then
				local d = ctx.Nations.get(o.target)
				d.troops = math.max(0, d.troops - loss)
			end
			Territory.setOwner(cell, o.nation)
			o.front = cell
			taken = taken + 1
		end
	end
	if taken > 0 then o.stalled = false end
	if o.stalled then
		-- not enough troops for the cheapest cell left: the order ends, survivors go home
		finish(o, true)
	end
end

function ExpansionService.tick(dt)
	if not ctx.Match.isPlaying() then return end
	for i = 1, #orders do
		local o = orders[i]
		if not o.done then advance(o, dt) end
	end
	sweep()
end

-- Compact public view for clients: { id, nation, target, troops, front, anchor, origin }
function ExpansionService.publicView()
	local out = {}
	for _, o in ipairs(orders) do
		out[#out + 1] = { o.id, o.nation, o.target, math.floor(o.troops), o.front or 0, o.anchor, o.origin or 0 }
	end
	return out
end

return ExpansionService
