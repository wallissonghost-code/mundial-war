-- Mundial War · names shared by client and server so remote traffic stays consistent.
local Protocol = {}

Protocol.CommandRemote = "MW_Command"   -- client -> server: (action, a, b)
Protocol.EventRemote = "MW_Event"       -- server -> client: { k = kind, ... }

Protocol.Actions = {
	Sync = "sync",
	Spawn = "spawn",           -- (cell)
	Target = "target",         -- (cell, percent) land expansion/attack, or naval when no land route
	Cancel = "cancel",         -- (orderId or nil = all)
	Build = "build",           -- (cell, kind)
	Warship = "warship",       -- (portCell) buy a defence boat
	Patrol = "patrol",         -- (boatId, waterCell)
	Upgrade = "upgrade",       -- (cell)
	Weapon = "weapon",         -- (cell, weaponKind, percent) percent is used by the air bridge
	Vote = "vote",             -- (modeName) during the vote phase
	Nuke = "nuke",             -- (cell)
	Airstrike = "airstrike",   -- (cell)
	Ally = "ally",             -- (nationId) request or accept
	Decline = "decline",       -- (nationId)
	BreakAlliance = "breakAlliance", -- (nationId)
	War = "war",               -- (nationId)
}

Protocol.Events = {
	Init = "init",
	Tick = "tick",
	Nations = "nations",
	Orders = "orders",
	Notice = "notice",
	Diplomacy = "diplomacy",
	Match = "match",
	Impact = "impact",
	Debug = "debug",
}

Protocol.Phases = { Waiting = "waiting", Spawn = "spawn", Playing = "playing", Ended = "ended" }

-- Owner snapshots travel as run-length pairs {owner, count, owner, count, ...}.
function Protocol.encodeRuns(owner, n)
	local out, k = {}, 0
	local i = 1
	while i <= n do
		local v = owner[i]
		local j = i + 1
		while j <= n and owner[j] == v do
			j = j + 1
		end
		out[k + 1] = v
		out[k + 2] = j - i
		k = k + 2
		i = j
	end
	return out
end

function Protocol.decodeRuns(runs, into)
	local i = 1
	for k = 1, #runs, 2 do
		local v, len = runs[k], runs[k + 1]
		for c = i, i + len - 1 do
			into[c] = v
		end
		i = i + len
	end
	return i - 1
end

function Protocol.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function Protocol.formatK(n)
	n = math.floor(n or 0)
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 10000 then
		return string.format("%.1fK", n / 1000)
	elseif n >= 1000 then
		return string.format("%.2fK", n / 1000)
	end
	return tostring(n)
end

return Protocol
