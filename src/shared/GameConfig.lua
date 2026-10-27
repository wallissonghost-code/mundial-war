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
-- Cost of a new building grows with each one of the same kind owned: cost*(1+CostGrowth*count).
-- Every building can be upgraded to MaxBuildingLevel; level L -> L+1 costs cost*UpgradeCostFactor*L.
-- Each stat grows by perLevel[stat] per level above 1 (see shared/BuildingStats.lua).
GameConfig.CostGrowth = 0.35
GameConfig.MinBuildingSpacing = 2      -- cells between any two buildings
GameConfig.MaxBuildingLevel = 5
GameConfig.UpgradeCostFactor = 0.6
GameConfig.Buildings = {
	city = { name = "Cidade", icon = "🏙", cost = 1000, growth = 25, capacity = 15000, gold = 3,
		perLevel = { growth = 15, capacity = 10000, gold = 3 },
		purpose = "Aumenta a população: mais tropas por segundo, mais capacidade e um pouco de ouro." },
	factory = { name = "Fábrica", icon = "🏭", cost = 1500, gold = 25,
		perLevel = { gold = 18 },
		purpose = "Gera ouro e libera a fábrica de tanques e o silo." },
	port = { name = "Porto", icon = "⚓", cost = 1200, gold = 6, coastal = true, boats = 2,
		perLevel = { gold = 5, boats = 1 },
		purpose = "Só no litoral. Envia frotas de invasão pelo mar e constrói barcos de defesa." },
	bunker = { name = "Bunker", icon = "🛡", cost = 600, radius = 5, defense = 1.8, defensive = true,
		perLevel = { radius = 1, defense = 0.25 },
		purpose = "Fortifica a região: ataques inimigos dentro do alcance custam mais tropas." },
	tower = { name = "Torre de sniper", icon = "🎯", cost = 900, radius = 9, attrition = 0.015, defensive = true,
		perLevel = { radius = 1.5, attrition = 0.006 },
		purpose = "Desgasta as frentes inimigas que avançam dentro do alcance, a cada segundo." },
	machinegun = { name = "Metralhadora", icon = "🔫", cost = 1100, radius = 6, massDefense = 15000, maxFactor = 2, defensive = true,
		perLevel = { radius = 1, maxFactor = 0.25 },
		purpose = "Contra grandes exércitos: quanto maior o ataque no alcance, mais caro fica." },
	artillery = { name = "Artilharia", icon = "💥", cost = 1800, radius = 14, interval = 2, damage = 0.03, support = 0.8, defensive = true,
		perLevel = { radius = 2, damage = 0.01, support = -0.04 },
		purpose = "Bombardeia frentes inimigas no alcance e barateia seus próprios ataques ali." },
	tankfactory = { name = "Fábrica de tanques", icon = "🚜", cost = 2500, requires = "factory", attackBonus = 0.08, attackFloor = 0.6,
		perLevel = { attackBonus = 0.03 },
		purpose = "Blindados: todos os seus ataques custam menos tropas (mínimo ×0,6 somando todas)." },
	airfield = { name = "Base aérea", icon = "✈", cost = 3000, range = 90,
		perLevel = { range = 20 },
		purpose = "Lança ataques aéreos e bombas de fragmentação dentro do alcance." },
	airdefense = { name = "Defesa antiaérea", icon = "📡", cost = 2000, radius = 14, intercept = 0.6, defensive = true,
		perLevel = { radius = 2, intercept = 0.08 },
		purpose = "Pode derrubar mísseis e aviões inimigos que caiam dentro do alcance." },
	silo = { name = "Silo de mísseis", icon = "🚀", cost = 6000, requires = "factory", cooldownFactor = 1,
		perLevel = { cooldownFactor = -0.12 },
		purpose = "Lança bombas EMP, atômicas e, a partir do nível 3, de hidrogênio. Cada nível recarrega mais rápido." },
}
GameConfig.BuildingOrder = { "city", "factory", "port", "bunker", "tower", "machinegun", "artillery", "tankfactory", "airfield", "airdefense", "silo" }

-- Naval ------------------------------------------------------------------------
GameConfig.Naval = {
	TransportGold = 300,
	MinTroops = 100,
	MaxFleetsPerNation = 3,
	Speed = 14,                        -- water cells per second
	-- Defence boat: bought at a port, patrols around a point you choose on the water
	BoatGold = 1500,
	BoatHealth = 100,
	BoatSpeed = 9,                     -- cells per second
	BoatRange = 9,                     -- weapons reach (+1 per level of its port)
	BoatOrbit = 3,                     -- patrol circle around the chosen point
	BoatDamage = 14,                   -- health per second against enemy boats (+4 per port level)
	BoatTransportDamage = 0.1,         -- share of a passing enemy transport destroyed per second
	BoatGoldSteal = 10,                -- gold per second taken from each enemy port in reach
}

-- Strategic weapons --------------------------------------------------------------
-- launcher: building that fires it (one ready launcher of that kind is used; each has its own cooldown)
GameConfig.Weapons = {
	airstrike = { name = "Ataque aéreo", icon = "✈", gold = 1200, launcher = "airfield", cooldown = 30, speed = 45,
		radius = 3, troopShare = 0.06, destroys = true,
		purpose = "Destrói construções num raio pequeno e mata 6% das tropas do alvo." },
	cluster = { name = "Bomba de fragmentação", icon = "💣", gold = 2500, launcher = "airfield", cooldown = 40, speed = 40,
		radius = 6, troopKill = 1.5, destroys = false,
		purpose = "Mata muitas tropas na área sem destruir construções nem o território." },
	emp = { name = "Bomba EMP", icon = "⚡", gold = 4000, launcher = "silo", cooldown = 60, speed = 30,
		radius = 12, disable = 45, destroys = false,
		purpose = "Desliga todas as construções inimigas da área por 45 segundos." },
	atomic = { name = "Bomba atômica", icon = "☢", gold = 8000, launcher = "silo", cooldown = 90, speed = 30,
		radius = 10, fallout = 6, troopKill = 2, destroys = true,
		purpose = "Destrói construções, mata tropas e deixa o centro sem dono." },
	hydrogen = { name = "Bomba de hidrogênio", icon = "☣", gold = 20000, launcher = "silo", minLevel = 3, cooldown = 150, speed = 24,
		radius = 18, fallout = 11, troopKill = 2.5, destroys = true,
		purpose = "A maior explosão. Requer silo nível 3." },
}
GameConfig.WeaponOrder = { "airstrike", "cluster", "emp", "atomic", "hydrogen" }

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
	TwoClickConfirm = false,           -- true: first click aims, second click confirms (weapons always confirm)
	ConfirmRadius = 3,                 -- cells
	ConfirmTimeout = 5,
	LOD = { Regional = 1.6, Local = 4.0 }, -- zoom (multiples of the fit-to-screen zoom)
}

return GameConfig
