--[[
    FS25_UsedPlus - Finance Events (Consolidated)

    Network events for financing operations:
    - FinanceVehicleEvent: Finance a vehicle/land/placeable
    - FinancePaymentEvent: Make additional payment on a deal
    - TakeLoanEvent: Take out a general cash loan

    Pattern from: EnhancedLoanSystem, HirePurchasing network events
]]

--============================================================================
-- FINANCE VEHICLE EVENT
-- Network event for financing a vehicle/land
--============================================================================

FinanceVehicleEvent = {}
local FinanceVehicleEvent_mt = Class(FinanceVehicleEvent, Event)

InitEventClass(FinanceVehicleEvent, "FinanceVehicleEvent")

function FinanceVehicleEvent.emptyNew()
    local self = Event.new(FinanceVehicleEvent_mt)
    return self
end

function FinanceVehicleEvent.new(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations)
    local self = FinanceVehicleEvent.emptyNew()
    self.farmId = farmId
    self.itemType = itemType
    self.itemId = itemId
    self.itemName = itemName
    self.basePrice = basePrice
    self.downPayment = downPayment
    self.termYears = termYears
    self.cashBack = cashBack or 0
    self.configurations = configurations or {}
    return self
end

function FinanceVehicleEvent.sendToServer(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations)
    if g_server ~= nil then
        FinanceVehicleEvent.execute(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations)
    else
        g_client:getServerConnection():sendEvent(
            FinanceVehicleEvent.new(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations)
        )
    end
end

function FinanceVehicleEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
    streamWriteString(streamId, self.itemType)

    if self.itemType == "land" then
        streamWriteInt32(streamId, self.itemId)
    else
        streamWriteString(streamId, tostring(self.itemId))
    end

    streamWriteString(streamId, self.itemName)
    streamWriteFloat32(streamId, self.basePrice)
    streamWriteFloat32(streamId, self.downPayment)
    streamWriteInt32(streamId, self.termYears)
    streamWriteFloat32(streamId, self.cashBack)

    local configCount = 0
    for _ in pairs(self.configurations) do
        configCount = configCount + 1
    end

    streamWriteInt32(streamId, configCount)
    for configKey, configValue in pairs(self.configurations) do
        streamWriteString(streamId, tostring(configKey))
        streamWriteInt32(streamId, configValue)
    end
end

function FinanceVehicleEvent:readStream(streamId, connection)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self.itemType = streamReadString(streamId)

    if self.itemType == "land" then
        self.itemId = streamReadInt32(streamId)
    else
        self.itemId = streamReadString(streamId)
    end

    self.itemName = streamReadString(streamId)
    self.basePrice = streamReadFloat32(streamId)
    self.downPayment = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)
    self.cashBack = streamReadFloat32(streamId)

    self.configurations = {}
    local configCount = streamReadInt32(streamId)
    for i = 1, configCount do
        local configKey = streamReadString(streamId)
        local configValue = streamReadInt32(streamId)
        self.configurations[configKey] = configValue
    end

    self:run(connection)
end

function FinanceVehicleEvent.execute(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations)
    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        return
    end

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", farmId))
        return
    end

    local netCost = downPayment - cashBack
    if farm.money < netCost then
        UsedPlus.logError(string.format("Insufficient funds for down payment ($%.2f required, $%.2f available)",
            netCost, farm.money))
        return
    end

    local deal = g_financeManager:createFinanceDeal(
        farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations or {}
    )

    if deal then
        UsedPlus.logDebug(string.format("Finance deal created successfully: %s (ID: %s)", itemName, deal.id))
    else
        UsedPlus.logError(string.format("Failed to create finance deal for %s", itemName))
    end
end

function FinanceVehicleEvent:run(connection)
    if not connection:getIsServer() then
        UsedPlus.logError("FinanceVehicleEvent must run on server")
        return
    end

    FinanceVehicleEvent.execute(
        self.farmId, self.itemType, self.itemId, self.itemName,
        self.basePrice, self.downPayment, self.termYears, self.cashBack, self.configurations
    )
end

--============================================================================
-- FINANCE PAYMENT EVENT
-- Network event for making additional payment on finance/lease deal
--============================================================================

FinancePaymentEvent = {}
local FinancePaymentEvent_mt = Class(FinancePaymentEvent, Event)

InitEventClass(FinancePaymentEvent, "FinancePaymentEvent")

function FinancePaymentEvent.emptyNew()
    local self = Event.new(FinancePaymentEvent_mt)
    return self
end

function FinancePaymentEvent.new(dealId, paymentAmount, farmId)
    local self = FinancePaymentEvent.emptyNew()
    self.dealId = dealId
    self.paymentAmount = paymentAmount
    self.farmId = farmId
    return self
end

function FinancePaymentEvent:sendToServer(dealId, paymentAmount, farmId)
    if g_server ~= nil then
        self:run(g_server:getServerConnection())
    else
        g_client:getServerConnection():sendEvent(
            FinancePaymentEvent.new(dealId, paymentAmount, farmId)
        )
    end
end

function FinancePaymentEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteFloat32(streamId, self.paymentAmount)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
end

function FinancePaymentEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.paymentAmount = streamReadFloat32(streamId)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self:run(connection)
end

function FinancePaymentEvent:run(connection)
    if not connection:getIsServer() then
        UsedPlus.logError("FinancePaymentEvent must run on server")
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", self.dealId))
        return
    end

    if deal.farmId ~= self.farmId then
        UsedPlus.logError(string.format("Farm %d does not own deal %s", self.farmId, self.dealId))
        return
    end

    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        return
    end

    if farm.money < self.paymentAmount then
        UsedPlus.logError(string.format("Insufficient funds for payment ($%.2f required, $%.2f available)",
            self.paymentAmount, farm.money))
        return
    end

    if self.paymentAmount <= 0 then
        UsedPlus.logError(string.format("Invalid payment amount: $%.2f", self.paymentAmount))
        return
    end

    local payoffAmount = deal.currentBalance

    if self.paymentAmount >= payoffAmount then
        -- Full payoff
        local penalty = deal:calculatePrepaymentPenalty()
        local totalCost = payoffAmount + penalty

        if farm.money < totalCost then
            UsedPlus.logError(string.format("Insufficient funds for payoff with penalty ($%.2f required)", totalCost))
            return
        end

        g_currentMission:addMoneyChange(-totalCost, self.farmId, MoneyType.OTHER, true)

        deal.status = "completed"
        deal.currentBalance = 0

        g_financeManager.deals[deal.id] = nil
        local farmDeals = g_financeManager.dealsByFarm[deal.farmId]
        if farmDeals then
            for i, d in ipairs(farmDeals) do
                if d.id == deal.id then
                    table.remove(farmDeals, i)
                    break
                end
            end
        end

        UsedPlus.logDebug(string.format("Deal %s paid off: $%.2f (penalty: $%.2f)", deal.id, payoffAmount, penalty))

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_dealPaidOff"), deal.itemName)
        )
    else
        -- Partial payment
        local interestPortion = (deal.interestRate / 12) * deal.currentBalance
        local principalPortion = self.paymentAmount - interestPortion

        g_currentMission:addMoneyChange(-self.paymentAmount, self.farmId, MoneyType.OTHER, true)

        deal.currentBalance = deal.currentBalance - principalPortion
        deal.totalInterestPaid = deal.totalInterestPaid + interestPortion

        UsedPlus.logDebug(string.format("Payment processed for %s: $%.2f (principal: $%.2f, interest: $%.2f)",
            deal.id, self.paymentAmount, principalPortion, interestPortion))

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_paymentProcessed"), g_i18n:formatMoney(self.paymentAmount), deal.itemName)
        )
    end
end

--============================================================================
-- TAKE LOAN EVENT
-- Network event for taking out a general cash loan
--============================================================================

TakeLoanEvent = {}
local TakeLoanEvent_mt = Class(TakeLoanEvent, Event)

InitEventClass(TakeLoanEvent, "TakeLoanEvent")

function TakeLoanEvent.emptyNew()
    local self = Event.new(TakeLoanEvent_mt)
    return self
end

function TakeLoanEvent.new(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    local self = TakeLoanEvent.emptyNew()
    self.farmId = farmId
    self.loanAmount = loanAmount
    self.termYears = termYears
    self.interestRate = interestRate
    self.monthlyPayment = monthlyPayment
    self.collateralItems = collateralItems or {}
    return self
end

function TakeLoanEvent.sendToServer(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    if g_server ~= nil then
        TakeLoanEvent.execute(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    else
        g_client:getServerConnection():sendEvent(
            TakeLoanEvent.new(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
        )
    end
end

function TakeLoanEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.loanAmount)
    streamWriteInt32(streamId, self.termYears)
    streamWriteFloat32(streamId, self.interestRate)
    streamWriteFloat32(streamId, self.monthlyPayment)

    -- Serialize collateral items array
    local collateralCount = #self.collateralItems
    streamWriteInt32(streamId, collateralCount)

    for _, item in ipairs(self.collateralItems) do
        streamWriteString(streamId, item.vehicleId or "")
        streamWriteInt32(streamId, item.objectId or 0)
        streamWriteString(streamId, item.configFile or "")
        streamWriteString(streamId, item.name or "")
        streamWriteFloat32(streamId, item.value or 0)
    end
end

function TakeLoanEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.loanAmount = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)
    self.interestRate = streamReadFloat32(streamId)
    self.monthlyPayment = streamReadFloat32(streamId)

    -- Deserialize collateral items array
    self.collateralItems = {}
    local collateralCount = streamReadInt32(streamId)

    for i = 1, collateralCount do
        local item = {
            vehicleId = streamReadString(streamId),
            objectId = streamReadInt32(streamId),
            configFile = streamReadString(streamId),
            name = streamReadString(streamId),
            value = streamReadFloat32(streamId),
            farmId = self.farmId  -- Use event's farmId
        }
        table.insert(self.collateralItems, item)
    end

    self:run(connection)
end

function TakeLoanEvent.execute(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    collateralItems = collateralItems or {}

    UsedPlus.logDebug(string.format("TakeLoanEvent.execute: farmId=%d, amount=$%.0f, term=%d years, collateral=%d items",
        farmId, loanAmount, termYears, #collateralItems))

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("TakeLoanEvent - Farm %d not found", farmId))
        return false
    end

    if loanAmount <= 0 then
        UsedPlus.logError("TakeLoanEvent - Invalid loan amount")
        return false
    end

    if termYears < 1 or termYears > 30 then
        UsedPlus.logError(string.format("TakeLoanEvent - Invalid term: %d years", termYears))
        return false
    end

    local timeComponent = 0
    if g_currentMission and g_currentMission.time then
        timeComponent = math.floor(g_currentMission.time)
    else
        timeComponent = math.random(100000, 999999)
    end
    local loanId = string.format("LOAN_%d_%d", farmId, timeComponent)

    if g_financeManager then
        local termMonths = termYears * 12
        local interestRatePercent = interestRate * 100

        local deal = FinanceDeal.new(
            farmId, "loan", loanId, "Cash Loan", loanAmount, 0,
            termMonths, interestRatePercent, 0
        )

        if deal then
            deal.monthlyPayment = monthlyPayment
            deal.currentBalance = loanAmount
            deal.amountFinanced = loanAmount

            -- Store collateral items for this loan
            deal.collateralItems = collateralItems
            if #collateralItems > 0 then
                local collateralValue = 0
                for _, item in ipairs(collateralItems) do
                    collateralValue = collateralValue + (item.value or 0)
                end
                UsedPlus.logDebug(string.format("Collateral pledged: %d vehicles worth $%d",
                    #collateralItems, collateralValue))
            end

            g_financeManager:registerDeal(deal)
            g_currentMission:addMoney(loanAmount, farmId, MoneyType.OTHER, true, true)

            -- Sync to vanilla farm.loan so it appears on vanilla Finances page
            -- Note: This may cause vanilla to charge additional interest, but ensures visibility
            farm.loan = (farm.loan or 0) + loanAmount
            UsedPlus.logDebug(string.format("Updated farm.loan to $%.0f (added $%.0f)", farm.loan, loanAmount))

            UsedPlus.logDebug(string.format("Loan created: $%d at %.2f%% for %d years (ID: %s)",
                loanAmount, interestRate * 100, termYears, deal.id))

            return true
        else
            UsedPlus.logError("Failed to create loan deal")
            return false
        end
    else
        UsedPlus.logError("FinanceManager not available")
        return false
    end
end

function TakeLoanEvent:run(connection)
    if not connection:getIsServer() then
        UsedPlus.logError("TakeLoanEvent must run on server")
        return
    end

    TakeLoanEvent.execute(self.farmId, self.loanAmount, self.termYears, self.interestRate, self.monthlyPayment, self.collateralItems)
end

--============================================================================

UsedPlus.logInfo("FinanceEvents loaded (FinanceVehicleEvent, FinancePaymentEvent, TakeLoanEvent)")
