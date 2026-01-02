--[[
    FS25_UsedPlus - Unified Purchase Dialog

     Single dialog for all purchase modes (Cash, Finance, Lease)
    with integrated Trade-In support. Replaces separate dialogs for cleaner UX.

    Features:
    - Mode selector: Buy with Cash, Finance, Lease
    - Trade-in support for all modes
    - Dynamic section visibility based on mode
    - Unified calculations and purchase flow
]]

UnifiedPurchaseDialog = {}
local UnifiedPurchaseDialog_mt = Class(UnifiedPurchaseDialog, MessageDialog)

-- Purchase modes
UnifiedPurchaseDialog.MODE_CASH = 1
UnifiedPurchaseDialog.MODE_FINANCE = 2
UnifiedPurchaseDialog.MODE_LEASE = 3

UnifiedPurchaseDialog.MODE_TEXTS = {"Buy with Cash", "Finance", "Lease"}

-- Term options
UnifiedPurchaseDialog.FINANCE_TERMS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20}  -- Years (1-year increments)
-- Lease terms in months - standard lease options (1-5 years)
-- Vehicle leases beyond 5 years don't make financial sense - just buy it!
UnifiedPurchaseDialog.LEASE_TERMS = {12, 24, 36, 48, 60}
UnifiedPurchaseDialog.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}  -- Percent
UnifiedPurchaseDialog.CASH_BACK_OPTIONS = {0, 500, 1000, 2500, 5000, 10000}

--[[
    Get available down payment options based on settings minimum
    @return filtered table of down payment percentages
]]
function UnifiedPurchaseDialog.getDownPaymentOptions()
    local minPercent = UsedPlusSettings and UsedPlusSettings:get("minDownPaymentPercent") or 0
    local options = {}
    for _, pct in ipairs(UnifiedPurchaseDialog.DOWN_PAYMENT_OPTIONS) do
        if pct >= minPercent then
            table.insert(options, pct)
        end
    end
    -- Ensure at least one option exists
    if #options == 0 then
        options = {minPercent}
    end
    return options
end

--[[
    Get the actual down payment percentage for a given dropdown index
    Uses filtered options from settings
    @param index - Dropdown index (1-based)
    @return percentage value
]]
function UnifiedPurchaseDialog.getDownPaymentPercent(index)
    local options = UnifiedPurchaseDialog.getDownPaymentOptions()
    return options[index] or options[1] or 0
end

--[[
    Constructor
]]
function UnifiedPurchaseDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or UnifiedPurchaseDialog_mt)

    -- Current state
    self.currentMode = UnifiedPurchaseDialog.MODE_CASH
    self.tradeInEnabled = false
    self.tradeInVehicle = nil
    self.tradeInValue = 0

    -- Vehicle data
    self.storeItem = nil
    self.vehiclePrice = 0
    self.vehicleName = ""
    self.vehicleCategory = ""
    self.isUsedVehicle = false
    self.usedCondition = 100
    self.saleItem = nil  -- For used vehicle purchases

    -- Finance parameters
    self.financeTermIndex = 5  -- Default 5 years
    self.financeDownIndex = 3  -- Default 10%
    self.financeCashBackIndex = 1  -- Default $0

    -- Lease parameters (LEASE_TERMS is in months: index 3 = 36 months = 3 years)
    self.leaseTermIndex = 3  -- Default 3 years (36 months)
    self.leaseDownIndex = 3  -- Default 10%

    -- Credit data
    self.creditScore = 650
    self.creditRating = "Fair"
    self.interestRate = 0.08

    -- Trade-in vehicles list
    self.eligibleTradeIns = {}

    return self
end

--[[
    Called when GUI elements are ready
]]
function UnifiedPurchaseDialog:onGuiSetupFinished()
    UnifiedPurchaseDialog:superClass().onGuiSetupFinished(self)

    -- Setup mode selector
    if self.modeSelector then
        self.modeSelector:setTexts(UnifiedPurchaseDialog.MODE_TEXTS)
        self.modeSelector:setState(1)  -- Default to Cash
    end

    -- Setup finance term slider
    if self.financeTermSlider then
        local texts = {}
        for _, years in ipairs(UnifiedPurchaseDialog.FINANCE_TERMS) do
            table.insert(texts, years .. (years == 1 and " Year" or " Years"))
        end
        self.financeTermSlider:setTexts(texts)
        self.financeTermSlider:setState(self.financeTermIndex)
    end

    -- Setup finance down payment slider (uses filtered options from settings)
    if self.financeDownSlider then
        local options = UnifiedPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.financeDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.financeDownIndex = math.min(self.financeDownIndex, #options)
        self.financeDownSlider:setState(self.financeDownIndex)
    end

    -- Setup finance cash back slider
    if self.financeCashBackSlider then
        local texts = {}
        for _, amount in ipairs(UnifiedPurchaseDialog.CASH_BACK_OPTIONS) do
            table.insert(texts, g_i18n:formatMoney(amount, 0, true, true))
        end
        self.financeCashBackSlider:setTexts(texts)
        self.financeCashBackSlider:setState(self.financeCashBackIndex)
    end

    -- Setup lease term slider (terms are in months)
    if self.leaseTermSlider then
        local texts = {}
        for _, months in ipairs(UnifiedPurchaseDialog.LEASE_TERMS) do
            if months < 12 then
                table.insert(texts, months .. (months == 1 and " Month" or " Months"))
            elseif months == 12 then
                table.insert(texts, "1 Year")
            else
                local years = months / 12
                table.insert(texts, years .. " Years")
            end
        end
        self.leaseTermSlider:setTexts(texts)
        self.leaseTermSlider:setState(self.leaseTermIndex)
    end

    -- Setup lease down payment slider (uses filtered options from settings)
    if self.leaseDownSlider then
        local options = UnifiedPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.leaseDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.leaseDownIndex = math.min(self.leaseDownIndex, #options)
        self.leaseDownSlider:setState(self.leaseDownIndex)
    end

end

--[[
    Set vehicle data for purchase
]]
function UnifiedPurchaseDialog:setVehicleData(storeItem, price, saleItem)
    self.storeItem = storeItem
    self.vehiclePrice = price or 0
    self.saleItem = saleItem

    -- Use consolidated utility functions for vehicle name and category
    self.vehicleName = UIHelper.Vehicle.getFullName(storeItem)
    self.vehicleCategory = storeItem and UIHelper.Vehicle.getCategoryName(storeItem) or ""

    -- Check if this is a used vehicle
    if saleItem then
        self.isUsedVehicle = true
        self.usedCondition = saleItem.condition or 100
    else
        self.isUsedVehicle = false
        self.usedCondition = 100
    end

    -- Set item image with dynamic scaling to prevent stretching
    -- Using 210x105 (2:1 ratio) to match FS25 store image format (512x256)
    if self.itemImage then
        UIHelper.Image.setStoreItemImageScaled(self.itemImage, storeItem, 210, 105)
    end

    -- Calculate credit parameters
    self:calculateCreditParameters()

    -- Load eligible trade-in vehicles
    self:loadEligibleTradeIns()
end

--[[
    Set initial mode (called from shop extension)
]]
function UnifiedPurchaseDialog:setInitialMode(mode)
    self.currentMode = mode or UnifiedPurchaseDialog.MODE_CASH

    if self.modeSelector then
        self.modeSelector:setState(self.currentMode)
    end
end

--[[
    Calculate credit parameters
]]
function UnifiedPurchaseDialog:calculateCreditParameters()
    local farmId = g_currentMission:getFarmId()

    if CreditScore then
        self.creditScore = CreditScore.calculate(farmId)
        self.creditRating = CreditScore.getRating(self.creditScore)

        -- Calculate interest rate based on credit
        local baseRate = 0.08
        local adjustment = CreditScore.getInterestAdjustment(self.creditScore) or 0
        self.interestRate = math.max(0.03, math.min(0.15, baseRate + adjustment))

        -- Check qualification for each financing type
        self.canFinance, self.financeMinScore = CreditScore.canFinance(farmId, "VEHICLE_FINANCE")
        self.canLease, self.leaseMinScore = CreditScore.canFinance(farmId, "VEHICLE_LEASE")
    else
        self.creditScore = 650
        self.creditRating = "Fair"
        self.interestRate = 0.08
        self.canFinance = true
        self.canLease = true
        self.financeMinScore = 550
        self.leaseMinScore = 600
    end
end

--[[
    Check if current mode is available based on credit score and minimum amounts
    @return isAvailable (boolean), message (string or nil)
]]
function UnifiedPurchaseDialog:isModeAvailable()
    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        return true, nil  -- Cash is always available
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        -- Check minimum financing amount first
        if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
            local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(self.vehiclePrice, "VEHICLE_FINANCE")
            if not meetsMinimum then
                local msg = string.format(g_i18n:getText("usedplus_finance_amountTooSmall") or "Amount too small for financing. Minimum: %s",
                    g_i18n:formatMoney(minRequired, 0, true, true))
                return false, msg
            end
        end
        -- Then check credit score
        if not self.canFinance then
            local msgTemplate = g_i18n:getText("usedplus_credit_tooLowForFinancing")
            return false, string.format(msgTemplate, self.creditScore, self.financeMinScore or 550)
        end
        return true, nil
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        -- Check minimum lease amount first
        if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
            local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(self.vehiclePrice, "VEHICLE_LEASE")
            if not meetsMinimum then
                local msg = string.format(g_i18n:getText("usedplus_lease_amountTooSmall") or "Amount too small for leasing. Minimum: %s",
                    g_i18n:formatMoney(minRequired, 0, true, true))
                return false, msg
            end
        end
        -- Then check credit score
        if not self.canLease then
            local msgTemplate = g_i18n:getText("usedplus_credit_tooLowForLeasing")
            return false, string.format(msgTemplate, self.creditScore, self.leaseMinScore or 600)
        end
        return true, nil
    end
    return true, nil
end

--[[
    Calculate credit score modifier for trade-in values
    Better credit = higher trade-in offer (dealers trust you more for financing)

    Trade-in value hierarchy (must be LESS than agent sales!):
    - Trade-In: 50-65% of sell price (instant, convenient)
    - Local Agent: 60-75% (1-2 months wait)
    - Regional Agent: 75-90% (2-4 months wait)
    - National Agent: 90-100% (3-6 months wait)

    Credit impact on trade-in (50-65% range):
    - 800-850: Exceptional -> 65% of sell price
    - 740-799: Very Good   -> 61% of sell price
    - 670-739: Good        -> 57% of sell price
    - 580-669: Fair        -> 53% of sell price
    - 300-579: Poor        -> 50% of sell price

    Condition (damage + wear) further reduces value by up to 30%
]]
function UnifiedPurchaseDialog:getCreditTradeInMultiplier()
    local score = self.creditScore or 650

    -- Trade-in ranges from 50% (poor credit) to 65% (excellent credit) of sell price
    -- This ensures trade-in is ALWAYS less than even Local Agent (60-75%)
    if score >= 800 then
        return 0.65  -- Exceptional credit: best trade-in (65%)
    elseif score >= 740 then
        return 0.61  -- Very good credit (61%)
    elseif score >= 670 then
        return 0.57  -- Good credit (57%)
    elseif score >= 580 then
        return 0.53  -- Fair credit (53%)
    else
        return 0.50  -- Poor credit: minimum trade-in (50%)
    end
end

--[[
    Load vehicles eligible for trade-in
    Trade-in values are adjusted based on:
    1. Credit score (determines base percentage 50-65%)
    2. Vehicle condition (damage + wear reduce value further)
    Always less than agent sale values (convenience tradeoff)
]]
function UnifiedPurchaseDialog:loadEligibleTradeIns()
    self.eligibleTradeIns = {}

    -- v1.4.0: Check settings system for trade-in feature toggle
    local tradeInEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("TradeIn")
    if not tradeInEnabled then
        UsedPlus.logDebug("Trade-in system disabled by settings")
        return
    end

    local farmId = g_currentMission:getFarmId()

    -- Get credit-based trade-in multiplier (returns 0.50 to 0.65)
    local creditMultiplier = self:getCreditTradeInMultiplier()

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farmId and
           vehicle.propertyState == VehiclePropertyState.OWNED then
            -- Check if vehicle has outstanding finance
            local hasFinance = false
            if g_financeManager then
                local deals = g_financeManager:getDealsForFarm(farmId)
                if deals then
                    for _, deal in ipairs(deals) do
                        if deal.status == "active" and deal.itemId == vehicle.configFileName then
                            hasFinance = true
                            break
                        end
                    end
                end
            end

            -- Only add if no outstanding finance
            if not hasFinance then
                -- Get base sell price (what vanilla would give you)
                local sellPrice = vehicle:getSellPrice() or 0

                -- Get vehicle condition using TradeInCalculations helpers
                local damageLevel = 0
                local wearLevel = 0
                local conditionMultiplier = 1.0

                if TradeInCalculations then
                    damageLevel = TradeInCalculations.getVehicleDamage(vehicle)
                    wearLevel = TradeInCalculations.getVehicleWear(vehicle)
                    conditionMultiplier = TradeInCalculations.calculateConditionMultiplier(damageLevel, wearLevel)
                end

                -- Calculate trade-in value:
                -- 1. Start with vanilla sell price
                -- 2. Apply credit-based percentage (50-65%)
                -- 3. Apply condition multiplier (damage + wear penalty, 70-100%)
                local tradeInValue = math.floor(sellPrice * creditMultiplier * conditionMultiplier)

                -- Calculate condition percentages for display
                local repairPercent = math.floor((1 - damageLevel) * 100)
                local paintPercent = math.floor((1 - wearLevel) * 100)

                table.insert(self.eligibleTradeIns, {
                    vehicle = vehicle,
                    name = vehicle:getFullName() or "Unknown",
                    value = tradeInValue,
                    sellPrice = sellPrice,  -- Store for reference
                    creditMultiplier = creditMultiplier,
                    conditionMultiplier = conditionMultiplier,
                    damageLevel = damageLevel,
                    wearLevel = wearLevel,
                    repairPercent = repairPercent,
                    paintPercent = paintPercent,
                    condition = math.floor((repairPercent + paintPercent) / 2),  -- Average condition
                    operatingHours = vehicle.operatingTime or 0
                })
            end
        end
    end

    -- Update trade-in selector
    self:updateTradeInSelector()
end

--[[
    Update trade-in vehicle selector dropdown
]]
function UnifiedPurchaseDialog:updateTradeInSelector()
    if self.tradeInVehicleSelector then
        local texts = {"None"}  -- First option is always "None"

        for _, item in ipairs(self.eligibleTradeIns) do
            local shortName = item.name
            if #shortName > 30 then
                shortName = string.sub(shortName, 1, 28) .. ".."
            end
            -- Don't show price here - it's displayed separately below the selector
            table.insert(texts, shortName)
        end

        self.tradeInVehicleSelector:setTexts(texts)
        self.tradeInVehicleSelector:setState(1)  -- Default to "None"
    end
end

--[[
    Called when dialog opens
]]
function UnifiedPurchaseDialog:onOpen()
    UnifiedPurchaseDialog:superClass().onOpen(self)

    -- Reset trade-in state
    self.tradeInEnabled = false
    self.tradeInVehicle = nil
    self.tradeInValue = 0

    -- Reset selector to "None"
    if self.tradeInVehicleSelector then
        self.tradeInVehicleSelector:setState(1)
    end

    -- Hide trade-in details container (no vehicle selected initially)
    if self.tradeInDetailsContainer then
        self.tradeInDetailsContainer:setVisible(false)
    end

    -- Reset cash back to $0 and update options (no equity = no cash back allowed)
    self.financeCashBackIndex = 1
    self:updateCashBackOptions()

    -- Update display
    self:updateDisplay()
    self:updateSectionVisibility()
end

--[[
    Mode selector changed
]]
function UnifiedPurchaseDialog:onModeChanged()
    if self.modeSelector then
        self.currentMode = self.modeSelector:getState()
    end

    self:updateSectionVisibility()
    self:updateDisplay()
end

--[[
    Trade-in vehicle selection changed
    Index 1 = "None", Index 2+ = vehicles from eligibleTradeIns
]]
function UnifiedPurchaseDialog:onTradeInVehicleChanged()
    local index = 1
    if self.tradeInVehicleSelector then
        index = self.tradeInVehicleSelector:getState()
    end

    -- Index 1 = "None" selected
    if index == 1 then
        self.tradeInEnabled = false
        self.tradeInVehicle = nil
        self.tradeInValue = 0

        -- Hide entire trade-in details container
        if self.tradeInDetailsContainer then
            self.tradeInDetailsContainer:setVisible(false)
        end
    else
        -- Index 2+ = vehicle selected (subtract 1 for eligibleTradeIns array)
        local vehicleIndex = index - 1
        if vehicleIndex > 0 and vehicleIndex <= #self.eligibleTradeIns then
            local item = self.eligibleTradeIns[vehicleIndex]
            self.tradeInEnabled = true
            self.tradeInVehicle = item.vehicle
            self.tradeInValue = item.value

            -- Show trade-in details container
            if self.tradeInDetailsContainer then
                self.tradeInDetailsContainer:setVisible(true)
            end

            -- Update trade-in name
            if self.tradeInNameText then
                self.tradeInNameText:setText(item.name or "")
            end

            -- Update trade-in image
            local storeItem = g_storeManager:getItemByXMLFilename(item.vehicle.configFileName)
            UIHelper.Image.setStoreItemImage(self.tradeInImage, storeItem)

            -- Update condition display - Line 1: Repair status
            if self.tradeInConditionText then
                local repairText = string.format("Repair: %d%%", item.repairPercent or 100)
                if (item.repairPercent or 100) < 70 then
                    repairText = repairText .. " (damaged)"
                end
                self.tradeInConditionText:setText(repairText)
            end

            -- Update condition display - Line 2: Paint status
            if self.tradeInCondition2Text then
                local paintText = string.format("Paint: %d%%", item.paintPercent or 100)
                if (item.paintPercent or 100) < 70 then
                    paintText = paintText .. " (worn)"
                end
                self.tradeInCondition2Text:setText(paintText)
            end

            -- Update hours display
            if self.tradeInHoursText then
                local hours = math.floor((item.operatingHours or 0) / 3600000)  -- ms to hours
                self.tradeInHoursText:setText(string.format("Hours: %d", hours))
            end

            -- Update value percentage (what % of sell price this represents)
            if self.tradeInPercentText then
                local sellPrice = item.sellPrice or 0
                local percentOfSell = 0
                if sellPrice > 0 then
                    percentOfSell = math.floor((item.value / sellPrice) * 100)
                end
                self.tradeInPercentText:setText(string.format("(%d%% of sell value)", percentOfSell))
            end

            -- Update credit impact display
            if self.tradeInCreditText then
                local creditPct = math.floor((item.creditMultiplier or 0.50) * 100)
                local condPct = math.floor((item.conditionMultiplier or 1.0) * 100)
                self.tradeInCreditText:setText(string.format("Credit: %d%% | Cond: %d%%", creditPct, condPct))
            end
        else
            self.tradeInEnabled = false
            self.tradeInVehicle = nil
            self.tradeInValue = 0
            -- Hide trade-in details container
            if self.tradeInDetailsContainer then
                self.tradeInDetailsContainer:setVisible(false)
            end
        end
    end

    -- Update cash back options (max is 50% of down payment + trade-in)
    self:updateCashBackOptions()
    self:updateDisplay()
end

--[[
    Finance term changed
]]
function UnifiedPurchaseDialog:onFinanceTermChanged()
    if self.financeTermSlider then
        self.financeTermIndex = self.financeTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Finance down payment changed
]]
function UnifiedPurchaseDialog:onFinanceDownChanged()
    if self.financeDownSlider then
        self.financeDownIndex = self.financeDownSlider:getState()
    end
    -- Update cash back options (max is 50% of down payment + trade-in)
    self:updateCashBackOptions()
    self:updateDisplay()
end

--[[
    Finance cash back changed
]]
function UnifiedPurchaseDialog:onFinanceCashBackChanged()
    if self.financeCashBackSlider then
        self.financeCashBackIndex = self.financeCashBackSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Update cash back options based on down payment + trade-in value
    Rule: Cash back cannot exceed 50% of (down payment amount + trade-in value)
    If no down payment and no trade-in, cash back must be $0
]]
function UnifiedPurchaseDialog:updateCashBackOptions()
    if not self.financeCashBackSlider then
        return
    end

    -- Calculate down payment amount (percentage of vehicle price, using filtered options)
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)
    local downPaymentAmount = self.vehiclePrice * (downPct / 100)

    -- Calculate max allowed cash back: 50% of (down payment + trade-in)
    local totalEquity = downPaymentAmount + (self.tradeInValue or 0)
    local maxCashBack = math.floor(totalEquity * 0.50)

    -- Build filtered options list (only values <= maxCashBack)
    local validOptions = {}
    local validIndices = {}
    for i, amount in ipairs(UnifiedPurchaseDialog.CASH_BACK_OPTIONS) do
        if amount <= maxCashBack then
            table.insert(validOptions, amount)
            table.insert(validIndices, i)
        end
    end

    -- Always ensure at least $0 option exists
    if #validOptions == 0 then
        validOptions = {0}
        validIndices = {1}
    end

    -- Build text labels for dropdown
    local texts = {}
    for _, amount in ipairs(validOptions) do
        table.insert(texts, g_i18n:formatMoney(amount, 0, true, true))
    end

    -- Store valid options for lookup when confirming purchase
    self.validCashBackOptions = validOptions

    -- Update dropdown
    self.financeCashBackSlider:setTexts(texts)

    -- Adjust current selection if it's now out of bounds
    if self.financeCashBackIndex > #validOptions then
        self.financeCashBackIndex = #validOptions  -- Select highest valid option
    end
    self.financeCashBackSlider:setState(self.financeCashBackIndex)

    -- Debug log
    UsedPlus.logDebug(string.format("CashBack updated: downPmt=$%d + tradeIn=$%d = equity $%d, maxCashBack=$%d, options=%d",
        math.floor(downPaymentAmount), math.floor(self.tradeInValue or 0), math.floor(totalEquity), maxCashBack, #validOptions))
end

--[[
    Update down payment dropdown to show both percentage AND dollar amount
    This helps users understand "10% = 4,250 $" at a glance

    @param slider - The MultiTextOption element to update
    @param currentIndex - Current selected index to preserve
]]
function UnifiedPurchaseDialog:updateDownPaymentOptions(slider, currentIndex)
    if not slider then
        return
    end

    -- Use filtered options from settings
    local options = UnifiedPurchaseDialog.getDownPaymentOptions()
    local texts = {}
    for _, pct in ipairs(options) do
        local dollarAmount = self.vehiclePrice * (pct / 100)
        -- Format: "10% (4,250 $)" - using game's locale formatting
        local formatted = string.format("%d%% (%s)", pct, g_i18n:formatMoney(dollarAmount, 0, true, true))
        table.insert(texts, formatted)
    end

    slider:setTexts(texts)
    -- Ensure index is within bounds
    local safeIndex = math.min(currentIndex or 1, #options)
    slider:setState(safeIndex)
end

--[[
    Lease term changed
]]
function UnifiedPurchaseDialog:onLeaseTermChanged()
    if self.leaseTermSlider then
        self.leaseTermIndex = self.leaseTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Lease down payment changed
]]
function UnifiedPurchaseDialog:onLeaseDownChanged()
    if self.leaseDownSlider then
        self.leaseDownIndex = self.leaseDownSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Update section visibility based on current mode
]]
function UnifiedPurchaseDialog:updateSectionVisibility()
    local isCash = (self.currentMode == UnifiedPurchaseDialog.MODE_CASH)
    local isFinance = (self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE)
    local isLease = (self.currentMode == UnifiedPurchaseDialog.MODE_LEASE)

    if self.cashSection then
        self.cashSection:setVisible(isCash)
    end

    if self.financeSection then
        self.financeSection:setVisible(isFinance)
    end

    if self.leaseSection then
        self.leaseSection:setVisible(isLease)
    end
end

--[[
    Update all display elements
    Refactored to use UIHelper for consistent formatting
]]
function UnifiedPurchaseDialog:updateDisplay()
    -- Item info
    UIHelper.Element.setText(self.itemNameText, self.vehicleName)
    UIHelper.Element.setText(self.itemPriceText, UIHelper.Text.formatMoney(self.vehiclePrice))
    UIHelper.Element.setText(self.itemCategoryText, self.vehicleCategory)

    -- Used badge
    UIHelper.Vehicle.displayUsedBadge(self.usedBadgeText, self.isUsedVehicle, self.usedCondition)

    -- Trade-in value (green - credit toward purchase)
    UIHelper.Finance.displayAssetValue(self.tradeInValueText, self.tradeInValue)

    -- Check if current mode is available (credit qualification)
    local modeAvailable, creditWarning = self:isModeAvailable()

    -- Show/hide credit warning
    if self.creditWarningText then
        if creditWarning then
            self.creditWarningText:setText(creditWarning)
            self.creditWarningText:setVisible(true)
            -- Red color for warning
            self.creditWarningText:setTextColor(1, 0.3, 0.3, 1)
        else
            self.creditWarningText:setVisible(false)
        end
    end

    -- Show/hide credit warning container (background)
    if self.creditWarningContainer then
        self.creditWarningContainer:setVisible(creditWarning ~= nil)
    end

    -- Enable/disable confirm button based on mode availability
    if self.confirmButton then
        self.confirmButton:setDisabled(not modeAvailable)
    end

    -- Update mode selector to show unavailable options with indicators
    self:updateModeSelectorTexts()

    -- Update mode-specific displays
    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        self:updateCashDisplay()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        self:updateFinanceDisplay()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        self:updateLeaseDisplay()
    end
end

--[[
    Update mode selector texts to show which options are unavailable
    Adds visual indicators for credit-locked options
]]
function UnifiedPurchaseDialog:updateModeSelectorTexts()
    if not self.modeSelector then return end

    local texts = {}

    -- Cash is always available
    table.insert(texts, g_i18n:getText("usedplus_mode_cash"))

    -- Finance - show lock indicator if unavailable
    if self.canFinance then
        table.insert(texts, g_i18n:getText("usedplus_mode_finance"))
    else
        local template = g_i18n:getText("usedplus_mode_financeCredit")
        table.insert(texts, string.format(template, self.financeMinScore or 550))
    end

    -- Lease - show lock indicator if unavailable
    if self.canLease then
        table.insert(texts, g_i18n:getText("usedplus_mode_lease"))
    else
        local template = g_i18n:getText("usedplus_mode_leaseCredit")
        table.insert(texts, string.format(template, self.leaseMinScore or 600))
    end

    self.modeSelector:setTexts(texts)
end

--[[
    Update cash mode display
    Refactored to use UIHelper formatting
]]
function UnifiedPurchaseDialog:updateCashDisplay()
    local totalDue = self.vehiclePrice - self.tradeInValue

    UIHelper.Element.setText(self.cashPriceText, UIHelper.Text.formatMoney(self.vehiclePrice))

    -- Trade-in credit (shown as negative)
    if self.tradeInEnabled and self.tradeInValue > 0 then
        UIHelper.Element.setTextWithColor(self.cashTradeInText,
            "-" .. UIHelper.Text.formatMoney(self.tradeInValue), UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setText(self.cashTradeInText, "-" .. UIHelper.Text.formatMoney(0))
    end

    -- Total due (or refund if negative)
    if totalDue < 0 then
        UIHelper.Element.setTextWithColor(self.cashTotalText,
            "+" .. UIHelper.Text.formatMoney(math.abs(totalDue)) .. " REFUND", UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setText(self.cashTotalText, UIHelper.Text.formatMoney(totalDue))
    end
end

--[[
    Update finance mode display
    Refactored to use UIHelper formatting
]]
function UnifiedPurchaseDialog:updateFinanceDisplay()
    local termYears = UnifiedPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 5
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)
    -- Use filtered cash back options (limited by down payment + trade-in)
    local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0

    -- Down payment is cash paid today (percentage of vehicle price)
    local downPayment = self.vehiclePrice * (downPct / 100)

    -- Amount financed calculation:
    -- Start with vehicle price
    -- Subtract trade-in (reduces what you need to finance)
    -- Subtract down payment (cash you're putting down)
    -- Add cash back (increases loan amount)
    local amountFinanced = self.vehiclePrice - self.tradeInValue - downPayment + cashBack
    amountFinanced = math.max(0, amountFinanced)

    -- Due today = down payment (cash out of pocket)
    -- Trade-in does NOT reduce due today - it reduces amount financed
    -- Cash back also doesn't affect due today - it's added to the loan
    local dueTodayAmount = downPayment

    -- Use centralized calculation function
    local termMonths = termYears * 12
    local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
        math.max(0, amountFinanced),
        self.interestRate,
        termMonths
    )

    -- Update UI with UIHelper
    UIHelper.Element.setText(self.financeAmountText, UIHelper.Text.formatMoney(math.max(0, amountFinanced)))
    UIHelper.Element.setText(self.financeRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Finance.displayMonthlyPayment(self.financeMonthlyText, monthlyPayment)

    -- Update down payment dropdown to show dollar amounts (e.g., "10% (4,250 $)")
    self:updateDownPaymentOptions(self.financeDownSlider, self.financeDownIndex)

    UIHelper.Element.setTextWithColor(self.financeTotalInterestText,
        UIHelper.Text.formatMoney(math.max(0, totalInterest)), UIHelper.Colors.COST_ORANGE)
    UIHelper.Element.setText(self.financeDueTodayText, UIHelper.Text.formatMoney(dueTodayAmount))
    UIHelper.Element.setText(self.financeCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
end

--[[
    Update lease mode display
    Refactored to use UIHelper formatting

    LEASE ECONOMICS:
    - You pay for DEPRECIATION during the lease term, not the full vehicle value
    - Cap reduction (down payment) is a percentage of DEPRECIATION, not vehicle price
    - This makes leasing more affordable and economically sensible
    - At end of lease: return vehicle OR pay residual (buyout) to keep it
    - Lease payments build equity toward the buyout
    - Security deposit is credit-based (automatic, not selectable)

    IMPORTANT: Capitalized cost must never go below residual value, or we get
    negative depreciation (impossible scenario). If trade-in + cap reduction
    would push capitalized cost below residual, we cap it at residual.
]]
function UnifiedPurchaseDialog:updateLeaseDisplay()
    -- LEASE_TERMS now stores months directly
    local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12
    local termYears = termMonths / 12  -- For residual value calculation
    local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex)

    -- Calculate residual value first (what vehicle is worth at end of lease)
    local residualValue = FinanceCalculations.calculateResidualValue(self.vehiclePrice, termYears)

    -- Depreciation = what you're "using up" during the lease
    local depreciation = self.vehiclePrice - residualValue

    -- Cap reduction is a percentage of VEHICLE PRICE (like a down payment)
    -- This keeps the upfront cost consistent regardless of lease term
    -- Longer terms = lower monthly but same upfront if same % selected
    local capReduction = self.vehiclePrice * (capReductionPct / 100)

    -- Capitalized cost = vehicle price - trade-in - cap reduction
    -- CRITICAL: Capitalized cost must be >= residual value to avoid negative depreciation
    -- If trade-in is very large, we cap the benefit to prevent impossible scenarios
    local rawCapitalizedCost = self.vehiclePrice - self.tradeInValue - capReduction
    local capitalizedCost = math.max(residualValue, rawCapitalizedCost)

    -- Track if trade-in exceeds what can be applied (would go to refund/equity)
    local tradeInExcess = math.max(0, residualValue - rawCapitalizedCost)

    -- Monthly payment calculation (will always be non-negative now)
    local monthlyPayment = FinanceCalculations.calculateLeasePayment(
        capitalizedCost,
        residualValue,
        self.interestRate,
        termMonths
    )

    -- Extra safety: ensure monthly payment is never negative
    monthlyPayment = math.max(0, monthlyPayment)

    -- Security deposit = credit-based months of lease payment (automatic)
    local securityDeposit, depositMonths, depositTierName = FinanceCalculations.calculateSecurityDeposit(
        monthlyPayment, self.creditScore)

    -- Total lease cost = all monthly payments + cap reduction + security deposit
    local totalLeaseCost = monthlyPayment * termMonths + capReduction + securityDeposit

    -- Due today = cap reduction + security deposit (cash out of pocket)
    -- Trade-in does NOT reduce due today - it reduces capitalized cost
    local dueTodayAmount = capReduction + securityDeposit

    -- Store for executeLeasePurchase
    self.calculatedSecurityDeposit = securityDeposit
    self.calculatedDepositMonths = depositMonths

    -- Update UI with UIHelper
    UIHelper.Finance.displayMonthlyPayment(self.leaseMonthlyText, monthlyPayment)
    UIHelper.Element.setText(self.leaseRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Element.setText(self.leaseTotalText, UIHelper.Text.formatMoney(totalLeaseCost))
    UIHelper.Element.setText(self.leaseBuyoutText, UIHelper.Text.formatMoney(residualValue))
    UIHelper.Element.setText(self.leaseCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))

    -- Update down payment dropdown to show dollar amounts (e.g., "10% (4,250 $)")
    self:updateDownPaymentOptions(self.leaseDownSlider, self.leaseDownIndex)

    -- Security deposit display (credit-based, not selectable)
    if self.leaseDepositText then
        local depositText
        if depositMonths == 0 then
            depositText = "No Deposit (" .. depositTierName .. " credit)"
        else
            depositText = string.format("%s (%d mo, %s)",
                UIHelper.Text.formatMoney(securityDeposit), depositMonths, depositTierName)
        end
        UIHelper.Element.setText(self.leaseDepositText, depositText)
    end

    -- Due today display (cap reduction + security deposit)
    UIHelper.Element.setText(self.leaseDueTodayText, UIHelper.Text.formatMoney(dueTodayAmount))

    -- Debug log
    UsedPlus.logDebug(string.format("Lease: price=$%d, depreciation=$%d, capRed=%d%% ($%d), deposit=$%d (%d mo), residual=$%d, monthly=$%d",
        self.vehiclePrice, math.floor(depreciation), capReductionPct, math.floor(capReduction),
        math.floor(securityDeposit), depositMonths, math.floor(residualValue), math.floor(monthlyPayment)))
end

--[[
    Confirm purchase button clicked
    Shows confirmation dialog with transaction details before executing
]]
function UnifiedPurchaseDialog:onConfirmPurchase()
    -- Build confirmation message based on current mode
    local confirmMessage = self:buildConfirmationMessage()

    -- Show YesNo confirmation dialog
    YesNoDialog.show(
        confirmMessage,
        function(yes)
            if yes then
                self:executeConfirmedPurchase()
            end
        end,
        self,
        "Confirm Purchase"
    )
end

--[[
    Build confirmation message based on current mode
]]
function UnifiedPurchaseDialog:buildConfirmationMessage()
    local lines = {}

    table.insert(lines, "CONFIRM PURCHASE")
    table.insert(lines, "")
    table.insert(lines, string.format("Vehicle: %s", self.vehicleName))
    table.insert(lines, string.format("Price: %s", g_i18n:formatMoney(self.vehiclePrice)))
    table.insert(lines, "")

    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        -- Cash purchase
        local totalDue = self.vehiclePrice - self.tradeInValue
        table.insert(lines, "PURCHASE TYPE: Cash")
        if self.tradeInEnabled and self.tradeInValue > 0 then
            table.insert(lines, string.format("Trade-In Credit: -%s", g_i18n:formatMoney(self.tradeInValue)))
        end
        table.insert(lines, "")
        if totalDue < 0 then
            table.insert(lines, string.format("REFUND: +%s", g_i18n:formatMoney(math.abs(totalDue))))
        else
            table.insert(lines, string.format("TOTAL DUE NOW: %s", g_i18n:formatMoney(totalDue)))
        end

    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        -- Finance purchase
        local termYears = UnifiedPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 5
        local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)
        local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0
        local downPayment = self.vehiclePrice * (downPct / 100)
        local amountFinanced = self.vehiclePrice - self.tradeInValue - downPayment + cashBack
        amountFinanced = math.max(0, amountFinanced)

        local termMonths = termYears * 12
        local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
            amountFinanced, self.interestRate, termMonths)

        table.insert(lines, "PURCHASE TYPE: Finance")
        table.insert(lines, string.format("Term: %d years (%d months)", termYears, termMonths))
        table.insert(lines, string.format("Interest Rate: %.2f%%", self.interestRate * 100))
        table.insert(lines, string.format("Amount Financed: %s", g_i18n:formatMoney(amountFinanced)))
        table.insert(lines, "")
        table.insert(lines, string.format("Monthly Payment: %s", g_i18n:formatMoney(monthlyPayment)))
        table.insert(lines, string.format("Total Interest: %s", g_i18n:formatMoney(totalInterest)))
        table.insert(lines, "")
        table.insert(lines, string.format("DUE TODAY: %s (down payment)", g_i18n:formatMoney(downPayment)))

    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        -- Lease
        local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 36
        local termYears = termMonths / 12
        local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex)
        local residualValue = FinanceCalculations.calculateResidualValue(self.vehiclePrice, termYears)
        local capReduction = self.vehiclePrice * (capReductionPct / 100)
        local capitalizedCost = math.max(residualValue, self.vehiclePrice - self.tradeInValue - capReduction)
        local monthlyPayment = FinanceCalculations.calculateLeasePayment(
            capitalizedCost, residualValue, self.interestRate, termMonths)
        monthlyPayment = math.max(0, monthlyPayment)
        local securityDeposit = self.calculatedSecurityDeposit or 0
        local totalDueToday = capReduction + securityDeposit

        table.insert(lines, "PURCHASE TYPE: Lease")
        table.insert(lines, string.format("Term: %d months", termMonths))
        table.insert(lines, string.format("Monthly Payment: %s", g_i18n:formatMoney(monthlyPayment)))
        table.insert(lines, string.format("Buyout at End: %s", g_i18n:formatMoney(residualValue)))
        table.insert(lines, "")
        if capReduction > 0 then
            table.insert(lines, string.format("Cap Reduction: %s", g_i18n:formatMoney(capReduction)))
        end
        if securityDeposit > 0 then
            table.insert(lines, string.format("Security Deposit: %s", g_i18n:formatMoney(securityDeposit)))
        end
        table.insert(lines, string.format("DUE TODAY: %s", g_i18n:formatMoney(totalDueToday)))
    end

    table.insert(lines, "")
    table.insert(lines, "Proceed with this transaction?")

    return table.concat(lines, "\n")
end

--[[
    Execute the confirmed purchase based on current mode
]]
function UnifiedPurchaseDialog:executeConfirmedPurchase()
    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        self:executeCashPurchase()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        self:executeFinancePurchase()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        self:executeLeasePurchase()
    end
end

--[[
    Execute cash purchase

    Uses the game's shop controller to spawn the vehicle properly.
]]
function UnifiedPurchaseDialog:executeCashPurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    local totalDue = self.vehiclePrice - self.tradeInValue

    -- Check if player can afford
    if totalDue > 0 and farm.money < totalDue then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsGeneric"), g_i18n:formatMoney(totalDue, 0, true, true)))
        return
    end

    -- Handle trade-in first
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Spawn vehicle using shop controller
    local spawnSuccess = self:spawnVehicle(farmId, totalDue)

    if spawnSuccess then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehiclePurchased"), self.vehicleName, g_i18n:formatMoney(math.max(0, totalDue))))
    else
        -- Fallback: just deduct money and show message
        if totalDue ~= 0 then
            g_currentMission:addMoney(-totalDue, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)
        end
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehiclePurchasedShop"), self.vehicleName))
    end

    self:close()
end

--[[
    Spawn a vehicle using the game's shop system
    @param farmId - Owner farm
    @param price - Price to pay (0 for financed/leased)
    @return boolean - True if spawn succeeded
]]
function UnifiedPurchaseDialog:spawnVehicle(farmId, price)
    if not self.storeItem then
        UsedPlus.logError("No storeItem for vehicle spawn")
        return false
    end

    -- Try using the shop controller's buy method
    if g_currentMission.shopController and g_currentMission.shopController.buy then
        local success = pcall(function()
            g_currentMission.shopController:buy(self.storeItem, {}, farmId, price or 0)
        end)
        if success then
            UsedPlus.logDebug("Vehicle spawned via shopController:buy()")
            return true
        end
    end

    -- Fallback: Try direct VehicleLoadingUtil
    if VehicleLoadingUtil and VehicleLoadingUtil.loadVehicle then
        local x, y, z = self:getVehicleSpawnPosition()
        local success = pcall(function()
            VehicleLoadingUtil.loadVehicle(
                self.storeItem.xmlFilename,
                {x = x, y = y, z = z},
                true,   -- addPhysics
                0,      -- yRotation
                farmId,
                {},     -- configurations
                nil,    -- callback
                nil,    -- callbackTarget
                {}      -- callbackArguments
            )
        end)
        if success then
            UsedPlus.logDebug("Vehicle spawned via VehicleLoadingUtil")
            return true
        end
    end

    UsedPlus.logWarn("Could not spawn vehicle - no suitable spawn method found")
    return false
end

--[[
    Get a spawn position for the vehicle (near shop/player)
]]
function UnifiedPurchaseDialog:getVehicleSpawnPosition()
    -- Try to get a position near the player
    local player = g_currentMission.player
    if player and player.rootNode then
        local x, y, z = getWorldTranslation(player.rootNode)
        -- Offset slightly so vehicle doesn't spawn on player
        return x + 5, y, z + 5
    end

    -- Fallback to a default spawn point
    return 0, 0, 0
end

--[[
    Execute finance purchase

    NOTE: FinanceVehicleEvent handles:
    1. Creating the finance deal
    2. Spawning the vehicle
    3. Deducting down payment

    Trade-in and cash back are handled here before sending the event.
]]
function UnifiedPurchaseDialog:executeFinancePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Credit score check - must meet minimum for vehicle financing
    if CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore, message = CreditScore.canFinance(farmId, "VEHICLE_FINANCE")
        if not canFinance then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Finance rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Calculate finance parameters
    local termYears = UnifiedPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 5
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)
    -- Use filtered cash back options (limited by down payment + trade-in)
    local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0

    -- Down payment is cash paid today (regardless of trade-in)
    local downPayment = self.vehiclePrice * (downPct / 100)

    -- Check if player can afford down payment
    if downPayment > farm.money then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDownPayment"), g_i18n:formatMoney(downPayment, 0, true, true)))
        return
    end

    -- Handle trade-in first (removes the vehicle)
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Get vehicle config filename
    local vehicleConfig = self.storeItem and self.storeItem.xmlFilename or "unknown"

    -- Calculate effective price after trade-in (for the finance deal)
    -- Trade-in reduces the amount that needs to be financed
    local effectivePrice = self.vehiclePrice - self.tradeInValue

    -- Send finance event to server (creates the deal and handles money)
    FinanceVehicleEvent.sendToServer(
        farmId,
        "vehicle",           -- itemType
        vehicleConfig,       -- itemId (xmlFilename)
        self.vehicleName,    -- itemName
        effectivePrice,      -- basePrice (after trade-in reduction)
        downPayment,         -- downPayment
        termYears,           -- termYears
        cashBack,            -- cashBack
        {}                   -- configurations
    )

    -- Spawn the vehicle (FinanceVehicleEvent only creates the deal, not the vehicle)
    local spawnSuccess = self:spawnVehicle(farmId, 0)  -- Price 0 since it's financed

    if spawnSuccess then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehicleFinanced"), self.vehicleName, g_i18n:formatMoney(downPayment)))
    else
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehicleFinancedShop"), self.vehicleName))
    end

    -- Close dialog
    self:close()
end

--[[
    Execute lease purchase

    LEASE ECONOMICS:
    - Cap reduction is based on vehicle price percentage
    - Security deposit is credit-based (automatic)
    - LeaseVehicleEvent handles deal creation AND vehicle spawning

    NOTE: We send the event to server which handles:
    1. Creating the lease deal
    2. Spawning the vehicle with LEASED property state
    3. Deducting money (down payment)
]]
function UnifiedPurchaseDialog:executeLeasePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Credit score check - leasing requires HIGHER credit score than financing
    if CreditScore and CreditScore.canFinance then
        local canLease, minRequired, currentScore, message = CreditScore.canFinance(farmId, "VEHICLE_LEASE")
        if not canLease then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Lease rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Calculate lease parameters (LEASE_TERMS stores months directly)
    local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 36
    local termYears = termMonths / 12
    local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex)

    -- Cap reduction as percentage of vehicle price
    local capReduction = self.vehiclePrice * (capReductionPct / 100)

    -- Get security deposit
    local securityDeposit = self.calculatedSecurityDeposit or 0

    -- Total due today = cap reduction + security deposit
    local totalDueToday = capReduction + securityDeposit

    -- Check if player can afford total due today
    if totalDueToday > farm.money then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Insufficient funds! Need " .. g_i18n:formatMoney(totalDueToday, 0, true, true))
        return
    end

    -- Handle trade-in first (removes the vehicle)
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Get vehicle config filename
    local vehicleConfig = self.storeItem and self.storeItem.xmlFilename or "unknown"

    -- Send lease event to server
    -- LeaseVehicleEvent handles: deal creation, money deduction, vehicle spawning
    LeaseVehicleEvent.sendToServer(
        farmId,
        vehicleConfig,
        self.vehicleName,
        self.vehiclePrice,
        totalDueToday,  -- downPayment = cap reduction + security deposit
        termYears,      -- LeaseVehicleEvent expects years
        {}              -- configurations (empty for now)
    )

    -- Close dialog
    self:close()

    -- Note: Success notification is shown by LeaseVehicleEvent after spawn
end

--[[
    Execute trade-in (sell the trade-in vehicle)
]]
function UnifiedPurchaseDialog:executeTradeIn()
    if not self.tradeInVehicle then return end

    local farmId = g_currentMission:getFarmId()

    -- The trade-in value is already applied to the transaction
    -- We just need to remove the vehicle
    if self.tradeInVehicle.delete then
        self.tradeInVehicle:delete()
    elseif g_currentMission.vehicleSystem.removeVehicle then
        g_currentMission.vehicleSystem:removeVehicle(self.tradeInVehicle)
    end

end

--[[
    Cancel button clicked
]]
function UnifiedPurchaseDialog:onCancel()
    self:close()
end

--[[
    Search Used button clicked
     Refactored to use DialogLoader for centralized loading
]]
function UnifiedPurchaseDialog:onSearchUsed()
    if not self.storeItem then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, g_i18n:getText("usedplus_error_noVehicleSelected"))
        return
    end

    -- Close this dialog first
    self:close()

    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("UsedSearchDialog", "setData", self.storeItem, self.storeItem.xmlFilename, farmId)
end

--[[
    Static show method
]]
function UnifiedPurchaseDialog.show(storeItem, price, saleItem, initialMode)
    local dialog = g_gui.guis.UnifiedPurchaseDialog
    if dialog and dialog.target then
        dialog.target:setVehicleData(storeItem, price, saleItem)
        dialog.target:setInitialMode(initialMode or UnifiedPurchaseDialog.MODE_CASH)
        g_gui:showDialog("UnifiedPurchaseDialog")
    else
        UsedPlus.logError("UnifiedPurchaseDialog not registered")
    end
end

UsedPlus.logInfo("UnifiedPurchaseDialog loaded")
