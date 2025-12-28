--[[
    FS25_UsedPlus - Finance Calculations Utility

    Central location for all financial mathematics
    Pattern from: EnhancedLoanSystem financial formulas
    Reference: FS25_UsedPlus.md Mathematical Formulas section (lines 1634-1853)

    Provides:
    - Interest rate calculation (base + credit + term + down payment adjustments)
    - Residual value calculation for leases
    - Cash back limit calculation
    - Validation functions for input ranges
    - Minimum financing thresholds

    All formulas match the design specification exactly.
]]

FinanceCalculations = {}

--[[
    Minimum Financing Thresholds
    Banks don't process loans for trivially small amounts - the administrative
    overhead exceeds the potential profit. These thresholds ensure realistic
    financing behavior.
]]
FinanceCalculations.MINIMUM_AMOUNTS = {
    VEHICLE_FINANCE = 2500,   -- Minimum for financing vehicles/equipment
    VEHICLE_LEASE = 5000,     -- Leasing has higher admin overhead
    CASH_LOAN = 1000,         -- Secured loans can be smaller
    REPAIR_FINANCE = 500,     -- Emergency repairs need accessibility
    LAND_FINANCE = 10000,     -- Land purchases are always significant
}

--[[
    Check if an amount meets the minimum financing threshold
    @param amount - The amount to check
    @param financeType - One of: "VEHICLE_FINANCE", "VEHICLE_LEASE", "CASH_LOAN", "REPAIR_FINANCE", "LAND_FINANCE"
    @return meetsMinimum (boolean), minimumRequired (number)
]]
function FinanceCalculations.meetsMinimumAmount(amount, financeType)
    local minimum = FinanceCalculations.MINIMUM_AMOUNTS[financeType]
    if minimum == nil then
        -- Unknown type - default to vehicle finance minimum
        minimum = FinanceCalculations.MINIMUM_AMOUNTS.VEHICLE_FINANCE
    end
    return amount >= minimum, minimum
end

--[[
    Calculate final interest rate for vehicle/equipment finance
    Formula breakdown:
        Base Rate: 4.5%
        + Credit Score Adjustment: -1.5% to +3.0%
        + Term Adjustment: 0% to +1.5%
        + Down Payment Adjustment: -1.0% to +1.0%
        = Final Rate (capped 2.0% to 15.0%)
]]
function FinanceCalculations.calculateVehicleInterestRate(creditScore, termMonths, downPaymentPercent)
    local baseRate = 4.5

    -- Credit score adjustment (from CreditScore tiers)
    local creditAdj = CreditScore.getInterestAdjustment(creditScore)

    -- Term adjustment (longer term = higher rate)
    local termAdj = 0
    if termMonths > 180 then      -- > 15 years
        termAdj = 1.5
    elseif termMonths > 120 then  -- > 10 years
        termAdj = 1.0
    elseif termMonths > 60 then   -- > 5 years
        termAdj = 0.5
    end

    -- Down payment adjustment (larger down = lower rate)
    local dpAdj = 0
    if downPaymentPercent >= 0.40 then     -- >= 40%
        dpAdj = -1.0
    elseif downPaymentPercent >= 0.25 then -- >= 25%
        dpAdj = -0.5
    elseif downPaymentPercent >= 0.10 then -- >= 10%
        dpAdj = 0
    else                                    -- < 10%
        dpAdj = 1.0
    end

    -- Calculate final rate
    local finalRate = baseRate + creditAdj + termAdj + dpAdj

    -- Cap rate between 2% and 15%
    finalRate = math.max(2.0, math.min(15.0, finalRate))

    return finalRate
end

--[[
    Calculate interest rate for land finance
    Lower rates than vehicles (land doesn't depreciate)
    Base: 3.5%, Final: 2.5% to 8.0%
]]
function FinanceCalculations.calculateLandInterestRate(creditScore, termYears, downPaymentPercent)
    local baseRate = 3.5  -- Lower base for land

    -- Credit adjustment (smaller range for land)
    local rating, level = CreditScore.getRating(creditScore)
    local creditAdj = 0
    if level == 1 then      -- Excellent
        creditAdj = -1.0
    elseif level == 2 then  -- Good
        creditAdj = 0
    elseif level == 3 then  -- Fair
        creditAdj = 0.5
    else                    -- Poor
        creditAdj = 1.5
    end

    -- Term adjustment (land can be financed longer)
    local termAdj = 0
    if termYears > 20 then
        termAdj = 1.0
    elseif termYears > 15 then
        termAdj = 0.5
    end

    -- Down payment adjustment
    local dpAdj = 0
    if downPaymentPercent >= 0.30 then     -- >= 30%
        dpAdj = -0.5
    elseif downPaymentPercent < 0.10 then  -- < 10%
        dpAdj = 1.0
    end

    -- Calculate final rate
    local finalRate = baseRate + creditAdj + termAdj + dpAdj

    -- Cap rate for land (2.5% to 8.0%)
    finalRate = math.max(2.5, math.min(8.0, finalRate))

    return finalRate
end

--[[
    Calculate interest rate for leases
    Typically 1-2% higher than finance
    Base: 5.5%, Final: 3.0% to 12.0%
]]
function FinanceCalculations.calculateLeaseInterestRate(creditScore, downPaymentPercent)
    local baseRate = 5.5  -- Higher base for leases

    -- Credit adjustment (same as finance)
    local creditAdj = CreditScore.getInterestAdjustment(creditScore)

    -- Down payment adjustment (simpler for leases)
    local dpAdj = 0
    if downPaymentPercent >= 0.15 then  -- >= 15%
        dpAdj = -0.5
    else
        dpAdj = 1.0
    end

    -- Calculate final rate
    local finalRate = baseRate + creditAdj + dpAdj

    -- Cap rate for leases (3.0% to 12.0%)
    finalRate = math.max(3.0, math.min(12.0, finalRate))

    return finalRate
end

--[[
    Calculate residual value for lease
    Uses realistic monthly depreciation curve:
    - Year 1: ~1.5% per month (18% annual) - steepest depreciation
    - Year 2: ~1.0% per month (12% annual) - slowing down
    - Year 3+: ~0.75% per month (9% annual) - gradual decline

    This makes short-term leases affordable (4 months = ~6% depreciation)
    while long-term leases reflect real value loss.
]]
function FinanceCalculations.calculateResidualValue(basePrice, termYears)
    local termMonths = termYears * 12
    local totalDepreciation = 0

    -- Calculate depreciation month by month with decreasing rate
    for month = 1, math.floor(termMonths) do
        local monthlyRate
        if month <= 12 then
            -- Year 1: 1.5% per month (18% annual)
            monthlyRate = 0.015
        elseif month <= 24 then
            -- Year 2: 1.0% per month (12% annual)
            monthlyRate = 0.010
        elseif month <= 36 then
            -- Year 3: 0.8% per month (9.6% annual)
            monthlyRate = 0.008
        else
            -- Year 4+: 0.6% per month (7.2% annual) - floor
            monthlyRate = 0.006
        end
        totalDepreciation = totalDepreciation + monthlyRate
    end

    -- Handle partial months (e.g., 4.5 months)
    local partialMonth = termMonths - math.floor(termMonths)
    if partialMonth > 0 then
        local monthlyRate = 0.015  -- Use year 1 rate for partial
        if termMonths > 12 then monthlyRate = 0.010 end
        if termMonths > 24 then monthlyRate = 0.008 end
        if termMonths > 36 then monthlyRate = 0.006 end
        totalDepreciation = totalDepreciation + (monthlyRate * partialMonth)
    end

    -- Cap total depreciation at 75% (vehicle always worth at least 25%)
    totalDepreciation = math.min(totalDepreciation, 0.75)

    local residualPercent = 1.0 - totalDepreciation

    UsedPlus.logDebug(string.format("Residual calc: %d months, %.1f%% depreciation, %.1f%% residual",
        math.floor(termMonths), totalDepreciation * 100, residualPercent * 100))

    return basePrice * residualPercent
end

--[[
    Validate finance parameters are within allowed ranges
    Returns: isValid (bool), errorMessage (string or nil)
]]
function FinanceCalculations.validateFinanceParams(price, downPayment, termYears, itemType)
    -- Validate price
    if price <= 0 then
        return false, g_i18n:getText("usedplus_error_invalidPrice")
    end

    -- Validate down payment
    local maxDownPaymentPercent = 0.50  -- 50% max for vehicles/equipment
    if itemType == "land" then
        maxDownPaymentPercent = 0.40     -- 40% max for land
    end

    if downPayment < 0 then
        return false, g_i18n:getText("usedplus_error_negativeDownPayment")
    end

    if downPayment > price * maxDownPaymentPercent then
        return false, g_i18n:getText("usedplus_error_downPaymentTooHigh")
    end

    -- Validate term
    local minTerm = 1
    local maxTerm = 20  -- 20 years for vehicles
    if itemType == "land" then
        maxTerm = 30     -- 30 years for land
    end

    if termYears < minTerm or termYears > maxTerm then
        return false, string.format(g_i18n:getText("usedplus_error_invalidTerm"), minTerm, maxTerm)
    end

    return true, nil
end

--[[
    Validate lease parameters
    Leases have stricter requirements than finance
]]
function FinanceCalculations.validateLeaseParams(price, downPayment, termYears)
    -- Validate price
    if price <= 0 then
        return false, g_i18n:getText("usedplus_error_invalidPrice")
    end

    -- Validate down payment (max 20% for leases)
    if downPayment < 0 then
        return false, g_i18n:getText("usedplus_error_negativeDownPayment")
    end

    if downPayment > price * 0.20 then
        return false, g_i18n:getText("usedplus_error_leaseDownPaymentTooHigh")
    end

    -- Validate term (1-5 years only for leases)
    if termYears < 1 or termYears > 5 then
        return false, g_i18n:getText("usedplus_error_leaseTermInvalid")
    end

    return true, nil
end

--[[
    Calculate monthly payment using standard amortization formula
    This is the core formula - use this instead of duplicating everywhere!
    Returns: monthlyPayment, totalInterest
    @param principal - Amount financed (after down payment)
    @param annualRate - Annual interest rate as decimal (e.g., 0.065 for 6.5%)
    @param termMonths - Loan term in months
]]
function FinanceCalculations.calculateMonthlyPayment(principal, annualRate, termMonths)
    if principal <= 0 then
        return 0, 0
    end

    local monthlyPayment
    local monthlyRate = annualRate / 12

    if monthlyRate > 0.0001 then
        -- Standard amortization formula: M = P * [r(1+r)^n] / [(1+r)^n - 1]
        local factor = math.pow(1 + monthlyRate, termMonths)
        monthlyPayment = principal * (monthlyRate * factor) / (factor - 1)
    else
        -- Zero interest edge case
        monthlyPayment = principal / termMonths
    end

    monthlyPayment = math.ceil(monthlyPayment)  -- Round up to whole currency
    local totalInterest = (monthlyPayment * termMonths) - principal

    return monthlyPayment, math.max(0, totalInterest)
end

--[[
    Calculate lease monthly payment
    Different formula - based on depreciation + money factor
    @param vehiclePrice - Original vehicle price
    @param residualValue - Value at end of lease (use calculateResidualValue)
    @param annualRate - Annual interest rate as decimal
    @param termMonths - Lease term in months
]]
function FinanceCalculations.calculateLeasePayment(vehiclePrice, residualValue, annualRate, termMonths)
    if vehiclePrice <= 0 or termMonths <= 0 then
        return 0
    end

    -- Depreciation portion: (price - residual) / term
    local depreciationPerMonth = (vehiclePrice - residualValue) / termMonths

    -- Interest portion: (price + residual) / 2 * monthly rate
    local interestPerMonth = ((vehiclePrice + residualValue) / 2) * (annualRate / 12)

    return math.ceil(depreciationPerMonth + interestPerMonth)
end

--[[
    Calculate total cost of finance over full term
    Used for preview in finance dialog
    Returns: totalCost, totalInterest
]]
function FinanceCalculations.calculateTotalCost(principal, monthlyPayment, termMonths)
    local totalPaid = monthlyPayment * termMonths
    local totalInterest = totalPaid - principal

    return totalPaid, totalInterest
end

--[[
    Calculate early payoff amount
    Includes prepayment penalty
]]
function FinanceCalculations.calculatePayoffAmount(currentBalance, monthsPaid, termMonths)
    local remainingMonths = termMonths - monthsPaid

    -- Determine prepayment penalty rate
    local penaltyRate = 0.02  -- 2% default
    if remainingMonths <= 12 then
        penaltyRate = 0.01     -- 1% if less than 1 year remaining
    end

    local penalty = currentBalance * penaltyRate
    local payoffAmount = currentBalance + penalty

    return payoffAmount, penalty
end

--[[
    Calculate lease termination fee
    Fee is 50% of (remaining payments + residual value)
]]
function FinanceCalculations.calculateLeaseTerminationFee(monthlyPayment, monthsPaid, termMonths, residualValue)
    local remainingMonths = termMonths - monthsPaid
    local remainingPayments = monthlyPayment * remainingMonths
    local totalRemaining = remainingPayments + residualValue

    -- Fee is 50% of total obligations
    local fee = totalRemaining * 0.50

    return fee
end

-- NOTE: formatMoney() and formatPercent() removed - use UIHelper.Text instead

--[[
    Calculate security deposit for leases based on credit score
    Used for BOTH land and vehicle leases - ensures consistency

    Better credit = lower risk = less deposit required
    Deposit is expressed as months of lease payment:
      Excellent (750+): 0 months (trusted lessee, no deposit needed)
      Good (700-749): 1 month
      Fair (650-699): 2 months (baseline)
      Poor (600-649): 3 months
      Very Poor (<600): 6 months (high risk requires substantial deposit)

    @param creditScore - The lessee's credit score (300-850)
    @return depositMonths - Number of months of lease payment required as deposit
    @return tierName - Credit tier name for display
]]
function FinanceCalculations.getSecurityDepositMonths(creditScore)
    local rating, level = CreditScore.getRating(creditScore)

    local deposits = {
        [1] = { months = 0, name = "Excellent" },   -- 750+: Trusted, no deposit
        [2] = { months = 1, name = "Good" },        -- 700-749: Minimal deposit
        [3] = { months = 2, name = "Fair" },        -- 650-699: Standard deposit
        [4] = { months = 3, name = "Poor" },        -- 600-649: Higher deposit
        [5] = { months = 6, name = "Very Poor" },   -- <600: Maximum deposit
    }

    local deposit = deposits[level] or deposits[3]  -- Default to Fair if unknown
    return deposit.months, deposit.name
end

--[[
    Calculate security deposit amount for a lease
    Uses credit-based months × monthly payment

    @param monthlyPayment - The monthly lease payment
    @param creditScore - The lessee's credit score
    @return depositAmount - Dollar amount of security deposit required
    @return depositMonths - Number of months (for display)
    @return tierName - Credit tier name for display
]]
function FinanceCalculations.calculateSecurityDeposit(monthlyPayment, creditScore)
    local depositMonths, tierName = FinanceCalculations.getSecurityDepositMonths(creditScore)
    local depositAmount = monthlyPayment * depositMonths

    return depositAmount, depositMonths, tierName
end

--[[
    Calculate land price modifier based on credit score
    Better credit = negotiating power = lower price
    Fair credit (650-699) is baseline (0% adjustment)

    Modifiers by tier:
      Excellent (750+): -5% (discount - sellers want reliable buyers)
      Good (700-749): -2%
      Fair (650-699): 0% (baseline)
      Poor (600-649): +5% (premium - perceived risk)
      Very Poor (<600): +10% (high premium)

    @param creditScore - The buyer's credit score (300-850)
    @return multiplier (e.g., 0.95 for 5% discount, 1.10 for 10% premium)
    @return adjustment percent (e.g., -5 for discount, +10 for premium)
    @return tier name for display
]]
function FinanceCalculations.getLandPriceModifier(creditScore)
    local rating, level = CreditScore.getRating(creditScore)

    local modifiers = {
        [1] = { multiplier = 0.95, percent = -5, name = "Excellent" },   -- 750+
        [2] = { multiplier = 0.98, percent = -2, name = "Good" },        -- 700-749
        [3] = { multiplier = 1.00, percent = 0, name = "Fair" },         -- 650-699
        [4] = { multiplier = 1.05, percent = 5, name = "Poor" },         -- 600-649
        [5] = { multiplier = 1.10, percent = 10, name = "Very Poor" },   -- <600
    }

    local modifier = modifiers[level] or modifiers[3]  -- Default to Fair if unknown
    return modifier.multiplier, modifier.percent, modifier.name
end

--[[
    Calculate adjusted land price with credit modifier
    @param basePrice - Original land price
    @param creditScore - Buyer's credit score
    @return adjustedPrice, adjustment amount, modifier percent, rating name
]]
function FinanceCalculations.calculateAdjustedLandPrice(basePrice, creditScore)
    local multiplier, percent, ratingName = FinanceCalculations.getLandPriceModifier(creditScore)

    local adjustedPrice = math.floor(basePrice * multiplier)
    local adjustment = adjustedPrice - basePrice  -- Negative = discount, positive = premium

    return adjustedPrice, adjustment, percent, ratingName
end

--============================================================================
-- LEASE LIFECYCLE FUNCTIONS
-- Used for lease expiration, renewal, and buyout calculations
--============================================================================

--[[
    Calculate equity accumulated during a lease
    Equity = portion of payments that went toward depreciation (not interest)
    This equity can be applied toward buyout price

    @param monthlyPayment - Monthly lease payment
    @param monthsPaid - Number of months paid
    @param totalDepreciation - Total depreciation over full term
    @param termMonths - Total lease term in months
    @return equityAccumulated - Dollar amount of equity built
]]
function FinanceCalculations.calculateLeaseEquity(monthlyPayment, monthsPaid, totalDepreciation, termMonths)
    -- Equity builds proportionally to depreciation paid
    -- At full term, equity = total depreciation
    local progressPercent = monthsPaid / termMonths
    local equityAccumulated = totalDepreciation * progressPercent

    return math.floor(equityAccumulated)
end

--[[
    Calculate security deposit refund at lease end
    Full refund if no issues, reduced for damage/missed payments

    For vehicles:
    - Deduct damage penalty from deposit
    - Deduct $100 per missed payment

    For land:
    - No damage concept
    - Deduct $200 per missed payment (more impactful for land)

    @param securityDeposit - Original deposit amount
    @param damagePenalty - Calculated damage penalty (0 for land)
    @param missedPayments - Count of missed payments during lease
    @param isLand - true if land lease, false if vehicle
    @return refundAmount - Amount to refund
    @return deductions - Table of deduction details for display
]]
function FinanceCalculations.calculateSecurityDepositRefund(securityDeposit, damagePenalty, missedPayments, isLand)
    local deductions = {}
    local totalDeductions = 0

    -- Damage penalty (vehicles only)
    if damagePenalty > 0 and not isLand then
        table.insert(deductions, {
            reason = "Damage penalty",
            amount = damagePenalty
        })
        totalDeductions = totalDeductions + damagePenalty
    end

    -- Missed payment penalty
    if missedPayments > 0 then
        local penaltyPerMiss = isLand and 200 or 100
        local missedPenalty = missedPayments * penaltyPerMiss
        table.insert(deductions, {
            reason = string.format("Missed payments (%d × %s)", missedPayments, g_i18n:formatMoney(penaltyPerMiss, 0, true, true)),
            amount = missedPenalty
        })
        totalDeductions = totalDeductions + missedPenalty
    end

    -- Calculate refund (never negative)
    local refundAmount = math.max(0, securityDeposit - totalDeductions)

    return refundAmount, deductions
end

--[[
    Calculate lease renewal terms
    When renewing, equity rolls over as a discount on the new lease

    @param currentEquity - Equity accumulated from current lease
    @param newTermMonths - New lease term in months
    @param monthlyPayment - Current monthly payment
    @param residualValue - Current residual/buyout value
    @return newMonthlyPayment - Payment for renewed lease
    @return equityRollover - Amount of equity applied
    @return newResidualValue - Updated residual after equity application
]]
function FinanceCalculations.calculateLeaseRenewal(currentEquity, newTermMonths, monthlyPayment, residualValue)
    -- Equity reduces the residual value (buyout price)
    -- This makes buyout cheaper after renewal
    local equityRollover = currentEquity
    local newResidualValue = math.max(0, residualValue - equityRollover)

    -- New monthly payment is recalculated based on remaining value to depreciate
    -- For simplicity, we'll use same payment rate but could adjust
    local newMonthlyPayment = monthlyPayment  -- Keep same for consistency

    return newMonthlyPayment, equityRollover, newResidualValue
end

--[[
    Calculate buyout price with equity applied
    Buyout = Residual Value - Equity Accumulated

    @param residualValue - Original residual/balloon value
    @param equityAccumulated - Equity built during lease
    @return buyoutPrice - Net price to purchase asset
]]
function FinanceCalculations.calculateLeaseBuyout(residualValue, equityAccumulated)
    return math.max(0, residualValue - equityAccumulated)
end

--[[
    Determine if a deal is a lease that has expired
    @param deal - The FinanceDeal object
    @return isExpired - true if lease term is complete
    @return isLease - true if this is a lease deal
]]
function FinanceCalculations.isLeaseExpired(deal)
    local isLease = (deal.dealType == 2) or (deal.itemType == "lease")
    local isExpired = deal.monthsPaid >= deal.termMonths

    return isExpired, isLease
end

UsedPlus.logInfo("FinanceCalculations utility loaded")
