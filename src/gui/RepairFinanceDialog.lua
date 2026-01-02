--[[
    FS25_UsedPlus - Repair Finance Dialog

     GUI for financing repair/repaint costs
     Pattern from: FinanceDialog (working reference)

    Features:
    - Term selection (3, 6, 12, 18, 24 months)
    - Down payment options (0%, 25%, 50%)
    - Live preview of monthly payments, total interest
    - Credit score display
]]

RepairFinanceDialog = {}
local RepairFinanceDialog_mt = Class(RepairFinanceDialog, MessageDialog)

--[[
     Constructor
]]
function RepairFinanceDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or RepairFinanceDialog_mt)

    self.i18n = i18n or g_i18n

    -- Vehicle/repair data
    self.vehicle = nil
    self.vehicleName = ""
    self.farmId = 0
    self.repairCost = 0
    self.repairPercent = 0
    self.repaintPercent = 0
    self.mode = "repair"  -- "repair" or "repaint"

    -- Finance configuration
    self.termMonths = 6  -- Default 6 months
    self.downPaymentPercent = 0  -- Default 0%

    -- Calculated values
    self.monthlyPayment = 0
    self.totalInterest = 0
    self.totalPayments = 0
    self.interestRate = 0
    self.creditScore = 650

    -- Track if data is set
    self.isDataSet = false

    return self
end

-- Term options in months
RepairFinanceDialog.TERM_OPTIONS = {3, 6, 12, 18, 24}
-- Down payment options as percentages (matches UnifiedPurchaseDialog)
RepairFinanceDialog.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}

--[[
    Get available down payment options based on settings minimum
    @return filtered table of down payment percentages
]]
function RepairFinanceDialog.getDownPaymentOptions()
    local minPercent = UsedPlusSettings and UsedPlusSettings:get("minDownPaymentPercent") or 0
    local options = {}
    for _, pct in ipairs(RepairFinanceDialog.DOWN_PAYMENT_OPTIONS) do
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
function RepairFinanceDialog.getDownPaymentPercent(index)
    local options = RepairFinanceDialog.getDownPaymentOptions()
    return options[index] or options[1] or 0
end

--[[
     Called when dialog opens
]]
function RepairFinanceDialog:onOpen()
    RepairFinanceDialog:superClass().onOpen(self)

    -- Initialize term options using helper
    UIHelper.Element.populateTermSelector(self.termSlider, RepairFinanceDialog.TERM_OPTIONS, "month", 2)

    -- Initialize down payment options using helper (filtered by settings)
    UIHelper.Element.populatePercentSelector(self.downPaymentSlider, RepairFinanceDialog.getDownPaymentOptions(), 1)

    -- Update preview if data is set
    if self.isDataSet then
        self:updatePreview()
    end
end

--[[
     Set repair data for financing
    @param vehicle - The vehicle being repaired
    @param farmId - Farm ID
    @param repairCost - Total cost of repair
    @param repairPercent - Repair percentage (0-100)
    @param repaintPercent - Repaint percentage (0-100)
    @param mode - "repair" or "repaint"
]]
function RepairFinanceDialog:setData(vehicle, farmId, repairCost, repairPercent, repaintPercent, mode)
    self.vehicle = vehicle
    self.farmId = farmId
    self.repairCost = repairCost
    self.repairPercent = repairPercent
    self.repaintPercent = repaintPercent
    self.mode = mode or "repair"
    self.storeItem = nil

    -- Get vehicle name using consolidated utility
    if vehicle then
        self.storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        self.vehicleName = UIHelper.Vehicle.getFullName(self.storeItem)
    end

    -- Update title based on mode
    if self.dialogTitleElement then
        if self.mode == "repaint" then
            self.dialogTitleElement:setText(g_i18n:getText("usedplus_repairfinance_title_repaint"))
        else
            self.dialogTitleElement:setText(g_i18n:getText("usedplus_repairfinance_title_repair"))
        end
    end

    -- Update vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(self.vehicleName)
    end

    -- Update service type (Mechanical Repair or Repaint)
    if self.serviceTypeText then
        local serviceType = self.mode == "repaint"
            and g_i18n:getText("usedplus_rp_sectionRepaint")
            or g_i18n:getText("usedplus_rp_sectionRepair")
        self.serviceTypeText:setText(serviceType)
    end

    -- Set vehicle image
    if self.vehicleImageElement and self.storeItem then
        UIHelper.Image.setStoreItemImage(self.vehicleImageElement, self.storeItem)
    end

    -- Update repair cost display with label
    local costLabel = self.mode == "repaint"
        and g_i18n:getText("usedplus_rf_repaintCost") or g_i18n:getText("usedplus_rf_repairCost")
    UIHelper.Element.setText(self.repairCostText, costLabel .. " " .. UIHelper.Text.formatMoney(self.repairCost))

    -- Get credit score
    if CreditScore then
        self.creditScore = CreditScore.calculate(farmId)
    end

    self.isDataSet = true
    self:updatePreview()
end

--[[
     Check credit qualification and minimum amount, update UI
]]
function RepairFinanceDialog:updateCreditStatus()
    self.canFinanceRepair = true
    local warningMsg = nil

    -- Check minimum financing amount first
    if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
        local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(self.repairCost or 0, "REPAIR_FINANCE")
        if not meetsMinimum then
            self.canFinanceRepair = false
            warningMsg = string.format(g_i18n:getText("usedplus_repair_amountTooSmall") or "Amount too small for financing. Minimum: %s",
                g_i18n:formatMoney(minRequired, 0, true, true))
        end
    end

    -- Then check credit score (only if amount check passed)
    if self.canFinanceRepair and CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore = CreditScore.canFinance(self.farmId, "REPAIR")
        if not canFinance then
            self.canFinanceRepair = false
            local template = g_i18n:getText("usedplus_credit_tooLowForRepair")
            warningMsg = string.format(template, currentScore, minRequired)
        end
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
        self.acceptButton:setDisabled(not self.canFinanceRepair)
    end
end

--[[
     Update live preview when options change
]]
function RepairFinanceDialog:updatePreview()
    if not self.isDataSet then return end

    -- Update credit status
    self:updateCreditStatus()

    -- Get term from slider
    local termIndex = 2  -- Default
    if self.termSlider then
        termIndex = self.termSlider:getState()
    end

    -- Get term from class constants
    self.termMonths = RepairFinanceDialog.TERM_OPTIONS[termIndex] or 6

    -- Get down payment from slider
    local downPaymentIndex = 1  -- Default
    if self.downPaymentSlider then
        downPaymentIndex = self.downPaymentSlider:getState()
    end

    -- Get down payment percent from filtered options (convert from 0-100 to 0-1)
    local downPaymentPct = RepairFinanceDialog.getDownPaymentPercent(downPaymentIndex)
    self.downPaymentPercent = downPaymentPct / 100

    -- Calculate down payment amount
    local downPayment = self.repairCost * self.downPaymentPercent

    -- Calculate amount financed
    local amountFinanced = self.repairCost - downPayment

    -- Calculate interest rate based on credit score
    local baseRate = 0.08  -- 8% base
    local rateAdj = 0
    if CreditScore then
        rateAdj = CreditScore.getInterestAdjustment(self.creditScore) or 0
    end
    self.interestRate = (baseRate + (rateAdj / 100)) * 100  -- Convert to percentage display

    -- Use centralized calculation function
    local annualRate = self.interestRate / 100  -- Convert back to decimal
    self.monthlyPayment, self.totalInterest = FinanceCalculations.calculateMonthlyPayment(
        amountFinanced,
        annualRate,
        self.termMonths
    )

    -- Calculate total payments
    self.totalPayments = self.monthlyPayment * self.termMonths

    -- Update UI elements using UIHelper
    UIHelper.Finance.displayMonthlyPayment(self.monthlyPaymentText, self.monthlyPayment)
    UIHelper.Element.setTextWithColor(self.totalInterestText,
        UIHelper.Text.formatMoney(self.totalInterest), UIHelper.Colors.COST_ORANGE)
    UIHelper.Finance.displayInterestRate(self.interestRateText, self.interestRate / 100)
    UIHelper.Element.setText(self.totalPaymentsText, UIHelper.Text.formatMoney(self.totalPayments))
    UIHelper.Element.setText(self.downPaymentDisplayText, UIHelper.Text.formatMoney(downPayment))
    UIHelper.Element.setText(self.dueTodayText, UIHelper.Text.formatMoney(downPayment))

    -- Credit score with color
    UIHelper.Credit.display(self.creditScoreText, self.creditRatingText, self.creditScore)
end

--[[
     Term slider changed callback
]]
function RepairFinanceDialog:onTermChanged()
    self:updatePreview()
end

--[[
     Down payment slider changed callback
]]
function RepairFinanceDialog:onDownPaymentChanged()
    self:updatePreview()
end

--[[
     Accept button clicked - process the financed repair
]]
function RepairFinanceDialog:onAcceptFinance()
    if not self.vehicle or self.repairCost <= 0 then
        UsedPlus.logWarn("RepairFinanceDialog: No valid repair data")
        return
    end

    -- Credit score check - repair financing has lowest bar but still requires minimum
    if CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore, message = CreditScore.canFinance(self.farmId, "REPAIR")
        if not canFinance then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Repair finance rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Calculate down payment
    local downPayment = self.repairCost * self.downPaymentPercent

    -- Check if player can afford down payment
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm and farm.money < downPayment then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Insufficient funds for down payment. Need %s",
                UIHelper.Text.formatMoney(downPayment))
        )
        return
    end

    -- Send repair event with finance flag
    -- Note: repairPercent and repaintPercent are already mode-specific (0 for inactive mode)
    RepairVehicleEvent.sendToServer(
        self.vehicle,
        self.farmId,
        self.repairPercent / 100,
        self.repaintPercent / 100,
        self.repairCost,
        true,  -- Financed
        self.termMonths,
        self.monthlyPayment,
        downPayment
    )

    -- Close dialog
    self:close()

    -- Show success notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("%s financed!\n%s over %d months\n%s/month",
            self.mode == "repaint" and "Repaint" or "Repair",
            self.vehicleName,
            self.termMonths,
            UIHelper.Text.formatMoney(self.monthlyPayment))
    )

    -- Refresh the WorkshopScreen to show updated values
    if RepairDialog and RepairDialog.refreshWorkshopScreen then
        RepairDialog.refreshWorkshopScreen()
    end
end

--[[
     Cancel button clicked
]]
function RepairFinanceDialog:onCancel()
    self:close()
end

--[[
     Dialog closed - cleanup
]]
function RepairFinanceDialog:onClose()
    self.vehicle = nil
    self.vehicleName = ""
    self.farmId = 0
    self.repairCost = 0
    self.isDataSet = false

    RepairFinanceDialog:superClass().onClose(self)
end

UsedPlus.logInfo("RepairFinanceDialog loaded")
