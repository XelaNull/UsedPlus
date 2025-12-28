--[[
    FS25_UsedPlus - Maintenance System Vehicle Specialization

    Adds hidden reliability scores and maintenance tracking to vehicles.
    Pattern from: HeadlandManagement headlandManagement.lua

    Features:
    - Hidden reliability scores (engine, hydraulic, electrical)
    - Purchase information tracking (used vs new)
    - Maintenance history (repairs, failures)
    - Runtime failure system (stalling, drift, cutout)
    - Speed degradation based on damage + reliability

    Phase 1: Core data model and save/load
    Phase 2: Failure system (stalling, speed degradation)
    Phase 3: Used market integration
    Phase 4: Inspection system
    Phase 5: Polish (hydraulic drift, cutout, resale)
]]

UsedPlusMaintenance = {}

UsedPlusMaintenance.MOD_NAME = g_currentModName
UsedPlusMaintenance.SPEC_NAME = UsedPlusMaintenance.MOD_NAME .. ".UsedPlusMaintenance"

-- Configuration defaults
UsedPlusMaintenance.CONFIG = {
    -- Feature toggles
    enableFailures = true,
    enableInspection = true,
    enableSpeedDegradation = true,
    enableSteeringDegradation = true, -- v1.5.1: Worn steering feels loose/sloppy
    enableResaleModifier = true,
    enableHydraulicDrift = true,
    enableElectricalCutout = true,
    enableLemonScale = true,          -- Workhorse/Lemon DNA system

    -- Balance tuning
    failureRateMultiplier = 1.0,      -- Global failure frequency
    speedDegradationMax = 0.5,        -- Max 50% speed reduction
    inspectionCostBase = 200,         -- Base inspection cost
    inspectionCostPercent = 0.01,     -- + 1% of vehicle price

    -- Thresholds
    damageThresholdForFailures = 0.2, -- Failures start at 20% damage
    reliabilityRepairBonus = 0.15,    -- Each repair adds 15% reliability
    maxReliabilityAfterRepair = 0.95, -- Can never fully restore (legacy, superseded by ceiling)

    -- Workhorse/Lemon Scale settings (v1.4.0+)
    ceilingDegradationMax = 0.01,     -- Max 1% ceiling loss per repair (for lemons)
    minReliabilityCeiling = 0.30,     -- Ceiling can never go below 30%

    -- Timing
    stallCooldownMs = 30000,          -- 30 seconds between stalls
    updateIntervalMs = 1000,          -- Check failures every 1 second

    -- Hydraulic drift settings
    hydraulicDriftSpeed = 0.001,      -- Radians per second of drift
    hydraulicDriftThreshold = 0.5,    -- Only drift if reliability below 50%

    -- Electrical cutout settings
    cutoutCheckIntervalMs = 5000,     -- Check for cutout every 5 seconds
    cutoutDurationMs = 3000,          -- Cutout lasts 3 seconds
    cutoutBaseChance = 0.03,          -- 3% base chance per check

    -- v1.5.1: Stall recovery settings
    stallRecoveryDurationMs = 5000,   -- 5 seconds before engine can restart after stall

    -- v1.6.0: Steering pull settings (worn vehicles pull to one side)
    steeringPullThreshold = 0.7,          -- Pull starts when hydraulic reliability drops below 70%
    steeringPullMax = 0.15,               -- Max 15% steering bias at lowest reliability
    steeringPullSpeedMin = 5,             -- No pull below 5 km/h
    steeringPullSpeedMax = 25,            -- Full pull effect at 25+ km/h
    steeringPullSurgeIntervalMin = 30000, -- Minimum 30 seconds between surge events
    steeringPullSurgeIntervalMax = 90000, -- Maximum 90 seconds between surge events
    steeringPullSurgeDuration = 3000,     -- Surge lasts 3 seconds
    steeringPullSurgeMultiplier = 1.5,    -- Pull is 50% stronger during surge

    -- v1.6.0: Engine misfiring settings (worn engine stutters/hiccups)
    enableMisfiring = true,
    misfireThreshold = 0.6,               -- Misfires start below 60% engine reliability
    misfireCheckIntervalMs = 500,         -- Check for misfire every 500ms
    misfireMaxChancePerCheck = 0.15,      -- Max 15% chance per check at 0% reliability
    misfireDurationMin = 100,             -- Minimum 100ms per misfire
    misfireDurationMax = 300,             -- Maximum 300ms per misfire
    misfireBurstChance = 0.3,             -- 30% chance of burst (multiple quick misfires)
    misfireBurstCount = 3,                -- Up to 3 misfires in a burst

    -- v1.6.0: Engine overheating settings (worn engine builds heat)
    enableOverheating = true,
    overheatThreshold = 0.5,              -- Overheating effects start below 50% engine reliability
    overheatHeatRateBase = 0.002,         -- Base heat gain per second when running
    overheatHeatRateLoad = 0.008,         -- Additional heat per second at full load
    overheatCoolRateOff = 0.015,          -- Cool rate when engine off
    overheatCoolRateIdle = 0.005,         -- Cool rate when idling
    overheatWarningTemp = 0.7,            -- Show warning at 70% temperature
    overheatStallTemp = 0.95,             -- Force stall at 95% temperature
    overheatRestartTemp = 0.4,            -- Must cool to 40% to restart
    overheatCooldownMs = 20000,           -- Minimum 20 second cooldown after overheat

    -- v1.6.0: Implement surge settings (implements randomly lift)
    enableImplementSurge = true,
    implementSurgeThreshold = 0.4,        -- Surge starts below 40% hydraulic reliability
    implementSurgeChance = 0.002,         -- 0.2% chance per check when lowered

    -- v1.6.0: Implement drop settings (implements suddenly drop)
    enableImplementDrop = true,
    implementDropThreshold = 0.35,        -- Drop starts below 35% hydraulic reliability
    implementDropChance = 0.001,          -- 0.1% chance per check when raised

    -- v1.6.0: PTO toggle settings (power randomly turns on/off)
    enablePTOToggle = true,
    ptoToggleThreshold = 0.4,             -- Toggle starts below 40% electrical reliability
    ptoToggleChance = 0.003,              -- 0.3% chance per check

    -- v1.6.0: Hitch failure settings (implement detaches - VERY RARE)
    enableHitchFailure = true,
    hitchFailureThreshold = 0.15,         -- Only below 15% hydraulic reliability
    hitchFailureChance = 0.0001,          -- 0.01% chance per check (VERY rare)

    -- v1.7.0: Tire System Settings
    enableTireWear = true,
    tireWearRatePerKm = 0.001,            -- 0.1% condition loss per km
    tireWarnThreshold = 0.3,              -- Warn when tires below 30%
    tireCriticalThreshold = 0.15,         -- Critical warning below 15%

    -- Tire quality tiers (Retread = 1, Normal = 2, Quality = 3)
    tireRetreadCostMult = 0.40,           -- 40% of normal cost
    tireRetreadTractionMult = 0.85,       -- 85% traction
    tireRetreadFailureMult = 3.0,         -- 3x failure chance
    tireNormalCostMult = 1.0,             -- 100% cost (baseline)
    tireNormalTractionMult = 1.0,         -- 100% traction (baseline)
    tireNormalFailureMult = 1.0,          -- 1x failure chance (baseline)
    tireQualityCostMult = 1.50,           -- 150% of normal cost
    tireQualityTractionMult = 1.10,       -- 110% traction
    tireQualityFailureMult = 0.5,         -- 0.5x failure chance

    -- v1.7.0: Flat tire malfunction
    enableFlatTire = true,
    flatTireThreshold = 0.2,              -- Flat tire possible below 20% condition
    flatTireBaseChance = 0.0005,          -- 0.05% chance per check
    flatTireSpeedReduction = 0.5,         -- 50% max speed with flat
    flatTirePullStrength = 0.25,          -- Steering pull strength (0-1)
    flatTireFrictionMult = 0.3,           -- 30% friction with flat tire

    -- v1.7.0: Tire friction physics hook
    enableTireFriction = true,            -- Hook into WheelPhysics for friction reduction

    -- v1.7.0: Low traction malfunction (weather-aware)
    enableLowTraction = true,
    lowTractionThreshold = 0.25,          -- Low traction warnings below 25% condition
    lowTractionWetMultiplier = 1.5,       -- 50% worse in rain
    lowTractionSnowMultiplier = 2.0,      -- 100% worse in snow

    -- v1.7.0: Friction reduction based on tire condition
    enableTireFriction = true,
    tireFrictionMinMultiplier = 0.6,      -- Minimum 60% friction at 0% condition
    tireFrictionWetPenalty = 0.15,        -- Additional 15% loss when wet
    tireFrictionSnowPenalty = 0.25,       -- Additional 25% loss in snow

    -- v1.7.0: Oil System Settings
    enableOilSystem = true,
    oilDepletionRatePerHour = 0.01,       -- 1% per operating hour (100 hours to empty)
    oilWarnThreshold = 0.25,              -- Warn when oil below 25%
    oilCriticalThreshold = 0.10,          -- Critical warning below 10%
    oilLowDamageMultiplier = 2.0,         -- 2x engine wear when low on oil
    oilPermanentDamageOnFailure = 0.10,   -- 10% permanent ceiling drop if failure while low

    -- v1.7.0: Oil leak malfunction
    enableOilLeak = true,
    oilLeakThreshold = 0.4,               -- Leaks possible below 40% engine reliability
    oilLeakBaseChance = 0.0003,           -- 0.03% chance per check
    oilLeakMinorMult = 2.0,               -- Minor leak: 2x depletion
    oilLeakModerateMult = 5.0,            -- Moderate leak: 5x depletion
    oilLeakSevereMult = 10.0,             -- Severe leak: 10x depletion

    -- v1.7.0: Hydraulic Fluid System Settings
    enableHydraulicFluidSystem = true,
    hydraulicFluidDepletionPerAction = 0.002, -- 0.2% per hydraulic action
    hydraulicFluidWarnThreshold = 0.25,   -- Warn when below 25%
    hydraulicFluidCriticalThreshold = 0.10, -- Critical warning below 10%
    hydraulicFluidLowDamageMultiplier = 2.0, -- 2x hydraulic wear when low
    hydraulicFluidPermanentDamageOnFailure = 0.10, -- 10% permanent ceiling drop

    -- v1.7.0: Hydraulic leak malfunction
    enableHydraulicLeak = true,
    hydraulicLeakThreshold = 0.4,         -- Leaks possible below 40% hydraulic reliability
    hydraulicLeakBaseChance = 0.0003,     -- 0.03% chance per check
    hydraulicLeakMinorMult = 2.0,         -- Minor leak: 2x depletion
    hydraulicLeakModerateMult = 5.0,      -- Moderate leak: 5x depletion
    hydraulicLeakSevereMult = 10.0,       -- Severe leak: 10x depletion

    -- v1.7.0: Fuel leak malfunction (engine issue)
    enableFuelLeak = true,
    fuelLeakThreshold = 0.35,             -- Fuel leaks possible below 35% engine reliability
    fuelLeakBaseChance = 0.0002,          -- 0.02% chance per check
    fuelLeakMinMult = 2.0,                -- Minimum 2x fuel consumption
    fuelLeakMaxMult = 5.0,                -- Maximum 5x fuel consumption
    fuelLeakBaseDrainRate = 0.5,          -- Base leak rate: 0.5 L/s when engine running
}

--[[
    Inspector Quote System (v1.4.0)
    50 quotes across 10 tiers that hint at vehicle DNA quality
    Each tier has 5 quotes: 2 technical, 2 superstitious, 1 country
]]
UsedPlusMaintenance.INSPECTOR_QUOTES = {
    catastrophic = {  -- 0.00 - 0.09
        "usedplus_quote_cat_1",
        "usedplus_quote_cat_2",
        "usedplus_quote_cat_3",
        "usedplus_quote_cat_4",
        "usedplus_quote_cat_5",
    },
    terrible = {  -- 0.10 - 0.19
        "usedplus_quote_ter_1",
        "usedplus_quote_ter_2",
        "usedplus_quote_ter_3",
        "usedplus_quote_ter_4",
        "usedplus_quote_ter_5",
    },
    poor = {  -- 0.20 - 0.29
        "usedplus_quote_poor_1",
        "usedplus_quote_poor_2",
        "usedplus_quote_poor_3",
        "usedplus_quote_poor_4",
        "usedplus_quote_poor_5",
    },
    belowAverage = {  -- 0.30 - 0.39
        "usedplus_quote_below_1",
        "usedplus_quote_below_2",
        "usedplus_quote_below_3",
        "usedplus_quote_below_4",
        "usedplus_quote_below_5",
    },
    slightlyBelow = {  -- 0.40 - 0.49
        "usedplus_quote_slight_1",
        "usedplus_quote_slight_2",
        "usedplus_quote_slight_3",
        "usedplus_quote_slight_4",
        "usedplus_quote_slight_5",
    },
    average = {  -- 0.50 - 0.59
        "usedplus_quote_avg_1",
        "usedplus_quote_avg_2",
        "usedplus_quote_avg_3",
        "usedplus_quote_avg_4",
        "usedplus_quote_avg_5",
    },
    aboveAverage = {  -- 0.60 - 0.69
        "usedplus_quote_above_1",
        "usedplus_quote_above_2",
        "usedplus_quote_above_3",
        "usedplus_quote_above_4",
        "usedplus_quote_above_5",
    },
    good = {  -- 0.70 - 0.79
        "usedplus_quote_good_1",
        "usedplus_quote_good_2",
        "usedplus_quote_good_3",
        "usedplus_quote_good_4",
        "usedplus_quote_good_5",
    },
    excellent = {  -- 0.80 - 0.89
        "usedplus_quote_exc_1",
        "usedplus_quote_exc_2",
        "usedplus_quote_exc_3",
        "usedplus_quote_exc_4",
        "usedplus_quote_exc_5",
    },
    legendary = {  -- 0.90 - 1.00
        "usedplus_quote_leg_1",
        "usedplus_quote_leg_2",
        "usedplus_quote_leg_3",
        "usedplus_quote_leg_4",
        "usedplus_quote_leg_5",
    },
}

--[[
    Quality Tier → DNA Distribution Correlation (v1.4.0)
    Higher quality tiers bias toward workhorses, lower toward lemons
    This adds risk/reward dynamics to tier selection

    Order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Must match UsedSearchDialog.QUALITY_TIERS order!
]]
UsedPlusMaintenance.QUALITY_DNA_RANGES = {
    [1] = { min = 0.00, max = 0.85, avg = 0.40 },  -- Any: Wide variance
    [2] = { min = 0.00, max = 0.70, avg = 0.30 },  -- Poor: High lemon risk (~45%)
    [3] = { min = 0.15, max = 0.85, avg = 0.50 },  -- Fair: Balanced
    [4] = { min = 0.30, max = 0.95, avg = 0.60 },  -- Good: Quality bias (~5% lemon, ~20% workhorse)
    [5] = { min = 0.50, max = 1.00, avg = 0.75 },  -- Excellent: Workhorse bias (~0% lemon, ~40% workhorse)
}

--[[
    Get inspector quote based on workhorse/lemon scale
    Returns localized quote text from the appropriate tier
    @param workhorseLemonScale - The vehicle's hidden quality score (0.0-1.0)
    @return string - Localized quote text
]]
function UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    local quotes = UsedPlusMaintenance.INSPECTOR_QUOTES

    -- Determine tier based on scale (10 tiers, 0.1 each)
    local tier
    if workhorseLemonScale < 0.10 then
        tier = "catastrophic"
    elseif workhorseLemonScale < 0.20 then
        tier = "terrible"
    elseif workhorseLemonScale < 0.30 then
        tier = "poor"
    elseif workhorseLemonScale < 0.40 then
        tier = "belowAverage"
    elseif workhorseLemonScale < 0.50 then
        tier = "slightlyBelow"
    elseif workhorseLemonScale < 0.60 then
        tier = "average"
    elseif workhorseLemonScale < 0.70 then
        tier = "aboveAverage"
    elseif workhorseLemonScale < 0.80 then
        tier = "good"
    elseif workhorseLemonScale < 0.90 then
        tier = "excellent"
    else
        tier = "legendary"
    end

    -- Select random quote from tier
    local tierQuotes = quotes[tier]
    local quoteKey = tierQuotes[math.random(#tierQuotes)]

    -- Return localized text (with fallback)
    local text = g_i18n:getText(quoteKey)
    if text == quoteKey then
        -- Translation not found, return a generic message
        return "Vehicle condition assessed."
    end
    return text
end

--[[
    v1.6.0: Check if warnings should be shown for this vehicle
    Warnings should ONLY show when:
    1. Player is actively controlling THIS vehicle (isActiveForInput)
    2. Startup grace period has expired (not immediately after load/purchase)

    This prevents phantom warnings when standing outside vehicles or on game start.
    @param vehicle - The vehicle to check
    @return boolean - true if warnings can be shown, false otherwise
]]
function UsedPlusMaintenance.shouldShowWarning(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return false end

    -- Check startup grace period - no warnings during first few seconds
    if spec.startupGracePeriod and spec.startupGracePeriod > 0 then
        return false
    end

    -- v1.7.3: Use multiple methods to check if player is in/controlling this vehicle
    -- Method 1: Check if player has entered this vehicle
    if vehicle.getIsEntered and vehicle:getIsEntered() then
        return true
    end

    -- Method 2: Check if this is the HUD's controlled vehicle
    if g_currentMission and g_currentMission.controlledVehicle then
        local rootVehicle = vehicle:getRootVehicle()
        if rootVehicle == g_currentMission.controlledVehicle then
            return true
        end
    end

    -- Method 3: Check stored isActiveForInput from last onUpdate frame
    if spec.lastIsActiveForInput then
        return true
    end

    -- Method 4: Fallback to getIsControlled
    if vehicle.getIsControlled and vehicle:getIsControlled() then
        return true
    end

    return false
end

--[[
    Show a blinking warning message to the player
    Only shows if shouldShowWarning returns true
    @param vehicle - The vehicle triggering the warning
    @param message - The warning text to display
    @param duration - Optional duration in ms (default 2500)
]]
function UsedPlusMaintenance.showWarning(vehicle, message, duration)
    if not UsedPlusMaintenance.shouldShowWarning(vehicle) then
        return
    end

    duration = duration or 2500

    if g_currentMission and g_currentMission.showBlinkingWarning then
        g_currentMission:showBlinkingWarning(message, duration)
    end
end

--[[
    Generate workhorse/lemon scale for a NEW vehicle (from dealership)
    New vehicles have slight quality bias - dealerships don't sell obvious lemons
    Range: 0.3 to 1.0, average ~0.6
]]
function UsedPlusMaintenance.generateNewVehicleScale()
    -- Bell curve centered at 0.6 using sum of randoms
    local r1 = math.random()
    local r2 = math.random()
    local scale = 0.3 + (r1 * 0.5) + (r2 * 0.2)
    return math.min(1.0, math.max(0.0, scale))
end

--[[
    Generate workhorse/lemon scale for a USED vehicle (from used market)
    DNA distribution is now correlated with quality tier (v1.4.0)

    @param qualityLevel - Optional quality tier (1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent)
    @return scale - DNA value 0.0 (lemon) to 1.0 (workhorse)
]]
function UsedPlusMaintenance.generateUsedVehicleScale(qualityLevel)
    -- Get DNA range for quality tier (default to "Any" if not specified)
    local dnaRange = UsedPlusMaintenance.QUALITY_DNA_RANGES[qualityLevel]
    if dnaRange == nil then
        dnaRange = UsedPlusMaintenance.QUALITY_DNA_RANGES[1]  -- Default to "Any"
    end

    -- Bell curve within tier's range using sum of 2 randoms
    local r1 = math.random()
    local r2 = math.random()
    local rangeWidth = dnaRange.max - dnaRange.min
    local scale = dnaRange.min + ((r1 + r2) / 2) * rangeWidth

    UsedPlus.logDebug(string.format("Generated DNA: qualityLevel=%d, range=[%.2f-%.2f], result=%.3f",
        qualityLevel or 1, dnaRange.min, dnaRange.max, scale))

    return math.min(1.0, math.max(0.0, scale))
end

--[[
    Calculate initial ceiling for used vehicle based on previous ownership
    Simulates unknown repair history from age and hours
    @param workhorseLemonScale - The vehicle's DNA (0.0-1.0)
    @param estimatedPreviousRepairs - Estimated from age/hours
    @return Initial ceiling value (0.3-1.0)
]]
function UsedPlusMaintenance.calculateInitialCeiling(workhorseLemonScale, estimatedPreviousRepairs)
    -- Degradation rate based on DNA: Lemons (0.0) = 1%, Workhorses (1.0) = 0%
    local degradationRate = (1 - workhorseLemonScale) * UsedPlusMaintenance.CONFIG.ceilingDegradationMax
    local totalDegradation = degradationRate * estimatedPreviousRepairs
    local ceiling = 1.0 - totalDegradation
    return math.max(UsedPlusMaintenance.CONFIG.minReliabilityCeiling, ceiling)
end

--[[
    Prerequisites check
    Return true to allow spec to load
]]
function UsedPlusMaintenance.prerequisitesPresent(specializations)
    return true
end

--[[
    Initialize specialization - Register XML schema for save/load
    Pattern from: HeadlandManagement initSpecialization
]]
function UsedPlusMaintenance.initSpecialization()
    UsedPlus.logDebug("UsedPlusMaintenance.initSpecialization starting schema registration")

    local schemaSavegame = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)." .. UsedPlusMaintenance.SPEC_NAME

    -- Purchase Information
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".purchasedUsed", "Was this vehicle bought used?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseDate", "Game time when purchased", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchasePrice", "What player paid", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseDamage", "Damage at time of purchase", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseHours", "Operating hours at purchase", 0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasInspected", "Did player pay for inspection?", false)

    -- Hidden Reliability Scores (0.0-1.0, lower = worse)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".engineReliability", "Engine reliability score", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicReliability", "Hydraulic reliability score", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".electricalReliability", "Electrical reliability score", 1.0)

    -- Workhorse/Lemon Scale System (v1.4.0+)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".workhorseLemonScale", "Hidden quality DNA (0=lemon, 1=workhorse)", 0.5)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxReliabilityCeiling", "Current max achievable reliability", 1.0)

    -- Maintenance History
    schemaSavegame:register(XMLValueType.INT,   key .. ".repairCount", "Times repaired at shop", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".totalRepairCost", "Lifetime repair spending", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".lastRepairDate", "Last shop visit game time", 0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".failureCount", "Total breakdowns experienced", 0)

    -- Inspection Cache (for paid inspections on owned vehicles)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasInspectionCache", "Has a paid inspection been done?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheHours", "Operating hours at inspection", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheDamage", "Damage level at inspection", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheWear", "Wear/paint level at inspection", 0)

    -- v1.7.0: Tire System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".tireCondition", "Tire tread condition (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".tireQuality", "Tire quality tier (1=Retread, 2=Normal, 3=Quality)", 2)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".distanceTraveled", "Distance traveled for tire wear", 0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasFlatTire", "Does vehicle have a flat tire?", false)
    schemaSavegame:register(XMLValueType.STRING, key .. ".flatTireSide", "Which side has flat tire (left/right)", "")

    -- v1.7.0: Oil System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".oilLevel", "Engine oil level (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasLowOil", "Was low oil warning shown?", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasOilLeak", "Does engine have oil leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".oilLeakSeverity", "Oil leak severity multiplier", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".engineReliabilityCeiling", "Max engine reliability due to oil damage", 1.0)

    -- v1.7.0: Hydraulic Fluid System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicFluidLevel", "Hydraulic fluid level (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasLowHydraulicFluid", "Was low hydraulic fluid warning shown?", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasHydraulicLeak", "Does hydraulic system have leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicLeakSeverity", "Hydraulic leak severity multiplier", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicReliabilityCeiling", "Max hydraulic reliability due to fluid damage", 1.0)

    -- v1.7.0: Fuel Leak System
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasFuelLeak", "Does fuel tank have leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".fuelLeakMultiplier", "Fuel leak rate multiplier", 1.0)

    UsedPlus.logDebug("UsedPlusMaintenance schema registration complete (v1.7.0 with tire/fluid fields)")
end

--[[
    Register event listeners for this specialization
    Pattern from: HeadlandManagement registerEventListeners
]]
function UsedPlusMaintenance.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", UsedPlusMaintenance)
    -- v1.5.1: Listen for vehicle enter to trigger first-start stall check
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", UsedPlusMaintenance)
end

--[[
    Register overwritten functions
    Pattern from: HeadlandManagement registerOverwrittenFunctions
]]
function UsedPlusMaintenance.registerOverwrittenFunctions(vehicleType)
    -- v1.5.1: Override getCanMotorRun for stall recovery period and speed governor
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", UsedPlusMaintenance.getCanMotorRun)

    -- v1.5.1: Override setSteeringInput for steering degradation (loose steering on worn hydraulics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setSteeringInput", UsedPlusMaintenance.setSteeringInput)
end

--[[
    v1.5.1: Override getCanMotorRun to enforce:
    1. Stall recovery period (prevents instant restart after stall)
    2. Speed governor (cuts power when over reliability-based max speed)

    The speed governor acts like a rev limiter - when you exceed the max speed
    your engine can sustain, power cuts briefly until you drop back below.
    This is more realistic than applying brakes (no brake lights).
]]
function UsedPlusMaintenance:getCanMotorRun(superFunc)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then
        return superFunc(self)
    end

    -- Check if in stall recovery period
    if spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0 then
        local currentTime = g_currentMission.time or 0
        if currentTime < spec.stallRecoveryEndTime then
            -- Still in recovery - engine cannot run
            return false
        else
            -- Recovery complete - clear the timer
            spec.stallRecoveryEndTime = 0
        end
    end

    -- v1.6.0: Check for engine overheat - can't run until cooled
    if spec.isOverheated then
        return false
    end

    -- v1.6.0: Check for active misfire - brief power cut
    if spec.misfireActive then
        return false
    end

    -- v1.5.1: Speed governor - cut motor when significantly over reliability-based max speed
    -- This acts like a speed limiter/rev limiter - power cuts when you exceed what the worn engine can sustain
    -- NOTE: Skip governor check during stall recovery (engine is already off, no need for governor warning)
    local inStallRecovery = spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0
    if not inStallRecovery and UsedPlusMaintenance.CONFIG.enableSpeedDegradation and spec.maxSpeedFactor and spec.maxSpeedFactor < 0.95 then
        local currentSpeed = 0
        if self.getLastSpeed then
            currentSpeed = self:getLastSpeed()  -- km/h
        end

        -- Calculate max speed based on vehicle's base max and our degradation factor
        local baseMaxSpeed = 50  -- Default fallback
        if self.spec_drivable and self.spec_drivable.cruiseControl then
            baseMaxSpeed = self.spec_drivable.cruiseControl.maxSpeed or 50
        end
        local degradedMaxSpeed = baseMaxSpeed * spec.maxSpeedFactor

        -- Allow 3 km/h grace before cutting (prevents constant flickering at the limit)
        local overspeedThreshold = degradedMaxSpeed + 3

        if currentSpeed > overspeedThreshold then
            -- Over speed - cut power (acts like hitting a governor/rev limiter)
            -- Use pulsing to allow brief power bursts (feels more natural than hard cut)
            spec.governorPulseTimer = (spec.governorPulseTimer or 0) + 1
            if spec.governorPulseTimer % 3 ~= 0 then  -- Cut 2 out of every 3 frames
                -- Show warning first time
                -- v1.6.0: Only show if player is controlling this vehicle
                if not spec.hasShownGovernorWarning and UsedPlusMaintenance.shouldShowWarning(self) then
                    g_currentMission:showBlinkingWarning(
                        g_i18n:getText("usedPlus_speedGovernor") or "Engine struggling at this speed!",
                        2000
                    )
                    spec.hasShownGovernorWarning = true
                end
                return false
            end
        else
            spec.governorPulseTimer = 0
            spec.hasShownGovernorWarning = false
        end
    end

    -- v1.8.1: Chain to AdvancedMaintenance's damage check if installed
    -- This allows both maintenance systems to work together:
    -- - UsedPlus: Gradual symptoms (stalling, overheating, speed degradation)
    -- - AdvancedMaintenance: Damage-based engine block (catastrophic failures)
    if ModCompatibility.advancedMaintenanceInstalled then
        local shouldChain, chainFunc = ModCompatibility.getAdvancedMaintenanceChain(self)
        if shouldChain and chainFunc then
            local amResult = chainFunc()
            if amResult == false then
                -- AM says engine can't run (damage too high)
                return false
            end
        end
    end

    -- Normal check
    return superFunc(self)
end

--[[
    v1.5.1: Override setSteeringInput for steering degradation
    Poor hydraulic reliability causes "loose" steering - the vehicle doesn't hold straight
    v1.7.0: Added flat tire steering pull (stronger, more consistent)
    Pattern from: HeadlandManagement setSteeringInput
]]
function UsedPlusMaintenance:setSteeringInput(superFunc, inputValue, isAnalog, deviceCategory)
    local spec = self.spec_usedPlusMaintenance

    -- If no maintenance data, pass through
    if spec == nil then
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    local config = UsedPlusMaintenance.CONFIG
    -- v1.8.0: Use ModCompatibility to get hydraulic reliability
    -- Note: RVB doesn't have hydraulic parts, so this uses native UsedPlus reliability
    -- Steering pull is a UNIQUE UsedPlus feature that complements RVB!
    local hydraulicReliability = ModCompatibility.getHydraulicReliability(self)

    -- Get current speed (used by multiple effects)
    local speed = 0
    if self.getLastSpeed then
        speed = self:getLastSpeed()
    end

    -- ========== v1.7.0: FLAT TIRE STEERING PULL ==========
    -- Flat tire causes strong, consistent pull to one side
    -- This applies REGARDLESS of hydraulic state

    if spec.hasFlatTire and config.enableFlatTire then
        -- Flat tire pull is strong and constant
        local flatTirePullStrength = config.flatTirePullStrength  -- 0.25 = 25% steering bias

        -- Speed factor - more noticeable at speed, but still present at low speed
        local flatSpeedFactor = 0.3  -- Minimum 30% effect even at low speed
        if speed > 3 then
            flatSpeedFactor = math.min(0.3 + (speed / 40) * 0.7, 1.0)  -- Scales up to 100% at 40 km/h
        end

        -- Apply flat tire pull
        local flatPullAmount = flatTirePullStrength * flatSpeedFactor * spec.flatTireSide
        inputValue = inputValue + flatPullAmount

        -- Clamp to valid range
        inputValue = math.max(-1, math.min(1, inputValue))
    end

    -- ========== HYDRAULIC STEERING DEGRADATION ==========
    -- Only apply if enabled and hydraulics are degraded

    if not config.enableSteeringDegradation then
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    if hydraulicReliability >= config.steeringPullThreshold then
        -- Good hydraulics, no additional degradation - reset pull state
        -- (but flat tire pull already applied above if present)
        spec.steeringPullDirection = 0
        spec.steeringPullInitialized = false
        spec.hasShownPullWarning = false
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    -- ========== v1.6.0: STEERING PULL (consistent bias to one side) ==========

    -- Initialize pull direction once (vehicle develops a "personality")
    if not spec.steeringPullInitialized then
        spec.steeringPullDirection = math.random() < 0.5 and -1 or 1  -- Left or right
        spec.steeringPullInitialized = true
        -- Set initial surge timer
        local surgeInterval = math.random(config.steeringPullSurgeIntervalMin, config.steeringPullSurgeIntervalMax)
        spec.steeringPullSurgeTimer = surgeInterval
        UsedPlus.logDebug(string.format("Steering pull initialized: direction=%d, nextSurge=%dms",
            spec.steeringPullDirection, surgeInterval))
    end

    -- Calculate base pull strength based on reliability
    -- 70% reliability = 0% pull, 0% reliability = max pull (15%)
    local pullFactor = (config.steeringPullThreshold - hydraulicReliability) / config.steeringPullThreshold
    local basePullStrength = pullFactor * config.steeringPullMax

    -- Speed factor - pull is more noticeable at higher speeds
    -- Below min speed: no pull (safety at low speed maneuvering)
    -- Above max speed: full pull effect
    local speedFactor = 0
    if speed > config.steeringPullSpeedMin then
        speedFactor = math.min((speed - config.steeringPullSpeedMin) / (config.steeringPullSpeedMax - config.steeringPullSpeedMin), 1.0)
    end

    -- Check for surge event (temporary intensification)
    local currentTime = g_currentMission.time or 0
    local surgeMultiplier = 1.0

    if spec.steeringPullSurgeActive then
        -- Currently in a surge
        if currentTime >= spec.steeringPullSurgeEndTime then
            -- Surge ended
            spec.steeringPullSurgeActive = false
            -- Schedule next surge
            local surgeInterval = math.random(config.steeringPullSurgeIntervalMin, config.steeringPullSurgeIntervalMax)
            spec.steeringPullSurgeTimer = surgeInterval
        else
            -- Still surging - apply multiplier
            surgeMultiplier = config.steeringPullSurgeMultiplier
        end
    end

    -- Calculate final pull amount
    local pullAmount = basePullStrength * speedFactor * surgeMultiplier * spec.steeringPullDirection

    -- Apply pull to steering input (before wander)
    if speedFactor > 0 then
        inputValue = inputValue + pullAmount

        -- Show one-time warning when pull first manifests
        if not spec.hasShownPullWarning and UsedPlusMaintenance.shouldShowWarning(self) then
            local directionText = spec.steeringPullDirection < 0 and
                (g_i18n:getText("usedPlus_directionLeft") or "left") or
                (g_i18n:getText("usedPlus_directionRight") or "right")
            g_currentMission:showBlinkingWarning(
                string.format(g_i18n:getText("usedPlus_steeringPull") or "Steering pulling to the %s!", directionText),
                3000
            )
            spec.hasShownPullWarning = true
        end

        -- Show surge warning (if during surge and significant)
        if spec.steeringPullSurgeActive and surgeMultiplier > 1.0 then
            -- Could add a brief warning here, but might be too spammy
            -- The intensification itself is the feedback
        end
    end

    -- ========== STEERING WANDER (random micro-adjustments) ==========

    if speed > 3 then  -- Above 3 km/h
        -- Calculate slop factor (how loose the steering is)
        -- 70% reliability = 0% slop
        -- 40% reliability = 43% slop
        -- 10% reliability = 86% slop
        local slopFactor = (config.steeringPullThreshold - hydraulicReliability) / config.steeringPullThreshold
        slopFactor = math.min(slopFactor, 0.9)  -- Max 90% slop

        -- Generate steering wander (random drift that accumulates)
        -- Higher speed = more noticeable wander
        local wanderSpeedFactor = math.min(speed / 30, 1.0)  -- Maxes out at 30 km/h
        local wanderIntensity = slopFactor * wanderSpeedFactor * 0.08  -- Max ~7% input modification

        -- Smooth random wander (not jerky)
        spec.steeringWanderTarget = spec.steeringWanderTarget or 0
        spec.steeringWanderCurrent = spec.steeringWanderCurrent or 0

        -- Occasionally change wander target (every ~0.5-2 seconds worth of frames)
        if math.random() < 0.02 then  -- ~2% chance per frame
            spec.steeringWanderTarget = (math.random() - 0.5) * 2 * wanderIntensity
        end

        -- Smoothly approach target (creates gradual drift, not sudden jerks)
        local approach = 0.05  -- 5% per frame toward target
        spec.steeringWanderCurrent = spec.steeringWanderCurrent + (spec.steeringWanderTarget - spec.steeringWanderCurrent) * approach

        -- Apply wander to input
        -- When player is steering hard, wander has less effect (they're actively fighting it)
        local playerInputStrength = math.abs(inputValue)
        local wanderWeight = 1.0 - (playerInputStrength * 0.7)  -- Wander reduced when steering hard
        local finalWander = spec.steeringWanderCurrent * wanderWeight

        inputValue = inputValue + finalWander

        -- Clamp to valid range
        inputValue = math.max(-1, math.min(1, inputValue))

        -- Occasional larger "slip" for very worn steering (dramatic effect)
        if hydraulicReliability < 0.3 and math.random() < 0.001 then  -- Very rare
            local slip = (math.random() - 0.5) * 0.15  -- Up to 15% slip
            inputValue = math.max(-1, math.min(1, inputValue + slip))

            -- Show warning on first slip
            -- v1.6.0: Only show if player is controlling this vehicle
            if not spec.hasShownSteeringWarning and UsedPlusMaintenance.shouldShowWarning(self) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_steeringLoose") or "Steering feels loose!",
                    2000
                )
                spec.hasShownSteeringWarning = true
            end
        end
    else
        -- Reset wander when stopped
        spec.steeringWanderCurrent = 0
        spec.steeringWanderTarget = 0
    end

    -- Final clamp
    inputValue = math.max(-1, math.min(1, inputValue))

    return superFunc(self, inputValue, isAnalog, deviceCategory)
end

--[[
    Called when vehicle is loaded
    Initialize all spec data with defaults
    Pattern from: HeadlandManagement onLoad
]]
function UsedPlusMaintenance:onLoad(savegame)
    -- Make spec accessible via self.spec_usedPlusMaintenance
    self.spec_usedPlusMaintenance = self["spec_" .. UsedPlusMaintenance.SPEC_NAME]
    local spec = self.spec_usedPlusMaintenance

    if spec == nil then
        UsedPlus.logWarn("UsedPlusMaintenance spec not found for vehicle: " .. tostring(self:getName()))
        return
    end

    -- Create dirty flag for network sync
    spec.dirtyFlag = self:getNextDirtyFlag()

    -- Purchase Information
    spec.purchasedUsed = false
    spec.purchaseDate = 0
    spec.purchasePrice = 0
    spec.purchaseDamage = 0
    spec.purchaseHours = 0
    spec.wasInspected = false

    -- Hidden Reliability Scores (1.0 = perfect, 0.0 = broken)
    spec.engineReliability = 1.0
    spec.hydraulicReliability = 1.0
    spec.electricalReliability = 1.0

    -- Workhorse/Lemon Scale System (v1.4.0+)
    -- Hidden "DNA" of the vehicle - NEVER changes after creation
    spec.workhorseLemonScale = 0.5   -- Default average, will be set properly on purchase
    spec.maxReliabilityCeiling = 1.0 -- Starts at 100%, degrades over repairs based on DNA

    -- Maintenance History
    spec.repairCount = 0
    spec.totalRepairCost = 0
    spec.lastRepairDate = 0
    spec.failureCount = 0

    -- Inspection Cache (for paid inspections)
    spec.hasInspectionCache = false
    spec.inspectionCacheHours = 0
    spec.inspectionCacheDamage = 0
    spec.inspectionCacheWear = 0

    -- Runtime State (not persisted)
    spec.updateTimer = 0
    spec.stallCooldown = 0
    spec.isStalled = false
    spec.currentMaxSpeed = nil

    -- Electrical cutout state
    spec.cutoutTimer = 0
    spec.isCutout = false
    spec.cutoutEndTime = 0

    -- Hydraulic drift state
    spec.isDrifting = false

    -- v1.5.1: Stall recovery state (prevents immediate restart)
    spec.stallRecoveryEndTime = 0

    -- v1.6.0: Startup grace period - prevents warnings immediately after load/purchase
    -- Warnings only show after player has been in control for a few seconds
    spec.startupGracePeriod = 2000  -- 2 seconds before warnings can show (reduced from 5)
    spec.lastIsActiveForInput = false  -- Track player control state for override functions

    -- Warning notification state (reset per session, not persisted)
    -- Speed degradation warnings
    spec.hasShownSpeedWarning = false
    spec.speedWarningTimer = 0
    spec.speedWarningInterval = 300000  -- 5 minutes between reminders

    -- Hydraulic drift warnings
    spec.hasShownDriftWarning = false
    spec.hasShownDriftMidpointWarning = false

    -- v1.6.0: Steering pull state (worn vehicles pull to one side)
    spec.steeringPullDirection = 0        -- -1 = left, 0 = none, +1 = right
    spec.steeringPullInitialized = false  -- Set true once direction is chosen
    spec.steeringPullSurgeTimer = 0       -- Countdown to next surge event
    spec.steeringPullSurgeActive = false  -- True during a surge
    spec.steeringPullSurgeEndTime = 0     -- When current surge ends
    spec.hasShownPullWarning = false      -- One-time warning when pull manifests

    -- v1.6.0: Engine misfiring state
    spec.misfireTimer = 0                 -- Timer for misfire check interval
    spec.misfireActive = false            -- True during a misfire
    spec.misfireEndTime = 0               -- When current misfire ends
    spec.misfireBurstRemaining = 0        -- Remaining misfires in burst
    spec.hasShownMisfireWarning = false   -- One-time warning

    -- v1.6.0: Engine overheating state
    spec.engineTemperature = 0            -- 0 = cold, 1 = overheated
    spec.isOverheated = false             -- True when engine overheated and cooling
    spec.overheatCooldownEndTime = 0      -- Minimum time before restart
    spec.hasShownOverheatWarning = false  -- Warning at 70% temp
    spec.hasShownOverheatCritical = false -- Warning at critical temp

    -- v1.6.0: Implement malfunction state
    spec.implementMalfunctionTimer = 0    -- Timer for implement checks
    spec.hasShownSurgeWarning = false     -- One-time surge warning
    spec.hasShownDropWarning = false      -- One-time drop warning
    spec.hasShownPTOWarning = false       -- One-time PTO toggle warning
    spec.hasShownHitchWarning = false     -- One-time hitch failure warning

    -- v1.7.0: Tire system state
    spec.tireCondition = 1.0              -- 0-1, 1 = new tires
    spec.tireQuality = 2                  -- 1=Retread, 2=Normal, 3=Quality
    spec.tireMaxTraction = 1.0            -- Traction multiplier based on quality
    spec.tireFailureMultiplier = 1.0      -- Failure chance multiplier based on quality
    spec.distanceTraveled = 0             -- Meters traveled (for wear calculation)
    spec.lastPosition = nil               -- For distance tracking
    spec.hasFlatTire = false              -- True if currently has a flat
    spec.flatTireSide = 0                 -- -1=left, 0=none, 1=right
    spec.hasShownTireWarnWarning = false  -- One-time tire low warning
    spec.hasShownTireCriticalWarning = false -- One-time critical tire warning
    spec.hasShownFlatTireWarning = false  -- One-time flat tire warning
    spec.hasShownLowTractionWarning = false -- One-time traction warning

    -- v1.7.0: Oil system state
    spec.oilLevel = 1.0                   -- 0-1, 1 = full
    spec.wasLowOil = false                -- Track if engine ran low (for permanent damage)
    spec.hasOilLeak = false               -- True if currently leaking
    spec.oilLeakSeverity = 0              -- 0=none, 1=minor, 2=moderate, 3=severe
    spec.engineReliabilityCeiling = 1.0   -- Permanent ceiling (separate from maxReliabilityCeiling)
    spec.hasShownOilWarnWarning = false   -- One-time oil low warning
    spec.hasShownOilCriticalWarning = false -- One-time critical oil warning
    spec.hasShownOilLeakWarning = false   -- One-time oil leak warning

    -- v1.7.0: Hydraulic fluid system state
    spec.hydraulicFluidLevel = 1.0        -- 0-1, 1 = full
    spec.wasLowHydraulicFluid = false     -- Track if ran low (for permanent damage)
    spec.hasHydraulicLeak = false         -- True if currently leaking
    spec.hydraulicLeakSeverity = 0        -- 0=none, 1=minor, 2=moderate, 3=severe
    spec.hydraulicReliabilityCeiling = 1.0 -- Permanent ceiling for hydraulics
    spec.hasShownHydraulicWarnWarning = false -- One-time hydraulic low warning
    spec.hasShownHydraulicCriticalWarning = false -- One-time critical warning
    spec.hasShownHydraulicLeakWarning = false -- One-time leak warning

    -- v1.7.0: Fuel leak state
    spec.hasFuelLeak = false              -- True if currently leaking fuel
    spec.fuelLeakMultiplier = 1.0         -- Current fuel consumption multiplier
    spec.hasShownFuelLeakWarning = false  -- One-time fuel leak warning

    UsedPlus.logTrace("UsedPlusMaintenance onLoad complete for: " .. tostring(self:getName()))
end

--[[
    Called after vehicle is fully loaded
    Load saved data from savegame if available
    Pattern from: HeadlandManagement onPostLoad
]]
function UsedPlusMaintenance:onPostLoad(savegame)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    if savegame ~= nil then
        local xmlFile = savegame.xmlFile
        local key = savegame.key .. "." .. UsedPlusMaintenance.SPEC_NAME

        -- Load purchase information
        spec.purchasedUsed = xmlFile:getValue(key .. ".purchasedUsed", spec.purchasedUsed)
        spec.purchaseDate = xmlFile:getValue(key .. ".purchaseDate", spec.purchaseDate)
        spec.purchasePrice = xmlFile:getValue(key .. ".purchasePrice", spec.purchasePrice)
        spec.purchaseDamage = xmlFile:getValue(key .. ".purchaseDamage", spec.purchaseDamage)
        spec.purchaseHours = xmlFile:getValue(key .. ".purchaseHours", spec.purchaseHours)
        spec.wasInspected = xmlFile:getValue(key .. ".wasInspected", spec.wasInspected)

        -- Load hidden reliability scores
        spec.engineReliability = xmlFile:getValue(key .. ".engineReliability", spec.engineReliability)
        spec.hydraulicReliability = xmlFile:getValue(key .. ".hydraulicReliability", spec.hydraulicReliability)
        spec.electricalReliability = xmlFile:getValue(key .. ".electricalReliability", spec.electricalReliability)

        -- Load Workhorse/Lemon Scale (v1.4.0+)
        spec.workhorseLemonScale = xmlFile:getValue(key .. ".workhorseLemonScale", spec.workhorseLemonScale)
        spec.maxReliabilityCeiling = xmlFile:getValue(key .. ".maxReliabilityCeiling", spec.maxReliabilityCeiling)

        -- Load maintenance history
        spec.repairCount = xmlFile:getValue(key .. ".repairCount", spec.repairCount)
        spec.totalRepairCost = xmlFile:getValue(key .. ".totalRepairCost", spec.totalRepairCost)
        spec.lastRepairDate = xmlFile:getValue(key .. ".lastRepairDate", spec.lastRepairDate)
        spec.failureCount = xmlFile:getValue(key .. ".failureCount", spec.failureCount)

        -- Load inspection cache
        spec.hasInspectionCache = xmlFile:getValue(key .. ".hasInspectionCache", spec.hasInspectionCache)
        spec.inspectionCacheHours = xmlFile:getValue(key .. ".inspectionCacheHours", spec.inspectionCacheHours)
        spec.inspectionCacheDamage = xmlFile:getValue(key .. ".inspectionCacheDamage", spec.inspectionCacheDamage)
        spec.inspectionCacheWear = xmlFile:getValue(key .. ".inspectionCacheWear", spec.inspectionCacheWear)

        -- v1.7.0: Load tire system state (with nil guards for old savegames)
        spec.tireCondition = xmlFile:getValue(key .. ".tireCondition", spec.tireCondition) or 1.0
        spec.tireQuality = xmlFile:getValue(key .. ".tireQuality", spec.tireQuality) or 2
        spec.distanceTraveled = xmlFile:getValue(key .. ".distanceTraveled", spec.distanceTraveled) or 0
        spec.hasFlatTire = xmlFile:getValue(key .. ".hasFlatTire", spec.hasFlatTire) or false
        spec.flatTireSide = xmlFile:getValue(key .. ".flatTireSide", spec.flatTireSide) or ""

        -- Apply tire quality modifiers after loading
        if spec.tireQuality == 1 then  -- Retread
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireRetreadTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireRetreadFailureMult
        elseif spec.tireQuality == 3 then  -- Quality
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireQualityTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireQualityFailureMult
        else  -- Normal (2)
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireNormalTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireNormalFailureMult
        end

        -- v1.7.0: Load oil system state (with nil guards for old savegames)
        spec.oilLevel = xmlFile:getValue(key .. ".oilLevel", spec.oilLevel) or 1.0
        spec.wasLowOil = xmlFile:getValue(key .. ".wasLowOil", spec.wasLowOil) or false
        spec.hasOilLeak = xmlFile:getValue(key .. ".hasOilLeak", spec.hasOilLeak) or false
        spec.oilLeakSeverity = xmlFile:getValue(key .. ".oilLeakSeverity", spec.oilLeakSeverity) or 1.0
        spec.engineReliabilityCeiling = xmlFile:getValue(key .. ".engineReliabilityCeiling", spec.engineReliabilityCeiling) or 1.0

        -- v1.7.0: Load hydraulic fluid system state (with nil guards for old savegames)
        spec.hydraulicFluidLevel = xmlFile:getValue(key .. ".hydraulicFluidLevel", spec.hydraulicFluidLevel) or 1.0
        spec.wasLowHydraulicFluid = xmlFile:getValue(key .. ".wasLowHydraulicFluid", spec.wasLowHydraulicFluid) or false
        spec.hasHydraulicLeak = xmlFile:getValue(key .. ".hasHydraulicLeak", spec.hasHydraulicLeak) or false
        spec.hydraulicLeakSeverity = xmlFile:getValue(key .. ".hydraulicLeakSeverity", spec.hydraulicLeakSeverity) or 1.0
        spec.hydraulicReliabilityCeiling = xmlFile:getValue(key .. ".hydraulicReliabilityCeiling", spec.hydraulicReliabilityCeiling) or 1.0

        -- v1.7.0: Load fuel leak state (with nil guards for old savegames)
        spec.hasFuelLeak = xmlFile:getValue(key .. ".hasFuelLeak", spec.hasFuelLeak) or false
        spec.fuelLeakMultiplier = xmlFile:getValue(key .. ".fuelLeakMultiplier", spec.fuelLeakMultiplier) or 1.0

        UsedPlus.logTrace(string.format("UsedPlusMaintenance loaded for %s: used=%s, engine=%.2f, repairs=%d, tires=%.0f%%, oil=%.0f%%",
            self:getName(), tostring(spec.purchasedUsed), spec.engineReliability, spec.repairCount,
            spec.tireCondition * 100, spec.oilLevel * 100))
    end
end

--[[
    Save vehicle data to XML
    Pattern from: HeadlandManagement saveToXMLFile
]]
function UsedPlusMaintenance:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Save purchase information
    xmlFile:setValue(key .. ".purchasedUsed", spec.purchasedUsed)
    xmlFile:setValue(key .. ".purchaseDate", spec.purchaseDate)
    xmlFile:setValue(key .. ".purchasePrice", spec.purchasePrice)
    xmlFile:setValue(key .. ".purchaseDamage", spec.purchaseDamage)
    xmlFile:setValue(key .. ".purchaseHours", spec.purchaseHours)
    xmlFile:setValue(key .. ".wasInspected", spec.wasInspected)

    -- Save hidden reliability scores
    xmlFile:setValue(key .. ".engineReliability", spec.engineReliability)
    xmlFile:setValue(key .. ".hydraulicReliability", spec.hydraulicReliability)
    xmlFile:setValue(key .. ".electricalReliability", spec.electricalReliability)

    -- Save Workhorse/Lemon Scale (v1.4.0+)
    xmlFile:setValue(key .. ".workhorseLemonScale", spec.workhorseLemonScale)
    xmlFile:setValue(key .. ".maxReliabilityCeiling", spec.maxReliabilityCeiling)

    -- Save maintenance history
    xmlFile:setValue(key .. ".repairCount", spec.repairCount)
    xmlFile:setValue(key .. ".totalRepairCost", spec.totalRepairCost)
    xmlFile:setValue(key .. ".lastRepairDate", spec.lastRepairDate)
    xmlFile:setValue(key .. ".failureCount", spec.failureCount)

    -- Save inspection cache
    xmlFile:setValue(key .. ".hasInspectionCache", spec.hasInspectionCache)
    xmlFile:setValue(key .. ".inspectionCacheHours", spec.inspectionCacheHours)
    xmlFile:setValue(key .. ".inspectionCacheDamage", spec.inspectionCacheDamage)
    xmlFile:setValue(key .. ".inspectionCacheWear", spec.inspectionCacheWear)

    -- v1.7.0: Save tire system state
    xmlFile:setValue(key .. ".tireCondition", spec.tireCondition)
    xmlFile:setValue(key .. ".tireQuality", spec.tireQuality)
    xmlFile:setValue(key .. ".distanceTraveled", spec.distanceTraveled)
    xmlFile:setValue(key .. ".hasFlatTire", spec.hasFlatTire)
    xmlFile:setValue(key .. ".flatTireSide", spec.flatTireSide)

    -- v1.7.0: Save oil system state
    xmlFile:setValue(key .. ".oilLevel", spec.oilLevel)
    xmlFile:setValue(key .. ".wasLowOil", spec.wasLowOil)
    xmlFile:setValue(key .. ".hasOilLeak", spec.hasOilLeak)
    xmlFile:setValue(key .. ".oilLeakSeverity", spec.oilLeakSeverity)
    xmlFile:setValue(key .. ".engineReliabilityCeiling", spec.engineReliabilityCeiling)

    -- v1.7.0: Save hydraulic fluid system state
    xmlFile:setValue(key .. ".hydraulicFluidLevel", spec.hydraulicFluidLevel)
    xmlFile:setValue(key .. ".wasLowHydraulicFluid", spec.wasLowHydraulicFluid)
    xmlFile:setValue(key .. ".hasHydraulicLeak", spec.hasHydraulicLeak)
    xmlFile:setValue(key .. ".hydraulicLeakSeverity", spec.hydraulicLeakSeverity)
    xmlFile:setValue(key .. ".hydraulicReliabilityCeiling", spec.hydraulicReliabilityCeiling)

    -- v1.7.0: Save fuel leak state
    xmlFile:setValue(key .. ".hasFuelLeak", spec.hasFuelLeak)
    xmlFile:setValue(key .. ".fuelLeakMultiplier", spec.fuelLeakMultiplier)

    UsedPlus.logTrace(string.format("UsedPlusMaintenance saved for %s", self:getName()))
end

--[[
    Read data from network stream (multiplayer client join)
    Pattern from: HeadlandManagement onReadStream
]]
function UsedPlusMaintenance:onReadStream(streamId, connection)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Purchase info
    spec.purchasedUsed = streamReadBool(streamId)
    spec.purchaseDate = streamReadFloat32(streamId)
    spec.purchasePrice = streamReadFloat32(streamId)
    spec.purchaseDamage = streamReadFloat32(streamId)
    spec.purchaseHours = streamReadFloat32(streamId)
    spec.wasInspected = streamReadBool(streamId)

    -- Reliability scores
    spec.engineReliability = streamReadFloat32(streamId)
    spec.hydraulicReliability = streamReadFloat32(streamId)
    spec.electricalReliability = streamReadFloat32(streamId)

    -- Workhorse/Lemon Scale (v1.4.0+)
    spec.workhorseLemonScale = streamReadFloat32(streamId)
    spec.maxReliabilityCeiling = streamReadFloat32(streamId)

    -- Maintenance history
    spec.repairCount = streamReadInt32(streamId)
    spec.totalRepairCost = streamReadFloat32(streamId)
    spec.lastRepairDate = streamReadFloat32(streamId)
    spec.failureCount = streamReadInt32(streamId)

    -- Inspection cache
    spec.hasInspectionCache = streamReadBool(streamId)
    spec.inspectionCacheHours = streamReadFloat32(streamId)
    spec.inspectionCacheDamage = streamReadFloat32(streamId)
    spec.inspectionCacheWear = streamReadFloat32(streamId)

    -- v1.7.0: Tire system
    spec.tireCondition = streamReadFloat32(streamId)
    spec.tireQuality = streamReadInt8(streamId)
    spec.distanceTraveled = streamReadFloat32(streamId)
    spec.hasFlatTire = streamReadBool(streamId)
    spec.flatTireSide = streamReadInt8(streamId)

    -- Apply tire quality modifiers after reading
    if spec.tireQuality == 1 then  -- Retread
        spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireRetreadTractionMult
        spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireRetreadFailureMult
    elseif spec.tireQuality == 3 then  -- Quality
        spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireQualityTractionMult
        spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireQualityFailureMult
    else  -- Normal (2)
        spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireNormalTractionMult
        spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireNormalFailureMult
    end

    -- v1.7.0: Oil system
    spec.oilLevel = streamReadFloat32(streamId)
    spec.wasLowOil = streamReadBool(streamId)
    spec.hasOilLeak = streamReadBool(streamId)
    spec.oilLeakSeverity = streamReadInt8(streamId)
    spec.engineReliabilityCeiling = streamReadFloat32(streamId)

    -- v1.7.0: Hydraulic fluid system
    spec.hydraulicFluidLevel = streamReadFloat32(streamId)
    spec.wasLowHydraulicFluid = streamReadBool(streamId)
    spec.hasHydraulicLeak = streamReadBool(streamId)
    spec.hydraulicLeakSeverity = streamReadInt8(streamId)
    spec.hydraulicReliabilityCeiling = streamReadFloat32(streamId)

    -- v1.7.0: Fuel leak
    spec.hasFuelLeak = streamReadBool(streamId)
    spec.fuelLeakMultiplier = streamReadFloat32(streamId)

    UsedPlus.logTrace("UsedPlusMaintenance onReadStream complete")
end

--[[
    Write data to network stream (multiplayer)
    Pattern from: HeadlandManagement onWriteStream
]]
function UsedPlusMaintenance:onWriteStream(streamId, connection)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Purchase info
    streamWriteBool(streamId, spec.purchasedUsed)
    streamWriteFloat32(streamId, spec.purchaseDate)
    streamWriteFloat32(streamId, spec.purchasePrice)
    streamWriteFloat32(streamId, spec.purchaseDamage)
    streamWriteFloat32(streamId, spec.purchaseHours)
    streamWriteBool(streamId, spec.wasInspected)

    -- Reliability scores
    streamWriteFloat32(streamId, spec.engineReliability)
    streamWriteFloat32(streamId, spec.hydraulicReliability)
    streamWriteFloat32(streamId, spec.electricalReliability)

    -- Workhorse/Lemon Scale (v1.4.0+)
    streamWriteFloat32(streamId, spec.workhorseLemonScale)
    streamWriteFloat32(streamId, spec.maxReliabilityCeiling)

    -- Maintenance history
    streamWriteInt32(streamId, spec.repairCount)
    streamWriteFloat32(streamId, spec.totalRepairCost)
    streamWriteFloat32(streamId, spec.lastRepairDate)
    streamWriteInt32(streamId, spec.failureCount)

    -- Inspection cache
    streamWriteBool(streamId, spec.hasInspectionCache)
    streamWriteFloat32(streamId, spec.inspectionCacheHours)
    streamWriteFloat32(streamId, spec.inspectionCacheDamage)
    streamWriteFloat32(streamId, spec.inspectionCacheWear)

    -- v1.7.0: Tire system
    streamWriteFloat32(streamId, spec.tireCondition)
    streamWriteInt8(streamId, spec.tireQuality)
    streamWriteFloat32(streamId, spec.distanceTraveled)
    streamWriteBool(streamId, spec.hasFlatTire)
    streamWriteInt8(streamId, spec.flatTireSide)

    -- v1.7.0: Oil system
    streamWriteFloat32(streamId, spec.oilLevel)
    streamWriteBool(streamId, spec.wasLowOil)
    streamWriteBool(streamId, spec.hasOilLeak)
    streamWriteInt8(streamId, spec.oilLeakSeverity)
    streamWriteFloat32(streamId, spec.engineReliabilityCeiling)

    -- v1.7.0: Hydraulic fluid system
    streamWriteFloat32(streamId, spec.hydraulicFluidLevel)
    streamWriteBool(streamId, spec.wasLowHydraulicFluid)
    streamWriteBool(streamId, spec.hasHydraulicLeak)
    streamWriteInt8(streamId, spec.hydraulicLeakSeverity)
    streamWriteFloat32(streamId, spec.hydraulicReliabilityCeiling)

    -- v1.7.0: Fuel leak
    streamWriteBool(streamId, spec.hasFuelLeak)
    streamWriteFloat32(streamId, spec.fuelLeakMultiplier)

    UsedPlus.logTrace("UsedPlusMaintenance onWriteStream complete")
end

--[[
    Called every frame when vehicle is active
    Throttled to check failures every 1 second
    Pattern from: HeadlandManagement onUpdate
]]
function UsedPlusMaintenance:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- v1.7.1: Track player control state BEFORE server check
    -- This runs on both client and server so shouldShowWarning() works properly
    -- Without this, multiplayer clients never see warnings because lastIsActiveForInput stays false
    spec.lastIsActiveForInput = isActiveForInput

    -- v1.7.1: Countdown startup grace period on client AND server
    -- Prevents warnings immediately after loading or purchasing a vehicle
    if isActiveForInput and spec.startupGracePeriod and spec.startupGracePeriod > 0 then
        spec.startupGracePeriod = spec.startupGracePeriod - dt
    end

    -- Only process FAILURE SIMULATION on server (state changes, probability checks, etc.)
    -- Warnings and display logic happens above and in override functions on clients
    if not self.isServer then return end

    -- Update stall cooldown
    if spec.stallCooldown > 0 then
        spec.stallCooldown = spec.stallCooldown - dt
    end

    -- v1.5.1: Process first-start stall timer
    if spec.firstStartStallPending and spec.firstStartStallTimer then
        spec.firstStartStallTimer = spec.firstStartStallTimer - dt
        if spec.firstStartStallTimer <= 0 then
            spec.firstStartStallPending = false
            spec.firstStartStallTimer = nil
            -- Trigger the stall with custom first-start message (no duplicate warning)
            UsedPlusMaintenance.triggerEngineStall(self, true)  -- true = isFirstStart
        end
    end

    -- ========== PER-FRAME CHECKS (must run every frame for smooth physics) ==========

    -- v1.5.1: Enforce speed limit with braking (every frame for smooth limiting)
    if UsedPlusMaintenance.CONFIG.enableSpeedDegradation then
        UsedPlusMaintenance.enforceSpeedLimit(self, dt)
    end

    -- v1.5.1: Apply steering degradation (every frame for smooth feel)
    if UsedPlusMaintenance.CONFIG.enableSteeringDegradation then
        UsedPlusMaintenance.applySteeringDegradation(self, dt)
    end

    -- v1.6.0: Check and update misfire state (per-frame for responsive feel)
    if UsedPlusMaintenance.CONFIG.enableMisfiring then
        UsedPlusMaintenance.updateMisfireState(self, dt)
    end

    -- v1.7.0: Track distance traveled for tire wear (per-frame for accuracy)
    if UsedPlusMaintenance.CONFIG.enableTireWear then
        UsedPlusMaintenance.trackDistanceTraveled(self, dt)
    end

    -- ========== PERIODIC CHECKS (throttled to every 1 second) ==========

    spec.updateTimer = (spec.updateTimer or 0) + dt
    if spec.updateTimer < UsedPlusMaintenance.CONFIG.updateIntervalMs then
        return
    end
    spec.updateTimer = 0

    -- Calculate speed limit factor (updates spec.maxSpeedFactor)
    if UsedPlusMaintenance.CONFIG.enableSpeedDegradation then
        UsedPlusMaintenance.calculateSpeedLimit(self)
    end

    -- Only check failures if feature is enabled
    if UsedPlusMaintenance.CONFIG.enableFailures then
        UsedPlusMaintenance.checkEngineStall(self)
    end

    -- Hydraulic drift (implements slowly lower)
    if UsedPlusMaintenance.CONFIG.enableHydraulicDrift then
        UsedPlusMaintenance.checkHydraulicDrift(self, dt)
    end

    -- Electrical cutout (implements randomly shut off)
    if UsedPlusMaintenance.CONFIG.enableElectricalCutout then
        UsedPlusMaintenance.checkImplementCutout(self, dt)
    end

    -- v1.6.0: Steering pull surge timer (intermittent intensification)
    if UsedPlusMaintenance.CONFIG.enableSteeringDegradation then
        UsedPlusMaintenance.updateSteeringPullSurge(self)
    end

    -- v1.6.0: Engine misfiring (check for new misfire triggers)
    if UsedPlusMaintenance.CONFIG.enableMisfiring then
        UsedPlusMaintenance.checkEngineMisfire(self)
    end

    -- v1.6.0: Engine overheating (temperature management)
    if UsedPlusMaintenance.CONFIG.enableOverheating then
        UsedPlusMaintenance.updateEngineTemperature(self)
    end

    -- v1.6.0: Implement malfunctions (surge, drop, PTO, hitch)
    UsedPlusMaintenance.checkImplementMalfunctions(self)

    -- v1.7.0: Tire wear and malfunctions
    if UsedPlusMaintenance.CONFIG.enableTireWear then
        UsedPlusMaintenance.applyTireWear(self)
        UsedPlusMaintenance.checkTireMalfunctions(self)
    end

    -- v1.7.0: Oil system (depletion, leak processing, damage)
    if UsedPlusMaintenance.CONFIG.enableOilSystem then
        UsedPlusMaintenance.updateOilSystem(self, dt)
    end

    -- v1.7.0: Hydraulic fluid system (depletion, leak processing, damage)
    if UsedPlusMaintenance.CONFIG.enableHydraulicFluidSystem then
        UsedPlusMaintenance.updateHydraulicFluidSystem(self, dt)
    end

    -- v1.7.0: Check for new leaks (oil, hydraulic, fuel)
    UsedPlusMaintenance.checkForNewLeaks(self)

    -- v1.7.0: Process fuel leak (drains fuel from tank)
    UsedPlusMaintenance.processFuelLeak(self, dt)

    -- v1.8.0: Sync data from external mods (RVB, UYT)
    -- This keeps our reliability and tire data in sync when other mods are managing those systems
    ModCompatibility.syncTireConditionFromUYT(self)
    ModCompatibility.syncReliabilityFromRVB(self)
end

--[[
    v1.6.0: Update steering pull surge timer and trigger surge events
    Called every 1 second from onUpdate periodic checks
    Surges create "oh crap" moments where pull temporarily intensifies
]]
function UsedPlusMaintenance.updateSteeringPullSurge(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Only process if pull is active (direction initialized)
    if not spec.steeringPullInitialized or spec.steeringPullDirection == 0 then
        return
    end

    -- Don't start new surge if one is already active
    if spec.steeringPullSurgeActive then
        return
    end

    local config = UsedPlusMaintenance.CONFIG

    -- Decrement surge timer
    spec.steeringPullSurgeTimer = (spec.steeringPullSurgeTimer or 0) - config.updateIntervalMs

    -- Check if it's time for a surge
    if spec.steeringPullSurgeTimer <= 0 then
        -- Trigger surge!
        spec.steeringPullSurgeActive = true
        spec.steeringPullSurgeEndTime = (g_currentMission.time or 0) + config.steeringPullSurgeDuration

        UsedPlus.logDebug(string.format("Steering pull surge triggered on %s (direction=%d, duration=%dms)",
            vehicle:getName(), spec.steeringPullDirection, config.steeringPullSurgeDuration))
    end
end

--[[
    v1.6.0: Update misfire state per-frame
    Handles active misfire timing and burst mode
    Called every frame for responsive stuttering effect
]]
function UsedPlusMaintenance.updateMisfireState(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local currentTime = g_currentMission.time or 0

    -- Check if currently in a misfire
    if spec.misfireActive then
        if currentTime >= spec.misfireEndTime then
            -- Misfire ended
            spec.misfireActive = false

            -- Check for burst mode (multiple quick misfires)
            if spec.misfireBurstRemaining and spec.misfireBurstRemaining > 0 then
                spec.misfireBurstRemaining = spec.misfireBurstRemaining - 1
                -- Schedule next misfire in burst (50-150ms gap)
                local gapMs = math.random(50, 150)
                spec.misfireActive = true
                local duration = math.random(
                    UsedPlusMaintenance.CONFIG.misfireDurationMin,
                    UsedPlusMaintenance.CONFIG.misfireDurationMax
                )
                spec.misfireEndTime = currentTime + gapMs + duration
            end
        end
    end
end

--[[
    v1.6.0: Check for new engine misfire events
    Called every 1 second from periodic checks
    Triggers random misfires based on engine reliability
]]
function UsedPlusMaintenance.checkEngineMisfire(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    local engineReliability = spec.engineReliability or 1.0

    -- Only misfire if below threshold
    if engineReliability >= config.misfireThreshold then
        spec.hasShownMisfireWarning = false
        return
    end

    -- Don't start new misfire if one is active
    if spec.misfireActive then
        return
    end

    -- Only misfire if engine is running
    if not vehicle.getIsMotorStarted or not vehicle:getIsMotorStarted() then
        return
    end

    -- Calculate misfire chance based on reliability
    -- At threshold (60%): 0% chance
    -- At 0%: max chance (15%)
    local reliabilityFactor = (config.misfireThreshold - engineReliability) / config.misfireThreshold
    local misfireChance = reliabilityFactor * config.misfireMaxChancePerCheck

    -- Higher load = more likely to misfire
    local load = 0
    if vehicle.getMotorLoadPercentage then
        load = vehicle:getMotorLoadPercentage() or 0
    end
    misfireChance = misfireChance * (0.5 + load * 0.5)  -- 50-100% of base chance

    if math.random() < misfireChance then
        -- Trigger misfire!
        spec.misfireActive = true
        local duration = math.random(config.misfireDurationMin, config.misfireDurationMax)
        spec.misfireEndTime = (g_currentMission.time or 0) + duration

        -- Check for burst mode
        if math.random() < config.misfireBurstChance then
            spec.misfireBurstRemaining = math.random(1, config.misfireBurstCount)
        else
            spec.misfireBurstRemaining = 0
        end

        -- Show warning (once per session)
        if not spec.hasShownMisfireWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
            g_currentMission:showBlinkingWarning(
                g_i18n:getText("usedPlus_engineMisfire") or "Engine misfiring!",
                2000
            )
            spec.hasShownMisfireWarning = true
        end

        UsedPlus.logDebug(string.format("Engine misfire on %s (duration=%dms, burst=%d)",
            vehicle:getName(), duration, spec.misfireBurstRemaining or 0))
    end
end

--[[
    v1.6.0: Update engine temperature
    Heat builds when running, dissipates when off
    Overheating causes forced stall and cooldown period
]]
function UsedPlusMaintenance.updateEngineTemperature(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    local engineReliability = spec.engineReliability or 1.0
    local currentTime = g_currentMission.time or 0

    -- Only affected if below threshold
    if engineReliability >= config.overheatThreshold then
        -- Good engine - temperature stays at 0
        spec.engineTemperature = math.max(0, (spec.engineTemperature or 0) - config.overheatCoolRateOff)
        spec.hasShownOverheatWarning = false
        spec.hasShownOverheatCritical = false
        return
    end

    local isRunning = vehicle.getIsMotorStarted and vehicle:getIsMotorStarted()

    if isRunning then
        -- Engine running - heat builds up
        local load = 0
        if vehicle.getMotorLoadPercentage then
            load = vehicle:getMotorLoadPercentage() or 0
        end

        -- Heat rate scales with inverse reliability
        -- At 50% reliability: 1x heat rate
        -- At 25% reliability: 1.5x heat rate
        -- At 0% reliability: 2x heat rate
        local reliabilityFactor = 1 + (1 - engineReliability / config.overheatThreshold)

        local heatRate = config.overheatHeatRateBase + (load * config.overheatHeatRateLoad)
        heatRate = heatRate * reliabilityFactor

        spec.engineTemperature = math.min(1.0, (spec.engineTemperature or 0) + heatRate)

        -- Check for warning thresholds
        if spec.engineTemperature >= config.overheatWarningTemp then
            if not spec.hasShownOverheatWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                local tempPercent = math.floor(spec.engineTemperature * 100)
                g_currentMission:showBlinkingWarning(
                    string.format(g_i18n:getText("usedPlus_engineOverheating") or "Engine overheating! (%d%%)", tempPercent),
                    3000
                )
                spec.hasShownOverheatWarning = true
            end
        end

        -- Check for critical overheat (force stall)
        if spec.engineTemperature >= config.overheatStallTemp then
            if not spec.isOverheated then
                -- Force stall!
                if vehicle.stopMotor then
                    vehicle:stopMotor()
                end
                spec.isOverheated = true
                spec.overheatCooldownEndTime = currentTime + config.overheatCooldownMs
                spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as breakdown

                if UsedPlusMaintenance.shouldShowWarning(vehicle) then
                    g_currentMission:showBlinkingWarning(
                        g_i18n:getText("usedPlus_engineOverheated") or "ENGINE OVERHEATED! Let it cool down!",
                        5000
                    )
                end
                spec.hasShownOverheatCritical = true

                UsedPlus.logDebug(string.format("Engine overheated on %s - forced stall", vehicle:getName()))
            end
        end
    else
        -- Engine off - cool down
        local coolRate = config.overheatCoolRateOff
        spec.engineTemperature = math.max(0, (spec.engineTemperature or 0) - coolRate)

        -- Check if cooled enough to restart
        if spec.isOverheated then
            if currentTime >= spec.overheatCooldownEndTime and spec.engineTemperature <= config.overheatRestartTemp then
                spec.isOverheated = false
                spec.hasShownOverheatWarning = false
                spec.hasShownOverheatCritical = false
                UsedPlus.logDebug(string.format("Engine cooled on %s - can restart", vehicle:getName()))
            end
        end
    end
end

--[[
    v1.6.0: Check for implement malfunctions
    Handles surge (random lift), drop (sudden lower), PTO toggle, and hitch failure
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.checkImplementMalfunctions(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    local electricalReliability = spec.electricalReliability or 1.0

    -- Get attached implements
    if not vehicle.getAttachedImplements then return end
    local implements = vehicle:getAttachedImplements()
    if implements == nil or #implements == 0 then return end

    -- Process each implement
    for _, implement in pairs(implements) do
        local attachedVehicle = implement.object
        if attachedVehicle then
            -- Implement Surge (random lift) - hydraulic pressure spike
            if config.enableImplementSurge and hydraulicReliability < config.implementSurgeThreshold then
                UsedPlusMaintenance.checkImplementSurge(vehicle, attachedVehicle, hydraulicReliability)
            end

            -- Implement Drop (sudden lower) - hydraulic valve failure
            if config.enableImplementDrop and hydraulicReliability < config.implementDropThreshold then
                UsedPlusMaintenance.checkImplementDrop(vehicle, attachedVehicle, hydraulicReliability)
            end

            -- PTO Toggle - electrical relay failure
            if config.enablePTOToggle and electricalReliability < config.ptoToggleThreshold then
                UsedPlusMaintenance.checkPTOToggle(vehicle, attachedVehicle, electricalReliability)
            end

            -- Hitch Failure - implement detaches (VERY RARE)
            if config.enableHitchFailure and hydraulicReliability < config.hitchFailureThreshold then
                UsedPlusMaintenance.checkHitchFailure(vehicle, implement, hydraulicReliability)
            end
        end
    end
end

--[[
    v1.6.0: Check for implement surge (random lift)
    Simulates hydraulic pressure spike lifting a lowered implement
]]
function UsedPlusMaintenance.checkImplementSurge(vehicle, implement, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects lowered implements
    if not implement.getIsLowered or not implement:getIsLowered() then
        return
    end

    -- Calculate surge chance based on reliability
    local reliabilityFactor = (config.implementSurgeThreshold - hydraulicReliability) / config.implementSurgeThreshold
    local surgeChance = reliabilityFactor * config.implementSurgeChance

    if math.random() < surgeChance then
        -- Surge! Lift the implement
        if implement.setLoweredAll then
            implement:setLoweredAll(false)

            if not spec.hasShownSurgeWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_implementSurge") or "Hydraulic surge - implement raised!",
                    3000
                )
                spec.hasShownSurgeWarning = true
            end

            UsedPlus.logDebug(string.format("Implement surge on %s - %s raised",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    v1.6.0: Check for implement drop (sudden lower)
    Simulates hydraulic valve failure dropping a raised implement
]]
function UsedPlusMaintenance.checkImplementDrop(vehicle, implement, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects raised implements
    if not implement.getIsLowered or implement:getIsLowered() then
        return
    end

    -- Calculate drop chance based on reliability
    local reliabilityFactor = (config.implementDropThreshold - hydraulicReliability) / config.implementDropThreshold
    local dropChance = reliabilityFactor * config.implementDropChance

    if math.random() < dropChance then
        -- Drop! Lower the implement suddenly
        if implement.setLoweredAll then
            implement:setLoweredAll(true)
            spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as breakdown

            -- v1.7.0: Hydraulic failure while fluid is low = permanent damage
            UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)

            if not spec.hasShownDropWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_implementDrop") or "Hydraulic failure - implement dropped!",
                    3000
                )
                spec.hasShownDropWarning = true
            end

            UsedPlus.logDebug(string.format("Implement drop on %s - %s lowered",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    v1.6.0: Check for PTO toggle (power randomly on/off)
    Simulates electrical relay failure toggling implement power
]]
function UsedPlusMaintenance.checkPTOToggle(vehicle, implement, electricalReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects implements that can be turned on/off
    if not implement.getIsTurnedOn then
        return
    end

    -- Calculate toggle chance based on reliability
    local reliabilityFactor = (config.ptoToggleThreshold - electricalReliability) / config.ptoToggleThreshold
    local toggleChance = reliabilityFactor * config.ptoToggleChance

    if math.random() < toggleChance then
        -- Toggle! Switch power state
        local isOn = implement:getIsTurnedOn()
        if implement.setIsTurnedOn then
            implement:setIsTurnedOn(not isOn)

            if not spec.hasShownPTOWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                local stateText = isOn and
                    (g_i18n:getText("usedPlus_ptoOff") or "off") or
                    (g_i18n:getText("usedPlus_ptoOn") or "on")
                g_currentMission:showBlinkingWarning(
                    string.format(g_i18n:getText("usedPlus_ptoToggle") or "Electrical fault - PTO switched %s!", stateText),
                    3000
                )
                spec.hasShownPTOWarning = true
            end

            UsedPlus.logDebug(string.format("PTO toggle on %s - %s turned %s",
                vehicle:getName(), implement:getName(), isOn and "off" or "on"))
        end
    end
end

--[[
    v1.6.0: Check for hitch failure (implement detaches)
    VERY RARE - only at critical hydraulic reliability
    Simulates complete hydraulic hitch failure
]]
function UsedPlusMaintenance.checkHitchFailure(vehicle, implementInfo, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    local implement = implementInfo.object
    if implement == nil then return end

    -- Calculate failure chance (very low)
    local reliabilityFactor = (config.hitchFailureThreshold - hydraulicReliability) / config.hitchFailureThreshold
    local failureChance = reliabilityFactor * config.hitchFailureChance

    if math.random() < failureChance then
        -- Hitch failure! Detach the implement
        local jointDescIndex = implementInfo.jointDescIndex

        -- Try to detach using the vehicle's method
        if vehicle.detachImplementByObject then
            vehicle:detachImplementByObject(implement)
            spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as major breakdown

            -- v1.7.0: Hitch failure while fluid is low = permanent damage
            UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)

            if not spec.hasShownHitchWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_hitchFailure") or "HITCH FAILURE - Implement detached!",
                    5000
                )
                spec.hasShownHitchWarning = true
            end

            UsedPlus.logDebug(string.format("Hitch failure on %s - %s detached!",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    Calculate failure probability based on damage, reliability, hours, and load
    Returns probability per second (0.0-1.0)

    BALANCE NOTE (v1.2): Completely rewritten so reliability matters even at 0% damage.
    Old system: damage < 20% = no failures (reliability was meaningless after repair)
    New system: Low reliability = baseline failure chance, damage amplifies it

    A vehicle with 50% engine reliability will have ~5x the failure rate of a 100% one.
    Damage now AMPLIFIES failure rate rather than gating it entirely.

    v1.8.0: Added optional reliabilityOverride parameter for ModCompatibility integration
    When RVB is installed, callers pass in reliability derived from RVB part health

    @param vehicle - The vehicle to check
    @param failureType - "engine", "hydraulic", or "electrical"
    @param reliabilityOverride - Optional: use this reliability instead of spec value
]]
function UsedPlusMaintenance.calculateFailureProbability(vehicle, failureType, reliabilityOverride)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 0 end

    -- Get current damage
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- Get operating hours
    local hours = 0
    if vehicle.getOperatingTime then
        hours = (vehicle:getOperatingTime() or 0) / 3600000  -- Convert ms to hours
    end

    -- Get engine load (0-1)
    local load = 0
    if vehicle.getMotorLoadPercentage then
        load = vehicle:getMotorLoadPercentage() or 0
    end

    -- v1.8.0: Use override if provided (from ModCompatibility)
    -- Otherwise fall back to spec values
    local reliability = reliabilityOverride
    if reliability == nil then
        if failureType == "engine" then
            reliability = spec.engineReliability or 1.0
        elseif failureType == "hydraulic" then
            reliability = spec.hydraulicReliability or 1.0
        elseif failureType == "electrical" then
            reliability = spec.electricalReliability or 1.0
        else
            reliability = 1.0
        end
    end

    -- v1.5.1 REBALANCED: Low reliability = MUCH higher failure rates
    -- Previous formula was too gentle - 10% reliability only had 0.017% stall chance per second
    -- New formula makes low reliability vehicles ACTUALLY struggle

    -- 1. BASE CHANCE FROM RELIABILITY (dramatically increased!)
    -- 100% reliability = virtually no failures (0.001% per second)
    -- 50% reliability = occasional failures (0.1% per second = ~6% per minute)
    -- 10% reliability = frequent failures (0.5% per second = ~25% per minute)
    -- 0% reliability = constant failures (0.8% per second = ~40% per minute)
    local reliabilityFactor = math.pow(1 - reliability, 1.5)  -- Less aggressive curve, but higher base
    local baseChance = 0.00001 + (reliabilityFactor * 0.008)  -- 0.001% to 0.8% per second

    -- 2. DAMAGE MULTIPLIER (amplifies base chance, doesn't gate it)
    -- 0% damage = 1x multiplier (no change)
    -- 50% damage = 2x multiplier
    -- 100% damage = 3x multiplier
    local damageMultiplier = 1.0 + (damage * 2.0)

    -- 3. HOURS CONTRIBUTION (high hours = slightly more prone to issues)
    -- Caps at +50% after 10,000 hours
    local hoursMultiplier = 1.0 + math.min(hours / 20000, 0.5)

    -- 4. LOAD CONTRIBUTION (high load with low reliability = very risky)
    -- This is significant when EITHER load OR reliability is extreme
    local loadMultiplier = 1.0 + (load * (1 - reliability) * 3.0)

    -- Combined probability
    local probability = baseChance * damageMultiplier * hoursMultiplier * loadMultiplier
    probability = probability * UsedPlusMaintenance.CONFIG.failureRateMultiplier

    -- Cap at 5% per second max (allows for truly terrible engines)
    return math.min(probability, 0.05)
end

--[[
    Check for engine stall
    Stalling more likely with high damage + low reliability + high load

    v1.8.0: "Symptoms Before Failure" integration
    Our stalls are TEMPORARY (engine dies but restarts after cooldown)
    RVB's ENGINE FAULT is PERMANENT (7km/h cap until repaired)
    We provide the "symptoms", RVB provides the "failure"
    So we KEEP our stalls active even when RVB is installed!
]]
function UsedPlusMaintenance.checkEngineStall(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Cooldown check (prevent stalling every frame)
    if spec.stallCooldown > 0 then
        return
    end

    -- Only check running engines
    if vehicle.getIsMotorStarted and not vehicle:getIsMotorStarted() then
        return
    end

    -- v1.8.0: Use ModCompatibility to get engine reliability
    -- If RVB installed, this provides "symptom stalls" based on RVB part health
    local engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Calculate stall probability using the compatibility-aware reliability
    local stallChance = UsedPlusMaintenance.calculateFailureProbability(vehicle, "engine", engineReliability)

    if math.random() < stallChance then
        -- STALL! (temporary - player can restart after cooldown)
        UsedPlusMaintenance.triggerEngineStall(vehicle)
    end
end

--[[
    Actually perform the engine stall
    Stops the motor and notifies the player
    @param vehicle - The vehicle to stall
    @param isFirstStart - Optional: true if this is a first-start stall (different message)
]]
function UsedPlusMaintenance.triggerEngineStall(vehicle, isFirstStart)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Stop the motor
    if vehicle.stopMotor then
        vehicle:stopMotor()
    end

    spec.isStalled = true
    spec.stallCooldown = UsedPlusMaintenance.CONFIG.stallCooldownMs
    spec.failureCount = (spec.failureCount or 0) + 1

    -- v1.7.0: Check for permanent damage from low fluids
    -- Engine stall while oil is critically low = permanent engine damage
    UsedPlusMaintenance.applyOilDamageOnFailure(vehicle)

    -- v1.5.1: Set recovery period - engine cannot restart for X seconds
    -- This defeats auto-start and forces the player to actually stop
    local currentTime = g_currentMission.time or 0
    local recoveryDuration = UsedPlusMaintenance.CONFIG.stallRecoveryDurationMs
    spec.stallRecoveryEndTime = currentTime + recoveryDuration

    -- Show warning to player (include recovery time)
    local recoverySeconds = math.ceil(recoveryDuration / 1000)
    local message
    if isFirstStart then
        -- First-start stall - different message
        message = g_i18n:getText("usedPlus_firstStartStall")
        if message == "usedPlus_firstStartStall" then
            message = "Engine failed to start! Wait %d seconds..."
        else
            message = message .. " Wait %d seconds..."
        end
    else
        -- Normal stall during operation
        message = g_i18n:getText("usedPlus_engineStalledRecovery")
        if message == "usedPlus_engineStalledRecovery" then
            message = "Engine stalled! Wait %d seconds..."
        end
    end
    -- v1.7.2: Show warning - first-start stalls ALWAYS show (intentional feedback)
    -- Normal stalls respect shouldShowWarning (checks grace period, control state)
    local shouldShow = isFirstStart or UsedPlusMaintenance.shouldShowWarning(vehicle)
    if shouldShow then
        g_currentMission:showBlinkingWarning(
            string.format(message, recoverySeconds),
            recoveryDuration
        )
        UsedPlus.logDebug("Stall warning shown to player")
    else
        UsedPlus.logDebug("Stall warning suppressed (not controlling or grace period)")
    end

    -- Stop AI worker if active
    local rootVehicle = vehicle:getRootVehicle()
    if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
        if rootVehicle.stopCurrentAIJob then
            -- Try to create error message
            local errorMessage = nil
            if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                errorMessage = AIMessageErrorVehicleBroken.new()
            end
            rootVehicle:stopCurrentAIJob(errorMessage)
        end
    end

    UsedPlus.logDebug(string.format("Engine stalled on %s (failures: %d, firstStart: %s)",
        vehicle:getName(), spec.failureCount, tostring(isFirstStart or false)))
end

--[[
    v1.5.1: Called when player enters a vehicle
    Used to check for "first-start" stall on poor reliability vehicles
    This simulates an engine that has trouble starting

    v1.8.0: Uses ModCompatibility to get engine reliability
    Works with both native UsedPlus and RVB-derived health
    This is a "symptom" that RVB doesn't have - hard starting!
]]
function UsedPlusMaintenance:onEnterVehicle(isControlling)
    if not isControlling then return end  -- Only process for controlling player
    if not self.isServer then return end  -- Only on server

    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- v1.8.0: Use ModCompatibility to get engine reliability
    -- If RVB installed, this is derived from RVB part health
    -- This provides "first-start stalling" symptom that RVB doesn't have!
    local engineReliability = ModCompatibility.getEngineReliability(self)

    -- Only check on poor reliability vehicles
    if engineReliability >= 0.5 then
        return  -- Good enough reliability, no first-start issues
    end

    -- Don't double-stall if we're already in recovery
    if spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0 then
        return
    end

    -- Calculate first-start stall chance based on reliability
    -- 50% reliability = 0% chance
    -- 25% reliability = 50% chance
    -- 10% reliability = 80% chance
    -- 0% reliability = 100% chance
    local stallChance = (0.5 - engineReliability) * 2.0
    stallChance = math.max(0, math.min(stallChance, 1.0))

    -- Roll for first-start stall
    if math.random() < stallChance then
        -- Stall immediately after short delay (feels like "almost started then died")
        -- Use a timer so it happens after the vehicle fully loads
        spec.firstStartStallPending = true
        spec.firstStartStallTimer = 500  -- 500ms delay

        UsedPlus.logDebug(string.format("First-start stall scheduled for %s (reliability: %d%%, source: %s)",
            self:getName(), math.floor(engineReliability * 100),
            ModCompatibility.rvbInstalled and "RVB" or "UsedPlus"))
    end
end

--[[
    Calculate speed limit factor based on engine reliability and damage
    This is called periodically (every 1 second) to update spec.maxSpeedFactor
    The actual speed enforcement happens in getCanMotorRun() every frame via the governor

    v1.5.1 FIX: Low reliability NOW reduces speed even when damage is 0!
    v1.5.1: Renamed from updateSpeedLimit, actual enforcement moved to governor
]]
function UsedPlusMaintenance.calculateSpeedLimit(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Get current damage
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- v1.8.0: Use ModCompatibility to get engine reliability
    -- If RVB is installed, this returns health derived from RVB parts
    -- Otherwise, returns our native engineReliability
    -- This enables "symptoms before failure" - we provide gradual degradation
    -- leading up to RVB's final failure event
    local engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Calculate speed factor from RELIABILITY (applies even at 0% damage!)
    -- 100% reliability = 100% speed
    -- 50% reliability = 70% speed
    -- 10% reliability = 46% speed
    -- 0% reliability = 40% speed (absolute minimum before RVB's 7km/h kicks in)
    local reliabilitySpeedFactor = 0.4 + (engineReliability * 0.6)

    -- Damage ALSO reduces speed (stacks with reliability)
    local maxReduction = config.speedDegradationMax
    local damageSpeedFactor = 1 - (damage * maxReduction)

    -- v1.7.0: Flat tire severely limits speed
    -- v1.8.0: Skip flat tire logic if UYT/RVB handles tires
    local flatTireSpeedFactor = 1.0
    if spec.hasFlatTire and config.enableFlatTire and not ModCompatibility.shouldDeferTireFailure() then
        flatTireSpeedFactor = config.flatTireSpeedReduction  -- 0.5 = 50% max speed
    end

    -- Combined factor (multiplicative stacking)
    local finalFactor = reliabilitySpeedFactor * damageSpeedFactor * flatTireSpeedFactor
    finalFactor = math.max(finalFactor, 0.2)  -- Never below 20% speed (even with flat)

    -- Store for use by getCanMotorRun speed governor
    spec.maxSpeedFactor = finalFactor

    -- Calculate actual limited speed for display/warnings
    local baseMaxSpeed = 50
    if vehicle.spec_drivable and vehicle.spec_drivable.cruiseControl then
        baseMaxSpeed = vehicle.spec_drivable.cruiseControl.maxSpeed or 50
    end
    spec.currentMaxSpeed = baseMaxSpeed * finalFactor

    -- Only show warnings if there's actual degradation (below 95%)
    if finalFactor >= 0.95 then
        spec.hasShownSpeedWarning = false
        spec.speedWarningTimer = 0
        return
    end

    -- Show warning when speed degradation is first noticed
    -- v1.6.0: Only show if player is controlling this vehicle
    if not spec.hasShownSpeedWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
        local speedPercent = math.floor(finalFactor * 100)
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedPlus_speedDegraded") or "Engine struggling - max speed reduced to %d%%!", speedPercent),
            4000
        )
        spec.hasShownSpeedWarning = true
        spec.speedWarningTimer = 0
        UsedPlus.logDebug(string.format("Speed degradation: %d%% (max %d km/h)", speedPercent, math.floor(spec.currentMaxSpeed)))
    end
end

--[[
    v1.5.1: Placeholder for per-frame speed enforcement (not needed with governor approach)
    The actual enforcement now happens in getCanMotorRun() which is called every frame
]]
function UsedPlusMaintenance.enforceSpeedLimit(vehicle, dt)
    -- Speed enforcement is now handled by the governor in getCanMotorRun()
    -- This function exists for future enhancements (e.g., HUD display updates)
end

--[[
    v1.5.1: Apply steering degradation for worn feel
    Poor hydraulic reliability causes loose, sloppy steering response
    Makes the vehicle feel "old" and worn
]]
function UsedPlusMaintenance.applySteeringDegradation(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Only apply steering degradation if hydraulic reliability is low
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    if hydraulicReliability >= 0.8 then
        return  -- Steering fine above 80% reliability
    end

    -- Calculate steering "slop" factor (0 = perfect, 1 = very loose)
    -- At 80% reliability: 0% slop
    -- At 50% reliability: 37.5% slop
    -- At 10% reliability: 87.5% slop
    local slopFactor = (0.8 - hydraulicReliability) / 0.8
    slopFactor = math.min(slopFactor, 0.9)  -- Max 90% slop

    -- Add random steering "wander" based on slop
    -- This creates the feeling of loose steering that doesn't hold straight
    if vehicle.spec_drivable and vehicle.spec_drivable.steeringAngle then
        -- Only apply wander when moving
        local speed = 0
        if vehicle.getLastSpeed then
            speed = vehicle:getLastSpeed()
        end

        if speed > 5 then  -- Only above 5 km/h
            -- Random micro-adjustments to steering
            local wanderAmount = slopFactor * 0.002 * (math.random() - 0.5)

            -- Apply steering wander (very subtle)
            spec.steeringWander = (spec.steeringWander or 0) + wanderAmount
            spec.steeringWander = spec.steeringWander * 0.95  -- Decay

            -- Clamp wander
            spec.steeringWander = math.max(-0.03, math.min(0.03, spec.steeringWander))
        else
            spec.steeringWander = 0
        end
    end
end

--[[
    Check for hydraulic drift on attached implements
    Poor hydraulic reliability causes raised implements to slowly lower
    Phase 5 feature
    v1.4.0: Added visual warnings so players understand why implements are lowering
]]
function UsedPlusMaintenance.checkHydraulicDrift(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- v1.8.0: Use ModCompatibility to get hydraulic reliability
    -- Note: RVB doesn't have hydraulic parts, so this will use native UsedPlus reliability
    -- This is a UNIQUE UsedPlus feature that complements RVB!
    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)

    -- Only drift if hydraulic reliability is below threshold
    -- BALANCE NOTE (v1.2): Removed damage gate - low reliability causes drift even when repaired
    if hydraulicReliability >= UsedPlusMaintenance.CONFIG.hydraulicDriftThreshold then
        -- Reset warning flags when hydraulics are healthy (so warnings trigger again if they degrade)
        spec.hasShownDriftWarning = false
        spec.hasShownDriftMidpointWarning = false
        return
    end

    -- v1.4.0: Show one-time warning when drift conditions are first detected
    -- v1.6.0: Only show if player is controlling this vehicle
    if not spec.hasShownDriftWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
        local reliabilityPercent = math.floor(hydraulicReliability * 100)
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedPlus_hydraulicWeak") or "Hydraulics weak (%d%%) - implements may drift!", reliabilityPercent),
            4000
        )
        spec.hasShownDriftWarning = true
        UsedPlus.logDebug(string.format("Hydraulic drift warning shown: %d%% reliability", reliabilityPercent))
    end

    -- Get current damage - amplifies drift speed but doesn't gate it
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- Calculate drift speed based on reliability (lower = faster drift)
    -- Damage amplifies drift speed (up to 3x at 100% damage)
    local baseSpeed = UsedPlusMaintenance.CONFIG.hydraulicDriftSpeed
    local reliabilityFactor = 1 - hydraulicReliability  -- 0.5 reliability = 0.5 factor
    local damageMultiplier = 1.0 + (damage * 2.0)  -- 0% damage = 1x, 100% = 3x
    local driftSpeed = baseSpeed * reliabilityFactor * damageMultiplier * (dt / 1000)  -- Convert to per-second

    -- Check all child vehicles (attached implements)
    local childVehicles = vehicle:getChildVehicles()
    if childVehicles then
        for _, childVehicle in pairs(childVehicles) do
            -- Pass parent spec so child can trigger midpoint warning
            UsedPlusMaintenance.applyHydraulicDriftToVehicle(childVehicle, driftSpeed, dt, spec)
        end
    end
end

--[[
    Apply hydraulic drift to a single vehicle's cylindered tools
    @param vehicle - The implement vehicle to check
    @param driftSpeed - How fast to drift (radians per second)
    @param dt - Delta time in milliseconds
    @param parentSpec - The parent vehicle's UsedPlusMaintenance spec (for warning flags)
]]
function UsedPlusMaintenance.applyHydraulicDriftToVehicle(vehicle, driftSpeed, dt, parentSpec)
    if vehicle.spec_cylindered == nil then return end

    local spec = vehicle.spec_cylindered
    local movingTools = spec.movingTools

    if movingTools == nil then return end

    for i, tool in pairs(movingTools) do
        -- Only process if tool is NOT actively being moved by player
        if tool.move == 0 and tool.node and tool.rotationAxis then
            local curRot = {getRotation(tool.node)}
            local currentAngle = curRot[tool.rotationAxis] or 0

            -- Check if tool is raised (near max rotation)
            local maxRot = tool.rotMax or 0
            local minRot = tool.rotMin or 0

            -- Only drift if above 50% of range (considered "raised")
            local range = maxRot - minRot
            local midpoint = minRot + (range * 0.5)

            if currentAngle > midpoint then
                -- Apply drift toward minimum (lowering)
                local newAngle = currentAngle - driftSpeed

                -- Don't go below midpoint
                if newAngle > midpoint then
                    curRot[tool.rotationAxis] = newAngle
                    setRotation(tool.node, curRot[1], curRot[2], curRot[3])

                    -- Mark dirty for network sync
                    if Cylindered and Cylindered.setDirty then
                        Cylindered.setDirty(vehicle, tool)
                    end

                    -- Only log occasionally to avoid spam
                    if math.random() < 0.01 then
                        UsedPlus.logTrace("Hydraulic drift active on implement")
                    end
                else
                    -- v1.4.0: Implement just reached midpoint (fully drifted down)
                    -- Show warning once per session when this happens
                    if parentSpec and not parentSpec.hasShownDriftMidpointWarning then
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            g_i18n:getText("usedPlus_hydraulicDrifted") or "Implement lowered due to hydraulic failure"
                        )
                        parentSpec.hasShownDriftMidpointWarning = true
                        UsedPlus.logDebug("Hydraulic drift midpoint warning shown - implement fully lowered")
                    end
                end
            end
        end
    end
end

--[[
    Check for electrical cutout on attached implements
    Poor electrical reliability causes random implement shutoffs
    Phase 5 feature
]]
function UsedPlusMaintenance.checkImplementCutout(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Handle active cutout
    if spec.isCutout then
        if g_currentMission.time >= spec.cutoutEndTime then
            -- Cutout ended, restore power
            spec.isCutout = false
            UsedPlus.logDebug("Electrical cutout ended - implements restored")
        end
        return  -- Don't check for new cutout while one is active
    end

    -- Update cutout check timer
    spec.cutoutTimer = (spec.cutoutTimer or 0) + dt
    if spec.cutoutTimer < UsedPlusMaintenance.CONFIG.cutoutCheckIntervalMs then
        return
    end
    spec.cutoutTimer = 0

    -- BALANCE NOTE (v1.2): Removed damage gate - low reliability causes cutouts even when repaired
    -- Get current damage (amplifies chance but doesn't gate it)
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- v1.5.1 REBALANCED: Calculate cutout probability based on electrical reliability
    -- Previous formula was too gentle - 42% reliability rarely caused cutouts
    -- New formula: Low reliability = significant base chance, damage amplifies
    local baseChance = UsedPlusMaintenance.CONFIG.cutoutBaseChance  -- 3% base
    local electricalReliability = spec.electricalReliability or 1.0

    -- 100% reliability = 0% factor (no cutouts)
    -- 50% reliability = 25% factor
    -- 10% reliability = 81% factor
    local reliabilityFactor = math.pow(1 - electricalReliability, 1.5)  -- Less harsh curve but still significant

    -- Damage amplifies (0% damage = 1x, 100% = 3x)
    local damageMultiplier = 1.0 + (damage * 2.0)

    -- Combined: at 42% reliability, 0% damage = 3% * 0.44 * 1.0 = 1.3% per 5 sec = ~15% per minute
    -- At 10% reliability, 0% damage = 3% * 0.73 * 1.0 = 2.2% per 5 sec = ~24% per minute
    local cutoutChance = baseChance * reliabilityFactor * damageMultiplier * UsedPlusMaintenance.CONFIG.failureRateMultiplier

    if math.random() < cutoutChance then
        -- CUTOUT!
        UsedPlusMaintenance.triggerImplementCutout(vehicle)
    end
end

--[[
    Trigger an electrical cutout - implements stop working temporarily
]]
function UsedPlusMaintenance.triggerImplementCutout(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.isCutout = true
    spec.cutoutEndTime = g_currentMission.time + UsedPlusMaintenance.CONFIG.cutoutDurationMs
    spec.failureCount = (spec.failureCount or 0) + 1

    -- Try to raise/stop implements
    if vehicle.getAttachedAIImplements then
        local implements = vehicle:getAttachedAIImplements()
        if implements then
            for _, implement in pairs(implements) do
                if implement.object and implement.object.aiImplementEndLine then
                    implement.object:aiImplementEndLine()
                end
            end
        end
    end

    -- Also try direct child vehicles
    local childVehicles = vehicle:getChildVehicles()
    if childVehicles then
        for _, childVehicle in pairs(childVehicles) do
            if childVehicle.aiImplementEndLine then
                childVehicle:aiImplementEndLine()
            end
            -- Turn off PTO if possible
            if childVehicle.setIsTurnedOn then
                childVehicle:setIsTurnedOn(false)
            end
        end
    end

    -- Show warning to player
    -- v1.6.0: Only show if player is controlling this vehicle
    if UsedPlusMaintenance.shouldShowWarning(vehicle) then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedPlus_electricalCutout") or "Electrical fault - implements offline!",
            3000
        )
    end

    -- Stop AI worker if active
    local rootVehicle = vehicle:getRootVehicle()
    if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
        if rootVehicle.stopCurrentAIJob then
            local errorMessage = nil
            if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                errorMessage = AIMessageErrorVehicleBroken.new()
            end
            rootVehicle:stopCurrentAIJob(errorMessage)
        end
    end

    UsedPlus.logDebug(string.format("Electrical cutout on %s (failures: %d)", vehicle:getName(), spec.failureCount))
end

--[[
    PUBLIC API: Set maintenance data when purchasing a used vehicle
    Called from UsedVehicleManager when purchase completes

    v1.4.0: Now transfers workhorseLemonScale and maxReliabilityCeiling
]]
function UsedPlusMaintenance.setUsedPurchaseData(vehicle, usedPlusData)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logWarn("Cannot set used purchase data - spec not found")
        return false
    end

    -- Mark as purchased used
    spec.purchasedUsed = true
    spec.purchaseDate = g_currentMission.environment.dayTime or 0
    spec.purchasePrice = usedPlusData.price or 0
    spec.purchaseDamage = usedPlusData.damage or 0
    spec.purchaseHours = usedPlusData.operatingHours or 0
    spec.wasInspected = usedPlusData.wasInspected or false

    -- Transfer hidden reliability scores
    spec.engineReliability = usedPlusData.engineReliability or 1.0
    spec.hydraulicReliability = usedPlusData.hydraulicReliability or 1.0
    spec.electricalReliability = usedPlusData.electricalReliability or 1.0

    -- v1.6.0: Reset grace period - prevents warnings immediately after purchase
    spec.startupGracePeriod = 2000

    -- v1.4.0: Transfer Workhorse/Lemon Scale data
    spec.workhorseLemonScale = usedPlusData.workhorseLemonScale or 0.5
    spec.maxReliabilityCeiling = usedPlusData.maxReliabilityCeiling or 1.0

    -- v1.7.0: Transfer tire data
    spec.tireCondition = usedPlusData.tireCondition or 1.0
    spec.tireQuality = usedPlusData.tireQuality or 2

    -- Apply tire quality modifiers
    local config = UsedPlusMaintenance.CONFIG
    if spec.tireQuality == 1 then  -- Retread
        spec.tireMaxTraction = config.tireRetreadTractionMult
        spec.tireFailureMultiplier = config.tireRetreadFailureMult
    elseif spec.tireQuality == 3 then  -- Quality
        spec.tireMaxTraction = config.tireQualityTractionMult
        spec.tireFailureMultiplier = config.tireQualityFailureMult
    else  -- Normal (2)
        spec.tireMaxTraction = config.tireNormalTractionMult
        spec.tireFailureMultiplier = config.tireNormalFailureMult
    end

    -- v1.7.0: Transfer fluid data
    spec.oilLevel = usedPlusData.oilLevel or 1.0
    spec.hydraulicFluidLevel = usedPlusData.hydraulicFluidLevel or 1.0

    -- v1.7.0: Initialize reliability ceilings (separate from DNA ceiling)
    spec.engineReliabilityCeiling = spec.maxReliabilityCeiling
    spec.hydraulicReliabilityCeiling = spec.maxReliabilityCeiling

    -- Initialize maintenance history
    spec.repairCount = 0
    spec.totalRepairCost = 0
    spec.failureCount = 0

    UsedPlus.logDebug(string.format("Set used purchase data for %s: DNA=%.2f, ceiling=%.1f%%, engine=%.2f, tires=%.0f%%, oil=%.0f%%",
        vehicle:getName(), spec.workhorseLemonScale, spec.maxReliabilityCeiling * 100,
        spec.engineReliability, spec.tireCondition * 100, spec.oilLevel * 100))

    return true
end

--[[
    PUBLIC API: Get current reliability data for a vehicle
    Used for inspection reports and vehicle info display

    v1.4.0: Now includes workhorseLemonScale and maxReliabilityCeiling
]]
function UsedPlusMaintenance.getReliabilityData(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return nil
    end

    -- Calculate average reliability
    local avgReliability = (spec.engineReliability + spec.hydraulicReliability + spec.electricalReliability) / 3

    -- v1.4.0: Calculate resale modifier based on average reliability
    -- Formula: 0.7 + (avgReliability * 0.3) => Range: 0.7 to 1.0
    -- A 50% reliable vehicle sells for 85% of normal value
    -- A 90% reliable vehicle sells for 97% of normal value
    local resaleModifier = 0.7 + (avgReliability * 0.3)

    -- v1.7.0: Get tire quality name
    local tireQualityName = "Normal"
    if spec.tireQuality == 1 then
        tireQualityName = "Retread"
    elseif spec.tireQuality == 3 then
        tireQualityName = "Quality"
    end

    return {
        purchasedUsed = spec.purchasedUsed,
        wasInspected = spec.wasInspected,
        engineReliability = spec.engineReliability,
        hydraulicReliability = spec.hydraulicReliability,
        electricalReliability = spec.electricalReliability,
        workhorseLemonScale = spec.workhorseLemonScale,
        maxReliabilityCeiling = spec.maxReliabilityCeiling,
        repairCount = spec.repairCount,
        totalRepairCost = spec.totalRepairCost,
        failureCount = spec.failureCount,
        avgReliability = avgReliability,
        resaleModifier = resaleModifier,  -- v1.4.0: Reliability affects resale value

        -- v1.7.0: Tire data
        tireCondition = spec.tireCondition,
        tireQuality = spec.tireQuality,
        tireQualityName = tireQualityName,
        tireMaxTraction = spec.tireMaxTraction,
        hasFlatTire = spec.hasFlatTire,

        -- v1.7.0: Fluid data
        oilLevel = spec.oilLevel,
        hasOilLeak = spec.hasOilLeak,
        oilLeakSeverity = spec.oilLeakSeverity,
        engineReliabilityCeiling = spec.engineReliabilityCeiling,

        hydraulicFluidLevel = spec.hydraulicFluidLevel,
        hasHydraulicLeak = spec.hasHydraulicLeak,
        hydraulicLeakSeverity = spec.hydraulicLeakSeverity,
        hydraulicReliabilityCeiling = spec.hydraulicReliabilityCeiling,

        -- v1.7.0: Fuel leak data
        hasFuelLeak = spec.hasFuelLeak,
        fuelLeakMultiplier = spec.fuelLeakMultiplier
    }
end

--[[
    PUBLIC API: Update reliability after repair
    Called from VehicleSellingPointExtension when repair completes

    v1.4.0: Now implements Workhorse/Lemon Scale system
    - Each repair degrades the reliability CEILING based on vehicle DNA
    - Lemons (0.0) lose 1% ceiling per repair
    - Workhorses (1.0) lose 0% ceiling per repair
    - Reliability scores are capped by the current ceiling, not a fixed 95%
]]
function UsedPlusMaintenance.onVehicleRepaired(vehicle, repairCost)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Update maintenance history
    spec.repairCount = spec.repairCount + 1
    spec.totalRepairCost = spec.totalRepairCost + repairCost
    spec.lastRepairDate = g_currentMission.environment.dayTime or 0

    -- v1.4.0: Calculate ceiling degradation based on vehicle DNA
    if UsedPlusMaintenance.CONFIG.enableLemonScale then
        -- Lemon (0.0) = 1% degradation per repair, Workhorse (1.0) = 0% degradation
        local degradationRate = (1 - (spec.workhorseLemonScale or 0.5)) *
            UsedPlusMaintenance.CONFIG.ceilingDegradationMax

        -- Reduce the ceiling
        spec.maxReliabilityCeiling = (spec.maxReliabilityCeiling or 1.0) - degradationRate

        -- Ensure minimum ceiling (vehicle is never completely unrepairable)
        spec.maxReliabilityCeiling = math.max(
            UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
            spec.maxReliabilityCeiling
        )

        UsedPlus.logDebug(string.format("Ceiling degraded: DNA=%.2f, degradation=%.3f%%, newCeiling=%.1f%%",
            spec.workhorseLemonScale or 0.5, degradationRate * 100, spec.maxReliabilityCeiling * 100))
    end

    -- Apply repair bonus, capped by CURRENT ceiling (not fixed 95%)
    local repairBonus = UsedPlusMaintenance.CONFIG.reliabilityRepairBonus
    local ceiling = spec.maxReliabilityCeiling or UsedPlusMaintenance.CONFIG.maxReliabilityAfterRepair

    spec.engineReliability = math.min(ceiling, spec.engineReliability + repairBonus)
    spec.hydraulicReliability = math.min(ceiling, spec.hydraulicReliability + repairBonus)
    spec.electricalReliability = math.min(ceiling, spec.electricalReliability + repairBonus)

    -- v1.4.0: Reset warning flags so they can trigger again if problems return
    -- Speed degradation warnings reset when damage drops below threshold (automatic)
    -- But hydraulic warnings need manual reset since reliability might still be low
    spec.hasShownDriftWarning = false
    spec.hasShownDriftMidpointWarning = false
    -- Speed warning will auto-reset when damage < threshold, but reset timer
    spec.speedWarningTimer = 0

    UsedPlus.logDebug(string.format("Vehicle repaired: %s - ceiling=%.1f%%, engine=%.2f, hydraulic=%.2f, electrical=%.2f",
        vehicle:getName(), ceiling * 100, spec.engineReliability, spec.hydraulicReliability, spec.electricalReliability))
end

--[[
    PUBLIC API: Generate random reliability scores for a used vehicle listing
    Called from UsedVehicleManager when generating sale items

    v1.4.0: Now includes workhorseLemonScale and calculates initial ceiling
    based on estimated previous repairs from age/hours

    @param damage - Vehicle damage level (0-1)
    @param age - Vehicle age in years
    @param hours - Operating hours
    @param qualityLevel - Optional quality tier (1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent)
                          Affects DNA distribution - higher tiers bias toward workhorses
]]
function UsedPlusMaintenance.generateReliabilityScores(damage, age, hours, qualityLevel)
    -- Base reliability inversely related to damage
    local reliabilityBase = 1 - (damage or 0)

    -- Add variance - a high-damage vehicle MIGHT have good engine, or might not
    local function randomVariance(maxVariance)
        return (math.random() * 2 - 1) * maxVariance
    end

    local engineReliability = reliabilityBase + randomVariance(0.2)
    local hydraulicReliability = reliabilityBase + randomVariance(0.25)
    local electricalReliability = reliabilityBase + randomVariance(0.15)

    -- Clamp to 0.1-1.0 (never completely dead, never perfect if used)
    engineReliability = math.max(0.1, math.min(1.0, engineReliability))
    hydraulicReliability = math.max(0.1, math.min(1.0, hydraulicReliability))
    electricalReliability = math.max(0.1, math.min(1.0, electricalReliability))

    -- v1.4.0: Generate workhorse/lemon scale (DNA correlated with quality tier)
    local workhorseLemonScale = UsedPlusMaintenance.generateUsedVehicleScale(qualityLevel)

    -- v1.4.0: Estimate previous repairs from age/hours and calculate initial ceiling
    local estimatedRepairs = math.floor((hours or 0) / 500)  -- ~1 repair per 500 hours
    estimatedRepairs = estimatedRepairs + (age or 0)  -- Plus ~1 per year
    local maxReliabilityCeiling = UsedPlusMaintenance.calculateInitialCeiling(
        workhorseLemonScale, estimatedRepairs)

    -- Cap reliability scores by the calculated ceiling
    engineReliability = math.min(engineReliability, maxReliabilityCeiling)
    hydraulicReliability = math.min(hydraulicReliability, maxReliabilityCeiling)
    electricalReliability = math.min(electricalReliability, maxReliabilityCeiling)

    -- v1.7.0: Generate tire condition based on age and hours
    -- Tires wear roughly 10% per 500 operating hours
    local tireWearFromHours = (hours or 0) / 5000  -- 10% per 500 hours
    local tireWearFromAge = (age or 0) * 0.05  -- 5% per year from age
    local tireCondition = math.max(0.1, 1.0 - tireWearFromHours - tireWearFromAge + randomVariance(0.1))
    tireCondition = math.min(1.0, tireCondition)

    -- Tire quality - used vehicles typically have normal tires
    -- Rarely retreads (lemons) or quality (workhorses)
    local tireQuality = 2  -- Normal
    if workhorseLemonScale < 0.3 then
        -- Lemons may have retreads
        if math.random() < 0.3 then
            tireQuality = 1  -- Retread
        end
    elseif workhorseLemonScale > 0.7 then
        -- Workhorses may have quality tires
        if math.random() < 0.2 then
            tireQuality = 3  -- Quality
        end
    end

    -- v1.7.0: Generate fluid levels (oil tends to be ok, hydraulic varies more)
    local oilLevel = math.max(0.2, 1.0 - (hours or 0) / 20000 + randomVariance(0.2))  -- Depletes slowly
    oilLevel = math.min(1.0, oilLevel)

    local hydraulicFluidLevel = math.max(0.3, 1.0 - (hours or 0) / 15000 + randomVariance(0.25))
    hydraulicFluidLevel = math.min(1.0, hydraulicFluidLevel)

    -- Lemons more likely to have fluid issues
    if workhorseLemonScale < 0.3 then
        oilLevel = oilLevel * 0.7
        hydraulicFluidLevel = hydraulicFluidLevel * 0.6
    end

    UsedPlus.logDebug(string.format("Generated reliability: DNA=%.2f, ceiling=%.1f%%, est.repairs=%d, tires=%.0f%%, oil=%.0f%%",
        workhorseLemonScale, maxReliabilityCeiling * 100, estimatedRepairs, tireCondition * 100, oilLevel * 100))

    return {
        engineReliability = engineReliability,
        hydraulicReliability = hydraulicReliability,
        electricalReliability = electricalReliability,
        workhorseLemonScale = workhorseLemonScale,
        maxReliabilityCeiling = maxReliabilityCeiling,
        wasInspected = false,

        -- v1.7.0: Tire and fluid data
        tireCondition = tireCondition,
        tireQuality = tireQuality,
        oilLevel = oilLevel,
        hydraulicFluidLevel = hydraulicFluidLevel
    }
end

--[[
    PUBLIC API: Get rating text for reliability score
    Returns rating string and icon for inspection reports
]]
function UsedPlusMaintenance.getRatingText(reliability)
    if reliability >= 0.8 then
        return "Good", "✓"
    elseif reliability >= 0.6 then
        return "Acceptable", "✓"
    elseif reliability >= 0.4 then
        return "Below Average", "⚠"
    elseif reliability >= 0.2 then
        return "Poor", "⚠"
    else
        return "Critical", "✗"
    end
end

--[[
    PUBLIC API: Generate inspector notes based on reliability data
    Used in inspection reports
]]
function UsedPlusMaintenance.generateInspectorNotes(reliabilityData)
    local notes = {}

    if reliabilityData.engineReliability < 0.5 then
        table.insert(notes, "Engine shows signs of hard use. Expect occasional stalling under load.")
    end
    if reliabilityData.hydraulicReliability < 0.5 then
        table.insert(notes, "Hydraulic system worn. Implements may drift when raised.")
    end
    if reliabilityData.electricalReliability < 0.5 then
        table.insert(notes, "Electrical issues detected. Implements may cut out unexpectedly.")
    end

    if #notes == 0 then
        table.insert(notes, "Vehicle in acceptable mechanical condition.")
    end

    return table.concat(notes, " ")
end

--[[
    PUBLIC API: Get current vehicle state for inspection comparison
    Returns hours, damage, wear values
]]
function UsedPlusMaintenance.getCurrentVehicleState(vehicle)
    local hours = 0
    if vehicle.getOperatingTime then
        hours = math.floor((vehicle:getOperatingTime() or 0) / 3600000)  -- Convert ms to hours
    end

    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    local wear = 0
    if vehicle.getWearTotalAmount then
        wear = vehicle:getWearTotalAmount() or 0
    end

    return {
        hours = hours,
        damage = damage,
        wear = wear
    }
end

--[[
    PUBLIC API: Check if inspection cache is still valid
    Returns true if cache exists AND vehicle state hasn't changed significantly
    @param vehicle - The vehicle to check
    @param tolerance - How much change is allowed before requiring new inspection (default 0.05 = 5%)
]]
function UsedPlusMaintenance.isInspectionCacheValid(vehicle, tolerance)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return false
    end

    -- No cache exists
    if not spec.hasInspectionCache then
        return false
    end

    tolerance = tolerance or 0.05  -- 5% tolerance by default

    -- Get current state
    local currentState = UsedPlusMaintenance.getCurrentVehicleState(vehicle)

    -- Compare with cached values
    local hoursDiff = math.abs(currentState.hours - spec.inspectionCacheHours)
    local damageDiff = math.abs(currentState.damage - spec.inspectionCacheDamage)
    local wearDiff = math.abs(currentState.wear - spec.inspectionCacheWear)

    -- Hours: allow 10 hours difference before requiring new inspection
    if hoursDiff > 10 then
        UsedPlus.logDebug(string.format("Inspection cache invalid: hours changed by %d", hoursDiff))
        return false
    end

    -- Damage: any significant change invalidates cache
    if damageDiff > tolerance then
        UsedPlus.logDebug(string.format("Inspection cache invalid: damage changed by %.1f%%", damageDiff * 100))
        return false
    end

    -- Wear: any significant change invalidates cache
    if wearDiff > tolerance then
        UsedPlus.logDebug(string.format("Inspection cache invalid: wear changed by %.1f%%", wearDiff * 100))
        return false
    end

    UsedPlus.logDebug("Inspection cache is still valid")
    return true
end

--[[
    PUBLIC API: Update inspection cache with current vehicle state
    Called after player pays for inspection
    @param vehicle - The vehicle to cache
]]
function UsedPlusMaintenance.updateInspectionCache(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logWarn("Cannot update inspection cache - spec not found")
        return false
    end

    local currentState = UsedPlusMaintenance.getCurrentVehicleState(vehicle)

    spec.hasInspectionCache = true
    spec.inspectionCacheHours = currentState.hours
    spec.inspectionCacheDamage = currentState.damage
    spec.inspectionCacheWear = currentState.wear

    UsedPlus.logDebug(string.format("Inspection cache updated: hours=%d, damage=%.1f%%, wear=%.1f%%",
        currentState.hours, currentState.damage * 100, currentState.wear * 100))

    return true
end

--[[
    PUBLIC API: Clear inspection cache (e.g., after major repairs)
    @param vehicle - The vehicle to clear cache for
]]
function UsedPlusMaintenance.clearInspectionCache(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return
    end

    spec.hasInspectionCache = false
    spec.inspectionCacheHours = 0
    spec.inspectionCacheDamage = 0
    spec.inspectionCacheWear = 0

    UsedPlus.logDebug("Inspection cache cleared")
end

--[[
    Inspection fee constant
]]
UsedPlusMaintenance.INSPECTION_FEE = 500

-- ============================================================================
-- v1.7.0: TIRE SYSTEM FUNCTIONS
-- ============================================================================

--[[
    Track distance traveled per-frame for tire wear calculation
    Uses 3D position delta to measure actual distance moved
]]
function UsedPlusMaintenance.trackDistanceTraveled(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Get current position
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local currentPos = {x = x, y = y, z = z}

    -- Calculate distance from last position
    if spec.lastPosition ~= nil then
        local dx = currentPos.x - spec.lastPosition.x
        local dy = currentPos.y - spec.lastPosition.y
        local dz = currentPos.z - spec.lastPosition.z
        local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

        -- Only count if moving (ignore tiny movements/jitter)
        if distance > 0.01 then
            spec.distanceTraveled = (spec.distanceTraveled or 0) + distance
        end
    end

    spec.lastPosition = currentPos
end

--[[
    Apply tire wear based on accumulated distance
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.applyTireWear(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end
    if spec.hasFlatTire then return end  -- No additional wear with flat

    -- Convert accumulated distance to km
    local distanceKm = (spec.distanceTraveled or 0) / 1000

    if distanceKm > 0 then
        -- Calculate wear amount
        local wearRate = UsedPlusMaintenance.CONFIG.tireWearRatePerKm
        local wearAmount = distanceKm * wearRate

        -- Apply wear
        spec.tireCondition = math.max(0, (spec.tireCondition or 1.0) - wearAmount)

        -- Reset distance counter
        spec.distanceTraveled = 0

        -- Check for warnings
        local config = UsedPlusMaintenance.CONFIG
        if spec.tireCondition <= config.tireCriticalThreshold and not spec.hasShownTireCriticalWarning then
            spec.hasShownTireCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_tireCritical"))
        elseif spec.tireCondition <= config.tireWarnThreshold and not spec.hasShownTireWarnWarning then
            spec.hasShownTireWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_tireWorn"))
        end
    end
end

--[[
    Check for tire-related malfunctions (flat tire, low traction)
    Called every 1 second from periodic checks
    v1.8.0: Defers flat tire trigger to UYT/RVB when those mods are installed
]]
function UsedPlusMaintenance.checkTireMalfunctions(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Skip if already have flat tire
    if spec.hasFlatTire then return end

    -- v1.8.0: Defer flat tire triggering to UYT or RVB if installed
    -- These mods have their own tire failure mechanics - we don't want double failures
    -- Our tire CONDITION still degrades (for low traction warnings, steering pull, etc.)
    -- But the actual FLAT TIRE event is handled by the other mod
    local shouldDeferFlatTire = ModCompatibility.shouldDeferTireFailure()

    -- Check for flat tire (only if tires are worn and vehicle is moving)
    -- v1.8.0: Skip flat tire trigger if UYT/RVB handles it
    if config.enableFlatTire and spec.tireCondition < config.flatTireThreshold and not shouldDeferFlatTire then
        -- Calculate chance based on tire condition and quality
        local conditionFactor = 1 - (spec.tireCondition / config.flatTireThreshold)
        local chance = config.flatTireBaseChance * conditionFactor * (spec.tireFailureMultiplier or 1.0)

        if math.random() < chance then
            -- Flat tire!
            spec.hasFlatTire = true
            spec.flatTireSide = math.random() < 0.5 and -1 or 1  -- Random left or right
            spec.hasShownFlatTireWarning = true
            spec.failureCount = (spec.failureCount or 0) + 1

            local sideText = spec.flatTireSide < 0 and "left" or "right"
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_flatTire"))
            UsedPlus.logDebug(string.format("Flat tire triggered on %s side for %s",
                sideText, vehicle:getName()))
        end
    end

    -- Check for low traction warning (weather-aware)
    if config.enableLowTraction and spec.tireCondition < config.lowTractionThreshold then
        if not spec.hasShownLowTractionWarning then
            -- Check weather conditions
            local isWet = false
            local isSnow = false

            if g_currentMission and g_currentMission.environment then
                local weather = g_currentMission.environment.weather
                if weather then
                    isWet = weather:getIsRaining() or false
                    isSnow = weather:getTimeSinceLastRain() ~= nil and weather:getSnowHeight() > 0
                end
            end

            if isWet or isSnow or spec.tireCondition < config.lowTractionThreshold * 0.5 then
                spec.hasShownLowTractionWarning = true
                UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_lowTraction"))
            end
        end
    end
end

--[[
    Get current tire traction multiplier based on condition, quality, and weather
    Used by friction system and display
]]
function UsedPlusMaintenance.getTireTractionMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local condition = spec.tireCondition or 1.0
    local qualityTraction = spec.tireMaxTraction or 1.0

    -- Base traction from tire condition (linear interpolation)
    -- At 100% condition: 100% of quality traction
    -- At 0% condition: 60% of quality traction (CONFIG.tireFrictionMinMultiplier)
    local minFriction = config.tireFrictionMinMultiplier
    local conditionTraction = minFriction + (condition * (1.0 - minFriction))

    local finalTraction = qualityTraction * conditionTraction

    -- Weather penalties (only if tire friction is enabled)
    if config.enableTireFriction then
        local isWet = false
        local isSnow = false

        if g_currentMission and g_currentMission.environment then
            local weather = g_currentMission.environment.weather
            if weather then
                isWet = weather:getIsRaining() or false
                -- Check for snow on ground
                if weather.getSnowHeight then
                    isSnow = weather:getSnowHeight() > 0
                end
            end
        end

        if isSnow then
            finalTraction = finalTraction * (1.0 - config.tireFrictionSnowPenalty)
        elseif isWet then
            finalTraction = finalTraction * (1.0 - config.tireFrictionWetPenalty)
        end
    end

    -- Flat tire = severe traction loss
    if spec.hasFlatTire then
        finalTraction = finalTraction * 0.5
    end

    return math.max(0.3, finalTraction)  -- Never below 30%
end

-- ============================================================================
-- v1.7.0: OIL SYSTEM FUNCTIONS
-- ============================================================================

--[[
    Update oil system: depletion, leak processing, damage
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.updateOilSystem(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only deplete oil when engine is running
    local motor = vehicle.spec_motorized
    if motor == nil or not motor.isMotorStarted then return end

    -- Base depletion rate (per second, converted from per hour)
    local baseRate = config.oilDepletionRatePerHour / 3600

    -- Leak multiplier
    local leakMult = 1.0
    if spec.hasOilLeak then
        if spec.oilLeakSeverity == 1 then
            leakMult = config.oilLeakMinorMult
        elseif spec.oilLeakSeverity == 2 then
            leakMult = config.oilLeakModerateMult
        else
            leakMult = config.oilLeakSevereMult
        end
    end

    -- Apply depletion
    local depletion = baseRate * leakMult * (dt / 1000)  -- dt is in ms
    spec.oilLevel = math.max(0, (spec.oilLevel or 1.0) - depletion)

    -- Check for low oil damage
    if spec.oilLevel <= config.oilCriticalThreshold then
        -- Track that we ran low (for permanent damage on failure)
        spec.wasLowOil = true

        -- Apply accelerated engine wear
        local wearAmount = 0.001 * config.oilLowDamageMultiplier
        spec.engineReliability = math.max(0.1, spec.engineReliability - wearAmount)

        -- Critical warning
        if not spec.hasShownOilCriticalWarning then
            spec.hasShownOilCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilCritical"))
        end
    elseif spec.oilLevel <= config.oilWarnThreshold then
        -- Low warning
        if not spec.hasShownOilWarnWarning then
            spec.hasShownOilWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilLow"))
        end
    end

    -- Leak warning
    if spec.hasOilLeak and not spec.hasShownOilLeakWarning then
        spec.hasShownOilLeakWarning = true
        local severityText = spec.oilLeakSeverity == 1 and "minor" or
                            (spec.oilLeakSeverity == 2 and "moderate" or "severe")
        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilLeak"))
    end
end

--[[
    Apply permanent engine damage when failure occurs while oil was low
    Called when engine stall or failure happens
]]
function UsedPlusMaintenance.applyOilDamageOnFailure(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if spec.wasLowOil and spec.oilLevel <= UsedPlusMaintenance.CONFIG.oilCriticalThreshold then
        local damage = UsedPlusMaintenance.CONFIG.oilPermanentDamageOnFailure
        spec.engineReliabilityCeiling = math.max(
            UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
            (spec.engineReliabilityCeiling or 1.0) - damage
        )

        -- Cap current reliability to new ceiling
        spec.engineReliability = math.min(spec.engineReliability, spec.engineReliabilityCeiling)

        UsedPlus.logDebug(string.format("Permanent engine damage! Ceiling now %.0f%% for %s",
            spec.engineReliabilityCeiling * 100, vehicle:getName()))

        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_engineDamage"))
    end
end

-- ============================================================================
-- v1.7.0: HYDRAULIC FLUID SYSTEM FUNCTIONS
-- ============================================================================

--[[
    Update hydraulic fluid system: depletion, leak processing, damage
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.updateHydraulicFluidSystem(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only deplete hydraulic fluid when doing hydraulic actions
    -- Check if any implement is raised/lowered
    local isUsingHydraulics = false

    -- Check attacherJoints for raised implements
    if vehicle.spec_attacherJoints then
        for _, joint in pairs(vehicle.spec_attacherJoints.attacherJoints or {}) do
            if joint.moveAlpha and joint.moveAlpha > 0 and joint.moveAlpha < 1 then
                isUsingHydraulics = true
                break
            end
        end
    end

    -- Check for cylinder movement
    if vehicle.spec_cylindered then
        for _, movingTool in pairs(vehicle.spec_cylindered.movingTools or {}) do
            if movingTool.isActive then
                isUsingHydraulics = true
                break
            end
        end
    end

    -- Leak always depletes, even without active hydraulics use
    local leakMult = 1.0
    if spec.hasHydraulicLeak then
        if spec.hydraulicLeakSeverity == 1 then
            leakMult = config.hydraulicLeakMinorMult
        elseif spec.hydraulicLeakSeverity == 2 then
            leakMult = config.hydraulicLeakModerateMult
        else
            leakMult = config.hydraulicLeakSevereMult
        end
    end

    -- Apply depletion
    local depletion = 0
    if isUsingHydraulics then
        depletion = config.hydraulicFluidDepletionPerAction * leakMult
    elseif spec.hasHydraulicLeak then
        -- Passive leak depletion (slower than active use)
        depletion = config.hydraulicFluidDepletionPerAction * 0.1 * leakMult
    end

    if depletion > 0 then
        spec.hydraulicFluidLevel = math.max(0, (spec.hydraulicFluidLevel or 1.0) - depletion)
    end

    -- Check for low hydraulic fluid damage
    if spec.hydraulicFluidLevel <= config.hydraulicFluidCriticalThreshold then
        spec.wasLowHydraulicFluid = true

        -- Apply accelerated hydraulic wear
        local wearAmount = 0.001 * config.hydraulicFluidLowDamageMultiplier
        spec.hydraulicReliability = math.max(0.1, spec.hydraulicReliability - wearAmount)

        if not spec.hasShownHydraulicCriticalWarning then
            spec.hasShownHydraulicCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicCritical"))
        end
    elseif spec.hydraulicFluidLevel <= config.hydraulicFluidWarnThreshold then
        if not spec.hasShownHydraulicWarnWarning then
            spec.hasShownHydraulicWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicLow"))
        end
    end

    -- Leak warning
    if spec.hasHydraulicLeak and not spec.hasShownHydraulicLeakWarning then
        spec.hasShownHydraulicLeakWarning = true
        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicLeak"))
    end
end

--[[
    Apply permanent hydraulic damage when failure occurs while fluid was low
]]
function UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if spec.wasLowHydraulicFluid and spec.hydraulicFluidLevel <= UsedPlusMaintenance.CONFIG.hydraulicFluidCriticalThreshold then
        local damage = UsedPlusMaintenance.CONFIG.hydraulicFluidPermanentDamageOnFailure
        spec.hydraulicReliabilityCeiling = math.max(
            UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
            (spec.hydraulicReliabilityCeiling or 1.0) - damage
        )

        spec.hydraulicReliability = math.min(spec.hydraulicReliability, spec.hydraulicReliabilityCeiling)

        UsedPlus.logDebug(string.format("Permanent hydraulic damage! Ceiling now %.0f%% for %s",
            spec.hydraulicReliabilityCeiling * 100, vehicle:getName()))

        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicDamage"))
    end
end

-- ============================================================================
-- v1.7.0: LEAK SYSTEM FUNCTIONS
-- ============================================================================

--[[
    Check for new leaks (oil, hydraulic, fuel)
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.checkForNewLeaks(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Check for new oil leak
    if config.enableOilLeak and not spec.hasOilLeak then
        if spec.engineReliability < config.oilLeakThreshold then
            local reliabilityFactor = 1 - (spec.engineReliability / config.oilLeakThreshold)
            local chance = config.oilLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasOilLeak = true
                -- Determine severity based on reliability
                if spec.engineReliability < 0.15 then
                    spec.oilLeakSeverity = 3  -- Severe
                elseif spec.engineReliability < 0.25 then
                    spec.oilLeakSeverity = 2  -- Moderate
                else
                    spec.oilLeakSeverity = 1  -- Minor
                end
                UsedPlus.logDebug(string.format("Oil leak (severity %d) triggered for %s",
                    spec.oilLeakSeverity, vehicle:getName()))
            end
        end
    end

    -- Check for new hydraulic leak
    if config.enableHydraulicLeak and not spec.hasHydraulicLeak then
        if spec.hydraulicReliability < config.hydraulicLeakThreshold then
            local reliabilityFactor = 1 - (spec.hydraulicReliability / config.hydraulicLeakThreshold)
            local chance = config.hydraulicLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasHydraulicLeak = true
                if spec.hydraulicReliability < 0.15 then
                    spec.hydraulicLeakSeverity = 3
                elseif spec.hydraulicReliability < 0.25 then
                    spec.hydraulicLeakSeverity = 2
                else
                    spec.hydraulicLeakSeverity = 1
                end
                UsedPlus.logDebug(string.format("Hydraulic leak (severity %d) triggered for %s",
                    spec.hydraulicLeakSeverity, vehicle:getName()))
            end
        end
    end

    -- Check for new fuel leak
    if config.enableFuelLeak and not spec.hasFuelLeak then
        if spec.engineReliability < config.fuelLeakThreshold then
            local reliabilityFactor = 1 - (spec.engineReliability / config.fuelLeakThreshold)
            local chance = config.fuelLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasFuelLeak = true
                -- Random multiplier between min and max
                spec.fuelLeakMultiplier = config.fuelLeakMinMult +
                    (math.random() * (config.fuelLeakMaxMult - config.fuelLeakMinMult))

                if not spec.hasShownFuelLeakWarning then
                    spec.hasShownFuelLeakWarning = true
                    UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_fuelLeak"))
                end

                UsedPlus.logDebug(string.format("Fuel leak (%.1fx consumption) triggered for %s",
                    spec.fuelLeakMultiplier, vehicle:getName()))
            end
        end
    end
end

--[[
    Get fuel consumption multiplier (for fuel leak effect)
    Returns 1.0 normally, or higher if fuel leak active
]]
function UsedPlusMaintenance.getFuelConsumptionMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    if spec.hasFuelLeak then
        return spec.fuelLeakMultiplier or 1.0
    end

    return 1.0
end

--[[
    v1.7.0: Process fuel leak - drain fuel from tank
    Called every 1 second from periodic checks
    Drains fuel at a rate based on the leak multiplier
]]
function UsedPlusMaintenance.processFuelLeak(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if not spec.hasFuelLeak then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only leak when engine is running (fuel system pressurized)
    local motor = vehicle.spec_motorized
    if motor == nil or not motor.isMotorStarted then return end

    -- Get fuel fill unit
    local fuelFillUnitIndex = nil
    if vehicle.getConsumerFillUnitIndex then
        fuelFillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
        -- Also check methane if no diesel
        if fuelFillUnitIndex == nil then
            fuelFillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.METHANE)
        end
    end

    if fuelFillUnitIndex == nil then return end

    -- Calculate leak rate (liters per second based on multiplier)
    -- Base leak: ~0.5 L/s, scaled by multiplier (1.5x to 3x)
    local baseFuelLeakRate = config.fuelLeakBaseDrainRate or 0.5
    local leakRate = baseFuelLeakRate * (spec.fuelLeakMultiplier - 1.0)

    -- dt is in seconds (1 second from periodic check)
    local fuelDrained = leakRate * 1.0  -- 1 second interval

    if fuelDrained > 0 then
        local currentFuel = vehicle:getFillUnitFillLevel(fuelFillUnitIndex)

        if currentFuel > 0 then
            -- Drain fuel using addFillUnitFillLevel with negative amount
            vehicle:addFillUnitFillLevel(
                vehicle:getOwnerFarmId(),
                fuelFillUnitIndex,
                -fuelDrained,
                vehicle:getFillUnitFillType(fuelFillUnitIndex),
                ToolType.UNDEFINED,
                nil
            )

            UsedPlus.logDebug(string.format("Fuel leak: drained %.2f L from %s (mult %.1fx)",
                fuelDrained, vehicle:getName(), spec.fuelLeakMultiplier))
        end
    end
end

--[[
    Set tire quality and apply modifiers
    Called when tires are replaced/retreaded
    @param quality 1=Retread, 2=Normal, 3=Quality
]]
function UsedPlusMaintenance.setTireQuality(vehicle, quality)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    spec.tireQuality = quality
    spec.tireCondition = 1.0  -- New tires
    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownTireWarnWarning = false
    spec.hasShownTireCriticalWarning = false
    spec.hasShownFlatTireWarning = false
    spec.hasShownLowTractionWarning = false

    if quality == 1 then  -- Retread
        spec.tireMaxTraction = config.tireRetreadTractionMult
        spec.tireFailureMultiplier = config.tireRetreadFailureMult
    elseif quality == 3 then  -- Quality
        spec.tireMaxTraction = config.tireQualityTractionMult
        spec.tireFailureMultiplier = config.tireQualityFailureMult
    else  -- Normal (2)
        spec.tireMaxTraction = config.tireNormalTractionMult
        spec.tireFailureMultiplier = config.tireNormalFailureMult
    end

    UsedPlus.logDebug(string.format("Tires replaced on %s: quality=%d, traction=%.0f%%, failureMult=%.1f",
        vehicle:getName(), quality, spec.tireMaxTraction * 100, spec.tireFailureMultiplier))
end

--[[
    Refill oil (full change or top up)
    @param isFullChange true for full change (resets wasLowOil), false for top up
]]
function UsedPlusMaintenance.refillOil(vehicle, isFullChange)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.oilLevel = 1.0
    spec.hasOilLeak = false
    spec.oilLeakSeverity = 0
    spec.hasShownOilWarnWarning = false
    spec.hasShownOilCriticalWarning = false
    spec.hasShownOilLeakWarning = false

    if isFullChange then
        spec.wasLowOil = false
    end

    UsedPlus.logDebug(string.format("Oil %s for %s",
        isFullChange and "changed" or "topped up", vehicle:getName()))
end

--[[
    Refill hydraulic fluid (full change or top up)
    @param isFullChange true for full change (resets wasLowHydraulicFluid), false for top up
]]
function UsedPlusMaintenance.refillHydraulicFluid(vehicle, isFullChange)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hydraulicFluidLevel = 1.0
    spec.hasHydraulicLeak = false
    spec.hydraulicLeakSeverity = 0
    spec.hasShownHydraulicWarnWarning = false
    spec.hasShownHydraulicCriticalWarning = false
    spec.hasShownHydraulicLeakWarning = false

    if isFullChange then
        spec.wasLowHydraulicFluid = false
    end

    UsedPlus.logDebug(string.format("Hydraulic fluid %s for %s",
        isFullChange and "changed" or "topped up", vehicle:getName()))
end

--[[
    Fix fuel leak (repair required)
]]
function UsedPlusMaintenance.repairFuelLeak(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hasFuelLeak = false
    spec.fuelLeakMultiplier = 1.0
    spec.hasShownFuelLeakWarning = false

    UsedPlus.logDebug(string.format("Fuel leak repaired for %s", vehicle:getName()))
end

--[[
    Fix flat tire (requires tire replacement via Tires dialog)
]]
function UsedPlusMaintenance.repairFlatTire(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownFlatTireWarning = false

    UsedPlus.logDebug(string.format("Flat tire fixed for %s", vehicle:getName()))
end

-- ============================================================================
-- v1.7.0: WHEEL PHYSICS FRICTION HOOK
-- Global hook into WheelPhysics to reduce tire friction based on condition
-- ============================================================================

--[[
    v1.7.0: Calculate tire friction scale for a vehicle
    Returns a multiplier (0.1 to 1.1) based on:
    - Tire condition (worn tires = less grip)
    - Tire quality (retread=0.85, normal=1.0, quality=1.1)
    - Flat tire (severely reduced)
]]
function UsedPlusMaintenance.getTireFrictionScale(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG

    -- Base friction from tire quality
    local qualityScale = spec.tireMaxTraction or 1.0

    -- Condition-based friction reduction
    -- New tires (1.0) = full friction
    -- Worn tires (0.3) = ~85% friction
    -- Critical tires (0.15) = ~70% friction
    local condition = spec.tireCondition or 1.0
    local conditionScale = 0.7 + (condition * 0.3)  -- Range: 0.7 to 1.0

    -- Flat tire = severe friction loss on that side
    local flatTireScale = 1.0
    if spec.hasFlatTire then
        flatTireScale = config.flatTireFrictionMult or 0.3  -- 30% friction with flat
    end

    -- Combine all factors
    local finalScale = qualityScale * conditionScale * flatTireScale

    -- Clamp to reasonable range
    return math.max(0.1, math.min(1.1, finalScale))
end

--[[
    v1.7.0: Hook into WheelPhysics.updateTireFriction
    Modifies tire friction based on UsedPlus tire condition system
    Pattern from: FS25_useYourTyres
]]
function UsedPlusMaintenance.hookTireFriction(physWheel)
    -- Safety check: ensure physWheel and vehicle exist
    if physWheel == nil or physWheel.vehicle == nil then return end
    if not physWheel.vehicle.isServer then return end
    if not physWheel.vehicle.isAddedToPhysics then return end

    local vehicle = physWheel.vehicle
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    if not config.enableTireFriction then return end

    -- Calculate our friction scale
    local usedPlusFrictionScale = UsedPlusMaintenance.getTireFrictionScale(vehicle)

    -- Only modify if we have a meaningful change
    if usedPlusFrictionScale >= 0.99 and usedPlusFrictionScale <= 1.01 then return end

    -- Apply friction modification
    -- The base game (or other mods like useYourTyres) will have already called
    -- setWheelShapeTireFriction, so we need to call it again with our modifier
    local frictionCoeff = physWheel.frictionScale * physWheel.tireGroundFrictionCoeff * usedPlusFrictionScale

    setWheelShapeTireFriction(
        physWheel.wheel.node,
        physWheel.wheelShape,
        physWheel.maxLongStiffness,
        physWheel.maxLatStiffness,
        physWheel.maxLatStiffnessLoad,
        frictionCoeff
    )
end

-- Register the global WheelPhysics hook (if WheelPhysics exists)
if WheelPhysics ~= nil and WheelPhysics.updateTireFriction ~= nil then
    WheelPhysics.updateTireFriction = Utils.appendedFunction(
        WheelPhysics.updateTireFriction,
        UsedPlusMaintenance.hookTireFriction
    )
    UsedPlus.logInfo("WheelPhysics friction hook registered for tire condition system")
else
    UsedPlus.logWarn("WheelPhysics not available - tire friction effects disabled")
end

UsedPlus.logInfo("UsedPlusMaintenance specialization loaded")
