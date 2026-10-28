-- Mundial War · authoritative ownership of every cell.
-- owner[i]: -1 water (never ownable), 0 neutral land, >0 nation id.
-- Keeps per-nation owned/border sets so nothing ever scans the whole map per capture.
local TerritoryService = {}

local ctx, Map
local owner = {}
local ownedBy, border = {}, {}
local changes, changeCount = {}, 0
local recentClaims = {}       -- nid -> list of recently claimed cells (enclave detection seeds)
local seen, stamp = {}, 0     -- reusable visit marks
local compMark, compStamp = {}, 0 -- component id per owned cell (0 = not analysed yet)
local nb, nbOuter = {}, {}
local borderChunks = {}       -- nid -> chunk key -> { cell = true } (spatial index of border cells)
local dirty = {}              -- nid -> true when its territory changed since the last analysis
local CHUNK = 16

TerritoryService.owner = owner

function TerritoryService.init(context)
	ctx = context
	Map = ctx.Map
	TerritoryService.reset()
end

function TerritoryService.reset()
	for i = 1, Map.N do
		owner[i] = Map.land[i] and 0 or -1
		compMark[i] = 0
		seen[i] = 0
	end
	stamp, compStamp = 0, 0
	ownedBy, border, recentClaims, borderChunks, dirty = {}, {}, {}, {}, {}
	changes, changeCount = {}, 0
end

function TerritoryService.register(nid)
	ownedBy[nid] = {}
	border[nid] = {}
	recentClaims[nid] = {}
	borderChunks[nid] = {}
	dirty[nid] = true
end

function TerritoryService.unregister(nid)
	ownedBy[nid], border[nid], recentClaims[nid], borderChunks[nid], dirty[nid] = nil, nil, nil, nil, nil
end

local function chunkOf(i)
	local x = (i - 1) % Map.W
	local y = (i - 1 - x) / Map.W
	return math.floor(x / CHUNK) * 1000 + math.floor(y / CHUNK)
end

local function setBorder(id, i, on)
	local set = border[id]
	if not set or (set[i] == true) == on then return end
	local chunks = borderChunks[id]
	local key = chunkOf(i)
	if on then
		set[i] = true
		local c = chunks[key]
		if not c then c = {} chunks[key] = c end
		c[i] = true
	else
		set[i] = nil
		local c = chunks[key]
		if c then c[i] = nil end
	end
end

function TerritoryService.ownerOf(i)
	return owner[i]
end

function TerritoryService.owned(nid)
	return ownedBy[nid]
end

function TerritoryService.borderCells(nid)
	return border[nid]
end

local function refreshBorder(i)
	local id = owner[i]
	if id <= 0 then return end
	if not border[id] then return end
	local n = Map:neighbors(i, nb)
	for k = 1, n do
		local o = owner[nb[k]]
		if o ~= -1 and o ~= id then
			setBorder(id, i, true)
			return
		end
	end
	setBorder(id, i, false)
end

-- The single place where ownership changes. Water is rejected here, so no code path
-- can ever give a nation a water cell.
function TerritoryService.setOwner(i, nid)
	local old = owner[i]
	if old == nid or old == -1 or old == nil then
		return false
	end
	local nations = ctx.Nations
	if old > 0 then
		local set = ownedBy[old]
		if set then set[i] = nil end
		setBorder(old, i, false)
		dirty[old] = true
		local n = nations.get(old)
		if n then
			n.land = n.land - 1
			if n.capital == i then n.capitalLost = true end
		end
	end
	owner[i] = nid
	if nid > 0 then
		ownedBy[nid][i] = true
		dirty[nid] = true
		local n = nations.get(nid)
		n.land = n.land + 1
		local recent = recentClaims[nid]
		if #recent < 512 then recent[#recent + 1] = i end
	end
	compMark[i] = 0
	changes[i] = nid
	changeCount = changeCount + 1
	refreshBorder(i)
	local n = Map:neighbors(i, nbOuter)
	for k = 1, n do
		refreshBorder(nbOuter[k])
	end
	ctx.Buildings.onOwnerChanged(i, old, nid)
	return true
end

-- Cells owned by `target` (0 = neutral) that touch nation `nid`. Uses a stamp array so
-- duplicates are skipped without allocating a set.
function TerritoryService.frontier(nid, target, out)
	out = out or {}
	local count = 0
	stamp = stamp + 1
	local set = border[nid]
	if not set then return out, 0 end
	for i in pairs(set) do
		local n = Map:neighbors(i, nb)
		for k = 1, n do
			local j = nb[k]
			if owner[j] == target and seen[j] ~= stamp then
				seen[j] = stamp
				count = count + 1
				out[count] = j
			end
		end
	end
	for k = count + 1, #out do out[k] = nil end
	return out, count
end

-- Same as frontier, but only from border cells within `radius` of `center` (chunk index).
-- Expansion uses it so a huge empire does not rescan its whole border every tick.
function TerritoryService.frontierNear(nid, target, center, radius, out)
	out = out or {}
	local count = 0
	stamp = stamp + 1
	local chunks = borderChunks[nid]
	if not chunks then return out, 0 end
	local W = Map.W
	local cx = (center - 1) % W
	local cy = (center - 1 - cx) / W
	local r2 = radius * radius
	for kx = math.floor((cx - radius) / CHUNK), math.floor((cx + radius) / CHUNK) do
		for ky = math.floor((cy - radius) / CHUNK), math.floor((cy + radius) / CHUNK) do
			local set = chunks[kx * 1000 + ky]
			if set then
				for i in pairs(set) do
					local x = (i - 1) % W
					local y = (i - 1 - x) / W
					if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2 then
						local n = Map:neighbors(i, nb)
						for k = 1, n do
							local j = nb[k]
							if owner[j] == target and seen[j] ~= stamp then
								seen[j] = stamp
								count = count + 1
								out[count] = j
							end
						end
					end
				end
			end
		end
	end
	for k = count + 1, #out do out[k] = nil end
	return out, count
end

function TerritoryService.touches(nid, target)
	local set = border[nid]
	if not set then return false end
	for i in pairs(set) do
		local n = Map:neighbors(i, nb)
		for k = 1, n do
			if owner[nb[k]] == target then return true end
		end
	end
	return false
end

-- True when `cell` connects to nation `nid` through cells owned by `target` (the same
-- owner as `cell`): the order has a real land route instead of jumping over someone else.
-- Bounded flood fill from the clicked cell; very large regions are accepted as connected.
function TerritoryService.reachable(nid, cell, limit)
	local target = owner[cell]
	if target == nil or target == -1 or target == nid then return false end
	stamp = stamp + 1
	local queue, head = { cell }, 1
	seen[cell] = stamp
	local nb2 = {}
	while head <= #queue do
		local i = queue[head]
		head = head + 1
		local n = Map:neighbors(i, nb2)
		for k = 1, n do
			local j = nb2[k]
			local o = owner[j]
			if o == nid then return true end
			if o == target and seen[j] ~= stamp then
				seen[j] = stamp
				queue[#queue + 1] = j
			end
		end
		if #queue > limit then return true end
	end
	return false
end

-- Owners (other than nid, neutral or water) that share a land border with nid.
function TerritoryService.neighborsOf(nid)
	local result = {}
	local set = border[nid]
	if not set then return result end
	for i in pairs(set) do
		local n = Map:neighbors(i, nb)
		for k = 1, n do
			local o = owner[nb[k]]
			if o > 0 and o ~= nid then result[o] = (result[o] or 0) + 1 end
		end
	end
	return result
end

function TerritoryService.ownNeighborCount(i, nid)
	local n = Map:neighbors(i, nb)
	local c = 0
	for k = 1, n do
		if owner[nb[k]] == nid then c = c + 1 end
	end
	return c
end

-- Annexes neutral pockets fully enclosed by a single nation (and water). Keeps territory
-- solid: expansion never leaves holes behind.
function TerritoryService.fillEnclaves(nid)
	local recent = recentClaims[nid]
	if not recent or #recent == 0 then return 0 end
	recentClaims[nid] = {}
	local limit = ctx.Config.Expansion.EnclaveMaxCells
	local annexed = 0
	local nb2 = {}
	for _, c in ipairs(recent) do
		local n = Map:neighbors(c, nb2)
		local seeds = { nb2[1], nb2[2], nb2[3], nb2[4] }
		for k = 1, n do
			local s = seeds[k]
			if owner[s] == 0 then
				stamp = stamp + 1
				local region, queue, head, enclosed = {}, { s }, 1, true
				seen[s] = stamp
				while head <= #queue do
					local i = queue[head]
					head = head + 1
					region[#region + 1] = i
					if #region > limit then enclosed = false break end
					local m = Map:neighbors(i, nb)
					if m < 4 then enclosed = false break end   -- map edge: not enclosed
					for q = 1, m do
						local j = nb[q]
						local o = owner[j]
						if o == 0 then
							if seen[j] ~= stamp then
								seen[j] = stamp
								queue[#queue + 1] = j
							end
						elseif o ~= nid and o ~= -1 then
							enclosed = false
							break
						end
					end
					if not enclosed then break end
				end
				if enclosed then
					for _, i in ipairs(region) do
						TerritoryService.setOwner(i, nid)
						annexed = annexed + 1
					end
				end
			end
		end
	end
	recentClaims[nid] = {}
	return annexed
end

-- Connected components of one nation: label anchor (centroid of the largest block),
-- block size, and which block holds the capital (anything else is an exclave).
function TerritoryService.analyze(nid)
	local n = ctx.Nations.get(nid)
	local set = ownedBy[nid]
	if not n or not set then return end
	-- unchanged territory keeps its label and exclave map
	if not dirty[nid] and not n.capitalLost then return end
	dirty[nid] = nil
	local W = Map.W
	local bestSize, bestCell, capComp = 0, nil, nil
	local largestComp = nil
	local passStart = compStamp + 1
	for start in pairs(set) do
		if compMark[start] < passStart then
			compStamp = compStamp + 1
			local id = compStamp
			local queue, head, sx, sy = { start }, 1, 0, 0
			compMark[start] = id
			while head <= #queue do
				local i = queue[head]
				head = head + 1
				local x = (i - 1) % W
				sx = sx + x
				sy = sy + (i - 1 - x) / W
				local m = Map:neighbors(i, nb)
				for q = 1, m do
					local j = nb[q]
					if owner[j] == nid and compMark[j] ~= id then
						compMark[j] = id
						queue[#queue + 1] = j
					end
				end
			end
			if compMark[n.capital] == id then capComp = id end
			if #queue > bestSize then
				bestSize = #queue
				largestComp = id
				local cx, cy = sx / #queue, sy / #queue
				local bestD = math.huge
				for _, i in ipairs(queue) do
					local x = (i - 1) % W
					local y = (i - 1 - x) / W
					local d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
					if d < bestD then bestD, bestCell = d, i end
				end
			end
		end
	end
	if bestCell then
		n.labelCell, n.labelSize = bestCell, bestSize
		if n.capitalLost or owner[n.capital] ~= nid then
			n.capital = bestCell
			n.capitalLost = false
			capComp = largestComp
		end
		n.mainComp = capComp or largestComp
	end
end

-- True when the cell's nation reaches it over land from its capital (stale marks count as connected).
function TerritoryService.isMainland(nid, i)
	local n = ctx.Nations.get(nid)
	if not n or not n.mainComp then return true end
	local m = compMark[i]
	if m == 0 then return true end   -- claimed after the last analysis: assume connected
	return m == n.mainComp
end

function TerritoryService.releaseAll(nid)
	local set = ownedBy[nid]
	if not set then return end
	local list = {}
	for i in pairs(set) do list[#list + 1] = i end
	for _, i in ipairs(list) do
		TerritoryService.setOwner(i, 0)
	end
end

function TerritoryService.drainChanges()
	if changeCount == 0 then return nil end
	local flat, k = {}, 0
	for i, o in pairs(changes) do
		flat[k + 1] = i
		flat[k + 2] = o
		k = k + 2
	end
	changes, changeCount = {}, 0
	return flat
end

function TerritoryService.snapshotRuns()
	return ctx.Protocol.encodeRuns(owner, Map.N)
end

function TerritoryService.landShare(nid)
	local n = ctx.Nations.get(nid)
	return n and n.land / Map.landCount or 0
end

return TerritoryService
