--[[
    FS25_UsedPlus - Credit System (Consolidated)

    Credit scoring and history tracking for financial operations:
    - CreditScore: Calculate credit score, ratings, interest adjustments
    - CreditHistory: Track credit events, persist history, score adjustments

    Pattern from: EnhancedLoanSystem "Collateral-Based Credit System"

    REALISTIC CREDIT SCORE RANGE: 300-850 (like FICO)
    Formula: Base score of 650, adjusted by debt-to-asset ratio and payment history
    Tiers:
      Excellent: 750-850 (-1.5% interest)
      Good: 700-749 (-0.5% interest)
      Fair: 650-699 (+0.5% interest)
      Poor: 600-649 (+1.5% interest)
      Very Poor: 300-599 (+3.0% interest)
]]

--============================================================================
-- CREDIT SCORE
-- Calculate credit score from farm assets and debt
--============================================================================

CreditScore = {}

-- Realistic credit score bounds (like FICO)
CreditScore.MIN_SCORE = 300
CreditScore.MAX_SCORE = 850
CreditScore.BASE_SCORE = 500  -- LOWER starting point - must BUILD credit

--[[
    NEW Credit Score Calculation - Payment History is PRIMARY Factor

    Formula breakdown (mirrors real FICO weighting):
      Base Score: 500 (lower starting point)
      + Payment History Factor: up to +250 (45% weight) - PRIMARY!
      + Asset/Debt Factor: up to +75 (20% weight)
      + Cash Reserve Bonus: up to +25 (5% weight)
      = Total: 500 + 250 + 75 + 25 = 850 max

    Key principle: You CANNOT achieve excellent credit (750+) without
    a proven track record of on-time payments. Assets alone cap you at ~600.

    Score ranges:
      Excellent (750-850): Requires 24+ on-time payments, 12+ streak
      Good (700-749): Requires 6+ on-time payments, good history
      Fair (650-699): Some payment history OR good assets
      Poor (600-649): Limited/bad history OR high debt
      Very Poor (300-599): No history with debt OR missed payments
]]
function CreditScore.calculate(farmId)
    -- v1.4.0: Check settings system for credit feature toggle
    -- When credit system is disabled, return fixed starting score
    local creditEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Credit")
    if not creditEnabled then
        local startingScore = UsedPlusSettings and UsedPlusSettings:get("startingCreditScore") or 650
        return startingScore
    end

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logWarn("CreditScore.calculate - Farm not found: " .. tostring(farmId))
        return CreditScore.MIN_SCORE
    end

    -- Start with base score (500)
    local score = CreditScore.BASE_SCORE

    -- ============================================================
    -- FACTOR 1: Payment History (up to +250 points) - PRIMARY!
    -- This is now the MOST IMPORTANT factor
    -- ============================================================
    local historyScore = 0
    if PaymentTracker then
        historyScore = PaymentTracker.calculateHistoryScore(farmId)
    end
    score = score + historyScore

    -- ============================================================
    -- FACTOR 2: Asset/Debt Ratio (up to +75 points)
    -- Reduced weight - assets alone don't make good credit
    -- ============================================================
    local assets = CreditScore.calculateAssets(farm)
    local debt = CreditScore.calculateDebt(farm)
    local assetScore = 0

    if assets > 0 then
        local debtToAssetRatio = debt / assets

        if debtToAssetRatio == 0 then
            assetScore = 60           -- No debt = good, but not max
        elseif debtToAssetRatio < 0.2 then
            assetScore = 50           -- Very low debt
        elseif debtToAssetRatio < 0.4 then
            assetScore = 35           -- Low debt
        elseif debtToAssetRatio < 0.6 then
            assetScore = 20           -- Moderate debt
        elseif debtToAssetRatio < 0.8 then
            assetScore = 0            -- High debt - no bonus
        elseif debtToAssetRatio < 1.0 then
            assetScore = -25          -- Very high debt - penalty
        else
            assetScore = -50          -- Underwater - severe penalty
        end

        -- Small bonus for having substantial assets (shows stability)
        if assets > 500000 then
            assetScore = assetScore + 15
        elseif assets > 200000 then
            assetScore = assetScore + 10
        elseif assets > 100000 then
            assetScore = assetScore + 5
        end
    else
        -- No assets
        if debt > 0 then
            assetScore = -75  -- Debt with no assets is very bad
        else
            assetScore = 0    -- No assets, no debt - neutral
        end
    end

    -- Cap asset score contribution
    assetScore = math.max(-75, math.min(75, assetScore))
    score = score + assetScore

    -- ============================================================
    -- FACTOR 3: Cash Reserves (up to +25 points)
    -- Having cash shows financial stability
    -- ============================================================
    local cashScore = 0
    if farm.money > 100000 then
        cashScore = 25
    elseif farm.money > 50000 then
        cashScore = 15
    elseif farm.money > 25000 then
        cashScore = 5
    end
    score = score + cashScore

    -- ============================================================
    -- FACTOR 4: Clean Slate Bonus (up to +40 points)
    -- New farms with assets but no payment history get a modest boost
    -- "We'll give you a chance since you have collateral"
    -- This bonus disappears once you have ANY payment history
    -- ============================================================
    local stats = PaymentTracker and PaymentTracker.getStats(farmId) or { totalPayments = 0 }
    if stats.totalPayments == 0 and assets > 0 and debt == 0 then
        -- Clean slate: no history, have assets, no debt
        -- Scaled by asset value (more collateral = more trust)
        local cleanSlateBonus = 0
        if assets > 500000 then
            cleanSlateBonus = 40
        elseif assets > 200000 then
            cleanSlateBonus = 35
        elseif assets > 100000 then
            cleanSlateBonus = 30
        elseif assets > 50000 then
            cleanSlateBonus = 20
        end
        score = score + cleanSlateBonus
    end

    -- ============================================================
    -- QUALIFICATION CHECKS - Enforce tier requirements
    -- ============================================================

    -- Cannot reach "Excellent" (750+) without payment history qualification
    if PaymentTracker and not PaymentTracker.qualifiesForExcellent(farmId) then
        score = math.min(score, 749)  -- Cap at top of "Good"
    end

    -- Cannot reach "Good" (700+) without minimum history
    if PaymentTracker and not PaymentTracker.hasMinimumHistory(farmId) then
        score = math.min(score, 699)  -- Cap at top of "Fair"
    end

    -- Clamp to valid range
    score = math.max(CreditScore.MIN_SCORE, math.min(CreditScore.MAX_SCORE, score))

    return math.floor(score)
end

--[[
    Calculate total asset value for a farm
    Includes: cash + WHOLLY OWNED land value + WHOLLY OWNED vehicle value
    Financed assets are NOT counted (debt offsets their value)
]]
function CreditScore.calculateAssets(farm)
    local total = 0

    -- Build set of financed vehicle IDs and land IDs to exclude
    local financedVehicleIds = {}
    local financedLandIds = {}

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farm.farmId)
        if deals then
            for _, deal in pairs(deals) do
                if deal.status == "active" then
                    if deal.dealType == 1 and deal.vehicleId then  -- Vehicle finance
                        financedVehicleIds[deal.vehicleId] = true
                    elseif deal.dealType == 4 and deal.farmlandId then  -- Land finance
                        financedLandIds[deal.farmlandId] = true
                    elseif deal.itemType == "land" and deal.farmlandId then
                        financedLandIds[deal.farmlandId] = true
                    end
                end
            end
        end
    end

    -- Cash on hand (immediate asset)
    total = total + farm.money

    -- Land value - only WHOLLY OWNED (not financed)
    if g_farmlandManager then
        local farmlands = g_farmlandManager:getFarmlands()
        if farmlands then
            for _, farmland in pairs(farmlands) do
                local ownerId = g_farmlandManager:getFarmlandOwner(farmland.id)
                if ownerId == farm.farmId then
                    -- Only count if NOT currently financed
                    if not financedLandIds[farmland.id] then
                        total = total + (farmland.price or 0)
                    end
                end
            end
        end
    end

    -- Vehicle value - only WHOLLY OWNED (not financed or leased)
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farm.farmId and
           vehicle.propertyState == VehiclePropertyState.OWNED then
            -- Only count if NOT currently financed
            local vehicleId = vehicle.id or NetworkUtil.getObjectId(vehicle)
            if not financedVehicleIds[vehicleId] then
                local value = CreditScore.getDepreciatedVehicleValue(vehicle)
                total = total + value
            end
        end
    end

    return total
end

--[[
    Calculate depreciated value of a single vehicle
    Uses built-in game depreciation system
    Factors: age, damage, wear, operating hours
]]
function CreditScore.getDepreciatedVehicleValue(vehicle)
    -- Get store item for base price
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        UsedPlus.logWarn("No store item for vehicle: " .. tostring(vehicle.configFileName))
        return 0
    end

    -- Use game's built-in getSellPrice() which accounts for all depreciation
    -- This is accurate and maintains consistency with game mechanics
    local sellPrice = vehicle:getSellPrice()

    return sellPrice
end

--[[
    Calculate total debt for a farm
    Sum of all active finance and lease balances
]]
function CreditScore.calculateDebt(farm)
    local total = 0

    -- Include vanilla game loans (farm.loan is the vanilla Finances page "Loan" line)
    if farm.loan ~= nil and farm.loan > 0 then
        total = total + farm.loan
    end

    -- Get finance deals from FinanceManager (UsedPlus loans, vehicle financing, land financing)
    -- This requires FinanceManager to be initialized (will be)
    if g_financeManager ~= nil then
        local deals = g_financeManager:getDealsForFarm(farm.farmId)
        if deals ~= nil then
            for _, deal in pairs(deals) do
                if deal.status == "active" then
                    total = total + deal.currentBalance
                end
            end
        end
    end

    return total
end

--[[
    Get credit rating tier from numeric score
    Returns: tier name (string), tier level (1-5 int)
    Ranges based on FICO scoring:
      Excellent: 750-850 (-1.5% interest)
      Good: 700-749 (-0.5% interest)
      Fair: 650-699 (+0.5% interest)
      Poor: 600-649 (+1.5% interest)
      Very Poor: 300-599 (+3.0% interest)
]]
function CreditScore.getRating(score)
    if score >= 750 then
        return "Excellent", 1
    elseif score >= 700 then
        return "Good", 2
    elseif score >= 650 then
        return "Fair", 3
    elseif score >= 600 then
        return "Poor", 4
    else
        return "Very Poor", 5
    end
end

--[[
    Get interest rate adjustment based on credit score
    Used in finance calculations
    Returns percentage points to add/subtract from base rate
]]
function CreditScore.getInterestAdjustment(score)
    -- v1.4.0: Check settings system for credit feature toggle
    -- When credit system is disabled, use flat interest rate (no adjustment)
    local creditEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Credit")
    if not creditEnabled then
        return 0  -- No credit-based adjustment
    end

    local rating, level = CreditScore.getRating(score)

    -- Credit adjustment table from design spec
    if level == 1 then  -- Excellent (750+)
        return -1.5
    elseif level == 2 then  -- Good (700-749)
        return -0.5
    elseif level == 3 then  -- Fair (650-699)
        return 0.5
    elseif level == 4 then  -- Poor (600-649)
        return 1.5
    else  -- Very Poor (300-599)
        return 3.0
    end
end

--[[
    Minimum credit score requirements for financing
    These prevent players with very poor credit from taking on debt they can't afford

    Tier thresholds:
    - REPAIR: 500 (lowest bar - small amounts, secured by vehicle)
    - VEHICLE_FINANCE: 550 (moderate - secured by vehicle)
    - VEHICLE_LEASE: 600 (higher - leases require better credit)
    - LAND_FINANCE: 600 (high amounts, secured by land)
    - CASH_LOAN: 550 (unsecured loans require proven history)
]]
CreditScore.MIN_CREDIT_FOR_FINANCING = {
    REPAIR = 500,           -- Small repair loans, low risk
    VEHICLE_FINANCE = 550,  -- Vehicle is collateral
    VEHICLE_LEASE = 600,    -- Leases are stricter
    LAND_FINANCE = 600,     -- Large amounts, land as collateral
    CASH_LOAN = 550,        -- Needs collateral pledged
}

--[[
    Check if a farm qualifies for a specific type of financing
    @param farmId - The farm ID
    @param financeType - One of: "REPAIR", "VEHICLE_FINANCE", "VEHICLE_LEASE", "LAND_FINANCE", "CASH_LOAN"
    @return canFinance (boolean), minRequired (number), currentScore (number), message (string)
]]
function CreditScore.canFinance(farmId, financeType)
    local currentScore = CreditScore.calculate(farmId)
    local minRequired = CreditScore.MIN_CREDIT_FOR_FINANCING[financeType]

    if minRequired == nil then
        UsedPlus.logWarn(string.format("Unknown finance type: %s", tostring(financeType)))
        minRequired = 600  -- Default to moderate requirement
    end

    local canFinance = currentScore >= minRequired
    local message = ""

    if not canFinance then
        local rating, _ = CreditScore.getRating(currentScore)
        local deficit = minRequired - currentScore

        -- Get finance type name for message
        local financeTypeNames = {
            REPAIR = g_i18n:getText("usedplus_finance_repairFinancing"),
            VEHICLE_FINANCE = g_i18n:getText("usedplus_finance_vehicleFinancing"),
            VEHICLE_LEASE = g_i18n:getText("usedplus_finance_vehicleLeasing"),
            LAND_FINANCE = g_i18n:getText("usedplus_finance_landFinancing"),
            CASH_LOAN = g_i18n:getText("usedplus_finance_cashLoan"),
        }
        local financeTypeName = financeTypeNames[financeType] or financeType

        -- Build localized message
        local detailTemplate = g_i18n:getText("usedplus_error_creditTooLowDetail")
        local tip = g_i18n:getText("usedplus_error_creditTip")
        message = string.format(detailTemplate, currentScore, minRequired, financeTypeName) .. "\n\n" .. tip
    end

    return canFinance, minRequired, currentScore, message
end

--[[
    Get user-friendly description of financing requirements
    @param financeType - The type of financing
    @return Table with description and tips
]]
function CreditScore.getFinanceRequirements(financeType)
    local requirements = {
        REPAIR = {
            name = "Repair/Repaint Financing",
            minScore = 500,
            description = "Finance vehicle repairs and repaints over time.",
            tips = {"Smallest credit requirement", "Good way to start building credit history"}
        },
        VEHICLE_FINANCE = {
            name = "Vehicle Financing",
            minScore = 550,
            description = "Purchase vehicles with monthly payments.",
            tips = {"Vehicle serves as collateral", "Miss 3 payments and vehicle is repossessed"}
        },
        VEHICLE_LEASE = {
            name = "Vehicle Leasing",
            minScore = 600,
            description = "Lease vehicles with option to buy at end of term.",
            tips = {"Requires better credit than financing", "Security deposit based on credit tier"}
        },
        LAND_FINANCE = {
            name = "Land Financing",
            minScore = 600,
            description = "Purchase farmland with mortgage payments.",
            tips = {"Land serves as collateral", "Lower interest rates than vehicle loans"}
        },
        CASH_LOAN = {
            name = "Cash Loan",
            minScore = 550,
            description = "Borrow against your assets for immediate cash.",
            tips = {"Requires pledging collateral", "Higher interest due to flexibility"}
        }
    }

    return requirements[financeType] or requirements.VEHICLE_FINANCE
end

--[[
    Get cash back multiplier based on credit score
    Better credit = more cash back allowed
    Returns multiplier (0.25x to 2.0x)
]]
function CreditScore.getCashBackMultiplier(score)
    local rating, level = CreditScore.getRating(score)

    -- Cash back multiplier table from design spec
    if level == 1 then  -- Excellent (750+)
        return 2.0  -- Up to 20% cash back
    elseif level == 2 then  -- Good (700-749)
        return 1.5  -- Up to 15% cash back
    elseif level == 3 then  -- Fair (650-699)
        return 1.0  -- Up to 10% cash back
    elseif level == 4 then  -- Poor (600-649)
        return 0.5  -- Up to 5% cash back
    else  -- Very Poor (300-599)
        return 0.25  -- Up to 2.5% cash back
    end
end

--[[
    Calculate maximum cash back amount
    Simple rule: Up to half of the down payment
    This prevents abuse while giving flexibility
]]
function CreditScore.getMaxCashBack(amountFinanced, downPayment, creditScore)
    -- Max cash back = 50% of down payment
    local maxCashBack = downPayment * 0.5

    return math.floor(maxCashBack)
end

--============================================================================
-- PAYMENT TRACKER
-- Detailed payment tracking for realistic credit scoring
-- This is the PRIMARY factor in credit score calculation
--============================================================================

PaymentTracker = {}

-- Payment status constants
PaymentTracker.STATUS_ON_TIME = "on_time"
PaymentTracker.STATUS_LATE = "late"       -- Paid, but late
PaymentTracker.STATUS_MISSED = "missed"   -- Not paid at all

-- Score impact values (tuned for REALISTIC credit behavior)
-- Key principle: VERY SLOW to gain, QUICK to lose
-- Real credit takes YEARS to build, one miss can undo months of progress
PaymentTracker.IMPACT = {
    -- Per-payment gains (intentionally small)
    ON_TIME_BASE = 2,          -- Base points per on-time payment (very slow gain)
    STREAK_BONUS = 0.5,        -- Per-payment streak bonus (0.5 per, max 12 at 24 streak)

    -- Penalties are now dynamic from settings (see getLatePenalty/getMissedPenalty)
    -- Legacy defaults kept for backwards compatibility
    LATE = -20,                -- Moderate penalty for late (overridden by settings)
    MISSED = -50,              -- Severe penalty for missed (overridden by settings)
    RECENT_MISS_PENALTY = -40, -- Extra penalty if missed in last 6 payments

    -- Milestone bonuses (reward long-term consistency)
    PERFECT_12_BONUS = 10,     -- Bonus for 12+ payments with no misses
    PERFECT_24_BONUS = 20,     -- Bonus for 24+ payments with no misses (total, not additional)
    PERFECT_48_BONUS = 35,     -- Bonus for 48+ payments with no misses

    -- Longevity (very slow accumulation)
    LONGEVITY_DIVISOR = 8,     -- totalPayments / 8 = longevity bonus
    MAX_LONGEVITY_BONUS = 30,  -- Max 30 points (requires 240 payments!)

    -- History requirements
    MIN_PAYMENTS_FOR_SCORE = 3, -- No credit score benefit until 3 payments made
}

--[[
    Get late payment penalty from settings
    @return negative number (e.g., -15)
]]
function PaymentTracker.getLatePenalty()
    local penalty = UsedPlusSettings and UsedPlusSettings:get("latePaymentPenalty") or 15
    return -penalty  -- Return as negative
end

--[[
    Get missed payment penalty from settings (3x the late penalty)
    @return negative number (e.g., -45)
]]
function PaymentTracker.getMissedPenalty()
    local latePenalty = UsedPlusSettings and UsedPlusSettings:get("latePaymentPenalty") or 15
    return -(latePenalty * 3)  -- Missed is 3x worse than late
end

-- Storage per farm
PaymentTracker.farmData = {}

--[[
    Initialize or get farm payment data
]]
function PaymentTracker.getFarmData(farmId)
    if PaymentTracker.farmData[farmId] == nil then
        PaymentTracker.farmData[farmId] = {
            payments = {},           -- Array of payment records
            stats = {
                totalPayments = 0,
                onTimePayments = 0,
                latePayments = 0,
                missedPayments = 0,
                currentStreak = 0,   -- Current consecutive on-time streak
                longestStreak = 0,   -- Best streak ever
                lastMissedIndex = 0, -- Index of most recent missed payment
            }
        }
    end
    return PaymentTracker.farmData[farmId]
end

--[[
    Record a payment
    @param farmId - Farm making the payment
    @param dealId - Deal the payment is for
    @param status - PaymentTracker.STATUS_ON_TIME, _LATE, or _MISSED
    @param amount - Payment amount
    @param dealType - Type of deal ("finance", "lease", "loan")
]]
function PaymentTracker.recordPayment(farmId, dealId, status, amount, dealType)
    local data = PaymentTracker.getFarmData(farmId)

    -- Create payment record
    local record = {
        dealId = dealId,
        dealType = dealType or "unknown",
        status = status,
        amount = amount or 0,
        period = g_currentMission.environment.currentPeriod or 1,
        year = g_currentMission.environment.currentYear or 1,
    }

    table.insert(data.payments, record)

    -- Update statistics
    data.stats.totalPayments = data.stats.totalPayments + 1

    if status == PaymentTracker.STATUS_ON_TIME then
        data.stats.onTimePayments = data.stats.onTimePayments + 1
        data.stats.currentStreak = data.stats.currentStreak + 1
        if data.stats.currentStreak > data.stats.longestStreak then
            data.stats.longestStreak = data.stats.currentStreak
        end
    elseif status == PaymentTracker.STATUS_LATE then
        data.stats.latePayments = data.stats.latePayments + 1
        data.stats.currentStreak = 0  -- Break streak
    elseif status == PaymentTracker.STATUS_MISSED then
        data.stats.missedPayments = data.stats.missedPayments + 1
        data.stats.currentStreak = 0  -- Break streak
        data.stats.lastMissedIndex = data.stats.totalPayments
    end

    -- Trim old payments (keep last 100)
    while #data.payments > 100 do
        table.remove(data.payments, 1)
    end

    UsedPlus.logDebug(string.format(
        "PaymentTracker: Farm %d recorded %s payment (streak: %d, total: %d)",
        farmId, status, data.stats.currentStreak, data.stats.totalPayments))
end

--[[
    Calculate payment history score contribution
    This is the PRIMARY factor in credit score (up to +250 points)

    REDESIGNED for realistic slow credit building:
    - No instant gratification from percentage rates
    - Linear accumulation: 2 points per on-time payment
    - Milestone bonuses for long-term consistency
    - Harsh penalties for misses (one miss undoes many months of progress)

    Progression timeline (monthly payments):
    - 3 payments (3 months): ~7 points (just starting to build)
    - 6 payments (6 months): ~15 points (establishing history)
    - 12 payments (1 year): ~35 points (decent history)
    - 24 payments (2 years): ~75 points (good history)
    - 48 payments (4 years): ~140 points (excellent history)

    Total possible: ~250 max (requires 4+ years of perfect payments)
]]
function PaymentTracker.calculateHistoryScore(farmId)
    local data = PaymentTracker.getFarmData(farmId)
    local stats = data.stats
    local impact = PaymentTracker.IMPACT

    -- No score until minimum payment history established
    if stats.totalPayments < impact.MIN_PAYMENTS_FOR_SCORE then
        return 0
    end

    local score = 0

    -- 1. Base score: 2 points per on-time payment (slow linear accumulation)
    -- 50 on-time payments = 100 points from this component
    local baseScore = stats.onTimePayments * impact.ON_TIME_BASE
    score = score + baseScore

    -- 2. Current streak bonus: 0.5 points per payment in streak (max 12 at 24 streak)
    -- Rewards consistency but doesn't dominate
    local streakBonus = math.min(stats.currentStreak, 24) * impact.STREAK_BONUS
    score = score + streakBonus

    -- 3. Perfect record milestone bonuses (tiered, not cumulative)
    -- Rewards long-term perfect history
    if stats.missedPayments == 0 then
        if stats.totalPayments >= 48 then
            score = score + impact.PERFECT_48_BONUS  -- +35 for 4 years perfect
        elseif stats.totalPayments >= 24 then
            score = score + impact.PERFECT_24_BONUS  -- +20 for 2 years perfect
        elseif stats.totalPayments >= 12 then
            score = score + impact.PERFECT_12_BONUS  -- +10 for 1 year perfect
        end
    end

    -- 4. Longevity bonus: rewards having a long credit history
    -- totalPayments / 8, max 30 points (requires 240 payments for max!)
    local longevityBonus = math.min(
        stats.totalPayments / impact.LONGEVITY_DIVISOR,
        impact.MAX_LONGEVITY_BONUS
    )
    score = score + longevityBonus

    -- 5. Recent miss penalty: harsh penalty if missed in last 6 payments
    -- One miss can wipe out months of progress
    local paymentsSinceLastMiss = stats.totalPayments - stats.lastMissedIndex
    if stats.lastMissedIndex > 0 and paymentsSinceLastMiss < 6 then
        score = score + impact.RECENT_MISS_PENALTY  -- -40 points!
    end

    -- Cap at reasonable range
    score = math.max(0, math.min(250, score))

    return math.floor(score)
end

--[[
    Get payment statistics for a farm
    Used for UI display
]]
function PaymentTracker.getStats(farmId)
    local data = PaymentTracker.getFarmData(farmId)
    return data.stats
end

--[[
    Get on-time payment rate as percentage
]]
function PaymentTracker.getOnTimeRate(farmId)
    local stats = PaymentTracker.getStats(farmId)
    if stats.totalPayments == 0 then
        return 0
    end
    return math.floor((stats.onTimePayments / stats.totalPayments) * 100)
end

--[[
    Check if farm has enough payment history for "Good" credit (700+)
    Requires at least 12 on-time payments (1 year of history)
]]
function PaymentTracker.hasMinimumHistory(farmId)
    local stats = PaymentTracker.getStats(farmId)
    return stats.onTimePayments >= 12
end

--[[
    Check if farm qualifies for "Excellent" credit (750+)
    Requires: 36+ on-time payments (3 years), current streak of 18+, no recent misses
    This is HARD to achieve - as it should be!
]]
function PaymentTracker.qualifiesForExcellent(farmId)
    local stats = PaymentTracker.getStats(farmId)
    local paymentsSinceLastMiss = stats.totalPayments - stats.lastMissedIndex

    return stats.onTimePayments >= 36 and
           stats.currentStreak >= 18 and
           (stats.lastMissedIndex == 0 or paymentsSinceLastMiss >= 18)
end

--[[
    Save payment tracker data to XML
]]
function PaymentTracker.saveToXMLFile(xmlFile, key)
    local farmIndex = 0

    for farmId, data in pairs(PaymentTracker.farmData) do
        local farmKey = string.format("%s.farm(%d)", key, farmIndex)
        xmlFile:setInt(farmKey .. "#farmId", farmId)

        -- Save stats
        xmlFile:setInt(farmKey .. ".stats#totalPayments", data.stats.totalPayments)
        xmlFile:setInt(farmKey .. ".stats#onTimePayments", data.stats.onTimePayments)
        xmlFile:setInt(farmKey .. ".stats#latePayments", data.stats.latePayments)
        xmlFile:setInt(farmKey .. ".stats#missedPayments", data.stats.missedPayments)
        xmlFile:setInt(farmKey .. ".stats#currentStreak", data.stats.currentStreak)
        xmlFile:setInt(farmKey .. ".stats#longestStreak", data.stats.longestStreak)
        xmlFile:setInt(farmKey .. ".stats#lastMissedIndex", data.stats.lastMissedIndex)

        -- Save recent payments (last 24 for recovery tracking)
        local startIdx = math.max(1, #data.payments - 23)
        local paymentIdx = 0
        for i = startIdx, #data.payments do
            local p = data.payments[i]
            local pKey = string.format("%s.payment(%d)", farmKey, paymentIdx)
            xmlFile:setString(pKey .. "#dealId", p.dealId or "")
            xmlFile:setString(pKey .. "#dealType", p.dealType or "")
            xmlFile:setString(pKey .. "#status", p.status or "")
            xmlFile:setInt(pKey .. "#amount", p.amount or 0)
            xmlFile:setInt(pKey .. "#period", p.period or 1)
            xmlFile:setInt(pKey .. "#year", p.year or 1)
            paymentIdx = paymentIdx + 1
        end

        farmIndex = farmIndex + 1
    end
end

--[[
    Load payment tracker data from XML
]]
function PaymentTracker.loadFromXMLFile(xmlFile, key)
    xmlFile:iterate(key .. ".farm", function(_, farmKey)
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        local data = PaymentTracker.getFarmData(farmId)

        -- Load stats
        data.stats.totalPayments = xmlFile:getInt(farmKey .. ".stats#totalPayments", 0)
        data.stats.onTimePayments = xmlFile:getInt(farmKey .. ".stats#onTimePayments", 0)
        data.stats.latePayments = xmlFile:getInt(farmKey .. ".stats#latePayments", 0)
        data.stats.missedPayments = xmlFile:getInt(farmKey .. ".stats#missedPayments", 0)
        data.stats.currentStreak = xmlFile:getInt(farmKey .. ".stats#currentStreak", 0)
        data.stats.longestStreak = xmlFile:getInt(farmKey .. ".stats#longestStreak", 0)
        data.stats.lastMissedIndex = xmlFile:getInt(farmKey .. ".stats#lastMissedIndex", 0)

        -- Load recent payments
        xmlFile:iterate(farmKey .. ".payment", function(_, pKey)
            local payment = {
                dealId = xmlFile:getString(pKey .. "#dealId", ""),
                dealType = xmlFile:getString(pKey .. "#dealType", ""),
                status = xmlFile:getString(pKey .. "#status", "on_time"),
                amount = xmlFile:getInt(pKey .. "#amount", 0),
                period = xmlFile:getInt(pKey .. "#period", 1),
                year = xmlFile:getInt(pKey .. "#year", 1),
            }
            table.insert(data.payments, payment)
        end)
    end)

    local farmCount = 0
    for _ in pairs(PaymentTracker.farmData) do
        farmCount = farmCount + 1
    end
    UsedPlus.logDebug(string.format("Loaded payment tracker data for %d farms", farmCount))
end

--[[
    Clear all data (for cleanup)
]]
function PaymentTracker.clear()
    PaymentTracker.farmData = {}
end

--============================================================================
-- CREDIT HISTORY
-- Track credit score changes over time based on player behavior
--============================================================================

CreditHistory = {}

-- Event type constants with score changes
-- NOTE: These are for DISPLAY/LOGGING purposes - actual score is calculated
-- by PaymentTracker.calculateHistoryScore() using payment statistics
-- Values here are intentionally small (slow to gain) or large negative (quick to lose)
CreditHistory.EVENT_TYPES = {
    -- Payment events (small gains, harsh penalties)
    PAYMENT_ON_TIME = { name = "Payment On Time", change = 2 },      -- Tiny gain
    PAYMENT_MISSED = { name = "Missed Payment", change = -50 },      -- Harsh!
    DEAL_PAID_OFF = { name = "Loan Paid Off", change = 15 },         -- Nice milestone
    NEW_DEBT_TAKEN = { name = "New Finance", change = -5 },          -- Small hit for new debt
    DEBT_RATIO_IMPROVED = { name = "Debt Ratio Improved", change = 5 },
    EXCELLENT_ACHIEVED = { name = "Excellent Credit", change = 10 }, -- Rare achievement

    -- Loan events
    LOAN_TAKEN = { name = "Cash Loan Taken", change = -3 },
    REPAIR_FINANCED = { name = "Repair Financed", change = -2 },

    -- Land lease events
    LAND_LEASE_CREATED = { name = "Land Leased", change = -3 },
    LAND_LEASE_PAYMENT = { name = "Land Lease Payment", change = 2 },
    LAND_LEASE_MISSED_PAYMENT = { name = "Missed Land Payment", change = -50 },  -- Harsh!
    LAND_LEASE_BUYOUT = { name = "Land Lease Buyout", change = 10 },
    LAND_LEASE_TERMINATED = { name = "Land Lease Terminated", change = -75 },    -- Very bad
    LAND_LEASE_EXPIRED = { name = "Land Lease Expired", change = 0 },
    LAND_SEIZED = { name = "Land Seized", change = -150 },           -- Devastating!

    -- Vehicle lease events
    LEASE_TERMINATED_EARLY = { name = "Lease Terminated Early", change = -40 },
    LEASE_BUYOUT = { name = "Lease Buyout", change = 10 },

    -- Payment configuration events
    PAYMENT_SKIPPED = { name = "Payment Skipped", change = -50 },    -- Same as missed
    PAYMENT_PARTIAL = { name = "Partial Payment", change = -15 },
    PAYMENT_MINIMUM = { name = "Minimum Payment", change = 0 },
    PAYMENT_STANDARD = { name = "Standard Payment", change = 2 },
    PAYMENT_EXTRA = { name = "Extra Payment", change = 3 },
}

-- Maximum history entries per farm (for performance)
CreditHistory.MAX_HISTORY_ENTRIES = 100

-- History storage by farm
CreditHistory.history = {}

-- Score adjustments (cumulative from history events)
CreditHistory.scoreAdjustments = {}

--[[
    Initialize history for a farm
]]
function CreditHistory.initFarm(farmId)
    if CreditHistory.history[farmId] == nil then
        CreditHistory.history[farmId] = {}
    end
    if CreditHistory.scoreAdjustments[farmId] == nil then
        CreditHistory.scoreAdjustments[farmId] = 0
    end
end

--[[
    Record a credit event for a farm
    @param farmId - The farm ID
    @param eventType - One of CreditHistory.EVENT_TYPES keys
    @param details - Optional string with additional details
    @return The score change applied
]]
function CreditHistory.recordEvent(farmId, eventType, details)
    CreditHistory.initFarm(farmId)

    local eventInfo = CreditHistory.EVENT_TYPES[eventType]
    if eventInfo == nil then
        UsedPlus.logWarn(string.format("Unknown credit event type: %s", tostring(eventType)))
        return 0
    end

    -- Create history entry
    local entry = {
        eventType = eventType,
        eventName = eventInfo.name,
        change = eventInfo.change,
        details = details or "",
        timestamp = g_currentMission.environment.dayTime or 0,
        period = g_currentMission.environment.currentPeriod or 1,
        year = g_currentMission.environment.currentYear or 1,
    }

    -- Add to history
    table.insert(CreditHistory.history[farmId], entry)

    -- Trim history if too long
    while #CreditHistory.history[farmId] > CreditHistory.MAX_HISTORY_ENTRIES do
        table.remove(CreditHistory.history[farmId], 1)
    end

    -- Apply score adjustment
    CreditHistory.scoreAdjustments[farmId] = (CreditHistory.scoreAdjustments[farmId] or 0) + eventInfo.change

    -- Cap adjustment range to prevent extreme scores
    CreditHistory.scoreAdjustments[farmId] = math.max(-200, math.min(200, CreditHistory.scoreAdjustments[farmId]))

    UsedPlus.logDebug(string.format("Credit event recorded for farm %d: %s (%+d)",
        farmId, eventInfo.name, eventInfo.change))

    return eventInfo.change
end

--[[
    Get the cumulative score adjustment from history
    @param farmId - The farm ID
    @return Score adjustment to add to base calculation
]]
function CreditHistory.getScoreAdjustment(farmId)
    return CreditHistory.scoreAdjustments[farmId] or 0
end

--[[
    Get history entries for a farm
    @param farmId - The farm ID
    @param limit - Optional limit on entries returned (default all)
    @return Array of history entries (newest first)
]]
function CreditHistory.getHistory(farmId, limit)
    CreditHistory.initFarm(farmId)

    local history = CreditHistory.history[farmId]
    local result = {}

    -- Return newest first
    local startIndex = #history
    local endIndex = 1
    if limit and limit > 0 then
        endIndex = math.max(1, #history - limit + 1)
    end

    for i = startIndex, endIndex, -1 do
        table.insert(result, history[i])
    end

    return result
end

--[[
    Get summary statistics for a farm's credit history
    @param farmId - The farm ID
    @return Table with totalEvents, positiveEvents, negativeEvents, netChange
]]
function CreditHistory.getSummary(farmId)
    CreditHistory.initFarm(farmId)

    local history = CreditHistory.history[farmId]
    local summary = {
        totalEvents = #history,
        positiveEvents = 0,
        negativeEvents = 0,
        netChange = 0,
        paymentsOnTime = 0,
        paymentsMissed = 0,
        dealsCompleted = 0,
    }

    for _, entry in ipairs(history) do
        summary.netChange = summary.netChange + entry.change
        if entry.change > 0 then
            summary.positiveEvents = summary.positiveEvents + 1
        elseif entry.change < 0 then
            summary.negativeEvents = summary.negativeEvents + 1
        end

        -- Count specific events
        if entry.eventType == "PAYMENT_ON_TIME" then
            summary.paymentsOnTime = summary.paymentsOnTime + 1
        elseif entry.eventType == "PAYMENT_MISSED" then
            summary.paymentsMissed = summary.paymentsMissed + 1
        elseif entry.eventType == "DEAL_PAID_OFF" then
            summary.dealsCompleted = summary.dealsCompleted + 1
        end
    end

    return summary
end

--[[
    Check for tier change and notify player
    @param farmId - The farm ID
    @param oldScore - Previous credit score
    @param newScore - New credit score
]]
function CreditHistory.checkTierChange(farmId, oldScore, newScore)
    local oldRating, oldLevel = CreditScore.getRating(oldScore)
    local newRating, newLevel = CreditScore.getRating(newScore)

    -- No tier change
    if newLevel == oldLevel then
        return
    end

    -- Tier improved (lower level number = better tier)
    if newLevel < oldLevel then
        -- Record bonus for excellent tier
        if newLevel == 1 then
            CreditHistory.recordEvent(farmId, "EXCELLENT_ACHIEVED", "Reached excellent credit tier")
        end

        -- Notify player of improvement
        if g_currentMission then
            local message = string.format("Credit Improved! Your credit is now %s (%d)",
                newRating, newScore)
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                message
            )
        end

    -- Tier worsened (higher level number = worse tier)
    elseif newLevel > oldLevel then
        -- Notify player of decline
        if g_currentMission then
            local message = string.format("Credit Warning: Your credit dropped to %s (%d)",
                newRating, newScore)
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                message
            )
        end
    end
end

--[[
    Save history to XML
    @param xmlFile - The XML file handle
    @param key - The base XML key
]]
function CreditHistory.saveToXMLFile(xmlFile, key)
    local farmIndex = 0

    for farmId, history in pairs(CreditHistory.history) do
        local farmKey = string.format("%s.farm(%d)", key, farmIndex)
        xmlFile:setInt(farmKey .. "#farmId", farmId)
        xmlFile:setInt(farmKey .. "#adjustment", CreditHistory.scoreAdjustments[farmId] or 0)

        -- Save recent history entries (last 50 to save space)
        local startIndex = math.max(1, #history - 49)
        local entryIndex = 0

        for i = startIndex, #history do
            local entry = history[i]
            local entryKey = string.format("%s.entry(%d)", farmKey, entryIndex)

            xmlFile:setString(entryKey .. "#type", entry.eventType)
            xmlFile:setInt(entryKey .. "#change", entry.change)
            xmlFile:setString(entryKey .. "#details", entry.details or "")
            xmlFile:setInt(entryKey .. "#period", entry.period or 1)
            xmlFile:setInt(entryKey .. "#year", entry.year or 1)

            entryIndex = entryIndex + 1
        end

        farmIndex = farmIndex + 1
    end
end

--[[
    Load history from XML
    @param xmlFile - The XML file handle
    @param key - The base XML key
]]
function CreditHistory.loadFromXMLFile(xmlFile, key)
    xmlFile:iterate(key .. ".farm", function(_, farmKey)
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        local adjustment = xmlFile:getInt(farmKey .. "#adjustment", 0)

        CreditHistory.initFarm(farmId)
        CreditHistory.scoreAdjustments[farmId] = adjustment

        xmlFile:iterate(farmKey .. ".entry", function(_, entryKey)
            local entry = {
                eventType = xmlFile:getString(entryKey .. "#type", "UNKNOWN"),
                change = xmlFile:getInt(entryKey .. "#change", 0),
                details = xmlFile:getString(entryKey .. "#details", ""),
                period = xmlFile:getInt(entryKey .. "#period", 1),
                year = xmlFile:getInt(entryKey .. "#year", 1),
            }

            -- Reconstruct event name
            local eventInfo = CreditHistory.EVENT_TYPES[entry.eventType]
            entry.eventName = eventInfo and eventInfo.name or entry.eventType

            table.insert(CreditHistory.history[farmId], entry)
        end)
    end)

    local farmCount = 0
    for _ in pairs(CreditHistory.history) do
        farmCount = farmCount + 1
    end
    UsedPlus.logDebug(string.format("Loaded credit history for %d farms", farmCount))
end

--[[
    Clear all history (for cleanup)
]]
function CreditHistory.clear()
    CreditHistory.history = {}
    CreditHistory.scoreAdjustments = {}
end

--============================================================================

UsedPlus.logInfo("CreditSystem loaded (CreditScore, CreditHistory)")
