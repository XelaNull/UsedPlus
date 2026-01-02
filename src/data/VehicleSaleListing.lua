--[[
    FS25_UsedPlus - Vehicle Sale Listing Data Class

    VehicleSaleListing represents a vehicle listed for sale through an agent
    Pattern mirrors UsedVehicleSearch but for SELLING instead of BUYING
    Player selects BOTH agent tier AND price tier for 2D control

    v1.9.7: Added offerShownToUser flag to prevent race conditions when
    multiple offers arrive in same tick (queue-based presentation)

    DUAL-TIER SYSTEM:
    AGENT_TIERS (reach and base timing):
    - Local: 1-2 months, 2% fee, lower reach
    - Regional: 2-4 months, 4% fee, medium reach
    - National: 4-6 months, 6% fee, widest reach

    PRICE_TIERS (asking price and requirements):
    - Quick Sale: 75-85% FMV, +15% success, no requirements
    - Market Price: 95-105% FMV, baseline success, no requirements
    - Premium: 115-130% FMV, -20% success, requires ≥95% condition & ≥80% paint

    Combined success = Agent base success + Price modifier
    Trade-In: 50-65% (instant, only when purchasing) - handled by TradeInCalculations

    Flow:
    1. Player selects vehicle to sell from ESC -> Vehicles page
    2. SellVehicleDialog shows agent tier AND price tier options
    3. Player selects both, pays combined agent fee
    4. VehicleSaleListing created with TTL/TTS countdown
    5. When TTS reached, offer generated and player notified
    6. Player accepts (vehicle sold, money received) or declines (listing continues or expires)
    7. When TTL expires without accepted offer, listing fails (vehicle returned, fee lost)
]]

VehicleSaleListing = {}
local VehicleSaleListing_mt = Class(VehicleSaleListing)

--[[
    AGENT TIERS - determines reach, timing, and base fee
    Tier 0 = Private Sale (no agent), Tiers 1-3 = Professional agents
    Wider reach = more potential buyers = higher base success
]]
VehicleSaleListing.AGENT_TIERS = {
    [0] = {  -- Private Sale (no agent)
        name = "Private Sale",
        feePercent = 0.00,          -- No fee - you're doing the work
        minMonths = 3,              -- 3-6 months (longer without professional help)
        maxMonths = 6,
        baseSuccessRate = 0.50,     -- 50% base success (no marketing reach)
        noPremium = true,           -- Private buyers won't pay premium prices
        description = "No agent fee, but longer time and lower success rate."
    },
    [1] = {  -- Local Agent
        name = "Local Agent",
        feePercent = 0.02,          -- 2% base fee
        minMonths = 1,              -- 1-2 months
        maxMonths = 2,
        baseSuccessRate = 0.70,     -- 70% base success (limited reach)
        description = "Quick turnaround, limited buyer pool."
    },
    [2] = {  -- Regional Agent
        name = "Regional Agent",
        feePercent = 0.04,          -- 4% base fee
        minMonths = 2,              -- 2-4 months
        maxMonths = 4,
        baseSuccessRate = 0.85,     -- 85% base success
        description = "Balanced reach and timing."
    },
    [3] = {  -- National Agent
        name = "National Agent",
        feePercent = 0.06,          -- 6% base fee
        minMonths = 4,              -- 4-6 months
        maxMonths = 6,
        baseSuccessRate = 0.95,     -- 95% base success (wide reach)
        description = "Maximum exposure, longest wait."
    }
}

--[[
    PRICE TIERS - determines asking price and success modifier
    Higher asking price = harder to find buyer
]]
VehicleSaleListing.PRICE_TIERS = {
    [1] = {  -- Quick Sale (Fire Sale)
        name = "Quick Sale",
        priceMultiplierMin = 0.75,  -- 75-85% of FMV
        priceMultiplierMax = 0.85,
        successModifier = 0.15,     -- +15% success (easy to sell cheap)
        requiresCondition = 0,      -- No condition requirement
        requiresPaint = 0,          -- No paint requirement
        description = "Fire sale pricing. Easy to find buyers."
    },
    [2] = {  -- Market Price (Fair Value)
        name = "Market Price",
        priceMultiplierMin = 0.95,  -- 95-105% of FMV
        priceMultiplierMax = 1.05,
        successModifier = 0.00,     -- Baseline success
        requiresCondition = 0,      -- No condition requirement
        requiresPaint = 0,          -- No paint requirement
        description = "Fair market value. Standard odds."
    },
    [3] = {  -- Premium Price (Top Dollar)
        name = "Premium Price",
        priceMultiplierMin = 1.15,  -- 115-130% of FMV
        priceMultiplierMax = 1.30,
        successModifier = -0.20,    -- -20% success (hard to sell expensive)
        requiresCondition = 95,     -- Must be ≥95% repaired
        requiresPaint = 80,         -- Must be ≥80% paint condition
        description = "Premium pricing. Requires pristine condition."
    }
}

--[[
    Legacy compatibility - SALE_TIERS now maps to AGENT_TIERS
    This maintains backward compatibility with existing save files
]]
VehicleSaleListing.SALE_TIERS = VehicleSaleListing.AGENT_TIERS

--[[
    Listing status enum
]]
VehicleSaleListing.STATUS = {
    ACTIVE = "active",          -- Waiting for offer
    OFFER_PENDING = "pending",  -- Offer received, awaiting player decision
    SOLD = "sold",              -- Player accepted offer, vehicle sold
    DECLINED = "declined",      -- Player declined offer, still active (can get more offers)
    EXPIRED = "expired",        -- TTL ran out without accepted offer
    CANCELLED = "cancelled"     -- Player cancelled listing
}

--[[
    Constructor for new sale listing
    @param farmId - Farm that owns the vehicle
    @param vehicle - The vehicle object being sold
    @param vehicleData - Table with vehicle info (for persistence after sale)
    @param saleTier - Agent tier (1=Local, 2=Regional, 3=National)
    @param priceTier - Price tier (1=Quick, 2=Market, 3=Premium) - optional, defaults to 2
]]
function VehicleSaleListing.new(farmId, vehicle, vehicleData, saleTier, priceTier)
    local self = setmetatable({}, VehicleSaleListing_mt)

    -- Identity
    self.id = nil  -- Set by VehicleSaleManager when registered
    self.farmId = farmId

    -- Vehicle information (stored for persistence)
    self.vehicleId = vehicle and vehicle.id or nil
    self.vehicleConfigFile = vehicleData.configFileName
    self.vehicleName = vehicleData.name or "Unknown Vehicle"
    self.vehicleImageFile = vehicleData.imageFilename or ""
    self.vanillaSellPrice = vehicleData.vanillaSellPrice or 0

    -- Condition data (affects perceived value AND premium tier eligibility)
    self.repairPercent = vehicleData.repairPercent or 100
    self.paintPercent = vehicleData.paintPercent or 100
    self.operatingHours = vehicleData.operatingHours or 0

    -- Sale parameters (DUAL-TIER SYSTEM)
    self.saleTier = saleTier       -- Agent tier (1=Local, 2=Regional, 3=National)
    self.priceTier = priceTier or 2  -- Price tier (1=Quick, 2=Market, 3=Premium)
    self.agentFee = 0              -- Calculated below (combines both tiers)
    self.expectedMinPrice = 0      -- Minimum expected return
    self.expectedMaxPrice = 0      -- Maximum expected return

    -- Timing (in hours, 1 week = 24 hours)
    self.ttl = 0  -- Time to live (total listing duration)
    self.tts = 0  -- Time to success (when first offer arrives)
    self.hoursElapsed = 0  -- Hours since listing created

    -- Offer data
    self.currentOffer = nil        -- Current pending offer amount
    self.offerExpiresIn = 0        -- Hours until offer expires (player must decide)
    self.offersReceived = 0        -- Number of offers received so far
    self.offersDeclined = 0        -- Number of offers declined
    self.offerShownToUser = false  -- Has the popup been shown for this offer? (prevents race condition)

    -- Status
    self.status = VehicleSaleListing.STATUS.ACTIVE
    self.createdAt = 0             -- Game hour when created
    self.completedAt = 0           -- Game hour when sold/expired/cancelled
    self.finalSalePrice = 0        -- Actual price received (if sold)

    -- Calculate sale parameters from both tiers
    self:calculateSaleParams()

    return self
end

--[[
    Calculate sale parameters from DUAL-TIER system
    Combines agent tier (reach/timing) with price tier (asking price/success modifier)
]]
function VehicleSaleListing:calculateSaleParams()
    -- Get agent tier config
    local agentTier = VehicleSaleListing.AGENT_TIERS[self.saleTier]
    if agentTier == nil then
        agentTier = VehicleSaleListing.AGENT_TIERS[2]  -- Default to Regional
    end

    -- Get price tier config
    local priceTier = VehicleSaleListing.PRICE_TIERS[self.priceTier]
    if priceTier == nil then
        priceTier = VehicleSaleListing.PRICE_TIERS[2]  -- Default to Market
    end

    -- Calculate expected price range (from price tier, based on FMV)
    self.expectedMinPrice = math.floor(self.vanillaSellPrice * priceTier.priceMultiplierMin)
    self.expectedMaxPrice = math.floor(self.vanillaSellPrice * priceTier.priceMultiplierMax)

    -- Calculate agent fee as percentage of expected price (from agent tier)
    -- Private Sale (tier 0) has no fee
    local expectedMidPrice = (self.expectedMinPrice + self.expectedMaxPrice) / 2
    if agentTier.feePercent == 0 then
        self.agentFee = 0  -- No fee for Private Sale
    else
        self.agentFee = math.floor(expectedMidPrice * (agentTier.feePercent or 0.04))
        self.agentFee = math.max(self.agentFee, 50)  -- Minimum $50 fee for agents
    end

    -- Calculate duration in hours from agent tier (1 month = 24 hours game time)
    local minMonths = agentTier.minMonths or 1
    local maxMonths = agentTier.maxMonths or 2
    local durationMonths = math.random(minMonths, maxMonths)
    self.ttl = durationMonths * 24  -- Convert months to hours

    -- Calculate combined success rate (agent base + price modifier)
    local combinedSuccessRate = agentTier.baseSuccessRate + (priceTier.successModifier or 0)
    combinedSuccessRate = math.max(0.10, math.min(0.98, combinedSuccessRate))  -- Clamp to 10-98%

    -- Determine if listing will succeed
    math.random()  -- Dry run for better randomness
    local willSucceed = math.random() <= combinedSuccessRate

    if willSucceed then
        -- Will get at least one offer
        -- First offer arrives between 25% and 75% of total duration
        self.tts = math.random(math.floor(self.ttl * 0.25), math.floor(self.ttl * 0.75))
    else
        -- No offers - tts > ttl
        self.tts = self.ttl + 1
    end

    -- Set creation time
    if g_currentMission and g_currentMission.environment then
        self.createdAt = g_currentMission.environment.currentHour
    end

    UsedPlus.logDebug(string.format("VehicleSaleListing created: %s", self.vehicleName))
    UsedPlus.logDebug(string.format("  Agent: %s (fee: $%d / %.0f%%)", agentTier.name, self.agentFee, (agentTier.feePercent or 0.04) * 100))
    UsedPlus.logDebug(string.format("  Price: %s (success mod: %+.0f%%)", priceTier.name, (priceTier.successModifier or 0) * 100))
    UsedPlus.logDebug(string.format("  Combined success: %.0f%%", combinedSuccessRate * 100))
    UsedPlus.logDebug(string.format("  Expected: $%d - $%d", self.expectedMinPrice, self.expectedMaxPrice))
    UsedPlus.logDebug(string.format("  TTL: %d hours, TTS: %d hours", self.ttl, self.tts))
end

--[[
    Update listing timers (called every hour)
    Decrements TTL and TTS, checks for offer generation
    @return string - Event that occurred ("offer", "expired", nil)
]]
function VehicleSaleListing:update()
    -- Don't update if not active
    if self.status ~= VehicleSaleListing.STATUS.ACTIVE and
       self.status ~= VehicleSaleListing.STATUS.DECLINED then
        return nil
    end

    self.hoursElapsed = self.hoursElapsed + 1
    self.ttl = self.ttl - 1
    self.tts = self.tts - 1

    -- Update offer expiration if pending
    if self.status == VehicleSaleListing.STATUS.OFFER_PENDING then
        self.offerExpiresIn = self.offerExpiresIn - 1
        if self.offerExpiresIn <= 0 then
            -- Offer expired, decline automatically
            self:declineOffer()
            return "offer_expired"
        end
    end

    -- Check for offer generation
    if self.tts <= 0 and self.status == VehicleSaleListing.STATUS.ACTIVE then
        self:generateOffer()
        return "offer"
    end

    -- Check for expiration
    if self.ttl <= 0 and self.status ~= VehicleSaleListing.STATUS.OFFER_PENDING then
        self.status = VehicleSaleListing.STATUS.EXPIRED
        if g_currentMission and g_currentMission.environment then
            self.completedAt = g_currentMission.environment.currentHour
        end
        return "expired"
    end

    return nil
end

--[[
    Generate an offer for the vehicle
    Price is determined by PRICE_TIER (Quick/Market/Premium)
]]
function VehicleSaleListing:generateOffer()
    local priceTier = VehicleSaleListing.PRICE_TIERS[self.priceTier]
    if priceTier == nil then
        priceTier = VehicleSaleListing.PRICE_TIERS[2]  -- Default to Market
    end

    -- Random price within price tier range
    math.random()  -- Dry run for better randomness
    local priceRange = priceTier.priceMultiplierMax - priceTier.priceMultiplierMin
    local priceMultiplier = priceTier.priceMultiplierMin + (math.random() * priceRange)

    -- Add some variance (+/- 5%)
    local variance = 0.95 + (math.random() * 0.10)
    self.currentOffer = math.floor(self.vanillaSellPrice * priceMultiplier * variance)

    -- Round to nearest $100
    self.currentOffer = math.floor(self.currentOffer / 100) * 100

    -- Ensure minimum offer
    self.currentOffer = math.max(self.currentOffer, 100)

    -- Set offer expiration (from settings, default 48 hours to decide)
    self.offerExpiresIn = UsedPlusSettings and UsedPlusSettings:get("offerExpirationHours") or 48
    self.offersReceived = self.offersReceived + 1
    self.offerShownToUser = false  -- Mark as not yet shown to user

    -- Update status
    self.status = VehicleSaleListing.STATUS.OFFER_PENDING

    UsedPlus.logDebug(string.format("Offer generated for %s: $%d (%s pricing, expires in %d hours)",
        self.vehicleName, self.currentOffer, priceTier.name, self.offerExpiresIn))

    return self.currentOffer
end

--[[
    Accept the current offer
    Finalizes sale, returns money to player
    @return salePrice - The final sale price
]]
function VehicleSaleListing:acceptOffer()
    if self.status ~= VehicleSaleListing.STATUS.OFFER_PENDING or self.currentOffer == nil then
        return 0
    end

    self.finalSalePrice = self.currentOffer
    self.status = VehicleSaleListing.STATUS.SOLD
    if g_currentMission and g_currentMission.environment then
        self.completedAt = g_currentMission.environment.currentHour
    end

    UsedPlus.logDebug(string.format("Offer accepted for %s: $%d", self.vehicleName, self.finalSalePrice))

    return self.finalSalePrice
end

--[[
    Decline the current offer
    Listing continues, may get another offer if time remains
]]
function VehicleSaleListing:declineOffer()
    if self.status ~= VehicleSaleListing.STATUS.OFFER_PENDING then
        return false
    end

    self.offersDeclined = self.offersDeclined + 1
    self.currentOffer = nil
    self.offerExpiresIn = 0
    self.offerShownToUser = false  -- Reset for potential future offer

    -- Return to active if time remains, else expire
    if self.ttl > 0 then
        self.status = VehicleSaleListing.STATUS.DECLINED
        -- Set new TTS for potential next offer
        -- Next offer comes in remaining time / 2 (if lucky)
        local remainingTime = math.max(1, self.ttl)
        self.tts = math.random(math.floor(remainingTime * 0.25), math.floor(remainingTime * 0.75))

        -- Reset to active status after setting new TTS
        self.status = VehicleSaleListing.STATUS.ACTIVE
    else
        self.status = VehicleSaleListing.STATUS.EXPIRED
        if g_currentMission and g_currentMission.environment then
            self.completedAt = g_currentMission.environment.currentHour
        end
    end

    UsedPlus.logDebug(string.format("Offer declined for %s. Status: %s, TTL: %d",
        self.vehicleName, self.status, self.ttl))

    return true
end

--[[
    Cancel the listing
    Vehicle is returned to player, fee is lost
]]
function VehicleSaleListing:cancel()
    self.status = VehicleSaleListing.STATUS.CANCELLED
    if g_currentMission and g_currentMission.environment then
        self.completedAt = g_currentMission.environment.currentHour
    end

    UsedPlus.logDebug(string.format("Listing cancelled for %s", self.vehicleName))

    return true
end

--[[
    Get agent tier configuration
    @return agent tier config table
]]
function VehicleSaleListing:getAgentTierConfig()
    return VehicleSaleListing.AGENT_TIERS[self.saleTier] or VehicleSaleListing.AGENT_TIERS[2]
end

--[[
    Get price tier configuration
    @return price tier config table
]]
function VehicleSaleListing:getPriceTierConfig()
    return VehicleSaleListing.PRICE_TIERS[self.priceTier] or VehicleSaleListing.PRICE_TIERS[2]
end

--[[
    Legacy alias for backward compatibility
    @return agent tier config table
]]
function VehicleSaleListing:getTierConfig()
    return self:getAgentTierConfig()
end

--[[
    Get combined tier name for display (shows both agent and price tier)
]]
function VehicleSaleListing:getTierName()
    local agentTier = self:getAgentTierConfig()
    local priceTier = self:getPriceTierConfig()
    return string.format("%s / %s", agentTier.name, priceTier.name)
end

--[[
    Get agent tier name only
]]
function VehicleSaleListing:getAgentTierName()
    local tier = self:getAgentTierConfig()
    return tier.name
end

--[[
    Get price tier name only
]]
function VehicleSaleListing:getPriceTierName()
    local tier = self:getPriceTierConfig()
    return tier.name
end

--[[
    Get remaining time in human-readable format
    Uses weeks instead of months
]]
function VehicleSaleListing:getRemainingTime()
    local hours = self.ttl
    if hours <= 0 then
        return "Expired"
    end

    local weeks = math.floor(hours / 24)
    local remainingHours = hours % 24

    if weeks > 0 then
        return string.format("%d week%s, %d hrs", weeks, weeks > 1 and "s" or "", remainingHours)
    else
        return string.format("%d hrs", hours)
    end
end

--[[
    Check if vehicle meets tier requirements
    @param tier - Tier configuration table
    @return meetsRequirements (bool), reason (string or nil)
]]
function VehicleSaleListing:meetsTierRequirements(tier)
    if tier == nil then
        return true, nil
    end

    local requiresCondition = tier.requiresCondition or 0
    local requiresPaint = tier.requiresPaint or 0

    -- Check condition requirement (repairPercent = 100 - damage)
    if requiresCondition > 0 and self.repairPercent < requiresCondition then
        return false, string.format("Requires %d%% condition (currently %d%%)", requiresCondition, self.repairPercent)
    end

    -- Check paint requirement
    if requiresPaint > 0 and self.paintPercent < requiresPaint then
        return false, string.format("Requires %d%% paint (currently %d%%)", requiresPaint, self.paintPercent)
    end

    return true, nil
end

--[[
    Check if a specific PRICE tier is available for this vehicle
    Only PRICE_TIERS have condition requirements (Premium requires good condition)
    @param repairPercent - Vehicle condition (100 = perfect)
    @param paintPercent - Paint condition (100 = perfect)
    @param priceTierIndex - 1=Quick, 2=Market, 3=Premium
    @return available (bool), reason (string or nil)
]]
function VehicleSaleListing.canUsePriceTier(repairPercent, paintPercent, priceTierIndex)
    local tier = VehicleSaleListing.PRICE_TIERS[priceTierIndex]
    if tier == nil then
        return false, "Invalid price tier"
    end

    local requiresCondition = tier.requiresCondition or 0
    local requiresPaint = tier.requiresPaint or 0

    if requiresCondition > 0 and repairPercent < requiresCondition then
        return false, string.format("Requires %d%% condition", requiresCondition)
    end

    if requiresPaint > 0 and paintPercent < requiresPaint then
        return false, string.format("Requires %d%% paint", requiresPaint)
    end

    return true, nil
end

-- Legacy alias
VehicleSaleListing.canUseTier = VehicleSaleListing.canUsePriceTier

--[[
    Get status display text
]]
function VehicleSaleListing:getStatusText()
    if self.status == VehicleSaleListing.STATUS.ACTIVE then
        return "Searching for buyer..."
    elseif self.status == VehicleSaleListing.STATUS.OFFER_PENDING then
        return string.format("OFFER: %s (expires in %d hrs)",
            g_i18n:formatMoney(self.currentOffer, 0, true, true), self.offerExpiresIn)
    elseif self.status == VehicleSaleListing.STATUS.SOLD then
        return string.format("SOLD for %s", g_i18n:formatMoney(self.finalSalePrice, 0, true, true))
    elseif self.status == VehicleSaleListing.STATUS.EXPIRED then
        return "Expired - No buyer found"
    elseif self.status == VehicleSaleListing.STATUS.CANCELLED then
        return "Cancelled"
    else
        return self.status
    end
end

--[[
    Check if listing has a pending offer
]]
function VehicleSaleListing:hasPendingOffer()
    return self.status == VehicleSaleListing.STATUS.OFFER_PENDING and self.currentOffer ~= nil
end

--[[
    Check if listing is still active (can receive offers)
]]
function VehicleSaleListing:isActive()
    return self.status == VehicleSaleListing.STATUS.ACTIVE or
           self.status == VehicleSaleListing.STATUS.DECLINED
end

--[[
    Check if listing is complete (sold, expired, or cancelled)
]]
function VehicleSaleListing:isComplete()
    return self.status == VehicleSaleListing.STATUS.SOLD or
           self.status == VehicleSaleListing.STATUS.EXPIRED or
           self.status == VehicleSaleListing.STATUS.CANCELLED
end

--[[
    Save listing to XML savegame
]]
function VehicleSaleListing:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. "#id", self.id or "")
    xmlFile:setInt(key .. "#farmId", self.farmId)

    -- Vehicle data
    xmlFile:setString(key .. "#vehicleId", tostring(self.vehicleId or ""))
    xmlFile:setString(key .. "#vehicleConfigFile", self.vehicleConfigFile or "")
    xmlFile:setString(key .. "#vehicleName", self.vehicleName)
    xmlFile:setString(key .. "#vehicleImageFile", self.vehicleImageFile or "")
    xmlFile:setFloat(key .. "#vanillaSellPrice", self.vanillaSellPrice)

    -- Condition data
    xmlFile:setInt(key .. "#repairPercent", self.repairPercent)
    xmlFile:setInt(key .. "#paintPercent", self.paintPercent)
    xmlFile:setInt(key .. "#operatingHours", self.operatingHours)

    -- Sale parameters (DUAL-TIER SYSTEM)
    xmlFile:setInt(key .. "#saleTier", self.saleTier)
    xmlFile:setInt(key .. "#priceTier", self.priceTier or 2)  -- Default to Market
    xmlFile:setFloat(key .. "#agentFee", self.agentFee)
    xmlFile:setFloat(key .. "#expectedMinPrice", self.expectedMinPrice)
    xmlFile:setFloat(key .. "#expectedMaxPrice", self.expectedMaxPrice)

    -- Timing
    xmlFile:setInt(key .. "#ttl", self.ttl)
    xmlFile:setInt(key .. "#tts", self.tts)
    xmlFile:setInt(key .. "#hoursElapsed", self.hoursElapsed)

    -- Offer data
    xmlFile:setFloat(key .. "#currentOffer", self.currentOffer or 0)
    xmlFile:setInt(key .. "#offerExpiresIn", self.offerExpiresIn)
    xmlFile:setInt(key .. "#offersReceived", self.offersReceived)
    xmlFile:setInt(key .. "#offersDeclined", self.offersDeclined)
    xmlFile:setBool(key .. "#offerShownToUser", self.offerShownToUser or false)

    -- Status
    xmlFile:setString(key .. "#status", self.status)
    xmlFile:setInt(key .. "#createdAt", self.createdAt)
    xmlFile:setInt(key .. "#completedAt", self.completedAt)
    xmlFile:setFloat(key .. "#finalSalePrice", self.finalSalePrice)
end

--[[
    Load listing from XML savegame
    @return true if successful
]]
function VehicleSaleListing:loadFromXMLFile(xmlFile, key)
    self.id = xmlFile:getString(key .. "#id")

    -- Validate required fields
    if self.id == nil or self.id == "" then
        UsedPlus.logWarn("Corrupt sale listing in savegame, skipping")
        return false
    end

    self.farmId = xmlFile:getInt(key .. "#farmId")

    -- Vehicle data
    self.vehicleId = xmlFile:getString(key .. "#vehicleId", "")
    self.vehicleConfigFile = xmlFile:getString(key .. "#vehicleConfigFile", "")
    self.vehicleName = xmlFile:getString(key .. "#vehicleName", "Unknown Vehicle")
    self.vehicleImageFile = xmlFile:getString(key .. "#vehicleImageFile", "")
    self.vanillaSellPrice = xmlFile:getFloat(key .. "#vanillaSellPrice", 0)

    -- Condition data
    self.repairPercent = xmlFile:getInt(key .. "#repairPercent", 100)
    self.paintPercent = xmlFile:getInt(key .. "#paintPercent", 100)
    self.operatingHours = xmlFile:getInt(key .. "#operatingHours", 0)

    -- Sale parameters (DUAL-TIER SYSTEM)
    self.saleTier = xmlFile:getInt(key .. "#saleTier", 2)   -- Default to Regional
    self.priceTier = xmlFile:getInt(key .. "#priceTier", 2) -- Default to Market
    self.agentFee = xmlFile:getFloat(key .. "#agentFee", 50)
    self.expectedMinPrice = xmlFile:getFloat(key .. "#expectedMinPrice", 0)
    self.expectedMaxPrice = xmlFile:getFloat(key .. "#expectedMaxPrice", 0)

    -- Timing
    self.ttl = xmlFile:getInt(key .. "#ttl", 0)
    self.tts = xmlFile:getInt(key .. "#tts", 0)
    self.hoursElapsed = xmlFile:getInt(key .. "#hoursElapsed", 0)

    -- Offer data
    local offer = xmlFile:getFloat(key .. "#currentOffer", 0)
    self.currentOffer = offer > 0 and offer or nil
    self.offerExpiresIn = xmlFile:getInt(key .. "#offerExpiresIn", 0)
    self.offersReceived = xmlFile:getInt(key .. "#offersReceived", 0)
    self.offersDeclined = xmlFile:getInt(key .. "#offersDeclined", 0)
    self.offerShownToUser = xmlFile:getBool(key .. "#offerShownToUser", false)

    -- Status
    self.status = xmlFile:getString(key .. "#status", VehicleSaleListing.STATUS.ACTIVE)
    self.createdAt = xmlFile:getInt(key .. "#createdAt", 0)
    self.completedAt = xmlFile:getInt(key .. "#completedAt", 0)
    self.finalSalePrice = xmlFile:getFloat(key .. "#finalSalePrice", 0)

    return true
end

--[[
    Create from existing vehicle object
    Helper to extract vehicle data for listing
    @param farmId - Farm ID
    @param vehicle - Vehicle object
    @param saleTier - Agent tier
    @return VehicleSaleListing instance
]]
function VehicleSaleListing.createFromVehicle(farmId, vehicle, agentTier, priceTier)
    if vehicle == nil then
        return nil
    end

    -- Default priceTier for legacy compatibility
    priceTier = priceTier or 2

    -- Get store item for vehicle info
    local storeItem = nil
    if vehicle.configFileName then
        storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    end

    -- Get vanilla sell price
    local vanillaSellPrice = 0
    if vehicle.getSellPrice then
        vanillaSellPrice = vehicle:getSellPrice()
    end

    -- Get condition data using TradeInCalculations if available
    local repairPercent = 100
    local paintPercent = 100
    local operatingHours = 0

    if TradeInCalculations then
        local damage = TradeInCalculations.getVehicleDamage(vehicle)
        local wear = TradeInCalculations.getVehicleWear(vehicle)
        repairPercent = math.floor((1 - damage) * 100)
        paintPercent = math.floor((1 - wear) * 100)
        operatingHours = TradeInCalculations.getVehicleOperatingHours(vehicle)
    end

    -- Build vehicle data table
    -- Use UIHelper.Vehicle.getFullName() to get "Brand Model" format (e.g., "John Deere 3650")
    local vehicleName = "Unknown Vehicle"
    if UIHelper and UIHelper.Vehicle and UIHelper.Vehicle.getFullName then
        vehicleName = UIHelper.Vehicle.getFullName(storeItem)
    elseif storeItem and storeItem.name then
        vehicleName = storeItem.name
    end

    local vehicleData = {
        configFileName = vehicle.configFileName,
        name = vehicleName,
        imageFilename = storeItem and storeItem.imageFilename or "",
        vanillaSellPrice = vanillaSellPrice,
        repairPercent = repairPercent,
        paintPercent = paintPercent,
        operatingHours = operatingHours
    }

    return VehicleSaleListing.new(farmId, vehicle, vehicleData, agentTier, priceTier)
end

UsedPlus.logInfo("VehicleSaleListing class loaded")
