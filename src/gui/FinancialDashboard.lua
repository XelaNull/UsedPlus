--[[
    FS25_UsedPlus - Financial Dashboard
     Comprehensive financial overview dialog
     Uses MessageDialog pattern for reliable display

    Features:
    - Credit score with trend indicator
    - Monthly obligations breakdown
    - Debt-to-asset ratio
    - Upcoming payments list
    - Lifetime statistics
]]

FinancialDashboard = {}
local FinancialDashboard_mt = Class(FinancialDashboard, MessageDialog)

--[[
     Constructor
]]
function FinancialDashboard.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or FinancialDashboard_mt)

    self.i18n = i18n or g_i18n

    -- Data
    self.farmId = nil
    self.creditScore = 650
    self.creditRating = "fair"
    self.assets = 0
    self.debt = 0

    return self
end

--[[
     Called when dialog opens
]]
function FinancialDashboard:onOpen()
    FinancialDashboard:superClass().onOpen(self)

    -- Get current farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm then
        self.farmId = farm.farmId
    end

    self:updateDashboard()
end

--[[
     Update all dashboard sections
]]
function FinancialDashboard:updateDashboard()
    if not self.farmId then
        return
    end

    local farm = g_farmManager:getFarmById(self.farmId)
    if not farm then
        return
    end

    self:updateCreditScoreSection(farm)
    self:updateObligationsSection(farm)
    self:updateDebtRatioSection(farm)
    self:updateUpcomingPayments(farm)
    self:updateStatistics(farm)
end

--[[
     Update credit score section with trend indicator
     Refactored to use UIHelper.Colors and UIHelper.Credit
]]
function FinancialDashboard:updateCreditScoreSection(farm)
    -- Calculate current credit score
    if CreditScore then
        self.creditScore = CreditScore.calculate(self.farmId)
        self.creditRating = CreditScore.getRating(self.creditScore)
    end

    -- Display score with color (UIHelper.Credit.getScoreColor uses numeric thresholds)
    UIHelper.Element.setTextWithColor(
        self.creditScoreValue,
        tostring(self.creditScore),
        UIHelper.Credit.getScoreColor(self.creditScore)
    )

    -- Display rating with range (dashboard-specific format)
    if self.creditScoreRating then
        local ratingTexts = {
            excellent = "Excellent (750-850)",
            good = "Good (670-749)",
            fair = "Fair (580-669)",
            poor = "Poor (300-579)",
        }
        UIHelper.Element.setText(self.creditScoreRating, ratingTexts[self.creditRating] or "Unknown")
    end

    -- Display trend based on history (nuanced 5-level trend)
    if self.creditScoreTrend and CreditHistory then
        local summary = CreditHistory.getSummary(self.farmId)
        local netChange = summary.netChange or 0
        local trendText, trendColor

        if netChange > 20 then
            trendText, trendColor = "Trending Up", UIHelper.Colors.TREND_UP
        elseif netChange > 0 then
            trendText, trendColor = "Slightly Up", UIHelper.Colors.CREDIT_GOOD
        elseif netChange < -20 then
            trendText, trendColor = "Trending Down", UIHelper.Colors.TREND_DOWN
        elseif netChange < 0 then
            trendText, trendColor = "Slightly Down", UIHelper.Colors.COST_ORANGE
        else
            trendText, trendColor = "Stable", UIHelper.Colors.TREND_STABLE
        end

        UIHelper.Element.setTextWithColor(self.creditScoreTrend, trendText, trendColor)
    end

    -- Display history adjustment
    if self.historyAdjustment and CreditHistory then
        local adjustment = CreditHistory.getScoreAdjustment(self.farmId)
        UIHelper.Element.setText(self.historyAdjustment, string.format("History: %+d points", adjustment))
    end
end

--[[
     Update monthly obligations breakdown
     Refactored to use UIHelper.Text.formatMoney
]]
function FinancialDashboard:updateObligationsSection(farm)
    local equipmentTotal = 0
    local landTotal = 0
    local loanTotal = 0

    -- Include vanilla game loans (farm.loan)
    -- Vanilla loans don't have fixed monthly payments, but we estimate interest obligation
    -- Vanilla uses ~10% annual interest, so monthly is ~0.83% of balance
    if farm.loan ~= nil and farm.loan > 0 then
        local vanillaMonthlyInterest = farm.loan * 0.0083  -- ~10% annual / 12 months
        loanTotal = loanTotal + vanillaMonthlyInterest
    end

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    local monthly = deal.monthlyPayment or 0

                    if deal.dealType == 1 then  -- Vehicle finance
                        equipmentTotal = equipmentTotal + monthly
                    elseif deal.dealType == 3 then  -- Cash loan
                        loanTotal = loanTotal + monthly
                    elseif deal.dealType == 4 or deal.itemType == "land" then  -- Land finance
                        landTotal = landTotal + monthly
                    else
                        equipmentTotal = equipmentTotal + monthly
                    end
                end
            end
        end
    end

    local total = equipmentTotal + landTotal + loanTotal

    -- Display monthly obligations with /mo suffix
    UIHelper.Element.setText(self.equipmentObligations, UIHelper.Text.formatMoney(equipmentTotal) .. "/mo")
    UIHelper.Element.setText(self.landObligations, UIHelper.Text.formatMoney(landTotal) .. "/mo")
    UIHelper.Element.setText(self.loanObligations, UIHelper.Text.formatMoney(loanTotal) .. "/mo")
    UIHelper.Element.setText(self.totalObligations, UIHelper.Text.formatMoney(total) .. "/mo")
end

--[[
     Update debt-to-asset ratio section
     Refactored to use UIHelper.Finance and UIHelper.Colors
]]
function FinancialDashboard:updateDebtRatioSection(farm)
    if CreditScore then
        self.assets = CreditScore.calculateAssets(farm)
        self.debt = CreditScore.calculateDebt(farm)
    end

    local ratio = 0
    if self.assets > 0 then
        ratio = self.debt / self.assets
    end

    -- Display assets (green) and debt (red) with semantic colors
    UIHelper.Finance.displayAssetValue(self.totalAssets, self.assets)
    UIHelper.Finance.displayDebt(self.totalDebt, self.debt)

    -- Display ratio percentage
    UIHelper.Element.setText(self.debtRatioValue, UIHelper.Text.formatPercent(ratio, true, 1))

    -- Status text with color (5-tier rating)
    if self.debtRatioStatus then
        local statusText, statusColor

        if ratio < 0.2 then
            statusText, statusColor = "Excellent", UIHelper.Colors.CREDIT_EXCELLENT
        elseif ratio < 0.4 then
            statusText, statusColor = "Good", UIHelper.Colors.CREDIT_GOOD
        elseif ratio < 0.6 then
            statusText, statusColor = "Fair", UIHelper.Colors.CREDIT_FAIR
        elseif ratio < 0.8 then
            statusText, statusColor = "High", UIHelper.Colors.COST_ORANGE
        else
            statusText, statusColor = "Critical", UIHelper.Colors.CREDIT_POOR
        end

        UIHelper.Element.setTextWithColor(self.debtRatioStatus, statusText, statusColor)
    end
end

--[[
     Update upcoming payments using simple row elements
     Refactored to use UIHelper.Element for safe element access
]]
function FinancialDashboard:updateUpcomingPayments(farm)
    local payments = {}

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    table.insert(payments, {
                        name = deal.itemName or "Unknown",
                        amount = deal.monthlyPayment or 0,
                    })
                end
            end
        end
    end

    -- Sort by amount (highest first)
    table.sort(payments, function(a, b)
        return a.amount > b.amount
    end)

    -- Show/hide "no payments" text
    UIHelper.Element.setVisible(self.noPaymentsText, #payments == 0)

    -- Update payment rows (up to 5)
    for i = 0, 4 do
        local nameElement = self["paymentName" .. i]
        local amountElement = self["paymentAmount" .. i]
        local rowElement = self["payment" .. i]

        if rowElement then
            if i < #payments then
                local payment = payments[i + 1]
                local displayName = payment.name
                if #displayName > 30 then
                    displayName = string.sub(displayName, 1, 28) .. ".."
                end

                UIHelper.Element.setText(nameElement, displayName)
                UIHelper.Element.setText(amountElement, UIHelper.Text.formatMoney(payment.amount))
                rowElement:setVisible(true)
            else
                rowElement:setVisible(false)
            end
        end
    end
end

--[[
     Update lifetime statistics
     Refactored to use UIHelper for formatting and colors
]]
function FinancialDashboard:updateStatistics(farm)
    local lifetimeFinancedTotal = 0
    local lifetimeInterestTotal = 0
    local completedDeals = 0

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                lifetimeFinancedTotal = lifetimeFinancedTotal + (deal.amountFinanced or deal.price or 0)
                lifetimeInterestTotal = lifetimeInterestTotal + (deal.totalInterestPaid or 0)

                if deal.status == "paid_off" or deal.status == "paid" then
                    completedDeals = completedDeals + 1
                end
            end
        end
    end

    -- Credit history summary
    local onTime = 0
    local missed = 0
    if CreditHistory then
        local summary = CreditHistory.getSummary(self.farmId)
        onTime = summary.paymentsOnTime or 0
        missed = summary.paymentsMissed or 0
        completedDeals = completedDeals + (summary.dealsCompleted or 0)
    end

    -- Display lifetime totals
    UIHelper.Element.setText(self.lifetimeFinanced, UIHelper.Text.formatMoney(lifetimeFinancedTotal))
    UIHelper.Element.setTextWithColor(self.lifetimeInterest, UIHelper.Text.formatMoney(lifetimeInterestTotal), UIHelper.Colors.COST_ORANGE)

    -- Display counts
    UIHelper.Element.setText(self.dealsCompleted, tostring(completedDeals))
    UIHelper.Element.setTextWithColor(self.onTimePayments, tostring(onTime), UIHelper.Colors.MONEY_GREEN)

    -- Missed payments: red if any, green if none
    local missedColor = missed > 0 and UIHelper.Colors.CREDIT_POOR or UIHelper.Colors.CREDIT_EXCELLENT
    UIHelper.Element.setTextWithColor(self.missedPayments, tostring(missed), missedColor)
end

--[[
     Handle Take Loan button click
     Refactored to use DialogLoader for centralized loading
]]
function FinancialDashboard:onTakeLoanClick()
    -- Close this dialog first
    self:close()

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("TakeLoanDialog", "setFarmId", self.farmId)
end

--[[
     Handle Close button click
     MUST use different name than onClose - that's the system lifecycle callback!
]]
function FinancialDashboard:onCloseButtonClick()
    self:close()
end

UsedPlus.logInfo("FinancialDashboard loaded")
