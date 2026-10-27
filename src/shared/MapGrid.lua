-- Mundial War · geographic grid shared by server and client.
-- Cells are numbered i = y*W + x + 1 (x, y zero-based). This module only holds geography;
-- ownership lives in the server's TerritoryService and the client's ClientState.
local MapGrid = {}
MapGrid.__index = MapGrid

local LAT_TOP = 84.0

local function decodeBase62(alphabet)
	local lookup = {}
	for k = 1, #alphabet do
		lookup[string.byte(alphabet, k)] = k - 1
	end
	return lookup
end

function MapGrid.new(data)
	local self = setmetatable({}, MapGrid)
	local W, H = data.W, data.H
	self.W, self.H, self.N = W, H, W * H
	self.countries = data.Countries
	self.country = {}   -- country index per cell (0 = water)
	self.land = {}      -- true for land
	self.coast = {}     -- land touching water
	self.polar = {}     -- row index -> true beyond 66 degrees latitude
	self.latitude = {}  -- row index -> latitude in degrees (cell centre)
	self.landCount = 0

	local lookup = decodeBase62(data.Alphabet)
	local country, land = self.country, self.land
	for y = 0, H - 1 do
		local row = data.Rows[y + 1]
		local x = 0
		for k = 1, #row, 4 do
			local b1, b2, b3, b4 = string.byte(row, k, k + 3)
			local id = lookup[b1] * 62 + lookup[b2]
			local len = lookup[b3] * 62 + lookup[b4]
			for c = x, x + len - 1 do
				local i = y * W + c + 1
				country[i] = id
				if id > 0 then
					land[i] = true
					self.landCount = self.landCount + 1
				end
			end
			x = x + len
		end
		assert(x == W, "MapData row " .. y .. " has wrong width")
	end
	for i = 1, self.N do
		if land[i] then
			local x = (i - 1) % W
			if (x > 0 and not land[i - 1]) or (x < W - 1 and not land[i + 1])
				or (i > W and not land[i - W]) or (i <= self.N - W and not land[i + W]) then
				self.coast[i] = true
			end
		end
	end
	local ySpan = 2 * math.pi * H / W
	local yTop = 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.rad(LAT_TOP)))
	for y = 0, H - 1 do
		local my = yTop - (y + 0.5) / H * ySpan
		local lat = math.deg(2.5 * math.atan(math.exp(0.8 * my)) - 0.625 * math.pi)
		self.latitude[y] = lat
		if math.abs(lat) > 66 then
			self.polar[y] = true
		end
	end
	return self
end

function MapGrid:xy(i)
	return (i - 1) % self.W, (i - 1 - (i - 1) % self.W) / self.W
end

function MapGrid:index(x, y)
	if x < 0 or y < 0 or x >= self.W or y >= self.H then
		return nil
	end
	return y * self.W + x + 1
end

function MapGrid:valid(i)
	return type(i) == "number" and i == i and i % 1 == 0 and i >= 1 and i <= self.N
end

-- Writes the up-to-4 orthogonal neighbours of i into out[1..n] and returns n.
function MapGrid:neighbors(i, out)
	local W, n = self.W, 0
	local x = (i - 1) % W
	if x > 0 then n = n + 1 out[n] = i - 1 end
	if x < W - 1 then n = n + 1 out[n] = i + 1 end
	if i > W then n = n + 1 out[n] = i - W end
	if i <= self.N - W then n = n + 1 out[n] = i + W end
	return n
end

function MapGrid:distance(a, b)
	local W = self.W
	local dx = (a - 1) % W - (b - 1) % W
	local dy = ((a - 1) - (a - 1) % W) / W - ((b - 1) - (b - 1) % W) / W
	return math.sqrt(dx * dx + dy * dy)
end

function MapGrid:isPolar(i)
	local _, y = self:xy(i)
	return self.polar[y] == true
end

-- Calls fn(i) for every cell inside a disc; stops early if fn returns true.
function MapGrid:disc(center, radius, fn)
	local cx, cy = self:xy(center)
	local r = math.floor(radius)
	for y = math.max(0, cy - r), math.min(self.H - 1, cy + r) do
		for x = math.max(0, cx - r), math.min(self.W - 1, cx + r) do
			local dx, dy = x - cx, y - cy
			if dx * dx + dy * dy <= radius * radius then
				if fn(y * self.W + x + 1) then
					return
				end
			end
		end
	end
end

-- Connected land masses (continents and islands): cell -> mass id, plus sizes.
function MapGrid:landmasses()
	local mass, sizes, nb = {}, {}, {}
	local id = 0
	for start = 1, self.N do
		if self.land[start] and not mass[start] then
			id = id + 1
			local queue, head = { start }, 1
			mass[start] = id
			while head <= #queue do
				local i = queue[head]
				head = head + 1
				local n = self:neighbors(i, nb)
				for k = 1, n do
					local j = nb[k]
					if self.land[j] and not mass[j] then
						mass[j] = id
						queue[#queue + 1] = j
					end
				end
			end
			sizes[id] = #queue
		end
	end
	return mass, sizes
end

function MapGrid:countryByCode(code)
	for index, c in ipairs(self.countries) do
		if c.code == code then
			return index, c
		end
	end
	return nil
end

return MapGrid
