-- Mundial War · client bootstrap: full-screen strategic map, HUD, input and replication.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("MundialWarShared")
local Config = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local Palette = require(Shared.Palette)
local MapGrid = require(Shared.MapGrid)
local BuildingStats = require(Shared.BuildingStats)

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
local state = ClientState.new(Map, Protocol, Config, Palette, BuildingStats)

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
-- Map drawing mode: GameConfig.View.MapRenderer, never "image" when the server found the
-- image APIs disabled; the 🗺 button switches for this session.
local function preferredMapMode()
	if ReplicatedStorage:GetAttribute("MW_ImageApis") == false then return "frames" end
	return Config.View.MapRenderer
end
local renderer = MapRenderer.new(state, world, { frames = preferredMapMode() ~= "image" })
local function switchMapMode()
	local wantImage = renderer:mode() ~= "image"
	if wantImage and ReplicatedStorage:GetAttribute("MW_ImageApis") == false then
		return false, "O modo imagem precisa de 'Enable Mesh / Image APIs' ativado nas configurações do jogo."
	end
	renderer:dispose()
	renderer = MapRenderer.new(state, world, { frames = not wantImage })
	renderer.fullDirty = true
	if wantImage and renderer:mode() ~= "image" then
		return false, "O modo imagem não está disponível aqui; mantendo o mapa compatível."
	end
	return true, wantImage and "Mapa em modo imagem (mais leve). Se aparecer xadrez rosa e azul, toque em 🗺 de novo." or "Mapa em modo compatível."
end
local overlay = OverlayRenderer.new(state, camera, world)
local debugOverlay = nil

local function send(action, a, b, c)
	commandRemote:FireServer(action, a, b, c)
end

-- Interaction state ------------------------------------------------------------------------
local mode = nil          -- nil | "build" | "weapon" | "patrol"
local buildKind = nil     -- building kind (build mode) or weapon kind (weapon mode)
local patrolBoat = nil    -- boat id while choosing where it patrols
local selectedCell = nil  -- own building whose reach is being shown
local pending = nil       -- { cell, at, kind }
local hud
local myVote = nil

local function clearAim()
	pending = nil
	overlay:setAim(nil, nil)
end

local updateRanges
local function setMode(newMode, kind)
	mode, buildKind = newMode, kind
	if mode ~= "patrol" then patrolBoat = nil end
	clearAim()
	selectedCell = nil
	hud:showTray(mode == "build", mode == "build" and buildKind or nil)
	hud:showWeapons(mode == "weapon", mode == "weapon" and buildKind or nil)
	hud.tools.build.BackgroundColor3 = mode == "build" and Color3.fromRGB(92, 74, 30) or Color3.fromRGB(34, 44, 58)
	hud.tools.weapons.BackgroundColor3 = mode == "weapon" and Color3.fromRGB(120, 48, 44) or Color3.fromRGB(34, 44, 58)
	updateRanges(nil)
end

-- Reach circles: where the chosen building/bomb would act, plus our existing defences.
local hoverCell = nil
updateRanges = function(cell)
	if cell ~= nil then hoverCell = cell end
	local list = {}
	local gold, red, blue = Color3.fromRGB(240, 196, 92), Color3.fromRGB(235, 90, 80), Color3.fromRGB(120, 200, 255)
	if mode == "build" then
		for c, b in pairs(state.buildings) do
			if b.owner == state.you and Config.Buildings[b.kind].defensive then
				list[#list + 1] = { c, BuildingStats.reach(Config, b.kind, b.level), blue }
			end
		end
		local r = buildKind and BuildingStats.reach(Config, buildKind, 1)
		if r and hoverCell and Map.land[hoverCell] then list[#list + 1] = { hoverCell, r, gold } end
	elseif mode == "weapon" and buildKind then
		local w = Config.Weapons[buildKind]
		if w.launcher == "airfield" then
			for c, b in pairs(state.buildings) do
				if b.owner == state.you and b.kind == "airfield" then list[#list + 1] = { c, BuildingStats.reach(Config, "airfield", b.level), blue } end
			end
		end
		if hoverCell then list[#list + 1] = { hoverCell, w.radius, red } end
	elseif selectedCell and state.buildings[selectedCell] then
		local b = state.buildings[selectedCell]
		local r = BuildingStats.reach(Config, b.kind, b.level)
		if r then list[#list + 1] = { selectedCell, r, gold } end
	end
	overlay:setRanges(list)
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
	if not mode and selectedCell then
		selectedCell = nil
		updateRanges(nil)
	end
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

	if mode == "build" then
		if buildKind then send(Actions.Build, cell, buildKind) else hud:toast("Escolha uma construção na lista.") end
		return
	elseif mode == "patrol" then
		if Map.land[cell] then hud:toast("Escolha um ponto na água para o barco patrulhar.", "bad") return end
		send(Actions.Patrol, patrolBoat, cell)
		setMode(nil)
		return
	elseif mode == "weapon" then
		if not buildKind then hud:toast("Escolha uma arma na lista.") return end
		local w = Config.Weapons[buildKind]
		local now = os.clock()
		if pending and pending.kind == "weapon" and Map:distance(pending.cell, cell) <= Config.View.ConfirmRadius
			and now - pending.at <= Config.View.ConfirmTimeout then
			send(Actions.Weapon, pending.cell, buildKind, state.percent)
			setMode(nil)
			return
		end
		pending = { cell = cell, at = now, kind = "weapon" }
		overlay:setAim(nil, cell, string.format("Clique de novo para lançar %s %s · 💰 %s", w.icon, w.name, Protocol.formatK(w.gold)), Color3.fromRGB(255, 90, 80))
		return
	end

	-- clicking one of our boats selects it; the next click on water sets its patrol
	local mx, my = camera:screenToMap(p)
	local boat = state:boatNear(state.you, mx, my, math.max(1.5, 12 / camera.scale))
	if boat then
		setMode("patrol")
		patrolBoat = boat[1]
		hud:toast("Barco selecionado: clique na água onde ele deve patrulhar.")
		return
	end

	if owner == state.you then
		clearAim()
		local b = state.buildings[cell]
		if b then
			local def = Config.Buildings[b.kind]
			local body = def.purpose .. "\n" .. table.concat(BuildingStats.lines(Config, b.kind, b.level), " · ")
			if b.off then body = "⚡ Desligada por EMP.\n" .. body end
			local buttons = {}
			local cost = BuildingStats.upgradeCost(Config, b.kind, b.level)
			if cost then
				body = body .. "\nNível " .. (b.level + 1) .. ": " .. table.concat(BuildingStats.lines(Config, b.kind, b.level + 1), " · ")
				buttons[#buttons + 1] = { "⬆ Melhorar · 💰 " .. Protocol.formatK(cost), function() send(Actions.Upgrade, cell) end }
			end
			if b.kind == "port" then
				buttons[#buttons + 1] = { "🚢 Barco · 💰 " .. Protocol.formatK(Config.Naval.BoatGold), function() send(Actions.Warship, cell) end }
			end
			hud:showPopover(p, def.icon .. " " .. def.name .. " · Nível " .. b.level, body, buttons)
			selectedCell = cell
			updateRanges(nil)
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
	"<b>Expandir/atacar:</b> escolha o % de tropas e clique no destino. A fronteira avança sozinha.",
	"<b>Construções:</b> 🏗 mostra para que serve cada uma e o alcance no mapa. Clique numa construção sua para melhorar o nível.",
	"<b>Mar:</b> construa um porto e clique numa costa do outro lado. No porto, compre barcos de defesa; clique num barco e depois na água para escolher a patrulha.",
	"<b>Bombas:</b> 💣 aparece quando você tem base aérea ou silo. Clique no alvo e confirme com um segundo clique.",
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
		elseif name == "weapons" then
			setMode(mode ~= "weapon" and "weapon" or nil)
		elseif name == "ranking" then hud:toggleRanking()
		elseif name == "fit" then camera:fit()
		elseif name == "mapmode" then
			local ok, msg = switchMapMode()
			hud:toast(msg, ok and "good" or "bad")
		elseif name == "help" then hud:showCenter("Mundial War", helpText, true) end
	end,
	onBuild = function(kind)
		if buildKind == kind then setMode("build", nil) else setMode("build", kind) end
	end,
	onVote = function(mode)
		myVote = mode
		send(Actions.Vote, mode)
		hud:refreshMenu(myVote)
	end,
	onWeapon = function(kind)
		if buildKind == kind then setMode("weapon", nil) else setMode("weapon", kind) end
	end,
})

InputController.new(camera, Config, {
	onClick = handleClick,
	onKey = handleKey,
	onHover = function(p)
		if debugOverlay then debugOverlay:hover(p) end
		if mode == "build" or mode == "weapon" then updateRanges(camera:screenToCell(p)) end
	end,
})

-- Banner: phase, countdown and the active mode, refreshed four times per second.
task.spawn(function()
	while gui.Parent do
		local phase = state.match.phase
		local text
		if mode == "build" then
			text = buildKind and ("🏗 " .. Config.Buildings[buildKind].name .. " — clique numa célula sua · Esc sai") or "🏗 Escolha uma construção"
		elseif mode == "weapon" then
			text = buildKind and (Config.Weapons[buildKind].icon .. " Escolha o alvo · Esc cancela") or "💣 Escolha uma arma"
		elseif mode == "patrol" then
			text = "🚢 Clique na água onde o barco deve patrulhar · Esc cancela"
		elseif phase == "spawn" then
			local left = math.ceil(state:timeLeft())
			if state.match.mode == "extreme" then
				text = state.you and ("A guerra começa em " .. left .. "s") or ("🔥 Clique num país para governá-lo · " .. left .. "s")
			else
				text = state.you and ("A guerra começa em " .. left .. "s") or ("Clique numa terra livre para fundar sua nação · " .. left .. "s")
			end
		elseif phase == "playing" and not state.you then
			text = state.match.mode == "extreme" and "🔥 Clique num país controlado pela IA para governá-lo"
				or "Clique numa terra livre para fundar uma nova nação"
		elseif phase == "vote" then
			text = nil
		elseif phase == "waiting" then
			text = "Preparando o mundo…"
		end
		hud:setBanner(text)
		hud:refreshMenu(myVote)
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
		myVote = nil
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
		state.match = { phase = data.phase, round = data.round, left = data.left, winner = data.winner, mode = data.mode, votes = data.votes }
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
