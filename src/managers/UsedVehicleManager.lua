--[[
    FS25_UsedPlus - Used Vehicle Manager

    UsedVehicleManager handles used equipment search queue
    Pattern from: BuyUsedEquipment "Async Search Queue System"
    Reference: FS25_ADVANCED_PATTERNS.md - Async Operations section

    v1.5.0: Multi-find agent model
    - Small retainer fee upfront (paid when search starts)
    - Commission built into vehicle asking price (paid when buying)
    - Monthly success rolls (1 game day = 1 month)
    - Multiple vehicles accumulate in portfolio
    - Player browses and picks from found vehicles

    Responsibilities:
    - Track all active used vehicle searches across all farms
    - Process search queue daily (1 day = 1 month) for success rolls
    - Generate used vehicle listings when monthly rolls succeed
    - Manage portfolio of found vehicles per search
    - Send notifications (vehicle found/search complete) via network events
    - Save/load search queue to savegame
    - Provide query methods for active searches and portfolios

    This is a global singleton: g_usedVehicleManager
]]

UsedVehicleManager = {}
local UsedVehicleManager_mt = Class(UsedVehicleManager)

--[[
    Constructor
    Creates manager instance with empty data structures
]]
function UsedVehicleManager.new()
    local self = setmetatable({}, UsedVehicleManager_mt)

    -- Data structures
    self.activeSearches = {}  -- All searches indexed by ID
    self.nextSearchId = 1

    -- Pending used vehicle purchases - tracks listings that need condition applied after spawn
    -- Key: storeItem.xmlFilename, Value: { listing=..., farmId=..., timestamp=... }
    self.pendingUsedPurchases = {}

    -- Event subscriptions
    self.isServer = g_currentMission:getIsServer()
    self.isClient = g_currentMission:getIsClient()

    return self
end

--[[
    Initialize manager after mission loads
    Subscribe to hourly events for queue processing
    v1.5.0: Still uses HOUR_CHANGED but checks for day change (1 day = 1 month)
]]
function UsedVehicleManager:loadMapFinished()
    if self.isServer then
        -- Subscribe to hourly game time - we check for day changes
        -- Pattern from: BuyUsedEquipment hourly queue processing
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)

        -- Track the last day we processed monthly checks
        self.lastProcessedDay = g_currentMission.environment.currentDay

        UsedPlus.logDebug("UsedVehicleManager subscribed to HOUR_CHANGED (v1.5.0 monthly model)")
    end
end

--[[
    Hourly queue processing
    v1.5.0: Checks for day change (1 game day = 1 month) to process monthly success rolls
    Called automatically when in-game hour changes
]]
function UsedVehicleManager:onHourChanged()
    if not self.isServer then return end

    local currentDay = g_currentMission.environment.currentDay

    -- v1.5.0: Only process monthly checks once per day (1 day = 1 month)
    if self.lastProcessedDay == currentDay then
        return  -- Already processed today
    end

    self.lastProcessedDay = currentDay

    local totalSearches = self:getTotalSearchCount()
    UsedPlus.logDebug(string.format("DAY_CHANGED (Day %d) - Processing monthly search rolls (total active: %d)",
        currentDay, totalSearches))

    -- Process all active searches
    -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        if farm.usedVehicleSearches and #farm.usedVehicleSearches > 0 then
            UsedPlus.logTrace(string.format("  Farm %d has %d searches", farmId, #farm.usedVehicleSearches))
            self:processSearchesForFarm(farmId, farm)
        end
    end
end

--[[
    Process searches for a single farm
    v1.5.0: Monthly success rolls - vehicles accumulate in portfolio
    Iterate backwards to safely remove completed searches
]]
function UsedVehicleManager:processSearchesForFarm(farmId, farm)
    -- Iterate backwards for safe removal
    for i = #farm.usedVehicleSearches, 1, -1 do
        local search = farm.usedVehicleSearches[i]

        if search.status == "active" then
            -- Log before monthly check
            UsedPlus.logTrace(string.format("    Search %s: %s - Month %d/%d, Listings: %d/%d",
                search.id, search.storeItemName,
                search.monthsElapsed or 0, search.maxMonths or 1,
                #(search.foundListings or {}), search.maxListings or 10))

            -- v1.5.0: Process monthly success roll
            local listingData = search:processMonthlyCheck()

            -- If a vehicle was found this month, flesh out the listing
            if listingData then
                UsedPlus.logDebug(string.format("Search %s found vehicle this month: condition=%.1f%%",
                    search.id, (1 - (listingData.damage or 0)) * 100))

                -- Generate full listing with store item details, configurations, etc.
                local fullListing = self:generateUsedVehicleListingFromData(search, listingData)

                if fullListing then
                    -- Add to search's portfolio (foundListings is managed by the search object)
                    -- The listingData was already added by processMonthlyCheck, but we need to
                    -- update it with the full data
                    for j, existingListing in ipairs(search.foundListings) do
                        if existingListing.id == listingData.id then
                            -- Replace partial data with full listing
                            search.foundListings[j] = fullListing
                            break
                        end
                    end

                    -- Track statistic
                    if g_financeManager then
                        g_financeManager:incrementStatistic(farmId, "vehiclesFound", 1)
                    end

                    -- Notify player a vehicle was found
                    self:notifyVehicleFound(search, fullListing, farmId)
                end
            end

            -- Check if search has completed (expired or player bought a vehicle)
            if search.status == "completed" then
                UsedPlus.logDebug(string.format("Search %s completed: %s (%d vehicles found)",
                    search.id, search.storeItemName, #(search.foundListings or {})))

                -- Remove from active searches
                table.remove(farm.usedVehicleSearches, i)
                self.activeSearches[search.id] = nil

                -- Track completion statistic
                if g_financeManager then
                    local foundCount = #(search.foundListings or {})
                    if foundCount > 0 then
                        g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
                    else
                        g_financeManager:incrementStatistic(farmId, "searchesFailed", 1)
                    end
                end

                -- Notify player search is complete
                self:notifySearchComplete(search, farmId)
            end
            -- else: search still active, will continue next month
        end
    end
end

--[[
    Notify player that a vehicle was found
    v1.5.0: Shows notification AND opens UsedVehiclePreviewDialog
    Player can inspect/buy the found vehicle immediately
]]
function UsedVehicleManager:notifyVehicleFound(search, listing, farmId)
    -- Only show if game is running
    if g_currentMission == nil or g_currentMission.isLoading then
        return
    end

    local message = string.format(
        g_i18n:getText("usedplus_notify_vehicleFound") or "Your agent found a %s!",
        search.storeItemName or "vehicle"
    )

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        message
    )

    UsedPlus.logDebug(string.format("Notified player: vehicle found for search %s", search.id))

    -- v1.5.0: Show the preview dialog so player can act on it immediately
    -- This is the same dialog as before - lets them Inspect or Buy As-Is
    if listing then
        self:showSearchResultDialog(listing, farmId)
    end
end

--[[
    Notify player that a search has completed
    v1.5.0: Shows summary of what was found
    v1.5.1: Shows SearchExpiredDialog with renewal option
]]
function UsedVehicleManager:notifySearchComplete(search, farmId)
    -- Only show if game is running
    if g_currentMission == nil or g_currentMission.isLoading then
        return
    end

    local foundCount = #(search.foundListings or {})

    -- Calculate renewal cost (same as original search)
    local renewCost = self:calculateSearchCost(search.tier, search.storeItemPrice or 0, farmId)

    UsedPlus.logDebug(string.format("Search %s complete with %d vehicles, showing expiration dialog", search.id, foundCount))

    -- Show the SearchExpiredDialog with renewal option
    if SearchExpiredDialog and SearchExpiredDialog.showWithData then
        SearchExpiredDialog.showWithData(search, foundCount, renewCost, function(renewChoice)
            if renewChoice then
                -- Player chose to renew - create a new search with same parameters
                self:renewSearch(search, farmId)
            else
                -- Player declined - just log it
                UsedPlus.logDebug(string.format("Player declined to renew search %s", search.id))
            end
        end)
    else
        -- Fallback to notification if dialog not available
        local message = string.format(
            g_i18n:getText("usedplus_notify_searchComplete") or "Search complete: %d vehicle(s) found for %s",
            foundCount, search.storeItemName or "vehicle"
        )

        g_currentMission:addIngameNotification(
            foundCount > 0 and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_INFO,
            message
        )
    end
end

--[[
    Renew a search with the same parameters
    @param oldSearch - The completed search to renew
    @param farmId - Farm ID
]]
function UsedVehicleManager:renewSearch(oldSearch, farmId)
    -- Calculate cost
    local cost = self:calculateSearchCost(oldSearch.tier, oldSearch.storeItemPrice or 0, farmId)

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(farmId)
    if farm.money < cost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Insufficient funds to renew search."
        )
        return false
    end

    -- Create new search with same parameters
    local newSearch = UsedVehicleSearch.new(
        oldSearch.storeItemIndex,
        oldSearch.storeItemName,
        oldSearch.storeItemPrice or 0,
        oldSearch.tier,
        oldSearch.qualityTier,
        oldSearch.requestedConfigId
    )

    -- Charge the fee
    farm:changeBalance(-cost, MoneyType.OTHER)

    -- Add to active searches
    self.activeSearches[newSearch.id] = newSearch
    table.insert(farm.usedVehicleSearches, newSearch)

    -- Notify player
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Search renewed for %s!", oldSearch.storeItemName)
    )

    UsedPlus.logInfo(string.format("Renewed search for %s (Tier %d, Quality %d)",
        oldSearch.storeItemName, oldSearch.tier, oldSearch.qualityTier))

    return true
end

--[[
    Calculate search cost based on tier and vehicle price
    @param tier - Search tier (1-3)
    @param vehiclePrice - Base price of vehicle
    @param farmId - Farm ID for credit modifier
    @return cost - Total search cost
]]
function UsedVehicleManager:calculateSearchCost(tier, vehiclePrice, farmId)
    local tierInfo = UsedVehicleSearch.SEARCH_TIERS[tier]
    if not tierInfo then
        return 0
    end

    local baseCost = tierInfo.retainerFlat + (vehiclePrice * tierInfo.retainerPercent)

    -- Apply credit score modifier
    if farmId and CreditScore then
        local score = CreditScore.calculate(farmId)
        local modifier = UsedVehicleSearch.getCreditFeeModifier(score)
        baseCost = baseCost * (1 + modifier)
    end

    return math.floor(baseCost)
end

--[[
    Generate used vehicle listing from partial data returned by processMonthlyCheck
    v1.5.0: Takes basic condition data and adds store item details, configs, commission
    @param search - The UsedVehicleSearch object
    @param listingData - Partial data from processMonthlyCheck (id, damage, wear, age, operatingHours, basePrice)
]]
function UsedVehicleManager:generateUsedVehicleListingFromData(search, listingData)
    -- Get store item data
    local storeItem = g_storeManager:getItemByXMLFilename(search.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError(string.format("Store item not found for search %s (xmlFilename: %s)",
            search.id, tostring(search.storeItemIndex)))
        return nil
    end

    -- Apply configuration matching if specific config requested
    local selectedConfig = nil
    if search.requestedConfigId then
        local configMatch = self:findMatchingConfiguration(storeItem, search.requestedConfigId)
        if configMatch then
            selectedConfig = configMatch
        else
            selectedConfig = self:selectRandomConfiguration(storeItem)
        end
    else
        selectedConfig = self:selectRandomConfiguration(storeItem)
    end

    -- Generate hidden reliability scores based on damage, age, hours, and quality tier
    local usedPlusData = nil
    if UsedPlusMaintenance and UsedPlusMaintenance.generateReliabilityScores then
        usedPlusData = UsedPlusMaintenance.generateReliabilityScores(
            listingData.damage or 0,
            listingData.age or 1,
            listingData.operatingHours or 100,
            search.qualityLevel  -- DNA bias based on quality tier
        )
    end

    -- v1.5.0: Calculate commission and asking price
    local basePrice = listingData.basePrice or listingData.price or 0
    local commissionPercent = search.commissionPercent or 0.08
    local commissionAmount = math.floor(basePrice * commissionPercent)
    local askingPrice = basePrice + commissionAmount

    -- Create full listing object
    local fullListing = {
        id = listingData.id,
        farmId = search.farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,
        configuration = selectedConfig,

        -- Used vehicle stats
        age = listingData.age or 1,
        operatingHours = math.floor(listingData.operatingHours or 100),
        damage = listingData.damage or 0,
        wear = listingData.wear or 0,

        -- v1.5.0: Pricing with commission
        basePrice = basePrice,                -- Vehicle value before commission
        commissionPercent = commissionPercent,
        commissionAmount = commissionAmount,  -- Commission in dollars
        askingPrice = askingPrice,            -- What player pays (base + commission)
        price = askingPrice,                  -- Legacy field for compatibility

        -- Hidden maintenance data
        usedPlusData = usedPlusData,

        -- Metadata
        generationName = listingData.generationName or "Unknown",
        qualityLevel = listingData.qualityLevel or search.qualityLevel,
        qualityName = listingData.qualityName or "Any",
        listingDate = g_currentMission.environment.currentDay,
        status = "available"
    }

    UsedPlus.logDebug(string.format("Generated full listing %s: %s (base $%d + $%d commission = $%d asking)",
        fullListing.id, fullListing.storeItemName,
        fullListing.basePrice, fullListing.commissionAmount, fullListing.askingPrice))

    return fullListing
end

--[[
    Generate used vehicle listing from successful search (LEGACY - kept for compatibility)
    v1.5.0: Updated to include commission calculation
    Uses DepreciationCalculations to create realistic used vehicle
]]
function UsedVehicleManager:generateUsedVehicleListing(search)
    -- Get store item data
    -- FIXED: storeItemIndex is actually xmlFilename (string), use getItemByXMLFilename
    local storeItem = g_storeManager:getItemByXMLFilename(search.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError(string.format("Store item not found for search %s (xmlFilename: %s)",
            search.id, tostring(search.storeItemIndex)))
        return nil
    end

    -- Generate used vehicle parameters
    -- Pattern from: BuyUsedEquipment vehicle generation
    -- searchLevel affects generation distribution (age) and applies condition modifier
    -- qualityLevel determines base damage/wear ranges (player's preference)
    -- Local (1): More old vehicles, worse condition
    -- Regional (2): Normal distribution
    -- National (3): More recent vehicles, better condition
    local usedParams = DepreciationCalculations.generateUsedVehicleParams(nil, search.searchLevel, search.qualityLevel)

    -- Apply configuration matching if specific config requested
    local selectedConfig = nil
    if search.requestedConfigId then
        -- Try to match requested configuration
        local configMatch = self:findMatchingConfiguration(storeItem, search.requestedConfigId)
        if configMatch then
            selectedConfig = configMatch
            UsedPlus.logTrace(string.format("Matched config %s for %s", selectedConfig.id, search.storeItemName))
        else
            -- Fallback to random config if exact match not found
            selectedConfig = self:selectRandomConfiguration(storeItem)
        end
    else
        -- Random configuration
        selectedConfig = self:selectRandomConfiguration(storeItem)
    end

    -- Calculate used vehicle price
    -- FIXED: usedParams doesn't have 'price' - must calculate it
    local usedPrice, repairCost, repaintCost = DepreciationCalculations.calculateUsedPrice(storeItem, usedParams)

    -- Generate hidden reliability scores based on damage, age, hours, and quality tier
    -- v1.4.0: DNA distribution is now correlated with quality tier
    local usedPlusData = nil
    if UsedPlusMaintenance and UsedPlusMaintenance.generateReliabilityScores then
        usedPlusData = UsedPlusMaintenance.generateReliabilityScores(
            usedParams.damage,
            usedParams.age,
            usedParams.operatingHours,
            usedParams.qualityLevel  -- DNA bias based on quality tier
        )
        UsedPlus.logTrace(string.format("Generated reliability: engine=%.2f, hydraulic=%.2f, electrical=%.2f, DNA=%.3f",
            usedPlusData.engineReliability, usedPlusData.hydraulicReliability, usedPlusData.electricalReliability,
            usedPlusData.workhorseLemonScale or 0.5))
    end

    -- v1.5.0: Calculate commission and asking price
    local commissionPercent = search.commissionPercent or 0.08
    local commissionAmount = math.floor(usedPrice * commissionPercent)
    local askingPrice = usedPrice + commissionAmount

    -- Create listing object
    local listing = {
        id = self:generateListingId(),
        farmId = search.farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,
        configuration = selectedConfig,

        -- Used vehicle stats
        age = usedParams.age,
        operatingHours = math.floor(usedParams.operatingHours),
        damage = usedParams.damage,
        wear = usedParams.wear,

        -- v1.5.0: Pricing with commission
        basePrice = usedPrice,                -- Vehicle value before commission
        commissionPercent = commissionPercent,
        commissionAmount = commissionAmount,  -- Commission in dollars
        askingPrice = askingPrice,            -- What player pays (base + commission)
        price = askingPrice,                  -- Legacy field for compatibility

        -- Hidden maintenance data (Phase 3)
        usedPlusData = usedPlusData,

        -- Metadata
        generationName = usedParams.generationName,
        qualityLevel = usedParams.qualityLevel,
        qualityName = usedParams.qualityName,
        listingDate = g_currentMission.environment.currentDay,
        expirationTTL = 72,  -- 72 hours (3 days) to purchase
        status = "available"
    }

    UsedPlus.logDebug(string.format("Generated listing %s: %s (base $%.2f + $%.2f commission = $%.2f asking, %d hrs, %.1f%% damage)",
        listing.id, listing.storeItemName, listing.basePrice, listing.commissionAmount, listing.askingPrice,
        listing.operatingHours, listing.damage * 100))

    return listing
end

--[[
    Show the UsedVehiclePreviewDialog for a completed search result
    Allows user to Buy As-Is, Inspect, or Cancel
    @param listing - The generated UsedVehicleListing
    @param farmId - Farm ID of the buyer
]]
function UsedVehicleManager:showSearchResultDialog(listing, farmId)
    -- Only show dialog if game is running and not in loading state
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logDebug("Skipping dialog - mission not ready")
        return
    end

    -- Use DialogLoader to show the preview dialog
    -- Capture self explicitly to avoid closure issues
    local manager = self
    local callback = function(confirmed, resultListing)
        UsedPlus.logDebug(string.format("UsedVehicleManager callback invoked: confirmed=%s, resultListing=%s",
            tostring(confirmed), tostring(resultListing and resultListing.storeItemName or "nil")))
        UsedPlus.logDebug(string.format("Callback closure check: manager=%s, farmId=%s",
            tostring(manager), tostring(farmId)))
        if confirmed and resultListing then
            -- User wants to buy - spawn the vehicle
            UsedPlus.logDebug(string.format("Calling purchaseUsedVehicle for %s", resultListing.storeItemName or "Unknown"))
            if manager and manager.purchaseUsedVehicle then
                UsedPlus.logDebug("manager.purchaseUsedVehicle exists, calling it...")
                UsedPlus.logDebug("CODE VERSION: 2025-12-01 18:30 - About to call purchaseUsedVehicle")
                local purchaseResult = nil
                local success, err = pcall(function()
                    purchaseResult = manager:purchaseUsedVehicle(resultListing, farmId)
                end)
                UsedPlus.logDebug(string.format("pcall returned: success=%s, err=%s, purchaseResult=%s",
                    tostring(success), tostring(err), tostring(purchaseResult)))
                if not success then
                    UsedPlus.logError(string.format("purchaseUsedVehicle FAILED: %s", tostring(err)))
                else
                    UsedPlus.logDebug("purchaseUsedVehicle completed")
                end
            else
                UsedPlus.logError(string.format("CANNOT CALL purchaseUsedVehicle: manager=%s, method=%s",
                    tostring(manager), tostring(manager and manager.purchaseUsedVehicle)))
            end
        else
            -- User cancelled - listing remains available for later
            UsedPlus.logDebug("User cancelled used vehicle purchase")
        end
    end

    -- Show the UsedVehiclePreviewDialog
    if DialogLoader and DialogLoader.show then
        DialogLoader.show("UsedVehiclePreviewDialog", "show", listing, farmId, callback, self)
        UsedPlus.logDebug(string.format("Showing UsedVehiclePreviewDialog for %s", listing.storeItemName or "Unknown"))
    else
        UsedPlus.logWarn("DialogLoader not available - cannot show preview dialog")
    end
end

--[[
    Show dialog when search fails (no vehicle found)
    @param search - The failed UsedVehicleSearch
]]
function UsedVehicleManager:showSearchFailedDialog(search)
    -- Only show dialog if game is running and not in loading state
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logDebug("Skipping failure dialog - mission not ready")
        return
    end

    local title = g_i18n:getText("usedplus_searchFailed_title") or "Search Complete"
    local message = string.format(
        g_i18n:getText("usedplus_searchFailed_message") or "Your agent was unable to find a %s matching your criteria. The search fee is non-refundable.",
        search.storeItemName or "vehicle"
    )

    -- Use InfoDialog for single-button "OK" dialog
    local dialog = g_gui:showDialog("InfoDialog")
    if dialog ~= nil and dialog.target ~= nil then
        dialog.target:setDialogType(DialogElement.TYPE_INFO)
        dialog.target:setText(message)
        dialog.target:setCallback(function() end, nil)
        UsedPlus.logDebug(string.format("Showing search failed dialog for %s", search.storeItemName or "Unknown"))
    else
        -- Fallback to notification if dialog fails
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            message
        )
        UsedPlus.logDebug(string.format("Showing search failed notification for %s", search.storeItemName or "Unknown"))
    end
end

--[[
    Purchase a used vehicle from a listing
    Called when user confirms purchase in UsedVehiclePreviewDialog
    @param listing - The UsedVehicleListing to purchase
    @param farmId - Farm ID of the buyer
]]
function UsedVehicleManager:purchaseUsedVehicle(listing, farmId)
    UsedPlus.logDebug("=== purchaseUsedVehicle FUNCTION ENTERED (v2025-12-01 BuyVehicleEvent) ===")
    UsedPlus.logDebug(string.format("purchaseUsedVehicle args: listing=%s, farmId=%s",
        tostring(listing and listing.storeItemName or "nil"), tostring(farmId)))
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError("Farm not found for purchase")
        return false
    end

    -- Check if player can afford
    if farm.money < listing.price then
        g_currentMission:showBlinkingWarning(
            string.format("Insufficient funds. Need %s", g_i18n:formatMoney(listing.price, 0, true, true)),
            3000
        )
        return false
    end

    -- Deduct money
    g_currentMission:addMoney(-listing.price, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)

    -- Spawn the vehicle
    local success = self:spawnUsedVehicle(listing, farmId)

    if success then
        -- Remove listing from available listings
        self:removeListing(listing, farmId)

        -- v1.7.1: End the search when a vehicle is purchased - player found what they wanted
        if listing.searchId then
            self:endSearchAfterPurchase(listing.searchId, farmId)
        end

        -- Track statistics
        if g_financeManager then
            g_financeManager:incrementStatistic(farmId, "usedVehiclesPurchased", 1)
            g_financeManager:incrementStatistic(farmId, "totalUsedVehicleSpent", listing.price)
        end

        -- Use addGameNotification (pattern from BuyUsedEquipment)
        g_currentMission:addGameNotification(
            "Purchase Complete",
            "",
            string.format("Purchased %s for %s. Check near your position!",
                listing.storeItemName,
                g_i18n:formatMoney(listing.price, 0, true, true)),
            nil,
            10000
        )

        UsedPlus.logDebug(string.format("Used vehicle purchased: %s for $%.2f", listing.storeItemName, listing.price))
        return true
    else
        -- Refund if spawn failed
        g_currentMission:addMoney(listing.price, farmId, MoneyType.OTHER, true, true)
        g_currentMission:showBlinkingWarning("Failed to spawn vehicle. Money refunded.", 5000)
        return false
    end
end

--[[
    Spawn a used vehicle from listing
    Uses BuyVehicleData/BuyVehicleEvent - the proper FS25 vehicle purchase API
    @param listing - The UsedVehicleListing
    @param farmId - Owner farm ID
    @return boolean success
]]
function UsedVehicleManager:spawnUsedVehicle(listing, farmId)
    UsedPlus.logDebug("=== spawnUsedVehicle ENTERED (using BuyVehicleData API) ===")
    UsedPlus.logDebug(string.format("spawnUsedVehicle: storeItemIndex=%s", tostring(listing.storeItemIndex)))

    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError("Could not find store item for spawning")
        return false
    end

    UsedPlus.logDebug(string.format("Store item: %s", tostring(storeItem.name)))

    -- Check if BuyVehicleData and BuyVehicleEvent are available
    if BuyVehicleData == nil then
        UsedPlus.logError("BuyVehicleData class not available")
        return false
    end
    if BuyVehicleEvent == nil then
        UsedPlus.logError("BuyVehicleEvent class not available")
        return false
    end

    -- Build configurations table from listing's random configuration
    local configTable = {}
    if listing.configuration then
        for configName, configValue in pairs(listing.configuration) do
            configTable[configName] = configValue
        end
    end

    -- Log the configurations being used
    local configCount = 0
    for k, v in pairs(configTable) do
        UsedPlus.logDebug(string.format("  Config: %s = %s", tostring(k), tostring(v)))
        configCount = configCount + 1
    end
    UsedPlus.logDebug(string.format("Total configurations: %d", configCount))

    UsedPlus.logDebug("Creating BuyVehicleData...")

    -- Create BuyVehicleData - the proper FS25 way to purchase vehicles
    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(farmId)
    buyData:setPrice(0)  -- Price already deducted in purchaseUsedVehicle
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations(configTable)

    -- Set configuration data if available (for appearance like colors)
    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end

    -- Set license plate data if method exists
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    -- Store pending purchase so we can apply used condition after spawn
    -- Key by xmlFilename + farmId to handle multiple purchases
    local pendingKey = storeItem.xmlFilename .. "_" .. tostring(farmId) .. "_" .. tostring(g_currentMission.time)
    self.pendingUsedPurchases[pendingKey] = {
        listing = listing,
        farmId = farmId,
        xmlFilename = storeItem.xmlFilename,
        timestamp = g_currentMission.time
    }
    UsedPlus.logDebug(string.format("Stored pending purchase: %s", pendingKey))

    UsedPlus.logDebug("Sending BuyVehicleEvent...")

    -- Send the event - this triggers the proper vehicle spawning
    local success, err = pcall(function()
        g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
    end)

    if success then
        UsedPlus.logDebug("BuyVehicleEvent sent successfully - condition will be applied in onBought hook")
        return true
    else
        UsedPlus.logError(string.format("BuyVehicleEvent failed: %s", tostring(err)))
        -- Clean up pending purchase on failure
        self.pendingUsedPurchases[pendingKey] = nil
        return false
    end
end

--[[
    Apply used condition to a spawned vehicle
    Sets damage, wear, operating hours, and UsedPlus reliability data
    Uses FS25 Wearable spec methods (pattern from RealisticWeather, Courseplay)
    @param vehicle - The spawned vehicle
    @param listing - The UsedVehicleListing with condition data
]]
function UsedVehicleManager:applyUsedConditionToVehicle(vehicle, listing)
    if vehicle == nil then
        UsedPlus.logWarn("applyUsedConditionToVehicle: vehicle is nil")
        return
    end

    UsedPlus.logDebug(string.format("applyUsedConditionToVehicle: Applying to %s", tostring(vehicle.typeName or "unknown")))

    -- Apply damage and wear via spec_wearable (FS25 pattern)
    local wearable = vehicle.spec_wearable
    if wearable then
        -- Apply damage - use addDamageAmount since vehicle starts at 0
        if listing.damage and listing.damage > 0 then
            if wearable.addDamageAmount then
                wearable:addDamageAmount(listing.damage, true)
                UsedPlus.logDebug(string.format("  Added damage via spec_wearable: %.2f", listing.damage))
            elseif vehicle.addDamageAmount then
                vehicle:addDamageAmount(listing.damage, true)
                UsedPlus.logDebug(string.format("  Added damage via vehicle: %.2f", listing.damage))
            end
        end

        -- Apply wear - use addWearAmount since vehicle starts at 0
        if listing.wear and listing.wear > 0 then
            if wearable.addWearAmount then
                wearable:addWearAmount(listing.wear, true)
                UsedPlus.logDebug(string.format("  Added wear via spec_wearable: %.2f", listing.wear))
            elseif vehicle.addWearAmount then
                vehicle:addWearAmount(listing.wear, true)
                UsedPlus.logDebug(string.format("  Added wear via vehicle: %.2f", listing.wear))
            end
        end
    else
        UsedPlus.logDebug("  No spec_wearable found, trying vehicle methods directly")
        -- Fallback to vehicle-level methods
        if listing.damage and listing.damage > 0 and vehicle.addDamageAmount then
            vehicle:addDamageAmount(listing.damage, true)
        end
        if listing.wear and listing.wear > 0 and vehicle.addWearAmount then
            vehicle:addWearAmount(listing.wear, true)
        end
    end

    -- Apply operating hours via setOperatingTime (takes milliseconds)
    if listing.operatingHours and listing.operatingHours > 0 then
        local operatingTimeMs = listing.operatingHours * 60 * 60 * 1000
        if vehicle.setOperatingTime then
            vehicle:setOperatingTime(operatingTimeMs)
            UsedPlus.logDebug(string.format("  Set operating time: %d hours (%d ms)", listing.operatingHours, operatingTimeMs))
        else
            UsedPlus.logDebug("  setOperatingTime not available on vehicle")
        end
    end

    -- Apply vehicle age (in months) - FS25 stores age in months
    if listing.age and listing.age > 0 then
        local ageMonths = listing.age * 12  -- Convert years to months

        -- Try setting vehicle.age directly (most FS25 vehicles have this property)
        local success = pcall(function()
            vehicle.age = ageMonths
        end)

        if success then
            UsedPlus.logDebug(string.format("  Set vehicle.age: %d years (%d months)", listing.age, ageMonths))
        else
            -- Try setAge method if direct assignment fails
            if vehicle.setAge then
                vehicle:setAge(ageMonths)
                UsedPlus.logDebug(string.format("  Set vehicle age via setAge(): %d years (%d months)", listing.age, ageMonths))
            else
                UsedPlus.logDebug(string.format("  Could not set vehicle age - property/method not available"))
            end
        end
    end

    -- Apply UsedPlus maintenance data if available
    if listing.usedPlusData and UsedPlusMaintenance and UsedPlusMaintenance.setUsedPurchaseData then
        local purchaseData = {
            price = listing.price or 0,
            damage = listing.damage or 0,
            operatingHours = listing.operatingHours or 0,
            wasInspected = listing.usedPlusData.wasInspected or false,
            engineReliability = listing.usedPlusData.engineReliability or 0.8,
            hydraulicReliability = listing.usedPlusData.hydraulicReliability or 0.8,
            electricalReliability = listing.usedPlusData.electricalReliability or 0.8
        }
        UsedPlusMaintenance.setUsedPurchaseData(vehicle, purchaseData)
        UsedPlus.logDebug("  Applied UsedPlus reliability data")
    end

    -- Apply dirt based on quality tier (v1.5.1)
    -- Lower quality = dirtier vehicle
    self:applyDirtBasedOnQuality(vehicle, listing.qualityLevel, listing.damage)

    UsedPlus.logDebug(string.format("Applied used condition complete: damage=%.2f, wear=%.2f, hours=%d",
        listing.damage or 0, listing.wear or 0, listing.operatingHours or 0))
end

--[[
    Apply dirt to vehicle based on quality level
    Lower quality levels = more dirt, higher levels = cleaner

    Quality Levels (from UsedVehicleSearch):
    1 = Any Condition (worst)
    2 = Poor Condition
    3 = Fair Condition
    4 = Good Condition
    5 = Excellent Condition (best)

    @param vehicle - The spawned vehicle
    @param qualityLevel - Quality level (1-5)
    @param damage - Vehicle damage (0-1) used as additional factor
]]
function UsedVehicleManager:applyDirtBasedOnQuality(vehicle, qualityLevel, damage)
    if vehicle == nil then
        return
    end

    -- Get spec_washable
    local washable = vehicle.spec_washable
    if washable == nil or washable.washableNodes == nil then
        UsedPlus.logDebug("  No washable nodes found - vehicle will be clean")
        return
    end

    -- Calculate dirt amount based on quality tier
    -- Each tier has a base range, then we add randomness
    local dirtRanges = {
        [1] = { min = 0.70, max = 1.00 },  -- Any Condition: 70-100% dirty (filthy)
        [2] = { min = 0.55, max = 0.85 },  -- Poor Condition: 55-85% dirty (very dirty)
        [3] = { min = 0.30, max = 0.55 },  -- Fair Condition: 30-55% dirty (moderately dirty)
        [4] = { min = 0.10, max = 0.30 },  -- Good Condition: 10-30% dirty (light dust)
        [5] = { min = 0.00, max = 0.10 },  -- Excellent Condition: 0-10% dirty (nearly clean)
    }

    local tier = qualityLevel or 3  -- Default to Fair
    local range = dirtRanges[tier] or dirtRanges[3]

    -- Base dirt amount from quality tier
    local baseDirt = range.min + math.random() * (range.max - range.min)

    -- Add a bit more dirt based on damage (damaged vehicles are often dirtier)
    local damageBonus = (damage or 0) * 0.15  -- Up to 15% extra dirt from damage
    local finalDirt = math.min(1.0, baseDirt + damageBonus)

    UsedPlus.logDebug(string.format("  Applying dirt: tier=%d, baseDirt=%.2f, damageBonus=%.2f, finalDirt=%.2f",
        tier, baseDirt, damageBonus, finalDirt))

    -- Apply dirt to all washable nodes
    local nodesApplied = 0
    for i = 1, #washable.washableNodes do
        local nodeData = washable.washableNodes[i]
        if nodeData then
            -- Add some per-node variation for more natural look
            local nodeVariation = (math.random() - 0.5) * 0.1  -- ±5% variation per node
            local nodeDirt = math.max(0, math.min(1, finalDirt + nodeVariation))

            -- Set the dirt amount directly on the node data
            nodeData.dirtAmount = nodeDirt
            -- Also set dirtAmountSent to trigger proper sync (fixes clean vehicle bug)
            nodeData.dirtAmountSent = nodeDirt

            -- Use vehicle's setNodeDirtAmount if available for visual update
            if vehicle.setNodeDirtAmount then
                vehicle:setNodeDirtAmount(nodeData, nodeDirt, true)
            end
            nodesApplied = nodesApplied + 1
        end
    end

    -- Force a visual update by calling setDirty on the spec if available
    if washable.setDirty then
        washable:setDirty()
    elseif vehicle.setDirty then
        vehicle:setDirty()
    end

    UsedPlus.logDebug(string.format("  Applied dirt to %d washable nodes", nodesApplied))
end

--[[
    Get spawn position near player
]]
function UsedVehicleManager:getVehicleSpawnPosition()
    if g_currentMission.player and g_currentMission.player.rootNode then
        local playerX, playerY, playerZ = getWorldTranslation(g_currentMission.player.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(g_currentMission.player.rootNode, 0, 0, 1)
        return playerX + dirX * 5, playerY, playerZ + dirZ * 5
    end
    -- Fallback to map center
    local mapSize = g_currentMission.terrainSize / 2
    return mapSize, 200, mapSize
end

--[[
    Remove a listing from the farm's available listings
    @param listing - The listing to remove
    @param farmId - Farm ID
]]
function UsedVehicleManager:removeListing(listing, farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleListings then
        for i, l in ipairs(farm.usedVehicleListings) do
            if l.id == listing.id then
                table.remove(farm.usedVehicleListings, i)
                break
            end
        end
    end
end

--[[
    Add listing to game's built-in vehicle sale system
    This makes the vehicle appear in the Used Equipment Dealer
    Returns: saleId or nil if failed
]]
function UsedVehicleManager:addToGameVehicleSaleSystem(listing)
    -- Check if game has vehicle sale system
    if g_currentMission.vehicleSaleSystem == nil then
        UsedPlus.logWarn("vehicleSaleSystem not available")
        return nil
    end

    -- Debug: List all methods on vehicleSaleSystem
    UsedPlus.logDebug("=== vehicleSaleSystem methods ===")
    for k, v in pairs(g_currentMission.vehicleSaleSystem) do
        UsedPlus.logDebug(string.format("  %s = %s", tostring(k), type(v)))
    end

    -- Also check metatable
    local mt = getmetatable(g_currentMission.vehicleSaleSystem)
    if mt and mt.__index then
        UsedPlus.logDebug("=== vehicleSaleSystem metatable methods ===")
        for k, v in pairs(mt.__index) do
            UsedPlus.logDebug(string.format("  %s = %s", tostring(k), type(v)))
        end
    end

    -- Convert operating hours to milliseconds (game format)
    local operatingTime = listing.operatingHours * 60 * 60 * 1000

    -- Create sale entry in game format (matching BuyUsedEquipment pattern EXACTLY)
    local saleEntry = {
        ["timeLeft"] = listing.expirationTTL or 72,
        ["isGenerated"] = false,
        ["xmlFilename"] = listing.storeItemIndex,
        ["boughtConfigurations"] = listing.configuration or {},
        ["age"] = listing.age,
        ["price"] = listing.price,
        ["damage"] = listing.damage,
        ["wear"] = listing.wear,
        ["operatingTime"] = operatingTime,
    }

    UsedPlus.logDebug(string.format("Creating sale entry: xmlFilename=%s, price=%.0f, age=%d, damage=%.2f, wear=%.2f, operatingTime=%d",
        saleEntry.xmlFilename, saleEntry.price, saleEntry.age, saleEntry.damage, saleEntry.wear, saleEntry.operatingTime))

    -- Add to game's vehicle sale system
    local success, result = pcall(function()
        return g_currentMission.vehicleSaleSystem:addSale(saleEntry)
    end)

    UsedPlus.logDebug(string.format("addSale result: success=%s, result=%s", tostring(success), tostring(result)))

    if success and result then
        UsedPlus.logDebug(string.format("Added to vehicleSaleSystem: saleId=%s", tostring(result)))
        return result
    else
        -- Log the actual error from pcall
        if not success then
            UsedPlus.logWarn(string.format("vehicleSaleSystem:addSale() error: %s", tostring(result)))
        else
            UsedPlus.logWarn("vehicleSaleSystem:addSale() returned nil - may need different API format")
        end
        return nil
    end
end

--[[
    Find configuration matching requested ID
    Compares configuration IDs from shop system
]]
function UsedVehicleManager:findMatchingConfiguration(storeItem, requestedConfigId)
    if storeItem.configurations == nil then
        return nil
    end

    -- Search through available configurations
    for _, config in ipairs(storeItem.configurations) do
        if config.id == requestedConfigId then
            return config
        end
    end

    return nil
end

--[[
    Generate random configurations for ALL available configuration types
    This makes used vehicles feel unique with random wheels, colors, designs, etc.
    Returns table like { wheel = 3, design = 2, color = 5, ... }
]]
function UsedVehicleManager:selectRandomConfiguration(storeItem)
    local randomConfigs = {}

    -- Get the vehicle's XML to find all available configurations
    local xmlFilename = storeItem.xmlFilename
    if xmlFilename == nil then
        UsedPlus.logDebug("selectRandomConfiguration: No xmlFilename, using empty config")
        return randomConfigs
    end

    -- Try to get configurations from ConfigurationUtil
    -- In FS25, vehicle configurations are stored per-xmlFilename
    local configSets = nil

    -- Method 1: Try to get from g_configurationManager if available
    if g_configurationManager and g_configurationManager.configurations then
        configSets = g_configurationManager.configurations[xmlFilename]
    end

    -- Method 2: Use storeItem.configurations directly (this is usually config presets)
    if configSets == nil and storeItem.configurations then
        -- storeItem.configurations may be a table of config TYPE names with their options
        -- Iterate and pick random values
        for configName, configData in pairs(storeItem.configurations) do
            if type(configData) == "table" then
                -- configData is an array of options - pick random index
                local numOptions = #configData
                if numOptions > 0 then
                    -- IMPORTANT: For wheel configs, skip index 1 if multiple options exist
                    -- because wheelConfiguration(0) is often a stub without proper wheel data
                    local minIndex = 1
                    if configName == "wheel" and numOptions > 1 then
                        minIndex = 2  -- Start from second option to avoid empty wheel configs
                    end
                    randomConfigs[configName] = math.random(minIndex, numOptions)
                    UsedPlus.logTrace(string.format("  Random config: %s = %d (of %d options, min=%d)",
                        configName, randomConfigs[configName], numOptions, minIndex))
                end
            elseif type(configData) == "number" then
                -- configData is the number of options - pick random
                if configData > 0 then
                    -- Same fix for wheel configs
                    local minIndex = 1
                    if configName == "wheel" and configData > 1 then
                        minIndex = 2
                    end
                    randomConfigs[configName] = math.random(minIndex, configData)
                end
            end
        end
    end

    -- Method 3: Use StoreItemUtil to get configuration items if available
    if next(randomConfigs) == nil and StoreItemUtil and StoreItemUtil.getConfigurationsFromXML then
        -- This might need the vehicle XML file loaded
        UsedPlus.logDebug("selectRandomConfiguration: Trying StoreItemUtil method")
    end

    -- Method 4: If vehicle type has known common configuration types, randomize those
    -- This is a fallback that covers common FS25 configuration types
    if next(randomConfigs) == nil then
        -- Common configuration types in FS25 - will only be used if the vehicle has them
        local commonConfigTypes = {
            "wheel", "design", "color", "rimColor", "baseColor",
            "frontLoader", "frontLoaderAttacher", "attacherJoint",
            "beacon", "wheels", "tire", "engine", "transmission"
        }

        -- Check if storeItem has configurationSets (preset combinations)
        if storeItem.configurationSets and #storeItem.configurationSets > 0 then
            -- Pick a random preset as our base
            local randomPreset = storeItem.configurationSets[math.random(1, #storeItem.configurationSets)]
            if randomPreset and randomPreset.configurations then
                for k, v in pairs(randomPreset.configurations) do
                    randomConfigs[k] = v
                end
                local presetCount = 0
                for _ in pairs(randomConfigs) do presetCount = presetCount + 1 end
                UsedPlus.logDebug(string.format("selectRandomConfiguration: Using random preset with %d configs", presetCount))
            end
        end
    end

    -- Count configurations
    local configCount = 0
    for _ in pairs(randomConfigs) do configCount = configCount + 1 end
    UsedPlus.logDebug(string.format("selectRandomConfiguration: Generated %d random configurations", configCount))

    return randomConfigs
end

--[[
    Create new search request
    Called from network event (client request → server execution)
    v1.5.0: Deducts retainer fee (small upfront cost), not percentage fee
]]
function UsedVehicleManager:createSearchRequest(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, requestedConfigId)
    if not self.isServer then
        UsedPlus.logError("createSearchRequest must be called on server")
        return nil
    end

    -- Validate search level (1 = local, 2 = regional, 3 = national)
    if searchLevel < 1 or searchLevel > 3 then
        UsedPlus.logError(string.format("Invalid search level %d", searchLevel))
        return nil
    end

    -- Create search object
    local search = UsedVehicleSearch.new(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, requestedConfigId)

    -- Assign unique ID
    search.id = self:generateSearchId()

    -- Register search
    self:registerSearch(search)

    -- v1.5.0: Deduct retainer fee (small upfront cost)
    -- Retainer is already calculated in UsedVehicleSearch.new()
    local farm = g_farmManager:getFarmById(farmId)
    g_currentMission:addMoney(-search.retainerFee, farmId, MoneyType.OTHER, true, true)

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "searchesStarted", 1)
        g_financeManager:incrementStatistic(farmId, "totalSearchFees", search.retainerFee)
    end

    UsedPlus.logDebug(string.format("Created search %s: %s ($%d retainer, %d%% commission, %d months)",
        search.id, storeItemName, search.retainerFee,
        math.floor((search.commissionPercent or 0.08) * 100), search.maxMonths or 1))

    return search
end

--[[
    Register search in manager and farm
    Adds to both global list and farm-specific list
    v1.5.0: Updated logging for monthly model
]]
function UsedVehicleManager:registerSearch(search)
    -- Add to global searches table
    self.activeSearches[search.id] = search

    -- Add to farm-specific searches table
    local farm = g_farmManager:getFarmById(search.farmId)
    if farm then
        if farm.usedVehicleSearches == nil then
            farm.usedVehicleSearches = {}
        end
        table.insert(farm.usedVehicleSearches, search)

        -- v1.5.0: Log monthly model parameters
        UsedPlus.logDebug(string.format("REGISTERED Search %s for farm %d - %d months, %.0f%% monthly success, max %d finds",
            search.id, search.farmId,
            search.maxMonths or 1,
            (search.monthlySuccessChance or 0.5) * 100,
            search.maxListings or 10))
        UsedPlus.logTrace(string.format("  Farm now has %d active searches", #farm.usedVehicleSearches))
    else
        UsedPlus.logError(string.format("Could not find farm %d to register search", search.farmId))
    end
end

--[[
    Generate unique search ID
    Format: "SEARCH_NNNNNNNN" (8-digit counter)
    Note: os.date() not available in FS25, using simple counter instead
]]
function UsedVehicleManager:generateSearchId()
    local id = string.format("SEARCH_%08d", self.nextSearchId)
    self.nextSearchId = self.nextSearchId + 1
    return id
end

--[[
    Generate unique listing ID
    Format: "LISTING_DAY_NNNN"
    Note: os.date() is NOT available in FS25 Lua, use game environment instead
]]
function UsedVehicleManager:generateListingId()
    -- Use in-game day instead of os.date() (which is nil in FS25)
    local currentDay = g_currentMission.environment.currentDay or 0
    local id = string.format("LISTING_D%d_%08d", currentDay, self.nextSearchId)

    self.nextSearchId = self.nextSearchId + 1

    return id
end

--[[
    Get all searches for a specific farm
    Returns array of searches (or empty array if none)
]]
function UsedVehicleManager:getSearchesForFarm(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleSearches then
        return farm.usedVehicleSearches
    end
    return {}
end

--[[
    Get all listings for a specific farm
    Returns array of available listings
]]
function UsedVehicleManager:getListingsForFarm(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleListings then
        return farm.usedVehicleListings
    end
    return {}
end

--[[
    Get search by ID
    Returns search or nil if not found
]]
function UsedVehicleManager:getSearchById(searchId)
    return self.activeSearches[searchId]
end

--[[
    End a search after a vehicle is purchased from it
    v1.7.1: Called when player buys from UsedVehiclePreviewDialog (direct purchase path)
    This ensures the search stops running when the player finds what they wanted

    @param searchId - The search ID to end
    @param farmId - Farm ID of the buyer
]]
function UsedVehicleManager:endSearchAfterPurchase(searchId, farmId)
    if searchId == nil then
        return
    end

    local search = self.activeSearches[searchId]
    if search == nil then
        UsedPlus.logDebug(string.format("endSearchAfterPurchase: search %s not found (may already be ended)", searchId))
        return
    end

    UsedPlus.logDebug(string.format("endSearchAfterPurchase: Ending search %s after vehicle purchase", searchId))

    -- Mark search as completed
    search.status = "completed"

    -- Remove from farm's search list
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleSearches then
        for i = #farm.usedVehicleSearches, 1, -1 do
            if farm.usedVehicleSearches[i].id == searchId then
                table.remove(farm.usedVehicleSearches, i)
                UsedPlus.logDebug(string.format("Removed search %s from farm %d", searchId, farmId))
                break
            end
        end
    end

    -- Remove from global registry
    self.activeSearches[searchId] = nil

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
    end

    UsedPlus.logDebug(string.format("Search %s ended after direct purchase", searchId))
end

--[[
    Complete a purchase from the portfolio browser
    v1.5.0: Called when player buys a vehicle from VehiclePortfolioDialog
    This ends the search - player gets one vehicle, remaining listings disappear

    @param search - The UsedVehicleSearch object
    @param listing - The portfolio listing being purchased
    @param farmId - Farm ID of the buyer
    @return boolean success
]]
function UsedVehicleManager:completePurchaseFromSearch(search, listing, farmId)
    if search == nil then
        UsedPlus.logError("completePurchaseFromSearch: search is nil")
        return false
    end

    if listing == nil then
        UsedPlus.logError("completePurchaseFromSearch: listing is nil")
        return false
    end

    UsedPlus.logDebug(string.format("completePurchaseFromSearch: %s buying from search %s",
        listing.id or "unknown", search.id or "unknown"))

    -- Build a full listing compatible with purchaseUsedVehicle
    local fullListing = {
        id = listing.id,
        farmId = farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,

        -- Vehicle condition
        damage = listing.damage or 0,
        wear = listing.wear or 0,
        age = listing.age or 1,
        operatingHours = listing.operatingHours or 0,

        -- Pricing (use asking price which includes commission)
        price = listing.askingPrice or listing.basePrice or 0,
        basePrice = listing.basePrice or 0,
        commissionAmount = listing.commissionAmount or 0,
        askingPrice = listing.askingPrice or 0,

        -- Configuration from search (random config was selected during generation)
        configuration = listing.configuration or {},

        -- Reliability data
        usedPlusData = listing.usedPlusData
    }

    -- Perform the purchase
    local success = self:purchaseUsedVehicle(fullListing, farmId)

    if success then
        -- Mark search as completed
        search.status = "completed"

        -- Remove from farm's search list
        local farm = g_farmManager:getFarmById(farmId)
        if farm and farm.usedVehicleSearches then
            for i = #farm.usedVehicleSearches, 1, -1 do
                if farm.usedVehicleSearches[i].id == search.id then
                    table.remove(farm.usedVehicleSearches, i)
                    UsedPlus.logDebug(string.format("Removed search %s from farm %d", search.id, farmId))
                    break
                end
            end
        end

        -- Remove from global registry
        self.activeSearches[search.id] = nil

        -- Track statistics
        if g_financeManager then
            g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
            g_financeManager:incrementStatistic(farmId, "commissionsPaid", listing.commissionAmount or 0)
        end

        UsedPlus.logDebug(string.format("Search %s completed via portfolio purchase - vehicle bought, search ended",
            search.id))

        -- Notify player
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("Search complete! Your %s has been delivered.", search.storeItemName or "vehicle")
        )
    end

    return success
end

--[[
    Cancel an active search
    Called from CancelSearchEvent - no refund (agent fee is sunk cost)
    Returns: true if cancelled, false if not found or not active
]]
function UsedVehicleManager:cancelSearch(searchId)
    if not self.isServer then
        UsedPlus.logError("cancelSearch must be called on server")
        return false
    end

    -- Find search in global registry
    local search = self.activeSearches[searchId]
    if search == nil then
        UsedPlus.logWarn(string.format("Search %s not found for cancellation", searchId))
        return false
    end

    -- Only cancel active searches
    if search.status ~= "active" then
        UsedPlus.logWarn(string.format("Search %s is not active (status: %s)", searchId, search.status))
        return false
    end

    -- Mark search as cancelled
    search:cancel()

    -- Remove from farm's search list
    local farm = g_farmManager:getFarmById(search.farmId)
    if farm and farm.usedVehicleSearches then
        for i = #farm.usedVehicleSearches, 1, -1 do
            if farm.usedVehicleSearches[i].id == searchId then
                table.remove(farm.usedVehicleSearches, i)
                break
            end
        end
    end

    -- Remove from global registry
    self.activeSearches[searchId] = nil

    -- Track cancelled statistic
    if g_financeManager then
        g_financeManager:incrementStatistic(search.farmId, "searchesCancelled", 1)
    end

    -- Send notification (no refund message)
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_searchCancelled"), search.storeItemName)
    )

    UsedPlus.logDebug(string.format("Search %s cancelled: %s (no refund)", searchId, search.storeItemName))

    return true
end

--[[
    Save all searches and listings to savegame
    Pattern from: BuyUsedEquipment nested XML serialization
]]
function UsedVehicleManager:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusVehicles.xml"
    local xmlFile = XMLFile.create("usedPlusVehiclesXML", filePath, "usedPlusVehicles")

    if xmlFile ~= nil then
        -- Save next ID counter
        xmlFile:setInt("usedPlusVehicles#nextSearchId", self.nextSearchId)

        -- Save searches and listings grouped by farm
        -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
        local farmIndex = 0
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            local hasSaveData = false

            -- Check if farm has searches or listings
            if (farm.usedVehicleSearches and #farm.usedVehicleSearches > 0) or
               (farm.usedVehicleListings and #farm.usedVehicleListings > 0) then
                hasSaveData = true
            end

            if hasSaveData then
                local farmKey = string.format("usedPlusVehicles.farms.farm(%d)", farmIndex)
                xmlFile:setInt(farmKey .. "#farmId", farmId)

                -- Save active searches
                if farm.usedVehicleSearches then
                    local searchIndex = 0
                    for _, search in ipairs(farm.usedVehicleSearches) do
                        local searchKey = string.format(farmKey .. ".search(%d)", searchIndex)
                        search:saveToXMLFile(xmlFile, searchKey)
                        searchIndex = searchIndex + 1
                    end
                end

                -- Save available listings
                if farm.usedVehicleListings then
                    local listingIndex = 0
                    for _, listing in ipairs(farm.usedVehicleListings) do
                        local listingKey = string.format(farmKey .. ".listing(%d)", listingIndex)
                        self:saveListingToXMLFile(xmlFile, listingKey, listing)
                        listingIndex = listingIndex + 1
                    end
                end

                farmIndex = farmIndex + 1
            end
        end

        xmlFile:save()
        xmlFile:delete()

        UsedPlus.logDebug(string.format("Saved %d searches and listings across %d farms",
            self:getTotalSearchCount(), farmIndex))
    end
end

--[[
    Save listing to XML
    Listings are tables, not objects, so manual serialization
]]
function UsedVehicleManager:saveListingToXMLFile(xmlFile, key, listing)
    xmlFile:setString(key .. "#id", listing.id)
    xmlFile:setInt(key .. "#farmId", listing.farmId)
    xmlFile:setString(key .. "#searchId", listing.searchId or "")
    -- storeItemIndex is actually the xmlFilename (string), NOT an integer!
    xmlFile:setString(key .. "#storeItemXmlFilename", listing.storeItemIndex)
    xmlFile:setString(key .. "#storeItemName", listing.storeItemName)

    -- Configuration (if present)
    if listing.configuration then
        xmlFile:setString(key .. "#configId", listing.configuration.id or "default")
        xmlFile:setString(key .. "#configName", listing.configuration.name or "Default")
    end

    -- Used vehicle stats
    xmlFile:setInt(key .. "#age", listing.age)
    xmlFile:setInt(key .. "#operatingHours", listing.operatingHours)
    xmlFile:setFloat(key .. "#damage", listing.damage)
    xmlFile:setFloat(key .. "#wear", listing.wear)
    xmlFile:setFloat(key .. "#price", listing.price)

    -- Metadata
    xmlFile:setString(key .. "#generationName", listing.generationName)
    xmlFile:setInt(key .. "#listingDate", listing.listingDate)
    xmlFile:setInt(key .. "#expirationTTL", listing.expirationTTL)
    xmlFile:setString(key .. "#status", listing.status)

    -- Hidden maintenance data (Phase 3)
    if listing.usedPlusData then
        xmlFile:setFloat(key .. "#engineReliability", listing.usedPlusData.engineReliability or 1.0)
        xmlFile:setFloat(key .. "#hydraulicReliability", listing.usedPlusData.hydraulicReliability or 1.0)
        xmlFile:setFloat(key .. "#electricalReliability", listing.usedPlusData.electricalReliability or 1.0)
        xmlFile:setBool(key .. "#wasInspected", listing.usedPlusData.wasInspected or false)
    end
end

--[[
    Load all searches and listings from savegame
    Reconstructs search and listing objects from XML data
]]
function UsedVehicleManager:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusVehicles.xml"
    local xmlFile = XMLFile.loadIfExists("usedPlusVehiclesXML", filePath, "usedPlusVehicles")

    if xmlFile ~= nil then
        -- Load next ID counter
        self.nextSearchId = xmlFile:getInt("usedPlusVehicles#nextSearchId", 1)

        -- Load searches and listings
        xmlFile:iterate("usedPlusVehicles.farms.farm", function(_, farmKey)
            local farmId = xmlFile:getInt(farmKey .. "#farmId")
            local farm = g_farmManager:getFarmById(farmId)

            if farm then
                -- Load searches
                xmlFile:iterate(farmKey .. ".search", function(_, searchKey)
                    local search = UsedVehicleSearch.new()
                    if search:loadFromXMLFile(xmlFile, searchKey) then
                        self:registerSearch(search)
                    end
                end)

                -- Load listings
                xmlFile:iterate(farmKey .. ".listing", function(_, listingKey)
                    local listing = self:loadListingFromXMLFile(xmlFile, listingKey)
                    if listing then
                        if not farm.usedVehicleListings then
                            farm.usedVehicleListings = {}
                        end
                        table.insert(farm.usedVehicleListings, listing)
                    end
                end)
            end
        end)

        xmlFile:delete()

        UsedPlus.logDebug(string.format("Loaded %d searches from savegame", self:getTotalSearchCount()))
    else
        UsedPlus.logDebug("No saved vehicle data found (new game)")
    end
end

--[[
    Load listing from XML
    Manual reconstruction of listing table
]]
function UsedVehicleManager:loadListingFromXMLFile(xmlFile, key)
    local listing = {}

    listing.id = xmlFile:getString(key .. "#id")
    listing.farmId = xmlFile:getInt(key .. "#farmId")
    listing.searchId = xmlFile:getString(key .. "#searchId")
    -- storeItemIndex is actually the xmlFilename (string), NOT an integer!
    -- Try new attribute name first, fall back to old for save compatibility
    listing.storeItemIndex = xmlFile:getString(key .. "#storeItemXmlFilename")
    if listing.storeItemIndex == nil or listing.storeItemIndex == "" then
        -- Old saves might have it as storeItemIndex (incorrectly as int, would be nil)
        listing.storeItemIndex = xmlFile:getString(key .. "#storeItemIndex")
    end
    listing.storeItemName = xmlFile:getString(key .. "#storeItemName")

    -- Configuration
    local configId = xmlFile:getString(key .. "#configId")
    if configId then
        listing.configuration = {
            id = configId,
            name = xmlFile:getString(key .. "#configName", "Default")
        }
    end

    -- Used vehicle stats
    listing.age = xmlFile:getInt(key .. "#age", 0)
    listing.operatingHours = xmlFile:getInt(key .. "#operatingHours", 0)
    listing.damage = xmlFile:getFloat(key .. "#damage", 0)
    listing.wear = xmlFile:getFloat(key .. "#wear", 0)
    listing.price = xmlFile:getFloat(key .. "#price", 0)

    -- Metadata
    listing.generationName = xmlFile:getString(key .. "#generationName", "Unknown")
    listing.listingDate = xmlFile:getInt(key .. "#listingDate", 0)
    listing.expirationTTL = xmlFile:getInt(key .. "#expirationTTL", 72)
    listing.status = xmlFile:getString(key .. "#status", "available")

    -- Hidden maintenance data (Phase 3)
    local engineReliability = xmlFile:getFloat(key .. "#engineReliability", nil)
    if engineReliability ~= nil then
        listing.usedPlusData = {
            engineReliability = engineReliability,
            hydraulicReliability = xmlFile:getFloat(key .. "#hydraulicReliability", 1.0),
            electricalReliability = xmlFile:getFloat(key .. "#electricalReliability", 1.0),
            wasInspected = xmlFile:getBool(key .. "#wasInspected", false)
        }
    end

    -- Validate required fields
    if listing.id == nil or listing.storeItemIndex == nil then
        UsedPlus.logWarn(string.format("Invalid listing data at %s", key))
        return nil
    end

    return listing
end

--[[
    Get total count of all active searches
]]
function UsedVehicleManager:getTotalSearchCount()
    local count = 0
    for _ in pairs(self.activeSearches) do
        count = count + 1
    end
    return count
end

--[[
    Cleanup on mission unload
]]
function UsedVehicleManager:delete()
    -- Unsubscribe from events
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.HOUR_CHANGED, self)
    end

    -- Clear data
    self.activeSearches = {}
    self.pendingUsedPurchases = {}

    UsedPlus.logDebug("UsedVehicleManager cleaned up")
end

--[[
    Hook for BuyVehicleData.onBought - called when any vehicle purchase completes
    This is where we apply used condition to vehicles purchased through our system
    Pattern from: FS25_HirePurchasing BuyVehicleDataExtension
]]
function UsedVehicleManager.onVehicleBought(buyVehicleData, loadedVehicles, loadingState, callbackArguments)
    -- Only process on successful load
    if loadingState ~= VehicleLoadingState.OK then
        UsedPlus.logDebug(string.format("onVehicleBought: loadingState not OK (%s), skipping", tostring(loadingState)))
        return
    end

    -- Check if we have a manager instance
    if g_usedVehicleManager == nil then
        return
    end

    -- Check if there are any pending used purchases
    if g_usedVehicleManager.pendingUsedPurchases == nil or
       next(g_usedVehicleManager.pendingUsedPurchases) == nil then
        return
    end

    UsedPlus.logDebug(string.format("onVehicleBought: Processing %d loaded vehicles", #loadedVehicles))

    -- Get the storeItem from the buyVehicleData
    local storeItem = buyVehicleData.storeItem
    if storeItem == nil then
        UsedPlus.logDebug("onVehicleBought: No storeItem in buyVehicleData")
        return
    end

    local xmlFilename = storeItem.xmlFilename
    local farmId = buyVehicleData.ownerFarmId

    UsedPlus.logDebug(string.format("onVehicleBought: Checking for pending purchase - xml=%s, farmId=%s",
        tostring(xmlFilename), tostring(farmId)))

    -- Find matching pending purchase
    local matchedKey = nil
    local pendingData = nil
    for key, data in pairs(g_usedVehicleManager.pendingUsedPurchases) do
        if data.xmlFilename == xmlFilename and data.farmId == farmId then
            matchedKey = key
            pendingData = data
            break
        end
    end

    if matchedKey == nil then
        UsedPlus.logDebug("onVehicleBought: No matching pending purchase found (normal shop purchase)")
        return
    end

    UsedPlus.logDebug(string.format("onVehicleBought: Found pending purchase %s, applying used condition", matchedKey))

    -- Apply used condition to all loaded vehicles (usually just one)
    for _, vehicle in ipairs(loadedVehicles) do
        g_usedVehicleManager:applyUsedConditionToVehicle(vehicle, pendingData.listing)
        UsedPlus.logDebug(string.format("Applied used condition to vehicle: %s", tostring(vehicle.typeName)))
    end

    -- Remove from pending purchases
    g_usedVehicleManager.pendingUsedPurchases[matchedKey] = nil
    UsedPlus.logDebug("Pending purchase processed and removed")
end

-- Install the hook when this file loads
if BuyVehicleData ~= nil and BuyVehicleData.onBought ~= nil then
    BuyVehicleData.onBought = Utils.appendedFunction(BuyVehicleData.onBought, UsedVehicleManager.onVehicleBought)
    UsedPlus.logInfo("UsedVehicleManager: Hooked into BuyVehicleData.onBought")
else
    UsedPlus.logWarn("UsedVehicleManager: BuyVehicleData.onBought not available for hooking")
end

UsedPlus.logInfo("UsedVehicleManager loaded")
