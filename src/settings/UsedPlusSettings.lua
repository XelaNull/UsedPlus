--[[
    FS25_UsedPlus - Settings Manager

    Central settings singleton with save/load and network sync.
    All managers query this for configuration values.

    24 settings total: 9 toggles + 15 economic parameters

    Usage:
        -- Check if system is enabled
        if UsedPlusSettings:isSystemEnabled("Finance") then ... end

        -- Get a setting value
        local rate = UsedPlusSettings:get("baseInterestRate")

        -- Set a setting (auto-saves)
        UsedPlusSettings:set("missedPaymentsToDefault", 5)

        -- Apply a preset
        UsedPlusSettings:applyPreset("casual")
]]

UsedPlusSettings = {
    -- Settings version (for future migrations)
    SETTINGS_VERSION = 1,

    -- Save file path (set on init)
    savePath = nil,

    -- Track if initialized
    isInitialized = false,
}

-- Default values for ALL settings
UsedPlusSettings.DEFAULTS = {
    -- === SYSTEM TOGGLES (9) ===
    enableFinanceSystem = true,
    enableLeaseSystem = true,
    enableUsedVehicleSearch = true,
    enableVehicleSaleSystem = true,
    enableRepairSystem = true,
    enableTradeInSystem = true,
    enableCreditSystem = true,
    enableTireWearSystem = true,
    enableMalfunctionsSystem = true,

    -- === MONEY & RATES (4) ===
    baseInterestRate = 0.08,        -- 8%
    baseTradeInPercent = 55,        -- 55%
    repairCostMultiplier = 1.0,     -- 1.0x
    leaseMarkupPercent = 15,        -- 15%

    -- === FORGIVENESS & RISK (4) ===
    missedPaymentsToDefault = 3,    -- 3 strikes
    minDownPaymentPercent = 0,      -- 0%
    startingCreditScore = 650,      -- 650
    latePaymentPenalty = 15,        -- -15 points

    -- === MARKETPLACE (4) ===
    searchSuccessPercent = 75,      -- 75% (averaged across tiers)
    maxListingsPerFarm = 3,         -- 3 listings
    offerExpirationHours = 48,      -- 48 hours
    agentCommissionPercent = 8,     -- 8% (averaged)

    -- === CONDITION & QUALITY (3) ===
    usedConditionMin = 40,          -- 40%
    usedConditionMax = 95,          -- 95%
    conditionPriceMultiplier = 1.0, -- 1.0x
    brandLoyaltyBonus = 5,          -- 5%
}

-- Current settings (merged defaults + loaded)
UsedPlusSettings.current = {}

-- Listeners for setting changes
UsedPlusSettings.listeners = {}

--[[
    Initialize settings system
    Called from FSBaseMission.loadItemsFinished hook
    @param savegameDirectory - Path to savegame directory
]]
function UsedPlusSettings:init(savegameDirectory)
    if self.isInitialized then
        UsedPlus.logDebug("UsedPlusSettings already initialized")
        return
    end

    -- Set save path
    if savegameDirectory then
        self.savePath = savegameDirectory .. "/usedplus_settings.xml"
    end

    -- Start with defaults
    self.current = {}
    for key, value in pairs(self.DEFAULTS) do
        self.current[key] = value
    end

    -- Load saved settings (overwrites defaults with saved values)
    self:load()

    self.isInitialized = true
    UsedPlus.logInfo("UsedPlusSettings initialized")
end

--[[
    Get a setting value
    @param key - Setting key
    @return value - Current value (or default if not set)
]]
function UsedPlusSettings:get(key)
    -- Return current if set
    if self.current[key] ~= nil then
        return self.current[key]
    end

    -- Fall back to default
    return self.DEFAULTS[key]
end

--[[
    Set a setting value
    @param key - Setting key
    @param value - New value
    @param skipSave - Optional: skip auto-save (for batch updates)
    @param skipNotify - Optional: skip notifying listeners
]]
function UsedPlusSettings:set(key, value, skipSave, skipNotify)
    -- Validate key exists
    if self.DEFAULTS[key] == nil then
        UsedPlus.logWarn(string.format("UsedPlusSettings: Unknown key '%s'", key))
        return false
    end

    -- Skip if value unchanged
    if self.current[key] == value then
        return true
    end

    -- Store old value for notification
    local oldValue = self.current[key]

    -- Set new value
    self.current[key] = value
    UsedPlus.logDebug(string.format("UsedPlusSettings: Set %s = %s", key, tostring(value)))

    -- Auto-save unless told not to
    if not skipSave then
        self:save()
    end

    -- Notify listeners
    if not skipNotify then
        self:notifyListeners(key, value, oldValue)
    end

    return true
end

--[[
    Set multiple settings at once (batch update)
    @param settings - Table of key/value pairs
]]
function UsedPlusSettings:setMultiple(settings)
    for key, value in pairs(settings) do
        self:set(key, value, true, true)  -- Skip save and notify for each
    end

    -- Save once at the end
    self:save()

    -- Notify all listeners with "batch" key
    self:notifyListeners("batch", nil, nil)
end

--[[
    Check if a system is enabled
    @param systemName - System name (Finance, Lease, UsedVehicleSearch, etc.)
    @return boolean
]]
function UsedPlusSettings:isSystemEnabled(systemName)
    local key = "enable" .. systemName .. "System"
    return self:get(key) == true
end

--[[
    Apply a preset configuration
    @param presetName - casual/realistic/hardcore/lite
]]
function UsedPlusSettings:applyPreset(presetName)
    if not SettingsPresets or not SettingsPresets[presetName] then
        UsedPlus.logWarn(string.format("UsedPlusSettings: Unknown preset '%s'", presetName))
        return false
    end

    local preset = SettingsPresets[presetName]
    self:setMultiple(preset)
    UsedPlus.logInfo(string.format("UsedPlusSettings: Applied preset '%s'", presetName))
    return true
end

--[[
    Reset all settings to defaults
]]
function UsedPlusSettings:resetToDefaults()
    self.current = {}
    for key, value in pairs(self.DEFAULTS) do
        self.current[key] = value
    end

    self:save()
    self:notifyListeners("reset", nil, nil)
    UsedPlus.logInfo("UsedPlusSettings: Reset to defaults")
end

--[[
    Save settings to XML file
]]
function UsedPlusSettings:save()
    if not self.savePath then
        UsedPlus.logDebug("UsedPlusSettings: No save path, skipping save")
        return false
    end

    local xmlFile = XMLFile.create("usedPlusSettings", self.savePath, "usedPlusSettings")
    if xmlFile == nil then
        UsedPlus.logError("UsedPlusSettings: Failed to create settings file")
        return false
    end

    -- Write version
    xmlFile:setInt("usedPlusSettings#version", self.SETTINGS_VERSION)

    -- Write each setting
    local settingIndex = 0
    for key, value in pairs(self.current) do
        local basePath = string.format("usedPlusSettings.settings.setting(%d)", settingIndex)
        xmlFile:setString(basePath .. "#name", key)

        local valueType = type(value)
        if valueType == "boolean" then
            xmlFile:setString(basePath .. "#type", "bool")
            xmlFile:setBool(basePath .. "#value", value)
        elseif valueType == "number" then
            xmlFile:setString(basePath .. "#type", "number")
            xmlFile:setFloat(basePath .. "#value", value)
        elseif valueType == "string" then
            xmlFile:setString(basePath .. "#type", "string")
            xmlFile:setString(basePath .. "#value", value)
        end

        settingIndex = settingIndex + 1
    end

    xmlFile:save()
    xmlFile:delete()

    UsedPlus.logDebug("UsedPlusSettings: Saved to " .. self.savePath)
    return true
end

--[[
    Load settings from XML file
]]
function UsedPlusSettings:load()
    if not self.savePath then
        UsedPlus.logDebug("UsedPlusSettings: No save path, using defaults")
        return false
    end

    if not fileExists(self.savePath) then
        UsedPlus.logDebug("UsedPlusSettings: No saved settings, using defaults")
        return false
    end

    local xmlFile = XMLFile.loadIfExists("usedPlusSettings", self.savePath)
    if xmlFile == nil then
        UsedPlus.logWarn("UsedPlusSettings: Failed to load settings file")
        return false
    end

    -- Check version (for future migrations)
    local version = xmlFile:getInt("usedPlusSettings#version", 1)

    -- Load each setting
    local settingIndex = 0
    while true do
        local basePath = string.format("usedPlusSettings.settings.setting(%d)", settingIndex)

        if not xmlFile:hasProperty(basePath .. "#name") then
            break
        end

        local name = xmlFile:getString(basePath .. "#name")
        local valueType = xmlFile:getString(basePath .. "#type", "string")

        -- Only load if key exists in defaults (ignore obsolete settings)
        if self.DEFAULTS[name] ~= nil then
            if valueType == "bool" then
                self.current[name] = xmlFile:getBool(basePath .. "#value", self.DEFAULTS[name])
            elseif valueType == "number" then
                self.current[name] = xmlFile:getFloat(basePath .. "#value", self.DEFAULTS[name])
            else
                self.current[name] = xmlFile:getString(basePath .. "#value", self.DEFAULTS[name])
            end
        end

        settingIndex = settingIndex + 1
    end

    xmlFile:delete()

    UsedPlus.logInfo(string.format("UsedPlusSettings: Loaded %d settings from savegame", settingIndex))
    return true
end

--[[
    Register a listener for setting changes
    @param listener - Object with onSettingChanged(key, newValue, oldValue) method
]]
function UsedPlusSettings:addListener(listener)
    table.insert(self.listeners, listener)
end

--[[
    Remove a listener
    @param listener - Previously registered listener
]]
function UsedPlusSettings:removeListener(listener)
    for i, l in ipairs(self.listeners) do
        if l == listener then
            table.remove(self.listeners, i)
            return
        end
    end
end

--[[
    Notify all listeners of a setting change
    @param key - Setting key that changed
    @param newValue - New value
    @param oldValue - Previous value
]]
function UsedPlusSettings:notifyListeners(key, newValue, oldValue)
    for _, listener in ipairs(self.listeners) do
        if listener.onSettingChanged then
            local success, err = pcall(listener.onSettingChanged, listener, key, newValue, oldValue)
            if not success then
                UsedPlus.logWarn(string.format("UsedPlusSettings: Listener error: %s", tostring(err)))
            end
        end
    end
end

--[[
    Get all current settings as table (for network sync)
    @return table - All current settings
]]
function UsedPlusSettings:getAllSettings()
    local settings = {}
    for key, value in pairs(self.current) do
        settings[key] = value
    end
    return settings
end

--[[
    Apply settings from network (multiplayer sync)
    @param settings - Table of key/value pairs from server
]]
function UsedPlusSettings:applyFromNetwork(settings)
    for key, value in pairs(settings) do
        self.current[key] = value
    end
    UsedPlus.logInfo("UsedPlusSettings: Applied settings from server")
    self:notifyListeners("network", nil, nil)
end

--[[
    Get list of all system toggle keys
    @return table - Array of toggle key names
]]
function UsedPlusSettings:getSystemToggleKeys()
    return {
        "enableFinanceSystem",
        "enableLeaseSystem",
        "enableUsedVehicleSearch",
        "enableVehicleSaleSystem",
        "enableRepairSystem",
        "enableTradeInSystem",
        "enableCreditSystem",
        "enableTireWearSystem",
        "enableMalfunctionsSystem",
    }
end

--[[
    Get list of all economic setting keys
    @return table - Array of economic setting key names
]]
function UsedPlusSettings:getEconomicSettingKeys()
    return {
        "baseInterestRate",
        "baseTradeInPercent",
        "repairCostMultiplier",
        "leaseMarkupPercent",
        "missedPaymentsToDefault",
        "minDownPaymentPercent",
        "startingCreditScore",
        "latePaymentPenalty",
        "searchSuccessPercent",
        "maxListingsPerFarm",
        "offerExpirationHours",
        "agentCommissionPercent",
        "usedConditionMin",
        "usedConditionMax",
        "conditionPriceMultiplier",
        "brandLoyaltyBonus",
    }
end

UsedPlus.logInfo("UsedPlusSettings loaded")
