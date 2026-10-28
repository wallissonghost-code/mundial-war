-- Mundial War · building numbers per level, shared by server rules and both clients.
local BuildingStats = {}

-- Value of `field` for a building of `kind` at `level` (1-based).
function BuildingStats.stat(Config, kind, level, field)
	local def = Config.Buildings[kind]
	local base = def and def[field]
	if base == nil then return nil end
	local inc = def.perLevel and def.perLevel[field] or 0
	local v = base + inc * ((level or 1) - 1)
	if field == "intercept" then v = math.min(0.95, v) end
	if field == "support" then v = math.max(0.4, v) end
	if field == "shelter" then v = math.max(0.15, v) end
	if field == "cooldownFactor" then v = math.max(0.4, v) end
	return v
end

function BuildingStats.maxStat(Config, kind, field)
	return BuildingStats.stat(Config, kind, Config.MaxBuildingLevel, field)
end

-- Gold to go from `level` to `level + 1`, or nil at the top level.
function BuildingStats.upgradeCost(Config, kind, level)
	if level >= Config.MaxBuildingLevel then return nil end
	return math.floor(Config.Buildings[kind].cost * Config.UpgradeCostFactor * level)
end

local function num(v)
	if math.abs(v - math.floor(v)) < 1e-6 then
		local s = tostring(math.floor(v))
		-- thousands separator for readability
		local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
		if out:sub(1, 1) == "." then out = out:sub(2) end
		return out
	end
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""):gsub("%.", ","))
end

local function pct(v) return num(v * 100) .. "%" end

-- Effect lines (Portuguese) for the building at `level`.
function BuildingStats.lines(Config, kind, level)
	local s = function(f) return BuildingStats.stat(Config, kind, level, f) end
	local out = {}
	if kind == "city" then
		out[#out + 1] = "+" .. num(s("growth")) .. " tropas/s"
		out[#out + 1] = "+" .. num(s("capacity")) .. " capacidade"
		out[#out + 1] = "+" .. num(s("gold")) .. " ouro/s"
	elseif kind == "factory" then
		out[#out + 1] = "+" .. num(s("gold")) .. " ouro/s"
	elseif kind == "port" then
		out[#out + 1] = "+" .. num(s("gold")) .. " ouro/s"
		out[#out + 1] = "Até " .. num(s("boats")) .. " barcos de defesa"
	elseif kind == "bunker" or kind == "wall" then
		out[#out + 1] = "Ataques custam ×" .. num(s("defense"))
	elseif kind == "tower" then
		out[#out + 1] = "Frentes inimigas perdem " .. pct(s("attrition")) .. "/s"
	elseif kind == "machinegun" then
		out[#out + 1] = "Ataques grandes custam até ×" .. num(s("maxFactor"))
	elseif kind == "artillery" then
		out[#out + 1] = "Frentes inimigas perdem " .. pct(s("damage")) .. " a cada " .. num(s("interval")) .. " s"
		out[#out + 1] = "Seus ataques ali custam ×" .. num(s("support"))
	elseif kind == "tankfactory" then
		out[#out + 1] = "Ataques custam −" .. pct(s("attackBonus"))
	elseif kind == "airfield" then
		out[#out + 1] = "Alcance dos aviões: " .. num(s("range")) .. " células"
	elseif kind == "airdefense" then
		out[#out + 1] = pct(s("intercept")) .. " de chance de interceptar"
	elseif kind == "silo" then
		out[#out + 1] = "Recarga ×" .. num(s("cooldownFactor"))
		if level >= 3 then out[#out + 1] = "Libera bomba de hidrogênio" end
		if level >= 5 then out[#out + 1] = "Libera o Fim de Era" end
	elseif kind == "trench" then
		out[#out + 1] = "Frentes inimigas perdem " .. pct(s("attrition")) .. "/s"
		out[#out + 1] = "Você perde ×" .. num(s("shelter")) .. " tropas ao ceder terreno"
	elseif kind == "antinaval" then
		out[#out + 1] = num(s("damage")) .. " de dano/s em barcos"
		out[#out + 1] = "Desembarques custam ×" .. num(s("landing"))
	elseif kind == "flak" then
		out[#out + 1] = pct(s("intercept")) .. " de chance de derrubar aviões"
	elseif kind == "oilwell" then
		out[#out + 1] = "+" .. num(s("oil")) .. " petróleo/s"
	end
	local r = s("radius")
	if r then table.insert(out, 1, "Alcance: " .. num(r) .. " células") end
	return out
end

-- Radius drawn on the map for a building (defence reach, or aircraft range for an air base).
function BuildingStats.reach(Config, kind, level)
	return BuildingStats.stat(Config, kind, level, "radius") or BuildingStats.stat(Config, kind, level, "range")
end

return BuildingStats
