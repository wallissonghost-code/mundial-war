-- Integration: the real server and client scripts running together on the Roblox mock.
local M = dofile("tests/lua/roblox_mock.lua")
local ok = function(c, msg) if not c then error("ASSERT: " .. msg, 2) end end

local function find(root, pred, out)
	out = out or {}
	for _, c in ipairs(root:GetChildren()) do
		if pred(c) then out[#out + 1] = c end
		find(c, pred, out)
	end
	return out
end

local function texts(root)
	local all = {}
	for _, c in ipairs(find(root, function(c) return c.ClassName == "TextLabel" or c.ClassName == "TextButton" end)) do
		local t = rawget(c, "_props").Text
		if t then all[#all + 1] = t end
	end
	return table.concat(all, "\n")
end

local function boot(editable)
	M.reset()
	M.editableAvailable = editable
	local game = M.game
	M.mount(game:GetService("ReplicatedStorage"), "src/shared", "MundialWarShared")
	local server = M.mount(game:GetService("ServerScriptService"), "src/server", "MundialWar")
	local client = M.mount(M.localPlayer, "src/client", "MundialWar")
	M.run(server)
	M.run(client)
	return game
end

local UIS
local function frame(dt)
	M.clock = M.clock + dt
	M.services.RunService.Heartbeat:Fire(dt)
	M.pump()
	M.services.RunService.RenderStepped:Fire(dt)
	M.runQueue()
	M.pump()
end
local function run(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do frame(0.05) end
end

local function input(kind, x, y, z)
	return { UserInputType = M.Enum and M.Enum or nil, Position = { X = x, Y = y, Z = z or 0 }, KeyCode = nil, _kind = kind }
end

local Enum
local function mouse(event, button, x, y, z)
	local obj = { UserInputType = button, Position = { X = x, Y = y, Z = z or 0 } }
	M.services.UserInputService[event]:Fire(obj, false)
end
local function click(x, y, right)
	local b = right and Enum.UserInputType.MouseButton2 or Enum.UserInputType.MouseButton1
	mouse("InputBegan", b, x, y)
	mouse("InputEnded", b, x, y)
	frame(0.05)
end

-- screen position of a cell at the initial "fit" zoom (1920x1080 screen, 640x320 map -> 3 px/cell)
local function screenOf(cell)
	local x = (cell - 1) % 640
	local y = (cell - 1 - x) / 640
	return x * 3 + 1.5, 60 + y * 3 + 1.5
end

-- Load the real map data for picking cells
local MapData = assert(loadfile("src/shared/MapData.lua"))()
local brasilia
for _, c in ipairs(MapData.Countries) do if c.code == "BRA" then brasilia = c.capital end end

do
	boot(true)
	Enum = M.env(nil).Enum
	local gui = M.localPlayer.PlayerGui
	run(1)
	ok(M.warnings == nil, "no warnings during boot")
	ok(M.services.Players.CharacterAutoLoads == false, "characters disabled")
	-- every round opens with the mode menu; vote for the classic mode
	ok(texts(gui):find("Conquista Extrema") and texts(gui):find("Votar"), "mode menu shown")
	local votes = find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "Votar" end)
	ok(#votes == 2, "one vote button per mode")
	votes[1].Activated:Fire()
	run(1)
	ok(rawget(gui.MundialWar.ModeMenu, "_props").Visible == false, "menu closes after everyone voted")
	local all = texts(gui)
	ok(all:find("fundar sua nação"), "spawn banner shown")
	run(1)
	local rowFrames = #find(gui, function(c) return c.ClassName == "Frame" and c.Parent and c.Parent.Name == "TerritoryRows" end)
	ok(rowFrames > 500, "compatible map drawn with frames by default (" .. rowFrames .. ")")
	-- switch to the image map
	for _, b in ipairs(find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "🗺" end)) do b.Activated:Fire() end
	run(0.5)
	ok(M.pixelWrites >= 1, "map painted through EditableImage after switching")
	ok(#find(gui, function(c) return c.Name == "TerritoryRows" end) == 0, "frame map removed after switching")
	local labels = #find(gui, function(c) return c.ClassName == "TextLabel" end)
	ok(labels > 20, "bot labels created (" .. labels .. ")")

	-- click on water: rejected locally
	click(10, 300)
	ok(texts(gui):find("terra"), "water spawn hint")

	-- spawn in Brazil, far from every capital (AI nations sit on real capitals)
	local Grid = assert(loadfile("src/shared/MapGrid.lua"))().new(MapData)
	local brIndex = Grid:countryByCode("BRA")
	local home
	for i = 1, Grid.N do
		if Grid.country[i] == brIndex and not Grid.coast[i] and Grid.country[i - 25] == brIndex then
			local far = true
			for _, c in ipairs(MapData.Countries) do
				if Grid:distance(c.capital, i) < 24 then far = false break end
			end
			if far then home = i break end
		end
	end
	ok(home, "found a free spot in Brazil")
	local sx, sy = screenOf(home)
	click(sx, sy)
	run(0.5)
	ok(texts(gui):find("Nação fundada"), "spawn notice")
	ok(texts(gui):find("A guerra começa em"), "countdown after spawning")

	-- spawn phase ends
	run(26)
	ok(texts(gui):find("👥"), "player card shows troops")

	-- one click starts the expansion to the west
	local tx, ty = screenOf(home - 25)
	click(tx, ty)
	run(0.5)
	ok(texts(gui):find("Avanço iniciado"), "order started by a single click: " .. texts(gui):sub(1, 400))
	local writes = M.pixelWrites
	run(4)
	ok(M.pixelWrites > writes, "territory deltas repainted")

	-- percent buttons, zoom, pan, keyboard
	for _, b in ipairs(find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "50%" end)) do
		b.Activated:Fire()
	end
	mouse("InputChanged", Enum.UserInputType.MouseWheel, 960, 540, 1)
	mouse("InputChanged", Enum.UserInputType.MouseWheel, 960, 540, 1)
	mouse("InputBegan", Enum.UserInputType.MouseButton1, 900, 500)
	mouse("InputChanged", Enum.UserInputType.MouseMovement, 960, 560)
	mouse("InputChanged", Enum.UserInputType.MouseMovement, 1100, 600)
	mouse("InputEnded", Enum.UserInputType.MouseButton1, 1100, 600)
	M.services.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F, Position = { X = 0, Y = 0, Z = 0 } }, false)
	M.keysDown[Enum.KeyCode.D] = true
	run(0.3)
	M.keysDown[Enum.KeyCode.D] = nil
	run(40) -- earn gold for a city and its upgrade
	-- build tray: select a city and place it inside our territory
	for _, b in ipairs(find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "🏗" end)) do b.Activated:Fire() end
	run(0.3)
	ok(texts(gui):find("Cidade"), "build tray lists buildings")
	local cityButtons = find(gui, function(c) return c.ClassName == "TextButton" and (rawget(c, "_props").Text or ""):find("Cidade") end)
	for _, b in ipairs(cityButtons) do b.Activated:Fire() end
	M.services.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F, Position = { X = 0, Y = 0, Z = 0 } }, false)
	run(0.3)
	click(sx, sy)
	run(0.5)
	ok(texts(gui.MundialWar.Notices):find("Construção pronta: Cidade"), "city built: " .. texts(gui.MundialWar.Notices))
	M.services.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape, Position = { X = 0, Y = 0, Z = 0 } }, false)
	run(0.2)
	do
		click(sx, sy)
		ok(texts(gui):find("Nível 1") and texts(gui):find("Alcance") == nil, "building popover with level")
		local up = find(gui, function(c) return c.ClassName == "TextButton" and (rawget(c, "_props").Text or ""):find("Melhorar") end)
		ok(#up == 1, "upgrade button")
		up[1].Activated:Fire()
		run(0.5)
		ok(texts(gui):find("nível 2"), "upgrade confirmed")
	end

	-- right click on a bot opens diplomacy
	local Map = assert(loadfile("src/shared/MapGrid.lua"))().new(MapData)
	local _, arg = Map:countryByCode("ARG")
	local ax, ay = screenOf(arg.capital)
	click(ax, ay, true)
	ok(texts(gui):find("Aliança"), "diplomacy popover")
	for _, b in ipairs(find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "🤝 Aliança" end)) do b.Activated:Fire() end
	run(0.5)
	ok(texts(gui):find("aliança") or texts(gui):find("Aliança"), "alliance answer shown")

	run(60)
	ok(M.warnings == nil, "no server errors or warnings in 90 s of play")
	local dump = os.getenv("MW_DUMP")
	if dump then
		M.services.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F, Position = { X = 0, Y = 0, Z = 0 } }, false)
		run(1.1)
		M.dump(gui, dump .. "/world.txt")
		for _ = 1, 9 do mouse("InputChanged", Enum.UserInputType.MouseWheel, sx, sy, 1) end
		run(1.1)
		M.dump(gui, dump .. "/zoom.txt")
	end
	print(string.format("PASS client+server integration (%d instances, %d pixel writes, %.0f KB sent to the client)", M.created, M.pixelWrites, M.bytes / 1024))
end

do
	boot(false)
	run(1)
	ok(M.warnings == nil, "compatible map needs no warning")
	ok(M.game:GetService("ReplicatedStorage"):GetAttribute("MW_ImageApis") == false, "server detected image APIs off")
	for _, b in ipairs(find(M.localPlayer.PlayerGui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "🗺" end)) do b.Activated:Fire() end
	run(0.5)
	ok(texts(M.localPlayer.PlayerGui):find("Mesh / Image APIs"), "explains why the image map is unavailable")
	local rows = #find(M.localPlayer.PlayerGui, function(c) return c.ClassName == "Frame" and c.Parent and c.Parent.Name == "TerritoryRows" end)
	run(2)
	rows = #find(M.localPlayer.PlayerGui, function(c) return c.ClassName == "Frame" and c.Parent and c.Parent.Name == "TerritoryRows" end)
	ok(rows > 1000, "fallback renderer draws rows (" .. rows .. " frames)")
	print(string.format("PASS compatible map without image APIs (%d frames)", rows))
end

do
	boot(true)
	local gui = M.localPlayer.PlayerGui
	run(1)
	local votes = find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "Votar" end)
	votes[2].Activated:Fire()
	run(1.5)
	ok(texts(gui):find("Clique num país"), "extreme spawn banner")
	local sx, sy = screenOf(brasilia + 2)
	click(sx, sy)
	run(0.5)
	ok(texts(gui):find("Você agora governa Brasil"), "took Brazil: " .. texts(gui.MundialWar.Notices))
	run(26)
	ok(texts(gui.MundialWar.PlayerCard):find("🛢"), "oil shown in Conquista Extrema")
	for _, b in ipairs(find(gui, function(c) return c.ClassName == "TextButton" and rawget(c, "_props").Text == "🏗" end)) do b.Activated:Fire() end
	run(0.3)
	local wall = find(gui, function(c) return c.ClassName == "TextButton" and (rawget(c, "_props").Text or ""):find("Muro") end)
	ok(#wall == 1 and rawget(wall[1], "_props").Visible ~= false, "extreme buildings in the tray")
	run(20)
	ok(M.warnings == nil, "no server errors in Conquista Extrema")
	print("PASS client in Conquista Extrema")
end
