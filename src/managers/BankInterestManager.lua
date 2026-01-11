--[[
    FS25_UsedPlus - Bank Interest Manager
    v2.0.0: Monthly interest on positive bank balances

    Based on: FS25_bankAccountInterest by Evan Kirsch
    Enhanced with: Configurable rates, preset scaling, notification system

    Real-world US credit union rates (2024-2025): 1.5% - 5.0% APY
    We use moderate rates that scale with presets:
    - Easy Mode: 3.5% APY (generous passive income)
    - Casual: 2.0% APY (modest interest)
    - Balanced: 1.0% APY (realistic credit union rate)
    - Hardcore: 0.5% APY (minimal reward for hoarding)
    - Punishing: 0.0% APY (no free money!)

    Interest is calculated monthly (12x per year) on positive cash balances.
    Formula: monthly_interest = balance * (annual_rate / 12)

    This is a global singleton: g_bankInterestManager
]]

BankInterestManager = {}
local BankInterestManager_mt = Class(BankInterestManager)

--[[
    Constructor
]]
function BankInterestManager.new()
    local self = setmetatable({}, BankInterestManager_mt)

    -- Statistics tracking
    self.totalInterestPaid = {}  -- Per farm: total interest earned
    self.lastInterestPaid = {}   -- Per farm: last month's interest

    -- Track if initialized
    self.isInitialized = false

    return self
end

--[[
    Initialize the manager - called from main.lua
]]
function BankInterestManager:init()
    if self.isInitialized then
        return
    end

    -- Only process on server (handles multiplayer sync)
    if not g_currentMission:getIsServer() then
        UsedPlus.logDebug("BankInterestManager: Client mode, skipping initialization")
        self.isInitialized = true
        return
    end

    -- Subscribe to monthly period change
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)

    -- Listen for setting changes
    if UsedPlusSettings then
        UsedPlusSettings:addListener(self)
    end

    self.isInitialized = true
    UsedPlus.logInfo("BankInterestManager initialized (server mode)")
end

--[[
    Get the current interest rate
    @return number - Annual interest rate as decimal (e.g., 0.01 = 1%)
]]
function BankInterestManager:getInterestRate()
    if UsedPlusSettings then
        return UsedPlusSettings:get("bankInterestRate") or 0.01
    end
    return 0.01  -- Default 1% APY
end

--[[
    Check if bank interest is enabled
    @return boolean
]]
function BankInterestManager:isEnabled()
    if UsedPlusSettings then
        return UsedPlusSettings:get("enableBankInterest") == true
    end
    return false
end

--[[
    Called every month (period change)
    Calculates and deposits interest for all farms with positive balances
]]
function BankInterestManager:onPeriodChanged()
    -- Only run on server
    if not g_currentMission:getIsServer() then
        return
    end

    -- Check if feature is enabled
    if not self:isEnabled() then
        return
    end

    local rate = self:getInterestRate()

    -- Skip if rate is 0 or negative
    if rate <= 0 then
        return
    end

    -- Process all farms
    local farms = g_farmManager.farmIdToFarm
    if not farms then
        return
    end

    local totalInterestThisMonth = 0
    local farmsProcessed = 0

    for farmId, farm in pairs(farms) do
        -- Skip spectator farm (farmId 0)
        if farmId > 0 and farm.money then
            local balance = farm.money

            -- Only earn interest on positive balances
            if balance > 0 then
                -- Calculate monthly interest: balance * (annual_rate / 12)
                local monthlyInterest = balance * (rate / 12)

                -- Round to whole number (no fractional currency)
                monthlyInterest = math.floor(monthlyInterest)

                -- Only deposit if meaningful amount (at least $1)
                if monthlyInterest >= 1 then
                    -- Add money to farm account
                    g_currentMission:addMoney(
                        monthlyInterest,
                        farmId,
                        MoneyType.OTHER,
                        true,   -- addChange (show in finances)
                        true    -- showHUD (display notification)
                    )

                    -- Track statistics
                    self.lastInterestPaid[farmId] = monthlyInterest
                    self.totalInterestPaid[farmId] = (self.totalInterestPaid[farmId] or 0) + monthlyInterest

                    totalInterestThisMonth = totalInterestThisMonth + monthlyInterest
                    farmsProcessed = farmsProcessed + 1

                    UsedPlus.logDebug(string.format(
                        "Bank interest for farm %d: balance=%d, rate=%.2f%%, interest=%d",
                        farmId, balance, rate * 100, monthlyInterest
                    ))
                end
            end
        end
    end

    if farmsProcessed > 0 then
        UsedPlus.logInfo(string.format(
            "Bank interest deposited: %d farms, total %s",
            farmsProcessed,
            g_i18n:formatMoney(totalInterestThisMonth)
        ))
    end
end

--[[
    Get statistics for a specific farm
    @param farmId - Farm ID
    @return table - {totalInterest, lastInterest, currentBalance, monthlyEstimate}
]]
function BankInterestManager:getStatistics(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    local balance = farm and farm.money or 0
    local rate = self:getInterestRate()

    return {
        totalInterest = self.totalInterestPaid[farmId] or 0,
        lastInterest = self.lastInterestPaid[farmId] or 0,
        currentBalance = balance,
        monthlyEstimate = math.floor(balance * (rate / 12)),
        annualRate = rate
    }
end

--[[
    Get display text for current interest settings
    @return string - Human readable description
]]
function BankInterestManager:getStatusText()
    if not self:isEnabled() then
        return "Bank Interest: Disabled"
    end

    local rate = self:getInterestRate()
    return string.format("Bank Interest: %.2f%% APY", rate * 100)
end

--[[
    Calculate what interest would be earned on a given balance
    @param balance - Cash balance to calculate interest on
    @return number - Monthly interest amount
]]
function BankInterestManager:calculateMonthlyInterest(balance)
    if balance <= 0 then
        return 0
    end

    local rate = self:getInterestRate()
    return math.floor(balance * (rate / 12))
end

--[[
    Calculate annual interest for a given balance
    @param balance - Cash balance to calculate interest on
    @return number - Approximate annual interest (simple interest, not compound)
]]
function BankInterestManager:calculateAnnualInterest(balance)
    if balance <= 0 then
        return 0
    end

    local rate = self:getInterestRate()
    return math.floor(balance * rate)
end

--[[
    Settings change listener
]]
function BankInterestManager:onSettingChanged(key, newValue, oldValue)
    if key == "enableBankInterest" then
        if newValue then
            UsedPlus.logInfo("Bank interest enabled")
        else
            UsedPlus.logInfo("Bank interest disabled")
        end
    elseif key == "bankInterestRate" then
        UsedPlus.logInfo(string.format("Bank interest rate changed to %.2f%%", newValue * 100))
    end
end

--[[
    Debug console command
]]
function BankInterestManager:consoleCommandStatus()
    print(self:getStatusText())

    if self:isEnabled() then
        local rate = self:getInterestRate()
        print(string.format("  Annual rate: %.2f%%", rate * 100))
        print(string.format("  Monthly rate: %.4f%%", (rate / 12) * 100))

        -- Show per-farm stats
        local farms = g_farmManager.farmIdToFarm
        if farms then
            for farmId, farm in pairs(farms) do
                if farmId > 0 then
                    local stats = self:getStatistics(farmId)
                    print(string.format(
                        "  Farm %d: balance=%s, monthly=%s, total earned=%s",
                        farmId,
                        g_i18n:formatMoney(stats.currentBalance),
                        g_i18n:formatMoney(stats.monthlyEstimate),
                        g_i18n:formatMoney(stats.totalInterest)
                    ))
                end
            end
        end
    end
end

--[[
    Save manager state to savegame
    @param xmlFile - XML file handle
    @param key - Base XML key
]]
function BankInterestManager:saveToXML(xmlFile, key)
    local index = 0
    for farmId, total in pairs(self.totalInterestPaid) do
        local farmKey = string.format("%s.farm(%d)", key, index)
        xmlFile:setInt(farmKey .. "#id", farmId)
        xmlFile:setFloat(farmKey .. "#totalInterest", total)
        xmlFile:setFloat(farmKey .. "#lastInterest", self.lastInterestPaid[farmId] or 0)
        index = index + 1
    end
    UsedPlus.logDebug(string.format("BankInterestManager: Saved stats for %d farms", index))
end

--[[
    Load manager state from savegame
    @param xmlFile - XML file handle
    @param key - Base XML key
]]
function BankInterestManager:loadFromXML(xmlFile, key)
    local index = 0
    while true do
        local farmKey = string.format("%s.farm(%d)", key, index)
        if not xmlFile:hasProperty(farmKey .. "#id") then
            break
        end

        local farmId = xmlFile:getInt(farmKey .. "#id")
        self.totalInterestPaid[farmId] = xmlFile:getFloat(farmKey .. "#totalInterest", 0)
        self.lastInterestPaid[farmId] = xmlFile:getFloat(farmKey .. "#lastInterest", 0)

        index = index + 1
    end
    UsedPlus.logDebug(string.format("BankInterestManager: Loaded stats for %d farms", index))
end

-- Create global singleton
g_bankInterestManager = BankInterestManager.new()

UsedPlus.logInfo("BankInterestManager loaded")
