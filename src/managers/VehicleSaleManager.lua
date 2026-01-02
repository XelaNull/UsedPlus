--[[
    FS25_UsedPlus - Vehicle Sale Manager

    VehicleSaleManager handles agent-based vehicle sales queue
    Pattern mirrors UsedVehicleManager but for SELLING instead of BUYING
    Replaces vanilla instant-sell with time-based agent system

    Responsibilities:
    - Track all active sale listings across all farms
    - Process sale queue hourly (subscribe to HOUR_CHANGED)
    - Update TTL/TTS counters for each listing
    - Generate sale offers when TTS reached
    - Handle accept/decline of offers
    - Send notifications for offers, sales, expirations
    - Save/load sale listings to savegame
    - Remove vehicle from farm when sold

    v1.9.7: Queue-based offer presentation
    - Added offerShownToUser flag to prevent race conditions
    - showNextPendingOffer() ensures offers are shown one at a time
    - After each dialog closes, checks for more pending offers
    - Handles case where multiple offers arrive in same tick

    This is a global singleton: g_vehicleSaleManager
]]

VehicleSaleManager = {}
local VehicleSaleManager_mt = Class(VehicleSaleManager)

-- Maximum concurrent sale listings per farm (default, overridden by settings)
VehicleSaleManager.MAX_LISTINGS_PER_FARM = 3

--[[
    Get maximum allowed sale listings per farm from settings
    @return number - max listings allowed
]]
function VehicleSaleManager.getMaxListingsPerFarm()
    return UsedPlusSettings and UsedPlusSettings:get("maxListingsPerFarm") or VehicleSaleManager.MAX_LISTINGS_PER_FARM
end

--[[
    Constructor
    Creates manager instance with empty data structures
]]
function VehicleSaleManager.new()
    local self = setmetatable({}, VehicleSaleManager_mt)

    -- Data structures
    self.activeListings = {}  -- All listings indexed by ID
    self.nextListingId = 1

    -- Event subscriptions
    self.isServer = false
    self.isClient = false

    -- v1.9.7: Flag to check for pending offers on first hour tick after load
    self.checkPendingOnFirstTick = false

    return self
end

--[[
    Initialize manager after mission loads
    Subscribe to hourly events for queue processing
]]
function VehicleSaleManager:loadMapFinished()
    -- Set server/client status
    if g_currentMission then
        self.isServer = g_currentMission:getIsServer()
        self.isClient = g_currentMission:getIsClient()
    end

    if self.isServer then
        -- Subscribe to hourly game time for TTL/TTS countdown
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
        UsedPlus.logDebug("VehicleSaleManager subscribed to HOUR_CHANGED")
    end

    -- v1.9.7: Check for any pending offers that weren't shown before save
    -- Subscribe to HOUR_CHANGED on client to check for pending offers after first hour tick
    -- This ensures UI is ready before showing dialogs
    if self.isClient and not self.isServer then
        self.checkPendingOnFirstTick = true
    elseif self.isClient then
        -- In single-player (both server and client), check on first hour tick
        self.checkPendingOnFirstTick = true
    end
end

--[[
    Hourly queue processing
    Called automatically when in-game hour changes
    Updates all listings, generates offers, handles expirations
]]
function VehicleSaleManager:onHourChanged()
    if not self.isServer then return end

    -- v1.9.7: Check for pending offers from previous session on first tick
    if self.checkPendingOnFirstTick then
        self.checkPendingOnFirstTick = false
        local shown = self:showNextPendingOffer()
        if shown then
            UsedPlus.logDebug("onHourChanged: Showed pending offer from previous session")
        end
    end

    local totalListings = self:getTotalListingCount()
    UsedPlus.logTrace(string.format("HOUR_CHANGED - Processing sale queue (total active: %d)", totalListings))

    -- Process all active listings
    -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        if farm.vehicleSaleListings and #farm.vehicleSaleListings > 0 then
            UsedPlus.logTrace(string.format("  Farm %d has %d sale listings", farmId, #farm.vehicleSaleListings))
            self:processListingsForFarm(farmId, farm)
        end
    end
end

--[[
    Process listings for a single farm
    Iterate backwards to safely remove completed listings
]]
function VehicleSaleManager:processListingsForFarm(farmId, farm)
    -- Iterate backwards for safe removal
    for i = #farm.vehicleSaleListings, 1, -1 do
        local listing = farm.vehicleSaleListings[i]

        if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
            -- Log before update
            UsedPlus.logTrace(string.format("    Listing %s: %s - TTL=%d, TTS=%d, Status=%s",
                listing.id, listing.vehicleName, listing.ttl, listing.tts, listing.status))

            -- Update listing (decrements TTL/TTS, checks offer expiration)
            local event = listing:update()

            -- Handle events
            if event == "offer" then
                -- New offer generated
                self:onOfferReceived(farmId, listing)

            elseif event == "offer_expired" then
                -- Player didn't respond in time
                self:onOfferExpired(farmId, listing)

            elseif event == "expired" then
                -- Listing expired without accepted offer
                self:onListingExpired(farmId, listing, i)
            end

            -- Check if listing is complete (sold or expired)
            if listing:isComplete() then
                -- Remove from active listings (keep in history for UI)
                self.activeListings[listing.id] = nil
            end
        end
    end
end

--[[
    Handle new offer received
    v1.9.7: Refactored to use queue-based presentation pattern
    - Sends notification to alert player
    - Calls showNextPendingOffer() which checks offerShownToUser flag
    - This prevents race conditions when multiple offers arrive in same tick
]]
function VehicleSaleManager:onOfferReceived(farmId, listing)
    UsedPlus.logDebug(string.format("onOfferReceived ENTERED for %s: $%d",
        listing.vehicleName, listing.currentOffer))

    -- Check if game is ready
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logDebug("onOfferReceived: Skipping - mission not ready or loading")
        return
    end

    -- Step 1: Show notification to alert the player (always)
    local notifyMessage = string.format(
        g_i18n:getText("usedplus_notify_saleOffer") or "Buyer found for %s! Offering %s",
        listing.vehicleName,
        g_i18n:formatMoney(listing.currentOffer, 0, true, true)
    )
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        notifyMessage
    )

    -- Step 2: Determine if we should show dialog for this farm
    local playerFarmId = nil
    if g_currentMission.player and g_currentMission.player.farmId then
        playerFarmId = g_currentMission.player.farmId
    elseif g_currentMission.playerUserId then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        if farm then
            playerFarmId = farm.farmId
        end
    end
    if playerFarmId == nil and g_currentMission:getIsServer() then
        playerFarmId = 1  -- Default farm in single-player
    end

    local isLocalFarm = (playerFarmId ~= nil and playerFarmId == farmId)
    local isSinglePlayer = g_currentMission:getIsServer() and not g_currentMission.missionDynamicInfo.isMultiplayer
    local shouldShowDialog = isSinglePlayer or isLocalFarm

    UsedPlus.logDebug(string.format("onOfferReceived: farmId=%s, playerFarmId=%s, shouldShow=%s",
        tostring(farmId), tostring(playerFarmId), tostring(shouldShowDialog)))

    -- Step 3: Use queue-based presentation - showNextPendingOffer checks offerShownToUser flag
    -- This ensures if another dialog is open, this offer waits its turn
    if shouldShowDialog then
        self:showNextPendingOffer(farmId)
    end
end

--[[
    Handle offer that expired without response
    Listing may continue if time remains
]]
function VehicleSaleManager:onOfferExpired(farmId, listing)
    UsedPlus.logDebug(string.format("Offer expired for %s", listing.vehicleName))

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format("Offer expired for %s. Agent continues searching...", listing.vehicleName)
    )
end

--[[
    Show the next pending offer that hasn't been shown to user yet
    Called after dialog closes to ensure all offers are eventually presented
    v1.9.7: Added to fix race condition when multiple offers arrive in same tick
    @param farmId - Optional farm ID to filter by, nil = check all farms
    @return true if a dialog was shown
]]
function VehicleSaleManager:showNextPendingOffer(farmId)
    -- Check if game is ready
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logTrace("showNextPendingOffer: Skipping - mission not ready")
        return false
    end

    -- Determine which farm to check
    local targetFarmId = farmId

    -- If no farm specified, get player's farm
    if targetFarmId == nil then
        if g_currentMission.player and g_currentMission.player.farmId then
            targetFarmId = g_currentMission.player.farmId
        elseif g_currentMission.playerUserId then
            local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
            if farm then
                targetFarmId = farm.farmId
            end
        end
        -- In single-player, assume farm 1 if still nil
        if targetFarmId == nil and g_currentMission:getIsServer() then
            targetFarmId = 1
        end
    end

    if targetFarmId == nil then
        UsedPlus.logTrace("showNextPendingOffer: Could not determine farm ID")
        return false
    end

    -- Find listings with pending offers that haven't been shown
    local farm = g_farmManager:getFarmById(targetFarmId)
    if farm == nil or farm.vehicleSaleListings == nil then
        return false
    end

    for _, listing in ipairs(farm.vehicleSaleListings) do
        if listing:hasPendingOffer() and not listing.offerShownToUser then
            -- Found an unshown offer - show it now
            UsedPlus.logDebug(string.format("showNextPendingOffer: Showing offer for %s ($%d)",
                listing.vehicleName, listing.currentOffer))

            -- Mark as shown BEFORE opening dialog to prevent re-entry
            listing.offerShownToUser = true

            -- Create callback
            local listingId = listing.id
            local self_ref = self  -- Capture self for callback closure
            local callback = function(accepted)
                UsedPlus.logDebug(string.format("SaleOfferDialog callback: accepted=%s, listingId=%s",
                    tostring(accepted), tostring(listingId)))
                if accepted then
                    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_ACCEPT)
                else
                    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_DECLINE)
                end

                -- After handling this offer, check for more pending offers
                -- Use a small delay to let the UI settle
                if self_ref then
                    self_ref:showNextPendingOffer(targetFarmId)
                end
            end

            -- Show the dialog
            if DialogLoader and DialogLoader.show then
                DialogLoader.show("SaleOfferDialog", "setListing", listing, callback)
                return true
            end
        end
    end

    UsedPlus.logTrace("showNextPendingOffer: No unshown pending offers found")
    return false
end

--[[
    Handle listing expiration
    Vehicle is returned to player (stays in inventory), fee lost
]]
function VehicleSaleManager:onListingExpired(farmId, listing, listingIndex)
    UsedPlus.logDebug(string.format("Listing expired for %s", listing.vehicleName))

    -- Show popup dialog instead of notification
    if SaleExpiredDialog then
        local callback = function(relistChoice)
            if relistChoice then
                -- Player wants to relist - show SellVehicleDialog
                local vehicle = listing.vehicle
                if vehicle and DialogLoader then
                    local sellCallback = function(agentTier, priceTier)
                        if agentTier ~= nil then
                            -- Create new listing
                            local newListing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier or 2)
                            if newListing then
                                UsedPlus.logInfo(string.format("Relisted %s with agent tier %d, price tier %d",
                                    newListing.vehicleName, agentTier, priceTier))
                            end
                        end
                    end
                    DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, sellCallback)
                else
                    -- Vehicle not available, just show notification
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        "Vehicle no longer available to relist."
                    )
                end
            end
            -- If not relisting, nothing more to do - vehicle stays in inventory
        end

        SaleExpiredDialog.showWithListing(listing, callback)
    else
        -- Fallback to notification if dialog not loaded
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("No buyer found for %s. Agent fee ($%d) was non-refundable.",
                listing.vehicleName, listing.agentFee)
        )
    end

    -- Note: We don't remove from farm.vehicleSaleListings here
    -- It stays with "expired" status for history/UI purposes
    -- Clean up old expired listings periodically
end

--[[
    Create new sale listing
    Called from SellVehicleDialog when player selects agent tier
    @param farmId - Farm that owns the vehicle
    @param vehicle - The vehicle object to sell
    @param agentTier - Agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Price tier (1=Quick, 2=Market, 3=Premium) - optional, defaults to 2
    @return listing or nil on failure
]]
function VehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier)
    if not self.isServer then
        UsedPlus.logError("createSaleListing must be called on server")
        return nil
    end

    -- Default priceTier for legacy compatibility
    priceTier = priceTier or 2

    -- Validate vehicle
    if vehicle == nil then
        UsedPlus.logError("Cannot create listing for nil vehicle")
        return nil
    end

    -- Validate agent tier (0=Private, 1-3=Professional agents)
    if agentTier < 0 or agentTier > 3 then
        UsedPlus.logError(string.format("Invalid agent tier %d", agentTier))
        return nil
    end

    -- Validate price tier (1=Quick, 2=Market, 3=Premium)
    if priceTier < 1 or priceTier > 3 then
        UsedPlus.logError(string.format("Invalid price tier %d", priceTier))
        return nil
    end

    -- Check vehicle is owned and not already listed
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError("Vehicle not owned by this farm")
        return nil
    end

    if self:isVehicleListed(vehicle) then
        UsedPlus.logError("Vehicle is already listed for sale")
        return nil
    end

    -- Check listing limit (UI only supports 3 rows)
    local canCreate, currentCount, maxAllowed = self:canCreateListing(farmId)
    if not canCreate then
        UsedPlus.logError(string.format("Farm %d already has maximum sale listings (%d/%d)", farmId, currentCount, maxAllowed))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_maxSaleListings") or "Maximum %d vehicles can be listed for sale at once.", maxAllowed)
        )
        return nil
    end

    -- Check vehicle is not leased (cannot sell leased vehicles at all)
    if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
        UsedPlus.logError("Cannot sell leased vehicle")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            g_i18n:getText("usedplus_error_cannotSellLeasedVehicle")
        )
        return nil
    end

    -- Check vehicle is not financed
    if TradeInCalculations and TradeInCalculations.isVehicleFinanced then
        if TradeInCalculations.isVehicleFinanced(vehicle, farmId) then
            UsedPlus.logError("Cannot sell financed vehicle")
            return nil
        end
    end

    -- Create listing using factory method
    local listing = VehicleSaleListing.createFromVehicle(farmId, vehicle, agentTier, priceTier)
    if listing == nil then
        UsedPlus.logError("Failed to create listing from vehicle")
        return nil
    end

    -- Assign unique ID
    listing.id = self:generateListingId()

    -- Register listing
    self:registerListing(listing)

    -- Deduct agent fee
    g_currentMission:addMoney(-listing.agentFee, farmId, MoneyType.OTHER, true, true)

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "salesListed", 1)
    end

    UsedPlus.logDebug(string.format("Created sale listing %s: %s ($%d fee, %d hrs TTL, Agent: %s, Price: %s)",
        listing.id, listing.vehicleName, listing.agentFee, listing.ttl,
        listing:getAgentTierName(), listing:getPriceTierName()))

    -- Note: Confirmation notification now handled by SaleListingInitiatedDialog
    -- No inline notification here to avoid duplicate feedback

    return listing
end

--[[
    Register listing in manager and farm
]]
function VehicleSaleManager:registerListing(listing)
    -- Add to global listings table
    self.activeListings[listing.id] = listing

    -- Add to farm-specific listings table
    local farm = g_farmManager:getFarmById(listing.farmId)
    if farm then
        if farm.vehicleSaleListings == nil then
            farm.vehicleSaleListings = {}
        end
        table.insert(farm.vehicleSaleListings, listing)

        UsedPlus.logDebug(string.format("REGISTERED Listing %s for farm %d - TTL=%d, TTS=%d",
            listing.id, listing.farmId, listing.ttl, listing.tts))
        UsedPlus.logTrace(string.format("  Farm now has %d active sale listings", #farm.vehicleSaleListings))
    else
        UsedPlus.logError(string.format("Could not find farm %d to register listing", listing.farmId))
    end
end

--[[
    Accept current offer on a listing
    Deletes vehicle and credits money to farm
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:acceptOffer(listingId)
    if not self.isServer then
        UsedPlus.logError("acceptOffer must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    if not listing:hasPendingOffer() then
        UsedPlus.logError(string.format("Listing %s has no pending offer", listingId))
        return false
    end

    -- Get sale price before accepting
    local grossSalePrice = listing.currentOffer
    local farmId = listing.farmId
    local vehicleName = listing.vehicleName
    local vehicleId = listing.vehicleId

    -- Calculate agent commission from settings (default 8%)
    local commissionPercent = UsedPlusSettings and UsedPlusSettings:get("agentCommissionPercent") or 8
    local agentCommission = math.floor(grossSalePrice * (commissionPercent / 100))
    local netSalePrice = grossSalePrice - agentCommission

    -- Accept the offer (updates listing status)
    listing:acceptOffer()

    -- Find and delete the vehicle
    local vehicleDeleted = self:deleteVehicleById(vehicleId)
    if not vehicleDeleted then
        UsedPlus.logWarn(string.format("Could not find vehicle to delete for listing %s", listingId))
        -- Continue anyway - money should still be credited
    end

    -- Credit NET sale price to farm (after agent commission)
    g_currentMission:addMoney(netSalePrice, farmId, MoneyType.VEHICLE_SELL, true, true)

    -- Track statistics (record gross sale for reporting)
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "salesCompleted", 1)
        g_financeManager:incrementStatistic(farmId, "totalSaleProceeds", grossSalePrice)
        g_financeManager:incrementStatistic(farmId, "totalAgentCommissions", agentCommission)
    end

    -- Remove from active listings
    self.activeListings[listingId] = nil

    -- Send notification showing gross, commission, and net
    local notificationMsg = string.format("SOLD: %s\nGross: %s | Commission: %s (%d%%)\nNet: %s",
        vehicleName,
        g_i18n:formatMoney(grossSalePrice, 0, true, true),
        g_i18n:formatMoney(agentCommission, 0, true, true),
        commissionPercent,
        g_i18n:formatMoney(netSalePrice, 0, true, true))
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationMsg)

    UsedPlus.logDebug(string.format("Sale completed: %s sold for $%d (net $%d after %d%% commission)",
        vehicleName, grossSalePrice, netSalePrice, commissionPercent))

    return true
end

--[[
    Decline current offer on a listing
    Listing continues, may receive more offers if time remains
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:declineOffer(listingId)
    if not self.isServer then
        UsedPlus.logError("declineOffer must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    if not listing:hasPendingOffer() then
        UsedPlus.logError(string.format("Listing %s has no pending offer to decline", listingId))
        return false
    end

    -- Decline the offer
    local declinedAmount = listing.currentOffer
    listing:declineOffer()

    -- Send notification
    if listing:isActive() then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("Declined %s offer for %s. Agent continues searching...",
                g_i18n:formatMoney(declinedAmount, 0, true, true), listing.vehicleName)
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("Declined offer for %s. Listing has expired.", listing.vehicleName)
        )
    end

    UsedPlus.logDebug(string.format("Offer declined for %s. Status: %s, TTL: %d",
        listing.vehicleName, listing.status, listing.ttl))

    return true
end

--[[
    Cancel a sale listing
    Vehicle stays in inventory, agent fee is NOT refunded
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:cancelListing(listingId)
    if not self.isServer then
        UsedPlus.logError("cancelListing must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    if listing:isComplete() then
        UsedPlus.logError(string.format("Listing %s is already complete", listingId))
        return false
    end

    -- Cancel the listing
    listing:cancel()

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(listing.farmId, "salesCancelled", 1)
    end

    -- Remove from active listings
    self.activeListings[listingId] = nil

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format("Cancelled sale listing for %s. Agent fee ($%d) was non-refundable.",
            listing.vehicleName, listing.agentFee)
    )

    UsedPlus.logDebug(string.format("Listing cancelled: %s", listing.vehicleName))

    return true
end

--[[
    Modify the asking price of an active listing
    Only allowed when listing is in "searching" status (no active offer)
    @param listingId - The listing ID
    @param newPrice - The new asking price
    @return true on success
]]
function VehicleSaleManager:modifyAskingPrice(listingId, newPrice)
    if not self.isServer then
        UsedPlus.logError("modifyAskingPrice must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    -- Can only modify if in searching status (no pending offer)
    if listing.status ~= "searching" then
        UsedPlus.logError(string.format("Listing %s cannot be modified - status is %s", listingId, listing.status))
        return false
    end

    -- Validate new price (must be positive and reasonable)
    if newPrice == nil or newPrice <= 0 then
        UsedPlus.logError("Invalid price: must be greater than 0")
        return false
    end

    -- Store old price for logging
    local oldPrice = listing.askingPrice

    -- Update the asking price
    listing.askingPrice = newPrice

    -- Recalculate price tier based on new price vs fair market value
    if listing.fairMarketValue and listing.fairMarketValue > 0 then
        local priceRatio = newPrice / listing.fairMarketValue
        if priceRatio <= 0.85 then
            listing.priceTier = 1  -- Quick Sale
        elseif priceRatio <= 1.05 then
            listing.priceTier = 2  -- Market Price
        else
            listing.priceTier = 3  -- Premium
        end
    end

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Updated asking price for %s: %s -> %s",
            listing.vehicleName,
            g_i18n:formatMoney(oldPrice, 0, true, true),
            g_i18n:formatMoney(newPrice, 0, true, true))
    )

    UsedPlus.logDebug(string.format("Listing %s price modified: $%.0f -> $%.0f", listingId, oldPrice, newPrice))

    return true
end

--[[
    Delete vehicle by ID
    Finds vehicle in mission and removes it
    @param vehicleId - The vehicle ID (from vehicle.id)
    @return true if vehicle was found and deleted
]]
function VehicleSaleManager:deleteVehicleById(vehicleId)
    if vehicleId == nil or vehicleId == "" then
        return false
    end

    -- Search through all vehicles
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if tostring(vehicle.id) == tostring(vehicleId) then
                if vehicle.delete then
                    vehicle:delete()
                    UsedPlus.logTrace(string.format("Deleted vehicle ID: %s", tostring(vehicleId)))
                    return true
                end
            end
        end
    end

    return false
end

--[[
    Check if a vehicle is already listed for sale
    @param vehicle - The vehicle object
    @return true if vehicle has an active listing
]]
function VehicleSaleManager:isVehicleListed(vehicle)
    if vehicle == nil then return false end

    local vehicleId = tostring(vehicle.id)

    for _, listing in pairs(self.activeListings) do
        if listing.vehicleId and tostring(listing.vehicleId) == vehicleId then
            if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                return true
            end
        end
    end

    return false
end

--[[
    Generate unique listing ID
    Format: "SALE_NNNNNNNN" (8-digit counter)
]]
function VehicleSaleManager:generateListingId()
    local id = string.format("SALE_%08d", self.nextListingId)
    self.nextListingId = self.nextListingId + 1
    return id
end

--[[
    Get all listings for a specific farm
    @param farmId - The farm ID
    @param activeOnly - If true, only return active/pending listings
    @return Array of listings
]]
function VehicleSaleManager:getListingsForFarm(farmId, activeOnly)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.vehicleSaleListings then
        if activeOnly then
            local active = {}
            for _, listing in ipairs(farm.vehicleSaleListings) do
                if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                    table.insert(active, listing)
                end
            end
            return active
        else
            return farm.vehicleSaleListings
        end
    end
    return {}
end

--[[
    Check if farm can create more sale listings
    @param farmId - The farm ID
    @return canCreate (bool), currentCount, maxAllowed
]]
function VehicleSaleManager:canCreateListing(farmId)
    local activeListings = self:getListingsForFarm(farmId, true)  -- true = active only
    local currentCount = #activeListings
    local maxAllowed = VehicleSaleManager.getMaxListingsPerFarm()
    return currentCount < maxAllowed, currentCount, maxAllowed
end

--[[
    Get listing by ID
    @return listing or nil
]]
function VehicleSaleManager:getListingById(listingId)
    return self.activeListings[listingId]
end

--[[
    Get count of listings with pending offers for a farm
    @return count of pending offers
]]
function VehicleSaleManager:getPendingOfferCount(farmId)
    local count = 0
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.vehicleSaleListings then
        for _, listing in ipairs(farm.vehicleSaleListings) do
            if listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                count = count + 1
            end
        end
    end
    return count
end

--[[
    Get total count of all active listings
]]
function VehicleSaleManager:getTotalListingCount()
    local count = 0
    for _ in pairs(self.activeListings) do
        count = count + 1
    end
    return count
end

--[[
    Save all listings to savegame
]]
function VehicleSaleManager:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusSales.xml"
    local xmlFile = XMLFile.create("usedPlusSalesXML", filePath, "usedPlusSales")

    if xmlFile ~= nil then
        -- Save next ID counter
        xmlFile:setInt("usedPlusSales#nextListingId", self.nextListingId)

        -- Save listings grouped by farm
        -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
        local farmIndex = 0
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            if farm.vehicleSaleListings and #farm.vehicleSaleListings > 0 then
                local farmKey = string.format("usedPlusSales.farms.farm(%d)", farmIndex)
                xmlFile:setInt(farmKey .. "#farmId", farmId)

                -- Save all listings (including completed for history)
                local listingIndex = 0
                for _, listing in ipairs(farm.vehicleSaleListings) do
                    local listingKey = string.format(farmKey .. ".listing(%d)", listingIndex)
                    listing:saveToXMLFile(xmlFile, listingKey)
                    listingIndex = listingIndex + 1
                end

                farmIndex = farmIndex + 1
            end
        end

        xmlFile:save()
        xmlFile:delete()

        UsedPlus.logDebug(string.format("Saved %d sale listings across %d farms",
            self:getTotalListingCount(), farmIndex))
    end
end

--[[
    Load all listings from savegame
]]
function VehicleSaleManager:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusSales.xml"
    local xmlFile = XMLFile.loadIfExists("usedPlusSalesXML", filePath, "usedPlusSales")

    if xmlFile ~= nil then
        -- Load next ID counter
        self.nextListingId = xmlFile:getInt("usedPlusSales#nextListingId", 1)

        -- Load listings
        xmlFile:iterate("usedPlusSales.farms.farm", function(_, farmKey)
            local farmId = xmlFile:getInt(farmKey .. "#farmId")
            local farm = g_farmManager:getFarmById(farmId)

            if farm then
                if farm.vehicleSaleListings == nil then
                    farm.vehicleSaleListings = {}
                end

                -- Load listings
                xmlFile:iterate(farmKey .. ".listing", function(_, listingKey)
                    local listing = setmetatable({}, {__index = VehicleSaleListing})
                    if listing:loadFromXMLFile(xmlFile, listingKey) then
                        table.insert(farm.vehicleSaleListings, listing)

                        -- Re-register active listings
                        if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                            self.activeListings[listing.id] = listing
                        end
                    end
                end)
            end
        end)

        xmlFile:delete()

        UsedPlus.logDebug(string.format("Loaded %d sale listings from savegame", self:getTotalListingCount()))
    else
        UsedPlus.logDebug("No saved sale data found (new game)")
    end
end

--[[
    Cleanup on mission unload
]]
function VehicleSaleManager:delete()
    -- Unsubscribe from events
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.HOUR_CHANGED, self)
    end

    -- Clear data
    self.activeListings = {}

    UsedPlus.logDebug("VehicleSaleManager cleaned up")
end

UsedPlus.logInfo("VehicleSaleManager loaded")
