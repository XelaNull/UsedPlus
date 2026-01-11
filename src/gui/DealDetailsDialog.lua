--[[
    DealDetailsDialog.lua
    Dialog to display comprehensive details about a finance or lease deal

    Shows item info, financial terms, payment progress, and payment summary
    Provides early payoff option if player has sufficient funds
]]

DealDetailsDialog = {}
-- Use ScreenElement, NOT MessageDialog (MessageDialog lacks registerControls and causes issues)
local DealDetailsDialog_mt = Class(DealDetailsDialog, ScreenElement)

-- Static instance
DealDetailsDialog.instance = nil
DealDetailsDialog.xmlPath = nil

-- Payment multiplier options
DealDetailsDialog.MULTIPLIER_OPTIONS = {1.0, 1.2, 1.5, 2.0, 3.0}
DealDetailsDialog.MULTIPLIER_TEXTS = {"1x", "1.2x", "1.5x", "2x", "3x"}

--[[
    Get or create dialog instance
    Follows singleton pattern for dialogs
]]
function DealDetailsDialog.getInstance()
    if DealDetailsDialog.instance == nil then
        -- Determine XML path
        if DealDetailsDialog.xmlPath == nil then
            DealDetailsDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/DealDetailsDialog.xml"
        end

        DealDetailsDialog.instance = DealDetailsDialog.new()
        g_gui:loadGui(DealDetailsDialog.xmlPath, "DealDetailsDialog", DealDetailsDialog.instance)
    end

    return DealDetailsDialog.instance
end

--[[
    Constructor - extends ScreenElement, NOT MessageDialog
]]
function DealDetailsDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or DealDetailsDialog_mt)

    self.deal = nil
    self.onCloseCallback = nil
    self.isBackAllowed = true

    return self
end

--[[
    Called when GUI elements are ready
    Set up multiplier dropdown texts
]]
function DealDetailsDialog:onGuiSetupFinished()
    DealDetailsDialog:superClass().onGuiSetupFinished(self)

    -- Set up multiplier dropdown texts
    if self.multiplierSelector then
        self.multiplierSelector:setTexts(DealDetailsDialog.MULTIPLIER_TEXTS)
        self.multiplierSelector:setState(1)  -- Default to 1x (first option)
    end
end

--[[
    Show dialog with deal information
    @param deal - FinanceDeal or LeaseDeal object
    @param onCloseCallback - Optional callback when dialog closes
]]
function DealDetailsDialog:show(deal, onCloseCallback)
    if deal == nil then
        UsedPlus.logError("DealDetailsDialog:show called with nil deal")
        return
    end

    self.deal = deal
    self.onCloseCallback = onCloseCallback

    -- Populate all fields
    self:updateDisplay()

    -- Show the dialog
    g_gui:showDialog("DealDetailsDialog")
end

--[[
    Update all display fields with deal data
]]
function DealDetailsDialog:updateDisplay()
    if self.deal == nil then return end

    local deal = self.deal
    local isLease = (deal.dealType == 2) or (deal.itemType == "lease")
    local isDefaulted = deal.status == "defaulted"

    -- Show/hide sections based on deal status
    self:updateSectionVisibility(isDefaulted)

    -- Update title based on deal type
    if self.dialogTitleElement then
        local title = isLease and "LEASE DETAILS" or "FINANCE DETAILS"
        self.dialogTitleElement:setText(title)
    end

    -- Item Info
    if self.itemNameText then
        self.itemNameText:setText(deal.itemName or "Unknown")
    end
    if self.itemTypeText then
        local typeText = deal.itemType or "vehicle"

        -- Convert itemType codes to display-friendly text
        local typeDisplayMap = {
            vehicle = "Vehicle Finance",
            repair = "Repair",
            repaint = "Repaint",
            repair_repaint = "Repair & Repaint",
            land = "Land Finance",
            lease = "Lease",
            land_lease = "Land Lease"
        }

        typeText = typeDisplayMap[typeText] or (typeText:sub(1,1):upper() .. typeText:sub(2))
        self.itemTypeText:setText(typeText)
    end

    -- Status
    if self.dealStatusText then
        local statusText = deal.status or "Active"
        statusText = statusText:sub(1,1):upper() .. statusText:sub(2)
        self.dealStatusText:setText(statusText)

        -- Color based on status
        if deal.status == "active" then
            self.dealStatusText:setTextColor(0.3, 1, 0.3, 1)  -- Green
        elseif deal.status == "defaulted" then
            self.dealStatusText:setTextColor(1, 0.3, 0.3, 1)  -- Red
        else
            self.dealStatusText:setTextColor(0.7, 0.7, 0.7, 1)  -- Gray
        end
    end

    if self.missedPaymentsText then
        local missed = deal.missedPayments or 0
        self.missedPaymentsText:setText(tostring(missed))

        -- Color red if any missed
        if missed > 0 then
            self.missedPaymentsText:setTextColor(1, 0.3, 0.3, 1)
        else
            self.missedPaymentsText:setTextColor(0.3, 1, 0.3, 1)
        end
    end

    -- Financial Terms
    if self.originalPriceText then
        self.originalPriceText:setText(g_i18n:formatMoney(deal.originalPrice or 0, 0, true, true))
    end
    if self.downPaymentText then
        self.downPaymentText:setText(g_i18n:formatMoney(deal.downPayment or 0, 0, true, true))
    end
    if self.amountFinancedText then
        self.amountFinancedText:setText(g_i18n:formatMoney(deal.amountFinanced or 0, 0, true, true))
    end

    if self.termText then
        local months = deal.termMonths or 0
        local years = math.floor(months / 12)
        local remainingMonths = months % 12
        local termStr
        if remainingMonths == 0 then
            termStr = string.format("%d months (%d year%s)", months, years, years == 1 and "" or "s")
        else
            termStr = string.format("%d months", months)
        end
        self.termText:setText(termStr)
    end

    if self.interestRateText then
        local rate = (deal.interestRate or 0) * 100  -- Convert from decimal
        self.interestRateText:setText(string.format("%.2f%%", rate))
    end

    if self.monthlyPaymentText then
        self.monthlyPaymentText:setText(g_i18n:formatMoney(deal.monthlyPayment or 0, 0, true, true))
    end

    -- Payment Progress
    if self.paymentsMadeText then
        local made = deal.monthsPaid or 0
        local total = deal.termMonths or 0
        self.paymentsMadeText:setText(string.format("%d of %d", made, total))
    end

    if self.monthsRemainingText then
        local remaining = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        self.monthsRemainingText:setText(tostring(math.max(0, remaining)))
    end

    if self.currentBalanceText then
        self.currentBalanceText:setText(g_i18n:formatMoney(deal.currentBalance or 0, 0, true, true))
    end

    if self.equityBuiltText then
        local equity = (deal.amountFinanced or 0) - (deal.currentBalance or 0)
        self.equityBuiltText:setText(g_i18n:formatMoney(math.max(0, equity), 0, true, true))
    end

    -- Payment Summary
    if self.principalPaidText then
        local principalPaid = (deal.amountFinanced or 0) - (deal.currentBalance or 0)
        self.principalPaidText:setText(g_i18n:formatMoney(math.max(0, principalPaid), 0, true, true))
    end

    if self.interestPaidText then
        self.interestPaidText:setText(g_i18n:formatMoney(deal.totalInterestPaid or 0, 0, true, true))
    end

    if self.totalPaidText then
        local principalPaid = (deal.amountFinanced or 0) - (deal.currentBalance or 0)
        local totalPaid = principalPaid + (deal.totalInterestPaid or 0)
        self.totalPaidText:setText(g_i18n:formatMoney(math.max(0, totalPaid), 0, true, true))
    end

    -- Payment Multiplier section
    self:updateMultiplierDisplay()

    -- Payoff amount (balance plus any accrued interest)
    local payoffAmount = deal.currentBalance or 0
    if deal.accruedInterest then
        payoffAmount = payoffAmount + deal.accruedInterest
    end

    if self.payoffAmountText then
        self.payoffAmountText:setText(g_i18n:formatMoney(payoffAmount, 0, true, true))
    end

    -- Calculate potential interest savings
    local remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0)
    local remainingPayments = remainingMonths * (deal.monthlyPayment or 0)
    local potentialSavings = remainingPayments - payoffAmount

    if self.infoText then
        if potentialSavings > 0 then
            self.infoText:setText(string.format(g_i18n:getText("usedplus_dealdetails_earlyPayoffSaves"),
                g_i18n:formatMoney(potentialSavings, 0, true, true)))
            self.infoText:setTextColor(0.3, 1, 0.3, 1)
        else
            self.infoText:setText(g_i18n:getText("usedplus_dealdetails_payoffInfo"))
            self.infoText:setTextColor(0.6, 0.6, 0.6, 1)
        end
    end

    -- Enable/disable payoff button based on funds and deal status
    if self.payoffButton then
        local farmId = g_currentMission:getFarmId()
        local farm = g_farmManager:getFarmById(farmId)
        local canPayoff = farm and farm.money >= payoffAmount and deal.status == "active"
        self.payoffButton:setDisabled(not canPayoff)

        if isLease then
            self.payoffButton:setText(g_i18n:getText("usedplus_dealdetails_buyoutLease"))
        else
            self.payoffButton:setText(g_i18n:getText("usedplus_dealdetails_earlyPayoff"))
        end
    end
end

--[[
    Handle view history button click
    Opens PaymentHistoryDialog showing full amortization schedule
]]
function DealDetailsDialog:onViewHistory()
    if self.deal == nil then return end

    -- Open payment history dialog
    if PaymentHistoryDialog then
        local historyDialog = PaymentHistoryDialog.getInstance()
        historyDialog:show(self.deal)
    else
        UsedPlus.logError("PaymentHistoryDialog not available")
    end
end

--[[
    Update the multiplier dropdown and adjusted payment display
    Also calculates and shows interest savings
]]
function DealDetailsDialog:updateMultiplierDisplay()
    if self.deal == nil then return end

    local deal = self.deal
    local basePayment = deal.monthlyPayment or 0

    -- For vanilla loans, get multiplier from FinanceManager instead of the pseudo-deal
    local currentMultiplier
    if deal.isVanillaLoan and g_financeManager then
        local farmId = deal.farmId or g_currentMission:getFarmId()
        currentMultiplier = g_financeManager:getVanillaLoanMultiplier(farmId)
    else
        currentMultiplier = deal.paymentMultiplier or 1.0
    end

    -- Find and set the dropdown state based on current multiplier
    if self.multiplierSelector then
        local stateIndex = 1  -- Default to 1x
        for i, mult in ipairs(DealDetailsDialog.MULTIPLIER_OPTIONS) do
            if math.abs(currentMultiplier - mult) < 0.01 then
                stateIndex = i
                break
            end
        end
        self.multiplierSelector:setState(stateIndex)
    end

    -- Update adjusted payment display
    if self.adjustedPaymentText then
        local adjustedPayment = basePayment * currentMultiplier
        self.adjustedPaymentText:setText(g_i18n:formatMoney(adjustedPayment, 0, true, true))
    end

    -- Calculate and display savings info
    self:updateSavingsDisplay()
end

--[[
    Update the savings display based on current multiplier
    Shows projected months to payoff and interest saved
]]
function DealDetailsDialog:updateSavingsDisplay()
    if self.deal == nil then return end

    local deal = self.deal
    local currentMultiplier = deal.paymentMultiplier or 1.0

    -- Show/hide savings row based on multiplier
    local showSavings = currentMultiplier > 1.0
    if self.savingsRow then
        self.savingsRow:setVisible(showSavings)
    end

    if not showSavings then return end

    -- Calculate savings using the deal's method
    if deal.calculateMultiplierSavings then
        local projectedMonths, normalInterest, multipliedInterest, interestSaved = deal:calculateMultiplierSavings()

        -- Update projected months display
        if self.projectedMonthsText then
            if projectedMonths > 0 then
                local years = math.floor(projectedMonths / 12)
                local months = projectedMonths % 12
                local timeStr
                if years > 0 and months > 0 then
                    timeStr = string.format("%dy %dm", years, months)
                elseif years > 0 then
                    timeStr = string.format("%d year%s", years, years == 1 and "" or "s")
                else
                    timeStr = string.format("%d month%s", months, months == 1 and "" or "s")
                end
                self.projectedMonthsText:setText(timeStr)
            else
                self.projectedMonthsText:setText(g_i18n:getText("usedplus_dealdetails_paidOff"))
            end
        end

        -- Update interest saved display
        if self.interestSavedText then
            if interestSaved > 0 then
                self.interestSavedText:setText(g_i18n:formatMoney(interestSaved, 0, true, true))
                self.interestSavedText:setTextColor(0.2, 1, 0.4, 1)  -- Bright green
            else
                self.interestSavedText:setText(g_i18n:formatMoney(0, 0, true, true))
                self.interestSavedText:setTextColor(0.6, 0.6, 0.6, 1)  -- Gray
            end
        end
    end
end

--[[
    Handle multiplier dropdown change
    Called when player selects a different multiplier
]]
function DealDetailsDialog:onMultiplierChanged()
    if self.deal == nil or self.multiplierSelector == nil then return end

    local deal = self.deal
    local stateIndex = self.multiplierSelector:getState()
    local newMultiplier = DealDetailsDialog.MULTIPLIER_OPTIONS[stateIndex] or 1.0

    -- Handle vanilla loan multiplier specially - store in FinanceManager
    if deal.isVanillaLoan then
        local farmId = deal.farmId or g_currentMission:getFarmId()
        if g_financeManager then
            g_financeManager:setVanillaLoanMultiplier(farmId, newMultiplier)
        end

        -- Update display
        if self.adjustedPaymentText then
            local basePayment = deal.monthlyPayment or 0
            local adjustedPayment = basePayment * newMultiplier
            self.adjustedPaymentText:setText(g_i18n:formatMoney(adjustedPayment, 0, true, true))
        end

        -- Update savings display
        self:updateSavingsDisplay()

        -- Show notification for vanilla loan
        local notificationText
        if newMultiplier > 1.0 then
            local extraPercent = math.floor((newMultiplier - 1.0) * 100)
            notificationText = string.format(
                "Bank loan payment: %s (+%d%% extra toward principal)",
                DealDetailsDialog.MULTIPLIER_TEXTS[stateIndex],
                extraPercent
            )
        else
            notificationText = "Bank loan payment: Standard (interest only)"
        end
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationText)
        return
    end

    -- Regular UsedPlus deal - update the deal's multiplier
    if deal.setPaymentMultiplier then
        deal:setPaymentMultiplier(newMultiplier)
    else
        deal.paymentMultiplier = newMultiplier
    end

    -- Update display
    if self.adjustedPaymentText then
        local basePayment = deal.monthlyPayment or 0
        local adjustedPayment = basePayment * newMultiplier
        self.adjustedPaymentText:setText(g_i18n:formatMoney(adjustedPayment, 0, true, true))
    end

    -- Update savings display
    self:updateSavingsDisplay()

    -- Send network event to sync in multiplayer (only for real UsedPlus deals)
    if SetPaymentConfigEvent then
        local paymentMode = deal.paymentMode or 2  -- Default to STANDARD
        local customAmount = deal.configuredPayment or 0
        SetPaymentConfigEvent.sendToServer(deal.id, paymentMode, customAmount, newMultiplier)
    end

    -- Show notification with savings info if applicable
    local notificationText = string.format("Payment set to %s (%.0f%% of base)",
        DealDetailsDialog.MULTIPLIER_TEXTS[stateIndex],
        newMultiplier * 100)

    if newMultiplier > 1.0 and deal.calculateMultiplierSavings then
        local projectedMonths, _, _, interestSaved = deal:calculateMultiplierSavings()
        if interestSaved > 0 then
            notificationText = notificationText .. string.format("\nSave %s in interest!",
                g_i18n:formatMoney(interestSaved, 0, true, true))
        end
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationText)
end

--[[
    Handle early payoff button click
]]
function DealDetailsDialog:onEarlyPayoff()
    if self.deal == nil then return end

    local deal = self.deal
    local isLease = (deal.dealType == 2) or (deal.itemType == "lease")
    local payoffAmount = deal.currentBalance or 0
    if deal.accruedInterest then
        payoffAmount = payoffAmount + deal.accruedInterest
    end

    local actionText = isLease and "buyout" or "pay off"
    local message = string.format("Are you sure you want to %s this %s for %s?",
        actionText,
        isLease and "lease" or "loan",
        g_i18n:formatMoney(payoffAmount, 0, true, true))

    -- Use YesNoDialog.show() - correct FS25 pattern
    -- Signature: YesNoDialog.show(callback, target, text, title, yesText, noText)
    local title = isLease and "Buyout Lease" or "Early Payoff"
    YesNoDialog.show(
        self.onPayoffConfirm,
        self,
        message,
        title
    )
end

--[[
    Callback for payoff confirmation dialog
]]
function DealDetailsDialog:onPayoffConfirm(yes)
    if yes then
        self:executePayoff()
    end
end

--[[
    Execute early payoff
]]
function DealDetailsDialog:executePayoff()
    if self.deal == nil then return end

    local deal = self.deal
    local payoffAmount = deal.currentBalance or 0
    if deal.accruedInterest then
        payoffAmount = payoffAmount + deal.accruedInterest
    end

    local farmId = g_currentMission:getFarmId()

    -- Deduct funds
    g_currentMission:addMoney(-payoffAmount, farmId, MoneyType.OTHER, true, true)

    -- Mark deal as paid off
    deal.status = "paid_off"
    deal.currentBalance = 0
    deal.accruedInterest = 0

    -- Track statistics
    g_financeManager:incrementStatistic(farmId, "dealsCompleted", 1)
    if deal.totalInterestPaid then
        g_financeManager:incrementStatistic(farmId, "totalInterestPaid", deal.totalInterestPaid)
    end

    -- Record credit event
    if CreditHistory then
        CreditHistory.recordEvent(farmId, "DEAL_PAID_OFF", deal.itemName or "Unknown")
    end

    -- Remove from active deals
    g_financeManager:removeDeal(deal.id)

    -- Show notification
    local isLease = (deal.dealType == 2) or (deal.itemType == "lease")
    local notificationText = isLease and
        string.format("Lease for %s bought out!", deal.itemName) or
        string.format("Loan for %s paid off!", deal.itemName)

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationText)

    -- Store callback before closing (dialog close clears it)
    local refreshCallback = self.onCloseCallback

    -- Close dialog (ScreenElement doesn't have close(), use g_gui)
    g_gui:closeDialogByName("DealDetailsDialog")

    -- Refresh the finance manager frame using multiple fallback methods
    -- Method 1: Use the stored callback (passed from FinanceManagerFrame)
    if refreshCallback then
        refreshCallback()
    -- Method 2: Use static refresh method
    elseif FinanceManagerFrame and FinanceManagerFrame.refresh then
        FinanceManagerFrame.refresh()
    -- Method 3: Fallback to global reference
    elseif g_usedPlusFinanceFrame and g_usedPlusFinanceFrame.updateDisplay then
        g_usedPlusFinanceFrame:updateDisplay()
    end
end

--[[
    Handle close button click
]]
function DealDetailsDialog:onCloseDialog()
    g_gui:closeDialogByName("DealDetailsDialog")
end

--[[
    Handle ESC key / back button
]]
function DealDetailsDialog:onClickBack()
    g_gui:closeDialogByName("DealDetailsDialog")
end

--[[
    Handle input events (ESC key for ScreenElement)
]]
function DealDetailsDialog:inputEvent(action, value, eventUsed)
    eventUsed = DealDetailsDialog:superClass().inputEvent(self, action, value, eventUsed)

    if not eventUsed and action == InputAction.MENU_BACK and value > 0 then
        g_gui:closeDialogByName("DealDetailsDialog")
        eventUsed = true
    end

    return eventUsed
end

--[[
    Called when dialog closes
]]
function DealDetailsDialog:onClose()
    DealDetailsDialog:superClass().onClose(self)

    if self.onCloseCallback then
        self.onCloseCallback()
    end

    self.deal = nil
    self.onCloseCallback = nil
end

--[[
    Update section visibility based on deal status
    When defaulted, hide multiplier/payoff sections and show repossessed section
    @param isDefaulted - Whether the deal is defaulted
]]
function DealDetailsDialog:updateSectionVisibility(isDefaulted)
    -- Hide multiplier and payoff sections for defaulted deals
    if self.multiplierSection then
        self.multiplierSection:setVisible(not isDefaulted)
    end
    if self.payoffSection then
        self.payoffSection:setVisible(not isDefaulted)
    end

    -- Show repossessed section only for defaulted deals with repossessed items
    local hasRepossessedItems = self.deal and self.deal.repossessedItems and #self.deal.repossessedItems > 0
    if self.repossessedSection then
        self.repossessedSection:setVisible(isDefaulted and hasRepossessedItems)
    end

    -- Update repossessed items display if visible
    if isDefaulted and hasRepossessedItems then
        self:updateRepossessedItemsDisplay()
    end

    -- Disable payoff button for defaulted deals
    if self.payoffButton then
        self.payoffButton:setDisabled(isDefaulted)
    end
end

--[[
    Update the repossessed items display with data from the deal
    Shows up to 4 repossessed items with their names and values
]]
function DealDetailsDialog:updateRepossessedItemsDisplay()
    if self.deal == nil or self.deal.repossessedItems == nil then
        return
    end

    local items = self.deal.repossessedItems
    local totalValue = 0

    -- Update each item text element (up to 4)
    for i = 1, 4 do
        local itemElement = self["repossessedItem" .. i]
        if itemElement then
            local item = items[i]
            if item then
                local itemText = string.format("• %s - %s",
                    item.name or "Unknown Vehicle",
                    g_i18n:formatMoney(item.value or 0, 0, true, true))
                itemElement:setText(itemText)
                itemElement:setVisible(true)
                totalValue = totalValue + (item.value or 0)
            else
                itemElement:setText("")
                itemElement:setVisible(false)
            end
        end
    end

    -- If there are more than 4 items, show count in last slot
    if #items > 4 then
        local remaining = #items - 3
        local itemElement = self.repossessedItem4
        if itemElement then
            itemElement:setText(string.format("...and %d more item(s)", remaining))
            itemElement:setVisible(true)
        end

        -- Calculate total for all items
        totalValue = 0
        for _, item in ipairs(items) do
            totalValue = totalValue + (item.value or 0)
        end
    end

    -- Update total value text
    if self.repossessedTotalText then
        self.repossessedTotalText:setText(string.format("Total value repossessed: %s",
            g_i18n:formatMoney(totalValue, 0, true, true)))
    end

    -- Update info text
    if self.repossessedInfoText then
        local infoText = string.format("The following %d item(s) were repossessed due to missed payments:",
            #items)
        self.repossessedInfoText:setText(infoText)
    end
end
