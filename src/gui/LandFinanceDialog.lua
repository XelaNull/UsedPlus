--[[
    FS25_UsedPlus - Land Finance Dialog

     GUI class for farmland financing
     Pattern from: FinanceDialog.lua (working implementation)
     Reference: FS25_ADVANCED_PATTERNS.md - GUI Dialog Pattern

    Responsibilities:
    - Display field details (number, size, price)
    - Provide sliders for term (5-30 years), down payment (0-40%)
    - Live preview with lower interest rates (land-specific)
    - Display credit score
    - Send FinanceVehicleEvent with itemType="land"

    Differences from Vehicle Finance:
    - Longer term range (5-30 years vs 1-20)
    - Lower interest rates (base 3.5% vs 4.5%)
    - Higher down payment max (40% vs 50%)
    - No cash back option
]]

LandFinanceDialog = {}
local LandFinanceDialog_mt = Class(LandFinanceDialog, MessageDialog)

--[[
     Constructor
     Pattern from FinanceDialog
]]
function LandFinanceDialog.new(target, customMt, i18n)
    local self = MessageDialog.new(target, customMt or LandFinanceDialog_mt)

    -- Controls are automatically mapped by g_gui:loadGui() based on XML id attributes
    -- Available controls after loadGui:
    --   self.fieldNumberText, self.fieldSizeText, self.fieldPriceText
    --   self.termSlider, self.downPaymentSlider
    --   self.downPaymentText, self.dueTodayText
    --   self.monthlyPaymentText, self.yearlyPaymentText
    --   self.totalInterestText, self.interestRateText
    --   self.creditScoreText, self.creditRatingText

    -- Data for current finance configuration
    self.fieldId = nil
    self.fieldPrice = 0
    self.farmId = nil
    self.i18n = i18n
    self.isDataSet = false  -- Prevent callbacks before data is set

    return self
end

--[[
     Called when dialog is created (required by GUI system)
]]
function LandFinanceDialog:onCreate()
    LandFinanceDialog:superClass().onCreate(self)
end

-- Generate term options array (5-30 years for land)
LandFinanceDialog.TERM_OPTIONS = {}
for years = 5, 30 do
    table.insert(LandFinanceDialog.TERM_OPTIONS, years)
end

-- Generate down payment options array (0-40% in 5% steps)
LandFinanceDialog.DOWN_PAYMENT_OPTIONS = {}
for percent = 0, 40, 5 do
    table.insert(LandFinanceDialog.DOWN_PAYMENT_OPTIONS, percent)
end

--[[
     Called when dialog opens (required by GUI system)
]]
function LandFinanceDialog:onOpen()
    LandFinanceDialog:superClass().onOpen(self)

    -- Initialize term options using helper (5-30 years)
    UIHelper.Element.populateTermSelector(self.termSlider, LandFinanceDialog.TERM_OPTIONS, "year", 11)

    -- Initialize down payment options using helper (0-40% in 5% steps)
    UIHelper.Element.populatePercentSelector(self.downPaymentSlider, LandFinanceDialog.DOWN_PAYMENT_OPTIONS, 5)

    -- Update preview after sliders are initialized (if data is set)
    if self.isDataSet then
        self:updatePreview()
    end
end

--[[
     Initialize dialog with field data
     Called by InGameMenuMapFrameExtension when finance option selected
]]
function LandFinanceDialog:setData(fieldId, fieldPrice, farmId)
    self.fieldId = fieldId
    self.fieldPrice = fieldPrice
    self.farmId = farmId

    UsedPlus.logDebug(string.format("Land Finance setData called: fieldId=%s, price=%s, farmId=%s",
        tostring(fieldId), tostring(fieldPrice), tostring(farmId)))

    -- Display field number
    if self.fieldNumberText then
        self.fieldNumberText:setText(string.format("Field %d", fieldId))
    end

    -- Get field info from game (safely)
    -- Correct property is areaInHa (already in hectares)
    -- Pattern from: FS25_FarmlandOverview
    local farmland = g_farmlandManager:getFarmlandById(fieldId)
    if farmland and self.fieldSizeText then
        local areaHa = farmland.areaInHa or 0
        if areaHa > 0 then
            -- Use game's localized area formatting
            self.fieldSizeText:setText(string.format("%.2f %s", g_i18n:getArea(areaHa), g_i18n:getAreaUnit()))
        else
            self.fieldSizeText:setText("--")
        end
    elseif self.fieldSizeText then
        self.fieldSizeText:setText("--")
    end

    -- Display price
    if self.fieldPriceText then
        self.fieldPriceText:setText(g_i18n:formatMoney(self.fieldPrice))
    end

    -- Mark data as set
    self.isDataSet = true

    -- Update preview with new data (only if sliders exist)
    if self.termSlider and self.downPaymentSlider then
        self:updatePreview()
    end
end

--[[
     Check credit qualification and minimum amount, update UI accordingly
]]
function LandFinanceDialog:updateCreditStatus()
    self.canFinanceLand = true
    local warningMsg = nil

    -- Check minimum financing amount first
    if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
        local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(self.fieldPrice or 0, "LAND_FINANCE")
        if not meetsMinimum then
            self.canFinanceLand = false
            warningMsg = string.format(g_i18n:getText("usedplus_land_amountTooSmall") or "Amount too small for land financing. Minimum: %s",
                g_i18n:formatMoney(minRequired, 0, true, true))
        end
    end

    -- Then check credit score (only if amount check passed)
    if self.canFinanceLand and CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore, message = CreditScore.canFinance(self.farmId, "LAND_FINANCE")
        if not canFinance then
            self.canFinanceLand = false
            local template = g_i18n:getText("usedplus_credit_tooLowForLand")
            warningMsg = string.format(template, currentScore, minRequired)
        end
        self.landMinScore = minRequired
        self.currentCreditScore = currentScore
    end

    -- Show/hide warning
    if self.creditWarningText then
        if warningMsg then
            self.creditWarningText:setText(warningMsg)
            self.creditWarningText:setVisible(true)
            self.creditWarningText:setTextColor(1, 0.3, 0.3, 1)
        else
            self.creditWarningText:setVisible(false)
        end
    end

    -- Disable accept button if cannot finance
    if self.acceptButton then
        self.acceptButton:setDisabled(not self.canFinanceLand)
    end
end

--[[
     Update live preview with land-specific interest rates
]]
function LandFinanceDialog:updatePreview()
    -- Safety checks - don't run until data is set
    if not self.isDataSet then return end
    if self.fieldPrice == nil or self.fieldPrice == 0 then return end
    if self.termSlider == nil or self.downPaymentSlider == nil then return end

    -- Update credit status (enables/disables accept button)
    self:updateCreditStatus()

    -- Get current slider values (1-based index) with safety
    local termIndex = self.termSlider:getState()
    if termIndex == nil or termIndex < 1 then termIndex = 11 end  -- Default 15 years
    -- Get term from class constants
    local termYears = LandFinanceDialog.TERM_OPTIONS[termIndex] or 15
    local termMonths = termYears * 12

    local downPaymentIndex = self.downPaymentSlider:getState()
    if downPaymentIndex == nil or downPaymentIndex < 1 then downPaymentIndex = 5 end  -- Default 20%
    -- Get down payment percent from class constants (convert from 0-100 to 0-1)
    local downPaymentPct = LandFinanceDialog.DOWN_PAYMENT_OPTIONS[downPaymentIndex] or 20
    local downPaymentPercent = downPaymentPct / 100
    local downPayment = self.fieldPrice * downPaymentPercent

    -- Calculate credit score
    local creditScore = CreditScore.calculate(self.farmId)
    local creditRating, creditTier = CreditScore.getRating(creditScore)

    -- Calculate land-specific interest rate (lower than vehicle)
    local interestRate = FinanceCalculations.calculateLandInterestRate(
        creditScore,
        termYears,
        downPaymentPercent
    )

    -- Calculate amount financed (no cash back for land)
    local amountFinanced = self.fieldPrice - downPayment

    -- Use centralized calculation function
    local annualRate = interestRate / 100  -- Convert percentage to decimal
    local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
        amountFinanced,
        annualRate,
        termMonths
    )
    local yearlyPayment = monthlyPayment * 12

    -- Update text displays using UIHelper
    UIHelper.Element.setText(self.downPaymentText, UIHelper.Text.formatMoney(downPayment))
    UIHelper.Element.setText(self.dueTodayText, UIHelper.Text.formatMoney(downPayment))
    UIHelper.Finance.displayMonthlyPayment(self.monthlyPaymentText, monthlyPayment)
    UIHelper.Element.setText(self.yearlyPaymentText, UIHelper.Text.formatMoney(yearlyPayment))
    UIHelper.Element.setTextWithColor(self.totalInterestText,
        UIHelper.Text.formatMoney(totalInterest), UIHelper.Colors.COST_ORANGE)
    UIHelper.Finance.displayInterestRate(self.interestRateText, interestRate / 100)

    -- Credit display with color
    UIHelper.Credit.display(self.creditScoreText, self.creditRatingText, creditScore)
end

--[[
     Callback when term slider changes
]]
function LandFinanceDialog:onTermChanged()
    if self.isDataSet then
        self:updatePreview()
    end
end

--[[
     Callback when down payment slider changes
]]
function LandFinanceDialog:onDownPaymentChanged()
    if self.isDataSet then
        self:updatePreview()
    end
end

--[[
     Callback when "Accept Finance" button clicked
]]
function LandFinanceDialog:onAcceptFinance()

    if self.fieldId == nil then
        UsedPlus.logError("No field selected for financing")
        return
    end

    -- Credit score check - land financing requires minimum credit score
    if CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore, message = CreditScore.canFinance(self.farmId, "LAND_FINANCE")
        if not canFinance then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Land finance rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Get final values from class constants
    local termIndex = self.termSlider:getState()
    local termYears = LandFinanceDialog.TERM_OPTIONS[termIndex] or 15

    local downPaymentIndex = self.downPaymentSlider:getState()
    local downPaymentPct = LandFinanceDialog.DOWN_PAYMENT_OPTIONS[downPaymentIndex] or 20
    local downPayment = self.fieldPrice * (downPaymentPct / 100)

    -- Validate funds
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError("Farm not found")
        return
    end

    if farm.money < downPayment then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFunds"), g_i18n:formatMoney(downPayment))
        )
        return
    end

    -- Get field name
    local fieldName = string.format("Field %d", self.fieldId)

    -- Send finance request with itemType="land"
    FinanceVehicleEvent.sendToServer(
        self.farmId,
        "land",              -- Item type
        self.fieldId,        -- Item ID (field number)
        fieldName,           -- Item name
        self.fieldPrice,     -- Base price
        downPayment,         -- Down payment
        termYears,           -- Term years
        0                    -- No cash back for land
    )

    -- Close dialog
    self:close()
end

--[[
     Callback when "Cancel" button clicked
]]
function LandFinanceDialog:onCancel()
    self:close()
end

--[[
     Cleanup when dialog closes
]]
function LandFinanceDialog:onClose()
    -- Clear data
    self.fieldId = nil
    self.fieldPrice = 0
    self.farmId = nil
    self.isDataSet = false  -- Reset flag for next use

    -- Call parent close
    LandFinanceDialog:superClass().onClose(self)
end

UsedPlus.logInfo("LandFinanceDialog loaded")
