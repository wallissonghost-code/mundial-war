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
		local bunker = Buildings.covered(cell, "bunker", target, "defense")
		if bunker then cost = cost * bunker end
		local wall = Buildings.covered(cell, "wall", target, "defense")
		if wall then cost = cost * wall end
		local shelter = Buildings.covered(cell, "trench", target, "shelter", true)
		if shelter then defenderLoss = defenderLoss * shelter end
		local mg = Buildings.covered(cell, "machinegun", target, "maxFactor")
		if mg then
			cost = cost * (1 + math.min(mg - 1, (orderTroops or 0) / B.machinegun.massDefense))
		end
		if Map:distance(cell, defender.capital) <= C.CapitalRadius then cost = cost * C.CapitalDefense end
		local support = Buildings.covered(cell, "artillery", attackerId, "support", true)
		if support then cost = cost * support end
		local attack = Buildings.totals(attackerId).attack
		if attack > 0 then
			cost = cost * math.max(B.tankfactory.attackFloor, 1 - attack)
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
			local attrition = doTower and ctx.Buildings.covered(order.front, "tower", order.target, "attrition")
			if attrition then
				order.troops = order.troops * (1 - attrition * pulseClock)
			end
			local trench = doTower and ctx.Buildings.covered(order.front, "trench", order.target, "attrition")
			if trench then
				order.troops = order.troops * (1 - trench * pulseClock)
			end
			if doArtillery then
				-- the defender's artillery, or an ally of the defender, shells the front
				local shooters = ctx.Diplomacy.allies(order.target)
				shooters[#shooters + 1] = order.target
				for _, nid in ipairs(shooters) do
					local damage = nid ~= order.nation and ctx.Buildings.covered(order.front, "artillery", nid, "damage")
					if damage then
						order.troops = order.troops * (1 - damage)
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
