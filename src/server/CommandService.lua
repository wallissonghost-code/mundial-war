-- Mundial War · validates and routes every client intention. Pure Lua (no Roblox APIs) so the
-- anti-cheat rules are unit tested. The client never decides anything: it only asks.
local CommandService = {}

local ctx, Config
local buckets = {}   -- userId -> { tokens, at }

function CommandService.init(context)
	ctx = context
	Config = ctx.Config
end

function CommandService.forget(userId)
	buckets[userId] = nil
end

-- Token bucket: CommandsPerSecond sustained, CommandBurst peak.
local function allow(userId, clock)
	local N = Config.Network
	local b = buckets[userId]
	if not b then
		b = { tokens = N.CommandBurst, at = clock }
		buckets[userId] = b
	end
	b.tokens = math.min(N.CommandBurst, b.tokens + (clock - b.at) * N.CommandsPerSecond)
	b.at = clock
	if b.tokens < 1 then return false end
	b.tokens = b.tokens - 1
	return true
end

local function isInt(v)
	return type(v) == "number" and v == v and v % 1 == 0 and v > -1e9 and v < 1e9
end

local function isPercent(v)
	return type(v) == "number" and v == v and v >= 0.01 and v <= 1
end

-- Returns ok, message (message may be nil for silent actions).
function CommandService.handle(userId, displayName, action, a, b, clock, c)
	if type(action) ~= "string" then return false, nil end
	if not allow(userId, clock or ctx.now()) then return false, nil end
	local A = ctx.Protocol.Actions
	local Map = ctx.Map
	local nation = ctx.Nations.forUser(userId)
	local nid = nation and nation.alive and nation.id or nil

	if action == A.Vote then
		if type(a) ~= "string" then return false, "Modo inválido." end
		return ctx.Match.vote(userId, a)
	end

	if action == A.Spawn then
		if nid then return false, "Você já tem uma nação." end
		if not ctx.Match.canSpawn() then return false, "Não é possível fundar uma nação agora." end
		if not isInt(a) or not Map:valid(a) then return false, "Célula inválida." end
		if not ctx.Nations.canRespawn(userId) then return false, "Aguarde alguns segundos para renascer." end
		local name = type(displayName) == "string" and string.sub(displayName, 1, 24) or "Jogador"
		if ctx.mode == "extreme" then
			local n, why = ctx.Nations.takeover(userId, name, a)
			if not n then return false, why end
			return true, "Você agora governa " .. n.name .. "."
		end
		local n, why = ctx.Nations.create("player", name, a, { userId = userId })
		if not n then return false, why end
		return true, "Nação fundada! Capital em " .. ((Map.countries[Map.country[a]] or {}).name or "terra livre") .. "."
	end

	if not nid then return false, "Escolha um ponto no mapa para fundar sua nação." end

	if action == A.Target then
		if not isInt(a) or not Map:valid(a) then return false, "Célula inválida." end
		if not isPercent(b) then return false, "Percentual inválido." end
		local ok, msg, hint = ctx.Expansion.issue(nid, a, b)
		if ok then return true, msg end
		if hint == "naval" and Map.land[a] then
			if ctx.Buildings.count(nid, "port") > 0 then
				return ctx.Naval.launch(nid, a, b)
			end
			return false, "Sem ligação por terra. Construa um porto para invadir pelo mar."
		end
		return false, msg
	elseif action == A.Cancel then
		if a ~= nil and not isInt(a) then return false, nil end
		ctx.Expansion.cancel(nid, a)
		return true, "Avanço cancelado; sobreviventes voltaram."
	elseif action == A.Build then
		if not isInt(a) or not Map:valid(a) then return false, "Célula inválida." end
		if type(b) ~= "string" or not Config.Buildings[b] then return false, "Construção inválida." end
		return ctx.Buildings.build(nid, a, b)
	elseif action == A.Warship then
		if not isInt(a) or not Map:valid(a) then return false, "Célula inválida." end
		return ctx.Naval.buyBoat(nid, a)
	elseif action == A.Patrol then
		if not isInt(a) or not isInt(b) or not Map:valid(b) then return false, "Ponto inválido." end
		return ctx.Naval.patrol(nid, a, b)
	elseif action == A.Upgrade then
		if not isInt(a) or not Map:valid(a) then return false, "Célula inválida." end
		return ctx.Buildings.upgrade(nid, a)
	elseif action == A.Weapon or action == A.Nuke or action == A.Airstrike then
		if not isInt(a) or not Map:valid(a) then return false, "Alvo inválido." end
		local kind = action == A.Nuke and "atomic" or action == A.Airstrike and "airstrike" or b
		if type(kind) ~= "string" or not Config.Weapons[kind] then return false, "Arma inválida." end
		return ctx.Strategic.launch(nid, a, kind, c)
	elseif action == A.Ally or action == A.Decline or action == A.BreakAlliance or action == A.War then
		if not isInt(a) or not ctx.Nations.get(a) or a == nid then return false, "Nação inválida." end
		if action == A.Ally then return ctx.Diplomacy.requestAlliance(nid, a) end
		if action == A.Decline then return ctx.Diplomacy.decline(nid, a) end
		if action == A.BreakAlliance then return ctx.Diplomacy.breakAlliance(nid, a) end
		return ctx.Diplomacy.declareWar(nid, a)
	end
	return false, nil
end

return CommandService
