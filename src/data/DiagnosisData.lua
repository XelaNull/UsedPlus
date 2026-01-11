--[[
    FS25_UsedPlus - Diagnosis Data for Field Service Kit

    Contains symptom-to-diagnosis mappings for the field repair minigame.
    Each system (Engine, Electrical, Hydraulic) has 4 possible failure scenarios.
    Player must match symptoms to the correct diagnosis for best repair outcome.

    v1.8.0 - Field Service Kit System
]]

DiagnosisData = {}

-- System types
DiagnosisData.SYSTEM_ENGINE = "engine"
DiagnosisData.SYSTEM_ELECTRICAL = "electrical"
DiagnosisData.SYSTEM_HYDRAULIC = "hydraulic"
DiagnosisData.SYSTEM_TIRE = "tire"

-- Outcome tiers
DiagnosisData.OUTCOME_PERFECT = "perfect"     -- Right system + Right diagnosis
DiagnosisData.OUTCOME_GOOD = "good"           -- Right system + Wrong diagnosis
DiagnosisData.OUTCOME_POOR = "poor"           -- Wrong system

--[[
    Outcome modifiers by tier
    reliabilityBoost: How much reliability is restored (0.0-1.0 scale)
    functionRestore: How much function level is restored (0.0-1.0 scale)
]]
DiagnosisData.OUTCOMES = {
    [DiagnosisData.OUTCOME_PERFECT] = {
        reliabilityBoostMin = 0.08,
        reliabilityBoostMax = 0.15,
        functionRestoreMin = 0.20,
        functionRestoreMax = 0.30,
        messageKey = "usedplus_fsk_result_perfect"
    },
    [DiagnosisData.OUTCOME_GOOD] = {
        reliabilityBoostMin = 0.04,
        reliabilityBoostMax = 0.08,
        functionRestoreMin = 0.10,
        functionRestoreMax = 0.20,
        messageKey = "usedplus_fsk_result_good"
    },
    [DiagnosisData.OUTCOME_POOR] = {
        reliabilityBoostMin = 0.01,
        reliabilityBoostMax = 0.03,
        functionRestoreMin = 0.05,
        functionRestoreMax = 0.10,
        messageKey = "usedplus_fsk_result_poor"
    }
}

--[[
    Kit tier modifiers
    successBonus: Added to base success (not used in diagnosis mode)
    reliabilityMultiplier: Multiplies the reliability boost
    price: Store price
]]
DiagnosisData.KIT_TIERS = {
    basic = {
        name = "usedplus_fsk_kit_basic",
        reliabilityMultiplier = 1.0,
        functionMultiplier = 1.0,
        price = 500
    },
    professional = {
        name = "usedplus_fsk_kit_professional",
        reliabilityMultiplier = 1.25,
        functionMultiplier = 1.25,
        price = 1500
    },
    master = {
        name = "usedplus_fsk_kit_master",
        reliabilityMultiplier = 1.5,
        functionMultiplier = 1.5,
        price = 3000
    }
}

--[[
    ENGINE DIAGNOSIS SCENARIOS
    Each scenario has:
    - id: Unique identifier
    - symptoms: Array of symptom translation keys
    - correctDiagnosis: The correct answer index (1-4)
    - diagnoses: Array of 4 possible diagnosis options
]]
DiagnosisData.ENGINE_SCENARIOS = {
    {
        id = "engine_air_filter",
        symptoms = {
            "usedplus_fsk_symptom_engine_misfiring",
            "usedplus_fsk_symptom_engine_black_smoke",
            "usedplus_fsk_symptom_engine_power_loss_gradual"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_fsk_diag_fuel_filter",
            "usedplus_fsk_diag_spark_plugs",
            "usedplus_fsk_diag_air_filter",
            "usedplus_fsk_diag_timing_belt"
        },
        repairDescription = "usedplus_fsk_repair_air_filter"
    },
    {
        id = "engine_fuel_filter",
        symptoms = {
            "usedplus_fsk_symptom_engine_hard_start",
            "usedplus_fsk_symptom_engine_stalling",
            "usedplus_fsk_symptom_engine_sputtering"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_fsk_diag_fuel_filter",
            "usedplus_fsk_diag_spark_plugs",
            "usedplus_fsk_diag_air_filter",
            "usedplus_fsk_diag_timing_belt"
        },
        repairDescription = "usedplus_fsk_repair_fuel_filter"
    },
    {
        id = "engine_spark_plugs",
        symptoms = {
            "usedplus_fsk_symptom_engine_rough_idle",
            "usedplus_fsk_symptom_engine_misfiring_high_rpm",
            "usedplus_fsk_symptom_engine_poor_acceleration"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_fsk_diag_fuel_filter",
            "usedplus_fsk_diag_spark_plugs",
            "usedplus_fsk_diag_air_filter",
            "usedplus_fsk_diag_timing_belt"
        },
        repairDescription = "usedplus_fsk_repair_spark_plugs"
    },
    {
        id = "engine_timing",
        symptoms = {
            "usedplus_fsk_symptom_engine_backfiring",
            "usedplus_fsk_symptom_engine_wont_start",
            "usedplus_fsk_symptom_engine_timing_off"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_fsk_diag_fuel_filter",
            "usedplus_fsk_diag_spark_plugs",
            "usedplus_fsk_diag_air_filter",
            "usedplus_fsk_diag_timing_belt"
        },
        repairDescription = "usedplus_fsk_repair_timing"
    }
}

--[[
    ELECTRICAL DIAGNOSIS SCENARIOS
]]
DiagnosisData.ELECTRICAL_SCENARIOS = {
    {
        id = "electrical_battery",
        symptoms = {
            "usedplus_fsk_symptom_elec_no_crank",
            "usedplus_fsk_symptom_elec_no_lights",
            "usedplus_fsk_symptom_elec_clicking"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_fsk_diag_battery",
            "usedplus_fsk_diag_fuse",
            "usedplus_fsk_diag_alternator",
            "usedplus_fsk_diag_wiring"
        },
        repairDescription = "usedplus_fsk_repair_battery"
    },
    {
        id = "electrical_fuse",
        symptoms = {
            "usedplus_fsk_symptom_elec_random_shutdowns",
            "usedplus_fsk_symptom_elec_specific_systems_fail",
            "usedplus_fsk_symptom_elec_partial_power"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_fsk_diag_battery",
            "usedplus_fsk_diag_fuse",
            "usedplus_fsk_diag_alternator",
            "usedplus_fsk_diag_wiring"
        },
        repairDescription = "usedplus_fsk_repair_fuse"
    },
    {
        id = "electrical_alternator",
        symptoms = {
            "usedplus_fsk_symptom_elec_starts_then_dies",
            "usedplus_fsk_symptom_elec_dim_lights",
            "usedplus_fsk_symptom_elec_battery_warning"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_fsk_diag_battery",
            "usedplus_fsk_diag_fuse",
            "usedplus_fsk_diag_alternator",
            "usedplus_fsk_diag_wiring"
        },
        repairDescription = "usedplus_fsk_repair_alternator"
    },
    {
        id = "electrical_wiring",
        symptoms = {
            "usedplus_fsk_symptom_elec_intermittent",
            "usedplus_fsk_symptom_elec_works_when_wiggling",
            "usedplus_fsk_symptom_elec_flickering"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_fsk_diag_battery",
            "usedplus_fsk_diag_fuse",
            "usedplus_fsk_diag_alternator",
            "usedplus_fsk_diag_wiring"
        },
        repairDescription = "usedplus_fsk_repair_wiring"
    }
}

--[[
    HYDRAULIC DIAGNOSIS SCENARIOS
]]
DiagnosisData.HYDRAULIC_SCENARIOS = {
    {
        id = "hydraulic_fluid",
        symptoms = {
            "usedplus_fsk_symptom_hyd_slow_response",
            "usedplus_fsk_symptom_hyd_weak_lift",
            "usedplus_fsk_symptom_hyd_low_pressure"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_fsk_diag_hyd_fluid",
            "usedplus_fsk_diag_hyd_air",
            "usedplus_fsk_diag_hyd_pump",
            "usedplus_fsk_diag_hyd_seals"
        },
        repairDescription = "usedplus_fsk_repair_hyd_fluid"
    },
    {
        id = "hydraulic_air",
        symptoms = {
            "usedplus_fsk_symptom_hyd_jerky",
            "usedplus_fsk_symptom_hyd_spongy",
            "usedplus_fsk_symptom_hyd_inconsistent"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_fsk_diag_hyd_fluid",
            "usedplus_fsk_diag_hyd_air",
            "usedplus_fsk_diag_hyd_pump",
            "usedplus_fsk_diag_hyd_seals"
        },
        repairDescription = "usedplus_fsk_repair_hyd_bleed"
    },
    {
        id = "hydraulic_pump",
        symptoms = {
            "usedplus_fsk_symptom_hyd_grinding",
            "usedplus_fsk_symptom_hyd_overheating",
            "usedplus_fsk_symptom_hyd_whining"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_fsk_diag_hyd_fluid",
            "usedplus_fsk_diag_hyd_air",
            "usedplus_fsk_diag_hyd_pump",
            "usedplus_fsk_diag_hyd_seals"
        },
        repairDescription = "usedplus_fsk_repair_hyd_pump"
    },
    {
        id = "hydraulic_seals",
        symptoms = {
            "usedplus_fsk_symptom_hyd_visible_leak",
            "usedplus_fsk_symptom_hyd_oil_spots",
            "usedplus_fsk_symptom_hyd_pressure_drop"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_fsk_diag_hyd_fluid",
            "usedplus_fsk_diag_hyd_air",
            "usedplus_fsk_diag_hyd_pump",
            "usedplus_fsk_diag_hyd_seals"
        },
        repairDescription = "usedplus_fsk_repair_hyd_seals"
    }
}

--[[
    TIRE REPAIR OPTIONS
    Simpler than system diagnosis - just choose repair method
]]
DiagnosisData.TIRE_REPAIRS = {
    patch = {
        name = "usedplus_fsk_tire_patch",
        description = "usedplus_fsk_tire_patch_desc",
        conditionRestore = 0.30,  -- Restore to 30% condition
        durabilityPenalty = 0.20  -- Tire wears 20% faster after patch
    },
    plug = {
        name = "usedplus_fsk_tire_plug",
        description = "usedplus_fsk_tire_plug_desc",
        conditionRestore = 0.50,  -- Restore to 50% condition
        durabilityPenalty = 0.10  -- Tire wears 10% faster after plug
    }
}

--[[
    Get a random scenario for a given system
    @param systemType string - SYSTEM_ENGINE, SYSTEM_ELECTRICAL, or SYSTEM_HYDRAULIC
    @return table - The scenario data
]]
function DiagnosisData.getRandomScenario(systemType)
    local scenarios
    if systemType == DiagnosisData.SYSTEM_ENGINE then
        scenarios = DiagnosisData.ENGINE_SCENARIOS
    elseif systemType == DiagnosisData.SYSTEM_ELECTRICAL then
        scenarios = DiagnosisData.ELECTRICAL_SCENARIOS
    elseif systemType == DiagnosisData.SYSTEM_HYDRAULIC then
        scenarios = DiagnosisData.HYDRAULIC_SCENARIOS
    else
        return nil
    end

    local index = math.random(1, #scenarios)
    return scenarios[index]
end

--[[
    Get scenario that matches the actual failed system's state
    Uses reliability to weight which scenario is most likely
    @param systemType string - The system type
    @param reliability number - Current reliability 0-1
    @return table - The scenario data
]]
function DiagnosisData.getScenarioForFailure(systemType, reliability)
    -- For now, just return random. Could weight by reliability in future
    return DiagnosisData.getRandomScenario(systemType)
end

--[[
    Calculate repair outcome based on player choices
    @param actualSystem string - The system that actually failed
    @param chosenSystem string - The system player chose to repair
    @param scenario table - The scenario being used
    @param chosenDiagnosis number - The diagnosis index player chose (1-4)
    @param kitTier string - "basic", "professional", or "master"
    @return table - {outcome, reliabilityBoost, functionRestore, message}
]]
function DiagnosisData.calculateOutcome(actualSystem, chosenSystem, scenario, chosenDiagnosis, kitTier)
    local tier = DiagnosisData.KIT_TIERS[kitTier] or DiagnosisData.KIT_TIERS.basic
    local outcome

    -- Determine outcome tier
    if chosenSystem ~= actualSystem then
        outcome = DiagnosisData.OUTCOME_POOR
    elseif chosenDiagnosis == scenario.correctDiagnosis then
        outcome = DiagnosisData.OUTCOME_PERFECT
    else
        outcome = DiagnosisData.OUTCOME_GOOD
    end

    local outcomeData = DiagnosisData.OUTCOMES[outcome]

    -- Calculate random values within range
    local reliabilityBoost = math.random() * (outcomeData.reliabilityBoostMax - outcomeData.reliabilityBoostMin) + outcomeData.reliabilityBoostMin
    local functionRestore = math.random() * (outcomeData.functionRestoreMax - outcomeData.functionRestoreMin) + outcomeData.functionRestoreMin

    -- Apply kit tier multipliers
    reliabilityBoost = reliabilityBoost * tier.reliabilityMultiplier
    functionRestore = functionRestore * tier.functionMultiplier

    -- Cap at reasonable maximums
    reliabilityBoost = math.min(reliabilityBoost, 0.25)
    functionRestore = math.min(functionRestore, 0.40)

    return {
        outcome = outcome,
        reliabilityBoost = reliabilityBoost,
        functionRestore = functionRestore,
        messageKey = outcomeData.messageKey,
        correctDiagnosis = scenario.correctDiagnosis,
        wasCorrectSystem = (chosenSystem == actualSystem),
        wasCorrectDiagnosis = (chosenDiagnosis == scenario.correctDiagnosis)
    }
end

--[[
    Calculate tire repair outcome
    @param repairType string - "patch" or "plug"
    @param kitTier string - Kit tier
    @return table - {conditionRestore, durabilityPenalty}
]]
function DiagnosisData.calculateTireOutcome(repairType, kitTier)
    local repair = DiagnosisData.TIRE_REPAIRS[repairType] or DiagnosisData.TIRE_REPAIRS.patch
    local tier = DiagnosisData.KIT_TIERS[kitTier] or DiagnosisData.KIT_TIERS.basic

    return {
        conditionRestore = repair.conditionRestore * tier.functionMultiplier,
        durabilityPenalty = repair.durabilityPenalty,
        repairType = repairType
    }
end

--[[
    SCANNER READOUT HINTS
    These appear in Step 1 to help the player deduce which system failed.
    Hints are designed to be interpretable but require thought:
    - ENGINE hints reference: powertrain, combustion, fuel, exhaust, P-codes
    - ELECTRICAL hints reference: voltage, signals, communication, B/U-codes
    - HYDRAULIC hints reference: pressure, implements, hitch, actuators, flow
]]
DiagnosisData.SYSTEM_HINTS = {
    [DiagnosisData.SYSTEM_ENGINE] = {
        "usedplus_fsk_hint_engine_dtc",           -- "DTC P0xxx: Powertrain fault codes stored"
        "usedplus_fsk_hint_engine_combustion",    -- "Irregular combustion cycle patterns logged"
        "usedplus_fsk_hint_engine_airfuel",       -- "Air-fuel mixture readings out of specification"
        "usedplus_fsk_hint_engine_exhaust",       -- "Exhaust gas sensor readings abnormal"
        "usedplus_fsk_hint_engine_throttle",      -- "Throttle response deviation detected"
        "usedplus_fsk_hint_engine_timing"         -- "Crankshaft timing variance recorded"
    },
    [DiagnosisData.SYSTEM_ELECTRICAL] = {
        "usedplus_fsk_hint_elec_dtc",             -- "DTC B/U codes: Network communication faults"
        "usedplus_fsk_hint_elec_voltage",         -- "Voltage regulation outside normal parameters"
        "usedplus_fsk_hint_elec_signal",          -- "Intermittent sensor signal dropouts detected"
        "usedplus_fsk_hint_elec_canbus",          -- "CAN bus communication errors logged"
        "usedplus_fsk_hint_elec_timeout",         -- "Module response timeouts recorded"
        "usedplus_fsk_hint_elec_ground"           -- "Ground fault indicators triggered"
    },
    [DiagnosisData.SYSTEM_HYDRAULIC] = {
        "usedplus_fsk_hint_hyd_response",         -- "Implement response time exceeds threshold"
        "usedplus_fsk_hint_hyd_pressure",         -- "Hydraulic pressure fluctuations detected"
        "usedplus_fsk_hint_hyd_hitch",            -- "Three-point hitch position sensor drift"
        "usedplus_fsk_hint_hyd_actuator",         -- "Actuator cycle time degradation noted"
        "usedplus_fsk_hint_hyd_flow",             -- "Flow rate irregularities in aux circuits"
        "usedplus_fsk_hint_hyd_temp"              -- "Hydraulic fluid temperature warnings logged"
    }
}

--[[
    Get random hints for a system to display in scanner readout
    @param systemType string - SYSTEM_ENGINE, SYSTEM_ELECTRICAL, or SYSTEM_HYDRAULIC
    @param count number - How many hints to return (default 2)
    @return table - Array of hint translation keys
]]
function DiagnosisData.getSystemHints(systemType, count)
    count = count or 2
    local hints = DiagnosisData.SYSTEM_HINTS[systemType]

    if hints == nil then
        return {}
    end

    -- Create a shuffled copy to pick random hints
    local available = {}
    for i, hint in ipairs(hints) do
        available[i] = hint
    end

    -- Fisher-Yates shuffle
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- Return first 'count' hints
    local result = {}
    for i = 1, math.min(count, #available) do
        result[i] = available[i]
    end

    return result
end

UsedPlus.logInfo("DiagnosisData loaded - Field Service Kit diagnosis system ready")
