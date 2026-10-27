-- Mundial War · server bootstrap. Builds the world from the modules and drives it from Heartbeat.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MundialWarShared")
local Config = require(Shared.GameConfig)

Players.CharacterAutoLoads = false   -- the nation is the character; no avatar walks on the map

local World = require(script.World)
local NetworkService = require(script.NetworkService)

local world = World.new({
	Config = Config,
	MapData = require(Shared.MapData),
	MapGrid = require(Shared.MapGrid),
	BuildingStats = require(Shared.BuildingStats),
	Palette = require(Shared.Palette),
	Protocol = require(Shared.Protocol),
	random = math.random,
	Services = {
		Territory = require(script.TerritoryService),
		Nations = require(script.NationService),
		Economy = require(script.EconomyService),
		Combat = require(script.CombatService),
		Buildings = require(script.BuildingService),
		Expansion = require(script.ExpansionService),
		Naval = require(script.NavalService),
		Strategic = require(script.StrategicService),
		Diplomacy = require(script.DiplomacyService),
		Bots = require(script.BotService),
		Match = require(script.MatchService),
		Commands = require(script.CommandService),
	},
})

NetworkService.start(world)

local failures = 0
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.25)   -- a long server hitch must not fast-forward the whole match
	local ok, err = pcall(function()
		world:step(dt, #Players:GetPlayers(), os.clock)
		NetworkService.flush(dt)
	end)
	if not ok then
		failures = failures + 1
		if failures <= 20 or failures % 100 == 0 then
			warn("[MundialWar] simulation error #" .. failures .. ": " .. tostring(err))
		end
	end
end)

if Config.DEBUG_MODE then
	task.spawn(function()
		while true do
			task.wait(10)
			local s = world.stats
			if s.simCount > 0 then
				print(string.format("[MundialWar] avg step %.2f ms, worst %.2f ms", s.simTime / s.simCount * 1000, s.worst * 1000))
				s.simTime, s.simCount, s.worst = 0, 0, 0
			end
		end
	end)
end
