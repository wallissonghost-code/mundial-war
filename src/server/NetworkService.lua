-- Mundial War · Roblox side of replication: remotes, join sync, batched broadcasts.
-- All decisions are made by World/CommandService; this module only moves data.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {}

local world, ctx, Protocol, Config
local commandRemote, eventRemote
local ready = {}            -- player -> true once the client asked for its first sync
local clocks = { delta = 0, nations = 0, orders = 0, private = 0 }

local function remote(name)
	local folder = ReplicatedStorage:FindFirstChild("MundialWarRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MundialWarRemotes"
		folder.Parent = ReplicatedStorage
	end
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	return r
end

local function playerForNation(nid)
	local n = ctx.Nations.get(nid)
	if not n or not n.userId then return nil end
	return Players:GetPlayerByUserId(n.userId)
end

local function sendInit(player)
	eventRemote:FireClient(player, world:initPayload(player.UserId))
end

local function broadcast(payload)
	for player in pairs(ready) do
		if player.Parent then eventRemote:FireClient(player, payload) end
	end
end

function NetworkService.start(theWorld)
	world = theWorld
	ctx = world.ctx
	Protocol = ctx.Protocol
	Config = ctx.Config
	ctx.realPlayers = true
	commandRemote = remote(Protocol.CommandRemote)
	eventRemote = remote(Protocol.EventRemote)

	commandRemote.OnServerEvent:Connect(function(player, action, a, b, c)
		if action == Protocol.Actions.Sync then
			if ready[player] and ready[player] > os.clock() - 2 then return end -- sync spam guard
			ready[player] = os.clock()
			sendInit(player)
			return
		end
		local ok, message = ctx.Commands.handle(player.UserId, player.DisplayName, action, a, b, os.clock(), c)
		if message then
			eventRemote:FireClient(player, { k = Protocol.Events.Notice, text = message, kind = ok and "good" or "bad" })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		ctx.Commands.forget(player.UserId)
		local n = ctx.Nations.forUser(player.UserId)
		if n and n.alive then
			if ctx.mode == "extreme" then
				ctx.Nations.returnToAI(n.id)
			else
				ctx.Nations.eliminate(n.id, "left")
			end
		end
	end)
end

function NetworkService.flush(dt)
	-- events produced by the simulation (notices, diplomacy, launches, match changes)
	for _, item in ipairs(world:drainOutbox()) do
		if item.to == nil then
			broadcast(item.payload)
		else
			local player = playerForNation(item.to)
			if player and ready[player] then eventRemote:FireClient(player, item.payload) end
		end
	end
	if ctx.fullResync then
		ctx.fullResync = false
		world:deltaPayload() -- discard: the init snapshot already contains it
		for player in pairs(ready) do
			if player.Parent then sendInit(player) end
		end
	end

	local T = Config.Tick
	clocks.delta = clocks.delta + dt
	clocks.nations = clocks.nations + dt
	clocks.orders = clocks.orders + dt
	clocks.private = clocks.private + dt
	if clocks.delta >= T.TerritoryDelta then
		clocks.delta = 0
		local payload = world:deltaPayload()
		if payload then broadcast(payload) end
	end
	if clocks.orders >= T.PublicOrders then
		clocks.orders = 0
		broadcast(world:ordersPayload())
	end
	if clocks.nations >= T.PublicNations then
		clocks.nations = 0
		broadcast(world:nationsPayload())
	end
	if clocks.private >= T.TerritoryDelta then
		clocks.private = 0
		for player in pairs(ready) do
			local payload = world:privatePayload(player.UserId)
			if payload and player.Parent then eventRemote:FireClient(player, payload) end
		end
	end
end

return NetworkService
