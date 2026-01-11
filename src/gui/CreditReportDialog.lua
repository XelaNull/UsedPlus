--[[
    FS25_UsedPlus - Credit Report Dialog
    Official credit report styled dialog showing:
    - Credit score with factors breakdown
    - Account history (open and closed)
    - Payment performance metrics
    - Score trend over time

    Styled to look like an official credit bureau report
]]

CreditReportDialog = {}
local CreditReportDialog_mt = Class(CreditReportDialog, MessageDialog)

--[[
     Constructor
]]
function CreditReportDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or CreditReportDialog_mt)
    self.i18n = i18n or g_i18n
    return self
end

--[[
    v2.0.0: Helper function to check if credit system is enabled
]]
function CreditReportDialog.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true  -- Default to enabled
end

--[[
     Called when dialog opens
]]
function CreditReportDialog:onOpen()
    CreditReportDialog:superClass().onOpen(self)

    -- v2.0.0: Check if credit system is enabled
    local creditEnabled = CreditReportDialog.isCreditSystemEnabled()

    -- Toggle visibility between credit content and disabled message
    if self.creditContentContainer then
        self.creditContentContainer:setVisible(creditEnabled)
    end
    if self.disabledMessageContainer then
        self.disabledMessageContainer:setVisible(not creditEnabled)
    end

    -- If disabled, no need to update report content
    if not creditEnabled then
        return
    end

    -- Get current farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm then
        self.farmId = farm.farmId
        self.farm = farm
    end

    self:updateReport()
end

--[[
     Update all report sections
]]
function CreditReportDialog:updateReport()
    if not self.farmId or not self.farm then
        return
    end

    self:updateHeader()
    self:updateScoreSection()
    self:updateFactorsSection()
    self:updateAccountsSection()
    self:updateActiveAccountsSection()
    self:updatePaymentHistorySection()
    self:updateTipsSection()
end

--[[
     Update report header with farm name and date
]]
function CreditReportDialog:updateHeader()
    -- Farm name
    if self.farmNameText then
        local farmName = self.farm.name or "Unknown Farm"
        self.farmNameText:setText(farmName)
    end

    -- Report date (current in-game date)
    if self.reportDateText then
        local currentDay = g_currentMission.environment.currentDay or 1
        local currentMonth = g_currentMission.environment.currentMonth or 1
        local currentYear = g_currentMission.environment.currentYear or 2025
        local dateStr = string.format("%02d/%02d/%d", currentMonth, currentDay, currentYear)
        self.reportDateText:setText("Report Date: " .. dateStr)
    end
end

--[[
     Update credit score section with large score display
]]
function CreditReportDialog:updateScoreSection()
    local score = 650
    local rating = "Fair"
    local interestAdj = 0

    if CreditScore then
        score = CreditScore.calculate(self.farmId)
        rating = CreditScore.getRating(score)
        interestAdj = CreditScore.getInterestAdjustment(score)
    end

    -- Large score display
    if self.scoreValueText then
        self.scoreValueText:setText(tostring(score))
        -- Color based on score
        local color = UIHelper.Credit.getScoreColor(score)
        self.scoreValueText:setTextColor(unpack(color))
    end

    -- Rating text
    if self.ratingText then
        self.ratingText:setText(rating)
    end

    -- Score range indicator (300-850)
    if self.scoreRangeText then
        self.scoreRangeText:setText("Score Range: 300-850")
    end

    -- Interest rate impact
    if self.interestImpactText then
        local impactStr
        if interestAdj < 0 then
            impactStr = string.format("%.1f%% discount on interest rates", -interestAdj)
        elseif interestAdj > 0 then
            impactStr = string.format("+%.1f%% on interest rates", interestAdj)
        else
            impactStr = "Standard interest rates apply"
        end
        self.interestImpactText:setText(impactStr)
    end

    -- Score trend
    self:updateScoreTrend()
end

--[[
     Update score trend based on PaymentTracker history
]]
function CreditReportDialog:updateScoreTrend()
    if not self.scoreTrendText then
        return
    end

    local trendText = "No History"
    local trendColor = {0.6, 0.6, 0.6, 1}

    if PaymentTracker then
        local stats = PaymentTracker.getStats(self.farmId)
        if stats and stats.totalPayments and stats.totalPayments > 0 then
            -- Calculate on-time rate from stats
            local onTimeRate = stats.onTimePayments / stats.totalPayments
            local streak = stats.currentStreak or 0

            if streak >= 6 and onTimeRate >= 0.95 then
                trendText = "▲▲ Excellent - Strong upward trend"
                trendColor = {0.2, 0.9, 0.3, 1}
            elseif streak >= 3 and onTimeRate >= 0.85 then
                trendText = "▲ Good - Positive momentum"
                trendColor = {0.5, 0.9, 0.4, 1}
            elseif onTimeRate >= 0.70 then
                trendText = "→ Stable - Maintaining"
                trendColor = {0.8, 0.8, 0.4, 1}
            elseif onTimeRate >= 0.50 then
                trendText = "▼ Declining - Needs attention"
                trendColor = {1, 0.6, 0.3, 1}
            else
                trendText = "▼▼ Poor - Immediate action needed"
                trendColor = {1, 0.3, 0.3, 1}
            end
        end
    end

    self.scoreTrendText:setText(trendText)
    self.scoreTrendText:setTextColor(unpack(trendColor))
end

--[[
     Update score factors section showing what affects the score
]]
function CreditReportDialog:updateFactorsSection()
    if not PaymentTracker then
        return
    end

    local stats = PaymentTracker.getStats(self.farmId)
    if not stats then
        return
    end

    -- Payment History factor (most important - 35%)
    if self.factorPaymentText then
        local paymentScore = "No history"
        local paymentColor = {0.6, 0.6, 0.6, 1}

        if stats.totalPayments and stats.totalPayments > 0 then
            local rate = stats.onTimePayments / stats.totalPayments
            if rate >= 0.95 then
                paymentScore = "Excellent (" .. math.floor(rate * 100) .. "% on-time)"
                paymentColor = {0.2, 0.9, 0.3, 1}
            elseif rate >= 0.85 then
                paymentScore = "Good (" .. math.floor(rate * 100) .. "% on-time)"
                paymentColor = {0.5, 0.9, 0.4, 1}
            elseif rate >= 0.70 then
                paymentScore = "Fair (" .. math.floor(rate * 100) .. "% on-time)"
                paymentColor = {0.8, 0.8, 0.4, 1}
            else
                paymentScore = "Poor (" .. math.floor(rate * 100) .. "% on-time)"
                paymentColor = {1, 0.4, 0.3, 1}
            end
        end

        self.factorPaymentText:setText(paymentScore)
        self.factorPaymentText:setTextColor(unpack(paymentColor))
    end

    -- Credit Utilization factor (30%)
    if self.factorUtilizationText and CreditScore then
        local assets = CreditScore.calculateAssets(self.farm)
        local debt = CreditScore.calculateDebt(self.farm)
        local ratio = assets > 0 and (debt / assets) or 0

        local utilScore = "N/A"
        local utilColor = {0.6, 0.6, 0.6, 1}

        if assets > 0 then
            if ratio <= 0.30 then
                utilScore = string.format("Excellent (%.0f%% utilized)", ratio * 100)
                utilColor = {0.2, 0.9, 0.3, 1}
            elseif ratio <= 0.50 then
                utilScore = string.format("Good (%.0f%% utilized)", ratio * 100)
                utilColor = {0.5, 0.9, 0.4, 1}
            elseif ratio <= 0.70 then
                utilScore = string.format("Fair (%.0f%% utilized)", ratio * 100)
                utilColor = {0.8, 0.8, 0.4, 1}
            else
                utilScore = string.format("High (%.0f%% utilized)", ratio * 100)
                utilColor = {1, 0.4, 0.3, 1}
            end
        end

        self.factorUtilizationText:setText(utilScore)
        self.factorUtilizationText:setTextColor(unpack(utilColor))
    end

    -- Account Age factor (15%)
    if self.factorAgeText then
        local totalPayments = stats.totalPayments or 0
        local ageScore = "New"
        local ageColor = {0.6, 0.6, 0.6, 1}

        if totalPayments >= 24 then
            ageScore = "Established (" .. totalPayments .. " payments)"
            ageColor = {0.2, 0.9, 0.3, 1}
        elseif totalPayments >= 12 then
            ageScore = "Building (" .. totalPayments .. " payments)"
            ageColor = {0.5, 0.9, 0.4, 1}
        elseif totalPayments >= 6 then
            ageScore = "Growing (" .. totalPayments .. " payments)"
            ageColor = {0.8, 0.8, 0.4, 1}
        elseif totalPayments > 0 then
            ageScore = "New (" .. totalPayments .. " payments)"
            ageColor = {0.7, 0.7, 0.7, 1}
        end

        self.factorAgeText:setText(ageScore)
        self.factorAgeText:setTextColor(unpack(ageColor))
    end
end

--[[
     Update accounts section showing open and closed accounts
]]
function CreditReportDialog:updateAccountsSection()
    local openCount = 0
    local closedCount = 0
    local totalBalance = 0

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    openCount = openCount + 1
                    totalBalance = totalBalance + (deal.currentBalance or 0)
                elseif deal.status == "completed" or deal.status == "paid_off" then
                    closedCount = closedCount + 1
                end
            end
        end
    end

    -- Open accounts
    if self.openAccountsText then
        self.openAccountsText:setText(tostring(openCount))
    end

    -- Closed accounts (good standing)
    if self.closedAccountsText then
        self.closedAccountsText:setText(tostring(closedCount))
    end

    -- Total outstanding balance
    if self.totalBalanceText then
        self.totalBalanceText:setText(g_i18n:formatMoney(totalBalance, 0, true, true))
    end
end

--[[
     Update active accounts detail section
     Shows up to 3 most recent active accounts with start dates
]]
function CreditReportDialog:updateActiveAccountsSection()
    local accounts = {}

    -- Collect all active accounts from finance manager
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    -- Determine deal type label
                    local typeLabel = "Loan"
                    if deal.dealType == DealUtils.TYPE.LEASE then
                        typeLabel = "Lease"
                    elseif deal.dealType == DealUtils.TYPE.FINANCE then
                        typeLabel = "Finance"
                    elseif deal.dealType == DealUtils.TYPE.LOAN then
                        typeLabel = "Cash Loan"
                    end

                    -- Get item name (truncate if too long)
                    local itemName = deal.itemName or deal.vehicleName or "Unknown"
                    if #itemName > 18 then
                        itemName = itemName:sub(1, 15) .. "..."
                    end

                    -- Format start date (Month/Year)
                    local month = deal.createdMonth or 1
                    local year = deal.createdYear or 2025
                    local startDate = string.format("%02d/%d", month, year)

                    -- Format balance
                    local balance = deal.currentBalance or 0

                    table.insert(accounts, {
                        name = itemName,
                        typeLabel = typeLabel,
                        startDate = startDate,
                        balance = balance,
                        createdYear = year,
                        createdMonth = month
                    })
                end
            end
        end
    end

    -- Sort by most recent first (newest first)
    table.sort(accounts, function(a, b)
        if a.createdYear ~= b.createdYear then
            return a.createdYear > b.createdYear
        end
        return a.createdMonth > b.createdMonth
    end)

    -- Populate account detail lines (up to 3)
    local accountLines = {self.accountLine1Text, self.accountLine2Text, self.accountLine3Text}

    for i, lineElement in ipairs(accountLines) do
        if lineElement then
            local account = accounts[i]
            if account then
                -- Format: "Item Name (Type) - MM/YYYY - $X"
                local lineText = string.format("%s (%s) - %s - %s",
                    account.name,
                    account.typeLabel,
                    account.startDate,
                    g_i18n:formatMoney(account.balance, 0, true, true))
                lineElement:setText(lineText)
                lineElement:setVisible(true)
            else
                lineElement:setText("No active accounts")
                lineElement:setVisible(i == 1 and #accounts == 0)  -- Only show "No accounts" on first line
            end
        end
    end
end

--[[
     Update payment history section with stats
]]
function CreditReportDialog:updatePaymentHistorySection()
    if not PaymentTracker then
        return
    end

    local stats = PaymentTracker.getStats(self.farmId)
    if not stats then
        -- No history yet
        if self.onTimePaymentsText then
            self.onTimePaymentsText:setText("0")
        end
        if self.missedPaymentsText then
            self.missedPaymentsText:setText("0")
        end
        if self.currentStreakText then
            self.currentStreakText:setText("N/A")
        end
        if self.longestStreakText then
            self.longestStreakText:setText("N/A")
        end
        return
    end

    -- On-time payments
    if self.onTimePaymentsText then
        self.onTimePaymentsText:setText(tostring(stats.onTimePayments or 0))
        self.onTimePaymentsText:setTextColor(0.3, 0.9, 0.3, 1)
    end

    -- Missed payments
    if self.missedPaymentsText then
        local missed = stats.missedPayments or 0
        self.missedPaymentsText:setText(tostring(missed))
        if missed > 0 then
            self.missedPaymentsText:setTextColor(1, 0.4, 0.3, 1)
        else
            self.missedPaymentsText:setTextColor(0.3, 0.9, 0.3, 1)
        end
    end

    -- Current streak
    if self.currentStreakText then
        local streak = stats.currentStreak or 0
        local streakText = streak > 0 and (streak .. " months") or "N/A"
        self.currentStreakText:setText(streakText)
        if streak >= 6 then
            self.currentStreakText:setTextColor(0.3, 0.9, 0.3, 1)
        elseif streak >= 3 then
            self.currentStreakText:setTextColor(0.7, 0.9, 0.3, 1)
        else
            self.currentStreakText:setTextColor(0.7, 0.7, 0.7, 1)
        end
    end

    -- Longest streak
    if self.longestStreakText then
        local longest = stats.longestStreak or 0
        local longestText = longest > 0 and (longest .. " months") or "N/A"
        self.longestStreakText:setText(longestText)
    end

    -- Payment histogram (simplified - show last 12 months as text)
    self:updatePaymentHistogram(stats)
end

--[[
     Update payment histogram display
     Shows a visual representation of payment breakdown
     Since we don't track individual payment dates, show proportional bars
]]
function CreditReportDialog:updatePaymentHistogram(stats)
    if not self.histogramText then
        return
    end

    local total = stats.totalPayments or 0
    local onTime = stats.onTimePayments or 0
    local missed = stats.missedPayments or 0
    local late = stats.latePayments or 0

    if total == 0 then
        self.histogramText:setText("No payment history yet")
        if self.histogramLegendText then
            self.histogramLegendText:setText("Start making payments to build your history")
        end
        return
    end

    -- Build proportional bar (12 characters total)
    local barLength = 12
    local onTimeCount = math.floor((onTime / total) * barLength + 0.5)
    local missedCount = math.floor((missed / total) * barLength + 0.5)
    local lateCount = barLength - onTimeCount - missedCount

    -- Ensure at least 1 char for each non-zero category
    if onTime > 0 and onTimeCount == 0 then onTimeCount = 1 end
    if missed > 0 and missedCount == 0 then missedCount = 1 end

    -- Build the bar: █ = on-time (green in display), ░ = missed
    local histogramStr = string.rep("█", onTimeCount) .. string.rep("▒", lateCount) .. string.rep("░", missedCount)

    self.histogramText:setText(histogramStr)

    -- Legend with actual counts
    if self.histogramLegendText then
        self.histogramLegendText:setText(string.format("█=%d on-time  ▒=%d late  ░=%d missed", onTime, late, missed))
    end
end

--[[
    Update tips section with context-sensitive credit improvement advice
    Tips are prioritized based on what will most improve the player's score
]]
function CreditReportDialog:updateTipsSection()
    local tips = {}

    -- Gather current credit status
    local score = 650
    local rating = "Fair"
    local assets = 0
    local debt = 0
    local debtRatio = 0
    local paymentStats = nil
    local openAccounts = 0
    local missedPayments = 0

    if CreditScore then
        score = CreditScore.calculate(self.farmId)
        rating = CreditScore.getRating(score)
        assets = CreditScore.calculateAssets(self.farm)
        debt = CreditScore.calculateDebt(self.farm)
        if assets > 0 then
            debtRatio = debt / assets
        end
    end

    if PaymentTracker then
        paymentStats = PaymentTracker.getStats(self.farmId)
        if paymentStats then
            missedPayments = paymentStats.missedPayments or 0
        end
    end

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    openAccounts = openAccounts + 1
                end
            end
        end
    end

    -- Priority 1: Address missed payments (biggest impact)
    if missedPayments > 0 then
        table.insert(tips, "PRIORITY: Avoid late payments - they hurt your score the most!")
    end

    -- Priority 2: High debt utilization
    if debtRatio > 0.70 then
        table.insert(tips, "Pay down debt - using >70% of credit hurts your score.")
    elseif debtRatio > 0.50 then
        table.insert(tips, "Try to keep debt below 50% of your assets for better rates.")
    end

    -- Based on score level
    if score < 600 then
        -- Very Poor score tips
        table.insert(tips, "Start small: finance one affordable vehicle to build history.")
        if missedPayments == 0 then
            table.insert(tips, "Make every payment on time for 6+ months to rebuild.")
        end
    elseif score < 650 then
        -- Poor score tips
        table.insert(tips, "Consistency is key - 6 on-time payments will boost your score.")
        if openAccounts == 0 then
            table.insert(tips, "Open a small finance deal to start building credit history.")
        end
    elseif score < 700 then
        -- Fair score tips
        if paymentStats and paymentStats.currentStreak and paymentStats.currentStreak < 6 then
            table.insert(tips, "Keep your current streak going - 6+ months helps a lot!")
        end
        table.insert(tips, "Mix account types (finance + lease) for a diverse credit mix.")
    elseif score < 750 then
        -- Good score tips
        table.insert(tips, "Excellent progress! Maintain current habits to reach 750+.")
        if debtRatio > 0.30 then
            table.insert(tips, "Paying down debt below 30% unlocks the best interest rates.")
        end
    else
        -- Excellent score tips
        table.insert(tips, "Outstanding credit! You qualify for the best rates available.")
        table.insert(tips, "Consider refinancing older loans at your new lower rate.")
    end

    -- Account age tip for new players
    if paymentStats == nil or (paymentStats.totalPayments or 0) < 6 then
        table.insert(tips, "Credit history takes time - keep making payments monthly.")
    end

    -- No accounts tip
    if openAccounts == 0 and debt == 0 then
        table.insert(tips, "No credit history yet - finance a vehicle to start building!")
    end

    -- Limit to 3 tips
    while #tips > 3 do
        table.remove(tips)
    end

    -- Pad with general tips if needed
    local generalTips = {
        "Pay bills on time - payment history is 35% of your score.",
        "Keep debt-to-asset ratio below 50% for better rates.",
        "Longer credit history = higher score. Be patient!",
        "Successfully completing loans improves your score.",
        "Finance used equipment for lower monthly payments."
    }

    local generalIndex = 1
    while #tips < 3 and generalIndex <= #generalTips do
        -- Don't add duplicates
        local isDuplicate = false
        for _, existingTip in ipairs(tips) do
            if existingTip == generalTips[generalIndex] then
                isDuplicate = true
                break
            end
        end
        if not isDuplicate then
            table.insert(tips, generalTips[generalIndex])
        end
        generalIndex = generalIndex + 1
    end

    -- Update UI elements
    if self.tipText1 then
        self.tipText1:setText(tips[1] or "")
    end
    if self.tipText2 then
        self.tipText2:setText(tips[2] or "")
    end
    if self.tipText3 then
        self.tipText3:setText(tips[3] or "")
    end
end

--[[
     Close button callback
]]
function CreditReportDialog:onClickBack()
    self:close()
end

UsedPlus.logInfo("CreditReportDialog loaded")
