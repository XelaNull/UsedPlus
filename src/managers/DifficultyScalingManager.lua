--[[
    FS25_UsedPlus - Farmland Difficulty Scaling Manager
    v2.0.0: Apply game's difficulty multipliers to farmland prices

    Based on: FS25_FarmlandDifficulty by GMNGjoy
    https://github.com/GMNGjoy/FS25_FarmlandDifficulty

    The vanilla game applies EconomyManager.COST_MULTIPLIER to vehicle prices,
    maintenance costs, and other expenses based on economic difficulty:
    - Easy: 0.6x (40% discount)
    - Normal: 1.0x (baseline)
    - Hard: 1.4x (40% markup)

    However, vanilla FS25 does NOT apply this to farmland prices.
    This manager fixes that inconsistency by scaling farmland the same way.

    This is a global singleton: g_difficultyScalingManager
]]

DifficultyScalingManager = {}
local DifficultyScalingManager_mt = Class(DifficultyScalingManager)

-- Difficulty level constants (match game's values)
DifficultyScalingManager.DIFFICULTY = {
    EASY = 1,
    NORMAL = 2,
    HARD = 3
}

DifficultyScalingManager.DIFFICULTY_NAMES = { "Easy", "Normal", "Hard" }

--[[
    Constructor
]]
function DifficultyScalingManager.new()
    local self = setmetatable({}, DifficultyScalingManager_mt)

    -- Track if hook is installed
    self.hookInstalled = false

    -- Track if initialized
    self.isInitialized = false

    return self
end

--[[
    Initialize the manager - called from main.lua
]]
function DifficultyScalingManager:init()
    if self.isInitialized then
        return
    end

    -- Install farmland price hook if enabled
    if UsedPlusSettings and UsedPlusSettings:get("enableFarmlandDifficultyScaling") then
        self:installFarmlandHook()
    end

    -- Listen for setting changes
    if UsedPlusSettings then
        UsedPlusSettings:addListener(self)
    end

    -- Listen for difficulty changes mid-game (like the reference mod)
    FSBaseMission.setEconomicDifficulty = Utils.appendedFunction(
        FSBaseMission.setEconomicDifficulty,
        function()
            self:onDifficultyChanged()
        end
    )

    self.isInitialized = true
    UsedPlus.logInfo("DifficultyScalingManager initialized")
end

--[[
    Get the current difficulty level from mission
    @return number - 1=Easy, 2=Normal, 3=Hard
]]
function DifficultyScalingManager:getCurrentDifficulty()
    if g_currentMission and g_currentMission.missionInfo then
        return g_currentMission.missionInfo.economicDifficulty or 2
    end
    return 2  -- Default to Normal
end

--[[
    Get the game's standard difficulty multiplier
    @param difficultyLevel - 1=Easy, 2=Normal, 3=Hard
    @return number - Multiplier (0.6, 1.0, or 1.4)
]]
function DifficultyScalingManager:getMultiplier(difficultyLevel)
    difficultyLevel = difficultyLevel or self:getCurrentDifficulty()

    -- Use the game's built-in multipliers
    return EconomyManager.COST_MULTIPLIER[difficultyLevel] or 1.0
end

--[[
    Install hook for farmland pricing
    Replaces FarmlandManager.getPricePerHa with our version
]]
function DifficultyScalingManager:installFarmlandHook()
    if self.hookInstalled then
        UsedPlus.logDebug("Farmland hook already installed")
        return
    end

    -- Override with our version that applies difficulty multiplier
    FarmlandManager.getPricePerHa = Utils.overwrittenFunction(
        FarmlandManager.getPricePerHa,
        function(farmlandManager, superFunc)
            return self:getAdjustedPricePerHa()
        end
    )

    self.hookInstalled = true
    UsedPlus.logInfo("Farmland difficulty scaling enabled - prices now scale with economic difficulty")
end

--[[
    Calculate adjusted price per hectare
    Applies the same difficulty multiplier that the game uses for vehicles
    @return number - Adjusted price per hectare
]]
function DifficultyScalingManager:getAdjustedPricePerHa()
    -- Get base price (map's configured price per hectare)
    local basePricePerHa = g_farmlandManager.pricePerHa

    -- Check if scaling is enabled
    if not UsedPlusSettings or not UsedPlusSettings:get("enableFarmlandDifficultyScaling") then
        -- If disabled, return base price (no scaling)
        return basePricePerHa
    end

    -- Get current difficulty and apply game's standard multiplier
    local difficulty = self:getCurrentDifficulty()
    local multiplier = self:getMultiplier(difficulty)
    local adjustedPrice = basePricePerHa * multiplier

    UsedPlus.logTrace(string.format(
        "Farmland price: base=%d, difficulty=%s, mult=%.2f, adjusted=%d",
        basePricePerHa,
        self.DIFFICULTY_NAMES[difficulty],
        multiplier,
        adjustedPrice
    ))

    return adjustedPrice
end

--[[
    Called when difficulty setting changes mid-game
    Updates all farmland prices to reflect new difficulty
]]
function DifficultyScalingManager:onDifficultyChanged()
    if not UsedPlusSettings or not UsedPlusSettings:get("enableFarmlandDifficultyScaling") then
        return
    end

    -- Update all farmland prices (like reference mod)
    if g_farmlandManager and g_farmlandManager.farmlands then
        for _, farmland in pairs(g_farmlandManager.farmlands) do
            if farmland.updatePrice then
                farmland:updatePrice()
            end
        end
        UsedPlus.logInfo("Farmland prices updated for new difficulty setting")
    end
end

--[[
    Settings change listener
    Handles enabling/disabling of feature
]]
function DifficultyScalingManager:onSettingChanged(key, newValue, oldValue)
    if key == "enableFarmlandDifficultyScaling" then
        if newValue and not self.hookInstalled then
            self:installFarmlandHook()
        end
        -- Update prices when setting changes
        self:onDifficultyChanged()

        if newValue then
            UsedPlus.logInfo("Farmland difficulty scaling enabled")
        else
            UsedPlus.logInfo("Farmland difficulty scaling disabled")
        end
    elseif key == "batch" or key == "reset" then
        -- Preset changed - update prices
        self:onDifficultyChanged()
    end
end

--[[
    Get display text for current difficulty scaling status
    @return string - Human readable description
]]
function DifficultyScalingManager:getStatusText()
    local enabled = UsedPlusSettings and UsedPlusSettings:get("enableFarmlandDifficultyScaling")

    if not enabled then
        return "Farmland Difficulty Scaling: Disabled"
    end

    local difficulty = self:getCurrentDifficulty()
    local diffName = self.DIFFICULTY_NAMES[difficulty]
    local multiplier = self:getMultiplier(difficulty)

    return string.format(
        "Farmland Difficulty Scaling: %s (%.0f%% of base price)",
        diffName,
        multiplier * 100
    )
end

--[[
    Debug console command
]]
function DifficultyScalingManager:consoleCommandStatus()
    print(self:getStatusText())

    if UsedPlusSettings and UsedPlusSettings:get("enableFarmlandDifficultyScaling") then
        local difficulty = self:getCurrentDifficulty()
        local basePricePerHa = g_farmlandManager and g_farmlandManager.pricePerHa or 0
        local adjustedPrice = self:getAdjustedPricePerHa()

        print(string.format("  Base price/ha: %s", g_i18n:formatMoney(basePricePerHa)))
        print(string.format("  Adjusted price/ha: %s", g_i18n:formatMoney(adjustedPrice)))
        print(string.format("  Multiplier: %.2f", self:getMultiplier(difficulty)))
    end
end

-- Create global singleton
g_difficultyScalingManager = DifficultyScalingManager.new()

UsedPlus.logInfo("DifficultyScalingManager loaded")
