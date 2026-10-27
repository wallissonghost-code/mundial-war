-- Mundial War · central balance and feature configuration.
-- Every gameplay number lives here; services must not hard-code tuning values.
local GameConfig = {}

GameConfig.Version = "1.0.0"
GameConfig.DEBUG_MODE = false          -- shows cell/chunk/order/bot debug overlays (never enable in production)

-- Match flow ---------------------------------------------------------------
GameConfig.Match = {
	MaxPlayers = 55,                   -- set the same value in Game Settings > Places > Max Players
	SpawnPhaseSeconds = 25,            -- players pick a start; no expansion yet
	VictoryPercent = 0.80,             -- share of all land cells
	EndScreenSeconds = 15,             -- victory screen before the next round
	AllowRespawn = true,               -- eliminated or late players may found a new nation
	RespawnCooldown = 10,
}

-- Simulation clocks (seconds) ----------------------------------------------
GameConfig.Tick = {
	Simulation = 0.2,                  -- expansion, combat, fleets
	Economy = 0.5,
	TerritoryDelta = 0.2,              -- batched ownership updates to clients
	PublicNations = 1.0,               -- troops/land/label for every nation
	PublicOrders = 0.4,
	Components = 2.0,                  -- label centroid + exclave detection
	EnclaveFill = 3.0,
}

-- Spawning -----------------------------------------------------------------
GameConfig.Spawn = {
	PlayerStartTroops = 2500,
	BotStartTroops = 1500,
	TribeStartTroops = 600,
	StartRadius = 2,                   -- disc of cells owned at spawn
	MinCapitalDistance = 18,           -- cells between capitals
}

-- Troops and gold ----------------------------------------------------------
-- growth/s = (Base + land*PerCell + bonuses) * (1 - troops/max)^SaturationPower
GameConfig.Troops = {
	BaseGrowth = 55,
	GrowthPerCell = 0.4,
	SaturationPower = 1.0,
	BaseCapacity = 10000,
	CapacityPerCell = 80,
	ExclaveGrowthFactor = 1.0,
}

GameConfig.Gold = {
	Base = 10,
	PerCell = 0.1,
	StartGold = 600,
}

GameConfig.TroopPercents = { 0.10, 0.25, 0.50, 0.75, 1.00 }
GameConfig.DefaultTroopPercent = 0.25

-- Expansion and combat -------------------------------------------------------
GameConfig.Expansion = {
	MaxOrdersPerNation = 3,            -- one order per target owner, at most this many fronts
	MinTroopsToSend = 10,
	NeutralBaseCost = 2.5,
	DistanceCostPerCell = 0.004,       -- extra cost per cell of distance from the capital
	PolarExtraCost = 1.5,              -- cells beyond 66 degrees of latitude
	CellsPerTickBase = 2,
	CellsPerTickTroopDivisor = 8,      -- + sqrt(orderTroops)/divisor
	CellsPerTickMax = 24,
	EnemyRateFactor = 0.5,             -- wars advance slower than neutral land
	FrontConeBase = 35,                -- degrees each side of the line origin→click
	FrontConeTroopDivisor = 6,         -- + sqrt(orderTroops)/divisor degrees: bigger armies, wider fronts
	FrontConeMax = 70,
	ConePenalty = 2.5,                 -- how strongly cells outside the cone are postponed
	OwnNeighborWeight = 1.6,           -- prefer cells already hugged by our territory (no holes)
	Jitter = 1.4,                      -- organic, non-grid edges
	EnclaveMaxCells = 80,              -- enclosed neutral pockets up to this size are annexed for free
	ReachSearchLimit = 40000,          -- cells searched to prove a land route from the click to our border
}

GameConfig.Combat = {
	EnemyMinCost = 8,
	DefenseDensityFactor = 1.0,        -- cost = defender troops per cell * factor
	DefenderLossFactor = 0.8,          -- defender loses density*factor per captured cell
	ExclaveAttackFactor = 1.4,         -- fronts outside the capital's connected territory pay more
	CapitalRadius = 4,
	CapitalDefense = 1.5,
	LandingCostFactor = 1.5,
	MinFailedLandingDamage = 0.5,      -- share of a failed landing that hurts the defender
}

-- Buildings ----------------------------------------------------------------
-- cost grows with each building of the same kind owned: cost*(1+CostGrowth*count)
GameConfig.CostGrowth = 0.35
GameConfig.MinBuildingSpacing = 2      -- cells between any two buildings
GameConfig.Buildings = {
	city = { name = "Cidade", icon = "🏙", cost = 1000, growth = 25, capacity = 15000, gold = 3,
		description = "+25 tropas/s, +15.000 capacidade, +3 ouro/s" },
	factory = { name = "Fábrica", icon = "🏭", cost = 1500, gold = 25,
		description = "+25 ouro/s; libera tanques e silo" },
	port = { name = "Porto", icon = "⚓", cost = 1200, gold = 6, coastal = true,
		description = "Litoral. Frotas de invasão e navios de guerra" },
	bunker = { name = "Bunker", icon = "🛡", cost = 600, radius = 5, defense = 1.8,
		description = "Ataques num raio de 5 custam ×1,8" },
	tower = { name = "Torre de sniper", icon = "🎯", cost = 900, radius = 9, attrition = 0.015,
		description = "Frentes inimigas num raio de 9 perdem 1,5% por segundo" },
	machinegun = { name = "Metralhadora", icon = "🔫", cost = 1100, radius = 6, massDefense = 15000,
		description = "Ataques grandes num raio de 6 custam até ×2" },
	artillery = { name = "Artilharia", icon = "💥", cost = 1800, radius = 14, interval = 2, damage = 0.03, support = 0.8,
		description = "Bombardeia frentes inimigas (raio 14); seus ataques ali custam ×0,8" },
	tankfactory = { name = "Fábrica de tanques", icon = "🚜", cost = 2500, requires = "factory", attackBonus = 0.08, attackFloor = 0.6,
		description = "-8% no custo de ataque (mín. ×0,6)" },
	airfield = { name = "Base aérea", icon = "✈", cost = 3000, range = 90,
		description = "Libera bombardeio aéreo até 90 células" },
	airdefense = { name = "Defesa antiaérea", icon = "📡", cost = 2000, radius = 14, intercept = 0.6,
		description = "60% de chance de interceptar mísseis e aviões num raio de 14" },
	silo = { name = "Silo nuclear", icon = "☢", cost = 6000, requires = "factory",
		description = "Permite lançar armas nucleares" },
}
GameConfig.BuildingOrder = { "city", "factory", "port", "bunker", "tower", "machinegun", "artillery", "tankfactory", "airfield", "airdefense", "silo" }

-- Naval ------------------------------------------------------------------------
GameConfig.Naval = {
	TransportGold = 300,
	MinTroops = 100,
	MaxFleetsPerNation = 3,
	Speed = 14,                        -- water cells per second
	WarshipGold = 1500,
	WarshipsPerPort = 2,
	WarshipRadius = 10,
	WarshipDamagePerSecond = 0.08,     -- share of a passing enemy transport destroyed per second
}

-- Strategic weapons --------------------------------------------------------------
GameConfig.Strategic = {
	NukeGold = 8000,
	NukeCooldown = 90,                 -- per silo
	NukeSpeed = 30,                    -- cells per second
	NukeRadius = 10,                   -- buildings destroyed, troops killed
	NukeFalloutRadius = 6,             -- cells become neutral
	AirstrikeGold = 1200,
	AirstrikeCooldown = 30,            -- per airfield
	AirstrikeSpeed = 45,
	AirstrikeRadius = 3,
	AirstrikeTroopDamage = 0.06,       -- share of the victim's troops
}

-- Diplomacy ----------------------------------------------------------------------
GameConfig.Diplomacy = {
	RequestSeconds = 30,
	BreakCooldown = 30,                -- after cancelling, no new alliance between the pair for this long
}

-- Bots -------------------------------------------------------------------------
GameConfig.Bots = {
	Nations = 36,                      -- largest countries become AI nations at their real capitals
	Tribes = 20,                       -- small, weak factions in other countries
	ThinkInterval = 1.2,               -- each bot; ticks are staggered across bots
	TribeThinkInterval = 3,
	AttackWhenStronger = 1.3,          -- troop ratio before picking a fight
	RecoverBelow = 0.25,               -- troops/max under which bots stop attacking
	SendPercent = 0.3,
	TribeSendPercent = 0.15,
}

-- Network / anti-cheat -------------------------------------------------------------
GameConfig.Network = {
	CommandsPerSecond = 10,
	CommandBurst = 20,
}

-- Map presentation (client) ------------------------------------------------------
GameConfig.View = {
	MaxPixelsPerCell = 28,
	ZoomStep = 1.15,
	KeyboardPanSpeed = 900,            -- screen pixels per second
	DragThreshold = 6,
	TwoClickConfirm = true,            -- first click aims, second click on the same spot confirms
	ConfirmRadius = 3,                 -- cells
	ConfirmTimeout = 5,
	LOD = { Regional = 1.6, Local = 4.0 }, -- zoom (multiples of the fit-to-screen zoom)
}

return GameConfig
