-- Mundial War · mouse, keyboard and touch → camera moves and map clicks.
-- Never relies on hover for anything essential, so phones and tablets work the same way.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local InputController = {}
InputController.__index = InputController

local function v2(p) return Vector2.new(p.X, p.Y) end

function InputController.new(camera, Config, handlers)
	local self = setmetatable({}, InputController)
	self.camera, self.Config, self.h = camera, Config, handlers
	self.press = nil
	self.touches = {}
	self.pinch = nil
	local threshold = Config.View.DragThreshold

	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if processed then return end
			self.touches[input] = v2(input.Position)
			local count = 0
			for _ in pairs(self.touches) do count = count + 1 end
			if count == 1 then
				self.press = { start = v2(input.Position), last = v2(input.Position), moved = false, button = 1, input = input }
			elseif count == 2 then
				self.press = nil
				local a, b = nil, nil
				for _, p in pairs(self.touches) do if not a then a = p else b = p end end
				self.pinch = { dist = (a - b).Magnitude, mid = (a + b) / 2 }
			end
			return
		end
		if processed then return end
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
			local button = t == Enum.UserInputType.MouseButton1 and 1 or t == Enum.UserInputType.MouseButton2 and 2 or 3
			self.press = { start = v2(input.Position), last = v2(input.Position), moved = false, button = button }
		elseif t == Enum.UserInputType.Keyboard then
			self.h.onKey(input.KeyCode)
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			if processed then return end
			local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
			local step = Config.View.ZoomStep
			camera:zoomAt(mouse, input.Position.Z > 0 and step or 1 / step)
		elseif t == Enum.UserInputType.MouseMovement then
			local p = v2(input.Position)
			if self.press and not self.press.input then
				if not self.press.moved and (p - self.press.start).Magnitude > threshold then
					self.press.moved = true
				end
				if self.press.moved then
					local d = p - self.press.last
					camera:pan(d.X, d.Y)
				end
				self.press.last = p
			end
			self.h.onHover(p)
		elseif t == Enum.UserInputType.Touch and self.touches[input] then
			local p = v2(input.Position)
			self.touches[input] = p
			if self.pinch then
				local a, b = nil, nil
				for _, q in pairs(self.touches) do if not a then a = q elseif not b then b = q end end
				if a and b then
					local dist = (a - b).Magnitude
					local mid = (a + b) / 2
					if self.pinch.dist > 0 then camera:zoomAt(mid, dist / self.pinch.dist) end
					camera:pan(mid.X - self.pinch.mid.X, mid.Y - self.pinch.mid.Y)
					self.pinch.dist, self.pinch.mid = dist, mid
				end
			elseif self.press and self.press.input == input then
				if not self.press.moved and (p - self.press.start).Magnitude > threshold * 2 then
					self.press.moved = true
				end
				if self.press.moved then
					local d = p - self.press.last
					camera:pan(d.X, d.Y)
				end
				self.press.last = p
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			local press = self.press
			self.touches[input] = nil
			local count = 0
			for _ in pairs(self.touches) do count = count + 1 end
			if count < 2 then self.pinch = nil end
			if press and press.input == input then
				self.press = nil
				if not press.moved then self.h.onClick(v2(input.Position), 1) end
			end
			return
		end
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
			local press = self.press
			self.press = nil
			if press and not press.input and not press.moved then
				self.h.onClick(v2(input.Position), press.button)
			end
		end
	end)

	-- keyboard panning (WASD / arrows) and +/- zoom, frame-rate independent
	RunService.RenderStepped:Connect(function(dt)
		if UserInputService:GetFocusedTextBox() then return end
		local dx, dy = 0, 0
		local K = Enum.KeyCode
		local down = function(k) return UserInputService:IsKeyDown(k) end
		if down(K.A) or down(K.Left) then dx = dx + 1 end
		if down(K.D) or down(K.Right) then dx = dx - 1 end
		if down(K.W) or down(K.Up) then dy = dy + 1 end
		if down(K.S) or down(K.Down) then dy = dy - 1 end
		if dx ~= 0 or dy ~= 0 then
			local speed = Config.View.KeyboardPanSpeed * dt
			camera:pan(dx * speed, dy * speed)
		end
		local zoom = 0
		if down(K.Equals) or down(K.KeypadPlus) then zoom = 1 end
		if down(K.Minus) or down(K.KeypadMinus) then zoom = -1 end
		if zoom ~= 0 then
			local size = camera.viewport.AbsoluteSize
			local center = camera.viewport.AbsolutePosition + size / 2
			camera:zoomAt(center, 1 + zoom * 2 * dt)
		end
	end)
	return self
end

return InputController
