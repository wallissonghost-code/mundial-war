-- Mundial War · cost of taking a cell and defensive area effects on fronts.
local CombatService = {}

local ctx, Config, Map
local pulseClock, artilleryClock = 0, 0

function CombatService.init(context)
	ctx = context
	Config = ctx.Config
	Map = ctx.Map
end

function CombatService.reset()
	pulseClock, artilleryClock = 0, 0
end

-- Troops the attacker spends to take `cell`, and troops the defender loses.
function CombatService.cellCost(attackerId, cell, orderTroops, front)
	local E, C, B = Config.Expansion, Config.Combat, Config.Buildings
	local attacker = ctx.Nations.get(attackerId)
	local target = ctx.Territory.ownerOf(cell)
	local cost, defenderLoss = 0, 0
	if target == 0 then
		cost = E.NeutralBaseCost + Map:distance(cell, attacker.capital) * E.DistanceCostPerCell
		if Map:isPolar(cell) then cost = cost + E.PolarExtraCost end
	else
		local defender = ctx.Nations.get(target)
		local density = defender.troops / math.max(1, defender.land)
		cost = math.max(C.EnemyMinCost, density * C.DefenseDensityFactor)
		defenderLoss = density * C.DefenderLossFactor
		local Buildings = ctx.Buildings
		if Buildings.covered(cell, "bunker", target) then cost = cost * B.bunker.defense end
		if Buildings.covered(cell, "machinegun", target) then
			cost = cost * (1 + math.min(1, (orderTroops or 0) / B.machinegun.massDefense))
		end
		if Map:distance(cell, defender.capital) <= C.CapitalRadius then cost = cost * C.CapitalDefense end
		if Buildings.covered(cell, "artillery", attackerId) then cost = cost * B.artillery.support end
		local tanks = Buildings.count(attackerId, "tankfactory")
		if tanks > 0 then
			cost = cost * math.max(B.tankfactory.attackFloor, 1 - B.tankfactory.attackBonus * tanks)
		end
	end
	if front and not ctx.Territory.isMainland(attackerId, front) then
		cost = cost * C.ExclaveAttackFactor
	end
	return cost, defenderLoss
end

-- Sniper towers wear fronts down every second; artillery shells them periodically.
function CombatService.tick(dt)
	pulseClock = pulseClock + dt
	artilleryClock = artilleryClock + dt
	local doTower = pulseClock >= 1
	local doArtillery = artilleryClock >= Config.Buildings.artillery.interval
	if not doTower and not doArtillery then return end
	local B = Config.Buildings
	for _, order in ipairs(ctx.Expansion.activeOrders()) do
		if order.target > 0 and order.front then
			if doTower and ctx.Buildings.covered(order.front, "tower", order.target) then
				order.troops = order.troops * (1 - B.tower.attrition * pulseClock)
			end
			if doArtillery then
				-- the defender's artillery, or an ally of the defender, shells the front
				local shooters = ctx.Diplomacy.allies(order.target)
				shooters[#shooters + 1] = order.target
				for _, nid in ipairs(shooters) do
					if nid ~= order.nation and ctx.Buildings.covered(order.front, "artillery", nid) then
						order.troops = order.troops * (1 - B.artillery.damage)
						break
					end
				end
			end
		end
	end
	if doTower then pulseClock = 0 end
	if doArtillery then artilleryClock = 0 end
end

return CombatService
