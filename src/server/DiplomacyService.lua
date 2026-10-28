-- Mundial War · alliances and wars.
-- Default relation is neutral: you may attack a neutral nation (that declares war).
-- Allies cannot attack each other until the alliance is cancelled.
local DiplomacyService = {}

local ctx
local relations = {}      -- "a:b" -> { kind = "ally" | "war", since }
local matrix = {}         -- a -> b -> kind (fast lookups for the simulation's hot loops)
local requests = {}       -- to -> { from -> expires }
local brokeAt = {}        -- "a:b" -> time alliance was cancelled

local function key(a, b)
	if a > b then a, b = b, a end
	return a .. ":" .. b
end

function DiplomacyService.init(context)
	ctx = context
end

function DiplomacyService.reset()
	relations, requests, brokeAt, matrix = {}, {}, {}, {}
end

local function setRelation(a, b, value)
	relations[key(a, b)] = value
	local kind = value and value.kind or nil
	matrix[a] = matrix[a] or {}
	matrix[b] = matrix[b] or {}
	matrix[a][b] = kind
	matrix[b][a] = kind
end

function DiplomacyService.relation(a, b)
	if a == b then return "self" end
	local row = matrix[a]
	return row and row[b] or "neutral"
end

function DiplomacyService.allied(a, b)
	return a ~= b and DiplomacyService.relation(a, b) == "ally"
end

function DiplomacyService.canAttack(a, b)
	if b == 0 then return true end
	if a == b then return false end
	return DiplomacyService.relation(a, b) ~= "ally"
end

local function notifyPair(a, b)
	local payload = { k = ctx.Protocol.Events.Diplomacy, a = a, b = b, rel = DiplomacyService.relation(a, b) }
	ctx.emit(nil, payload)
end

function DiplomacyService.declareWar(a, b)
	local na, nb = ctx.Nations.get(a), ctx.Nations.get(b)
	if not na or not nb or not na.alive or not nb.alive or a == b then
		return false, "Nação inválida."
	end
	local r = relations[key(a, b)]
	if r and r.kind == "war" then return true, "Vocês já estão em guerra." end
	if r and r.kind == "ally" then brokeAt[key(a, b)] = ctx.now() end
	setRelation(a, b, { kind = "war", since = ctx.now() })
	if requests[a] then requests[a][b] = nil end
	if requests[b] then requests[b][a] = nil end
	notifyPair(a, b)
	ctx.notify(b, na.name .. " declarou guerra a você!", "war")
	return true, "Guerra declarada contra " .. nb.name .. "."
end

-- Called by expansion when an attack starts; silently turns neutral into war.
function DiplomacyService.ensureWar(a, b)
	if b > 0 and DiplomacyService.relation(a, b) == "neutral" then
		DiplomacyService.declareWar(a, b)
	end
end

local function makeAlliance(a, b)
	setRelation(a, b, { kind = "ally", since = ctx.now() })
	if requests[a] then requests[a][b] = nil end
	if requests[b] then requests[b][a] = nil end
	-- allies stop fighting each other immediately; troops in the field go home
	ctx.Expansion.cancelAgainst(a, b)
	ctx.Expansion.cancelAgainst(b, a)
	notifyPair(a, b)
end

-- Request an alliance, or accept one if the other side already asked.
function DiplomacyService.requestAlliance(a, b)
	local na, nb = ctx.Nations.get(a), ctx.Nations.get(b)
	if not na or not nb or not na.alive or not nb.alive or a == b then
		return false, "Nação inválida."
	end
	if DiplomacyService.allied(a, b) then return false, "Vocês já são aliados." end
	local broke = brokeAt[key(a, b)]
	if broke and ctx.now() - broke < ctx.Config.Diplomacy.BreakCooldown then
		return false, "Aliança rompida há pouco. Aguarde."
	end
	local now = ctx.now()
	local incoming = requests[a] and requests[a][b]
	if incoming and incoming > now then
		makeAlliance(a, b)
		ctx.notify(b, na.name .. " aceitou a aliança.", "ally")
		return true, "Aliança formada com " .. nb.name .. "."
	end
	if nb.kind ~= "player" then
		if ctx.Bots.considerAlliance(b, a) then
			makeAlliance(a, b)
			return true, nb.name .. " aceitou a aliança."
		end
		return false, nb.name .. " recusou a aliança."
	end
	requests[b] = requests[b] or {}
	requests[b][a] = now + ctx.Config.Diplomacy.RequestSeconds
	ctx.emit(b, { k = ctx.Protocol.Events.Diplomacy, request = a, expires = ctx.Config.Diplomacy.RequestSeconds })
	return true, "Pedido de aliança enviado a " .. nb.name .. "."
end

function DiplomacyService.decline(a, b)
	if requests[a] and requests[a][b] then
		requests[a][b] = nil
		ctx.notify(b, (ctx.Nations.get(a) or { name = "?" }).name .. " recusou a aliança.", "info")
		return true, "Pedido recusado."
	end
	return false, "Não há pedido dessa nação."
end

function DiplomacyService.breakAlliance(a, b)
	if not DiplomacyService.allied(a, b) then return false, "Vocês não são aliados." end
	setRelation(a, b, nil)
	brokeAt[key(a, b)] = ctx.now()
	notifyPair(a, b)
	ctx.notify(b, (ctx.Nations.get(a) or { name = "?" }).name .. " cancelou a aliança.", "war")
	return true, "Aliança cancelada."
end

function DiplomacyService.removeNation(id)
	for k in pairs(relations) do
		local a, b = string.match(k, "^(%d+):(%d+)$")
		a, b = tonumber(a), tonumber(b)
		if a == id or b == id then setRelation(a, b, nil) end
	end
	requests[id] = nil
	for _, list in pairs(requests) do list[id] = nil end
end

function DiplomacyService.pendingFor(id)
	local out = {}
	local now = ctx.now()
	for from, expires in pairs(requests[id] or {}) do
		if expires > now then out[#out + 1] = { from = from, left = expires - now } end
	end
	return out
end

function DiplomacyService.snapshot()
	local out = {}
	for k, r in pairs(relations) do
		local a, b = string.match(k, "^(%d+):(%d+)$")
		out[#out + 1] = { tonumber(a), tonumber(b), r.kind }
	end
	return out
end

function DiplomacyService.allies(id)
	local out = {}
	for k, r in pairs(relations) do
		if r.kind == "ally" then
			local a, b = string.match(k, "^(%d+):(%d+)$")
			a, b = tonumber(a), tonumber(b)
			if a == id then out[#out + 1] = b elseif b == id then out[#out + 1] = a end
		end
	end
	return out
end

function DiplomacyService.tick()
	local now = ctx.now()
	for to, list in pairs(requests) do
		for from, expires in pairs(list) do
			if expires <= now then list[from] = nil end
		end
	end
end

return DiplomacyService
