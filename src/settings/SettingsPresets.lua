--[[
    FS25_UsedPlus - Settings Presets

    Pre-configured settings combinations for different playstyles.
    Each preset only overrides settings that differ from defaults.

    Presets:
    - realistic: Default balanced simulation (actually just uses defaults)
    - casual: Relaxed economics for farming-focused players
    - hardcore: Challenging economics requiring careful management
    - lite: Minimal systems - just finance and lease
]]

SettingsPresets = {}

--[[
    REALISTIC (Default)
    Balanced simulation - the intended experience
    Note: This is essentially empty since defaults ARE realistic
]]
SettingsPresets.realistic = {
    -- All defaults apply - this resets to standard
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,
    baseInterestRate = 0.08,
    missedPaymentsToDefault = 3,
    baseTradeInPercent = 55,
    startingCreditScore = 650,
    latePaymentPenalty = 15,
    searchSuccessPercent = 75,
}

--[[
    CASUAL
    Relaxed economics - focus on farming, not spreadsheets
    - Flat interest rates (no credit system)
    - More forgiving missed payments
    - Better trade-in values
    - Higher search success
]]
SettingsPresets.casual = {
    -- System toggles
    enableCreditSystem = false,         -- No credit scoring = flat rates

    -- More forgiving economics
    baseInterestRate = 0.05,            -- 5% instead of 8%
    missedPaymentsToDefault = 6,        -- 6 strikes instead of 3
    minDownPaymentPercent = 0,          -- No down payment required
    latePaymentPenalty = 5,             -- Smaller penalty

    -- Better values
    baseTradeInPercent = 65,            -- 65% instead of 55%
    searchSuccessPercent = 90,          -- 90% instead of 75%

    -- Disable annoyances
    enableMalfunctionsSystem = false,   -- No random breakdowns
}

--[[
    HARDCORE
    Punishing economics - every dollar matters
    - Higher interest rates
    - Faster defaults
    - Worse values
    - More breakdowns
]]
SettingsPresets.hardcore = {
    -- Tougher economics
    baseInterestRate = 0.12,            -- 12% instead of 8%
    missedPaymentsToDefault = 2,        -- 2 strikes instead of 3
    minDownPaymentPercent = 20,         -- 20% down required
    latePaymentPenalty = 25,            -- Bigger credit hit

    -- Worse values
    baseTradeInPercent = 45,            -- 45% instead of 55%
    startingCreditScore = 550,          -- Start with poor credit
    searchSuccessPercent = 60,          -- 60% instead of 75%
    agentCommissionPercent = 12,        -- Higher commission

    -- More challenges
    repairCostMultiplier = 1.5,         -- 50% more expensive repairs
    conditionPriceMultiplier = 1.3,     -- Condition matters more
}

--[[
    LITE
    Just the basics - finance and lease only
    Disables marketplace, repair, and maintenance systems
]]
SettingsPresets.lite = {
    -- Keep core systems
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableCreditSystem = true,

    -- Disable everything else
    enableUsedVehicleSearch = false,
    enableVehicleSaleSystem = false,
    enableRepairSystem = false,
    enableTradeInSystem = false,
    enableTireWearSystem = false,
    enableMalfunctionsSystem = false,
}

--[[
    Get preset names for UI display
    @return table - Array of {key, displayName} pairs
]]
function SettingsPresets.getPresetList()
    return {
        { key = "realistic", name = "Realistic" },
        { key = "casual", name = "Casual" },
        { key = "hardcore", name = "Hardcore" },
        { key = "lite", name = "Lite Mode" },
    }
end

--[[
    Get description for a preset
    @param presetKey - Preset key name
    @return string - Description text
]]
function SettingsPresets.getDescription(presetKey)
    local descriptions = {
        realistic = "Balanced simulation - the intended experience",
        casual = "Relaxed economics - focus on farming, not finance",
        hardcore = "Punishing economics - every dollar matters",
        lite = "Minimal systems - just finance and lease",
    }
    return descriptions[presetKey] or ""
end

UsedPlus.logInfo("SettingsPresets loaded")
