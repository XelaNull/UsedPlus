--[[
    FS25_UsedPlus - Unified Land Purchase Dialog

     Single dialog for all farmland purchase modes (Cash, Finance, Lease)
    No trade-in support for land purchases.

    Features:
    - Mode selector: Buy with Cash, Finance, Lease
    - Dynamic section visibility based on mode
    - Unified calculations and purchase flow for farmland
]]

UnifiedLandPurchaseDialog = {}
local UnifiedLandPurchaseDialog_mt = Class(UnifiedLandPurchaseDialog, MessageDialog)

-- Purchase modes
UnifiedLandPurchaseDialog.MODE_CASH = 1
UnifiedLandPurchaseDialog.MODE_FINANCE = 2
UnifiedLandPurchaseDialog.MODE_LEASE = 3

-- MODE_TEXTS built dynamically in onGuiSetupFinished using g_i18n

-- Term options for land
UnifiedLandPurchaseDialog.FINANCE_TERMS = {5, 10, 15, 20}  -- Years (max 20)
-- Lease terms in MONTHS: 1-12 months individually, then 2-5 years
UnifiedLandPurchaseDialog.LEASE_TERMS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 24, 36, 48, 60}
UnifiedLandPurchaseDialog.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}  -- Percent (for finance)

--[[
    Get available down payment options based on settings minimum
    @return filtered table of down payment percentages
]]
function UnifiedLandPurchaseDialog.getDownPaymentOptions()
    local minPercent = UsedPlusSettings and UsedPlusSettings:get("minDownPaymentPercent") or 0
    local options = {}
    for _, pct in ipairs(UnifiedLandPurchaseDialog.DOWN_PAYMENT_OPTIONS) do
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
    @param index - Dropdown index (1-based)
    @return percentage value
]]
function UnifiedLandPurchaseDialog.getDownPaymentPercent(index)
    local options = UnifiedLandPurchaseDialog.getDownPaymentOptions()
    return options[index] or options[1] or 0
end

-- Lease pricing constants
-- Base rate should make leasing ~25-35% of expected crop revenue for balance
-- 7 acres wheat @ $12k/year revenue → lease should be ~$3-4k/year
-- 7 acres = 2.83 ha → $1,000-1,400/ha base rate
UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA = 1000  -- Base $/ha/year for average soil

-- Soil quality multipliers for lease payment
UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS = {
    excellent = 1.50,  -- Premium soil = 50% higher lease
    good = 1.25,       -- Good soil = 25% higher lease
    average = 1.00,    -- Baseline
    poor = 0.75,       -- Poor soil = 25% lower lease
}

-- Credit risk multipliers for lease payment (poor credit = landlord charges more)
UnifiedLandPurchaseDialog.CREDIT_LEASE_MULTIPLIERS = {
    [1] = 0.90,  -- Excellent credit: 10% discount (reliable tenant)
    [2] = 0.95,  -- Good credit: 5% discount
    [3] = 1.00,  -- Fair credit: baseline
    [4] = 1.10,  -- Poor credit: 10% premium (risk)
    [5] = 1.25,  -- Very Poor credit: 25% premium (high risk)
}

-- Signing bonus: Estimated crop value based on grain
-- Conservative estimate: assume 60% of arable land has harvestable crops
UnifiedLandPurchaseDialog.CROP_COVERAGE_PERCENT = 0.60
UnifiedLandPurchaseDialog.GRAIN_YIELD_PER_HA = 7.0      -- tons/ha (typical wheat/barley)
UnifiedLandPurchaseDialog.GRAIN_PRICE_PER_TON = 320     -- $/ton (average grain price)

--[[
    Constructor
]]
function UnifiedLandPurchaseDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or UnifiedLandPurchaseDialog_mt)

    -- Current state
    self.currentMode = UnifiedLandPurchaseDialog.MODE_CASH

    -- Land data
    self.farmlandId = nil
    self.farmland = nil
    self.baseLandPrice = 0      -- Original price before credit adjustment
    self.landPrice = 0          -- Adjusted price after credit modifier
    self.creditAdjustment = 0   -- Dollar amount of adjustment (negative = discount)
    self.creditModifierPct = 0  -- Percentage adjustment (-5, 0, +10, etc.)
    self.landName = ""
    self.landSize = 0
    self.pricePerHa = 0

    -- Finance parameters
    self.financeTermIndex = 3  -- Default 15 years for land
    self.financeDownIndex = 5  -- Default 20%

    -- Lease parameters
    self.leaseTermIndex = 12  -- Default 1 year (12 months)

    -- Credit data
    self.creditScore = 650
    self.creditRating = "Fair"
    self.interestRate = 0.06  -- Land loans typically have lower rates

    return self
end

--[[
    Called when GUI elements are ready
]]
function UnifiedLandPurchaseDialog:onGuiSetupFinished()
    UnifiedLandPurchaseDialog:superClass().onGuiSetupFinished(self)

    -- Setup mode selector with localized texts
    if self.modeSelector then
        local modeTexts = {
            g_i18n:getText("usedplus_land_modeCash"),
            g_i18n:getText("usedplus_land_modeFinance"),
            g_i18n:getText("usedplus_land_modeLease")
        }
        self.modeSelector:setTexts(modeTexts)
        self.modeSelector:setState(1)  -- Default to Cash
    end

    -- Setup finance term slider with localized texts
    if self.financeTermSlider then
        local texts = {}
        for _, years in ipairs(UnifiedLandPurchaseDialog.FINANCE_TERMS) do
            if years == 1 then
                table.insert(texts, g_i18n:getText("usedplus_land_termYear"))
            else
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termYears"), years))
            end
        end
        self.financeTermSlider:setTexts(texts)
        self.financeTermSlider:setState(self.financeTermIndex)
    end

    -- Setup finance down payment slider (uses filtered options from settings)
    if self.financeDownSlider then
        local options = UnifiedLandPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.financeDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.financeDownIndex = math.min(self.financeDownIndex, #options)
        self.financeDownSlider:setState(self.financeDownIndex)
    end

    -- Setup lease term slider with localized texts (LEASE_TERMS stores months)
    if self.leaseTermSlider then
        local texts = {}
        for _, months in ipairs(UnifiedLandPurchaseDialog.LEASE_TERMS) do
            if months == 1 then
                table.insert(texts, g_i18n:getText("usedplus_land_termMonth"))
            elseif months < 12 then
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termMonths"), months))
            elseif months == 12 then
                table.insert(texts, g_i18n:getText("usedplus_land_termYear"))
            else
                local years = months / 12
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termYears"), years))
            end
        end
        self.leaseTermSlider:setTexts(texts)
        self.leaseTermSlider:setState(self.leaseTermIndex)
    end
    -- Note: Security deposit is now credit-based (automatic, no slider needed)
end

--[[
    Set land data for purchase
]]
function UnifiedLandPurchaseDialog:setLandData(farmlandId, farmland, price)
    self.farmlandId = farmlandId
    self.farmland = farmland
    self.baseLandPrice = price or 0  -- Store original price

    -- Verbose debug logging
    UsedPlus.logDebug(string.format("setLandData: farmlandId=%s, basePrice=%s", tostring(farmlandId), tostring(price)))
    if farmland then
        UsedPlus.logTrace("Farmland properties:")
        for key, value in pairs(farmland) do
            if type(value) ~= "table" and type(value) ~= "function" then
                UsedPlus.logTrace(string.format("  %s = %s", tostring(key), tostring(value)))
            end
        end
    end

    if farmland then
        -- Get land name (Field X or custom name)
        self.landName = farmland.name or string.format("Field %d", farmlandId)

        -- Get land size in hectares (farmland.areaInHa is the correct property)
        self.landSize = farmland.areaInHa or 0

        -- Get soil quality if available
        self.soilQuality = "Standard"
        if farmland.soilQuality then
            if farmland.soilQuality >= 0.8 then
                self.soilQuality = "Excellent"
            elseif farmland.soilQuality >= 0.6 then
                self.soilQuality = "Good"
            elseif farmland.soilQuality >= 0.4 then
                self.soilQuality = "Average"
            else
                self.soilQuality = "Poor"
            end
        end
    else
        self.landName = string.format("Farmland %d", farmlandId or 0)
        self.landSize = 0
        self.soilQuality = "Unknown"
    end

    -- Calculate credit parameters (this also calculates adjusted price)
    self:calculateCreditParameters()

    -- Calculate per-unit prices based on adjusted price
    if self.landSize > 0 then
        self.pricePerHa = self.landPrice / self.landSize
        self.landSizeAcres = self.landSize * 2.47105
        self.pricePerAcre = self.landPrice / self.landSizeAcres
    else
        self.pricePerHa = 0
        self.landSizeAcres = 0
        self.pricePerAcre = 0
    end
end

--[[
    Set initial mode (called from farmland extension)
]]
function UnifiedLandPurchaseDialog:setInitialMode(mode)
    self.currentMode = mode or UnifiedLandPurchaseDialog.MODE_CASH

    if self.modeSelector then
        self.modeSelector:setState(self.currentMode)
    end
end

--[[
    Calculate credit parameters and adjusted land price
]]
function UnifiedLandPurchaseDialog:calculateCreditParameters()
    local farmId = g_currentMission:getFarmId()

    if CreditScore then
        self.creditScore = CreditScore.calculate(farmId)
        self.creditRating = CreditScore.getRating(self.creditScore)

        -- Calculate interest rate based on credit (land loans are typically lower)
        local baseRate = 0.06
        local adjustment = CreditScore.getInterestAdjustment(self.creditScore) or 0
        self.interestRate = math.max(0.025, math.min(0.12, baseRate + adjustment))
    else
        self.creditScore = 650
        self.creditRating = "Fair"
        self.interestRate = 0.06
    end

    -- Calculate credit-adjusted land price
    if FinanceCalculations and self.baseLandPrice > 0 then
        self.landPrice, self.creditAdjustment, self.creditModifierPct, _ =
            FinanceCalculations.calculateAdjustedLandPrice(self.baseLandPrice, self.creditScore)

        UsedPlus.logDebug(string.format(
            "Credit price adjustment: Base=$%d, Adjusted=$%d, Modifier=%d%%, Score=%d (%s)",
            self.baseLandPrice, self.landPrice, self.creditModifierPct,
            self.creditScore, self.creditRating))
    else
        -- Fallback: no adjustment
        self.landPrice = self.baseLandPrice
        self.creditAdjustment = 0
        self.creditModifierPct = 0
    end
end

--[[
    Called when dialog opens
]]
function UnifiedLandPurchaseDialog:onOpen()
    UnifiedLandPurchaseDialog:superClass().onOpen(self)

    -- Update display
    self:updateDisplay()
    self:updateSectionVisibility()
end

--[[
    Mode selector changed
]]
function UnifiedLandPurchaseDialog:onModeChanged()
    if self.modeSelector then
        self.currentMode = self.modeSelector:getState()
    end

    self:updateSectionVisibility()
    self:updateDisplay()
end

--[[
    Finance term changed
]]
function UnifiedLandPurchaseDialog:onFinanceTermChanged()
    if self.financeTermSlider then
        self.financeTermIndex = self.financeTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Finance down payment changed
]]
function UnifiedLandPurchaseDialog:onFinanceDownChanged()
    if self.financeDownSlider then
        self.financeDownIndex = self.financeDownSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Lease term changed
]]
function UnifiedLandPurchaseDialog:onLeaseTermChanged()
    if self.leaseTermSlider then
        self.leaseTermIndex = self.leaseTermSlider:getState()
    end
    self:updateDisplay()
end

-- Note: Security deposit is now credit-based (no user selection needed)

--[[
    Update section visibility based on current mode
]]
function UnifiedLandPurchaseDialog:updateSectionVisibility()
    local isCash = (self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH)
    local isFinance = (self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE)
    local isLease = (self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE)

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
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateDisplay()
    -- Land info using UIHelper
    UIHelper.Element.setText(self.landNameText, self.landName)
    UIHelper.Element.setText(self.landSizeText, string.format("%.2f ha (%.1f acres)", self.landSize, self.landSizeAcres or 0))

    -- Show adjusted price as main price (this is what they'll pay)
    UIHelper.Element.setText(self.landPriceText, UIHelper.Text.formatMoney(self.landPrice))
    UIHelper.Element.setText(self.landPricePerHaText, UIHelper.Text.formatMoney(self.pricePerHa) .. "/ha")
    UIHelper.Element.setText(self.landPricePerAcreText, UIHelper.Text.formatMoney(self.pricePerAcre or 0) .. "/acre")
    UIHelper.Element.setText(self.landSoilText, self.soilQuality or "Standard")

    -- Update credit adjustment display elements (if they exist in XML)
    if self.basePriceText then
        UIHelper.Element.setText(self.basePriceText, UIHelper.Text.formatMoney(self.baseLandPrice))
    end

    if self.creditAdjustmentText then
        if self.creditAdjustment ~= 0 then
            local adjText = ""
            local adjColor = nil
            if self.creditAdjustment < 0 then
                -- Discount (good credit)
                adjText = "-" .. UIHelper.Text.formatMoney(math.abs(self.creditAdjustment)) ..
                    " (" .. self.creditModifierPct .. "% " .. self.creditRating .. ")"
                adjColor = UIHelper.Colors.MONEY_GREEN
            else
                -- Premium (bad credit)
                adjText = "+" .. UIHelper.Text.formatMoney(self.creditAdjustment) ..
                    " (+" .. self.creditModifierPct .. "% " .. self.creditRating .. ")"
                adjColor = UIHelper.Colors.DEBT_RED
            end
            UIHelper.Element.setTextWithColor(self.creditAdjustmentText, adjText, adjColor)
            UIHelper.Element.setVisible(self.creditAdjustmentText, true)
        else
            UIHelper.Element.setText(self.creditAdjustmentText, g_i18n:getText("usedplus_land_noAdjustment"))
            UIHelper.Element.setVisible(self.creditAdjustmentText, true)
        end
    end

    if self.adjustedPriceText then
        UIHelper.Element.setText(self.adjustedPriceText, UIHelper.Text.formatMoney(self.landPrice))
    end

    -- Update mode-specific displays
    if self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH then
        self:updateCashDisplay()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE then
        self:updateFinanceDisplay()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE then
        self:updateLeaseDisplay()
    end
end

--[[
    Update cash mode display
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateCashDisplay()
    UIHelper.Element.setText(self.cashPriceText, UIHelper.Text.formatMoney(self.landPrice))
    UIHelper.Element.setText(self.cashTaxText, UIHelper.Text.formatMoney(0))  -- No transfer tax in FS
    UIHelper.Element.setText(self.cashTotalText, UIHelper.Text.formatMoney(self.landPrice))
end

--[[
    Update finance mode display
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateFinanceDisplay()
    local termYears = UnifiedLandPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 15
    local downPct = UnifiedLandPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)

    local downPayment = self.landPrice * (downPct / 100)
    local amountFinanced = self.landPrice - downPayment

    -- Use centralized calculation function
    local termMonths = termYears * 12
    local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
        amountFinanced,
        self.interestRate,
        termMonths
    )

    -- Update UI using UIHelper
    UIHelper.Element.setText(self.financeAmountText, UIHelper.Text.formatMoney(amountFinanced))
    UIHelper.Element.setText(self.financeRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Finance.displayMonthlyPayment(self.financeMonthlyText, monthlyPayment)
    UIHelper.Element.setTextWithColor(self.financeTotalInterestText,
        UIHelper.Text.formatMoney(math.max(0, totalInterest)), UIHelper.Colors.COST_ORANGE)
    UIHelper.Element.setText(self.financeDueTodayText, UIHelper.Text.formatMoney(downPayment))
    UIHelper.Element.setText(self.financeCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
end

--[[
    Get soil quality key for multiplier lookup
    Maps self.soilQuality string to multiplier table key
]]
function UnifiedLandPurchaseDialog:getSoilMultiplierKey()
    local qualityMap = {
        ["Excellent"] = "excellent",
        ["Good"] = "good",
        ["Average"] = "average",
        ["Standard"] = "average",  -- Default fallback
        ["Poor"] = "poor",
        ["Unknown"] = "average"
    }
    return qualityMap[self.soilQuality] or "average"
end

--[[
    Get credit level for lease multiplier lookup
    Uses CreditScore system if available
]]
function UnifiedLandPurchaseDialog:getCreditLevel()
    if CreditScore and CreditScore.getRating then
        local rating, level = CreditScore.getRating(self.creditScore)
        return level or 3  -- Default to Fair (level 3)
    end
    return 3  -- Fair baseline
end

--[[
    Calculate annual lease payment based on acreage, soil quality, and credit
    Formula: Annual Payment = Base Rate × Hectares × Soil Multiplier × Credit Multiplier
]]
function UnifiedLandPurchaseDialog:calculateAnnualLeasePayment()
    local baseRate = UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA  -- $1000/ha/year
    local hectares = self.landSize or 0

    -- Get multipliers
    local soilKey = self:getSoilMultiplierKey()
    local soilMult = UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS[soilKey] or 1.0

    local creditLevel = self:getCreditLevel()
    local creditMult = UnifiedLandPurchaseDialog.CREDIT_LEASE_MULTIPLIERS[creditLevel] or 1.0

    local annualPayment = baseRate * hectares * soilMult * creditMult

    return math.ceil(annualPayment), soilMult, creditMult
end

--[[
    Estimate value of standing crops on the farmland
    For leases 12+ months, tenant gets the crop as "signing bonus"

    Simple estimation based on grain (wheat/barley):
    - Assume 60% of land has harvestable crops
    - Use typical grain yield (~7 tons/ha) and price (~$320/ton)
    - Results in ~$1,344/ha estimated crop value
]]
function UnifiedLandPurchaseDialog:estimateCropValue()
    local hectares = self.landSize or 0
    if hectares <= 0 then
        return 0, nil
    end

    -- Calculate estimated crop value based on grain
    local arableHa = hectares * UnifiedLandPurchaseDialog.CROP_COVERAGE_PERCENT
    local yieldTons = arableHa * UnifiedLandPurchaseDialog.GRAIN_YIELD_PER_HA
    local cropValue = yieldTons * UnifiedLandPurchaseDialog.GRAIN_PRICE_PER_TON

    -- Adjust for soil quality (better soil = more crops)
    local soilKey = self:getSoilMultiplierKey()
    local soilMult = UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS[soilKey] or 1.0
    cropValue = cropValue * soilMult

    return math.floor(cropValue), "grain"
end

--[[
    Update lease mode display
    Lease payment based on acreage × soil × credit, NOT property value
    Security deposit = credit-based months of payment (automatic, not selectable)
]]
function UnifiedLandPurchaseDialog:updateLeaseDisplay()
    -- Get term in months
    local termMonths = UnifiedLandPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12

    -- Calculate lease payment using formula
    local annualPayment, soilMult, creditMult = self:calculateAnnualLeasePayment()
    local monthlyPayment = math.ceil(annualPayment / 12)

    -- Security deposit = credit-based months of lease payment (automatic)
    local securityDeposit, depositMonths, depositTierName = FinanceCalculations.calculateSecurityDeposit(
        monthlyPayment, self.creditScore)

    -- Total lease cost over full term
    local totalPayments = monthlyPayment * termMonths
    local totalLeaseCost = totalPayments + securityDeposit

    -- Buyout price (can purchase land at any time)
    local buyoutPrice = self.landPrice

    -- Check for signing bonus (crop value for 12+ month leases)
    local cropValue, cropName = self:estimateCropValue()
    local hasSigningBonus = (termMonths >= 12 and cropValue > 0)

    -- Store for executeLeasePurchase
    self.calculatedMonthlyPayment = monthlyPayment
    self.calculatedAnnualPayment = annualPayment
    self.calculatedSecurityDeposit = securityDeposit
    self.calculatedCropBonus = hasSigningBonus and cropValue or 0
    self.calculatedCropName = cropName

    -- Update UI using UIHelper
    UIHelper.Finance.displayMonthlyPayment(self.leaseMonthlyText, monthlyPayment)

    -- Show rate breakdown
    if self.leaseRateText then
        local rateInfo = string.format("%s/ha × %.0f%% soil × %.0f%% credit",
            UIHelper.Text.formatMoney(UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA),
            soilMult * 100,
            creditMult * 100)
        UIHelper.Element.setText(self.leaseRateText, rateInfo)
    end

    -- Annual payment display
    if self.leaseAnnualText then
        UIHelper.Element.setText(self.leaseAnnualText, UIHelper.Text.formatMoney(annualPayment) .. "/year")
    end

    -- Security deposit (credit-based, not selectable)
    if self.leaseDepositText then
        local depositText
        if depositMonths == 0 then
            depositText = string.format(g_i18n:getText("usedplus_land_noDeposit"), depositTierName)
        else
            depositText = string.format(g_i18n:getText("usedplus_land_depositInfo"),
                UIHelper.Text.formatMoney(securityDeposit), depositMonths, depositTierName)
        end
        UIHelper.Element.setText(self.leaseDepositText, depositText)
    end

    -- Due today = security deposit only
    UIHelper.Element.setText(self.leaseDueTodayText, UIHelper.Text.formatMoney(securityDeposit))

    -- Total over lease term
    UIHelper.Element.setText(self.leaseTotalText, UIHelper.Text.formatMoney(totalLeaseCost))

    -- Buyout price to own the land (formatted as full sentence)
    UIHelper.Element.setText(self.leaseBuyoutText, string.format(g_i18n:getText("usedplus_land_buyoutAnytime"), UIHelper.Text.formatMoney(buyoutPrice)))

    -- Credit info
    UIHelper.Element.setText(self.leaseCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))

    -- Signing bonus display (for 12+ month leases with standing crops)
    if self.signingBonusSection then
        UIHelper.Element.setVisible(self.signingBonusSection, hasSigningBonus)
        if hasSigningBonus and self.signingBonusText then
            local bonusText = string.format(g_i18n:getText("usedplus_land_signingBonus"),
                cropName or "crops",
                UIHelper.Text.formatMoney(cropValue))
            UIHelper.Element.setText(self.signingBonusText, bonusText)
        end
    end
end

--[[
    Confirm purchase button clicked
]]
function UnifiedLandPurchaseDialog:onConfirmPurchase()
    if self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH then
        self:executeCashPurchase()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE then
        self:executeFinancePurchase()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE then
        self:executeLeasePurchase()
    end
end

--[[
    Execute cash purchase
]]
function UnifiedLandPurchaseDialog:executeCashPurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for cash purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Check if player can afford
    if self.landPrice > farm.money then
        local shortfall = self.landPrice - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsLand"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Use game's farmland purchase system
    if g_farmlandManager and self.farmlandId then
        g_farmlandManager:setLandOwnership(self.farmlandId, farmId)
        g_currentMission:addMoney(-self.landPrice, farmId, MoneyType.PROPERTY, true, true)

        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_landPurchased"),
                self.landName, UIHelper.Text.formatMoney(self.landPrice)))
    else
        UsedPlus.logError("g_farmlandManager or farmlandId is nil")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_couldNotCompletePurchase"))
    end

    self:close()
end

--[[
    Execute finance purchase
]]
function UnifiedLandPurchaseDialog:executeFinancePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for finance purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Calculate finance parameters (using filtered options from settings)
    local termYears = UnifiedLandPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 15
    local downPct = UnifiedLandPurchaseDialog.getDownPaymentPercent(self.financeDownIndex)
    local downPayment = self.landPrice * (downPct / 100)

    -- Check if player can afford down payment
    if downPayment > farm.money then
        local shortfall = downPayment - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDownPayment"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Deduct down payment
    if downPayment > 0 then
        g_currentMission:addMoney(-downPayment, farmId, MoneyType.PROPERTY, true, true)
    end

    -- Transfer land ownership
    if g_farmlandManager and self.farmlandId then
        g_farmlandManager:setLandOwnership(self.farmlandId, farmId)
    end

    -- Calculate amount financed
    local amountFinanced = self.landPrice - downPayment

    -- Create finance deal for land
    if g_financeManager and FinanceDeal and amountFinanced > 0 then
        local deal = FinanceDeal.new(
            farmId,
            "land",
            "farmland_" .. tostring(self.farmlandId),
            self.landName,
            self.landPrice,
            downPayment,
            termYears * 12,
            self.interestRate,
            0
        )
        g_financeManager:addDeal(deal)
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notify_landFinanced"),
            self.landName, UIHelper.Text.formatMoney(downPayment)))

    self:close()
end

--[[
    Execute lease purchase
    NEW SYSTEM: Lease based on acreage, security deposit based on credit score
]]
function UnifiedLandPurchaseDialog:executeLeasePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for lease purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Get calculated values from updateLeaseDisplay (already computed)
    local termMonths = UnifiedLandPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12
    local monthlyPayment = self.calculatedMonthlyPayment or 0
    local annualPayment = self.calculatedAnnualPayment or 0
    local securityDeposit = self.calculatedSecurityDeposit or 0

    -- Recalculate if needed (safety check)
    if monthlyPayment == 0 then
        annualPayment = self:calculateAnnualLeasePayment()
        monthlyPayment = math.ceil(annualPayment / 12)
        -- Security deposit is credit-based (automatic)
        securityDeposit = FinanceCalculations.calculateSecurityDeposit(monthlyPayment, self.creditScore)
    end

    -- Check if player can afford security deposit
    if securityDeposit > farm.money then
        local shortfall = securityDeposit - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDeposit"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Deduct security deposit
    if securityDeposit > 0 then
        g_currentMission:addMoney(-securityDeposit, farmId, MoneyType.LEASING_COSTS, true, true)
    end

    -- Transfer land ownership (leased land still counts as owned for gameplay)
    if g_farmlandManager and self.farmlandId then
        g_farmlandManager:setLandOwnership(self.farmlandId, farmId)
    end

    -- Create lease deal with payment-based tracking
    if g_financeManager and FinanceDeal then
        -- Calculate effective annual "rate" for record keeping (not actually used for payment calc)
        local effectiveRate = self.landPrice > 0 and (annualPayment / self.landPrice) or 0.08

        local deal = FinanceDeal.new(
            farmId,
            "lease",
            "farmland_" .. tostring(self.farmlandId),
            self.landName .. " (Lease)",
            self.landPrice,           -- Original land value (for buyout)
            securityDeposit,          -- Security deposit paid
            termMonths,               -- Lease term in months
            effectiveRate,            -- Effective rate for records
            0                         -- No cash back for leases
        )
        deal.dealType = 2             -- Lease type
        deal.residualValue = self.landPrice  -- Buyout price to own
        deal.monthlyPayment = monthlyPayment -- Monthly lease payment
        deal.currentBalance = 0       -- No principal balance for lease
        g_financeManager:addDeal(deal)
    end

    -- Format confirmation message
    local depositText = securityDeposit > 0
        and string.format(g_i18n:getText("usedplus_land_securityDeposit"), UIHelper.Text.formatMoney(securityDeposit))
        or g_i18n:getText("usedplus_land_noDepositRequired")

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notify_landLeased"),
            self.landName,
            UIHelper.Text.formatMoney(monthlyPayment),
            depositText))

    self:close()
end

--[[
    Cancel button clicked
]]
function UnifiedLandPurchaseDialog:onCancel()
    self:close()
end

--[[
    Static show method
]]
function UnifiedLandPurchaseDialog.show(farmlandId, farmland, price, initialMode)
    local dialog = g_gui.guis.UnifiedLandPurchaseDialog
    if dialog and dialog.target then
        dialog.target:setLandData(farmlandId, farmland, price)
        dialog.target:setInitialMode(initialMode or UnifiedLandPurchaseDialog.MODE_CASH)
        g_gui:showDialog("UnifiedLandPurchaseDialog")
    else
        UsedPlus.logError("UnifiedLandPurchaseDialog not registered")
    end
end

UsedPlus.logInfo("UnifiedLandPurchaseDialog loaded")
