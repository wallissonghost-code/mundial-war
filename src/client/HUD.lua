-- Mundial War · minimal interface around the map: player card, troop %, tools, ranking,
-- popovers and notices. Everything sits on the screen edges; the map stays the screen.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HUD = {}
HUD.__index = HUD

local FONT = Enum.Font.GothamMedium
local BOLD = Enum.Font.GothamBold
local PANEL = Color3.fromRGB(16, 22, 30)
local PANEL_T = 0.12
local TEXT = Color3.fromRGB(236, 238, 240)
local MUTED = Color3.fromRGB(150, 160, 172)
local ACCENT = Color3.fromRGB(240, 196, 92)
local GOOD = Color3.fromRGB(110, 200, 130)
local BAD = Color3.fromRGB(235, 110, 100)

local function make(class, parent, props)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local function panel(parent, props)
	local f = make("Frame", parent, props)
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = PANEL_T
	f.BorderSizePixel = 0
	make("UICorner", f, { CornerRadius = UDim.new(0, 8) })
	return f
end

local function button(parent, text, props)
	local b = make("TextButton", parent, props)
	b.Text = text
	b.Font = props and props.Font or BOLD
	b.TextSize = props and props.TextSize or 14
	b.TextColor3 = TEXT
	b.BackgroundColor3 = props and props.BackgroundColor3 or Color3.fromRGB(34, 44, 58)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	make("UICorner", b, { CornerRadius = UDim.new(0, 6) })
	return b
end

local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end

function HUD.new(state, gui, handlers)
	local self = setmetatable({}, HUD)
	self.state, self.gui, self.h = state, gui, handlers
	self.Config, self.Protocol = state.Config, state.Protocol
	local player = Players.LocalPlayer

	-- Player card (bottom-left) ----------------------------------------------------
	local card = panel(gui, { Name = "PlayerCard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(238, 64), ZIndex = 20 })
	local avatar = make("ImageLabel", card, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = Color3.fromRGB(60, 70, 84), BorderSizePixel = 0, ZIndex = 21 })
	make("UICorner", avatar, { CornerRadius = UDim.new(1, 0) })
	self.avatarStroke = make("UIStroke", avatar, { Thickness = 2, Color = TEXT })
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then avatar.Image = url end
	end)
	make("TextLabel", card, { Position = UDim2.fromOffset(64, 6), Size = UDim2.new(1, -70, 0, 18), BackgroundTransparency = 1, Font = BOLD, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = player.DisplayName, ZIndex = 21 })
	self.troopsText = make("TextLabel", card, { Position = UDim2.fromOffset(64, 25), Size = UDim2.new(1, -70, 0, 17), BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Text = "👥 —", ZIndex = 21 })
	self.goldText = make("TextLabel", card, { Position = UDim2.fromOffset(64, 43), Size = UDim2.new(1, -70, 0, 16), BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Text = "💰 —", ZIndex = 21 })

	-- Troop percentage (bottom-centre) ------------------------------------------------
	local bar = panel(gui, { Name = "Percent", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 20 })
	self.percentBar = bar
	make("UIListLayout", bar, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
	make("UIPadding", bar, { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
	self.percentButtons = {}
	for index, p in ipairs(self.Config.TroopPercents) do
		local b = button(bar, math.floor(p * 100) .. "%", { Size = UDim2.fromOffset(48, 30), LayoutOrder = index, TextSize = 13, ZIndex = 21 })
		b.Activated:Connect(function() self.h.onPercent(p) end)
		self.percentButtons[p] = b
	end
	self.cancelButton = button(bar, "✖", { Size = UDim2.fromOffset(40, 30), LayoutOrder = 10, BackgroundColor3 = Color3.fromRGB(110, 46, 44), ZIndex = 21 })
	self.cancelButton.Activated:Connect(function() self.h.onCancel() end)

	-- Tools (bottom-right) ---------------------------------------------------------------
	local tools = panel(gui, { Name = "Tools", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 20 })
	make("UIListLayout", tools, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
	make("UIPadding", tools, { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) })
	self.tools = {}
	local toolList = {
		{ "build", "🏗", "Construir" }, { "weapons", "💣", "Bombas e ataques" },
		{ "ranking", "🏆", "Ranking" }, { "fit", "🌍", "Ver o mundo" }, { "help", "?", "Ajuda" },
	}
	for index, t in ipairs(toolList) do
		local b = button(tools, t[2], { Size = UDim2.fromOffset(34, 30), LayoutOrder = index, TextSize = 16, ZIndex = 21 })
		b.Activated:Connect(function() self.h.onTool(t[1]) end)
		self.tools[t[1]] = b
	end
	-- weapons appear only after building an air base or a silo
	self.tools.weapons.Visible = false

	-- Build and weapon trays (above the tools): a grid of choices plus an explanation line ----
	local function tray(name, order, defs, onPick)
		local t = panel(gui, { Name = name, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -60), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 30 })
		make("UIPadding", t, { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
		make("UIListLayout", t, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
		local grid = make("Frame", t, { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 31 })
		make("UIGridLayout", grid, { CellSize = UDim2.fromOffset(141, 44), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder })
		local buttons = {}
		for index, kind in ipairs(order) do
			local b = button(grid, "", { LayoutOrder = index, ZIndex = 31, TextSize = 12 })
			b.RichText = true
			b.TextXAlignment = Enum.TextXAlignment.Left
			make("UIPadding", b, { PaddingLeft = UDim.new(0, 8) })
			b.Activated:Connect(function() onPick(kind) end)
			buttons[kind] = b
		end
		local info = make("TextLabel", t, { LayoutOrder = 2, BackgroundTransparency = 1, TextColor3 = MUTED, Font = FONT, TextSize = 12, TextWrapped = true, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", ZIndex = 31 })
		return t, buttons, info
	end
	self.tray, self.trayButtons, self.trayInfo = tray("BuildTray", self.Config.BuildingOrder, self.Config.Buildings, function(kind) self.h.onBuild(kind) end)
	self.weaponTray, self.weaponButtons, self.weaponInfo = tray("WeaponTray", self.Config.WeaponOrder, self.Config.Weapons, function(kind) self.h.onWeapon(kind) end)

	-- Top banner (phase / mode) and notices -------------------------------------------------
	self.banner = panel(gui, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 20, Visible = false })
	make("UIPadding", self.banner, { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) })
	self.bannerText = make("TextLabel", self.banner, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = BOLD, TextSize = 14, TextColor3 = ACCENT, ZIndex = 21 })
	self.toasts = make("Frame", gui, { Name = "Notices", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(460, 120), ZIndex = 25 })
	make("UIListLayout", self.toasts, { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })

	-- Ranking (top-right) and alliance requests ---------------------------------------------------
	self.ranking = panel(gui, { Name = "Ranking", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(210, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 20 })
	make("UIPadding", self.ranking, { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
	make("UIListLayout", self.ranking, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	self.rankRows = {}
	for k = 1, 8 do
		local row = make("TextLabel", self.ranking, { LayoutOrder = k, Size = UDim2.new(1, 0, 0, 17), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 21 })
		self.rankRows[k] = row
	end
	self.requests = make("Frame", gui, { Name = "Requests", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -230, 0, 10), Size = UDim2.fromOffset(250, 200), ZIndex = 25 })
	make("UIListLayout", self.requests, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })

	-- Popover (nation / cell) ------------------------------------------------------------------
	self.popover = panel(gui, { Name = "Popover", Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 40 })
	make("UIPadding", self.popover, { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
	make("UIListLayout", self.popover, { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })
	self.popTitle = make("TextLabel", self.popover, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = BOLD, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41 })
	self.popBody = make("TextLabel", self.popover, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, RichText = true, ZIndex = 41 })
	self.popButtons = make("Frame", self.popover, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 41 })
	make("UIGridLayout", self.popButtons, { CellSize = UDim2.new(0.5, -3, 0, 28), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder })

	-- Victory / help overlays ----------------------------------------------------------------------
	self.center = panel(gui, { Name = "Center", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 50 })
	make("UIPadding", self.center, { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) })
	make("UIListLayout", self.center, { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
	self.centerTitle = make("TextLabel", self.center, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Font = BOLD, TextSize = 28, TextColor3 = ACCENT, ZIndex = 51 })
	self.centerBody = make("TextLabel", self.center, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, TextSize = 14, TextColor3 = TEXT, TextWrapped = true, RichText = true, ZIndex = 51 })
	self.centerClose = button(self.center, "Fechar", { LayoutOrder = 3, Size = UDim2.fromOffset(120, 30), ZIndex = 51 })
	self.centerClose.Activated:Connect(function() self.center.Visible = false end)

	-- narrow screens (phones/tablets): lift the percentage bar above the player card
	local function layout()
		local narrow = gui.AbsoluteSize.X < 1000
		bar.Position = narrow and UDim2.new(0.5, 0, 1, -84) or UDim2.new(0.5, 0, 1, -12)
		if gui.AbsoluteSize.Y <= 420 then self.ranking.Visible = false end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	-- Mode menu: shown during the vote that opens every round -----------------------------------
	self.menu = panel(gui, { Name = "ModeMenu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 60 })
	make("UIPadding", self.menu, { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) })
	make("UIListLayout", self.menu, { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
	make("TextLabel", self.menu, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Font = BOLD, TextSize = 28, TextColor3 = ACCENT, Text = "MUNDIAL WAR", ZIndex = 61 })
	self.menuTimer = make("TextLabel", self.menu, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = MUTED, Text = "Escolha o modo da próxima partida", ZIndex = 61 })
	local cards = make("Frame", self.menu, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 61 })
	make("UIListLayout", cards, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })
	self.modeCards = {}
	for index, mode in ipairs(self.Config.ModeOrder) do
		local def = self.Config.Modes[mode]
		local card = make("Frame", cards, { LayoutOrder = index, Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(28, 38, 52), BorderSizePixel = 0, ZIndex = 61 })
		make("UICorner", card, { CornerRadius = UDim.new(0, 8) })
		local stroke = make("UIStroke", card, { Thickness = 2, Color = ACCENT, Transparency = 1 })
		make("UIPadding", card, { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
		make("UIListLayout", card, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
		make("TextLabel", card, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = BOLD, TextSize = 17, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, Text = def.icon .. " " .. def.name, ZIndex = 62 })
		make("TextLabel", card, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = def.description, ZIndex = 62 })
		local votes = make("TextLabel", card, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left, Text = "0 votos", ZIndex = 62 })
		local vote = button(card, "Votar", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 30), ZIndex = 62 })
		vote.Activated:Connect(function() self.h.onVote(mode) end)
		self.modeCards[mode] = { stroke = stroke, votes = votes }
	end

	self:setPercent(state.percent)
	return self
end

function HUD:setPercent(p)
	for value, b in pairs(self.percentButtons) do
		local on = math.abs(value - p) < 1e-6
		b.BackgroundColor3 = on and ACCENT or Color3.fromRGB(34, 44, 58)
		b.TextColor3 = on and Color3.fromRGB(30, 24, 10) or TEXT
	end
end

function HUD:toast(text, kind)
	if not text or text == "" then return end
	local color = kind == "bad" and BAD or kind == "good" and GOOD or kind == "war" and Color3.fromRGB(255, 140, 110) or TEXT
	local children = {}
	for _, c in ipairs(self.toasts:GetChildren()) do
		if c:IsA("TextLabel") then children[#children + 1] = c end
	end
	if #children >= 3 then children[1]:Destroy() end
	local t = make("TextLabel", self.toasts, {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1, Font = FONT, TextSize = 13, TextColor3 = color, Text = text,
		LayoutOrder = math.floor(os.clock() * 100) % 1000000, ZIndex = 26,
	})
	make("UICorner", t, { CornerRadius = UDim.new(0, 6) })
	make("UIPadding", t, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
	task.delay(4, function()
		if t.Parent then
			local tween = TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Connect(function() t:Destroy() end)
		end
	end)
end

function HUD:setBanner(text)
	self.banner.Visible = text ~= nil and text ~= ""
	self.bannerText.Text = text or ""
end

function HUD:refreshMe()
	local state = self.state
	local me = state.me
	local F = self.Protocol.formatK
	if not me or not state.you then
		self.troopsText.Text = "👥 —"
		self.goldText.Text = "💰 —"
		self.cancelButton.Visible = false
		return
	end
	self.troopsText.Text = string.format("👥 <b>%s</b> <font color=\"#96a0ac\">/ %s  +%s/s</font>", F(me.troops), F(me.max), F(me.rate))
	self.goldText.Text = string.format("💰 <b>%s</b> <font color=\"#96a0ac\">+%s/s · %.1f%% do mundo</font>", F(me.gold), F(me.goldRate), me.share * 100)
	if me.mode == "extreme" then
		self.goldText.Text = string.format("💰 <b>%s</b> <font color=\"#96a0ac\">+%s/s</font>  🛢 <b>%s</b> <font color=\"#96a0ac\">+%s/s</font>", F(me.gold), F(me.goldRate), F(me.oil), F(me.oilRate))
	end
	-- show only what exists in the current mode
	for kind, b in pairs(self.trayButtons) do
		local m = self.Config.Buildings[kind].mode
		b.Visible = m == nil or m == me.mode
	end
	for kind, b in pairs(self.weaponButtons) do
		local m = self.Config.Weapons[kind].mode
		b.Visible = m == nil or m == me.mode
	end
	self.avatarStroke.Color = rgb(state:nationColor(state.you))
	local mine = 0
	for _, o in ipairs(state.orders) do
		if o[2] == state.you then mine = mine + 1 end
	end
	self.cancelButton.Visible = mine > 0
	self.cancelButton.Text = mine > 1 and ("✖" .. mine) or "✖"
	-- weapons only once something can launch them
	self.tools.weapons.Visible = me.cooldowns ~= nil and (me.cooldowns.airfield ~= nil or me.cooldowns.silo ~= nil)
	if self.tray.Visible then self:refreshTray() end
	if self.weaponTray.Visible then self:refreshWeapons() end
end

function HUD:refreshTray()
	local me = self.state.me
	for kind, b in pairs(self.trayButtons) do
		local def = self.Config.Buildings[kind]
		local cost = me and me.costs and me.costs[kind] or def.cost
		local affordable = me and me.gold >= cost
		b.Text = string.format("%s <b>%s</b>\n<font size=\"11\" color=\"%s\">💰 %s</font>", def.icon, def.name, affordable and "#f0c45c" or "#8a8f96", self.Protocol.formatK(cost))
		b.BackgroundColor3 = (self.selectedBuild == kind) and Color3.fromRGB(92, 74, 30) or Color3.fromRGB(34, 44, 58)
		b.TextTransparency = affordable and 0 or 0.35
	end
	local kind = self.selectedBuild
	if kind then
		local def = self.Config.Buildings[kind]
		local lines = self.state.Stats.lines(self.Config, kind, 1)
		self.trayInfo.Text = "<b>" .. def.name .. "</b>: " .. def.purpose .. "\n" .. table.concat(lines, " · ")
	else
		self.trayInfo.Text = "Escolha uma construção para ver para que serve e o alcance; depois clique numa célula sua."
	end
end

function HUD:refreshWeapons()
	local me = self.state.me
	for kind, b in pairs(self.weaponButtons) do
		local w = self.Config.Weapons[kind]
		local ready = me and me.cooldowns and me.cooldowns[w.launcher]
		local affordable = me and me.gold >= w.gold and ready ~= nil
		local status = ready == nil and ("requer " .. self.Config.Buildings[w.launcher].name)
			or (ready > 0 and string.format("recarga %ds", math.ceil(ready)) or ("💰 " .. self.Protocol.formatK(w.gold)))
		b.Text = string.format("%s <b>%s</b>\n<font size=\"11\" color=\"%s\">%s</font>", w.icon, w.name, affordable and "#f0c45c" or "#8a8f96", status)
		b.BackgroundColor3 = (self.selectedWeapon == kind) and Color3.fromRGB(120, 48, 44) or Color3.fromRGB(34, 44, 58)
		b.TextTransparency = affordable and 0 or 0.35
	end
	local w = self.selectedWeapon and self.Config.Weapons[self.selectedWeapon]
	self.weaponInfo.Text = w and ("<b>" .. w.name .. "</b>: " .. w.purpose .. " Raio " .. w.radius .. ". Clique no alvo e confirme com um segundo clique.")
		or "Escolha uma arma. Aviões saem da base aérea; bombas EMP, atômica e de hidrogênio, do silo."
end

function HUD:showWeapons(visible, selected)
	self.weaponTray.Visible = visible
	self.selectedWeapon = selected
	if visible then self:refreshWeapons() end
end

function HUD:showTray(visible, selected)
	self.tray.Visible = visible
	self.selectedBuild = selected
	if visible then self:refreshTray() end
end

function HUD:refreshRanking()
	local state = self.state
	local list = {}
	for id, n in pairs(state.nations) do list[#list + 1] = n end
	table.sort(list, function(a, b) return a.land > b.land end)
	local total = state.Map.landCount
	for k, row in ipairs(self.rankRows) do
		local n = list[k]
		if n then
			local c = state.Palette.Nations[n.color] or state.Palette.Neutral
			local hex = string.format("#%02x%02x%02x", c[1], c[2], c[3])
			local you = n.id == state.you
			row.Text = string.format("<font color=\"%s\">■</font> %s%s <font color=\"#96a0ac\">%.1f%% · %s</font>",
				hex, you and "<b>" or "", n.name .. (you and "</b>" or ""), n.land / total * 100, self.Protocol.formatK(n.troops))
			row.Visible = true
		else
			row.Visible = false
		end
	end
end

function HUD:toggleRanking()
	self.ranking.Visible = not self.ranking.Visible
end

-- Popover near a screen point with a title, text and buttons { {label, fn, danger} }.
function HUD:showPopover(screenPos, title, body, buttons)
	self.popTitle.Text = title
	self.popBody.Text = body or ""
	for _, c in ipairs(self.popButtons:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for index, b in ipairs(buttons or {}) do
		local btn = button(self.popButtons, b[1], { LayoutOrder = index, TextSize = 12, ZIndex = 42, BackgroundColor3 = b[3] and Color3.fromRGB(120, 48, 44) or Color3.fromRGB(40, 58, 76) })
		btn.Activated:Connect(function()
			self:hidePopover()
			b[2]()
		end)
	end
	local size = self.gui.AbsoluteSize
	local x = math.clamp(screenPos.X + 16, 8, math.max(8, size.X - 236))
	local y = math.clamp(screenPos.Y - 20, 50, math.max(50, size.Y - 220))
	self.popover.Position = UDim2.fromOffset(x, y)
	self.popover.Visible = true
end

function HUD:hidePopover()
	self.popover.Visible = false
end

function HUD:showCenter(title, body, closable)
	self.centerTitle.Text = title
	self.centerBody.Text = body
	self.centerClose.Visible = closable ~= false
	self.center.Visible = true
end

function HUD:hideCenter()
	self.center.Visible = false
end

function HUD:allianceRequest(fromId, seconds, onAccept, onDecline)
	local n = self.state.nations[fromId]
	if not n then return end
	local card = panel(self.requests, { Size = UDim2.new(1, 0, 0, 62), ZIndex = 26 })
	make("TextLabel", card, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), BackgroundTransparency = 1, Font = BOLD, TextSize = 13, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, Text = "🤝 " .. n.name .. " propõe aliança", TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 27 })
	local yes = button(card, "Aceitar", { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(0.5, -14, 0, 26), BackgroundColor3 = Color3.fromRGB(46, 110, 64), TextSize = 12, ZIndex = 27 })
	local no = button(card, "Recusar", { Position = UDim2.new(0.5, 4, 0, 28), Size = UDim2.new(0.5, -14, 0, 26), TextSize = 12, ZIndex = 27 })
	yes.Activated:Connect(function() card:Destroy() onAccept() end)
	no.Activated:Connect(function() card:Destroy() onDecline() end)
	task.delay(seconds or 30, function() if card.Parent then card:Destroy() end end)
end


function HUD:refreshMenu(myVote)
	local match = self.state.match
	local show = match.phase == "vote"
	self.menu.Visible = show
	if not show then return end
	self.menuTimer.Text = "Escolha o modo da próxima partida · " .. math.ceil(self.state:timeLeft()) .. "s"
	for mode, c in pairs(self.modeCards) do
		local n = match.votes and match.votes[mode] or 0
		c.votes.Text = n .. (n == 1 and " voto" or " votos")
		c.stroke.Transparency = myVote == mode and 0 or 1
	end
end

return HUD
