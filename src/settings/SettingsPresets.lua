--[[
    FS25_UsedPlus - Settings Presets
    v2.0.0: Expanded preset system with 6 targeted presets

    Pre-configured settings combinations for different playstyles.
    Each preset only overrides settings that differ from defaults.

    Presets:
    - easy: Maximum forgiveness - "I just want to farm"
    - balanced: Default balanced simulation (intended experience)
    - challenging: Real consequences, tighter margins
    - hardcore: Economic survival - every dollar matters
    - streamlined: Just finance/lease, no marketplace/maintenance
    - immersive: Full simulation for use with RVB/UYT mods
]]

SettingsPresets = {}

--[[
    EASY - Maximum Forgiveness
    "I just want to farm, not manage spreadsheets"
    - Very cheap repairs and repaints
    - Extremely generous trade-in values
    - Low interest rates
    - Many chances before default
    - No credit system (flat rates)
    - No malfunctions or tire wear
]]
SettingsPresets.easy = {
    -- All systems enabled except stress-inducing ones
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = false,         -- No credit = flat rates
    enableTireWearSystem = false,       -- No tire degradation
    enableMalfunctionsSystem = false,   -- No random breakdowns
    enablePartialRepair = true,
    enablePartialRepaint = true,
    enableFarmlandDifficultyScaling = true,  -- v2.0.0: Scale land with difficulty
    enableBankInterest = true,               -- v2.0.0: Earn interest on cash

    -- Very forgiving economics
    baseInterestRate = 0.04,            -- 4% (very low)
    baseTradeInPercent = 80,            -- 80% (very generous)
    repairCostMultiplier = 0.25,        -- 25% of normal cost
    paintCostMultiplier = 0.25,         -- 25% of normal cost
    leaseMarkupPercent = 5,             -- Minimal markup
    missedPaymentsToDefault = 10,       -- 10 strikes
    minDownPaymentPercent = 0,          -- No down payment
    startingCreditScore = 750,          -- Excellent credit
    latePaymentPenalty = 0,             -- No penalty
    baseSearchSuccessPercent = 95,      -- Almost always find vehicles
    agentCommissionPercent = 4,         -- Low commission
    bankInterestRate = 0.035,           -- v2.0.0: 3.5% APY (generous passive income)
}

--[[
    BALANCED - Default Experience
    The intended UsedPlus experience - fair simulation
    Note: This resets to defaults
]]
SettingsPresets.balanced = {
    -- All systems enabled
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,
    enablePartialRepair = true,
    enablePartialRepaint = true,
    enableFarmlandDifficultyScaling = true,  -- v2.0.0: Scale land with difficulty
    enableBankInterest = true,               -- v2.0.0: Earn interest on cash

    -- Default economics
    baseInterestRate = 0.08,            -- 8%
    baseTradeInPercent = 55,            -- 55%
    repairCostMultiplier = 1.0,         -- Normal cost
    paintCostMultiplier = 1.0,          -- Normal cost
    leaseMarkupPercent = 15,            -- Standard markup
    missedPaymentsToDefault = 3,        -- 3 strikes
    minDownPaymentPercent = 0,          -- No down payment
    startingCreditScore = 650,          -- Average credit
    latePaymentPenalty = 15,            -- Standard penalty
    baseSearchSuccessPercent = 75,      -- Good chance
    agentCommissionPercent = 8,         -- Standard commission
    bankInterestRate = 0.01,            -- v2.0.0: 1% APY (realistic credit union rate)
}

--[[
    CHALLENGING - Real Consequences
    For players who want decisions to matter
    - Higher costs
    - Lower values
    - Faster defaults
    - Requires down payment
]]
SettingsPresets.challenging = {
    -- All systems enabled
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,
    enablePartialRepair = true,
    enablePartialRepaint = true,
    enableFarmlandDifficultyScaling = true,  -- v2.0.0: Scale land with difficulty
    enableBankInterest = true,               -- v2.0.0: Minimal interest

    -- Tighter economics
    baseInterestRate = 0.10,            -- 10%
    baseTradeInPercent = 50,            -- 50%
    repairCostMultiplier = 1.25,        -- 25% more expensive
    paintCostMultiplier = 1.25,         -- 25% more expensive
    leaseMarkupPercent = 20,            -- Higher markup
    missedPaymentsToDefault = 2,        -- Only 2 strikes
    minDownPaymentPercent = 10,         -- 10% down required
    startingCreditScore = 600,          -- Below average credit
    latePaymentPenalty = 20,            -- Bigger hit
    baseSearchSuccessPercent = 65,      -- Lower chance
    agentCommissionPercent = 10,        -- Higher commission
    bankInterestRate = 0.005,           -- v2.0.0: 0.5% APY (minimal reward for hoarding)
}

--[[
    HARDCORE - Economic Survival
    Every dollar matters - for spreadsheet farmers
    - High interest
    - Low trade-in
    - Expensive repairs
    - Fast defaults
    - Poor starting credit
]]
SettingsPresets.hardcore = {
    -- All systems enabled
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,
    enablePartialRepair = true,
    enablePartialRepaint = true,
    enableFarmlandDifficultyScaling = true,  -- v2.0.0: Scale land with difficulty
    enableBankInterest = false,              -- v2.0.0: No free money!

    -- Punishing economics
    baseInterestRate = 0.12,            -- 12%
    baseTradeInPercent = 40,            -- 40%
    repairCostMultiplier = 1.5,         -- 50% more expensive
    paintCostMultiplier = 1.5,          -- 50% more expensive
    leaseMarkupPercent = 25,            -- High markup
    missedPaymentsToDefault = 2,        -- Only 2 strikes
    minDownPaymentPercent = 20,         -- 20% down required
    startingCreditScore = 500,          -- Poor credit
    latePaymentPenalty = 30,            -- Major credit hit
    baseSearchSuccessPercent = 50,      -- Hard to find deals
    agentCommissionPercent = 12,        -- High commission
    conditionPriceMultiplier = 1.5,     -- Condition matters more
    bankInterestRate = 0.0,             -- v2.0.0: 0% (no free money for the masochists!)
}

--[[
    STREAMLINED - Just Finance
    "I want finance buttons, nothing else"
    - Finance and lease only
    - No marketplace
    - No maintenance systems
    - No partial repair/repaint
]]
SettingsPresets.streamlined = {
    -- Core finance only
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = false,    -- No used search
    enableVehicleSaleSystem = false,    -- No selling
    enableRepairSystem = false,         -- No repair integration
    enableTradeInSystem = true,         -- Keep trade-in (useful)
    enableCreditSystem = false,         -- No credit (simpler)
    enableTireWearSystem = false,       -- No tire wear
    enableMalfunctionsSystem = false,   -- No malfunctions
    enablePartialRepair = false,        -- No partial repair
    enablePartialRepaint = false,       -- No partial repaint
    enableFarmlandDifficultyScaling = false, -- v2.0.0: Keep vanilla land prices
    enableBankInterest = false,              -- v2.0.0: No extras

    -- Relaxed economics
    baseInterestRate = 0.06,            -- 6%
    baseTradeInPercent = 60,            -- 60%
    repairCostMultiplier = 1.0,         -- Normal (not used)
    paintCostMultiplier = 1.0,          -- Normal (not used)
    missedPaymentsToDefault = 5,        -- Forgiving
    latePaymentPenalty = 5,             -- Small penalty
    startingCreditScore = 700,          -- Good credit
    bankInterestRate = 0.0,             -- v2.0.0: 0% (feature disabled)
}

--[[
    IMMERSIVE - Full Simulation
    For use with RVB, UYT, and other simulation mods
    - All systems enabled
    - Realistic but not punishing values
    - Best paired with Real Vehicle Breakdowns and Use Up Your Tyres
]]
SettingsPresets.immersive = {
    -- All systems enabled
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,
    enablePartialRepair = true,
    enablePartialRepaint = true,
    enableFarmlandDifficultyScaling = true,  -- v2.0.0: Scale land with difficulty
    enableBankInterest = true,               -- v2.0.0: Realistic interest

    -- Realistic economics
    baseInterestRate = 0.08,            -- 8%
    baseTradeInPercent = 55,            -- 55%
    repairCostMultiplier = 1.0,         -- Normal
    paintCostMultiplier = 1.0,          -- Normal
    leaseMarkupPercent = 15,            -- Standard
    missedPaymentsToDefault = 3,        -- Standard
    minDownPaymentPercent = 5,          -- Small down payment
    startingCreditScore = 650,          -- Average
    latePaymentPenalty = 15,            -- Standard
    baseSearchSuccessPercent = 75,      -- Standard
    agentCommissionPercent = 8,         -- Standard
    bankInterestRate = 0.01,            -- v2.0.0: 1% APY (realistic credit union rate)
}

-- Legacy aliases for backwards compatibility
SettingsPresets.realistic = SettingsPresets.balanced
SettingsPresets.casual = SettingsPresets.easy
SettingsPresets.lite = SettingsPresets.streamlined

--[[
    Get preset names for UI display
    @return table - Array of {key, displayName} pairs
]]
function SettingsPresets.getPresetList()
    return {
        { key = "easy", name = "Easy" },
        { key = "balanced", name = "Balanced" },
        { key = "challenging", name = "Challenging" },
        { key = "hardcore", name = "Hardcore" },
        { key = "streamlined", name = "Streamlined" },
        { key = "immersive", name = "Immersive" },
    }
end

--[[
    Get description for a preset
    @param presetKey - Preset key name
    @return string - Description text
]]
function SettingsPresets.getDescription(presetKey)
    local descriptions = {
        easy = "Maximum forgiveness - focus on farming, not finance",
        balanced = "Default balanced simulation - the intended experience",
        challenging = "Real consequences - decisions matter",
        hardcore = "Economic survival - every dollar counts",
        streamlined = "Just finance and lease - no extras",
        immersive = "Full simulation - best with RVB/UYT mods",
        -- Legacy aliases
        realistic = "Default balanced simulation - the intended experience",
        casual = "Maximum forgiveness - focus on farming, not finance",
        lite = "Just finance and lease - no extras",
    }
    return descriptions[presetKey] or ""
end

UsedPlus.logInfo("SettingsPresets loaded (v2.0.0 - 6 presets)")
