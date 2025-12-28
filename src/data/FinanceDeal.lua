--[[
    FS25_UsedPlus - Finance Deal Data Class

    FinanceDeal is a data class with business logic
    Pattern from: EnhancedLoanSystem "Annuity Loan Financial Mathematics"
    Reference: FS25_ADVANCED_PATTERNS.md - Data Classes section

    Represents a single finance agreement:
    - Vehicle/Equipment/Land purchase with payment plan
    - Amortized loan with monthly payments
    - Interest/principal calculation
    - Early payoff with prepayment penalty
    - Save/load persistence
    - Network synchronization
]]

FinanceDeal = {}
local FinanceDeal_mt = Class(FinanceDeal)

-- Payment mode enum for configurable payments
FinanceDeal.PAYMENT_MODE = {
    SKIP = 0,       -- Skip payment (negative amortization)
    MINIMUM = 1,    -- Interest-only payment
    STANDARD = 2,   -- Regular amortized payment
    EXTRA = 3,      -- Double payment
    CUSTOM = 4,     -- User-defined amount
}

--[[
    Constructor for new finance deal
    Creates deal with all parameters, calculates monthly payment
]]
function FinanceDeal.new(farmId, itemType, itemId, itemName, price, downPayment, termMonths, interestRate, cashBack)
    local self = setmetatable({}, FinanceDeal_mt)

    -- Identity and classification (using DealUtils constants)
    self.dealType = DealUtils.TYPE.FINANCE
    self.id = DealUtils.generateId(self.dealType, farmId)
    self.farmId = farmId

    -- Item information
    self.itemType = itemType  -- "vehicle", "equipment", "land"
    self.itemId = itemId      -- Config filename or field ID
    self.itemName = itemName  -- Display name
    self.objectId = nil       -- Network object ID (for vehicles)

    -- Financial terms
    self.originalPrice = price
    self.downPayment = downPayment or 0
    self.cashBack = cashBack or 0
    self.amountFinanced = price - downPayment + cashBack

    self.termMonths = termMonths
    self.interestRate = interestRate / 100  -- Convert percentage to decimal
    self.monthlyPayment = 0  -- Calculated below

    -- Payment status
    self.currentBalance = self.amountFinanced
    self.monthsPaid = 0
    self.totalInterestPaid = 0
    self.status = "active"  -- active, paid_off, defaulted

    -- Tracking
    self.createdDate = g_currentMission.environment.currentDay
    self.createdMonth = g_currentMission.environment.currentMonth
    self.createdYear = g_currentMission.environment.currentYear
    self.missedPayments = 0

    -- Configurable payment fields
    self.paymentMode = FinanceDeal.PAYMENT_MODE.STANDARD  -- Default to standard payment
    self.paymentMultiplier = 1.0  -- Payment multiplier (1.0, 1.2, 1.5, 2.0, 3.0)
    self.configuredPayment = 0  -- Custom payment amount (when mode is CUSTOM)
    self.lastPaymentAmount = 0  -- Last payment actually made
    self.accruedInterest = 0    -- Unpaid interest (negative amortization)

    -- Collateral tracking (for cash loans)
    self.collateralItems = {}   -- Array of pledged vehicles: {vehicleId, objectId, configFile, name, value, farmId}
    self.repossessedItems = {}  -- Items that were repossessed on default (for history display)

    -- Calculate monthly payment using amortization formula
    self:calculatePayment()

    return self
end

--[[
    Calculate monthly payment using amortization formula
    Formula: M = P × [r(1 + r)^n] / [(1 + r)^n - 1]
    Where P = principal, r = monthly rate, n = number of months
]]
function FinanceDeal:calculatePayment()
    local P = self.amountFinanced
    local r = self.interestRate / 12  -- Monthly interest rate
    local n = self.termMonths

    -- Handle zero interest rate edge case
    if r == 0 or r < 0.0001 then
        self.monthlyPayment = P / n
    else
        -- Standard amortization formula
        local numerator = r * math.pow(1 + r, n)
        local denominator = math.pow(1 + r, n) - 1
        self.monthlyPayment = P * (numerator / denominator)
    end
end

--[[
    Calculate minimum payment (interest-only)
    This is the absolute minimum to avoid negative amortization
    @return The minimum payment amount
]]
function FinanceDeal:calculateMinimumPayment()
    local r = self.interestRate / 12
    return (self.currentBalance + self.accruedInterest) * r
end

--[[
    Get the payment amount based on current payment mode
    @return The configured payment amount for this period
]]
function FinanceDeal:getConfiguredPaymentAmount()
    local mode = self.paymentMode

    if mode == FinanceDeal.PAYMENT_MODE.SKIP then
        return 0
    elseif mode == FinanceDeal.PAYMENT_MODE.MINIMUM then
        return self:calculateMinimumPayment()
    elseif mode == FinanceDeal.PAYMENT_MODE.STANDARD then
        return self.monthlyPayment
    elseif mode == FinanceDeal.PAYMENT_MODE.EXTRA then
        return self.monthlyPayment * 2
    elseif mode == FinanceDeal.PAYMENT_MODE.CUSTOM then
        return self.configuredPayment
    end

    return self.monthlyPayment  -- Default to standard
end

--[[
    Process configurable payment with proper interest/principal split
    Handles skip, minimum, standard, extra, and custom payments
    Returns: true if paid off, false if still active
]]
function FinanceDeal:processConfiguredPayment()
    local farm = g_farmManager:getFarmById(self.farmId)
    local paymentAmount = self:getConfiguredPaymentAmount()
    local minimumPayment = self:calculateMinimumPayment()

    -- Check if farm can afford the configured payment
    if paymentAmount > 0 and farm.money < paymentAmount then
        -- Fall back to what they can afford
        if farm.money >= minimumPayment then
            paymentAmount = minimumPayment
        elseif farm.money >= 0 then
            paymentAmount = 0  -- Skip this payment
        else
            self:handleMissedPayment()
            return false
        end
    end

    -- Calculate interest due this period
    local r = self.interestRate / 12
    local interestDue = (self.currentBalance + self.accruedInterest) * r

    -- Process based on payment amount vs interest due
    if paymentAmount == 0 then
        -- Skip payment - negative amortization
        self.accruedInterest = self.accruedInterest + interestDue
        self.lastPaymentAmount = 0
        self.missedPayments = self.missedPayments + 1

        -- Record credit impact
        if CreditHistory then
            CreditHistory.recordEvent(self.farmId, "PAYMENT_SKIPPED", self.itemName)
        end

        -- Warn about increasing balance
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("Payment skipped for %s. Interest of %s added to balance.",
                self.itemName, g_i18n:formatMoney(interestDue, 0, true, true))
        )

        return false

    elseif paymentAmount < interestDue then
        -- Partial payment - some negative amortization
        local unpaidInterest = interestDue - paymentAmount
        self.accruedInterest = self.accruedInterest + unpaidInterest
        self.totalInterestPaid = self.totalInterestPaid + paymentAmount
        self.lastPaymentAmount = paymentAmount

        -- Deduct from farm
        if g_server then
            g_currentMission:addMoneyChange(-paymentAmount, self.farmId, MoneyType.OTHER, true)
        end

        -- Record credit impact
        if CreditHistory then
            CreditHistory.recordEvent(self.farmId, "PAYMENT_PARTIAL", self.itemName)
        end

        return false

    else
        -- Payment covers interest, remainder goes to principal
        local principalPayment = paymentAmount - interestDue

        -- First, pay off any accrued interest
        if self.accruedInterest > 0 and principalPayment > 0 then
            local accruedPayment = math.min(principalPayment, self.accruedInterest)
            self.accruedInterest = self.accruedInterest - accruedPayment
            principalPayment = principalPayment - accruedPayment
            self.totalInterestPaid = self.totalInterestPaid + accruedPayment
        end

        -- Apply remaining to balance
        self.currentBalance = self.currentBalance - principalPayment
        self.totalInterestPaid = self.totalInterestPaid + interestDue
        self.monthsPaid = self.monthsPaid + 1
        self.lastPaymentAmount = paymentAmount
        self.missedPayments = 0  -- Reset missed counter

        -- Sync cash loan principal payment to vanilla farm.loan for Finances page visibility
        if self.dealType == 3 and principalPayment > 0 then
            if farm.loan ~= nil and farm.loan > 0 then
                farm.loan = math.max(0, farm.loan - principalPayment)
            end
        end

        -- Deduct from farm
        if g_server then
            g_currentMission:addMoneyChange(-paymentAmount, self.farmId, MoneyType.OTHER, true)
        end

        -- Record credit impact based on payment mode
        if CreditHistory then
            if paymentAmount >= self.monthlyPayment * 1.5 then
                CreditHistory.recordEvent(self.farmId, "PAYMENT_EXTRA", self.itemName)
            elseif paymentAmount >= self.monthlyPayment then
                CreditHistory.recordEvent(self.farmId, "PAYMENT_STANDARD", self.itemName)
            else
                CreditHistory.recordEvent(self.farmId, "PAYMENT_MINIMUM", self.itemName)
            end
        end

        -- Check if paid off
        if self.currentBalance <= 0.01 then
            self.status = "paid_off"
            self.currentBalance = 0

            if CreditHistory then
                CreditHistory.recordEvent(self.farmId, "DEAL_PAID_OFF", self.itemName)
            end

            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                string.format("Congratulations! %s has been paid off!", self.itemName)
            )

            return true
        end

        return false
    end
end

--[[
    Recalculate remaining months based on current balance and payment
    Useful for showing impact of extra payments
    @return Estimated months remaining to payoff at current payment rate
]]
function FinanceDeal:recalculateRemainingMonths()
    local payment = self:getConfiguredPaymentAmount()
    local balance = self.currentBalance + self.accruedInterest
    local r = self.interestRate / 12

    if payment <= 0 or r <= 0 then
        return 999  -- Effectively infinite
    end

    -- For interest-only payments, loan never ends
    local minimumPayment = balance * r
    if payment <= minimumPayment then
        return 999
    end

    -- Standard remaining term calculation
    -- n = -log(1 - (r*P/M)) / log(1+r)
    local ratio = (r * balance) / payment
    if ratio >= 1 then
        return 999  -- Payment doesn't cover interest growth
    end

    local n = -math.log(1 - ratio) / math.log(1 + r)
    return math.ceil(n)
end

--[[
    Set payment mode for this deal
    @param mode - One of FinanceDeal.PAYMENT_MODE values
    @param customAmount - Required if mode is CUSTOM
]]
function FinanceDeal:setPaymentMode(mode, customAmount)
    self.paymentMode = mode
    if mode == FinanceDeal.PAYMENT_MODE.CUSTOM then
        self.configuredPayment = customAmount or self.monthlyPayment
    end
end

--[[
    Set payment multiplier (1.0, 1.2, 1.5, 2.0, 3.0)
    Multiplies the base monthly payment
    @param multiplier - Payment multiplier value
]]
function FinanceDeal:setPaymentMultiplier(multiplier)
    -- Validate multiplier is a reasonable value
    if multiplier and multiplier >= 1.0 and multiplier <= 5.0 then
        self.paymentMultiplier = multiplier
        -- Set mode to STANDARD to use multiplier logic
        self.paymentMode = FinanceDeal.PAYMENT_MODE.STANDARD
    end
end

--[[
    Get the actual payment amount based on current payment mode
    @return Payment amount that will be charged
]]
function FinanceDeal:getConfiguredPayment()
    local mode = self.paymentMode or FinanceDeal.PAYMENT_MODE.STANDARD
    local multiplier = self.paymentMultiplier or 1.0

    if mode == FinanceDeal.PAYMENT_MODE.SKIP then
        return 0
    elseif mode == FinanceDeal.PAYMENT_MODE.MINIMUM then
        -- Minimum is interest-only (or 30% of standard as fallback)
        if self.calculateMinimumPayment then
            return self:calculateMinimumPayment()
        else
            return (self.monthlyPayment or 0) * 0.3
        end
    elseif mode == FinanceDeal.PAYMENT_MODE.STANDARD then
        -- Apply payment multiplier (1x, 1.2x, 1.5x, 2x, 3x)
        return (self.monthlyPayment or 0) * multiplier
    elseif mode == FinanceDeal.PAYMENT_MODE.EXTRA then
        -- Legacy 2x mode - still works but multiplier is preferred
        return (self.monthlyPayment or 0) * 2
    elseif mode == FinanceDeal.PAYMENT_MODE.CUSTOM then
        return self.configuredPayment or self.monthlyPayment or 0
    end

    -- Default: apply multiplier
    return (self.monthlyPayment or 0) * multiplier
end

--[[
    Get effective balance including accrued interest
    @return Total amount owed
]]
function FinanceDeal:getEffectiveBalance()
    return self.currentBalance + self.accruedInterest
end

--[[
    Calculate projected payoff info based on current multiplier
    Returns: monthsRemaining, totalInterestIfNormal, totalInterestWithMultiplier, interestSaved
]]
function FinanceDeal:calculateMultiplierSavings()
    local multiplier = self.paymentMultiplier or 1.0
    local basePayment = self.monthlyPayment or 0
    local monthlyRate = (self.interestRate or 0) / 12
    local balance = self.currentBalance or 0

    -- If no balance or no multiplier effect, no savings
    if balance <= 0 or multiplier <= 1.0 then
        local remainingMonths = math.max(0, (self.termMonths or 0) - (self.monthsPaid or 0))
        return remainingMonths, 0, 0, 0
    end

    -- Calculate remaining interest at 1x (normal payments)
    local normalBalance = balance
    local normalInterest = 0
    local normalMonths = 0
    local maxIterations = 600  -- Safety limit (50 years)

    while normalBalance > 0.01 and normalMonths < maxIterations do
        local interestPortion = monthlyRate * normalBalance
        local principalPortion = basePayment - interestPortion
        if principalPortion <= 0 then break end  -- Payment doesn't cover interest
        normalBalance = normalBalance - principalPortion
        normalInterest = normalInterest + interestPortion
        normalMonths = normalMonths + 1
    end

    -- Calculate remaining interest with multiplier
    local multipliedPayment = basePayment * multiplier
    local multipliedBalance = balance
    local multipliedInterest = 0
    local multipliedMonths = 0

    while multipliedBalance > 0.01 and multipliedMonths < maxIterations do
        local interestPortion = monthlyRate * multipliedBalance
        local principalPortion = multipliedPayment - interestPortion
        if principalPortion <= 0 then break end
        multipliedBalance = multipliedBalance - principalPortion
        multipliedInterest = multipliedInterest + interestPortion
        multipliedMonths = multipliedMonths + 1
    end

    local interestSaved = normalInterest - multipliedInterest
    return multipliedMonths, normalInterest, multipliedInterest, interestSaved
end

--[[
    Process a single monthly payment
    Uses payment multiplier to allow paying extra toward principal
    Extra payments reduce principal faster, saving on total interest
    Returns: true if paid off, false if still active
]]
function FinanceDeal:processMonthlyPayment()
    local farm = g_farmManager:getFarmById(self.farmId)

    -- Get the actual payment amount (with multiplier applied)
    local paymentAmount = self:getConfiguredPayment()
    local basePayment = self.monthlyPayment or 0

    -- Check if farm can afford at least the base payment
    if farm.money < basePayment then
        self:handleMissedPayment()
        return false
    end

    -- If configured payment is more than available funds, pay what we can (at least base)
    if farm.money < paymentAmount then
        paymentAmount = math.max(basePayment, farm.money)
    end

    -- Calculate interest portion (interest on remaining balance)
    local interestPortion = (self.interestRate / 12) * self.currentBalance

    -- Calculate principal portion (everything above interest goes to principal)
    -- With multiplier > 1, MORE goes to principal reduction = faster payoff
    local principalPortion = paymentAmount - interestPortion

    -- Ensure we don't overpay
    if principalPortion > self.currentBalance then
        principalPortion = self.currentBalance
        paymentAmount = principalPortion + interestPortion
    end

    -- Apply payment to balance
    self.currentBalance = self.currentBalance - principalPortion
    self.monthsPaid = self.monthsPaid + 1
    self.totalInterestPaid = self.totalInterestPaid + interestPortion
    self.lastPaymentAmount = paymentAmount
    self.missedPayments = 0  -- Reset missed payment counter

    -- Deduct money from farm (server only)
    if g_server then
        g_currentMission:addMoneyChange(-paymentAmount, self.farmId, MoneyType.OTHER, true)
    end

    -- Check if paid off (balance near zero)
    if self.currentBalance <= 0.01 then
        self.status = "paid_off"
        self.currentBalance = 0
        return true
    end

    return false
end

--[[
    Handle missed payment
    Track consecutive missed payments
    Send warnings, potential seizure for land
]]
function FinanceDeal:handleMissedPayment()
    self.missedPayments = self.missedPayments + 1

    -- Send notifications based on item type and missed count
    if self.itemType == "land" then
        self:handleMissedLandPayment()
    elseif self.itemType == "loan" then
        self:handleMissedLoanPayment()
    else
        self:handleMissedVehiclePayment()
    end
end

--[[
    Handle missed land payment (stricter consequences)
    3 strikes = land seizure
]]
function FinanceDeal:handleMissedLandPayment()
    -- Accrue interest on missed payment (balance grows)
    local monthlyInterest = (self.interestRate / 12) * self.currentBalance
    self.accruedInterest = (self.accruedInterest or 0) + monthlyInterest

    -- Record credit impact
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "PAYMENT_MISSED", self.itemName)
    end

    if self.missedPayments == 1 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Missed land payment for %s! Interest of %s added. (1st warning)",
                self.itemName, g_i18n:formatMoney(monthlyInterest, 0, true, true)))
    elseif self.missedPayments == 2 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("FINAL WARNING: Missed land payment for %s! One more = SEIZURE!",
                self.itemName))
    elseif self.missedPayments >= 3 then
        self:seizeLand()
    end
end

--[[
    Handle missed vehicle payment
    3 strikes = vehicle repossession (same as land for consistency)
]]
function FinanceDeal:handleMissedVehiclePayment()
    -- Accrue interest on missed payment (balance grows)
    local monthlyInterest = (self.interestRate / 12) * self.currentBalance
    self.accruedInterest = (self.accruedInterest or 0) + monthlyInterest

    -- Record credit impact
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "PAYMENT_MISSED", self.itemName)
    end

    if self.missedPayments == 1 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("Missed payment for %s. Interest of %s added to balance. (1st warning)",
                self.itemName, g_i18n:formatMoney(monthlyInterest, 0, true, true)))
    elseif self.missedPayments == 2 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("FINAL WARNING: Missed payment for %s. One more missed payment will result in repossession!",
                self.itemName))
    elseif self.missedPayments >= 3 then
        self:repossessVehicle()
    end
end

--[[
    Repossess vehicle after 3 missed payments
    Remove vehicle from world, mark deal as defaulted
]]
function FinanceDeal:repossessVehicle()
    if not g_server then return end

    -- Find and remove the vehicle
    local vehicle = self:findVehicle()
    if vehicle then
        -- Log before removal
        UsedPlus.logDebug(string.format("Repossessing vehicle: %s (deal %s)", self.itemName, self.id))

        -- Remove vehicle using SellVehicleEvent with $0 payout (repossession)
        -- SellVehicleEvent.new(vehicle, price, isFullPrice)
        -- Price of 0 or 1 means no/minimal money returned to player
        local sellEvent = SellVehicleEvent.new(vehicle, 0, false)

        -- On server, run the event directly; the event handles the actual vehicle removal
        if g_server then
            sellEvent:run(nil)
        else
            -- Shouldn't reach here since we check g_server at start, but just in case
            g_client:getServerConnection():sendEvent(sellEvent)
        end

        UsedPlus.logInfo(string.format("Vehicle repossessed via SellVehicleEvent: %s", self.itemName))
    else
        UsedPlus.logWarn(string.format("Could not find vehicle for repossession (deal %s)", self.id))
    end

    -- Mark deal as defaulted
    self.status = "defaulted"
    self.currentBalance = 0

    -- Record credit impact (severe)
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "VEHICLE_REPOSSESSED", self.itemName)
    end

    -- Send critical notification
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
        string.format("VEHICLE REPOSSESSED: %s has been taken due to non-payment!", self.itemName))
end

--[[
    Find the vehicle associated with this finance deal
    @return vehicle object or nil
]]
function FinanceDeal:findVehicle()
    -- Try by objectId first (most reliable)
    if self.objectId then
        local vehicle = NetworkUtil.getObject(self.objectId)
        if vehicle then return vehicle end
    end

    -- Search by config filename and farm
    local configFile = self.itemId
    if configFile then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.configFileName == configFile and
               vehicle.ownerFarmId == self.farmId then
                return vehicle
            end
        end
    end

    return nil
end

--[[
    Seize land after 3 missed payments
    Transfer ownership back to unowned
    Mark deal as defaulted
]]
function FinanceDeal:seizeLand()
    -- Find the field and transfer ownership
    if g_server and self.itemType == "land" then
        local fieldId = tonumber(self.itemId)
        if fieldId ~= nil then
            g_farmlandManager:setLandOwnership(fieldId, 0)  -- 0 = unowned
        end
    end

    -- Mark deal as defaulted
    self.status = "defaulted"

    -- Send critical notification
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
        string.format(g_i18n:getText("usedplus_notification_landSeized"), self.itemName))
end

--[[
    Handle missed cash loan payment
    Cash loans have pledged collateral that gets repossessed on default
    3 strikes = collateral repossession
]]
function FinanceDeal:handleMissedLoanPayment()
    -- Accrue interest on missed payment (balance grows)
    local monthlyInterest = (self.interestRate / 12) * self.currentBalance
    self.accruedInterest = (self.accruedInterest or 0) + monthlyInterest

    -- Record credit impact
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "PAYMENT_MISSED", self.itemName)
    end

    -- Check if we have collateral
    local hasCollateral = self.collateralItems and #self.collateralItems > 0

    if self.missedPayments == 1 then
        local warningMsg = hasCollateral
            and string.format("Missed loan payment! Interest of %s added. Your pledged collateral (%d items) is at risk! (1st warning)",
                g_i18n:formatMoney(monthlyInterest, 0, true, true), #self.collateralItems)
            or string.format("Missed loan payment! Interest of %s added. (1st warning)",
                g_i18n:formatMoney(monthlyInterest, 0, true, true))

        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, warningMsg)

    elseif self.missedPayments == 2 then
        local warningMsg = hasCollateral
            and string.format("FINAL WARNING: Missed loan payment! One more = COLLATERAL REPOSSESSED! (%d vehicles at stake)",
                #self.collateralItems)
            or "FINAL WARNING: Missed loan payment! One more missed payment will result in loan default!"

        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, warningMsg)

    elseif self.missedPayments >= 3 then
        self:repossessCollateral()
    end
end

--[[
    Repossess collateral after 3 missed loan payments
    Removes all pledged vehicles and marks deal as defaulted
]]
function FinanceDeal:repossessCollateral()
    if not g_server then return end

    -- Initialize repossessedItems if needed
    self.repossessedItems = self.repossessedItems or {}

    local repossessedCount = 0
    local repossessedValue = 0

    -- Process each pledged collateral item
    if self.collateralItems and #self.collateralItems > 0 then
        for _, collateralItem in ipairs(self.collateralItems) do
            -- Find the vehicle
            local vehicle = nil

            if CollateralUtils and CollateralUtils.findPledgedVehicle then
                vehicle = CollateralUtils.findPledgedVehicle(collateralItem, self.farmId)
            else
                -- Fallback: try by objectId
                if collateralItem.objectId then
                    vehicle = NetworkUtil.getObject(collateralItem.objectId)
                end
            end

            if vehicle then
                -- Store repossession record for history
                table.insert(self.repossessedItems, {
                    name = collateralItem.name or vehicle:getName() or "Unknown Vehicle",
                    value = collateralItem.value or 0,
                    configFile = collateralItem.configFile or vehicle.configFileName,
                    repossessedDate = g_currentMission.environment.currentDay,
                    repossessedMonth = g_currentMission.environment.currentMonth,
                    repossessedYear = g_currentMission.environment.currentYear
                })

                -- Remove vehicle using SellVehicleEvent with $0 payout (repossession)
                local sellEvent = SellVehicleEvent.new(vehicle, 0, false)
                if g_server then
                    sellEvent:run(nil)
                end

                repossessedCount = repossessedCount + 1
                repossessedValue = repossessedValue + (collateralItem.value or 0)

                UsedPlus.logInfo(string.format("Collateral repossessed: %s (value: %s)",
                    collateralItem.name or "Unknown",
                    g_i18n:formatMoney(collateralItem.value or 0, 0, true, true)))
            else
                -- Vehicle not found (might have been sold/destroyed)
                UsedPlus.logWarn(string.format("Could not find pledged vehicle for repossession: %s",
                    collateralItem.name or "Unknown"))

                -- Still record it as repossessed for history
                table.insert(self.repossessedItems, {
                    name = collateralItem.name or "Unknown Vehicle",
                    value = collateralItem.value or 0,
                    configFile = collateralItem.configFile,
                    repossessedDate = g_currentMission.environment.currentDay,
                    repossessedMonth = g_currentMission.environment.currentMonth,
                    repossessedYear = g_currentMission.environment.currentYear,
                    notFound = true  -- Flag that vehicle wasn't found
                })
            end
        end
    end

    -- Mark deal as defaulted
    self.status = "defaulted"
    self.currentBalance = 0  -- Debt cleared (collateral seized)

    -- Record severe credit impact
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LOAN_DEFAULTED", self.itemName)
    end

    -- Send notification
    local notificationMsg
    if repossessedCount > 0 then
        notificationMsg = string.format(
            "LOAN DEFAULTED! %d vehicle(s) worth %s have been repossessed!",
            repossessedCount,
            g_i18n:formatMoney(repossessedValue, 0, true, true))
    else
        notificationMsg = "LOAN DEFAULTED! No collateral could be recovered."
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, notificationMsg)
end

--[[
    Set collateral items for this deal (used when creating cash loans)
    @param items - Array of collateral items from CollateralUtils
]]
function FinanceDeal:setCollateralItems(items)
    self.collateralItems = items or {}
end

--[[
    Get collateral items
    @return table - Array of collateral items
]]
function FinanceDeal:getCollateralItems()
    return self.collateralItems or {}
end

--[[
    Get repossessed items (for displaying in deal history)
    @return table - Array of repossessed item records
]]
function FinanceDeal:getRepossessedItems()
    return self.repossessedItems or {}
end

--[[
    Make a manual payment (player-initiated)
    Can pay extra to reduce term or pay off early
    Returns: success (bool), message (string)
]]
function FinanceDeal:makePayment(amount)
    local farm = g_farmManager:getFarmById(self.farmId)

    -- Validate amount
    if amount < self.monthlyPayment then
        return false, g_i18n:getText("usedplus_error_paymentTooLow")
    end

    local payoffAmount = self:getPayoffAmount()
    if amount > payoffAmount then
        return false, g_i18n:getText("usedplus_error_paymentTooHigh")
    end

    if farm.money < amount then
        return false, g_i18n:getText("usedplus_error_insufficientFunds")
    end

    -- Calculate how many months this payment covers
    local numMonths = math.floor(amount / self.monthlyPayment)

    -- Process each month's interest/principal split
    local totalInterest = 0
    local tempBalance = self.currentBalance

    for i = 1, numMonths do
        local monthlyInterest = (self.interestRate / 12) * tempBalance
        totalInterest = totalInterest + monthlyInterest
        tempBalance = tempBalance - (self.monthlyPayment - monthlyInterest)
    end

    local principal = amount - totalInterest

    -- Check if this is a full payoff
    if amount >= payoffAmount then
        local penalty = self:getPrepaymentPenalty()
        totalInterest = totalInterest + penalty
        principal = self.currentBalance
        self.status = "paid_off"
    end

    -- Apply payment
    self.currentBalance = self.currentBalance - principal
    self.monthsPaid = self.monthsPaid + numMonths
    self.totalInterestPaid = self.totalInterestPaid + totalInterest

    -- Sync cash loan principal payment to vanilla farm.loan for Finances page visibility
    if self.dealType == 3 and principal > 0 then
        if farm.loan ~= nil and farm.loan > 0 then
            farm.loan = math.max(0, farm.loan - principal)
        end
    end

    -- Deduct money
    if g_server then
        g_currentMission:addMoneyChange(-amount, self.farmId, MoneyType.OTHER, true)
    end

    return true, g_i18n:getText("usedplus_success_paymentMade")
end

--[[
    Get prepayment penalty for early payoff
    2% if > 12 months remaining, 1% if <= 12 months
]]
function FinanceDeal:getPrepaymentPenalty()
    local remainingMonths = self.termMonths - self.monthsPaid
    local penaltyPercent = 0.02  -- 2% default

    -- Reduce penalty if near end of term
    if remainingMonths <= 12 then
        penaltyPercent = 0.01  -- 1% if less than 1 year left
    end

    return self.currentBalance * penaltyPercent
end

--[[
    Get total amount needed to pay off deal
    Includes prepayment penalty
]]
function FinanceDeal:getPayoffAmount()
    return self.currentBalance + self:getPrepaymentPenalty()
end

--[[
    Save deal to XML savegame
    Pattern from: EnhancedLoanSystem nested XML serialization
]]
function FinanceDeal:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. "#id", self.id)
    xmlFile:setInt(key .. "#dealType", self.dealType)
    xmlFile:setInt(key .. "#farmId", self.farmId)
    xmlFile:setString(key .. "#itemType", self.itemType)
    xmlFile:setString(key .. "#itemId", self.itemId)
    xmlFile:setString(key .. "#itemName", self.itemName)
    xmlFile:setFloat(key .. "#originalPrice", self.originalPrice)
    xmlFile:setFloat(key .. "#downPayment", self.downPayment)
    xmlFile:setFloat(key .. "#cashBack", self.cashBack)
    xmlFile:setFloat(key .. "#amountFinanced", self.amountFinanced)
    xmlFile:setInt(key .. "#termMonths", self.termMonths)
    xmlFile:setFloat(key .. "#interestRate", self.interestRate * 100)  -- Save as percentage
    xmlFile:setFloat(key .. "#monthlyPayment", self.monthlyPayment)
    xmlFile:setFloat(key .. "#currentBalance", self.currentBalance)
    xmlFile:setInt(key .. "#monthsPaid", self.monthsPaid)
    xmlFile:setFloat(key .. "#totalInterestPaid", self.totalInterestPaid)
    xmlFile:setString(key .. "#status", self.status)
    xmlFile:setInt(key .. "#createdDate", self.createdDate)
    xmlFile:setInt(key .. "#createdMonth", self.createdMonth or 1)
    xmlFile:setInt(key .. "#createdYear", self.createdYear or 2025)
    xmlFile:setInt(key .. "#missedPayments", self.missedPayments)

    -- Save payment configuration fields
    xmlFile:setInt(key .. "#paymentMode", self.paymentMode or FinanceDeal.PAYMENT_MODE.STANDARD)
    xmlFile:setFloat(key .. "#paymentMultiplier", self.paymentMultiplier or 1.0)
    xmlFile:setFloat(key .. "#configuredPayment", self.configuredPayment or 0)
    xmlFile:setFloat(key .. "#lastPaymentAmount", self.lastPaymentAmount or 0)
    xmlFile:setFloat(key .. "#accruedInterest", self.accruedInterest or 0)

    -- Save lease-specific fields
    if self.dealType == 2 then  -- Lease type
        xmlFile:setFloat(key .. "#residualValue", self.residualValue or 0)
        xmlFile:setFloat(key .. "#securityDeposit", self.securityDeposit or 0)
        xmlFile:setFloat(key .. "#depreciation", self.depreciation or 0)
        xmlFile:setFloat(key .. "#tradeInValue", self.tradeInValue or 0)
    end

    if self.objectId ~= nil then
        xmlFile:setInt(key .. "#objectId", self.objectId)
    end

    -- Save collateral items (for cash loans)
    if self.collateralItems and #self.collateralItems > 0 then
        xmlFile:setInt(key .. "#collateralCount", #self.collateralItems)
        for i, item in ipairs(self.collateralItems) do
            local itemKey = string.format("%s.collateral(%d)", key, i - 1)
            xmlFile:setString(itemKey .. "#vehicleId", item.vehicleId or "")
            xmlFile:setInt(itemKey .. "#objectId", item.objectId or 0)
            xmlFile:setString(itemKey .. "#configFile", item.configFile or "")
            xmlFile:setString(itemKey .. "#name", item.name or "")
            xmlFile:setFloat(itemKey .. "#value", item.value or 0)
            xmlFile:setInt(itemKey .. "#farmId", item.farmId or self.farmId)
        end
    end

    -- Save repossessed items (for defaulted loans history)
    if self.repossessedItems and #self.repossessedItems > 0 then
        xmlFile:setInt(key .. "#repossessedCount", #self.repossessedItems)
        for i, item in ipairs(self.repossessedItems) do
            local itemKey = string.format("%s.repossessed(%d)", key, i - 1)
            xmlFile:setString(itemKey .. "#name", item.name or "")
            xmlFile:setFloat(itemKey .. "#value", item.value or 0)
            xmlFile:setString(itemKey .. "#configFile", item.configFile or "")
            xmlFile:setInt(itemKey .. "#repossessedDate", item.repossessedDate or 0)
            xmlFile:setInt(itemKey .. "#repossessedMonth", item.repossessedMonth or 1)
            xmlFile:setInt(itemKey .. "#repossessedYear", item.repossessedYear or 2025)
            xmlFile:setBool(itemKey .. "#notFound", item.notFound or false)
        end
    end
end

--[[
    Load deal from XML savegame
    Returns: true if successful, false if corrupt data
]]
function FinanceDeal:loadFromXMLFile(xmlFile, key)
    self.id = xmlFile:getString(key .. "#id")

    -- Validate required fields
    if self.id == nil or self.id == "" then
        UsedPlus.logWarn("Corrupt finance deal in savegame, skipping")
        return false
    end

    self.dealType = xmlFile:getInt(key .. "#dealType", 1)
    self.farmId = xmlFile:getInt(key .. "#farmId")
    self.itemType = xmlFile:getString(key .. "#itemType")
    self.itemId = xmlFile:getString(key .. "#itemId")
    self.itemName = xmlFile:getString(key .. "#itemName")
    self.originalPrice = xmlFile:getFloat(key .. "#originalPrice")
    self.downPayment = xmlFile:getFloat(key .. "#downPayment")
    self.cashBack = xmlFile:getFloat(key .. "#cashBack", 0)
    self.amountFinanced = xmlFile:getFloat(key .. "#amountFinanced")
    self.termMonths = xmlFile:getInt(key .. "#termMonths")
    self.interestRate = xmlFile:getFloat(key .. "#interestRate") / 100  -- Convert from percentage
    self.monthlyPayment = xmlFile:getFloat(key .. "#monthlyPayment")
    self.currentBalance = xmlFile:getFloat(key .. "#currentBalance")
    self.monthsPaid = xmlFile:getInt(key .. "#monthsPaid")
    self.totalInterestPaid = xmlFile:getFloat(key .. "#totalInterestPaid", 0)
    self.status = xmlFile:getString(key .. "#status", "active")
    self.createdDate = xmlFile:getInt(key .. "#createdDate")
    self.createdMonth = xmlFile:getInt(key .. "#createdMonth", 1)
    self.createdYear = xmlFile:getInt(key .. "#createdYear", 2025)
    self.missedPayments = xmlFile:getInt(key .. "#missedPayments", 0)
    self.objectId = xmlFile:getInt(key .. "#objectId")

    -- Load payment configuration fields
    self.paymentMode = xmlFile:getInt(key .. "#paymentMode", FinanceDeal.PAYMENT_MODE.STANDARD)
    self.paymentMultiplier = xmlFile:getFloat(key .. "#paymentMultiplier", 1.0)
    self.configuredPayment = xmlFile:getFloat(key .. "#configuredPayment", 0)
    self.lastPaymentAmount = xmlFile:getFloat(key .. "#lastPaymentAmount", 0)
    self.accruedInterest = xmlFile:getFloat(key .. "#accruedInterest", 0)

    -- Load lease-specific fields
    if self.dealType == 2 then  -- Lease type
        self.residualValue = xmlFile:getFloat(key .. "#residualValue", 0)
        self.securityDeposit = xmlFile:getFloat(key .. "#securityDeposit", 0)
        self.depreciation = xmlFile:getFloat(key .. "#depreciation", 0)
        self.tradeInValue = xmlFile:getFloat(key .. "#tradeInValue", 0)
    end

    -- Load collateral items (for cash loans)
    self.collateralItems = {}
    local collateralCount = xmlFile:getInt(key .. "#collateralCount", 0)
    for i = 0, collateralCount - 1 do
        local itemKey = string.format("%s.collateral(%d)", key, i)
        local item = {
            vehicleId = xmlFile:getString(itemKey .. "#vehicleId", ""),
            objectId = xmlFile:getInt(itemKey .. "#objectId", 0),
            configFile = xmlFile:getString(itemKey .. "#configFile", ""),
            name = xmlFile:getString(itemKey .. "#name", ""),
            value = xmlFile:getFloat(itemKey .. "#value", 0),
            farmId = xmlFile:getInt(itemKey .. "#farmId", self.farmId)
        }
        table.insert(self.collateralItems, item)
    end

    -- Load repossessed items (for defaulted loans history)
    self.repossessedItems = {}
    local repossessedCount = xmlFile:getInt(key .. "#repossessedCount", 0)
    for i = 0, repossessedCount - 1 do
        local itemKey = string.format("%s.repossessed(%d)", key, i)
        local item = {
            name = xmlFile:getString(itemKey .. "#name", ""),
            value = xmlFile:getFloat(itemKey .. "#value", 0),
            configFile = xmlFile:getString(itemKey .. "#configFile", ""),
            repossessedDate = xmlFile:getInt(itemKey .. "#repossessedDate", 0),
            repossessedMonth = xmlFile:getInt(itemKey .. "#repossessedMonth", 1),
            repossessedYear = xmlFile:getInt(itemKey .. "#repossessedYear", 2025),
            notFound = xmlFile:getBool(itemKey .. "#notFound", false)
        }
        table.insert(self.repossessedItems, item)
    end

    return true
end

UsedPlus.logInfo("FinanceDeal class loaded")
