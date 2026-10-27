-- Mundial War · client bootstrap: full-screen strategic map, HUD, input and replication.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("MundialWarShared")
local Config = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local Palette = require(Shared.Palette)
local MapGrid = require(Shared.MapGrid)

local ClientState = require(script.ClientState)
local MapRenderer = require(script.MapRenderer)
local CameraController = require(script.CameraController)
local OverlayRenderer = require(script.OverlayRenderer)
local InputController = require(script.InputController)
local HUD = require(script.HUD)
local DebugOverlay = require(script.DebugOverlay)

local player = Players.LocalPlayer
local Events, Actions = Protocol.Events, Protocol.Actions

-- The avatar is identity only: no character, no 3D camera, no default HUD clutter.
task.spawn(function()
	-- core scripts may not be ready on the first frames; retry briefly
	for _ = 1, 10 do
		local ok = pcall(function()
			for _, kind in ipairs({ Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }) do
				StarterGui:SetCoreGuiEnabled(kind, false)
			end
		end)
		if ok then break end
		task.wait(0.5)
	end
end)
local camera3d = workspace.CurrentCamera
camera3d.CameraType = Enum.CameraType.Scriptable
camera3d.CFrame = CFrame.new(0, 10000, 0) * CFrame.Angles(math.rad(90), 0, 0)

local remotes = ReplicatedStorage:WaitForChild("MundialWarRemotes")
local commandRemote = remotes:WaitForChild(Protocol.CommandRemote)
local eventRemote = remotes:WaitForChild(Protocol.EventRemote)

local Map = MapGrid.new(require(Shared.MapData))
local state = ClientState.new(Map, Protocol, Config, Palette)

-- Screen layout: the ocean-coloured viewport is the whole screen; the world frame moves inside it.
local gui = Instance.new("ScreenGui")
gui.Name = "MundialWar"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local viewport = Instance.new("Frame")
viewport.Name = "Viewport"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundColor3 = Color3.fromRGB(Palette.Water[1], Palette.Water[2], Palette.Water[3])
viewport.BorderSizePixel = 0
viewport.ClipsDescendants = true
viewport.Parent = gui

local world = Instance.new("Frame")
world.Name = "World"
world.BackgroundTransparency = 1
world.Parent = viewport

local camera = CameraController.new(viewport, world, Map, Config)
local renderer = MapRenderer.new(state, world)
local overlay = OverlayRenderer.new(state, camera, world)
local debugOverlay = nil

local function send(action, a, b)
	commandRemote:FireServer(action, a, b)
end

-- Interaction state ------------------------------------------------------------------------
local mode = nil          -- nil | "build" | "nuke" | "airstrike" | "warship"
local buildKind = nil
local pending = nil       -- { cell, at, kind }
local hud

local function clearAim()
	pending = nil
	overlay:setAim(nil, nil)
end

local function setMode(newMode, kind)
	mode, buildKind = newMode, kind
	clearAim()
	hud:showTray(mode == "build", buildKind)
	hud.tools.build.BackgroundColor3 = mode == "build" and Color3.fromRGB(92, 74, 30) or Color3.fromRGB(34, 44, 58)
	hud.tools.nuke.BackgroundColor3 = mode == "nuke" and Color3.fromRGB(120, 48, 44) or Color3.fromRGB(34, 44, 58)
	hud.tools.airstrike.BackgroundColor3 = mode == "airstrike" and Color3.fromRGB(120, 48, 44) or Color3.fromRGB(34, 44, 58)
end

local function nationName(id)
	local n = state.nations[id]
	return n and n.name or "?"
end

local function troopsToSend()
	local me = state.me
	return me and math.floor(me.troops * state.percent) or 0
end

local function relationText(rel)
	return ({ ally = "🤝 Aliado", war = "⚔ Em guerra", neutral = "Neutro" })[rel] or rel
end

local function nationPopover(screenPos, id)
	local n = state.nations[id]
	if not n or id == state.you then return end
	local rel = state:relation(state.you, id)
	local body = string.format("👥 %s · %.1f%% do mundo\n%s", Protocol.formatK(n.troops), n.land / Map.landCount * 100, relationText(rel))
	local buttons = {}
	if state.you then
		if rel == "ally" then
			buttons[#buttons + 1] = { "Cancelar aliança", function() send(Actions.BreakAlliance, id) end, true }
		else
			buttons[#buttons + 1] = { "🤝 Aliança", function() send(Actions.Ally, id) end }
			if rel ~= "war" then
				buttons[#buttons + 1] = { "⚔ Guerra", function() send(Actions.War, id) end, true }
			end
		end
	end
	hud:showPopover(screenPos, n.name, body, buttons)
end

local function aimOrder(cell)
	local o = state.owner[cell]
	local rel = o > 0 and state:relation(state.you, o) or "neutral"
	local origin = state:nearestBorder(state.you, cell)
	local color = Color3.fromRGB(255, 255, 255)
	local text
	if rel == "ally" then
		text = "Aliado: cancele a aliança para atacar"
		color = Color3.fromRGB(120, 200, 255)
	elseif o == 0 then
		text = "Clique de novo: expandir com " .. Protocol.formatK(troopsToSend())
	else
		text = "Clique de novo: atacar " .. nationName(o) .. " com " .. Protocol.formatK(troopsToSend())
		color = Color3.fromRGB(255, 140, 110)
	end
	overlay:setAim(origin, cell, text, color)
end

local function handleClick(p, button)
	hud:hidePopover()
	local cell = camera:screenToCell(p)
	if not cell then return end
	local owner = state.owner[cell]
	local phase = state.match.phase

	if button == 2 then
		if owner > 0 then nationPopover(p, owner) end
		return
	end
	if not state.you then
		if phase == "spawn" or phase == "playing" then
			if owner == -1 then hud:toast("Escolha uma célula de terra.", "bad") return end
			send(Actions.Spawn, cell)
		else
			hud:toast("Aguardando a próxima rodada.")
		end
		return
	end

	if mode == "build" and buildKind then
		send(Actions.Build, cell, buildKind)
		return
	elseif mode == "warship" then
		send(Actions.Warship, cell)
		setMode(nil)
		return
	elseif mode == "nuke" or mode == "airstrike" then
		local now = os.clock()
		if pending and pending.kind == mode and Map:distance(pending.cell, cell) <= Config.View.ConfirmRadius
			and now - pending.at <= Config.View.ConfirmTimeout then
			send(mode == "nuke" and Actions.Nuke or Actions.Airstrike, pending.cell)
			setMode(nil)
			return
		end
		pending = { cell = cell, at = now, kind = mode }
		local price = mode == "nuke" and Config.Strategic.NukeGold or Config.Strategic.AirstrikeGold
		overlay:setAim(nil, cell, string.format("Clique de novo para lançar %s · 💰 %s", mode == "nuke" and "☢" or "✈", Protocol.formatK(price)), Color3.fromRGB(255, 90, 80))
		return
	end

	if owner == state.you then
		clearAim()
		local b = state.buildings[cell]
		if b then
			local def = Config.Buildings[b.kind]
			local buttons = {}
			if b.kind == "port" then
				buttons[1] = { "🚢 Navio de guerra", function() send(Actions.Warship, cell) end }
			end
			hud:showPopover(p, def.icon .. " " .. def.name, def.description, buttons)
		end
		return
	end
	if owner == -1 then
		clearAim()
		hud:toast("Água não pode ser conquistada. Clique numa costa para invadir com um porto.")
		return
	end

	local now = os.clock()
	if not Config.View.TwoClickConfirm or (pending and pending.kind == "order"
		and Map:distance(pending.cell, cell) <= Config.View.ConfirmRadius and now - pending.at <= Config.View.ConfirmTimeout) then
		local target = pending and pending.cell or cell
		clearAim()
		send(Actions.Target, target, state.percent)
		return
	end
	pending = { cell = cell, at = now, kind = "order" }
	aimOrder(cell)
	if owner > 0 then nationPopover(p, owner) end
end

local function handleKey(key)
	local K = Enum.KeyCode
	if key == K.Escape then
		setMode(nil)
		hud:hidePopover()
	elseif key == K.Home or key == K.F then
		camera:fit()
	elseif key == K.B then
		setMode(mode ~= "build" and "build" or nil)
	elseif key == K.Space and state.you and state.nations[state.you] then
		camera:focusCell(state.nations[state.you].capital, math.max(camera.scale, camera:minScale() * 3))
	else
		local numbers = { K.One, K.Two, K.Three, K.Four, K.Five }
		for index, k in ipairs(numbers) do
			if key == k and Config.TroopPercents[index] then
				state.percent = Config.TroopPercents[index]
				hud:setPercent(state.percent)
				if pending and pending.kind == "order" then aimOrder(pending.cell) end
			end
		end
	end
end

local helpText = table.concat({
	"<b>Objetivo:</b> dominar " .. math.floor(Config.Match.VictoryPercent * 100) .. "% das terras do mundo.",
	"<b>Começar:</b> clique numa terra livre para fundar sua capital.",
	"<b>Expandir/atacar:</b> escolha o % de tropas, clique no destino e clique de novo para confirmar. A fronteira avança sozinha.",
	"<b>Mar:</b> construa um porto e clique numa costa do outro lado.",
	"<b>Câmera:</b> arraste para mover, roda do mouse/pinça para zoom, WASD, F para ver o mundo, Espaço para sua capital.",
	"<b>Atalhos:</b> 1–5 percentual, B construir, Esc cancelar, botão direito numa nação para diplomacia.",
}, "\n")

hud = HUD.new(state, gui, {
	onPercent = function(p)
		state.percent = p
		hud:setPercent(p)
		if pending and pending.kind == "order" then aimOrder(pending.cell) end
	end,
	onCancel = function() send(Actions.Cancel, nil) end,
	onTool = function(name)
		if name == "build" then setMode(mode ~= "build" and "build" or nil)
		elseif name == "nuke" or name == "airstrike" then
			setMode(mode ~= name and name or nil)
			if mode then hud:toast(name == "nuke" and "Escolha o alvo do míssil nuclear." or "Escolha um alvo inimigo para o ataque aéreo.") end
		elseif name == "ranking" then hud:toggleRanking()
		elseif name == "fit" then camera:fit()
		elseif name == "help" then hud:showCenter("Mundial War", helpText, true) end
	end,
	onBuild = function(kind)
		if buildKind == kind then setMode("build", nil) else setMode("build", kind) end
	end,
})

InputController.new(camera, Config, {
	onClick = handleClick,
	onKey = handleKey,
	onHover = function(p)
		if debugOverlay then debugOverlay:hover(p) end
	end,
})

-- Banner: phase, countdown and the active mode, refreshed four times per second.
task.spawn(function()
	while gui.Parent do
		local phase = state.match.phase
		local text
		if mode == "build" then
			text = buildKind and ("🏗 " .. Config.Buildings[buildKind].name .. " — clique numa célula sua · Esc sai") or "🏗 Escolha uma construção"
		elseif mode == "nuke" or mode == "airstrike" then
			text = (mode == "nuke" and "☢ Alvo nuclear" or "✈ Alvo do ataque aéreo") .. " · Esc cancela"
		elseif phase == "spawn" then
			local left = math.ceil(state:timeLeft())
			text = state.you and ("A guerra começa em " .. left .. "s") or ("Clique numa terra livre para fundar sua nação · " .. left .. "s")
		elseif phase == "playing" and not state.you then
			text = "Clique numa terra livre para fundar uma nova nação"
		elseif phase == "waiting" then
			text = "Preparando o mundo…"
		end
		hud:setBanner(text)
		task.wait(0.25)
	end
end)

-- Replication ------------------------------------------------------------------------------
local firstInit = true
local lastPhase, lastRound = nil, nil

local function onMatch(match)
	if match.phase == "ended" and match.winner and lastPhase ~= "ended" then
		local w = match.winner
		local mine = w.id == state.you
		hud:showCenter(mine and "VITÓRIA!" or "FIM DA PARTIDA",
			string.format("<b>%s</b> conquistou %.1f%% do mundo.\nNova rodada em instantes.", w.name, w.share * 100), false)
	elseif match.phase ~= "ended" and lastPhase == "ended" then
		hud:hideCenter()
	end
	if lastRound and match.round ~= lastRound then
		clearAim()
		setMode(nil)
	end
	lastPhase, lastRound = match.phase, match.round
end

eventRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local k = data.k
	if k == Events.Init then
		state:applyInit(data)
		onMatch(data.match)
		if firstInit then
			firstInit = false
			camera:fit()
			if data.debug and not debugOverlay then debugOverlay = DebugOverlay.new(state, camera, gui, world) end
		end
		hud:refreshRanking()
		hud:refreshMe()
	elseif k == Events.Tick then
		state:applyDelta(data)
	elseif k == Events.Nations then
		state:applyNations(data)
		if data.match then onMatch(data.match) end
		hud:refreshRanking()
	elseif k == Events.Orders then
		state:applyOrders(data)
	elseif k == Events.Notice then
		hud:toast(data.text, data.kind)
	elseif k == Events.Diplomacy then
		state:applyDiplomacy(data)
		if data.request then
			local from = data.request
			hud:allianceRequest(from, data.expires,
				function() send(Actions.Ally, from) end,
				function() send(Actions.Decline, from) end)
		end
	elseif k == Events.Match then
		state.match = { phase = data.phase, round = data.round, left = data.left, winner = data.winner }
		state.matchAt = os.clock()
		onMatch(state.match)
	elseif k == Events.Impact then
		state:applyImpact(data)
	elseif k == "me" then
		state:applyMe(data)
		hud:refreshMe()
	end
end)

state:on("nationList", function()
	hud:refreshRanking()
	if not state.you then hud:refreshMe() end
end)

send(Actions.Sync)
