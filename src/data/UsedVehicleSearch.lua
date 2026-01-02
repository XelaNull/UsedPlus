--[[
    FS25_UsedPlus - Used Vehicle Search Data Class

    v1.5.0 REDESIGN: Multi-Find Agent Model

    UsedVehicleSearch represents an active search with a vehicle broker/agent.

    New Model (v1.5.0):
    - Small retainer fee upfront (instead of large percentage fee)
    - Commission built into vehicle asking price
    - Monthly success rolls - multiple vehicles accumulate over time
    - Player browses portfolio and picks the best one
    - Search ends when player purchases a vehicle

    Search Tiers:
    1. Local Search:    $500 flat retainer, 6% commission, 1 month, 30%/month
    2. Regional Search: $1000+0.5% retainer, 8% commission, 3 months, 55%/month
    3. National Search: $2000+0.8% retainer, 10% commission, 6 months, 85%/month

    Pattern from: Realistic broker/agent model
]]

UsedVehicleSearch = {}
local UsedVehicleSearch_mt = Class(UsedVehicleSearch)

--[[
    Credit score modifiers for agent fees (retainer)
    Better credit = cheaper agent services (they trust you more)
    Must match UsedSearchDialog.CREDIT_FEE_MODIFIERS!
]]
UsedVehicleSearch.CREDIT_FEE_MODIFIERS = {
    {minScore = 750, modifier = -0.15, name = "Excellent"},  -- 15% discount
    {minScore = 700, modifier = -0.08, name = "Good"},       -- 8% discount
    {minScore = 650, modifier = 0.00,  name = "Fair"},       -- No change
    {minScore = 600, modifier = 0.10,  name = "Poor"},       -- 10% surcharge
    {minScore = 300, modifier = 0.20,  name = "Very Poor"}   -- 20% surcharge
}

--[[
    Search tier definitions - v1.5.0 REDESIGNED

    New fee model:
    - retainerFlat: Fixed upfront fee
    - retainerPercent: Additional percentage of vehicle price for retainer
    - commissionPercent: Percentage added to vehicle's asking price (paid when buying)

    New success model:
    - Monthly success rolls instead of single roll at creation
    - Multiple vehicles can be found over the search duration
    - Search ends when player buys OR when duration expires
]]
UsedVehicleSearch.SEARCH_TIERS = {
    {  -- Local Search: Quick, cheap, low odds
        name = "Local Search",
        retainerFlat = 500,           -- $500 flat retainer
        retainerPercent = 0,          -- No percentage
        commissionPercent = 0.06,     -- 6% added to vehicle price
        maxMonths = 1,                -- 1 month only
        monthlySuccessChance = 0.30,  -- 30% each month
        matchChance = 0.25,           -- 25% per configuration
        guaranteedMinimum = 0,        -- No guarantee
        maxListings = 3               -- Cap at 3 finds
    },
    {  -- Regional Search: Balanced, best value
        name = "Regional Search",
        retainerFlat = 1000,          -- $1000 base
        retainerPercent = 0.005,      -- Plus 0.5% of vehicle price
        commissionPercent = 0.08,     -- 8% commission
        maxMonths = 3,                -- Up to 3 months
        monthlySuccessChance = 0.55,  -- 55% each month
        matchChance = 0.50,           -- 50% per configuration
        guaranteedMinimum = 0,        -- No guarantee
        maxListings = 6               -- Cap at 6 finds
    },
    {  -- National Search: Premium, high certainty
        name = "National Search",
        retainerFlat = 2000,          -- $2000 base
        retainerPercent = 0.008,      -- Plus 0.8% of vehicle price
        commissionPercent = 0.10,     -- 10% commission
        maxMonths = 6,                -- Up to 6 months
        monthlySuccessChance = 0.85,  -- 85% each month
        matchChance = 0.70,           -- 70% per configuration
        guaranteedMinimum = 1,        -- At least 1 find guaranteed
        maxListings = 10              -- Cap at 10 finds
    }
}

--[[
    Quality tier definitions with RANGES (v1.4.0 - ECONOMICS.md compliance)
    Lower quality = lower price, but needs repairs
    successModifier affects the monthly success rate

    Order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Must match DepreciationCalculations.QUALITY_TIERS!
]]
UsedVehicleSearch.QUALITY_TIERS = {
    {  -- Any Condition: Catch-all with widest variance
        name = "Any Condition",
        priceRangeMin = 0.30,            -- 30% of new (70% off)
        priceRangeMax = 0.50,            -- 50% of new (50% off)
        damageRange = { 0.35, 0.60 },    -- 35-60% damage
        wearRange = { 0.40, 0.65 },      -- 40-65% wear
        hoursRange = { 300, 4000 },      -- 300-4000 operating hours
        ageRange = { 2, 8 },             -- 2-8 years old
        successModifier = 0.08,          -- +8% easier to find rough equipment
        description = "Wildcard - high variance in quality and price"
    },
    {  -- Poor Condition: Fixer-upper - highest repair costs
        name = "Poor Condition",
        priceRangeMin = 0.22,            -- 22% of new (78% off)
        priceRangeMax = 0.38,            -- 38% of new (62% off)
        damageRange = { 0.55, 0.80 },    -- 55-80% damage
        wearRange = { 0.60, 0.85 },      -- 60-85% wear
        hoursRange = { 2000, 6000 },     -- 2000-6000 hours (well used!)
        ageRange = { 5, 12 },            -- 5-12 years old
        successModifier = 0.15,          -- +15% easier to find junk
        description = "Bargain bin - extensive repairs needed"
    },
    {  -- Fair Condition: Middle ground
        name = "Fair Condition",
        priceRangeMin = 0.50,            -- 50% of new (50% off)
        priceRangeMax = 0.68,            -- 68% of new (32% off)
        damageRange = { 0.18, 0.35 },    -- 18-35% damage
        wearRange = { 0.22, 0.40 },      -- 22-40% wear
        hoursRange = { 800, 2500 },      -- 800-2500 hours
        ageRange = { 2, 6 },             -- 2-6 years old
        successModifier = 0.00,          -- Baseline (no modifier)
        description = "Moderate wear - some repairs likely"
    },
    {  -- Good Condition: Well maintained
        name = "Good Condition",
        priceRangeMin = 0.68,            -- 68% of new (32% off)
        priceRangeMax = 0.80,            -- 80% of new (20% off)
        damageRange = { 0.06, 0.18 },    -- 6-18% damage
        wearRange = { 0.08, 0.22 },      -- 8-22% wear
        hoursRange = { 200, 1200 },      -- 200-1200 hours (lightly used)
        ageRange = { 1, 4 },             -- 1-4 years old
        successModifier = -0.08,         -- -8% harder to find well-maintained
        description = "Well maintained - minimal repairs"
    },
    {  -- Excellent Condition: Like new
        name = "Excellent Condition",
        priceRangeMin = 0.80,            -- 80% of new (20% off)
        priceRangeMax = 0.94,            -- 94% of new (6% off)
        damageRange = { 0.00, 0.06 },    -- 0-6% damage
        wearRange = { 0.00, 0.08 },      -- 0-8% wear
        hoursRange = { 50, 500 },        -- 50-500 hours (barely used)
        ageRange = { 0, 2 },             -- 0-2 years old
        successModifier = -0.15,         -- -15% harder to find pristine
        description = "Like new - ready to work immediately"
    }
}

--[[
    Get credit score fee modifier for a farm
    @param farmId - Farm ID to check credit for
    @return modifier (negative = discount, positive = surcharge)
]]
function UsedVehicleSearch.getCreditFeeModifier(farmId)
    if not CreditScore then
        return 0
    end

    local score = CreditScore.calculate(farmId)
    for _, tier in ipairs(UsedVehicleSearch.CREDIT_FEE_MODIFIERS) do
        if score >= tier.minScore then
            return tier.modifier
        end
    end
    return 0.20  -- Default to worst tier
end

--[[
    Constructor for new search request - v1.5.0 REDESIGNED
    Sets up monthly rolling success model with portfolio accumulation
]]
function UsedVehicleSearch.new(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
    local self = setmetatable({}, UsedVehicleSearch_mt)

    -- Identity
    self.id = nil  -- Set by UsedVehicleManager when registered
    self.farmId = farmId

    -- Store item information
    self.storeItemIndex = storeItemIndex  -- xmlFilename or index
    self.storeItemName = storeItemName
    self.basePrice = basePrice

    -- Search parameters
    self.searchLevel = searchLevel  -- 1 = local, 2 = regional, 3 = national
    self.qualityLevel = qualityLevel or 1  -- 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    self.configurations = {}  -- Configuration options

    -- v1.5.0: New fee structure (retainer + commission)
    self.retainerFee = 0         -- Small upfront cost (calculated below)
    self.commissionPercent = 0   -- Added to vehicle price when buying
    self.creditFeeModifier = 0   -- Credit adjustment to retainer

    -- v1.5.0: Monthly tracking (replaces TTL/TTS countdown)
    self.maxMonths = 0           -- Total search duration
    self.monthsElapsed = 0       -- Months completed
    self.lastCheckDay = 0        -- Last day we checked for success
    self.monthlySuccessChance = 0  -- Per-month success rate

    -- v1.5.0: Multiple results (replaces single foundCondition/foundPrice)
    self.foundListings = {}      -- Array of found vehicle listings
    self.maxListings = 10        -- Cap on total finds
    self.guaranteedMinimum = 0   -- National tier gets 1 guaranteed

    -- Status
    self.status = "active"  -- active, completed, purchased, cancelled
    self.createdAt = g_currentMission.environment.currentDay

    -- v1.5.0: Legacy fields for save migration (not used in new code)
    self.ttl = 0  -- DEPRECATED - kept for migration
    self.tts = 0  -- DEPRECATED - kept for migration
    self.searchCost = 0  -- DEPRECATED - use retainerFee instead
    self.foundCondition = 0  -- DEPRECATED - use foundListings
    self.foundPrice = 0  -- DEPRECATED - use foundListings

    -- Calculate search parameters from tier
    self:calculateSearchParams()

    return self
end

--[[
    Calculate search parameters from search tier - v1.5.0 REDESIGNED
    Sets up retainer fee, commission, and monthly success parameters
]]
function UsedVehicleSearch:calculateSearchParams()
    local tier = UsedVehicleSearch.SEARCH_TIERS[self.searchLevel]
    if tier == nil then
        tier = UsedVehicleSearch.SEARCH_TIERS[2]  -- Default to Regional
    end

    -- Calculate retainer fee with credit modifier
    local creditFeeModifier = UsedVehicleSearch.getCreditFeeModifier(self.farmId)
    local baseRetainer = tier.retainerFlat + math.floor(self.basePrice * tier.retainerPercent)
    local adjustedRetainer = math.floor(baseRetainer * (1 + creditFeeModifier))

    self.retainerFee = adjustedRetainer
    self.creditFeeModifier = creditFeeModifier
    self.commissionPercent = tier.commissionPercent

    -- Monthly parameters
    self.maxMonths = tier.maxMonths
    self.monthsElapsed = 0
    self.lastCheckDay = g_currentMission.environment.currentDay

    -- Apply quality modifier and global settings modifier to monthly success chance
    local qualityTier = UsedVehicleSearch.QUALITY_TIERS[self.qualityLevel]
    local qualityModifier = qualityTier and qualityTier.successModifier or 0

    -- Get global success modifier from settings (default 75% = 1.0 multiplier)
    -- E.g., 90% setting = 1.2 multiplier, 60% setting = 0.8 multiplier
    local settingsPercent = UsedPlusSettings and UsedPlusSettings:get("searchSuccessPercent") or 75
    local globalModifier = settingsPercent / 75

    -- Apply: base chance × global modifier + quality modifier
    local adjustedChance = (tier.monthlySuccessChance * globalModifier) + qualityModifier
    self.monthlySuccessChance = math.max(0.05, math.min(0.95, adjustedChance))

    -- Limits
    self.maxListings = tier.maxListings
    self.guaranteedMinimum = tier.guaranteedMinimum

    -- Set match chances for configurations
    for configId, config in pairs(self.configurations) do
        config.matchChance = tier.matchChance
    end

    -- v1.5.0: Legacy compatibility - calculate deprecated fields
    self.searchCost = self.retainerFee  -- For old code that reads searchCost
    self.ttl = self.maxMonths * 24  -- For display code that reads ttl
    self.tts = self.ttl + 999  -- Ensure old success check never triggers

    UsedPlus.logDebug(string.format("Search configured: %s tier, %d months, %.0f%% monthly chance",
        tier.name, self.maxMonths, self.monthlySuccessChance * 100))
    UsedPlus.logDebug(string.format("  Retainer: $%d (credit mod: %.0f%%), Commission: %.0f%%",
        self.retainerFee, creditFeeModifier * 100, self.commissionPercent * 100))
end

--[[
    Process monthly success check - v1.5.0 NEW
    Called by UsedVehicleManager when a new game day starts
    Rolls for success and generates a listing if successful
    @return listing if found, nil otherwise
]]
function UsedVehicleSearch:processMonthlyCheck()
    -- Check if search is still active
    if self.status ~= "active" then
        return nil
    end

    -- Clean up any expired listings first
    -- "The seller found another buyer..."
    local expiredCount = self:cleanupExpiredListings()
    if expiredCount > 0 then
        -- Notify player that offers expired
        if g_currentMission and not g_currentMission.isLoading then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format("%d vehicle offer(s) expired - sellers found other buyers", expiredCount)
            )
        end
    end

    -- Increment month counter
    self.monthsElapsed = self.monthsElapsed + 1
    self.lastCheckDay = g_currentMission.environment.currentDay

    UsedPlus.logDebug(string.format("Search %s: Month %d of %d",
        self.id, self.monthsElapsed, self.maxMonths))

    -- Check if search duration completed
    if self.monthsElapsed > self.maxMonths then
        self:completeSearch()
        return nil
    end

    -- Check if at max listings
    if #self.foundListings >= self.maxListings then
        UsedPlus.logDebug("  At max listings capacity, skipping roll")
        return nil
    end

    -- Roll for success THIS month
    math.random()  -- Dry run for better randomness
    local roll = math.random()
    local success = roll <= self.monthlySuccessChance

    UsedPlus.logDebug(string.format("  Roll: %.2f vs %.2f = %s",
        roll, self.monthlySuccessChance, success and "SUCCESS" or "fail"))

    if success then
        -- Generate listing data (manager will create full listing object)
        local listingData = self:generateFoundVehicleDetails()
        return listingData
    end

    -- Check guaranteed minimum on final month
    if self.monthsElapsed == self.maxMonths then
        if self.guaranteedMinimum > 0 and #self.foundListings < self.guaranteedMinimum then
            UsedPlus.logDebug("  Applying guaranteed minimum find")
            local listingData = self:generateFoundVehicleDetails()
            return listingData
        end

        -- Search duration complete
        self:completeSearch()
    end

    return nil
end

--[[
    Complete the search (duration expired)
    Status changes to "completed" - listings remain for player to review
]]
function UsedVehicleSearch:completeSearch()
    self.status = "completed"
    UsedPlus.logDebug(string.format("Search %s completed: %d vehicles found",
        self.id, #self.foundListings))
end

--[[
    Mark search as purchased (player bought a vehicle)
    Remaining listings are discarded
]]
function UsedVehicleSearch:markPurchased()
    self.status = "purchased"
    UsedPlus.logDebug(string.format("Search %s: Vehicle purchased, search ended",
        self.id))
end

--[[
    Cancel this search
    No refund - retainer is a sunk cost (commitment)
]]
function UsedVehicleSearch:cancel()
    self.status = "cancelled"
    UsedPlus.logDebug(string.format("Search %s cancelled: %s", self.id, self.storeItemName))
end

--[[
    Clean up expired listings from the portfolio
    Each listing has a random expiration of 2-3 months from when it was found
    "The seller found another buyer"
    @return number of expired listings removed
]]
function UsedVehicleSearch:cleanupExpiredListings()
    local expiredCount = 0
    local expiredNames = {}

    -- Iterate backwards for safe removal
    for i = #self.foundListings, 1, -1 do
        local listing = self.foundListings[i]
        local listingAge = self.monthsElapsed - (listing.foundMonth or 0)
        local maxAge = listing.expirationMonths or 3  -- Default to 3 if not set

        if listingAge >= maxAge then
            table.insert(expiredNames, listing.id or "unknown")
            table.remove(self.foundListings, i)
            expiredCount = expiredCount + 1
        end
    end

    if expiredCount > 0 then
        UsedPlus.logDebug(string.format("Search %s: %d listing(s) expired - seller found other buyers (%s)",
            self.id, expiredCount, table.concat(expiredNames, ", ")))
    end

    return expiredCount
end

--[[
    Get months remaining until a listing expires
    @param listing - The listing object
    @return months remaining (0 = expires this month, negative = already expired)
]]
function UsedVehicleSearch:getListingMonthsRemaining(listing)
    local listingAge = self.monthsElapsed - (listing.foundMonth or 0)
    local maxAge = listing.expirationMonths or 3
    return maxAge - listingAge
end

--[[
    Add a listing to the found vehicles portfolio
    @param listing - The listing object to add
]]
function UsedVehicleSearch:addFoundListing(listing)
    if #self.foundListings >= self.maxListings then
        UsedPlus.logWarn("Cannot add listing - at capacity")
        return false
    end

    listing.foundMonth = self.monthsElapsed
    table.insert(self.foundListings, listing)

    UsedPlus.logDebug(string.format("Search %s: Added listing %s (total: %d)",
        self.id, listing.id, #self.foundListings))
    return true
end

--[[
    Remove a listing from the portfolio (player declined it)
    @param listingId - ID of the listing to remove
    @return true if removed, false if not found
]]
function UsedVehicleSearch:removeFoundListing(listingId)
    for i, listing in ipairs(self.foundListings) do
        if listing.id == listingId then
            table.remove(self.foundListings, i)
            UsedPlus.logDebug(string.format("Search %s: Removed listing %s (remaining: %d)",
                self.id, listingId, #self.foundListings))
            return true
        end
    end
    return false
end

--[[
    Get a listing by ID from the portfolio
    @param listingId - ID to find
    @return listing or nil
]]
function UsedVehicleSearch:getFoundListing(listingId)
    for _, listing in ipairs(self.foundListings) do
        if listing.id == listingId then
            return listing
        end
    end
    return nil
end

--[[
    Generate condition and price for found vehicle (v1.4.0 - uses damageRange/wearRange)
    Called when monthly roll succeeds
    Returns table with damage, wear, price details for manager to use
]]
function UsedVehicleSearch:generateFoundVehicleDetails()
    local qualityTier = UsedVehicleSearch.QUALITY_TIERS[self.qualityLevel]
    if qualityTier == nil then
        qualityTier = UsedVehicleSearch.QUALITY_TIERS[1]  -- Default to "Any"
    end

    -- Random damage within tier range
    math.random()  -- Dry run for better randomness
    local damageRange = qualityTier.damageRange or { 0.30, 0.60 }
    local wearRange = qualityTier.wearRange or { 0.35, 0.65 }
    local hoursRange = qualityTier.hoursRange or { 300, 4000 }
    local ageRange = qualityTier.ageRange or { 2, 8 }

    local foundDamage = damageRange[1] + (math.random() * (damageRange[2] - damageRange[1]))
    local foundWear = wearRange[1] + (math.random() * (wearRange[2] - wearRange[1]))

    -- v1.5.1: Generate hours and age based on quality tier
    local foundHours = math.floor(hoursRange[1] + (math.random() * (hoursRange[2] - hoursRange[1])))
    local foundAge = math.floor(ageRange[1] + (math.random() * (ageRange[2] - ageRange[1] + 1)))

    -- Condition is inverse of damage (for compatibility)
    local foundCondition = 1.0 - foundDamage

    -- Apply condition limits from settings (e.g., min 40%, max 95%)
    local conditionMin = UsedPlusSettings and (UsedPlusSettings:get("usedConditionMin") / 100) or 0.40
    local conditionMax = UsedPlusSettings and (UsedPlusSettings:get("usedConditionMax") / 100) or 0.95
    foundCondition = math.max(conditionMin, math.min(conditionMax, foundCondition))
    foundDamage = 1.0 - foundCondition  -- Recalculate damage from clamped condition

    -- Price from range with small variance
    local priceRangeMin = qualityTier.priceRangeMin or 0.30
    local priceRangeMax = qualityTier.priceRangeMax or 0.50
    local priceMultiplier = priceRangeMin + (math.random() * (priceRangeMax - priceRangeMin))
    local priceVariance = 0.95 + (math.random() * 0.10)  -- 95-105% variance

    -- Apply condition price multiplier from settings (affects how much condition impacts price)
    -- >1.0 = condition matters more (good condition = higher price, poor = lower)
    -- <1.0 = condition matters less (prices more uniform regardless of condition)
    local conditionMultiplier = UsedPlusSettings and UsedPlusSettings:get("conditionPriceMultiplier") or 1.0
    -- Adjust price based on condition deviation from 70% baseline
    local conditionDeviation = (foundCondition - 0.70) * conditionMultiplier
    priceMultiplier = priceMultiplier + (conditionDeviation * 0.2)  -- ±20% max impact
    priceMultiplier = math.max(0.15, math.min(0.98, priceMultiplier))  -- Clamp to reasonable range

    local basePrice = math.floor(self.basePrice * priceMultiplier * priceVariance)

    -- Calculate commission (added to asking price)
    local commissionAmount = math.floor(basePrice * self.commissionPercent)
    local askingPrice = basePrice + commissionAmount

    -- Generate unique listing ID
    local currentDay = 1
    if g_currentMission and g_currentMission.environment then
        currentDay = g_currentMission.environment.currentDay or 1
    end
    local listingId = string.format("%s_M%d_%d", self.id, self.monthsElapsed, currentDay)

    UsedPlus.logDebug(string.format("Generated found vehicle: %s (listing %s)", self.storeItemName, listingId))
    UsedPlus.logDebug(string.format("  Quality tier: %s", qualityTier.name))
    UsedPlus.logDebug(string.format("  Damage: %.1f%%, Wear: %.1f%%", foundDamage * 100, foundWear * 100))
    UsedPlus.logDebug(string.format("  Hours: %d, Age: %d years", foundHours, foundAge))
    UsedPlus.logDebug(string.format("  Base price: $%d + Commission: $%d = Asking: $%d",
        basePrice, commissionAmount, askingPrice))

    -- Random expiration: 2-3 months, favoring 3 months (70% chance)
    -- This creates uncertainty - player won't know if offer will last 2 or 3 months
    -- "The seller might find another buyer..."
    math.random()  -- Dry run for better randomness
    local expirationMonths = math.random() < 0.70 and 3 or 2

    -- Create listing data with ID
    local listingData = {
        id = listingId,
        damage = foundDamage,
        wear = foundWear,
        condition = foundCondition,
        operatingHours = foundHours,      -- v1.5.1: Hours based on quality tier
        age = foundAge,                    -- v1.5.1: Age based on quality tier
        basePrice = basePrice,
        commissionAmount = commissionAmount,
        askingPrice = askingPrice,
        qualityLevel = self.qualityLevel,
        qualityName = qualityTier.name,
        foundMonth = self.monthsElapsed,
        expirationMonths = expirationMonths  -- 2 or 3 months until offer expires
    }

    -- Add to portfolio immediately
    table.insert(self.foundListings, listingData)
    UsedPlus.logDebug(string.format("  Added to portfolio (now %d/%d, expires in %d months)",
        #self.foundListings, self.maxListings, expirationMonths))

    return listingData
end

--[[
    Generate matched configurations for found vehicle
    Rolls dice for each configuration option
    Returns table of configId -> index (or nil for no match)
]]
function UsedVehicleSearch:generateMatchedConfigurations()
    local matched = {}
    local tier = UsedVehicleSearch.SEARCH_TIERS[self.searchLevel] or UsedVehicleSearch.SEARCH_TIERS[2]

    for configId, config in pairs(self.configurations) do
        math.random()  -- Dry run for better randomness
        local roll = math.random()

        if roll <= (config.matchChance or tier.matchChance) then
            matched[configId] = config.index
        else
            matched[configId] = nil
        end
    end

    return matched
end

--[[
    Get quality tier name for display
]]
function UsedVehicleSearch:getQualityName()
    local qualityTier = UsedVehicleSearch.QUALITY_TIERS[self.qualityLevel]
    if qualityTier then
        return qualityTier.name
    end
    return "Unknown"
end

--[[
    Get search tier name for display
]]
function UsedVehicleSearch:getTierName()
    local tier = UsedVehicleSearch.SEARCH_TIERS[self.searchLevel]
    if tier then
        return tier.name
    end
    return "Unknown"
end

--[[
    Get remaining time in human-readable format
]]
function UsedVehicleSearch:getRemainingTime()
    local monthsRemaining = self.maxMonths - self.monthsElapsed
    if monthsRemaining > 1 then
        return string.format("%d months", monthsRemaining)
    elseif monthsRemaining == 1 then
        return "1 month"
    else
        return "Complete"
    end
end

--[[
    Get progress as percentage (0-100)
]]
function UsedVehicleSearch:getProgressPercent()
    if self.maxMonths == 0 then
        return 100
    end
    return math.floor((self.monthsElapsed / self.maxMonths) * 100)
end

--[[
    Check if search should process monthly check today
    @param currentDay - Current game day
    @return true if a day has passed since last check
]]
function UsedVehicleSearch:shouldProcessMonthlyCheck(currentDay)
    if self.status ~= "active" then
        return false
    end

    -- Check if a full day has passed (1 day = 1 month in game)
    return currentDay > self.lastCheckDay
end

--[[
    Check if search is complete (for manager cleanup)
    Returns true if status is not "active"
]]
function UsedVehicleSearch:isComplete()
    return self.status ~= "active"
end

--[[
    Check if search has any found listings available
]]
function UsedVehicleSearch:hasFoundListings()
    return #self.foundListings > 0
end

--[[
    DEPRECATED: Update search timers (legacy hourly countdown)
    Kept for compatibility but does nothing in v1.5.0
]]
function UsedVehicleSearch:update()
    -- v1.5.0: Monthly checks replace hourly TTL countdown
    -- This method is kept for backwards compatibility but does nothing
    -- Use processMonthlyCheck() instead
end

--[[
    DEPRECATED: Check if search is complete (legacy TTL/TTS check)
    Kept for compatibility but returns nil in v1.5.0
]]
function UsedVehicleSearch:checkCompletion()
    -- v1.5.0: Monthly processing replaces this
    -- Always return nil - manager uses shouldProcessMonthlyCheck() instead
    return nil
end

--[[
    Save search to XML savegame - v1.5.0 FORMAT
    Preserves search state including found listings
]]
function UsedVehicleSearch:saveToXMLFile(xmlFile, key)
    -- Identity
    xmlFile:setString(key .. "#id", self.id)
    xmlFile:setInt(key .. "#farmId", self.farmId)
    xmlFile:setString(key .. "#storeItemIndex", self.storeItemIndex)
    xmlFile:setString(key .. "#storeItemName", self.storeItemName)
    xmlFile:setFloat(key .. "#basePrice", self.basePrice)
    xmlFile:setInt(key .. "#searchLevel", self.searchLevel)
    xmlFile:setInt(key .. "#qualityLevel", self.qualityLevel or 1)
    xmlFile:setString(key .. "#status", self.status)
    xmlFile:setInt(key .. "#createdAt", self.createdAt)

    -- v1.5.0: New fee structure
    xmlFile:setFloat(key .. "#retainerFee", self.retainerFee)
    xmlFile:setFloat(key .. "#commissionPercent", self.commissionPercent)
    xmlFile:setFloat(key .. "#creditFeeModifier", self.creditFeeModifier or 0)

    -- v1.5.0: Monthly tracking
    xmlFile:setInt(key .. "#maxMonths", self.maxMonths)
    xmlFile:setInt(key .. "#monthsElapsed", self.monthsElapsed)
    xmlFile:setInt(key .. "#lastCheckDay", self.lastCheckDay)
    xmlFile:setFloat(key .. "#monthlySuccessChance", self.monthlySuccessChance)
    xmlFile:setInt(key .. "#maxListings", self.maxListings)
    xmlFile:setInt(key .. "#guaranteedMinimum", self.guaranteedMinimum)

    -- v1.5.0: Save found listings array
    for i, listing in ipairs(self.foundListings) do
        local listingKey = string.format("%s.foundListing(%d)", key, i - 1)
        self:saveListingToXML(xmlFile, listingKey, listing)
    end

    -- Save configurations
    local configIndex = 0
    for configId, config in pairs(self.configurations) do
        local configKey = string.format("%s.configuration(%d)", key, configIndex)
        xmlFile:setString(configKey .. "#id", configId)
        xmlFile:setInt(configKey .. "#index", config.index)
        xmlFile:setFloat(configKey .. "#matchChance", config.matchChance)
        xmlFile:setString(configKey .. "#name", config.name or "")
        configIndex = configIndex + 1
    end
end

--[[
    Save a single listing to XML
]]
function UsedVehicleSearch:saveListingToXML(xmlFile, key, listing)
    xmlFile:setString(key .. "#id", listing.id)
    xmlFile:setFloat(key .. "#basePrice", listing.basePrice or listing.price or 0)
    xmlFile:setFloat(key .. "#commissionAmount", listing.commissionAmount or 0)
    xmlFile:setFloat(key .. "#askingPrice", listing.askingPrice or listing.price or 0)
    xmlFile:setFloat(key .. "#damage", listing.damage or 0)
    xmlFile:setFloat(key .. "#wear", listing.wear or 0)
    xmlFile:setInt(key .. "#age", listing.age or 0)
    xmlFile:setInt(key .. "#operatingHours", listing.operatingHours or 0)
    xmlFile:setInt(key .. "#foundMonth", listing.foundMonth or 0)
    xmlFile:setString(key .. "#qualityName", listing.qualityName or "")

    -- Save usedPlusData if present
    if listing.usedPlusData then
        local dataKey = key .. ".usedPlusData"
        xmlFile:setFloat(dataKey .. "#engineReliability", listing.usedPlusData.engineReliability or 0.5)
        xmlFile:setFloat(dataKey .. "#hydraulicReliability", listing.usedPlusData.hydraulicReliability or 0.5)
        xmlFile:setFloat(dataKey .. "#electricalReliability", listing.usedPlusData.electricalReliability or 0.5)
        xmlFile:setFloat(dataKey .. "#workhorseLemonScale", listing.usedPlusData.workhorseLemonScale or 0.5)
        xmlFile:setBool(dataKey .. "#wasInspected", listing.usedPlusData.wasInspected or false)
    end
end

--[[
    Load search from XML savegame - v1.5.0 with MIGRATION
    Handles both new format and old v1.4.x format
]]
function UsedVehicleSearch:loadFromXMLFile(xmlFile, key)
    self.id = xmlFile:getString(key .. "#id")

    -- Validate required fields
    if self.id == nil or self.id == "" then
        UsedPlus.logWarn("Corrupt search request in savegame, skipping")
        return false
    end

    -- Load common fields
    self.farmId = xmlFile:getInt(key .. "#farmId")
    self.storeItemIndex = xmlFile:getString(key .. "#storeItemIndex")
    self.storeItemName = xmlFile:getString(key .. "#storeItemName")
    self.basePrice = xmlFile:getFloat(key .. "#basePrice")
    self.searchLevel = xmlFile:getInt(key .. "#searchLevel")
    self.qualityLevel = xmlFile:getInt(key .. "#qualityLevel", 1)
    self.status = xmlFile:getString(key .. "#status", "active")
    self.createdAt = xmlFile:getInt(key .. "#createdAt")

    -- Check if this is v1.5.0 format (has monthsElapsed)
    local hasNewFormat = xmlFile:hasProperty(key .. "#monthsElapsed")

    if hasNewFormat then
        -- v1.5.0 FORMAT - load directly
        self:loadNewFormat(xmlFile, key)
    else
        -- OLD FORMAT - migrate from TTL/TTS system
        self:migrateFromOldFormat(xmlFile, key)
    end

    -- Load configurations (same in both formats)
    self.configurations = {}
    xmlFile:iterate(key .. ".configuration", function(_, configKey)
        local configId = xmlFile:getString(configKey .. "#id")
        if configId ~= nil then
            self.configurations[configId] = {
                index = xmlFile:getInt(configKey .. "#index"),
                matchChance = xmlFile:getFloat(configKey .. "#matchChance"),
                name = xmlFile:getString(configKey .. "#name", "")
            }
        end
    end)

    return true
end

--[[
    Load v1.5.0 format data
]]
function UsedVehicleSearch:loadNewFormat(xmlFile, key)
    -- Fee structure
    self.retainerFee = xmlFile:getFloat(key .. "#retainerFee", 0)
    self.commissionPercent = xmlFile:getFloat(key .. "#commissionPercent", 0.08)
    self.creditFeeModifier = xmlFile:getFloat(key .. "#creditFeeModifier", 0)

    -- Monthly tracking
    self.maxMonths = xmlFile:getInt(key .. "#maxMonths", 1)
    self.monthsElapsed = xmlFile:getInt(key .. "#monthsElapsed", 0)
    self.lastCheckDay = xmlFile:getInt(key .. "#lastCheckDay", 0)
    self.monthlySuccessChance = xmlFile:getFloat(key .. "#monthlySuccessChance", 0.55)
    self.maxListings = xmlFile:getInt(key .. "#maxListings", 10)
    self.guaranteedMinimum = xmlFile:getInt(key .. "#guaranteedMinimum", 0)

    -- Load found listings
    self.foundListings = {}
    xmlFile:iterate(key .. ".foundListing", function(_, listingKey)
        local listing = self:loadListingFromXML(xmlFile, listingKey)
        if listing then
            table.insert(self.foundListings, listing)
        end
    end)

    -- Calculate deprecated fields for compatibility
    self.searchCost = self.retainerFee
    self.ttl = (self.maxMonths - self.monthsElapsed) * 24
    self.tts = self.ttl + 999

    UsedPlus.logDebug(string.format("Loaded search %s (v1.5.0 format): %d/%d months, %d listings",
        self.id, self.monthsElapsed, self.maxMonths, #self.foundListings))
end

--[[
    Load a single listing from XML
]]
function UsedVehicleSearch:loadListingFromXML(xmlFile, key)
    local id = xmlFile:getString(key .. "#id")
    if id == nil or id == "" then
        return nil
    end

    local listing = {
        id = id,
        basePrice = xmlFile:getFloat(key .. "#basePrice", 0),
        commissionAmount = xmlFile:getFloat(key .. "#commissionAmount", 0),
        askingPrice = xmlFile:getFloat(key .. "#askingPrice", 0),
        damage = xmlFile:getFloat(key .. "#damage", 0),
        wear = xmlFile:getFloat(key .. "#wear", 0),
        age = xmlFile:getInt(key .. "#age", 0),
        operatingHours = xmlFile:getInt(key .. "#operatingHours", 0),
        foundMonth = xmlFile:getInt(key .. "#foundMonth", 0),
        qualityName = xmlFile:getString(key .. "#qualityName", ""),

        -- Copy from search for convenience
        storeItemIndex = self.storeItemIndex,
        storeItemName = self.storeItemName,
        farmId = self.farmId
    }

    -- Set price for compatibility
    listing.price = listing.askingPrice

    -- Load usedPlusData if present
    local dataKey = key .. ".usedPlusData"
    if xmlFile:hasProperty(dataKey .. "#engineReliability") then
        listing.usedPlusData = {
            engineReliability = xmlFile:getFloat(dataKey .. "#engineReliability", 0.5),
            hydraulicReliability = xmlFile:getFloat(dataKey .. "#hydraulicReliability", 0.5),
            electricalReliability = xmlFile:getFloat(dataKey .. "#electricalReliability", 0.5),
            workhorseLemonScale = xmlFile:getFloat(dataKey .. "#workhorseLemonScale", 0.5),
            wasInspected = xmlFile:getBool(dataKey .. "#wasInspected", false)
        }
    end

    return listing
end

--[[
    Migrate from old v1.4.x format (TTL/TTS system)
    Converts to monthly system, preserving search progress
]]
function UsedVehicleSearch:migrateFromOldFormat(xmlFile, key)
    UsedPlus.logInfo(string.format("Migrating search %s from old format", self.id))

    -- Read old format fields
    local oldTTL = xmlFile:getInt(key .. "#ttl", 24)
    local oldTTS = xmlFile:getInt(key .. "#tts", 999)
    local oldSearchCost = xmlFile:getFloat(key .. "#searchCost", 0)
    local oldFoundCondition = xmlFile:getFloat(key .. "#foundCondition", 0)
    local oldFoundPrice = xmlFile:getFloat(key .. "#foundPrice", 0)

    -- Get tier configuration
    local tier = UsedVehicleSearch.SEARCH_TIERS[self.searchLevel] or UsedVehicleSearch.SEARCH_TIERS[2]

    -- Convert TTL hours to months (24 hours = 1 month)
    local totalMonths = math.ceil((oldTTL + (tier.maxMonths * 24 - oldTTL)) / 24)
    local elapsedMonths = tier.maxMonths - math.ceil(oldTTL / 24)

    -- Set monthly parameters
    self.maxMonths = tier.maxMonths
    self.monthsElapsed = math.max(0, elapsedMonths)
    self.lastCheckDay = g_currentMission.environment.currentDay
    self.monthlySuccessChance = tier.monthlySuccessChance
    self.maxListings = tier.maxListings
    self.guaranteedMinimum = tier.guaranteedMinimum

    -- Convert old fee to new structure
    -- Old fee was already paid, so treat as retainer (no additional charges)
    self.retainerFee = oldSearchCost
    self.commissionPercent = tier.commissionPercent
    self.creditFeeModifier = 0

    -- Initialize empty listings array
    self.foundListings = {}

    -- Check if old search had a "will succeed" result pending
    -- If TTS <= TTL and status is active, the search would have succeeded
    local wouldHaveSucceeded = (oldTTS <= oldTTL) and (self.status == "active")

    if wouldHaveSucceeded and oldFoundCondition > 0 then
        -- Create a listing from the old found vehicle data
        local listing = {
            id = self.id .. "_migrated",
            damage = 1.0 - oldFoundCondition,
            wear = 1.0 - oldFoundCondition,  -- Estimate wear from condition
            basePrice = oldFoundPrice,
            commissionAmount = 0,  -- No commission for migrated vehicles
            askingPrice = oldFoundPrice,
            price = oldFoundPrice,
            age = 3,  -- Estimate
            operatingHours = 500,  -- Estimate
            foundMonth = self.monthsElapsed,
            qualityName = self:getQualityName(),
            storeItemIndex = self.storeItemIndex,
            storeItemName = self.storeItemName,
            farmId = self.farmId
        }
        table.insert(self.foundListings, listing)
        UsedPlus.logInfo("  Migrated pending vehicle find")
    end

    -- Set deprecated fields for compatibility
    self.searchCost = self.retainerFee
    self.ttl = oldTTL
    self.tts = oldTTS
    self.foundCondition = oldFoundCondition
    self.foundPrice = oldFoundPrice

    UsedPlus.logInfo(string.format("  Migration complete: %d/%d months, %d listings",
        self.monthsElapsed, self.maxMonths, #self.foundListings))
end

UsedPlus.logInfo("UsedVehicleSearch class loaded (v1.5.0 - Multi-Find Agent Model)")
