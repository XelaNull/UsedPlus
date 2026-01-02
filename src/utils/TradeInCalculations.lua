--[[
    FS25_UsedPlus - Trade-In Calculations Utility

    Handles trade-in value calculations for vehicle purchases
    Trade-In is the LOWEST return option (instant disposal when buying)
    Value hierarchy: Trade-In < Local Agent < Regional Agent < National Agent

    Features:
    - Calculate trade-in value (50-65% of vanilla sell price - LOWEST return)
    - Condition impact: damage and wear reduce value further
    - Brand loyalty bonus (5% if same brand)
    - Display repair/paint condition levels
    - Integration with finance system

    Trade-In Formula:
    1. Get vanilla sell price
    2. Apply random base multiplier (50-65%)
    3. Apply condition multiplier (damage + wear impact)
    4. Apply brand bonus if applicable (+5%)
    5. Round to nearest $100

    Value Comparison (of vanilla sell price):
    - Trade-In: 50-65% (instant, worst return, only when purchasing)
    - Local Agent: 60-75% (1-2 months)
    - Regional Agent: 75-90% (2-4 months)
    - National Agent: 90-100% (3-6 months)
]]

TradeInCalculations = {}

--[[
    Configuration constants
    Trade-in gives LOWEST return - this is intentional
    Ranges overlap slightly with Local Agent for realism
]]

-- Trade-in base percentage RANGE (uses settings value as center)
-- This is intentionally the lowest return option
-- Settings baseTradeInPercent provides center, we add ±7.5% randomness
TradeInCalculations.TRADE_IN_RANGE = 0.075  -- ±7.5% around settings value

--[[
    Get trade-in percentage range from settings
    @return min, max percentages (as decimals)
]]
function TradeInCalculations.getTradeInRange()
    local settingsPercent = UsedPlusSettings and UsedPlusSettings:get("baseTradeInPercent") or 55
    local center = settingsPercent / 100  -- Convert to decimal (55 -> 0.55)
    local min = math.max(0.30, center - TradeInCalculations.TRADE_IN_RANGE)  -- Floor at 30%
    local max = math.min(0.80, center + TradeInCalculations.TRADE_IN_RANGE)  -- Cap at 80%
    return min, max
end

--[[
    Get brand loyalty bonus from settings
    @return bonus as decimal (e.g., 0.05 = 5%)
]]
function TradeInCalculations.getBrandLoyaltyBonus()
    local settingsBonus = UsedPlusSettings and UsedPlusSettings:get("brandLoyaltyBonus") or 5
    return settingsBonus / 100  -- Convert to decimal (5 -> 0.05)
end

-- Legacy constants (deprecated - use functions above)
TradeInCalculations.BASE_TRADE_IN_MIN = 0.50  -- Use getTradeInRange() instead
TradeInCalculations.BASE_TRADE_IN_MAX = 0.65  -- Use getTradeInRange() instead
TradeInCalculations.BRAND_LOYALTY_BONUS = 0.05  -- Use getBrandLoyaltyBonus() instead

-- Condition impact multipliers
-- Damage has bigger impact than cosmetic wear
TradeInCalculations.DAMAGE_IMPACT_MAX = 0.20   -- Up to 20% reduction for heavy damage
TradeInCalculations.WEAR_IMPACT_MAX = 0.10     -- Up to 10% reduction for heavy wear

-- Minimum trade-in value ($500)
TradeInCalculations.MIN_TRADE_IN_VALUE = 500

--[[
    Get vehicle's damage level (0.0 = perfect, 1.0 = destroyed)
    Checks multiple methods as different vehicle types may use different APIs
    @param vehicle - The vehicle to check
    @return damage level 0.0-1.0
]]
function TradeInCalculations.getVehicleDamage(vehicle)
    if vehicle == nil then
        return 0
    end

    -- Try different damage getter methods
    -- Method 1: getDamageAmount (most common)
    if vehicle.getDamageAmount then
        return vehicle:getDamageAmount() or 0
    end

    -- Method 2: Direct damage property
    if vehicle.damage then
        return vehicle.damage or 0
    end

    -- Method 3: Wearable specialization
    if vehicle.spec_wearable and vehicle.spec_wearable.damage then
        return vehicle.spec_wearable.damage or 0
    end

    -- No damage system found - assume perfect condition
    return 0
end

--[[
    Get vehicle's wear/paint level (0.0 = perfect, 1.0 = fully worn)
    This represents cosmetic wear (paint condition)
    @param vehicle - The vehicle to check
    @return wear level 0.0-1.0
]]
function TradeInCalculations.getVehicleWear(vehicle)
    if vehicle == nil then
        return 0
    end

    -- Try different wear getter methods
    -- Method 1: getWearTotalAmount (most common)
    if vehicle.getWearTotalAmount then
        return vehicle:getWearTotalAmount() or 0
    end

    -- Method 2: Direct wear property
    if vehicle.wear then
        return vehicle.wear or 0
    end

    -- Method 3: Wearable specialization
    if vehicle.spec_wearable and vehicle.spec_wearable.totalAmount then
        return vehicle.spec_wearable.totalAmount or 0
    end

    -- No wear system found - assume perfect condition
    return 0
end

--[[
    Get vehicle's operating hours
    @param vehicle - The vehicle to check
    @return operating hours
]]
function TradeInCalculations.getVehicleOperatingHours(vehicle)
    if vehicle == nil then
        return 0
    end

    -- Operating time is stored in milliseconds
    if vehicle.operatingTime then
        return math.floor(vehicle.operatingTime / (60 * 60 * 1000))  -- Convert ms to hours
    end

    return 0
end

--[[
    Calculate condition multiplier based on damage and wear
    Perfect condition = 1.0, heavily damaged/worn = lower
    @param damageLevel - Vehicle damage 0.0-1.0
    @param wearLevel - Vehicle wear 0.0-1.0
    @return condition multiplier 0.7-1.0
]]
function TradeInCalculations.calculateConditionMultiplier(damageLevel, wearLevel)
    -- Damage has more impact than cosmetic wear
    -- Damage: 0% damage = 1.0 multiplier, 100% damage = 0.8 multiplier (20% reduction)
    -- Wear: 0% wear = 1.0 multiplier, 100% wear = 0.9 multiplier (10% reduction)

    local damageMultiplier = 1.0 - (damageLevel * TradeInCalculations.DAMAGE_IMPACT_MAX)
    local wearMultiplier = 1.0 - (wearLevel * TradeInCalculations.WEAR_IMPACT_MAX)

    -- Combine multipliers (multiplicative, not additive)
    -- This means max reduction is ~28% (0.8 * 0.9 = 0.72)
    local conditionMultiplier = damageMultiplier * wearMultiplier

    -- Clamp to reasonable range
    return math.max(0.70, math.min(1.0, conditionMultiplier))
end

--[[
    Calculate maintenance history value modifier
    Integrates with UsedPlusMaintenance specialization
    Good reliability = slight bonus, poor reliability = penalty
    @param vehicle - The vehicle to check
    @return modifier (0.85-1.10), breakdown table
]]
function TradeInCalculations.getMaintenanceModifier(vehicle)
    -- Default: no modifier if UsedPlusMaintenance not available
    if UsedPlusMaintenance == nil or UsedPlusMaintenance.getReliabilityData == nil then
        return 1.0, nil
    end

    local reliabilityData = UsedPlusMaintenance.getReliabilityData(vehicle)
    if reliabilityData == nil then
        return 1.0, nil
    end

    local modifier = 1.0
    local breakdown = {
        avgReliability = reliabilityData.avgReliability,
        failureCount = reliabilityData.failureCount,
        repairCount = reliabilityData.repairCount,
        purchasedUsed = reliabilityData.purchasedUsed,
        wasInspected = reliabilityData.wasInspected,
    }

    -- Reliability factor: 0.6+ reliability = slight bonus, below = penalty
    -- avgReliability is 0.0-1.0
    local avgRel = reliabilityData.avgReliability or 1.0
    if avgRel >= 0.8 then
        -- Excellent reliability: up to +10% bonus
        modifier = modifier + ((avgRel - 0.8) * 0.5)  -- 0.8 rel = +0%, 1.0 rel = +10%
    elseif avgRel < 0.5 then
        -- Poor reliability: up to -15% penalty
        modifier = modifier - ((0.5 - avgRel) * 0.3)  -- 0.5 rel = -0%, 0.2 rel = -9%
    end

    -- Failure count penalty: each failure reduces value slightly
    -- Max penalty: 10% for 10+ failures
    local failures = reliabilityData.failureCount or 0
    local failurePenalty = math.min(failures * 0.01, 0.10)
    modifier = modifier - failurePenalty
    breakdown.failurePenalty = failurePenalty

    -- Repair count bonus: shows vehicle was maintained
    -- Small bonus: up to +5% for 5+ repairs
    local repairs = reliabilityData.repairCount or 0
    local repairBonus = math.min(repairs * 0.01, 0.05)
    modifier = modifier + repairBonus
    breakdown.repairBonus = repairBonus

    -- Was bought used: slightly lower value (history unknown)
    if reliabilityData.purchasedUsed then
        modifier = modifier - 0.02  -- -2% for used vehicles
        breakdown.usedPenalty = 0.02
    end

    -- Was inspected: buyers trust it more (+2%)
    if reliabilityData.wasInspected then
        modifier = modifier + 0.02
        breakdown.inspectedBonus = 0.02
    end

    -- Clamp to reasonable range
    modifier = math.max(0.85, math.min(1.10, modifier))
    breakdown.finalModifier = modifier

    UsedPlus.logTrace(string.format("Maintenance modifier for %s: %.2f (rel=%.2f, failures=%d, repairs=%d)",
        vehicle:getName(), modifier, avgRel, failures, repairs))

    return modifier, breakdown
end

--[[
    Calculate trade-in value for a vehicle
    This is the LOWEST return option - by design
    @param vehicle - The vehicle to trade in
    @param targetStoreItem - Optional: the store item being purchased (for brand bonus)
    @return tradeInValue, breakdown table
]]
function TradeInCalculations.calculateTradeInValue(vehicle, targetStoreItem)
    if vehicle == nil then
        return 0, nil
    end

    -- Get vehicle's current sell price (vanilla depreciated value)
    local vanillaSellPrice = 0
    if vehicle.getSellPrice then
        vanillaSellPrice = vehicle:getSellPrice()
    end

    if vanillaSellPrice <= 0 then
        return 0, nil
    end

    -- Get condition data
    local damageLevel = TradeInCalculations.getVehicleDamage(vehicle)
    local wearLevel = TradeInCalculations.getVehicleWear(vehicle)
    local operatingHours = TradeInCalculations.getVehicleOperatingHours(vehicle)

    -- Calculate condition multiplier
    local conditionMultiplier = TradeInCalculations.calculateConditionMultiplier(damageLevel, wearLevel)

    -- Get maintenance history modifier (Phase 5 integration)
    local maintenanceModifier, maintenanceBreakdown = TradeInCalculations.getMaintenanceModifier(vehicle)

    -- Generate random base trade-in percentage within range (from settings)
    -- This creates variation - sometimes you get a better deal, sometimes worse
    local tradeInMin, tradeInMax = TradeInCalculations.getTradeInRange()
    local basePercent = tradeInMin + (math.random() * (tradeInMax - tradeInMin))

    -- Calculate base value with condition and maintenance applied
    local baseValue = vanillaSellPrice * basePercent * conditionMultiplier * maintenanceModifier

    -- Check for brand loyalty bonus (from settings)
    local brandBonus = 0
    local brandBonusAmount = 0
    local isSameBrand = false

    if targetStoreItem then
        isSameBrand = TradeInCalculations.isSameBrand(vehicle, targetStoreItem)
        if isSameBrand then
            brandBonus = TradeInCalculations.getBrandLoyaltyBonus()
            brandBonusAmount = baseValue * brandBonus
        end
    end

    -- Calculate final value
    local finalValue = baseValue + brandBonusAmount

    -- Enforce minimum
    finalValue = math.max(TradeInCalculations.MIN_TRADE_IN_VALUE, finalValue)

    -- Round to nearest $100
    finalValue = math.floor(finalValue / 100) * 100

    -- Calculate what percentage of vanilla sell price this represents
    local percentOfVanilla = (finalValue / vanillaSellPrice) * 100

    -- Build comprehensive breakdown for UI display
    local breakdown = {
        -- Price data
        vanillaSellPrice = vanillaSellPrice,
        basePercent = math.floor(basePercent * 100),
        baseValue = baseValue,
        finalValue = finalValue,
        percentOfVanilla = math.floor(percentOfVanilla),

        -- Condition data
        damageLevel = damageLevel,
        wearLevel = wearLevel,
        operatingHours = operatingHours,
        conditionMultiplier = conditionMultiplier,
        repairPercent = math.floor((1 - damageLevel) * 100),  -- 100% = perfect
        paintPercent = math.floor((1 - wearLevel) * 100),     -- 100% = perfect
        conditionImpactPercent = math.floor((1 - conditionMultiplier) * 100),

        -- Brand bonus data
        isSameBrand = isSameBrand,
        brandBonusPercent = brandBonus * 100,
        brandBonusAmount = brandBonusAmount,

        -- Maintenance history data (Phase 5)
        maintenanceModifier = maintenanceModifier,
        maintenanceBreakdown = maintenanceBreakdown,
        maintenanceImpactPercent = math.floor((maintenanceModifier - 1.0) * 100),  -- +/- percentage
    }

    UsedPlus.logDebug(string.format("Trade-in calc: Vanilla=$%d, Base=%d%%, Condition=%.2f, Final=$%d (%.0f%% of vanilla)",
        vanillaSellPrice, breakdown.basePercent, conditionMultiplier, finalValue, percentOfVanilla))

    return finalValue, breakdown
end

--[[
    Check if vehicle and target store item are same brand
    @param vehicle - The vehicle being traded in
    @param targetStoreItem - The store item being purchased
    @return true if same brand
]]
function TradeInCalculations.isSameBrand(vehicle, targetStoreItem)
    if vehicle == nil or targetStoreItem == nil then
        return false
    end

    -- Get vehicle's store item
    local vehicleStoreItem = nil
    if vehicle.configFileName then
        vehicleStoreItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    end

    if vehicleStoreItem == nil then
        return false
    end

    -- Compare brands
    local vehicleBrand = vehicleStoreItem.brandIndex
    local targetBrand = targetStoreItem.brandIndex

    if vehicleBrand and targetBrand and vehicleBrand == targetBrand then
        return true
    end

    return false
end

--[[
    Get list of vehicles eligible for trade-in
    Only wholly-owned vehicles (not leased, not financed)
    @param farmId - The farm ID
    @return Array of {vehicle, tradeInValue, vehicleName, condition data...}
]]
function TradeInCalculations.getEligibleVehicles(farmId)
    local eligible = {}

    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return eligible
    end

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        -- Check ownership
        if vehicle.ownerFarmId == farmId then
            -- Check property state (must be owned, not leased)
            if vehicle.propertyState == VehiclePropertyState.OWNED then
                -- Check if not financed (has active finance deal)
                local isFinanced = TradeInCalculations.isVehicleFinanced(vehicle, farmId)

                if not isFinanced then
                    local tradeInValue, breakdown = TradeInCalculations.calculateTradeInValue(vehicle, nil)

                    if tradeInValue > 0 then
                        -- Get vehicle name
                        local vehicleName = "Unknown Vehicle"
                        local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
                        if storeItem then
                            vehicleName = storeItem.name
                        end

                        -- Include comprehensive data for UI
                        table.insert(eligible, {
                            vehicle = vehicle,
                            tradeInValue = tradeInValue,
                            vehicleName = vehicleName,
                            storeItem = storeItem,
                            breakdown = breakdown,
                            -- Condition data for display
                            damageLevel = breakdown and breakdown.damageLevel or 0,
                            wearLevel = breakdown and breakdown.wearLevel or 0,
                            repairPercent = breakdown and breakdown.repairPercent or 100,
                            paintPercent = breakdown and breakdown.paintPercent or 100,
                            operatingHours = breakdown and breakdown.operatingHours or 0,
                        })
                    end
                end
            end
        end
    end

    -- Sort by trade-in value (highest first)
    table.sort(eligible, function(a, b)
        return a.tradeInValue > b.tradeInValue
    end)

    return eligible
end

--[[
    Check if a vehicle has an active finance deal
    @param vehicle - The vehicle to check
    @param farmId - The farm ID
    @return true if vehicle is financed
]]
function TradeInCalculations.isVehicleFinanced(vehicle, farmId)
    if g_financeManager == nil then
        return false
    end

    local deals = g_financeManager:getDealsForFarm(farmId)
    if deals == nil then
        return false
    end

    -- Get vehicle's config filename for comparison
    local vehicleConfig = vehicle.configFileName

    for _, deal in ipairs(deals) do
        if deal.status == "active" and deal.dealType == 1 then  -- Vehicle finance
            if deal.itemId == vehicleConfig then
                return true
            end
        end
    end

    return false
end

--[[
    Execute trade-in transaction
    @param vehicle - The vehicle being traded in
    @param farmId - The farm ID
    @param tradeInValue - The agreed trade-in value
    @return true if successful
]]
function TradeInCalculations.executeTradeIn(vehicle, farmId, tradeInValue)
    if vehicle == nil or farmId == nil or tradeInValue <= 0 then
        return false
    end

    -- Remove the vehicle from the game
    if vehicle.delete then
        -- Credit the trade-in value to the farm
        -- Note: This is handled externally - the trade-in value reduces purchase price

        -- Delete the vehicle
        vehicle:delete()

        UsedPlus.logDebug(string.format("Trade-in executed: Vehicle removed, value $%d", tradeInValue))

        return true
    end

    return false
end

--[[
    Format trade-in breakdown for display
    @param breakdown - The breakdown table from calculateTradeInValue
    @return Formatted string for UI
]]
function TradeInCalculations.formatBreakdown(breakdown)
    if breakdown == nil then
        return "No trade-in available"
    end

    local lines = {}

    table.insert(lines, string.format("Vanilla Sell Value: %s", g_i18n:formatMoney(breakdown.vanillaSellPrice, 0, true, true)))
    table.insert(lines, string.format("Trade-In Rate: %d%%", breakdown.basePercent))
    table.insert(lines, "")
    table.insert(lines, string.format("Repair Condition: %d%%", breakdown.repairPercent))
    table.insert(lines, string.format("Paint Condition: %d%%", breakdown.paintPercent))

    if breakdown.conditionImpactPercent > 0 then
        table.insert(lines, string.format("Condition Penalty: -%d%%", breakdown.conditionImpactPercent))
    end

    if breakdown.isSameBrand then
        table.insert(lines, string.format("Brand Loyalty: +%d%%", breakdown.brandBonusPercent))
    end

    -- Maintenance history impact (Phase 5)
    if breakdown.maintenanceImpactPercent and breakdown.maintenanceImpactPercent ~= 0 then
        if breakdown.maintenanceImpactPercent > 0 then
            table.insert(lines, string.format("Maintenance History: +%d%%", breakdown.maintenanceImpactPercent))
        else
            table.insert(lines, string.format("Maintenance History: %d%%", breakdown.maintenanceImpactPercent))
        end
    end

    table.insert(lines, "---")
    table.insert(lines, string.format("Trade-In Value: %s", g_i18n:formatMoney(breakdown.finalValue, 0, true, true)))
    table.insert(lines, string.format("(%d%% of vanilla sell)", breakdown.percentOfVanilla))

    return table.concat(lines, "\n")
end

--[[
    Get condition rating text based on percentage
    @param percent - Condition percentage (0-100)
    @return rating text and color table {r, g, b, a}
]]
function TradeInCalculations.getConditionRating(percent)
    if percent >= 90 then
        return "Excellent", {0.2, 0.9, 0.2, 1}  -- Green
    elseif percent >= 70 then
        return "Good", {0.5, 0.9, 0.2, 1}       -- Yellow-green
    elseif percent >= 50 then
        return "Fair", {0.9, 0.7, 0.2, 1}       -- Orange
    elseif percent >= 30 then
        return "Poor", {0.9, 0.4, 0.2, 1}       -- Red-orange
    else
        return "Critical", {0.9, 0.2, 0.2, 1}   -- Red
    end
end

UsedPlus.logInfo("TradeInCalculations loaded (with condition-based pricing)")
