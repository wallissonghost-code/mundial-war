-- Mundial War · everything drawn on top of the territory: nation names, capitals,
-- structures, fronts, fleets, missiles and the aiming arrow. Items live inside the
-- world frame with scale positions, so panning costs nothing; sizes follow the zoom (LOD).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local OverlayRenderer = {}
OverlayRenderer.__index = OverlayRenderer

local FONT = Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(20, 26, 34)

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function make(class, parent, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

function OverlayRenderer.new(state, camera, world)
	local self = setmetatable({}, OverlayRenderer)
	self.state, self.camera, self.Map = state, camera, state.Map
	self.Config, self.Protocol = state.Config, state.Protocol
	self.layer = make("Frame", world, { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	self.labels, self.capitals, self.icons, self.orderItems = {}, {}, {}, {}
	self.fleetItems, self.missileItems, self.shipItems = {}, {}, {}
	self.fireItems, self.cargoItems = {}, {}
	self.thumbs = {}
	self.aim = nil
	self.needsLayout = true

	state:on("init", function() self:rebuildAll() end)
	-- a nation joined or fell: create/remove only its own items (ids restart each round,
	-- which is handled by the full rebuild on "init")
	state:on("nationList", function() self.needsLayout = true end)
	state:on("nations", function() self:updateLabels() end)
	state:on("buildings", function() self:updateBuildings() end)
	state:on("orders", function() self:updateOrders() end)
	state:on("relations", function() self:updateLabels() end)
	state:on("impact", function(kind, cell, stopped) self:flash(kind, cell, stopped) end)
	camera:onChanged(function() self.needsLayout = true end)
	RunService.RenderStepped:Connect(function()
		if self.needsLayout then
			self.needsLayout = false
			self:updateLabels()
			self:updateBuildings()
			self:updateOrders()
		end
		self:animate()
	end)
	return self
end

function OverlayRenderer:pos(cell, dx, dy)
	local x, y = self.Map:xy(cell)
	return UDim2.fromScale((x + 0.5 + (dx or 0)) / self.Map.W, (y + 0.5 + (dy or 0)) / self.Map.H)
end

function OverlayRenderer:posXY(x, y)
	return UDim2.fromScale(x / self.Map.W, y / self.Map.H)
end

-- A straight line between two map points (cell units) that scales with the world frame.
function OverlayRenderer:line(frame, ax, ay, bx, by, thickness)
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = self:posXY((ax + bx) / 2, (ay + by) / 2)
	frame.Size = UDim2.new(length / self.Map.W, 0, 0, thickness or 2)
	frame.Rotation = math.deg(math.atan2(dy, dx))
end

function OverlayRenderer:center(cell)
	local x, y = self.Map:xy(cell)
	return x + 0.5, y + 0.5
end

function OverlayRenderer:rebuildAll()
	for _, l in pairs(self.labels) do l.frame:Destroy() end
	for _, c in pairs(self.capitals) do c:Destroy() end
	for _, icon in pairs(self.icons) do icon:Destroy() end
	self.labels, self.capitals, self.icons = {}, {}, {}
	self:updateLabels()
	self:updateBuildings()
	self:updateOrders()
end

-- Nation name/avatar/troops over the centre of each nation's largest block.
function OverlayRenderer:updateLabels()
	local state, cam = self.state, self.camera
	local lod = cam:lod()
	local scale = cam.scale
	local alive = {}
	for id, n in pairs(state.nations) do
		alive[id] = true
		local item = self.labels[id]
		if not item then
			local frame = make("Frame", self.layer, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6 })
			local list = make("UIListLayout", frame, { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 0) })
			list.SortOrder = Enum.SortOrder.LayoutOrder
			local head = make("Frame", frame, { BackgroundTransparency = 1, LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X })
			make("UIListLayout", head, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
			local avatar = make("ImageLabel", head, { BackgroundColor3 = rgb(state:nationColor(id)), BorderSizePixel = 0, LayoutOrder = 1, ZIndex = 6 })
			make("UICorner", avatar, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", avatar, { Color = WHITE, Thickness = 1.5 })
			local initial = make("TextLabel", avatar, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT, TextColor3 = WHITE, TextScaled = true, Text = string.sub(n.name, 1, (utf8.offset(n.name, 2) or 2) - 1), ZIndex = 7 })
			local name = make("TextLabel", head, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Font = FONT, TextColor3 = INK, TextStrokeColor3 = Color3.fromRGB(245, 242, 232), TextStrokeTransparency = 0.25, Text = n.name, LayoutOrder = 2, ZIndex = 6 })
			local troops = make("TextLabel", frame, { BackgroundTransparency = 1, Font = FONT, TextColor3 = INK, TextStrokeColor3 = Color3.fromRGB(245, 242, 232), TextStrokeTransparency = 0.35, LayoutOrder = 2, ZIndex = 6 })
			item = { frame = frame, head = head, avatar = avatar, initial = initial, name = name, troops = troops }
			self.labels[id] = item
			if n.userId and n.userId > 0 then
				task.spawn(function()
					local thumb = self.thumbs[n.userId]
					if not thumb then
						local ok, url = pcall(function()
							return Players:GetUserThumbnailAsync(n.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
						end)
						if ok then thumb = url self.thumbs[n.userId] = url end
					end
					if thumb and avatar.Parent then
						avatar.Image = thumb
						initial.Visible = false
					end
				end)
			end
			local cap = make("TextLabel", self.layer, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Text = "★", Font = FONT, TextColor3 = WHITE, TextStrokeColor3 = INK, TextStrokeTransparency = 0.2, ZIndex = 5 })
			self.capitals[id] = cap
		end
		-- size follows the on-screen size of the territory, clamped
		local area = math.max(1, n.labelSize or n.land or 1)
		local px = math.sqrt(area) * scale
		local font = math.clamp(px * 0.16, 9, 30)
		local isYou = id == state.you
		local visible = n.land > 0 and (isYou or (lod == 0 and px > 30) or (lod == 1 and px > 20) or lod == 2)
		item.frame.Visible = visible
		if visible then
			item.frame.Position = self:pos(n.labelCell or n.capital)
			item.frame.Size = UDim2.fromOffset(math.max(60, font * 10), font * 2.4)
			item.head.Size = UDim2.fromOffset(0, font * 1.3)
			item.avatar.Size = UDim2.fromOffset(font * 1.25, font * 1.25)
			item.name.TextSize = font
			item.name.Size = UDim2.fromOffset(0, font * 1.3)
			local rel = state:relation(state.you, id)
			item.name.Text = (rel == "ally" and "🤝 " or rel == "war" and "⚔ " or "") .. n.name
			item.troops.Visible = isYou or lod >= 1 or font >= 14
			item.troops.TextSize = math.max(9, font * 0.85)
			item.troops.Size = UDim2.fromOffset(font * 6, font * 1.1)
			item.troops.Text = self.Protocol.formatK(n.troops)
		end
		local cap = self.capitals[id]
		cap.Visible = n.land > 0 and (lod >= 1 or isYou)
		cap.Position = self:pos(n.capital)
		cap.TextSize = math.clamp(scale * 1.6, 10, 22)
		cap.Size = UDim2.fromOffset(cap.TextSize, cap.TextSize)
		cap.TextColor3 = isYou and Color3.fromRGB(255, 226, 120) or WHITE
	end
	for id, item in pairs(self.labels) do
		if not alive[id] then
			item.frame:Destroy()
			self.labels[id] = nil
			if self.capitals[id] then self.capitals[id]:Destroy() self.capitals[id] = nil end
		end
	end
end

function OverlayRenderer:updateBuildings()
	local state, cam = self.state, self.camera
	local lod = cam:lod()
	local defs = self.Config.Buildings
	local size = math.floor(math.clamp(cam.scale * 1.7, 12, 28))
	local sizeChanged = size ~= self.iconSize or lod ~= self.iconLod
	self.iconSize, self.iconLod = size, lod
	for cell, b in pairs(state.buildings) do
		local icon = self.icons[cell]
		local fresh = false
		if not icon or icon:GetAttribute("Kind") ~= b.kind then
			if icon then icon:Destroy() end
			icon = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Font = FONT, TextScaled = true, ZIndex = 4 })
			make("UICorner", icon, { CornerRadius = UDim.new(0.3, 0) })
			make("UIStroke", icon, { Color = WHITE, Thickness = 1, Transparency = 0.2 })
			icon:SetAttribute("Kind", b.kind)
			icon.Text = defs[b.kind] and defs[b.kind].icon or "?"
			icon.Position = self:pos(cell)
			self.icons[cell] = icon
			fresh = true
		end
		if fresh or icon:GetAttribute("Owner") ~= b.owner or icon:GetAttribute("Level") ~= b.level or icon:GetAttribute("Off") ~= b.off then
			icon:SetAttribute("Owner", b.owner)
			icon:SetAttribute("Level", b.level)
			icon:SetAttribute("Off", b.off)
			icon.BackgroundColor3 = b.off and Color3.fromRGB(70, 70, 70) or rgb(state.Palette.shade(state:nationColor(b.owner), 0.75))
			local badge = icon:FindFirstChild("Level") or make("TextLabel", icon, { Name = "Level", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1.15, 1.15), Size = UDim2.fromScale(0.55, 0.55), BackgroundColor3 = INK, TextColor3 = Color3.fromRGB(240, 196, 92), Font = FONT, TextScaled = true, BorderSizePixel = 0, ZIndex = 5 })
			badge.Text = tostring(b.level)
			badge.Visible = b.level > 1
		end
		if fresh or sizeChanged then
			icon.Size = UDim2.fromOffset(size, size)
			-- world view hides structures; our own appear once zoomed in a little
			icon.Visible = lod >= 1
		end
	end
	for cell, icon in pairs(self.icons) do
		if not state.buildings[cell] then
			icon:Destroy()
			self.icons[cell] = nil
		end
	end
end

local function pool(list, key, factory)
	local item = list[key]
	if not item then
		item = factory()
		list[key] = item
	end
	item.used = true
	return item
end

local function release(list)
	for key, item in pairs(list) do
		if item.used then
			item.used = false
		else
			for _, inst in pairs(item) do
				if typeof(inst) == "Instance" then inst:Destroy() end
			end
			list[key] = nil
		end
	end
end

-- Fronts: arrow from where the order left our border to the clicked point, plus the
-- troops still in the field next to the active front cell.
function OverlayRenderer:updateOrders()
	local state, cam = self.state, self.camera
	local lod = cam:lod()
	for _, o in ipairs(state.orders) do
		local id, nation, target, troops, front, anchor, origin = o[1], o[2], o[3], o[4], o[5], o[6], o[7]
		local mine = nation == state.you
		local item = pool(self.orderItems, id, function()
			return {
				line = make("Frame", self.layer, { BorderSizePixel = 0, ZIndex = 3, BackgroundTransparency = 0.25 }),
				ring = make("Frame", self.layer, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 }),
				label = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.25, TextColor3 = WHITE, Font = FONT, ZIndex = 7, AutomaticSize = Enum.AutomaticSize.X }),
			}
		end)
		if not item.ring:FindFirstChild("Stroke") then
			make("UICorner", item.ring, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", item.ring, { Name = "Stroke", Thickness = 2, Color = WHITE })
			make("UICorner", item.label, { CornerRadius = UDim.new(0, 4) })
		end
		local color = rgb(state:nationColor(nation))
		local showArrow = mine and origin and origin > 0
		item.line.Visible = showArrow
		item.ring.Visible = mine
		if showArrow then
			local ax, ay = self:center(origin)
			local bx, by = self:center(anchor)
			self:line(item.line, ax, ay, bx, by, 2)
			item.line.BackgroundColor3 = color
		end
		item.ring.Position = self:pos(anchor)
		item.ring.Size = UDim2.fromOffset(14, 14)
		item.ring.Stroke.Color = color
		local showLabel = front and front > 0 and (mine or lod >= 1 or troops >= 5000)
		item.label.Visible = showLabel
		if showLabel then
			item.label.Position = self:pos(front, 0, -0.6)
			item.label.TextSize = mine and 13 or 11
			item.label.Text = (target == 0 and " ➜ " or " ⚔ ") .. self.Protocol.formatK(troops) .. " "
			item.label.Size = UDim2.fromOffset(0, mine and 18 or 15)
			item.label.BackgroundColor3 = mine and Color3.fromRGB(30, 44, 60) or INK
		end
	end
	release(self.orderItems)

	for _, w in ipairs(state.boats) do
		local id, nation, x, y, health, patrol = w[1], w[2], w[3], w[4], w[5], w[6]
		local mine = nation == state.you
		local item = pool(self.shipItems, id, function()
			local it = {
				icon = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "🚢", TextScaled = true, Font = FONT, ZIndex = 6 }),
				bar = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0), BorderSizePixel = 0, BackgroundColor3 = INK, ZIndex = 6 }),
				ring = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 3 }),
			}
			make("Frame", it.bar, { Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(110, 200, 130), ZIndex = 7 })
			make("UICorner", it.ring, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", it.ring, { Name = "Stroke", Thickness = 1, Transparency = 0.4 })
			return it
		end)
		local s = math.clamp(cam.scale * 1.8, 14, 26)
		local visible = lod >= 1 or mine
		-- glide between the 0.4 s server updates
		if item.x ~= x or item.y ~= y then
			item.x, item.y = x, y
			local info = TweenInfo.new(self.Config.Tick.PublicOrders, Enum.EasingStyle.Linear)
			TweenService:Create(item.icon, info, { Position = self:posXY(x, y) }):Play()
			TweenService:Create(item.bar, info, { Position = self:posXY(x, y + 0.9) }):Play()
		end
		item.icon.Size = UDim2.fromOffset(s, s)
		item.icon.Visible = visible
		item.bar.Size = UDim2.fromOffset(s, 3)
		item.bar.Visible = visible
		item.bar.Fill.Size = UDim2.fromScale(math.clamp(health / self.Config.Naval.BoatHealth, 0, 1), 1)
		item.bar.Fill.BackgroundColor3 = rgb(state:nationColor(nation))
		-- our own boats show their patrol circle
		item.ring.Visible = mine and patrol ~= nil
		if patrol then
			local r = self.Config.Naval.BoatOrbit + 1
			item.ring.Position = self:pos(patrol)
			item.ring.Size = UDim2.fromScale(r * 2 / self.Map.W, r * 2 / self.Map.H)
			item.ring.Stroke.Color = rgb(state:nationColor(nation))
		end
	end
	release(self.shipItems)

	-- fires: a translucent blaze that grows with the server's radius
	for _, f in ipairs(state.fires or {}) do
		local id, center, radius = f[1], f[2], f[3]
		local item = pool(self.fireItems, id, function()
			local it = { glow = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 120, 30), BackgroundTransparency = 0.45, ZIndex = 4 }) }
			make("UICorner", it.glow, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", it.glow, { Color = Color3.fromRGB(255, 70, 20), Thickness = 2 })
			local core = make("Frame", it.glow, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.55, 0.55), BackgroundColor3 = Color3.fromRGB(255, 200, 60), BackgroundTransparency = 0.35, ZIndex = 4 })
			make("UICorner", core, { CornerRadius = UDim.new(1, 0) })
			return it
		end)
		item.glow.Position = self:pos(center)
		item.glow.Size = UDim2.fromScale(radius * 2 / self.Map.W, radius * 2 / self.Map.H)
	end
	release(self.fireItems)

	-- cargo ships carrying gold home
	for _, c in ipairs(state.cargos or {}) do
		local id, nation, cell = c[1], c[2], c[3]
		local item = pool(self.cargoItems, id, function()
			return { icon = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "🚤", TextScaled = true, Font = FONT, ZIndex = 5 }) }
		end)
		local size = math.clamp(cam.scale * 1.3, 10, 18)
		item.icon.Size = UDim2.fromOffset(size, size)
		item.icon.Visible = lod >= 1 or nation == state.you
		if item.cell ~= cell then
			item.cell = cell
			TweenService:Create(item.icon, TweenInfo.new(self.Config.Tick.PublicOrders, Enum.EasingStyle.Linear), { Position = self:pos(cell) }):Play()
		end
	end
	release(self.cargoItems)
end

-- Fleets and missiles move every frame between server updates.
function OverlayRenderer:animate()
	local state, Map = self.state, self.Map
	local now = os.clock()
	for id, f in pairs(state.fleets) do
		local item = pool(self.fleetItems, id, function()
			local it = {
				icon = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = INK, BackgroundTransparency = 0.2, TextColor3 = WHITE, Font = FONT, TextSize = 12, ZIndex = 8, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18) }),
				route = make("Frame", self.layer, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }),
			}
			make("UICorner", it.icon, { CornerRadius = UDim.new(0, 4) })
			-- simplified route polyline (one segment every 6 water cells)
			local color = rgb(state:nationColor(f.nation))
			local path = f.path
			local step = 6
			local prev = path[1]
			for k = 1 + step, #path + step - 1, step do
				local cell = path[math.min(k, #path)]
				local seg = make("Frame", it.route, { BorderSizePixel = 0, BackgroundColor3 = color, BackgroundTransparency = 0.35, ZIndex = 3 })
				local ax, ay = self:center(prev)
				local bx, by = self:center(cell)
				self:line(seg, ax, ay, bx, by, 2)
				prev = cell
			end
			return it
		end)
		local progress = math.min(#f.path, f.progress + (now - f.t0) * f.speed)
		local k = math.max(1, math.floor(progress))
		local a, b = f.path[k], f.path[math.min(#f.path, k + 1)]
		local ax, ay = self:center(a)
		local bx, by = self:center(b)
		local t = progress - k
		item.icon.Position = self:posXY(ax + (bx - ax) * t, ay + (by - ay) * t)
		item.icon.Text = (f.air and " 🪂 " or " ⛵ ") .. self.Protocol.formatK(f.troops) .. " "
		item.route.Visible = f.nation == state.you or self.camera:lod() >= 1
	end
	release(self.fleetItems)
	for id, m in pairs(state.missiles) do
		local item = pool(self.missileItems, id, function()
			local it = {
				icon = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = (self.Config.Weapons[m.kind] or { icon = "✈" }).icon, TextColor3 = Color3.fromRGB(255, 230, 120), TextStrokeTransparency = 0, Font = FONT, TextSize = 20, ZIndex = 9 }),
				target = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 8 }),
			}
			make("UICorner", it.target, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", it.target, { Color = Color3.fromRGB(230, 60, 50), Thickness = 2 })
			return it
		end)
		local ax, ay = self:center(m.from)
		local bx, by = self:center(m.to)
		local dist = math.max(1, math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2))
		local t = math.min(1, (m.progress + (now - m.t0) * m.speed) / dist)
		item.icon.Position = self:posXY(ax + (bx - ax) * t, ay + (by - ay) * t)
		local radius = (self.Config.Weapons[m.kind] or { radius = 3 }).radius
		item.target.Position = self:pos(m.to)
		item.target.Size = UDim2.fromScale(radius * 2 / Map.W, radius * 2 / Map.H)
	end
	release(self.missileItems)
end

function OverlayRenderer:flash(kind, cell, stopped)
	local radius = (self.Config.Weapons[kind] or { radius = 3 }).radius
	local ring = make("Frame", self.layer, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = self:pos(cell), ZIndex = 9,
		BackgroundColor3 = stopped and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(255, 210, 120),
		BackgroundTransparency = 0.1, Size = UDim2.fromScale(0, 0),
	})
	make("UICorner", ring, { CornerRadius = UDim.new(1, 0) })
	local target = UDim2.fromScale(radius * 2.4 / self.Map.W, radius * 2.4 / self.Map.H)
	local tween = TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = target, BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function() ring:Destroy() end)
end

-- Reach circles: { { cell, radius, color } } (build preview, selected building, own defences).
function OverlayRenderer:setRanges(list)
	self.rangeItems = self.rangeItems or {}
	for k, r in ipairs(list) do
		local ring = self.rangeItems[k]
		if not ring then
			ring = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0.88, ZIndex = 3 })
			make("UICorner", ring, { CornerRadius = UDim.new(1, 0) })
			make("UIStroke", ring, { Name = "Stroke", Thickness = 1.5, Transparency = 0.15 })
			self.rangeItems[k] = ring
		end
		ring.Visible = true
		ring.Position = self:pos(r[1])
		ring.Size = UDim2.fromScale(r[2] * 2 / self.Map.W, r[2] * 2 / self.Map.H)
		ring.BackgroundColor3 = r[3]
		ring.Stroke.Color = r[3]
	end
	for k = #list + 1, #self.rangeItems do self.rangeItems[k].Visible = false end
end

-- Aim preview for the two-click order: arrow from our nearest border to the target.
function OverlayRenderer:setAim(fromCell, toCell, text, color)
	if not self.aim then
		self.aim = {
			line = make("Frame", self.layer, { BorderSizePixel = 0, ZIndex = 8, BackgroundTransparency = 0.1 }),
			ring = make("Frame", self.layer, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 8, Size = UDim2.fromOffset(18, 18) }),
			label = make("TextLabel", self.layer, { AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.1, TextColor3 = WHITE, Font = FONT, TextSize = 13, ZIndex = 9, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22) }),
		}
		make("UICorner", self.aim.ring, { CornerRadius = UDim.new(1, 0) })
		make("UIStroke", self.aim.ring, { Name = "Stroke", Thickness = 2.5, Color = WHITE })
		make("UICorner", self.aim.label, { CornerRadius = UDim.new(0, 5) })
		make("UIPadding", self.aim.label, { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
	end
	local aim = self.aim
	if not toCell then
		aim.line.Visible, aim.ring.Visible, aim.label.Visible = false, false, false
		return
	end
	aim.ring.Visible, aim.label.Visible = true, true
	aim.ring.Position = self:pos(toCell)
	aim.ring.Stroke.Color = color or WHITE
	aim.line.Visible = fromCell ~= nil
	if fromCell then
		local ax, ay = self:center(fromCell)
		local bx, by = self:center(toCell)
		self:line(aim.line, ax, ay, bx, by, 3)
		aim.line.BackgroundColor3 = color or WHITE
	end
	aim.label.Text = text
	aim.label.Position = self:pos(toCell, 0, -1.2)
end

return OverlayRenderer
