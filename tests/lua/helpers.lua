-- Test helpers: build a World from the real modules with a fake clock.
local H = {}

local function load(path)
	local chunk = assert(loadfile(path))
	return chunk()
end

H.Config = load("src/shared/GameConfig.lua")
H.Palette = load("src/shared/Palette.lua")
H.Protocol = load("src/shared/Protocol.lua")
H.MapGrid = load("src/shared/MapGrid.lua")
H.BuildingStats = load("src/shared/BuildingStats.lua")

local cachedReal = nil
function H.realMapData()
	cachedReal = cachedReal or load("src/shared/MapData.lua")
	return cachedReal
end

local B62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function b62(n, w)
	local s = ""
	for _ = 1, w do
		local d = n % 62
		s = string.sub(B62, d + 1, d + 1) .. s
		n = (n - d) / 62
	end
	return s
end

-- Map from ascii art: '.' water, 'A'..'Z' = country 1..26.
function H.asciiMap(lines)
	local W, Hh = #lines[1], #lines
	local rows, counts = {}, {}
	for y = 1, Hh do
		local line, out, x = lines[y], {}, 1
		while x <= W do
			local ch = string.sub(line, x, x)
			local stop = x + 1
			while stop <= W and string.sub(line, stop, stop) == ch do stop = stop + 1 end
			local id = ch == "." and 0 or (string.byte(ch) - 64)
			out[#out + 1] = b62(id, 2) .. b62(stop - x, 2)
			x = stop
		end
		rows[y] = table.concat(out)
	end
	local countries = {}
	for c = 1, 26 do
		countries[c] = { code = "C" .. c, name = "País " .. c, continent = "Test", cells = 0, capital = 1, population = 0 }
	end
	return { W = W, H = Hh, Land = 0, Alphabet = B62, Rows = rows, Countries = countries }
end

function H.newWorld(opts)
	opts = opts or {}
	-- tests skip the mode vote unless they ask for it
	local Config = opts.Config or H.configWith({ Match = { VoteSeconds = opts.vote or 0 } })
	if opts.Config and not opts.vote then
		Config = {}
		for k, v in pairs(opts.Config) do Config[k] = v end
		local match = {}
		for k, v in pairs(opts.Config.Match) do match[k] = v end
		match.VoteSeconds = 0
		Config.Match = match
	end
	local services = {}
	for _, name in ipairs({ "Territory", "Nations", "Economy", "Combat", "Buildings", "Expansion", "Naval",
		"Strategic", "Diplomacy", "Bots", "Match", "Commands" }) do
		local file = ({ Territory = "TerritoryService", Nations = "NationService", Economy = "EconomyService",
			Combat = "CombatService", Buildings = "BuildingService", Expansion = "ExpansionService",
			Naval = "NavalService", Strategic = "StrategicService", Diplomacy = "DiplomacyService",
			Bots = "BotService", Match = "MatchService", Commands = "CommandService" })[name]
		services[name] = load("src/server/" .. file .. ".lua")
	end
	local World = load("src/server/World.lua")
	local seed = opts.seed or 7
	math.randomseed(seed)
	local mapData = opts.mapData or H.realMapData()
	local world = World.new({
		mode = opts.mode,
		Config = Config, Palette = H.Palette, Protocol = H.Protocol, MapGrid = H.MapGrid, BuildingStats = H.BuildingStats,
		MapData = mapData, Services = services, random = math.random,
	})
	return world, world.ctx
end

-- Copy of the config with overrides applied (deep for one level of tables).
function H.configWith(overrides)
	local c = {}
	for k, v in pairs(H.Config) do
		if type(v) == "table" then
			local t = {}
			for k2, v2 in pairs(v) do t[k2] = v2 end
			c[k] = t
		else
			c[k] = v
		end
	end
	for section, values in pairs(overrides) do
		if type(values) == "table" and type(c[section]) == "table" then
			for k, v in pairs(values) do c[section][k] = v end
		else
			c[section] = values
		end
	end
	return c
end

function H.run(world, seconds, humans)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		world:step(dt, humans or 1)
	end
end

function H.ok(cond, msg)
	if not cond then error("ASSERT: " .. (msg or "?"), 2) end
end

function H.cellOfCountry(ctx, code)
	local index, c = ctx.Map:countryByCode(code)
	return c and c.capital, index
end

return H
