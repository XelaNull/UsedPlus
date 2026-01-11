--[[
    FS25_UsedPlus - Finance Manager

    FinanceManager handles all finance and lease deals
    Pattern from: EnhancedLoanSystem "Manager Pattern"
    Reference: FS25_ADVANCED_PATTERNS.md - Manager Pattern section

    Responsibilities:
    - Track all active finance/lease deals across all farms
    - Process monthly payments (subscribe to PERIOD_CHANGED)
    - Create new deals (from network events)
    - Save/load deals to savegame
    - Generate unique deal IDs
    - Provide deal query methods

    This is a global singleton: g_financeManager
]]

FinanceManager = {}
local FinanceManager_mt = Class(FinanceManager)

--[[
    Constructor
    Creates manager instance with empty data structures
]]
function FinanceManager.new()
    local self = setmetatable({}, FinanceManager_mt)

    -- Data structures
    self.deals = {}  -- All deals indexed by ID
    self.dealsByFarm = {}  -- Deals grouped by farm ID for fast lookup

    -- Statistics tracking per farm
    self.statisticsByFarm = {}

    -- Vanilla bank loan multipliers per farm (bridges vanilla loan system with UsedPlus)
    -- Allows players to pay extra toward vanilla loan principal each month
    self.vanillaLoanMultipliers = {}

    -- ID generation
    self.nextDealId = 1

    -- Event subscriptions
    self.isServer = g_currentMission:getIsServer()
    self.isClient = g_currentMission:getIsClient()

    return self
end

--[[
    Get statistics for a farm, initializing defaults if needed
]]
function FinanceManager:getStatistics(farmId)
    if self.statisticsByFarm[farmId] == nil then
        self.statisticsByFarm[farmId] = {
            -- Used Vehicle Search statistics
            searchesStarted = 0,
            searchesSucceeded = 0,
            searchesFailed = 0,
            searchesCancelled = 0,
            totalSearchFees = 0,
            totalSavingsFromUsed = 0,  -- basePrice - usedPrice when purchasing used
            usedPurchases = 0,         -- Count of used vehicles purchased

            -- Vehicle Sale statistics
            salesListed = 0,
            salesCompleted = 0,
            salesCancelled = 0,
            totalSaleProceeds = 0,

            -- Finance deal statistics (lifetime, not just active)
            dealsCreated = 0,
            dealsCompleted = 0,
            totalAmountFinanced = 0,
            totalInterestPaid = 0
        }
    end
    return self.statisticsByFarm[farmId]
end

--[[
    Increment a statistic for a farm
    @param farmId - Farm ID
    @param statName - Name of statistic to increment
    @param amount - Amount to add (default 1)
]]
function FinanceManager:incrementStatistic(farmId, statName, amount)
    amount = amount or 1
    local stats = self:getStatistics(farmId)
    if stats[statName] ~= nil then
        stats[statName] = stats[statName] + amount
        UsedPlus.logTrace(string.format("Stat %s for farm %d: +%d = %d",
            statName, farmId, amount, stats[statName]))
    else
        UsedPlus.logWarn(string.format("Unknown statistic: %s", statName))
    end
end

--[[
    Get a specific statistic value
    @param farmId - Farm ID
    @param statName - Name of statistic
    @return value or 0 if not found
]]
function FinanceManager:getStatistic(farmId, statName)
    local stats = self:getStatistics(farmId)
    return stats[statName] or 0
end

--[[
    Get vanilla loan payment multiplier for a farm
    @param farmId - Farm ID
    @return multiplier value (defaults to 1.0)
]]
function FinanceManager:getVanillaLoanMultiplier(farmId)
    return self.vanillaLoanMultipliers[farmId] or 1.0
end

--[[
    Set vanilla loan payment multiplier for a farm
    When > 1.0, extra payment goes toward principal each month
    @param farmId - Farm ID
    @param multiplier - Payment multiplier (1.0 to 5.0)
]]
function FinanceManager:setVanillaLoanMultiplier(farmId, multiplier)
    if multiplier and multiplier >= 1.0 and multiplier <= 5.0 then
        self.vanillaLoanMultipliers[farmId] = multiplier
        UsedPlus.logDebug(string.format("Set vanilla loan multiplier for farm %d to %.1fx", farmId, multiplier))
    end
end

--[[
    Initialize manager after mission loads
    Subscribe to game events
]]
function FinanceManager:loadMapFinished()
    if self.isServer then
        -- Subscribe to monthly period change for payment processing
        -- Pattern from: EnhancedLoanSystem period-based calculations
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)

        UsedPlus.logDebug("FinanceManager subscribed to PERIOD_CHANGED")
    end
end

--[[
    Monthly payment processing
    Called automatically when in-game month changes
    Pattern from: EnhancedLoanSystem automatic payment collection
]]
function FinanceManager:onPeriodChanged()
    if not self.isServer then return end

    UsedPlus.logDebug("Processing monthly payments for all farms")

    -- Process payments for each farm
    for farmId, deals in pairs(self.dealsByFarm) do
        self:processMonthlyPaymentsForFarm(farmId, deals)
    end

    -- Process vanilla bank loan extra payments (bridges vanilla loan system)
    self:processVanillaLoanExtraPayments()
end

--[[
    Process extra payments for vanilla bank loans
    When a player sets a multiplier > 1.0 on the vanilla loan, we pay the extra toward principal.
    The vanilla game handles its normal interest payment - we just add the principal acceleration.
]]
function FinanceManager:processVanillaLoanExtraPayments()
    local vanillaInterestRate = 0.10  -- Vanilla uses ~10% APY

    -- Process for each farm that has a vanilla loan multiplier set
    for farmId, multiplier in pairs(self.vanillaLoanMultipliers) do
        if multiplier > 1.0 then
            local farm = g_farmManager:getFarmById(farmId)
            if farm and farm.loan and farm.loan > 0 then
                -- Calculate what vanilla's monthly interest cost would be
                local monthlyInterestCost = farm.loan * vanillaInterestRate / 12

                -- Calculate extra payment based on multiplier
                -- Extra = monthlyInterest * (multiplier - 1.0)
                local extraPayment = math.floor(monthlyInterestCost * (multiplier - 1.0))

                -- Don't pay more than the remaining balance
                extraPayment = math.min(extraPayment, farm.loan)

                -- Check if player can afford the extra payment
                if farm.money >= extraPayment and extraPayment > 0 then
                    -- Deduct from player's account
                    g_currentMission:addMoney(-extraPayment, farmId, MoneyType.OTHER, true, true)

                    -- Reduce loan principal
                    local oldBalance = farm.loan
                    farm.loan = farm.loan - extraPayment

                    UsedPlus.logDebug(string.format(
                        "Vanilla loan extra payment: Farm %d paid %d toward principal (%.1fx). Balance: %d -> %d",
                        farmId, extraPayment, multiplier, oldBalance, farm.loan
                    ))

                    -- Notify player if loan is now paid off
                    if farm.loan <= 0 then
                        farm.loan = 0
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_OK,
                            g_i18n:getText("usedplus_notification_vanillaLoanPaidOff") or "Bank loan paid off!"
                        )
                        -- Clear multiplier since loan is gone
                        self.vanillaLoanMultipliers[farmId] = nil
                    end
                else
                    UsedPlus.logDebug(string.format(
                        "Vanilla loan extra payment skipped: Farm %d has insufficient funds (%d needed, %d available)",
                        farmId, extraPayment, farm.money or 0
                    ))
                end
            end
        end
    end
end

--[[
    Process monthly payments for a single farm
    Iterate backwards to safely remove completed deals
    Special handling for leases: show renewal dialog instead of auto-removing
]]
function FinanceManager:processMonthlyPaymentsForFarm(farmId, deals)
    local farm = g_farmManager:getFarmById(farmId)

    if farm == nil then
        UsedPlus.logWarn(string.format("Farm %d not found for payment processing", farmId))
        return
    end

    -- Iterate backwards for safe removal
    for i = #deals, 1, -1 do
        local deal = deals[i]

        -- Handle defaulted deals (seized/repossessed) - remove from tracking
        if deal.status == "defaulted" then
            UsedPlus.logDebug(string.format("Removing defaulted deal %s: %s", deal.id, deal.itemName))
            table.remove(deals, i)
            self.deals[deal.id] = nil

        -- Handle expired deals (land leases that ran their term) - remove from tracking
        elseif deal.status == "expired" then
            UsedPlus.logDebug(string.format("Removing expired deal %s: %s", deal.id, deal.itemName))
            table.remove(deals, i)
            self.deals[deal.id] = nil

        -- Handle terminated deals (early termination) - remove from tracking
        elseif deal.status == "terminated" then
            UsedPlus.logDebug(string.format("Removing terminated deal %s: %s", deal.id, deal.itemName))
            table.remove(deals, i)
            self.deals[deal.id] = nil

        elseif deal.status == "active" then
            -- Check if this is a lease that should show renewal dialog
            local isLease = (deal.dealType == 2) or (deal.itemType == "lease")

            -- Process monthly payment
            local completed = deal:processMonthlyPayment()

            -- Check if deal became defaulted during payment processing (repossession/seizure)
            if deal.status == "defaulted" then
                UsedPlus.logDebug(string.format("Deal %s defaulted during payment: %s", deal.id, deal.itemName))
                table.remove(deals, i)
                self.deals[deal.id] = nil

            elseif completed then
                if isLease then
                    -- Lease term complete - show renewal dialog instead of auto-removing
                    UsedPlus.logDebug(string.format("Lease %s term complete: %s", deal.id, deal.itemName))
                    self:showLeaseRenewalDialog(deal)
                    -- Don't remove yet - dialog will handle removal based on user choice
                else
                    -- Finance deal paid off
                    UsedPlus.logDebug(string.format("Deal %s completed: %s", deal.id, deal.itemName))

                    -- Track deal completion statistics
                    self:incrementStatistic(deal.farmId, "dealsCompleted", 1)
                    if deal.totalInterestPaid then
                        self:incrementStatistic(deal.farmId, "totalInterestPaid", deal.totalInterestPaid)
                    end

                    -- Send completion notification
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notification_dealComplete"), deal.itemName)
                    )

                    -- Record credit event for payoff
                    if CreditHistory then
                        CreditHistory.recordEvent(deal.farmId, "DEAL_PAID_OFF", deal.itemName)
                    end

                    -- Remove from active deals
                    table.remove(deals, i)
                    self.deals[deal.id] = nil
                end
            end
        end
    end
end

--[[
    Show lease renewal dialog when lease term completes
    @param deal - The expired lease deal
]]
function FinanceManager:showLeaseRenewalDialog(deal)
    -- Create callback to handle user choice
    local callback = function(action, data)
        -- Send event to server for processing
        LeaseRenewalEvent.sendToServer(deal.id, action, data)
    end

    -- Show dialog
    if LeaseRenewalDialog and LeaseRenewalDialog.show then
        LeaseRenewalDialog.show(deal, callback)
    else
        -- Fallback: use DialogLoader
        DialogLoader.show("LeaseRenewalDialog", "setDeal", deal, callback)
    end

    -- Send notification that lease has ended
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format("Lease term complete for %s! Choose to return, buyout, or renew.", deal.itemName)
    )
end

--[[
    Create new finance deal
    Called from network event (client request → server execution)
]]
function FinanceManager:createFinanceDeal(farmId, itemType, itemId, itemName, price, downPayment, termYears, cashBack, configurations)
    if not self.isServer then
        UsedPlus.logError("createFinanceDeal must be called on server")
        return nil
    end

    -- Calculate interest rate based on credit score
    local creditScore = CreditScore.calculate(farmId)
    local downPaymentPercent = downPayment / price
    local termMonths = termYears * 12

    local interestRate
    if itemType == "land" then
        interestRate = FinanceCalculations.calculateLandInterestRate(creditScore, termYears, downPaymentPercent)
    else
        interestRate = FinanceCalculations.calculateVehicleInterestRate(creditScore, termMonths, downPaymentPercent)
    end

    -- Validate parameters
    local isValid, errorMsg = FinanceCalculations.validateFinanceParams(price, downPayment, termYears, itemType)
    if not isValid then
        UsedPlus.logError(string.format("Invalid finance parameters: %s", errorMsg))
        return nil
    end

    -- Create deal object
    local deal = FinanceDeal.new(farmId, itemType, itemId, itemName, price, downPayment, termMonths, interestRate, cashBack or 0)

    -- Assign unique ID
    deal.id = self:generateDealId()

    -- Register deal
    self:registerDeal(deal)

    -- Deduct down payment and add cash back
    local farm = g_farmManager:getFarmById(farmId)
    local netCost = downPayment - (cashBack or 0)

    g_currentMission:addMoney(-netCost, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)

    -- Handle item acquisition based on type
    if itemType == "land" and itemId then
        -- Transfer land ownership to farm
        -- Pattern from FS25_FieldLeasing mod
        local previousOwner = g_farmlandManager:getFarmlandOwner(itemId)
        g_farmlandManager:setLandOwnership(itemId, farmId)

        -- Notify about property change
        if previousOwner ~= FarmlandManager.NO_OWNER_FARM_ID then
            g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, previousOwner)
        end
        g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, farmId)

        UsedPlus.logDebug(string.format("Transferred financed land ownership: Field %d to Farm %d", itemId, farmId))

    elseif itemType == "vehicle" and itemId then
        -- Purchase vehicle using game's built-in system
        local storeItem = g_storeManager:getItemByXMLFilename(itemId)

        if storeItem then
            -- Create BuyVehicleData with user's configurations
            local buyData = BuyVehicleData.new()
            buyData:setOwnerFarmId(farmId)
            buyData:setPrice(0)  -- Already paid via down payment
            buyData:setStoreItem(storeItem)

            -- Apply user-selected configurations
            local vehicleConfigs = configurations or {}
            buyData:setConfigurations(vehicleConfigs)

            -- Debug log configurations being applied
            local configCount = 0
            for k, v in pairs(vehicleConfigs) do
                UsedPlus.logDebug(string.format("  Applying config: %s = %d", tostring(k), v))
                configCount = configCount + 1
            end
            UsedPlus.logDebug(string.format("Total configurations applied: %d", configCount))

            -- Send buy event to spawn vehicle (works on both client and server)
            -- Pattern from HirePurchasing mod - always use event system
            g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))

            UsedPlus.logDebug(string.format("Purchased financed vehicle: %s", itemName))
        else
            UsedPlus.logWarn(string.format("Could not find storeItem for: %s", itemId))
        end
    end

    UsedPlus.logDebug(string.format("Created finance deal %s: %s ($%.2f, %d months @ %.2f%%)",
        deal.id, itemName, price, termMonths, interestRate))

    return deal
end

--[[
    Create new lease deal
    Similar to finance but with lease-specific calculations
]]
function FinanceManager:createLeaseDeal(farmId, vehicleConfig, vehicleName, price, downPayment, termYears)
    if not self.isServer then
        UsedPlus.logError("createLeaseDeal must be called on server")
        return nil
    end

    -- Calculate lease terms
    local creditScore = CreditScore.calculate(farmId)
    local downPaymentPercent = downPayment / price
    local termMonths = termYears * 12

    local interestRate = FinanceCalculations.calculateLeaseInterestRate(creditScore, downPaymentPercent)
    local residualValue = FinanceCalculations.calculateResidualValue(price, termYears)

    -- Validate parameters
    local isValid, errorMsg = FinanceCalculations.validateLeaseParams(price, downPayment, termYears)
    if not isValid then
        UsedPlus.logError(string.format("Invalid lease parameters: %s", errorMsg))
        return nil
    end

    -- Create lease deal object
    local deal = LeaseDeal.new(farmId, vehicleConfig, vehicleName, price, downPayment, termMonths, residualValue, interestRate)

    -- Assign unique ID
    deal.id = self:generateDealId()

    -- Register deal
    self:registerDeal(deal)

    -- Deduct down payment
    g_currentMission:addMoneyChange(-downPayment, farmId, MoneyType.LEASING_COSTS, true)

    UsedPlus.logDebug(string.format("Created lease deal %s: %s ($%.2f, %d months @ %.2f%%, residual $%.2f)",
        deal.id, vehicleName, price, termMonths, interestRate, residualValue))

    return deal
end

--[[
    Register deal in manager
    Adds to both global list and farm-specific list
    Records credit history event for new debt
    v1.8.1: Blocks cash loans when EnhancedLoanSystem is detected
]]
function FinanceManager:registerDeal(deal)
    -- v1.8.1: Block cash loans when EnhancedLoanSystem is installed
    -- ELS handles all loan functionality, we only track vehicle financing and leases
    if deal.dealType == 3 and not ModCompatibility.shouldEnableLoanSystem() then
        UsedPlus.logInfo("Cash loan blocked - EnhancedLoanSystem handles loans")
        return false
    end

    -- Assign unique ID if not already set
    if deal.id == nil then
        deal.id = self.nextDealId
        self.nextDealId = self.nextDealId + 1
    end

    -- Add to global deals table
    self.deals[deal.id] = deal

    -- Add to farm-specific deals table
    if self.dealsByFarm[deal.farmId] == nil then
        self.dealsByFarm[deal.farmId] = {}
    end

    table.insert(self.dealsByFarm[deal.farmId], deal)

    -- Record credit history event for new debt
    if CreditHistory then
        local eventType = "NEW_DEBT_TAKEN"
        if deal.dealType == 3 then  -- Cash loan
            eventType = "LOAN_TAKEN"
        end
        CreditHistory.recordEvent(deal.farmId, eventType, deal.itemName or "Unknown")
    end

    -- Track statistics
    self:incrementStatistic(deal.farmId, "dealsCreated", 1)
    if deal.amountFinanced then
        self:incrementStatistic(deal.farmId, "totalAmountFinanced", deal.amountFinanced)
    elseif deal.price and deal.downPayment then
        self:incrementStatistic(deal.farmId, "totalAmountFinanced", deal.price - deal.downPayment)
    end
end

--[[
    Alias for registerDeal (for backward compatibility)
]]
function FinanceManager:addDeal(deal)
    return self:registerDeal(deal)
end

--[[
    Generate unique deal ID
    Format: "DEAL_NNNNNNNN" (8-digit counter)
    Note: os.date() not available in FS25, using simple counter instead
]]
function FinanceManager:generateDealId()
    local id = string.format("DEAL_%08d", self.nextDealId)
    self.nextDealId = self.nextDealId + 1
    return id
end

--[[
    Get all deals for a specific farm
    Returns array of deals (or empty array if none)
]]
function FinanceManager:getDealsForFarm(farmId)
    return self.dealsByFarm[farmId] or {}
end

--[[
    Get deal by ID
    Returns deal or nil if not found
]]
function FinanceManager:getDealById(dealId)
    return self.deals[dealId]
end

--[[
    Get total monthly obligations for a farm
    Sum of all monthly payments
]]
function FinanceManager:getTotalMonthlyObligations(farmId)
    local deals = self:getDealsForFarm(farmId)
    local total = 0

    for _, deal in ipairs(deals) do
        if deal.status == "active" then
            total = total + deal.monthlyPayment
        end
    end

    return total
end

--[[
    Get total financed amount for a farm
    Sum of all current balances
]]
function FinanceManager:getTotalFinanced(farmId)
    local deals = self:getDealsForFarm(farmId)
    local total = 0

    for _, deal in ipairs(deals) do
        if deal.status == "active" then
            total = total + deal.currentBalance
        end
    end

    return total
end

--[[
    Check if a vehicle has an active lease
    Prevents selling leased vehicles
    @param vehicle - The vehicle object to check
    @return true if vehicle is under an active lease, false otherwise
]]
function FinanceManager:hasActiveLease(vehicle)
    if vehicle == nil then return false end

    local vehicleId = vehicle.id
    local configFileName = vehicle.configFileName

    -- Check all deals for matching lease
    for _, deal in pairs(self.deals) do
        if deal.dealType == 2 and deal.status == "active" then
            -- Match by objectId (most reliable)
            if deal.objectId ~= nil and deal.objectId == vehicleId then
                return true
            end

            -- Fallback: match by config filename and farm
            if deal.vehicleConfig == configFileName and deal.farmId == vehicle.ownerFarmId then
                return true
            end
        end
    end

    return false
end

--[[
    Check if a vehicle is financed (not lease)
    Allows selling but balance must be paid from proceeds
    @param vehicle - The vehicle object to check
    @return true if vehicle has active finance deal, false otherwise
]]
function FinanceManager:hasActiveFinance(vehicle)
    if vehicle == nil then return false end

    local vehicleId = vehicle.id
    local configFileName = vehicle.configFileName

    -- Check all deals for matching finance deal
    for _, deal in pairs(self.deals) do
        if deal.dealType == 1 and deal.status == "active" then
            -- Match by itemId (xmlFilename) for finance deals
            if deal.itemId == configFileName and deal.farmId == vehicle.ownerFarmId then
                return true
            end
        end
    end

    return false
end

--[[
    Get the finance deal for a vehicle
    Returns the deal object or nil
    @param vehicle - The vehicle object
    @return FinanceDeal or nil
]]
function FinanceManager:getFinanceDealForVehicle(vehicle)
    if vehicle == nil then return nil end

    local configFileName = vehicle.configFileName

    for _, deal in pairs(self.deals) do
        if deal.dealType == 1 and deal.status == "active" then
            if deal.itemId == configFileName and deal.farmId == vehicle.ownerFarmId then
                return deal
            end
        end
    end

    return nil
end

--[[
    Get the lease deal for a vehicle
    Returns the deal object or nil
    @param vehicle - The vehicle object
    @return LeaseDeal or nil
]]
function FinanceManager:getLeaseDealForVehicle(vehicle)
    if vehicle == nil then return nil end

    local vehicleId = vehicle.id
    local configFileName = vehicle.configFileName

    for _, deal in pairs(self.deals) do
        if deal.dealType == 2 and deal.status == "active" then
            if deal.objectId ~= nil and deal.objectId == vehicleId then
                return deal
            end
            if deal.vehicleConfig == configFileName and deal.farmId == vehicle.ownerFarmId then
                return deal
            end
        end
    end

    return nil
end

--[[
    Remove a deal from the manager
    Called when lease ends or deal is paid off
    @param dealId - The deal ID to remove
]]
function FinanceManager:removeDeal(dealId)
    local deal = self.deals[dealId]
    if deal == nil then
        UsedPlus.logWarn(string.format("Cannot remove deal %s - not found", dealId))
        return false
    end

    -- Remove from global deals table
    self.deals[dealId] = nil

    -- Remove from farm-specific deals table
    local farmDeals = self.dealsByFarm[deal.farmId]
    if farmDeals then
        for i = #farmDeals, 1, -1 do
            if farmDeals[i].id == dealId then
                table.remove(farmDeals, i)
                break
            end
        end
    end

    UsedPlus.logDebug(string.format("Removed deal %s from manager", dealId))

    return true
end

--[[
    Save all deals to savegame
    Pattern from: EnhancedLoanSystem nested XML serialization
]]
function FinanceManager:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlus.xml"
    local xmlFile = XMLFile.create("usedPlusXML", filePath, "usedPlus")

    if xmlFile ~= nil then
        -- Save next ID counter
        xmlFile:setInt("usedPlus#nextDealId", self.nextDealId)

        -- Save deals grouped by farm
        local farmIndex = 0
        for farmId, deals in pairs(self.dealsByFarm) do
            local farmKey = string.format("usedPlus.farms.farm(%d)", farmIndex)
            xmlFile:setInt(farmKey .. "#farmId", farmId)

            -- Save each deal
            local dealIndex = 0
            for _, deal in ipairs(deals) do
                local dealKey = string.format(farmKey .. ".deal(%d)", dealIndex)
                deal:saveToXMLFile(xmlFile, dealKey)
                dealIndex = dealIndex + 1
            end

            farmIndex = farmIndex + 1
        end

        -- Save credit history (legacy)
        if CreditHistory then
            CreditHistory.saveToXMLFile(xmlFile, "usedPlus.creditHistory")
        end

        -- Save payment tracker (NEW - primary credit data)
        if PaymentTracker then
            PaymentTracker.saveToXMLFile(xmlFile, "usedPlus.paymentTracker")
        end

        -- Save statistics per farm
        local statsIndex = 0
        for farmId, stats in pairs(self.statisticsByFarm) do
            local statsKey = string.format("usedPlus.statistics.farm(%d)", statsIndex)
            xmlFile:setInt(statsKey .. "#farmId", farmId)
            xmlFile:setInt(statsKey .. "#searchesStarted", stats.searchesStarted or 0)
            xmlFile:setInt(statsKey .. "#searchesSucceeded", stats.searchesSucceeded or 0)
            xmlFile:setInt(statsKey .. "#searchesFailed", stats.searchesFailed or 0)
            xmlFile:setInt(statsKey .. "#searchesCancelled", stats.searchesCancelled or 0)
            xmlFile:setFloat(statsKey .. "#totalSearchFees", stats.totalSearchFees or 0)
            xmlFile:setFloat(statsKey .. "#totalSavingsFromUsed", stats.totalSavingsFromUsed or 0)
            xmlFile:setInt(statsKey .. "#usedPurchases", stats.usedPurchases or 0)
            xmlFile:setInt(statsKey .. "#salesListed", stats.salesListed or 0)
            xmlFile:setInt(statsKey .. "#salesCompleted", stats.salesCompleted or 0)
            xmlFile:setInt(statsKey .. "#salesCancelled", stats.salesCancelled or 0)
            xmlFile:setFloat(statsKey .. "#totalSaleProceeds", stats.totalSaleProceeds or 0)
            xmlFile:setInt(statsKey .. "#dealsCreated", stats.dealsCreated or 0)
            xmlFile:setInt(statsKey .. "#dealsCompleted", stats.dealsCompleted or 0)
            xmlFile:setFloat(statsKey .. "#totalAmountFinanced", stats.totalAmountFinanced or 0)
            xmlFile:setFloat(statsKey .. "#totalInterestPaid", stats.totalInterestPaid or 0)
            statsIndex = statsIndex + 1
        end

        -- Save vanilla loan multipliers (bridge to vanilla loan system)
        local vanillaIndex = 0
        for farmId, multiplier in pairs(self.vanillaLoanMultipliers) do
            if multiplier > 1.0 then  -- Only save non-default multipliers
                local vanillaKey = string.format("usedPlus.vanillaLoanMultipliers.farm(%d)", vanillaIndex)
                xmlFile:setInt(vanillaKey .. "#farmId", farmId)
                xmlFile:setFloat(vanillaKey .. "#multiplier", multiplier)
                vanillaIndex = vanillaIndex + 1
            end
        end

        xmlFile:save()
        xmlFile:delete()

        UsedPlus.logDebug(string.format("Saved %d deals across %d farms", self:getTotalDealCount(), farmIndex))
    end
end

--[[
    Load all deals from savegame
    Reconstructs deals from XML data
]]
function FinanceManager:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlus.xml"
    local xmlFile = XMLFile.loadIfExists("usedPlusXML", filePath, "usedPlus")

    if xmlFile ~= nil then
        -- Load next ID counter
        self.nextDealId = xmlFile:getInt("usedPlus#nextDealId", 1)

        -- Load deals (without triggering credit history events)
        local skipCreditHistory = true
        xmlFile:iterate("usedPlus.farms.farm", function(_, farmKey)
            local farmId = xmlFile:getInt(farmKey .. "#farmId")

            xmlFile:iterate(farmKey .. ".deal", function(_, dealKey)
                local dealType = xmlFile:getInt(dealKey .. "#dealType", 1)

                local deal
                if dealType == 1 then
                    -- Finance deal
                    deal = FinanceDeal.new()
                elseif dealType == 2 then
                    -- Vehicle lease deal
                    deal = LeaseDeal.new()
                elseif dealType == 3 then
                    -- Land lease deal
                    deal = LandLeaseDeal.new()
                elseif dealType == 4 then
                    -- Cash loan (uses FinanceDeal)
                    deal = FinanceDeal.new()
                else
                    UsedPlus.logWarn(string.format("Unknown deal type %d", dealType))
                    return
                end

                -- Load deal data
                if deal:loadFromXMLFile(xmlFile, dealKey) then
                    -- Direct registration to avoid triggering credit events for loaded deals
                    self.deals[deal.id] = deal
                    if self.dealsByFarm[deal.farmId] == nil then
                        self.dealsByFarm[deal.farmId] = {}
                    end
                    table.insert(self.dealsByFarm[deal.farmId], deal)
                end
            end)
        end)

        -- Load credit history (legacy)
        if CreditHistory then
            CreditHistory.loadFromXMLFile(xmlFile, "usedPlus.creditHistory")
        end

        -- Load payment tracker (NEW - primary credit data)
        if PaymentTracker then
            PaymentTracker.loadFromXMLFile(xmlFile, "usedPlus.paymentTracker")
        end

        -- Load statistics per farm
        xmlFile:iterate("usedPlus.statistics.farm", function(_, statsKey)
            local farmId = xmlFile:getInt(statsKey .. "#farmId")
            if farmId then
                local stats = self:getStatistics(farmId)
                stats.searchesStarted = xmlFile:getInt(statsKey .. "#searchesStarted", 0)
                stats.searchesSucceeded = xmlFile:getInt(statsKey .. "#searchesSucceeded", 0)
                stats.searchesFailed = xmlFile:getInt(statsKey .. "#searchesFailed", 0)
                stats.searchesCancelled = xmlFile:getInt(statsKey .. "#searchesCancelled", 0)
                stats.totalSearchFees = xmlFile:getFloat(statsKey .. "#totalSearchFees", 0)
                stats.totalSavingsFromUsed = xmlFile:getFloat(statsKey .. "#totalSavingsFromUsed", 0)
                stats.usedPurchases = xmlFile:getInt(statsKey .. "#usedPurchases", 0)
                stats.salesListed = xmlFile:getInt(statsKey .. "#salesListed", 0)
                stats.salesCompleted = xmlFile:getInt(statsKey .. "#salesCompleted", 0)
                stats.salesCancelled = xmlFile:getInt(statsKey .. "#salesCancelled", 0)
                stats.totalSaleProceeds = xmlFile:getFloat(statsKey .. "#totalSaleProceeds", 0)
                stats.dealsCreated = xmlFile:getInt(statsKey .. "#dealsCreated", 0)
                stats.dealsCompleted = xmlFile:getInt(statsKey .. "#dealsCompleted", 0)
                stats.totalAmountFinanced = xmlFile:getFloat(statsKey .. "#totalAmountFinanced", 0)
                stats.totalInterestPaid = xmlFile:getFloat(statsKey .. "#totalInterestPaid", 0)
            end
        end)

        -- Load vanilla loan multipliers (bridge to vanilla loan system)
        xmlFile:iterate("usedPlus.vanillaLoanMultipliers.farm", function(_, vanillaKey)
            local farmId = xmlFile:getInt(vanillaKey .. "#farmId")
            local multiplier = xmlFile:getFloat(vanillaKey .. "#multiplier", 1.0)
            if farmId and multiplier > 1.0 then
                self.vanillaLoanMultipliers[farmId] = multiplier
                UsedPlus.logDebug(string.format("Loaded vanilla loan multiplier for farm %d: %.1fx", farmId, multiplier))
            end
        end)

        xmlFile:delete()

        UsedPlus.logDebug(string.format("Loaded %d deals from savegame", self:getTotalDealCount()))
    else
        UsedPlus.logDebug("No saved data found (new game)")
    end
end

--[[
    Get total count of all deals
]]
function FinanceManager:getTotalDealCount()
    local count = 0
    for _ in pairs(self.deals) do
        count = count + 1
    end
    return count
end

--[[
    Cleanup on mission unload
]]
function FinanceManager:delete()
    -- Unsubscribe from events
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    end

    -- Clear data
    self.deals = {}
    self.dealsByFarm = {}

    -- Clear credit tracking data
    if CreditHistory then
        CreditHistory.clear()
    end
    if PaymentTracker then
        PaymentTracker.clear()
    end

    UsedPlus.logDebug("FinanceManager cleaned up")
end

UsedPlus.logInfo("FinanceManager loaded")
