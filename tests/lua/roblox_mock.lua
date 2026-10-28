-- Minimal Roblox API emulation to execute the real server and client scripts under Lua 5.4.
-- It is deliberately strict about remote payloads (Roblox drops mixed tables and holes) and
-- about EditableImage writes, so integration bugs surface without opening Studio.
local M = {}

local unpack = table.unpack

---------------------------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ handlers = {} }, Signal) end
function Signal:Connect(fn)
	local h = { fn = fn, connected = true }
	table.insert(self.handlers, h)
	return { Disconnect = function() h.connected = false end, Connected = true }
end
function Signal:Fire(...)
	for _, h in ipairs(self.handlers) do
		if h.connected then h.fn(...) end
	end
end
function Signal:Wait() return coroutine.yield() end
M.Signal = Signal

---------------------------------------------------------------------------------- datatypes
local Vector2 = {}
Vector2.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	return Vector2[k]
end
Vector2.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
Vector2.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
Vector2.__div = function(a, s) return Vector2.new(a.X / s, a.Y / s) end
Vector2.__mul = function(a, s) return Vector2.new(a.X * s, a.Y * s) end
Vector2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
function Vector2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0, __type = "Vector2" }, Vector2) end
Vector2.zero = Vector2.new(0, 0)

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, Vector3) end

local UDim = {}
function UDim.new(s, o) return { Scale = s or 0, Offset = o or 0, __type = "UDim" } end
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo), __type = "UDim2" }
end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end

local Color3 = {}
Color3.__index = Color3
local function checkByte(v, what)
	assert(type(v) == "number" and v == v and v >= 0 and v <= 255, "Color3.fromRGB " .. what .. " out of range: " .. tostring(v))
end
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __type = "Color3" }, Color3) end
function Color3.fromRGB(r, g, b)
	checkByte(r, "r") checkByte(g, "g") checkByte(b, "b")
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3:Lerp(o, t) return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end

local CFrame = {}
CFrame.__index = CFrame
CFrame.__mul = function(a) return a end
function CFrame.new() return setmetatable({ __type = "CFrame" }, CFrame) end
function CFrame.Angles() return CFrame.new() end

local TweenInfo = { new = function() return { __type = "TweenInfo" } end }
local Content = { fromObject = function(o) assert(o and o.__editable, "Content.fromObject needs an EditableImage") return { __type = "Content", object = o } end }

-- Enum: Enum.Anything.Anything -> token
local function enumProxy(path)
	return setmetatable({ __path = path, Name = path:match("[^.]+$") }, {
		__index = function(t, k)
			local child = enumProxy(path .. "." .. k)
			rawset(t, k, child)
			return child
		end,
		__eq = function(a, b) return rawget(a, "__path") == rawget(b, "__path") end,
		__tostring = function() return path end,
	})
end
local Enum = enumProxy("Enum")

---------------------------------------------------------------------------------- buffer
local buffer = {}
function buffer.create(n)
	assert(type(n) == "number" and n >= 0 and n % 1 == 0, "buffer.create size")
	return { __buffer = true, size = n, data = {} }
end
function buffer.writeu8(b, o, v)
	assert(o >= 0 and o < b.size, "buffer.writeu8 offset out of bounds: " .. o .. "/" .. b.size)
	assert(v >= 0 and v <= 255 and v % 1 == 0, "buffer.writeu8 value " .. tostring(v))
	b.data[o] = v
end
function buffer.copy(target, toff, source, soff, count)
	assert(toff + count <= target.size, "buffer.copy target overflow")
	assert(soff + count <= source.size, "buffer.copy source overflow")
	for k = 0, count - 1 do target.data[toff + k] = source.data[soff + k] end
end
function buffer.len(b) return b.size end

---------------------------------------------------------------------------------- instances
local Instance = {}
local classDefaults = {
	ScreenGui = { AbsoluteSize = true }, Frame = {}, TextLabel = {}, TextButton = {}, ImageLabel = {},
	Folder = {}, RemoteEvent = {}, UICorner = {}, UIStroke = {}, UIListLayout = {}, UIGridLayout = {},
	UIPadding = {}, UISizeConstraint = {},
}
local GUI = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ScreenGui = true }
M.created = 0
M.screen = Vector2.new(1920, 1080)

local function absSize(inst)
	if inst.ClassName == "ScreenGui" or not inst.Parent or not GUI[inst.Parent.ClassName] then return M.screen end
	local p = absSize(inst.Parent)
	local s = rawget(inst, "_props").Size or UDim2.new(0, 0, 0, 0)
	return Vector2.new(p.X * s.X.Scale + s.X.Offset, p.Y * s.Y.Scale + s.Y.Offset)
end
local function absPos(inst)
	if inst.ClassName == "ScreenGui" or not inst.Parent or not GUI[inst.Parent.ClassName] then return Vector2.new(0, 0) end
	local pp, ps = absPos(inst.Parent), absSize(inst.Parent)
	local props = rawget(inst, "_props")
	local pos = props.Position or UDim2.new(0, 0, 0, 0)
	local anchor = props.AnchorPoint or Vector2.new(0, 0)
	local size = absSize(inst)
	return Vector2.new(pp.X + ps.X * pos.X.Scale + pos.X.Offset - anchor.X * size.X,
		pp.Y + ps.Y * pos.Y.Scale + pos.Y.Offset - anchor.Y * size.Y)
end

local InstanceMT = {}
local methods = {}
function methods:FindFirstChild(name)
	for _, c in ipairs(rawget(self, "_children")) do if c.Name == name then return c end end
	return nil
end
function methods:WaitForChild(name)
	local c = self:FindFirstChild(name)
	assert(c, "WaitForChild would hang forever: " .. self.Name .. "." .. tostring(name))
	return c
end
function methods:GetChildren()
	local out = {}
	for _, c in ipairs(rawget(self, "_children")) do out[#out + 1] = c end
	return out
end
function methods:IsA(cls) return self.ClassName == cls or (cls == "GuiObject" and GUI[self.ClassName]) end
function methods:Destroy()
	self.Parent = nil
	rawset(self, "_destroyed", true)
end
function methods:GetPropertyChangedSignal(prop)
	local signals = rawget(self, "_changed")
	signals[prop] = signals[prop] or Signal.new()
	return signals[prop]
end
function methods:SetAttribute(k, v) rawget(self, "_attrs")[k] = v end
function methods:GetAttribute(k) return rawget(self, "_attrs")[k] end
-- RemoteEvent: messages are serialised like Roblox and delivered later by M.pump()
M.pending = {}
M.bytes = 0
local function size(v)
	if type(v) == "table" then
		local s = 2
		for k, x in pairs(v) do s = s + size(k) + size(x) end
		return s
	elseif type(v) == "string" then return #v + 1 end
	return 8
end
function methods:FireServer(...)
	local args = { ... }
	local n = select("#", ...)
	for i = 1, n do args[i] = M.serialize(args[i], "FireServer#" .. i) end
	local remote = self
	table.insert(M.pending, function()
		rawget(remote, "_events").OnServerEvent = rawget(remote, "_events").OnServerEvent or M.Signal.new()
		rawget(remote, "_events").OnServerEvent:Fire(M.localPlayer, table.unpack(args, 1, n))
	end)
end
function methods:FireClient(player, payload)
	local data = M.serialize(payload, "FireClient")
	M.bytes = M.bytes + size(data)
	local remote = self
	table.insert(M.pending, function()
		rawget(remote, "_events").OnClientEvent = rawget(remote, "_events").OnClientEvent or M.Signal.new()
		rawget(remote, "_events").OnClientEvent:Fire(data)
	end)
end
function M.pump()
	local list = M.pending
	M.pending = {}
	for _, fn in ipairs(list) do fn() end
	return #list
end

InstanceMT.__index = function(self, k)
	if k == "AbsoluteSize" then return absSize(self) end
	if k == "AbsolutePosition" then return absPos(self) end
	local props = rawget(self, "_props")
	if props[k] ~= nil then return props[k] end
	if methods[k] then return methods[k] end
	local events = rawget(self, "_events")
	if events[k] then return events[k] end
	if k == "Activated" or k == "OnServerEvent" or k == "OnClientEvent" or k == "Completed" or k == "MouseButton1Click" then
		events[k] = events[k] or Signal.new()
		return events[k]
	end
	local child = methods.FindFirstChild(self, k)
	if child then return child end
	if k == "Visible" then return true end
	if k == "Parent" or k == "Image" or k == "ImageContent" or k == "Text" then return nil end
	error("mock: unknown member '" .. tostring(k) .. "' of " .. rawget(self, "ClassName"), 2)
end
InstanceMT.__newindex = function(self, k, v)
	assert(not rawget(self, "_destroyed") or k == "Parent", "mock: setting " .. k .. " on destroyed " .. self.ClassName)
	local props = rawget(self, "_props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "_children")
			for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
		end
		if v then table.insert(rawget(v, "_children"), self) end
	end
	if k == "BackgroundColor3" or k == "TextColor3" then
		assert(type(v) == "table" and v.__type == "Color3", "mock: " .. k .. " needs Color3")
	end
	if k == "Size" or k == "Position" then
		assert(type(v) == "table" and v.__type == "UDim2", "mock: " .. k .. " needs UDim2")
		local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
		assert(finite(v.X.Scale) and finite(v.X.Offset) and finite(v.Y.Scale) and finite(v.Y.Offset), "mock: NaN/inf in " .. k)
	end
	if k == "Text" then assert(type(v) == "string", "mock: Text must be a string, got " .. type(v)) end
	if k == "TextSize" then assert(type(v) == "number" and v == v, "mock: TextSize") end
	props[k] = v
	local signal = rawget(self, "_changed")[k]
	if signal then signal:Fire() end
end
InstanceMT.__tostring = function(self) return self.ClassName .. ":" .. tostring(self.Name) end

function Instance.new(cls)
	M.created = M.created + 1
	local inst = setmetatable({ ClassName = cls, _props = { Name = cls }, _children = {}, _events = {}, _changed = {}, _attrs = {} }, InstanceMT)
	return inst
end
M.Instance = Instance

---------------------------------------------------------------------------------- services
function M.reset()
	M.warnings = nil
	M.created = 0
	M.queue = {}             -- task.delay / spawn queue: { at, co or fn, args }
	M.clock = 0
	local game = Instance.new("DataModel")
	M.game = game
	local services = {}
	local function svc(name)
		local s = Instance.new(name)
		s.Name = name
		s.Parent = game
		services[name] = s
		return s
	end
	local players = svc("Players")
	local rs = svc("ReplicatedStorage")
	svc("ServerScriptService")
	svc("StarterGui")
	svc("Workspace")
	local runService = svc("RunService")
	local uis = svc("UserInputService")
	local guiService = svc("GuiService")
	local tween = svc("TweenService")
	local asset = svc("AssetService")
	local rawSvc = {}
	-- Players
	local localPlayer = Instance.new("Player")
	localPlayer.Name = "Ghost"
	rawset(localPlayer, "_props", rawget(localPlayer, "_props"))
	rawget(localPlayer, "_props").UserId = 4242
	rawget(localPlayer, "_props").DisplayName = "Ghost"
	localPlayer.Parent = players
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	rawget(players, "_props").LocalPlayer = localPlayer
	rawget(players, "_props").CharacterAutoLoads = true
	rawget(players, "_events").PlayerRemoving = Signal.new()
	rawget(players, "_events").PlayerAdded = Signal.new()
	local pm = {}
	function pm:GetPlayers() return { localPlayer } end
	function pm:GetPlayerByUserId(id) return id == 4242 and localPlayer or nil end
	function pm:GetUserThumbnailAsync() return "rbxthumb://type=AvatarHeadShot&id=4242&w=100&h=100" end
	rawSvc.Players = pm
	-- RunService
	rawget(runService, "_events").Heartbeat = Signal.new()
	rawget(runService, "_events").RenderStepped = Signal.new()
	-- UserInputService
	for _, e in ipairs({ "InputBegan", "InputChanged", "InputEnded", "TouchPinch" }) do rawget(uis, "_events")[e] = Signal.new() end
	M.keysDown = {}
	M.mouse = Vector2.new(960, 540)
	local um = {}
	function um:GetMouseLocation() return M.mouse + Vector2.new(0, 58) end
	function um:IsKeyDown(k) return M.keysDown[k] == true end
	function um:GetFocusedTextBox() return nil end
	rawSvc.UserInputService = um
	local gm = {}
	function gm:GetGuiInset() return Vector2.new(0, 58), Vector2.new(0, 0) end
	rawSvc.GuiService = gm
	local tm = {}
	function tm:Create(inst, info, goal)
		local t = { Completed = Signal.new() }
		function t:Play()
			for k, v in pairs(goal) do inst[k] = v end
			t.Completed:Fire()
		end
		return t
	end
	rawSvc.TweenService = tm
	local am = {}
	M.editableAvailable = true
	M.pixelWrites = 0
	function am:CreateEditableImage(opts)
		if not M.editableAvailable then error("EditableImage disabled") end
		local size = opts.Size
		local img = { __editable = true, Size = size }
		img.pixels = {}
		M.image = img
		function img:WritePixelsBuffer(pos, sz, buf)
			assert(pos.X >= 0 and pos.Y >= 0 and pos.X + sz.X <= size.X and pos.Y + sz.Y <= size.Y, "WritePixelsBuffer rect outside image")
			assert(buf.size == sz.X * sz.Y * 4, "WritePixelsBuffer buffer size " .. buf.size .. " ~= " .. sz.X * sz.Y * 4)
			M.pixelWrites = M.pixelWrites + 1
			for y = 0, sz.Y - 1 do
				for x = 0, sz.X - 1 do
					local o = (y * sz.X + x) * 4
					local d = ((pos.Y + y) * size.X + pos.X + x) * 3
					img.pixels[d] = buf.data[o] or 0
					img.pixels[d + 1] = buf.data[o + 1] or 0
					img.pixels[d + 2] = buf.data[o + 2] or 0
				end
			end
		end
		return img
	end
	rawSvc.AssetService = am
	local sg = {}
	function sg:SetCoreGuiEnabled() end
	rawSvc.StarterGui = sg

	function game:GetService(name)
		local s = services[name]
		assert(s, "mock: service " .. name)
		if rawSvc[name] then
			return setmetatable({}, {
				__index = function(_, k)
					if rawSvc[name][k] then return rawSvc[name][k] end
					return s[k]
				end,
				__newindex = function(_, k, v) s[k] = v end,
			})
		end
		return s
	end
	M.services = services
	M.localPlayer = localPlayer
	M.workspace = services.Workspace
	rawget(M.workspace, "_props").CurrentCamera = Instance.new("Camera")
	return game
end

---------------------------------------------------------------------------------- remotes
-- Roblox-like serialisation: arrays must have no holes, dictionaries need string keys,
-- functions/userdata are rejected.
local function serialize(v, path)
	local t = type(v)
	if t == "number" then
		assert(v == v, "remote: NaN at " .. path)
		return v
	end
	if t == "string" or t == "boolean" or t == "nil" then return v end
	if t == "table" then
		if v.__type then return v end
		local n = #v
		local count = 0
		for _ in pairs(v) do count = count + 1 end
		local out = {}
		if n > 0 then
			assert(count == n, "remote: mixed or holey table at " .. path .. " (#=" .. n .. ", keys=" .. count .. ")")
			for i = 1, n do out[i] = serialize(v[i], path .. "[" .. i .. "]") end
		else
			for k, x in pairs(v) do
				assert(type(k) == "string", "remote: non-string key " .. tostring(k) .. " at " .. path)
				out[k] = serialize(x, path .. "." .. k)
			end
		end
		return out
	end
	error("remote: cannot send " .. t .. " at " .. path)
end
M.serialize = serialize

---------------------------------------------------------------------------------- task
local task = {}
function task.spawn(fn, ...)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(err, 0) end
	if coroutine.status(co) ~= "dead" then table.insert(M.queue, { at = M.clock + (M.lastWait or 0), co = co }) end
	return co
end
function task.delay(sec, fn, ...)
	table.insert(M.queue, { at = M.clock + sec, fn = fn, args = { ... } })
end
function task.wait(sec)
	M.lastWait = sec or 0
	coroutine.yield()
	return sec
end
function M.runQueue()
	local due = {}
	local keep = {}
	for _, q in ipairs(M.queue) do
		if q.at <= M.clock then due[#due + 1] = q else keep[#keep + 1] = q end
	end
	M.queue = keep
	for _, q in ipairs(due) do
		if q.co then
			if coroutine.status(q.co) ~= "dead" then
				M.lastWait = 0
				local ok, err = coroutine.resume(q.co)
				if not ok then error(err, 0) end
				if coroutine.status(q.co) ~= "dead" then table.insert(M.queue, { at = M.clock + (M.lastWait or 0), co = q.co }) end
			end
		else
			q.fn(unpack(q.args))
		end
	end
end

---------------------------------------------------------------------------------- loading
function M.env(scriptInstance)
	local env = setmetatable({
		game = M.game, workspace = M.workspace, script = scriptInstance,
		Instance = Instance, Enum = Enum, Vector2 = Vector2, Vector3 = Vector3, UDim = UDim, UDim2 = UDim2,
		Color3 = Color3, CFrame = CFrame, TweenInfo = TweenInfo, Content = Content, buffer = buffer, task = task,
		warn = function(...) M.warnings = (M.warnings or 0) + 1 if M.warnings <= 3 then print("  warn:", ...) end end,
		typeof = function(v)
			if type(v) == "table" and getmetatable(v) == InstanceMT then return "Instance" end
			if type(v) == "table" and v.__type then return v.__type end
			return type(v)
		end,
		require = function(mod)
			local cache = rawget(mod, "_moduleResult")
			if cache ~= nil then return cache end
			local file = rawget(mod, "_file")
			assert(file, "require of non-module " .. tostring(mod))
			local chunk = assert(loadfile(file, "t", M.env(mod)))
			local result = chunk()
			rawset(mod, "_moduleResult", result)
			return result
		end,
	}, { __index = _G })
	env.math = setmetatable({
		clamp = function(v, lo, hi)
			assert(lo <= hi, "math.clamp: min > max")
			return math.max(lo, math.min(hi, v))
		end,
	}, { __index = math })
	return env
end

-- Mirrors tools/build_place.py: folder with init.*.lua becomes that script; files become modules.
function M.mount(parent, dir, name)
	local function list(path)
		local p = io.popen('ls -1 "' .. path .. '"')
		local out = {}
		for line in p:lines() do out[#out + 1] = line end
		p:close()
		return out
	end
	local entries = list(dir)
	local node
	local initFile
	for _, e in ipairs(entries) do
		if e == "init.server.lua" or e == "init.client.lua" then initFile = dir .. "/" .. e end
	end
	node = Instance.new(initFile and "Script" or "Folder")
	node.Name = name
	rawset(node, "_file", initFile)
	node.Parent = parent
	for _, e in ipairs(entries) do
		if e:sub(-4) == ".lua" and not e:match("^init%.") then
			local m = Instance.new("ModuleScript")
			m.Name = e:sub(1, -5)
			rawset(m, "_file", dir .. "/" .. e)
			m.Parent = node
		end
	end
	return node
end

-- Writes the visible GUI tree (absolute rects, colours, text) and the map image for
-- tests/render_gui.py, which draws an approximate screenshot.
function M.dump(root, path)
	local f = io.open(path, "w")
	local function visible(inst)
		while inst and GUI[inst.ClassName] do
			local p = rawget(inst, "_props")
			if p.Visible == false or rawget(inst, "_destroyed") then return false end
			inst = p.Parent
		end
		return true
	end
	local function walk(inst, depth)
		for order, c in ipairs(rawget(inst, "_children")) do
			if GUI[c.ClassName] and c.ClassName ~= "ScreenGui" and visible(c) then
				local p = rawget(c, "_props")
				local pos, size = absPos(c), absSize(c)
				local bg = p.BackgroundColor3 or Color3.new(1, 1, 1)
				local tc = p.TextColor3 or Color3.new(0, 0, 0)
				local text = (p.Text or ""):gsub("<[^>]->", ""):gsub("[\n\t|]", " ")
				f:write(table.concat({ c.ClassName, string.format("%.1f", pos.X), string.format("%.1f", pos.Y), string.format("%.1f", size.X), string.format("%.1f", size.Y),
					math.floor(bg.R * 255), math.floor(bg.G * 255), math.floor(bg.B * 255), tostring(p.BackgroundTransparency or 0),
					tostring(depth * 1000 + (p.ZIndex or 1)), text, math.floor(tc.R * 255), math.floor(tc.G * 255), math.floor(tc.B * 255),
					tostring(p.TextSize or 14), tostring(p.Name == "Territory" and 1 or 0), tostring(p.Rotation or 0) }, "|"), "\n")
			end
			walk(c, depth + 1)
		end
	end
	walk(root, 0)
	f:close()
	if M.image then
		local img = io.open(path .. ".ppm", "wb")
		local W, H = M.image.Size.X, M.image.Size.Y
		img:write("P6\n" .. W .. " " .. H .. "\n255\n")
		local chunk = {}
		for i = 0, W * H * 3 - 1 do chunk[#chunk + 1] = string.char(M.image.pixels[i] or 0) if #chunk >= 4096 then img:write(table.concat(chunk)) chunk = {} end end
		img:write(table.concat(chunk))
		img:close()
	end
end

function M.run(scriptInstance)
	local chunk = assert(loadfile(rawget(scriptInstance, "_file"), "t", M.env(scriptInstance)))
	return task.spawn(chunk)
end

return M
