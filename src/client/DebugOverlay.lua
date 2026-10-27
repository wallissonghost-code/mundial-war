-- Mundial War · DEBUG_MODE overlay: cell under cursor, chunk grid, orders and bot states.
-- Only created when the server says GameConfig.DEBUG_MODE is on.
local DebugOverlay = {}
DebugOverlay.__index = DebugOverlay

local CHUNK = 64

function DebugOverlay.new(state, camera, gui, world)
	local self = setmetatable({}, DebugOverlay)
	self.state, self.camera = state, camera
	self.text = Instance.new("TextLabel")
	self.text.Name = "Debug"
	self.text.AnchorPoint = Vector2.new(0, 1)
	self.text.Position = UDim2.new(0, 12, 1, -84)
	self.text.Size = UDim2.fromOffset(330, 150)
	self.text.BackgroundColor3 = Color3.new(0, 0, 0)
	self.text.BackgroundTransparency = 0.4
	self.text.TextColor3 = Color3.fromRGB(140, 255, 160)
	self.text.Font = Enum.Font.Code
	self.text.TextSize = 12
	self.text.TextXAlignment = Enum.TextXAlignment.Left
	self.text.TextYAlignment = Enum.TextYAlignment.Top
	self.text.ZIndex = 60
	self.text.Parent = gui
	local grid = Instance.new("Frame")
	grid.Name = "ChunkGrid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1)
	grid.ZIndex = 3
	grid.Parent = world
	local Map = state.Map
	for x = CHUNK, Map.W - 1, CHUNK do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
		f.BackgroundTransparency = 0.6
		f.Position = UDim2.fromScale(x / Map.W, 0)
		f.Size = UDim2.new(0, 1, 1, 0)
		f.Parent = grid
	end
	for y = CHUNK, Map.H - 1, CHUNK do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
		f.BackgroundTransparency = 0.6
		f.Position = UDim2.fromScale(0, y / Map.H)
		f.Size = UDim2.new(1, 0, 0, 1)
		f.Parent = grid
	end
	return self
end

function DebugOverlay:hover(p)
	local state, Map = self.state, self.state.Map
	local cell = self.camera:screenToCell(p)
	if not cell then return end
	local x, y = Map:xy(cell)
	local country = Map.countries[Map.country[cell]]
	local owner = state.owner[cell]
	local n = state.nations[owner]
	local lines = {
		string.format("cell %d  (%d, %d)  chunk %d,%d", cell, x, y, math.floor(x / CHUNK), math.floor(y / CHUNK)),
		string.format("country %s  coast %s", country and country.code or "-", tostring(Map.coast[cell] == true)),
		string.format("owner %d %s", owner, n and n.name or ""),
		string.format("zoom %.2f px/cell  lod %d", self.camera.scale, self.camera:lod()),
		string.format("orders %d  fleets %d", #state.orders, (function() local c = 0 for _ in pairs(state.fleets) do c = c + 1 end return c end)()),
	}
	local bots = {}
	for _, b in ipairs(state.botStates or {}) do
		local bn = state.nations[b[1]]
		if bn and #bots < 6 then bots[#bots + 1] = string.sub(bn.name, 1, 12) .. ":" .. b[2] end
	end
	if #bots > 0 then lines[#lines + 1] = table.concat(bots, "  ") end
	self.text.Text = table.concat(lines, "\n")
end

return DebugOverlay
