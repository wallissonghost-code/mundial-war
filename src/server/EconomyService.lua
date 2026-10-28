-- Mundial War · troop generation, capacity and gold.
local EconomyService = {}

local ctx

function EconomyService.init(context)
	ctx = context
end

function EconomyService.maxTroops(n)
	local T = ctx.Config.Troops
	local b = ctx.Buildings.totals(n.id)
	return T.BaseCapacity + n.land * T.CapacityPerCell + b.capacity
end

function EconomyService.troopRate(n, maxTroops)
	local T = ctx.Config.Troops
	local b = ctx.Buildings.totals(n.id)
	local raw = T.BaseGrowth + n.land * T.GrowthPerCell + b.growth
	local room = 1 - n.troops / maxTroops
	if room <= 0 then return 0 end
	return raw * room ^ T.SaturationPower
end

function EconomyService.goldRate(n)
	local G = ctx.Config.Gold
	local b = ctx.Buildings.totals(n.id)
	return G.Base + n.land * G.PerCell + b.gold
end

function EconomyService.tick(dt)
	if not ctx.Match.isPlaying() then return end
	for _, n in pairs(ctx.Nations.all()) do
		if n.alive then
			local maxTroops = EconomyService.maxTroops(n)
			local rate = EconomyService.troopRate(n, maxTroops)
			n.maxTroops = maxTroops
			n.troopRate = rate
			n.goldRate = EconomyService.goldRate(n)
			if n.troops < maxTroops then
				n.troops = math.min(maxTroops, n.troops + rate * dt)
			end
			n.gold = n.gold + n.goldRate * dt
			if ctx.mode == "extreme" then
				local O = ctx.Config.Oil
				n.oilRate = O.Base + n.land * O.PerCell + ctx.Buildings.totals(n.id).oil
				n.oil = (n.oil or 0) + n.oilRate * dt
			end
		end
	end
end

function EconomyService.spendGold(n, amount)
	if n.gold + 1e-6 < amount then return false end
	n.gold = n.gold - amount
	return true
end

return EconomyService
