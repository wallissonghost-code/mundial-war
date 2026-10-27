-- Mundial War · strategy camera over the 2D map: pan, zoom toward the cursor, bounds.
-- The map frame is moved/resized; nothing in the 3D world is involved.
local CameraController = {}
CameraController.__index = CameraController

function CameraController.new(viewport, world, Map, Config)
	local self = setmetatable({}, CameraController)
	self.viewport = viewport      -- full-screen clipping frame
	self.world = world            -- frame sized W*scale x H*scale holding map + overlays
	self.Map = Map
	self.Config = Config
	self.scale = 1
	self.cx, self.cy = Map.W / 2, Map.H / 2
	self.listeners = {}
	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local wasFit = self.scale <= self:minScale() + 1e-3
		if wasFit then self:fit() else self:apply() end
	end)
	return self
end

function CameraController:onChanged(fn)
	table.insert(self.listeners, fn)
end

function CameraController:minScale()
	local size = self.viewport.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return 1 end
	-- whole world visible; the ocean-coloured viewport fills any remaining margin
	return math.min(size.X / self.Map.W, size.Y / self.Map.H)
end

function CameraController:maxScale()
	return math.max(self:minScale() * 2, self.Config.View.MaxPixelsPerCell)
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Keeps the map covering the viewport: no scrolling into empty space.
function CameraController:clampCenter()
	local size = self.viewport.AbsoluteSize
	local halfW, halfH = size.X / (2 * self.scale), size.Y / (2 * self.scale)
	if halfW * 2 >= self.Map.W then
		self.cx = self.Map.W / 2
	else
		self.cx = clamp(self.cx, halfW, self.Map.W - halfW)
	end
	if halfH * 2 >= self.Map.H then
		self.cy = self.Map.H / 2
	else
		self.cy = clamp(self.cy, halfH, self.Map.H - halfH)
	end
end

function CameraController:apply()
	self.scale = clamp(self.scale, self:minScale(), self:maxScale())
	self:clampCenter()
	local size = self.viewport.AbsoluteSize
	local s = self.scale
	self.world.Size = UDim2.fromOffset(self.Map.W * s, self.Map.H * s)
	self.world.Position = UDim2.fromOffset(size.X / 2 - self.cx * s, size.Y / 2 - self.cy * s)
	for _, fn in ipairs(self.listeners) do fn(s) end
end

function CameraController:fit()
	self.scale = self:minScale()
	self.cx, self.cy = self.Map.W / 2, self.Map.H / 2
	self:apply()
end

-- Screen position (same space as GuiObject.AbsolutePosition) -> fractional cell coordinates.
function CameraController:screenToMap(p)
	local origin = self.world.AbsolutePosition
	return (p.X - origin.X) / self.scale, (p.Y - origin.Y) / self.scale
end

function CameraController:screenToCell(p)
	local x, y = self:screenToMap(p)
	return self.Map:index(math.floor(x), math.floor(y))
end

function CameraController:zoomAt(p, factor)
	local before = self.scale
	local mx, my = self:screenToMap(p)
	self.scale = clamp(self.scale * factor, self:minScale(), self:maxScale())
	if self.scale == before then return end
	-- keep the map point under the cursor fixed
	local origin = self.viewport.AbsolutePosition
	local size = self.viewport.AbsoluteSize
	local sx, sy = p.X - origin.X, p.Y - origin.Y
	self.cx = mx - (sx - size.X / 2) / self.scale
	self.cy = my - (sy - size.Y / 2) / self.scale
	self:apply()
end

function CameraController:pan(dx, dy)
	self.cx = self.cx - dx / self.scale
	self.cy = self.cy - dy / self.scale
	self:apply()
end

function CameraController:focusCell(cell, scale)
	local x, y = self.Map:xy(cell)
	self.cx, self.cy = x + 0.5, y + 0.5
	if scale then self.scale = scale end
	self:apply()
end

-- Level of detail: 0 world view, 1 regional, 2 local.
function CameraController:lod()
	local L = self.Config.View.LOD
	local zoom = self.scale / self:minScale()
	if zoom >= L.Local then return 2 end
	if zoom >= L.Regional then return 1 end
	return 0
end

return CameraController
