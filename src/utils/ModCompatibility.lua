--[[
    ModCompatibility.lua - Cross-Mod Integration Utility

    Detects and integrates with popular vehicle maintenance mods:
    - Real Vehicle Breakdowns (RVB) by MathiasHun
    - Use Up Your Tyres (UYT) by 50keda

    Philosophy: "Symptoms Before Failure"
    - UsedPlus provides the JOURNEY (gradual degradation, symptoms, warnings)
    - RVB/UYT provide the DESTINATION (catastrophic failures, visual wear)
    - Together they create a seamless realistic experience

    v1.8.0 - Initial implementation
]]

ModCompatibility = {}

-- Detection flags (set during init)
-- Integrated mods (enhanced cooperation)
ModCompatibility.rvbInstalled = false
ModCompatibility.uytInstalled = false

-- Formerly conflicting mods (now compatible)
ModCompatibility.advancedMaintenanceInstalled = false
ModCompatibility.hirePurchasingInstalled = false
ModCompatibility.buyUsedEquipmentInstalled = false
ModCompatibility.enhancedLoanSystemInstalled = false

ModCompatibility.initialized = false

-- RVB part key constants (must match RVB's definitions)
ModCompatibility.RVB_PARTS = {
    THERMOSTAT = "THERMOSTAT",
    LIGHTINGS = "LIGHTINGS",
    GLOWPLUG = "GLOWPLUG",
    WIPERS = "WIPERS",
    GENERATOR = "GENERATOR",
    ENGINE = "ENGINE",
    SELFSTARTER = "SELFSTARTER",
    BATTERY = "BATTERY",
    TIREFL = "TIREFL",
    TIREFR = "TIREFR",
    TIRERL = "TIRERL",
    TIRERR = "TIRERR",
}

--[[
    Initialize compatibility detection
    Called during mod load after other mods have registered
]]
function ModCompatibility.init()
    if ModCompatibility.initialized then return end

    -- ========================================================================
    -- INTEGRATED MODS (Enhanced cooperation)
    -- ========================================================================

    -- Detect Real Vehicle Breakdowns
    ModCompatibility.rvbInstalled = g_currentMission ~= nil and
                                    g_currentMission.vehicleBreakdowns ~= nil

    -- Detect Use Up Your Tyres
    ModCompatibility.uytInstalled = UseYourTyres ~= nil

    -- ========================================================================
    -- COMPATIBLE MODS (Feature deferral for coexistence)
    -- ========================================================================

    -- Detect AdvancedMaintenance - checks specialization registry
    ModCompatibility.advancedMaintenanceInstalled = ModCompatibility.checkAdvancedMaintenanceInstalled()

    -- Detect HirePurchasing - checks for HP-specific leaseDeals table
    -- Note: vanilla may have LeasingOptions but not leaseDeals
    ModCompatibility.hirePurchasingInstalled = g_currentMission ~= nil and
                                                g_currentMission.LeasingOptions ~= nil and
                                                g_currentMission.LeasingOptions.leaseDeals ~= nil

    -- Detect BuyUsedEquipment - checks for global namespace
    ModCompatibility.buyUsedEquipmentInstalled = BuyUsedEquipment ~= nil

    -- Detect EnhancedLoanSystem - checks for loan manager
    ModCompatibility.enhancedLoanSystemInstalled = g_els_loanManager ~= nil

    -- ========================================================================
    -- LOG DETECTION RESULTS
    -- ========================================================================

    UsedPlus.logInfo("=== ModCompatibility Detection Results ===")

    -- Integrated mods (full cooperation)
    if ModCompatibility.rvbInstalled then
        UsedPlus.logInfo("  [INTEGRATED] Real Vehicle Breakdowns DETECTED")
        UsedPlus.logInfo("    -> UsedPlus provides 'symptoms before failure'")
        UsedPlus.logInfo("    -> Final failure triggers deferred to RVB")
    end

    if ModCompatibility.uytInstalled then
        UsedPlus.logInfo("  [INTEGRATED] Use Up Your Tyres DETECTED")
        UsedPlus.logInfo("    -> Tire condition synced from UYT wear data")
        UsedPlus.logInfo("    -> Flat tire triggers deferred to UYT/RVB")
    end

    -- Compatible mods (feature deferral)
    if ModCompatibility.advancedMaintenanceInstalled then
        UsedPlus.logInfo("  [COMPATIBLE] AdvancedMaintenance DETECTED")
        UsedPlus.logInfo("    -> UsedPlus will chain to AM's engine damage checks")
        UsedPlus.logInfo("    -> Both maintenance systems work together")
    end

    if ModCompatibility.hirePurchasingInstalled then
        UsedPlus.logInfo("  [COMPATIBLE] HirePurchasing DETECTED")
        UsedPlus.logInfo("    -> UsedPlus Finance button HIDDEN (HP handles financing)")
        UsedPlus.logInfo("    -> UsedPlus retains: marketplace, maintenance, leasing")
    end

    if ModCompatibility.buyUsedEquipmentInstalled then
        UsedPlus.logInfo("  [COMPATIBLE] BuyUsedEquipment DETECTED")
        UsedPlus.logInfo("    -> UsedPlus Search button HIDDEN (BUE handles used search)")
        UsedPlus.logInfo("    -> UsedPlus retains: financing, maintenance, agent sales")
    end

    if ModCompatibility.enhancedLoanSystemInstalled then
        UsedPlus.logInfo("  [COMPATIBLE] EnhancedLoanSystem DETECTED")
        UsedPlus.logInfo("    -> UsedPlus loan features DISABLED (ELS handles loans)")
        UsedPlus.logInfo("    -> UsedPlus retains: marketplace, maintenance, leasing")
    end

    -- Special combined modes
    if ModCompatibility.rvbInstalled and ModCompatibility.uytInstalled then
        UsedPlus.logInfo("  [FULL STACK] RVB + UYT + UsedPlus = Best experience!")
    end

    -- No external mods
    local anyDetected = ModCompatibility.rvbInstalled or ModCompatibility.uytInstalled or
                        ModCompatibility.advancedMaintenanceInstalled or
                        ModCompatibility.hirePurchasingInstalled or
                        ModCompatibility.buyUsedEquipmentInstalled or
                        ModCompatibility.enhancedLoanSystemInstalled

    if not anyDetected then
        UsedPlus.logInfo("  No compatible mods detected - standalone mode")
    end

    UsedPlus.logInfo("==========================================")

    ModCompatibility.initialized = true
end

--[[
    Check if AdvancedMaintenance is installed
    Uses specialization registry lookup since AM uses custom specialization
]]
function ModCompatibility.checkAdvancedMaintenanceInstalled()
    -- AdvancedMaintenance adds a specialization to vehicles
    -- We check if the specialization exists in the registry
    if g_specializationManager then
        local amSpec = g_specializationManager:getSpecializationByName("advancedMaintenance")
        if amSpec then
            return true
        end
    end

    -- Also check for the global AdvancedMaintenance table
    if AdvancedMaintenance ~= nil then
        return true
    end

    return false
end

--============================================================================
-- RVB INTEGRATION FUNCTIONS
--============================================================================

--[[
    Get RVB part remaining life as a 0-1 percentage
    @param vehicle - The vehicle to check
    @param partKey - RVB part key (e.g., "ENGINE", "BATTERY")
    @return number - 0.0 (exhausted) to 1.0 (new)
]]
function ModCompatibility.getRVBPartLife(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return 1.0 end
    if vehicle == nil then return 1.0 end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return 1.0  -- Default to healthy if no data
    end

    local part = rvb.parts[partKey]
    if not part.tmp_lifetime or part.tmp_lifetime <= 0 then
        return 1.0
    end

    -- operatingHours / lifetime = used percentage
    -- 1 - usedPercent = remaining life
    local usedPercent = (part.operatingHours or 0) / part.tmp_lifetime
    return math.max(0, math.min(1, 1 - usedPercent))
end

--[[
    Check if an RVB part is in fault state
    @param vehicle - The vehicle to check
    @param partKey - RVB part key
    @return boolean - true if part has failed
]]
function ModCompatibility.isRVBPartFailed(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return false end
    if vehicle == nil then return false end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return false
    end

    local part = rvb.parts[partKey]
    return part.fault ~= nil and part.fault ~= "empty"
end

--[[
    Check if an RVB part is in prefault state (warning state before failure)
    @param vehicle - The vehicle to check
    @param partKey - RVB part key
    @return boolean - true if part is in prefault
]]
function ModCompatibility.isRVBPartPrefault(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return false end
    if vehicle == nil then return false end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return false
    end

    local part = rvb.parts[partKey]
    return part.prefault ~= nil and part.prefault ~= "empty"
end

--[[
    Get engine reliability - uses RVB if available, otherwise native UsedPlus
    Combines ENGINE + THERMOSTAT health from RVB

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getEngineReliability(vehicle)
    if ModCompatibility.rvbInstalled and vehicle.spec_faultData then
        -- Derive from RVB parts
        local engineLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.ENGINE)
        local thermoLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.THERMOSTAT)
        return (engineLife + thermoLife) / 2
    end

    -- Fall back to native UsedPlus reliability
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.engineReliability or 1.0
    end

    return 1.0
end

--[[
    Get electrical reliability - uses RVB if available, otherwise native UsedPlus
    Combines GENERATOR + BATTERY + SELFSTARTER + GLOWPLUG health from RVB

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getElectricalReliability(vehicle)
    if ModCompatibility.rvbInstalled and vehicle.spec_faultData then
        -- Derive from RVB parts
        local genLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.GENERATOR)
        local batLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.BATTERY)
        local startLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.SELFSTARTER)
        local glowLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.GLOWPLUG)
        return (genLife + batLife + startLife + glowLife) / 4
    end

    -- Fall back to native UsedPlus reliability
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.electricalReliability or 1.0
    end

    return 1.0
end

--[[
    Get hydraulic reliability - ALWAYS uses native UsedPlus
    RVB doesn't track hydraulic systems, this is unique to UsedPlus!

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getHydraulicReliability(vehicle)
    -- Always native - RVB doesn't have hydraulics
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.hydraulicReliability or 1.0
    end

    return 1.0
end

--[[
    Get combined overall reliability for resale value calculations
    Uses weighted average of all systems

    @param vehicle - The vehicle to check
    @return number - 0.0 to 1.0
]]
function ModCompatibility.getOverallReliability(vehicle)
    local engine = ModCompatibility.getEngineReliability(vehicle)
    local electrical = ModCompatibility.getElectricalReliability(vehicle)
    local hydraulic = ModCompatibility.getHydraulicReliability(vehicle)

    -- Weighted: engine most important, then hydraulic, then electrical
    return (engine * 0.4) + (hydraulic * 0.35) + (electrical * 0.25)
end

--[[
    Check if engine failure triggers should be deferred to RVB
    @return boolean - true if RVB should handle engine failures
]]
function ModCompatibility.shouldDeferEngineFailure()
    return ModCompatibility.rvbInstalled
end

--[[
    Check if electrical failure triggers should be deferred to RVB
    @return boolean - true if RVB should handle electrical failures
]]
function ModCompatibility.shouldDeferElectricalFailure()
    return ModCompatibility.rvbInstalled
end

--[[
    Check if flat tire triggers should be deferred to RVB/UYT
    @return boolean - true if other mods should handle tire failures
]]
function ModCompatibility.shouldDeferTireFailure()
    return ModCompatibility.rvbInstalled or ModCompatibility.uytInstalled
end

--============================================================================
-- UYT INTEGRATION FUNCTIONS
--============================================================================

--[[
    Get tire wear from UYT for a specific wheel
    @param vehicle - The vehicle to check
    @param wheelIndex - 1-based wheel index
    @return number - 0.0 (new) to 1.0 (worn out)
]]
function ModCompatibility.getUYTTireWear(vehicle, wheelIndex)
    if not ModCompatibility.uytInstalled then return 0 end
    if not UseYourTyres then return 0 end
    if vehicle == nil or not vehicle.spec_wheels then return 0 end

    local wheel = vehicle.spec_wheels.wheels[wheelIndex]
    if wheel and UseYourTyres.getWearAmount then
        return UseYourTyres.getWearAmount(wheel) or 0
    end

    return 0
end

--[[
    Get tire condition from UYT (inverted from wear)
    @param vehicle - The vehicle to check
    @param wheelIndex - 1-based wheel index
    @return number - 0.0 (worn out) to 1.0 (new)
]]
function ModCompatibility.getUYTTireCondition(vehicle, wheelIndex)
    local wear = ModCompatibility.getUYTTireWear(vehicle, wheelIndex)
    return 1.0 - wear
end

--[[
    Get maximum tire wear across all wheels
    @param vehicle - The vehicle to check
    @return number - 0.0 to 1.0 (worst tire)
]]
function ModCompatibility.getUYTMaxTireWear(vehicle)
    if not ModCompatibility.uytInstalled then return 0 end
    if vehicle == nil or not vehicle.spec_wheels then return 0 end

    local maxWear = 0
    for i, _ in ipairs(vehicle.spec_wheels.wheels) do
        local wear = ModCompatibility.getUYTTireWear(vehicle, i)
        maxWear = math.max(maxWear, wear)
    end

    return maxWear
end

--[[
    Get UYT tire replacement cost for vehicle
    @param vehicle - The vehicle to check
    @return number - Cost in dollars, or 0 if UYT not installed
]]
function ModCompatibility.getUYTReplacementCost(vehicle)
    if not ModCompatibility.uytInstalled then return 0 end
    if not UseYourTyres or not UseYourTyres.getTyresPrice then return 0 end

    return UseYourTyres.getTyresPrice(vehicle) or 0
end

--[[
    Check if vehicle has UYT-compatible tires
    @param vehicle - The vehicle to check
    @return boolean
]]
function ModCompatibility.hasUYTTires(vehicle)
    if not ModCompatibility.uytInstalled then return false end
    return vehicle.uytHasTyres == true
end

--============================================================================
-- SYNC FUNCTIONS - Update UsedPlus data from external sources
--============================================================================

--[[
    Sync UsedPlus tire condition from UYT wear data
    Called periodically to keep our tire condition in sync with UYT

    @param vehicle - The vehicle to sync
]]
function ModCompatibility.syncTireConditionFromUYT(vehicle)
    if not ModCompatibility.uytInstalled then return end
    if not ModCompatibility.hasUYTTires(vehicle) then return end

    local spec = vehicle.spec_usedPlusMaintenance
    if not spec or not spec.tires then return end

    local wheelCount = 0
    if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
        wheelCount = #vehicle.spec_wheels.wheels
    end

    -- Sync each tire's condition from UYT wear
    for i = 1, math.min(wheelCount, #spec.tires) do
        local uytCondition = ModCompatibility.getUYTTireCondition(vehicle, i)
        -- Only update if UYT has valid data
        if uytCondition < 1.0 or spec.tires[i].condition > uytCondition then
            spec.tires[i].condition = uytCondition
        end
    end
end

--[[
    Sync UsedPlus reliability from RVB part health
    Called periodically to update our reliability values

    @param vehicle - The vehicle to sync
]]
function ModCompatibility.syncReliabilityFromRVB(vehicle)
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    -- Update engine reliability from RVB
    spec.engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Update electrical reliability from RVB
    spec.electricalReliability = ModCompatibility.getElectricalReliability(vehicle)

    -- Note: hydraulicReliability stays native - RVB doesn't track it
end

--============================================================================
-- OBD FIELD SERVICE KIT INTEGRATION
--============================================================================

--[[
    Get diagnostic data for OBD Field Service Kit
    Returns combined data from RVB (if available) and UsedPlus

    @param vehicle - The vehicle to diagnose
    @return table - Diagnostic data for display
]]
function ModCompatibility.getOBDDiagnosticData(vehicle)
    local data = {
        hasRVBData = ModCompatibility.rvbInstalled and vehicle.spec_faultData ~= nil,
        hasUYTData = ModCompatibility.uytInstalled and ModCompatibility.hasUYTTires(vehicle),

        -- Engine system
        engine = {
            reliability = ModCompatibility.getEngineReliability(vehicle),
            source = ModCompatibility.rvbInstalled and "RVB" or "UsedPlus",
            rvbParts = {},
        },

        -- Electrical system
        electrical = {
            reliability = ModCompatibility.getElectricalReliability(vehicle),
            source = ModCompatibility.rvbInstalled and "RVB" or "UsedPlus",
            rvbParts = {},
        },

        -- Hydraulic system (always UsedPlus)
        hydraulic = {
            reliability = ModCompatibility.getHydraulicReliability(vehicle),
            source = "UsedPlus",
        },

        -- Tire data
        tires = {},
    }

    -- Add RVB part details if available
    if data.hasRVBData then
        -- Engine parts
        data.engine.rvbParts = {
            { name = "Engine", life = ModCompatibility.getRVBPartLife(vehicle, "ENGINE"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "ENGINE"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "ENGINE") },
            { name = "Thermostat", life = ModCompatibility.getRVBPartLife(vehicle, "THERMOSTAT"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "THERMOSTAT"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "THERMOSTAT") },
        }

        -- Electrical parts
        data.electrical.rvbParts = {
            { name = "Generator", life = ModCompatibility.getRVBPartLife(vehicle, "GENERATOR"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "GENERATOR"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "GENERATOR") },
            { name = "Battery", life = ModCompatibility.getRVBPartLife(vehicle, "BATTERY"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "BATTERY"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "BATTERY") },
            { name = "Starter", life = ModCompatibility.getRVBPartLife(vehicle, "SELFSTARTER"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "SELFSTARTER"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "SELFSTARTER") },
            { name = "Glow Plug", life = ModCompatibility.getRVBPartLife(vehicle, "GLOWPLUG"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "GLOWPLUG"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "GLOWPLUG") },
        }
    end

    -- Add tire data
    if data.hasUYTData then
        local wheelCount = vehicle.spec_wheels and #vehicle.spec_wheels.wheels or 0
        for i = 1, wheelCount do
            table.insert(data.tires, {
                index = i,
                wear = ModCompatibility.getUYTTireWear(vehicle, i),
                condition = ModCompatibility.getUYTTireCondition(vehicle, i),
                source = "UYT",
            })
        end
    else
        -- Use UsedPlus native tire data
        local spec = vehicle.spec_usedPlusMaintenance
        if spec and spec.tires then
            for i, tire in ipairs(spec.tires) do
                table.insert(data.tires, {
                    index = i,
                    wear = 1 - (tire.condition or 1),
                    condition = tire.condition or 1,
                    tier = tire.tier or "Economy",
                    source = "UsedPlus",
                })
            end
        end
    end

    return data
end

--[[
    Apply OBD repair to RVB parts
    Called when Field Service Kit successfully diagnoses and repairs

    @param vehicle - The vehicle to repair
    @param system - "engine" or "electrical"
    @param hoursReduction - How many operating hours to reduce
    @param clearFaults - Whether to clear fault states
]]
function ModCompatibility.applyOBDRepairToRVB(vehicle, system, hoursReduction, clearFaults)
    if not ModCompatibility.rvbInstalled then return end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then return end

    local partsToFix = {}
    if system == "engine" then
        partsToFix = { "ENGINE", "THERMOSTAT" }
    elseif system == "electrical" then
        partsToFix = { "GENERATOR", "BATTERY", "SELFSTARTER", "GLOWPLUG" }
    end

    for _, partKey in ipairs(partsToFix) do
        local part = rvb.parts[partKey]
        if part then
            -- Reduce operating hours (making the part "younger")
            part.operatingHours = math.max(0, (part.operatingHours or 0) - hoursReduction)

            -- Clear fault states if requested (perfect diagnosis)
            if clearFaults then
                part.prefault = "empty"
                part.fault = "empty"
                part.damaged = false
            end

            UsedPlus.logInfoDebug(string.format(
                "OBD repair applied to RVB %s: hours reduced by %d, faults cleared: %s",
                partKey, hoursReduction, tostring(clearFaults)))
        end
    end
end

--============================================================================
-- FEATURE AVAILABILITY QUERIES
-- Used by UI and managers to determine which features to enable/show
--============================================================================

--[[
    Should UsedPlus show the Finance button in shop?
    @return boolean - false if HirePurchasing handles financing
]]
function ModCompatibility.shouldShowFinanceButton()
    return not ModCompatibility.hirePurchasingInstalled
end

--[[
    Should UsedPlus show the Used Search button in shop?
    @return boolean - false if BuyUsedEquipment handles used search
]]
function ModCompatibility.shouldShowSearchButton()
    return not ModCompatibility.buyUsedEquipmentInstalled
end

--[[
    Should UsedPlus enable its loan/financing system?
    @return boolean - false if EnhancedLoanSystem handles loans
]]
function ModCompatibility.shouldEnableLoanSystem()
    return not ModCompatibility.enhancedLoanSystemInstalled
end

--[[
    Should UsedPlus show the "Take Loan" option in Finance Manager?
    @return boolean - false if ELS handles loans
]]
function ModCompatibility.shouldShowTakeLoanOption()
    return not ModCompatibility.enhancedLoanSystemInstalled
end

--[[
    Should UsedPlus initialize UsedVehicleManager?
    @return boolean - false if BuyUsedEquipment handles used search
]]
function ModCompatibility.shouldInitUsedVehicleManager()
    return not ModCompatibility.buyUsedEquipmentInstalled
end

--[[
    Should UsedPlus initialize FinanceManager?
    @return boolean - false if EnhancedLoanSystem handles loans
    Note: We still initialize for lease tracking even with ELS
]]
function ModCompatibility.shouldInitFinanceManager()
    -- Always initialize - we use it for leases and sales too
    -- But loan creation will be blocked
    return true
end

--[[
    Should UsedPlus chain to AdvancedMaintenance's damage check?
    @param vehicle - The vehicle to check
    @return boolean, function - Whether to chain, and the function to call
]]
function ModCompatibility.getAdvancedMaintenanceChain(vehicle)
    if not ModCompatibility.advancedMaintenanceInstalled then
        return false, nil
    end

    -- Try to get AM's damage check function
    if vehicle and vehicle.advancedMaintenanceCheckDamage then
        return true, vehicle.advancedMaintenanceCheckDamage
    end

    -- Alternative: check for the AM specialization
    if vehicle and vehicle.spec_advancedMaintenance then
        local spec = vehicle.spec_advancedMaintenance
        if spec and AdvancedMaintenance and AdvancedMaintenance.CheckDamage then
            return true, function()
                return AdvancedMaintenance.CheckDamage(vehicle)
            end
        end
    end

    return false, nil
end

--[[
    Get status string including all detected mods
]]
function ModCompatibility.getStatusString()
    local parts = {}

    -- Integrated mods
    if ModCompatibility.rvbInstalled then
        table.insert(parts, "RVB")
    end
    if ModCompatibility.uytInstalled then
        table.insert(parts, "UYT")
    end

    -- Compatible mods
    if ModCompatibility.advancedMaintenanceInstalled then
        table.insert(parts, "AM")
    end
    if ModCompatibility.hirePurchasingInstalled then
        table.insert(parts, "HP")
    end
    if ModCompatibility.buyUsedEquipmentInstalled then
        table.insert(parts, "BUE")
    end
    if ModCompatibility.enhancedLoanSystemInstalled then
        table.insert(parts, "ELS")
    end

    if #parts == 0 then
        return "Standalone mode (no compatible mods)"
    else
        return "Compatible mods: " .. table.concat(parts, " + ")
    end
end

--[[
    Get detailed feature status for debugging/display
    @return table with feature availability
]]
function ModCompatibility.getFeatureStatus()
    return {
        financeButton = ModCompatibility.shouldShowFinanceButton(),
        searchButton = ModCompatibility.shouldShowSearchButton(),
        loanSystem = ModCompatibility.shouldEnableLoanSystem(),
        takeLoanOption = ModCompatibility.shouldShowTakeLoanOption(),
        usedVehicleManager = ModCompatibility.shouldInitUsedVehicleManager(),
        financeManager = ModCompatibility.shouldInitFinanceManager(),
        -- Integrated features (always active with source attribution)
        engineSymptoms = true,  -- Always enabled, sources from RVB if available
        tireTracking = true,    -- Always enabled, syncs from UYT if available
        hydraulicDrift = true,  -- Unique to UsedPlus
        steeringPull = true,    -- Unique to UsedPlus
    }
end

--============================================================================
-- EXTERNAL MOD DATA ACCESS
-- Read loan/lease data from other mods for unified Finance Manager display
--============================================================================

--[[
    Get all active ELS loans for a farm
    @param farmId - Farm ID to get loans for
    @return array of pseudo-deal objects for Finance Manager display
]]
function ModCompatibility.getELSLoans(farmId)
    local loans = {}

    if not ModCompatibility.enhancedLoanSystemInstalled then
        return loans
    end

    -- Access ELS loan manager
    if g_els_loanManager and g_els_loanManager.currentLoans then
        local elsLoans = g_els_loanManager:currentLoans(farmId)
        if elsLoans then
            for i, loan in ipairs(elsLoans) do
                -- Create pseudo-deal object matching UsedPlus structure
                local monthlyPayment = 0
                if loan.calculateAnnuity then
                    monthlyPayment = loan:calculateAnnuity()
                end

                local totalAmount = 0
                if loan.calculateTotalAmount then
                    totalAmount = loan:calculateTotalAmount()
                end

                local pseudoDeal = {
                    id = "ELS_LOAN_" .. tostring(i),
                    dealType = 100,  -- Special type for ELS loans
                    itemName = "ELS Loan #" .. tostring(i),
                    currentBalance = loan.restAmount or loan.amount or 0,
                    originalAmount = loan.amount or 0,
                    monthlyPayment = monthlyPayment,
                    interestRate = loan.interest or 0,
                    termMonths = (loan.duration or 1) * 12,
                    monthsPaid = ((loan.duration or 1) * 12) - (loan.restDuration or 0),
                    remainingMonths = loan.restDuration or 0,
                    totalAmount = totalAmount,
                    status = "active",
                    isELSLoan = true,
                    elsLoanRef = loan,  -- Store reference for payoff
                    farmId = farmId,
                }

                table.insert(loans, pseudoDeal)
            end
        end
    end

    return loans
end

--[[
    Get all active HirePurchasing leases for a farm
    @param farmId - Farm ID to get leases for
    @return array of pseudo-deal objects for Finance Manager display
]]
function ModCompatibility.getHPLeases(farmId)
    local leases = {}

    if not ModCompatibility.hirePurchasingInstalled then
        return leases
    end

    -- Access HirePurchasing lease options
    if g_currentMission and g_currentMission.LeasingOptions and g_currentMission.LeasingOptions.leaseDeals then
        for i, deal in pairs(g_currentMission.LeasingOptions.leaseDeals) do
            if deal.farmId == farmId then
                -- Calculate monthly payment
                local monthlyPayment = 0
                if deal.getMonthlyPayment then
                    monthlyPayment = deal:getMonthlyPayment()
                end

                -- Calculate settlement cost
                local settlementCost = 0
                if deal.getSettlementCost then
                    settlementCost = deal:getSettlementCost()
                end

                -- Get vehicle name
                local vehicleName = "HP Lease"
                local vehicle = nil
                if deal.getVehicle then
                    vehicle = deal:getVehicle()
                    if vehicle and vehicle.getName then
                        vehicleName = vehicle:getName()
                    end
                end

                local remainingMonths = (deal.durationMonths or 0) - (deal.monthsPaid or 0)
                local remainingBalance = monthlyPayment * remainingMonths + (deal.finalFee or 0)

                local pseudoDeal = {
                    id = "HP_LEASE_" .. tostring(deal.id or i),
                    dealType = 101,  -- Special type for HP leases
                    itemName = vehicleName,
                    currentBalance = remainingBalance,
                    baseCost = deal.baseCost or 0,
                    deposit = deal.deposit or 0,
                    monthlyPayment = monthlyPayment,
                    termMonths = deal.durationMonths or 0,
                    monthsPaid = deal.monthsPaid or 0,
                    remainingMonths = remainingMonths,
                    finalFee = deal.finalFee or 0,
                    settlementCost = settlementCost,
                    status = "active",
                    isHPLease = true,
                    hpDealRef = deal,  -- Store reference for payoff
                    hpVehicle = vehicle,
                    farmId = farmId,
                }

                table.insert(leases, pseudoDeal)
            end
        end
    end

    return leases
end

--[[
    Make an early payment on an ELS loan
    @param pseudoDeal - The pseudo-deal object containing elsLoanRef
    @param amount - Amount to pay
    @return boolean - true if payment successful
]]
function ModCompatibility.payELSLoan(pseudoDeal, amount)
    if not pseudoDeal or not pseudoDeal.isELSLoan or not pseudoDeal.elsLoanRef then
        return false
    end

    local loan = pseudoDeal.elsLoanRef

    -- ELS uses specialRedemptionPayment for extra payments
    if g_els_loanManager and g_els_loanManager.specialRedemptionPayment then
        local success = g_els_loanManager:specialRedemptionPayment(loan, amount)
        if success then
            UsedPlus.logInfo(string.format("ELS loan payment: $%d applied", amount))
            return true
        end
    end

    return false
end

--[[
    Make a payment on an HP lease
    @param pseudoDeal - The pseudo-deal object containing hpDealRef
    @param amount - Amount to pay
    @return boolean - true if payment successful
]]
function ModCompatibility.payHPLease(pseudoDeal, amount)
    if not pseudoDeal or not pseudoDeal.isHPLease or not pseudoDeal.hpDealRef then
        return false
    end

    local deal = pseudoDeal.hpDealRef

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(pseudoDeal.farmId)
    if not farm or farm.money < amount then
        return false
    end

    -- Try to use HP's payment processing if available
    -- HP processes payments automatically on HOUR_CHANGED, but we can
    -- try to trigger a manual payment if the API is exposed
    if deal.processPayment then
        local success = deal:processPayment(amount)
        if success then
            UsedPlus.logInfo(string.format("HP lease payment processed: $%d", amount))
            return true
        end
    end

    -- Alternative: Check if LeasingOptions has a payment method
    if g_currentMission.LeasingOptions and g_currentMission.LeasingOptions.makePayment then
        local success = g_currentMission.LeasingOptions:makePayment(deal, amount)
        if success then
            UsedPlus.logInfo(string.format("HP lease payment via LeasingOptions: $%d", amount))
            return true
        end
    end

    -- HP doesn't expose a direct payment API
    -- Payments are handled automatically by HP on hour change
    UsedPlus.logInfo("HP lease payments are managed automatically by HirePurchasing mod")
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        "HP lease payments are automatic - managed by HirePurchasing"
    )

    return false
end

--[[
    Settle (pay off) an HP lease early
    @param pseudoDeal - The pseudo-deal object containing hpDealRef
    @return boolean - true if settlement successful
]]
function ModCompatibility.settleHPLease(pseudoDeal)
    if not pseudoDeal or not pseudoDeal.isHPLease or not pseudoDeal.hpDealRef then
        return false
    end

    local deal = pseudoDeal.hpDealRef
    local settlementCost = pseudoDeal.settlementCost or 0

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(pseudoDeal.farmId)
    if not farm or farm.money < settlementCost then
        return false
    end

    -- HP doesn't have a direct settlement API, but we can try:
    -- 1. Process remaining months rapidly
    -- 2. Or call any settlement function if available

    -- For now, we'll just display the settlement cost
    -- Full HP settlement would require HP mod to expose an API
    UsedPlus.logInfo(string.format("HP lease settlement would cost: $%d", settlementCost))

    -- Return false since we can't actually settle without HP API
    -- This is informational only until HP exposes settlement function
    return false
end

--[[
    Get total monthly obligations from external mods
    @param farmId - Farm ID
    @return number - Total monthly payment from ELS + HP
]]
function ModCompatibility.getExternalMonthlyObligations(farmId)
    local total = 0

    -- ELS loans
    local elsLoans = ModCompatibility.getELSLoans(farmId)
    for _, loan in ipairs(elsLoans) do
        total = total + (loan.monthlyPayment or 0)
    end

    -- HP leases
    local hpLeases = ModCompatibility.getHPLeases(farmId)
    for _, lease in ipairs(hpLeases) do
        total = total + (lease.monthlyPayment or 0)
    end

    return total
end

--[[
    Get total debt from external mods
    @param farmId - Farm ID
    @return number - Total debt from ELS + HP
]]
function ModCompatibility.getExternalTotalDebt(farmId)
    local total = 0

    -- ELS loans
    local elsLoans = ModCompatibility.getELSLoans(farmId)
    for _, loan in ipairs(elsLoans) do
        total = total + (loan.currentBalance or 0)
    end

    -- HP leases
    local hpLeases = ModCompatibility.getHPLeases(farmId)
    for _, lease in ipairs(hpLeases) do
        total = total + (lease.currentBalance or 0)
    end

    return total
end

--============================================================================
-- EMPLOYMENT SYSTEM INTEGRATION
--============================================================================

--[[
    Get total monthly employment wages
    @param playerId - Player user ID (not farm ID)
    @return number - Total monthly wages, 0 if Employment not installed
]]
function ModCompatibility.getEmploymentMonthlyCost(playerId)
    if not g_currentMission or not g_currentMission.employmentSystem then
        return 0
    end

    local employmentSystem = g_currentMission.employmentSystem
    if employmentSystem.getTotalWagesCost then
        return employmentSystem:getTotalWagesCost(playerId) or 0
    end

    return 0
end

--[[
    Get employee count
    @param playerId - Player user ID
    @return number - Total employees, 0 if Employment not installed
]]
function ModCompatibility.getEmployeeCount(playerId)
    if not g_currentMission or not g_currentMission.employmentSystem then
        return 0
    end

    local employmentSystem = g_currentMission.employmentSystem
    if employmentSystem.getEmployeeCount then
        return employmentSystem:getEmployeeCount(playerId) or 0
    end

    return 0
end

--============================================================================
-- FARMLAND ASSETS INTEGRATION
--============================================================================

--[[
    Get total farmland value owned by a farm
    @param farmId - Farm ID
    @return number - Total farmland value
]]
function ModCompatibility.getFarmlandValue(farmId)
    if not g_farmlandManager then
        return 0
    end

    local totalValue = 0

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            totalValue = totalValue + (farmland.price or 0)
        end
    end

    return totalValue
end

--[[
    Get farmland count owned by a farm
    @param farmId - Farm ID
    @return number - Number of farmland parcels owned
]]
function ModCompatibility.getFarmlandCount(farmId)
    if not g_farmlandManager then
        return 0
    end

    local count = 0

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            count = count + 1
        end
    end

    return count
end

--============================================================================
-- USED VEHICLE SPAWN INITIALIZATION
-- Apply pre-generated RVB/UYT data to newly spawned used vehicles
--============================================================================

--[[
    Initialize RVB parts data on a spawned used vehicle
    Called after vehicle purchase to apply the inspection-revealed part conditions

    @param vehicle - The spawned vehicle
    @param rvbPartsData - Table with part data from listing.rvbPartsData
    @return boolean - true if initialization successful
]]
function ModCompatibility.initializeRVBPartsFromListing(vehicle, rvbPartsData)
    if not ModCompatibility.rvbInstalled then
        UsedPlus.logDebug("initializeRVBPartsFromListing: RVB not installed, skipping")
        return false
    end

    if vehicle == nil or rvbPartsData == nil then
        UsedPlus.logWarn("initializeRVBPartsFromListing: Invalid vehicle or data")
        return false
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        UsedPlus.logDebug("initializeRVBPartsFromListing: Vehicle has no RVB spec_faultData")
        return false
    end

    -- Apply each part's operating hours from the listing data
    -- RVB calculates life from: 1 - (operatingHours / tmp_lifetime)
    local partsApplied = 0

    for partKey, partData in pairs(rvbPartsData) do
        local rvbPart = rvb.parts[partKey]
        if rvbPart then
            -- Set the operating hours to match the pre-generated life
            -- If RVB's lifetime differs from ours, recalculate hours
            local rvbLifetime = rvbPart.tmp_lifetime or partData.lifetime or 1000
            local targetLife = partData.life or 1.0

            -- hours = (1 - life) * lifetime
            local targetHours = math.floor((1 - targetLife) * rvbLifetime)
            rvbPart.operatingHours = targetHours

            UsedPlus.logDebug(string.format("  RVB %s: Set hours to %d (life %.0f%%)",
                partKey, targetHours, targetLife * 100))

            partsApplied = partsApplied + 1
        end
    end

    UsedPlus.logInfo(string.format("initializeRVBPartsFromListing: Applied %d RVB parts to vehicle",
        partsApplied))

    return partsApplied > 0
end

--[[
    Initialize UYT tire conditions on a spawned used vehicle
    Called after vehicle purchase to apply the inspection-revealed tire conditions

    @param vehicle - The spawned vehicle
    @param tireConditions - Table with conditions from listing.tireConditions (FL, FR, RL, RR)
    @return boolean - true if initialization successful
]]
function ModCompatibility.initializeTiresFromListing(vehicle, tireConditions)
    if vehicle == nil or tireConditions == nil then
        UsedPlus.logWarn("initializeTiresFromListing: Invalid vehicle or data")
        return false
    end

    -- Apply to UsedPlus native tire tracking
    local spec = vehicle.spec_usedPlusMaintenance
    if spec and spec.tires then
        local tireMapping = { "FL", "FR", "RL", "RR" }
        for i, tireKey in ipairs(tireMapping) do
            if spec.tires[i] and tireConditions[tireKey] then
                spec.tires[i].condition = tireConditions[tireKey]
                UsedPlus.logDebug(string.format("  Tire %d (%s): Set condition to %.0f%%",
                    i, tireKey, tireConditions[tireKey] * 100))
            end
        end
    end

    -- If UYT is installed, try to set tire wear there too
    if ModCompatibility.uytInstalled and UseYourTyres then
        -- UYT stores wear (inverse of condition) per wheel
        if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
            local wheelCount = #vehicle.spec_wheels.wheels
            local tireKeys = { "FL", "FR", "RL", "RR" }

            for i = 1, math.min(wheelCount, 4) do
                local wheel = vehicle.spec_wheels.wheels[i]
                local condition = tireConditions[tireKeys[i]] or 1.0
                local wear = 1.0 - condition

                -- Try to set UYT wear if the API is available
                if wheel and UseYourTyres.setWearAmount then
                    UseYourTyres.setWearAmount(wheel, wear)
                    UsedPlus.logDebug(string.format("  UYT wheel %d: Set wear to %.0f%%",
                        i, wear * 100))
                end
            end
        end
    end

    UsedPlus.logInfo("initializeTiresFromListing: Applied tire conditions to vehicle")
    return true
end

--[[
    Apply all listing data to a spawned used vehicle
    Master function that applies RVB parts, tires, and UsedPlus maintenance data

    @param vehicle - The spawned vehicle
    @param listing - The listing data with rvbPartsData, tireConditions, usedPlusData
]]
function ModCompatibility.applyListingDataToVehicle(vehicle, listing)
    if vehicle == nil or listing == nil then
        UsedPlus.logWarn("applyListingDataToVehicle: Invalid vehicle or listing")
        return
    end

    UsedPlus.logInfo(string.format("Applying listing data to spawned vehicle: %s",
        listing.storeItemName or "Unknown"))

    -- v2.1.0: ALWAYS store the data on the vehicle for persistence and deferred sync
    -- This ensures the data survives saves and can be synced when RVB/UYT is installed later
    local spec = vehicle.spec_usedPlusMaintenance
    if spec and (listing.rvbPartsData or listing.tireConditions) then
        if vehicle.storeListingData then
            vehicle:storeListingData(listing.rvbPartsData, listing.tireConditions)
        else
            -- Fallback: directly store on spec
            if listing.rvbPartsData then
                spec.storedRvbPartsData = listing.rvbPartsData
                spec.rvbDataSynced = ModCompatibility.rvbInstalled
            end
            if listing.tireConditions then
                spec.storedTireConditions = listing.tireConditions
                spec.tireDataSynced = ModCompatibility.uytInstalled
            end
        end
        UsedPlus.logDebug("  Stored RVB/tire data on vehicle for persistence")
    end

    -- Apply RVB parts data if present (only if RVB installed)
    if listing.rvbPartsData then
        ModCompatibility.initializeRVBPartsFromListing(vehicle, listing.rvbPartsData)
    end

    -- Apply tire conditions if present
    if listing.tireConditions then
        ModCompatibility.initializeTiresFromListing(vehicle, listing.tireConditions)
    end

    -- Apply UsedPlus maintenance data if present
    if listing.usedPlusData then
        local spec = vehicle.spec_usedPlusMaintenance
        if spec then
            spec.engineReliability = listing.usedPlusData.engineReliability or spec.engineReliability
            spec.hydraulicReliability = listing.usedPlusData.hydraulicReliability or spec.hydraulicReliability
            spec.electricalReliability = listing.usedPlusData.electricalReliability or spec.electricalReliability
            spec.workhorseLemonScale = listing.usedPlusData.workhorseLemonScale or spec.workhorseLemonScale

            UsedPlus.logDebug(string.format("  UsedPlus maintenance: Engine=%.0f%%, Hydraulic=%.0f%%, Electrical=%.0f%%",
                spec.engineReliability * 100,
                spec.hydraulicReliability * 100,
                spec.electricalReliability * 100))
        end
    end

    -- Apply basic wear/damage from listing
    if listing.damage and listing.damage > 0 then
        if vehicle.setDamageAmount then
            vehicle:setDamageAmount(listing.damage)
            UsedPlus.logDebug(string.format("  Damage: Set to %.0f%%", listing.damage * 100))
        end
    end

    if listing.wear and listing.wear > 0 then
        if vehicle.setWearAmount then
            vehicle:setWearAmount(listing.wear)
            UsedPlus.logDebug(string.format("  Wear: Set to %.0f%%", listing.wear * 100))
        end
    end

    if listing.operatingHours and listing.operatingHours > 0 then
        if vehicle.setOperatingTime then
            -- FS25 uses milliseconds for operating time
            vehicle:setOperatingTime(listing.operatingHours * 3600 * 1000)
            UsedPlus.logDebug(string.format("  Operating hours: Set to %d", listing.operatingHours))
        end
    end

    UsedPlus.logInfo("applyListingDataToVehicle: Complete")

    -- v2.2.0: Apply DNA-based lifetime multiplier to RVB parts
    ModCompatibility.applyDNAToRVBLifetimes(vehicle)
end

--[[
    v2.2.0: Apply initial DNA-based lifetime multiplier to all RVB parts
    Called at vehicle purchase to set starting lifetimes based on workhorse/lemon DNA

    DNA 0.0 (lemon):     0.6x lifetime = starts weaker, breaks down faster
    DNA 0.5 (average):   1.0x lifetime = normal
    DNA 1.0 (workhorse): 1.4x lifetime = starts stronger, lasts longer

    @param vehicle - The vehicle to apply multiplier to
    @return boolean - True if applied successfully
]]
function ModCompatibility.applyDNAToRVBLifetimes(vehicle)
    if not vehicle then return false end
    if not vehicle.isServer then return false end
    if not ModCompatibility.rvbInstalled then return false end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return false end

    local dna = spec.workhorseLemonScale or 0.5
    local multiplier = 0.6 + (dna * 0.8)  -- Range: 0.6 to 1.4

    spec.rvbLifetimeMultiplier = multiplier
    spec.rvbLifetimesApplied = true

    for partKey, part in pairs(rvb.parts) do
        if part.tmp_lifetime then
            part.tmp_lifetime = part.tmp_lifetime * multiplier
        end
    end

    UsedPlus.logDebug(string.format("Applied DNA %.2f -> RVB lifetime multiplier %.2fx to %s",
        dna, multiplier, vehicle:getName()))
    return true
end

--[[
    v2.2.0: Apply repair degradation to RVB parts
    Called when RVB repair/service completes
    Lemons lose more lifetime per repair, workhorses lose little/none

    Legendary workhorses (DNA >= 0.90) are IMMUNE to repair degradation

    @param vehicle - The vehicle being repaired
]]
function ModCompatibility.applyRVBRepairDegradation(vehicle)
    if not vehicle then return end
    if not vehicle.isServer then return end
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Legendary workhorses (DNA >= 0.90) are immune to repair degradation
    if dna >= 0.90 then
        UsedPlus.logDebug(string.format("Legendary workhorse - no repair degradation for %s (DNA %.2f)",
            vehicle:getName(), dna))
        return
    end

    -- Degradation formula: 0-2% per repair based on DNA
    local degradation = (1 - dna) * 0.02

    for partKey, part in pairs(rvb.parts) do
        if part.tmp_lifetime then
            part.tmp_lifetime = part.tmp_lifetime * (1 - degradation)
        end
    end

    -- Track cumulative degradation
    spec.rvbTotalDegradation = (spec.rvbTotalDegradation or 0) + degradation
    spec.rvbRepairCount = (spec.rvbRepairCount or 0) + 1

    UsedPlus.logDebug(string.format("RVB repair degradation %.1f%% applied to %s (DNA %.2f, total %.1f%%)",
        degradation * 100, vehicle:getName(), dna, spec.rvbTotalDegradation * 100))
end

--[[
    v2.2.0: Apply breakdown degradation to RVB parts
    Called when RVB fault/breakdown occurs
    Everyone loses lifetime on breakdown, but lemons lose MORE

    Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage

    @param vehicle - The vehicle with the breakdown
    @param partKey - The RVB part that broke (ENGINE, BATTERY, etc.)
]]
function ModCompatibility.applyRVBBreakdownDegradation(vehicle, partKey)
    if not vehicle then return end
    if not vehicle.isServer then return end
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Base degradation: 3% for everyone
    -- Lemon bonus: 0-5% extra based on DNA
    local baseDegradation = 0.03
    local lemonBonus = (1 - dna) * 0.05
    local totalDegradation = baseDegradation + lemonBonus

    -- Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage
    if dna >= 0.95 then
        totalDegradation = totalDegradation * 0.3
    end

    -- Apply to the specific RVB part that broke down
    local part = rvb.parts[partKey]
    if part and part.tmp_lifetime then
        part.tmp_lifetime = part.tmp_lifetime * (1 - totalDegradation)
    end

    -- Track cumulative degradation
    spec.rvbTotalDegradation = (spec.rvbTotalDegradation or 0) + totalDegradation
    spec.rvbBreakdownCount = (spec.rvbBreakdownCount or 0) + 1

    UsedPlus.logDebug(string.format("RVB breakdown degradation %.1f%% on %s for %s (DNA %.2f)",
        totalDegradation * 100, partKey or "unknown", vehicle:getName(), dna))
end

UsedPlus.logInfo("ModCompatibility utility loaded (v2.2.0 - RVB/UYT Used Vehicle Integration + DNA Degradation)")
