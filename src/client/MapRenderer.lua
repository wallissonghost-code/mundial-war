-- Mundial War · paints the territory map. One pixel per cell in a single EditableImage
-- (one draw call, unaffected by graphics quality). Falls back to pooled row Frames when
-- EditableImage is unavailable (e.g. "Enable Mesh / Image APIs" not turned on).
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local MapRenderer = {}
MapRenderer.__index = MapRenderer

local BORDER_SHADE = 0.58
local COUNTRY_SHADE = 0.9

function MapRenderer.new(state, parent)
	local self = setmetatable({}, MapRenderer)
	self.state = state
	self.Map = state.Map
	self.Palette = state.Palette
	self.dirty = {}
	self.dirtyCount = 0
	self.fullDirty = true
	local W, H = self.Map.W, self.Map.H

	local image = Instance.new("ImageLabel")
	image.Name = "Territory"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.ZIndex = 1
	image.Parent = parent
	self.image = image

	local ok, editable = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)
	if ok and editable then
		local bound = pcall(function()
			image.ImageContent = Content.fromObject(editable)
		end)
		if bound then
			self.editable = editable
			self.buffer = buffer.create(W * H * 4)
		end
	end
	if not self.editable then
		warn("[MundialWar] EditableImage indisponível; usando renderizador de Frames. Ative 'Enable Mesh / Image APIs' nas configurações da experiência para o modo rápido.")
		image.Visible = false
		self.rowsFrame = Instance.new("Frame")
		self.rowsFrame.Name = "TerritoryRows"
		self.rowsFrame.BackgroundTransparency = 1
		self.rowsFrame.Size = UDim2.fromScale(1, 1)
		self.rowsFrame.ZIndex = 1
		self.rowsFrame.Parent = parent
		self.rowPools = {}
		self.dirtyRows = {}
	end
	self:recolor()

	state:on("init", function()
		self:recolor()
		self.fullDirty = true
	end)
	state:on("nationList", function()
		-- colours only; the cells of a new or removed nation arrive as territory deltas
		self:recolor()
	end)
	state:on("owners", function(cells)
		for _, i in ipairs(cells) do self:markAround(i) end
	end)
	self.connection = RunService.RenderStepped:Connect(function()
		self:flush()
	end)
	return self
end

-- Pre-computes fill/border/country-line colours for every nation id.
function MapRenderer:recolor()
	local P = self.Palette
	self.colors = {}
	for id, n in pairs(self.state.nations) do
		local base = P.Nations[n.color] or P.Neutral
		self.colors[id] = {
			fill = base,
			border = P.shade(base, BORDER_SHADE),
			line = P.shade(base, COUNTRY_SHADE),
		}
	end
	self.neutralColors = {
		fill = P.Neutral, line = P.CountryLine,
		water = P.Water, waterCoast = P.WaterCoast,
	}
	-- free land fades smoothly toward snow at high latitudes (no hard line at the polar circle)
	self.rowNeutral = {}
	for y = 0, self.Map.H - 1 do
		local t = math.max(0, math.min(1, (math.abs(self.Map.latitude[y]) - 56) / 24))
		self.rowNeutral[y] = P.mix(P.Neutral, P.NeutralPolar, t)
	end
end

function MapRenderer:markAround(i)
	local W, N = self.Map.W, self.Map.N
	local list = { i, i - W, i + W }
	local x = (i - 1) % W
	if x > 0 then list[#list + 1] = i - 1 end
	if x < W - 1 then list[#list + 1] = i + 1 end
	for _, j in ipairs(list) do
		if j >= 1 and j <= N and not self.dirty[j] then
			self.dirty[j] = true
			self.dirtyCount = self.dirtyCount + 1
		end
	end
end

-- Colour of one cell: water, neutral land (with faint country lines), or a nation
-- (darker band on its outer border so neighbouring empires read as separate shapes).
function MapRenderer:cellColor(i)
	local Map, owner = self.Map, self.state.owner
	local W, N = Map.W, Map.N
	local o = owner[i]
	local x = (i - 1) % W
	local c = self.neutralColors
	if o == -1 then
		return Map.landNear and Map.landNear[i] and c.waterCoast or c.water
	end
	local country = Map.country[i]
	local otherOwner, otherCountry = false, false
	local j, oj
	for k = 1, 4 do
		if k == 1 then j = x > 0 and i - 1 or nil
		elseif k == 2 then j = x < W - 1 and i + 1 or nil
		elseif k == 3 then j = i > W and i - W or nil
		else j = i <= N - W and i + W or nil end
		if j then
			oj = owner[j]
			if oj ~= -1 then
				if oj ~= o then otherOwner = true end
				if Map.country[j] ~= country then otherCountry = true end
			end
		end
	end
	if o == 0 then
		if otherCountry then return c.line end
		return self.rowNeutral[(i - 1 - x) / W]
	end
	local nc = self.colors[o]
	if not nc then return c.fill end
	if otherOwner then return nc.border end
	if otherCountry then return nc.line end
	return nc.fill
end

function MapRenderer:paintFull()
	local Map = self.Map
	if not Map.landNear then
		Map.landNear = {}
		for i = 1, Map.N do
			if not Map.land[i] then
				local x = (i - 1) % Map.W
				if (x > 0 and Map.land[i - 1]) or (x < Map.W - 1 and Map.land[i + 1])
					or (i > Map.W and Map.land[i - Map.W]) or (i <= Map.N - Map.W and Map.land[i + Map.W]) then
					Map.landNear[i] = true
				end
			end
		end
	end
	if self.editable then
		local buf = self.buffer
		for i = 1, Map.N do
			local c = self:cellColor(i)
			local o = (i - 1) * 4
			buffer.writeu8(buf, o, c[1])
			buffer.writeu8(buf, o + 1, c[2])
			buffer.writeu8(buf, o + 2, c[3])
			buffer.writeu8(buf, o + 3, 255)
		end
		self.editable:WritePixelsBuffer(Vector2.zero, Vector2.new(Map.W, Map.H), buf)
	else
		for y = 0, Map.H - 1 do self.dirtyRows[y] = true end
	end
	self.dirty, self.dirtyCount = {}, 0
end

function MapRenderer:paintDirty()
	local Map = self.Map
	local W = Map.W
	if self.editable then
		local buf = self.buffer
		local minX, minY, maxX, maxY = W, Map.H, -1, -1
		for i in pairs(self.dirty) do
			local c = self:cellColor(i)
			local o = (i - 1) * 4
			buffer.writeu8(buf, o, c[1])
			buffer.writeu8(buf, o + 1, c[2])
			buffer.writeu8(buf, o + 2, c[3])
			local x = (i - 1) % W
			local y = (i - 1 - x) / W
			if x < minX then minX = x end
			if x > maxX then maxX = x end
			if y < minY then minY = y end
			if y > maxY then maxY = y end
		end
		if maxX >= minX then
			local w, h = maxX - minX + 1, maxY - minY + 1
			if w * h > Map.N / 3 then
				self.editable:WritePixelsBuffer(Vector2.zero, Vector2.new(W, Map.H), buf)
			else
				local rect = buffer.create(w * h * 4)
				for row = 0, h - 1 do
					buffer.copy(rect, row * w * 4, buf, ((minY + row) * W + minX) * 4, w * 4)
				end
				self.editable:WritePixelsBuffer(Vector2.new(minX, minY), Vector2.new(w, h), rect)
			end
		end
	else
		for i in pairs(self.dirty) do
			local x = (i - 1) % W
			self.dirtyRows[(i - 1 - x) / W] = true
		end
	end
	self.dirty, self.dirtyCount = {}, 0
end

-- Fallback: one Frame per run of equal colour in a row, pooled and reused.
function MapRenderer:paintRow(y)
	local Map = self.Map
	local W, H = Map.W, Map.H
	local pool = self.rowPools[y]
	if not pool then pool = {} self.rowPools[y] = pool end
	local used, x = 0, 0
	while x < W do
		local c = self:cellColor(y * W + x + 1)
		local stop = x + 1
		while stop < W do
			local d = self:cellColor(y * W + stop + 1)
			if d[1] ~= c[1] or d[2] ~= c[2] or d[3] ~= c[3] then break end
			stop = stop + 1
		end
		used = used + 1
		local f = pool[used]
		if not f then
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.Parent = self.rowsFrame
			pool[used] = f
		end
		f.Position = UDim2.fromScale(x / W, y / H)
		f.Size = UDim2.new((stop - x) / W, 1, 1 / H, 1)
		f.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
		f.Visible = true
		x = stop
	end
	for k = used + 1, #pool do pool[k].Visible = false end
end

function MapRenderer:flush()
	if self.fullDirty then
		self.fullDirty = false
		self:paintFull()
	elseif self.dirtyCount > 0 then
		self:paintDirty()
	end
	if self.dirtyRows then
		local count = 0
		for y in pairs(self.dirtyRows) do
			self.dirtyRows[y] = nil
			self:paintRow(y)
			count = count + 1
			if count >= 12 then break end
		end
	end
end

return MapRenderer
