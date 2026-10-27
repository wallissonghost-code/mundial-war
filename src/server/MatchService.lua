-- Mundial War · round life cycle: waiting → spawn phase → playing → victory → next round.
local MatchService = {}

local ctx, Config
local phase, phaseEnds, round, winner = "waiting", 0, 0, nil

function MatchService.init(context)
	ctx = context
	Config = ctx.Config
end

function MatchService.phase()
	return phase
end

function MatchService.round()
	return round
end

function MatchService.winner()
	return winner
end

function MatchService.isPlaying()
	return phase == "playing"
end

function MatchService.canSpawn()
	return phase == "spawn" or (phase == "playing" and Config.Match.AllowRespawn)
end

function MatchService.timeLeft()
	return math.max(0, phaseEnds - ctx.now())
end

local function announce()
	ctx.emit(nil, {
		k = ctx.Protocol.Events.Match, phase = phase, round = round,
		left = MatchService.timeLeft(), winner = winner,
	})
end

local function resetWorld()
	ctx.Territory.reset()
	ctx.Nations.reset()
	ctx.Buildings.reset()
	ctx.Expansion.reset()
	ctx.Naval.reset()
	ctx.Strategic.reset()
	ctx.Diplomacy.reset()
	ctx.Combat.reset()
	ctx.Bots.reset()
end

function MatchService.beginRound()
	resetWorld()
	round = round + 1
	winner = nil
	phase = "spawn"
	phaseEnds = ctx.now() + Config.Match.SpawnPhaseSeconds
	ctx.Bots.spawnAll()
	ctx.fullResync = true
	announce()
end

function MatchService.toWaiting()
	resetWorld()
	phase = "waiting"
	winner = nil
	ctx.fullResync = true
	announce()
end

-- Skips the rest of the spawn phase (used by tests and when every player already spawned).
function MatchService.startPlaying()
	if phase == "spawn" then
		phase = "playing"
		phaseEnds = 0
		announce()
	end
end

function MatchService.tick(humanCount)
	local now = ctx.now()
	if phase == "waiting" then
		if humanCount > 0 then MatchService.beginRound() end
		return
	end
	if humanCount == 0 and ctx.realPlayers then
		MatchService.toWaiting()
		return
	end
	if phase == "spawn" then
		if now >= phaseEnds then MatchService.startPlaying() end
	elseif phase == "playing" then
		ctx.Nations.checkEliminations()
		local landCount = ctx.Map.landCount
		for _, n in pairs(ctx.Nations.all()) do
			if n.alive and n.land / landCount >= Config.Match.VictoryPercent then
				winner = { id = n.id, name = n.name, share = n.land / landCount }
				phase = "ended"
				phaseEnds = now + Config.Match.EndScreenSeconds
				ctx.Expansion.reset()
				announce()
				return
			end
		end
	elseif phase == "ended" then
		if now >= phaseEnds then MatchService.beginRound() end
	end
end

function MatchService.publicView()
	return { phase = phase, round = round, left = MatchService.timeLeft(), winner = winner }
end

return MatchService
