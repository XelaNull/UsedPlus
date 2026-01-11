# UsedPlus Settings Implementation Blueprint

**Version:** 1.9.8+
**Last Updated:** 2026-01-01

Technical implementation guide for the UsedPlus settings system (~24 settings total).

---

## Table of Contents

1. [Scope](#scope)
2. [File Structure](#file-structure)
3. [Settings Manager](#settings-manager)
4. [UI Integration](#ui-integration)
5. [Savegame Persistence](#savegame-persistence)
6. [Multiplayer Sync](#multiplayer-sync)
7. [Testing Checklist](#testing-checklist)

---

## Scope

**What we're building:**
- 9 system toggles (on/off switches)
- 15 economic parameters (sliders/dropdowns)
- 4 presets (one-click configurations)

**Implementation approach:**
- ESC Menu → Settings: All 9 toggles
- Finance Manager: Full settings dialog with presets

---

## File Structure

```
FS25_UsedPlus/
├── src/
│   ├── settings/
│   │   └── UsedPlusSettings.lua       # Core settings manager (~150 lines)
│   └── extensions/
│       └── InGameMenuSettingsExtension.lua  # ESC menu toggles
├── gui/
│   └── UsedPlusSettingsDialog.xml     # Full settings dialog
└── translations/
    └── translation_en.xml             # ~20 new strings
```

---

## Settings Manager

### UsedPlusSettings.lua

```lua
--[[
    FS25_UsedPlus - Settings Manager (Compact Version)

    24 settings total: 9 toggles + 15 economic parameters
]]

UsedPlusSettings = {
    SETTINGS_VERSION = 1,
    savePath = nil,
}

-- All defaults in one place
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

--[[
    Initialize settings system
    @param savegamePath - Path to savegame directory
]]
function UsedPlusSettings:init(savegamePath)
    self.savePath = savegamePath .. "/usedplus_settings.xml"

    -- Start with defaults
    self.current = {}
    for key, value in pairs(self.DEFAULTS) do
        self.current[key] = value
    end

    -- Load saved settings
    self:load()

    UsedPlus.logInfo("UsedPlusSettings initialized")
end

--[[
    Get a setting value
    @param key - Setting key
    @return value - Current value (or default if not set)
]]
function UsedPlusSettings:get(key)
    if self.current[key] ~= nil then
        return self.current[key]
    end
    return self.DEFAULTS[key]
end

--[[
    Set a setting value
    @param key - Setting key
    @param value - New value
    @param skipSave - Optional: skip auto-save (for batch updates)
]]
function UsedPlusSettings:set(key, value, skipSave)
    if self.DEFAULTS[key] == nil then
        UsedPlus.logWarn(string.format("Unknown setting key: %s", key))
        return
    end

    self.current[key] = value

    if not skipSave then
        self:save()
    end

    -- Notify listeners
    self:onSettingChanged(key, value)
end

--[[
    Set multiple settings at once (batch update)
    @param settings - Table of key/value pairs
]]
function UsedPlusSettings:setMultiple(settings)
    for key, value in pairs(settings) do
        self:set(key, value, true)
    end
    self:save()
end

--[[
    Check if a system is enabled
    @param systemName - System name (Finance, Lease, etc.)
    @return boolean
]]
function UsedPlusSettings:isSystemEnabled(systemName)
    local key = "enable" .. systemName .. "System"
    return self:get(key) == true
end

--[[
    Apply a preset configuration
    @param presetName - casual/realistic/hardcore/etc.
]]
function UsedPlusSettings:applyPreset(presetName)
    local preset = SettingsPresets[presetName]
    if preset then
        self:setMultiple(preset)
        UsedPlus.logInfo(string.format("Applied preset: %s", presetName))
    else
        UsedPlus.logWarn(string.format("Unknown preset: %s", presetName))
    end
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
    UsedPlus.logInfo("Settings reset to defaults")
end

--[[
    Save settings to XML file
]]
function UsedPlusSettings:save()
    if not self.savePath then
        return
    end

    local xmlFile = XMLFile.create("usedPlusSettings", self.savePath, "usedPlusSettings")
    if xmlFile == nil then
        UsedPlus.logError("Failed to create settings file")
        return
    end

    xmlFile:setInt("usedPlusSettings#version", self.SETTINGS_VERSION)

    -- Save each setting
    for key, value in pairs(self.current) do
        local valueType = type(value)
        if valueType == "boolean" then
            xmlFile:setBool("usedPlusSettings.settings." .. key, value)
        elseif valueType == "number" then
            xmlFile:setFloat("usedPlusSettings.settings." .. key, value)
        elseif valueType == "string" then
            xmlFile:setString("usedPlusSettings.settings." .. key, value)
        end
    end

    xmlFile:save()
    xmlFile:delete()

    UsedPlus.logDebug("Settings saved")
end

--[[
    Load settings from XML file
]]
function UsedPlusSettings:load()
    if not self.savePath then
        return
    end

    if not fileExists(self.savePath) then
        UsedPlus.logDebug("No settings file found, using defaults")
        return
    end

    local xmlFile = XMLFile.loadIfExists("usedPlusSettings", self.savePath)
    if xmlFile == nil then
        return
    end

    local version = xmlFile:getInt("usedPlusSettings#version", 1)

    -- Load each known setting
    for key, defaultValue in pairs(self.DEFAULTS) do
        local valueType = type(defaultValue)
        local path = "usedPlusSettings.settings." .. key

        if valueType == "boolean" then
            if xmlFile:hasProperty(path) then
                self.current[key] = xmlFile:getBool(path, defaultValue)
            end
        elseif valueType == "number" then
            if xmlFile:hasProperty(path) then
                self.current[key] = xmlFile:getFloat(path, defaultValue)
            end
        elseif valueType == "string" then
            if xmlFile:hasProperty(path) then
                self.current[key] = xmlFile:getString(path, defaultValue)
            end
        end
    end

    xmlFile:delete()

    UsedPlus.logInfo("Settings loaded")
end

--[[
    Callback when a setting changes
    Override to add listeners
]]
function UsedPlusSettings:onSettingChanged(key, value)
    -- Broadcast to interested managers
    if key:find("^enable") then
        -- System toggle changed - may need to refresh UI
        if g_financeManager then
            g_financeManager:onSettingsChanged()
        end
    end
end

--[[
    Get settings for network sync
    @return table - All current settings
]]
function UsedPlusSettings:getNetworkData()
    return self.current
end

--[[
    Apply settings from network
    @param data - Settings table from server
]]
function UsedPlusSettings:applyNetworkData(data)
    for key, value in pairs(data) do
        self.current[key] = value
    end
    UsedPlus.logDebug("Applied settings from server")
end
```

---

## UI Integration

### InGameMenuSettingsExtension.lua

```lua
--[[
    FS25_UsedPlus - In-Game Menu Settings Extension

    Adds quick toggle switches to ESC → Settings
    Pattern from: Enhanced Animal System, Forestry Helper
]]

InGameMenuSettingsExtension = {}

-- Track our added elements for cleanup
InGameMenuSettingsExtension.elements = {}

--[[
    Initialize the extension
    Called from main.lua after game loads
]]
function InGameMenuSettingsExtension.init()
    -- Hook into InGameMenuSettingsFrame
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameOpen,
        InGameMenuSettingsExtension.onFrameOpen
    )

    InGameMenuSettingsFrame.onFrameClose = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameClose,
        InGameMenuSettingsExtension.onFrameClose
    )

    UsedPlus.logInfo("InGameMenuSettingsExtension initialized")
end

--[[
    Called when settings frame opens
]]
function InGameMenuSettingsExtension.onFrameOpen(frame)
    -- Only add once
    if InGameMenuSettingsExtension.elementsAdded then
        InGameMenuSettingsExtension.updateElements()
        return
    end

    -- Find the game settings page
    local settingsPage = frame.pageSettings
    if settingsPage == nil then
        UsedPlus.logWarn("Could not find pageSettings")
        return
    end

    -- Create section header
    local header = InGameMenuSettingsExtension.createSectionHeader(
        settingsPage,
        g_i18n:getText("usedplus_settings_header")
    )

    -- Create toggle switches for each system
    local toggles = {
        { key = "enableFinanceSystem", label = "usedplus_setting_finance" },
        { key = "enableLeaseSystem", label = "usedplus_setting_lease" },
        { key = "enableUsedVehicleSearch", label = "usedplus_setting_search" },
        { key = "enableVehicleSaleSystem", label = "usedplus_setting_sale" },
        { key = "enableRepairSystem", label = "usedplus_setting_repair" },
        { key = "enableTradeInSystem", label = "usedplus_setting_tradein" },
        { key = "enableCreditSystem", label = "usedplus_setting_credit" },
    }

    for _, toggle in ipairs(toggles) do
        local element = InGameMenuSettingsExtension.createBinaryOption(
            settingsPage,
            toggle.key,
            g_i18n:getText(toggle.label)
        )
        table.insert(InGameMenuSettingsExtension.elements, element)
    end

    -- Add "Advanced Settings" button
    local advButton = InGameMenuSettingsExtension.createAdvancedSettingsButton(settingsPage)
    table.insert(InGameMenuSettingsExtension.elements, advButton)

    InGameMenuSettingsExtension.elementsAdded = true
    InGameMenuSettingsExtension.updateElements()
end

--[[
    Called when settings frame closes
]]
function InGameMenuSettingsExtension.onFrameClose(frame)
    -- Settings auto-save on change, nothing needed here
end

--[[
    Create a section header element
]]
function InGameMenuSettingsExtension.createSectionHeader(parent, text)
    -- Clone existing header element or create new
    local header = parent.sectionHeaderTemplate:clone(parent.boxLayout)
    header:setText(text)
    return header
end

--[[
    Create a binary (on/off) option element
]]
function InGameMenuSettingsExtension.createBinaryOption(parent, settingKey, labelText)
    -- Clone existing binary option or create new
    local option = parent.binaryOptionTemplate:clone(parent.boxLayout)
    option:setLabel(labelText)
    option.settingKey = settingKey

    -- Set callback
    option.onClickCallback = function(element, state)
        InGameMenuSettingsExtension.onToggleChanged(settingKey, state == 1)
    end

    return option
end

--[[
    Create advanced settings button
]]
function InGameMenuSettingsExtension.createAdvancedSettingsButton(parent)
    local button = parent.buttonTemplate:clone(parent.boxLayout)
    button:setText(g_i18n:getText("usedplus_setting_advanced"))
    button.onClickCallback = function()
        -- Open the detailed settings dialog
        DialogLoader.show("UsedPlusSettingsDialog")
    end
    return button
end

--[[
    Update all toggle states from current settings
]]
function InGameMenuSettingsExtension.updateElements()
    for _, element in ipairs(InGameMenuSettingsExtension.elements) do
        if element.settingKey then
            local value = UsedPlusSettings:get(element.settingKey)
            element:setState(value and 1 or 0)
        end
    end
end

--[[
    Handle toggle change
]]
function InGameMenuSettingsExtension.onToggleChanged(key, enabled)
    -- Check multiplayer permissions
    if g_currentMission.missionDynamicInfo.isMultiplayer then
        if not g_currentMission:getHasMasterRights() then
            g_gui:showInfoDialog({
                text = g_i18n:getText("usedplus_setting_requires_admin")
            })
            -- Revert toggle
            InGameMenuSettingsExtension.updateElements()
            return
        end

        -- Send to server
        UsedPlusSettingsEvent.sendToServer(key, enabled)
    else
        -- Single player - apply directly
        UsedPlusSettings:set(key, enabled)
    end
end
```

---

## Savegame Persistence

### Hook into Mission Save/Load

```lua
-- In main.lua or UsedPlusSettings.lua

-- Hook savegame loading
Mission00.loadItemsFinished = Utils.appendedFunction(
    Mission00.loadItemsFinished,
    function(mission)
        local savegamePath = mission.missionInfo.savegameDirectory
        UsedPlusSettings:init(savegamePath)
    end
)

-- Hook savegame saving
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
    FSCareerMissionInfo.saveToXMLFile,
    function(missionInfo)
        UsedPlusSettings:save()
    end
)
```

---

## Network Events

### UsedPlusSettingsEvent.lua

```lua
--[[
    FS25_UsedPlus - Settings Sync Event

    Synchronizes settings changes in multiplayer
]]

UsedPlusSettingsEvent = {}
local UsedPlusSettingsEvent_mt = Class(UsedPlusSettingsEvent, Event)

InitEventClass(UsedPlusSettingsEvent, "UsedPlusSettingsEvent")

function UsedPlusSettingsEvent.emptyNew()
    local self = Event.new(UsedPlusSettingsEvent_mt)
    return self
end

function UsedPlusSettingsEvent.new(key, value)
    local self = UsedPlusSettingsEvent.emptyNew()
    self.key = key
    self.value = value
    return self
end

function UsedPlusSettingsEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    self.valueType = streamReadUInt8(streamId)

    if self.valueType == 1 then
        self.value = streamReadBool(streamId)
    elseif self.valueType == 2 then
        self.value = streamReadFloat32(streamId)
    elseif self.valueType == 3 then
        self.value = streamReadString(streamId)
    end

    self:run(connection)
end

function UsedPlusSettingsEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key)

    local valueType = type(self.value)
    if valueType == "boolean" then
        streamWriteUInt8(streamId, 1)
        streamWriteBool(streamId, self.value)
    elseif valueType == "number" then
        streamWriteUInt8(streamId, 2)
        streamWriteFloat32(streamId, self.value)
    else
        streamWriteUInt8(streamId, 3)
        streamWriteString(streamId, tostring(self.value))
    end
end

function UsedPlusSettingsEvent:run(connection)
    if g_server ~= nil then
        -- Server received from client
        -- Check permissions
        local player = g_currentMission:getPlayerByConnection(connection)
        if player and player:hasMasterRights() then
            -- Apply and broadcast to all clients
            UsedPlusSettings:set(self.key, self.value)
            g_server:broadcastEvent(UsedPlusSettingsEvent.new(self.key, self.value))
        else
            UsedPlus.logWarn("Player without master rights tried to change settings")
        end
    else
        -- Client received from server
        UsedPlusSettings:set(self.key, self.value, true) -- Skip save on client
    end
end

function UsedPlusSettingsEvent.sendToServer(key, value)
    g_client:getServerConnection():sendEvent(UsedPlusSettingsEvent.new(key, value))
end
```

---

## System Integration

### Checking Settings in Managers

```lua
-- In FinanceManager.lua
function FinanceManager:canFinanceVehicle(vehicle)
    -- Check if finance system is enabled
    if not UsedPlusSettings:isSystemEnabled("Finance") then
        return false
    end

    -- Rest of validation...
end

-- In UsedVehicleManager.lua
function UsedVehicleManager:startSearch(tier, storeItem, farmId)
    -- Check if search system is enabled
    if not UsedPlusSettings:isSystemEnabled("UsedVehicleSearch") then
        return false, "System disabled"
    end

    -- Check if this tier is enabled
    local tierEnabled = UsedPlusSettings:get("enable" .. tier .. "Search")
    if not tierEnabled then
        return false, "Search tier disabled"
    end

    -- Get tier-specific settings
    local costPercent = UsedPlusSettings:get(tier:lower() .. "SearchCostPercent")
    local searchCost = storeItem.price * (costPercent / 100)

    -- Rest of logic...
end

-- In VehicleSaleManager.lua
function VehicleSaleManager:getMaxListings(farmId)
    return UsedPlusSettings:get("maxListingsPerFarm")
end
```

---

## Testing Checklist

### Single Player

- [ ] Settings save to `usedplus_settings.xml`
- [ ] Settings load on game start
- [ ] Toggles immediately affect system availability
- [ ] Preset buttons apply correct values
- [ ] Reset to defaults works
- [ ] Advanced dialog opens from ESC menu

### Multiplayer

- [ ] Non-admin cannot change server settings
- [ ] Admin changes sync to all clients
- [ ] New player joining receives current settings
- [ ] Per-farm settings (credit score) remain separate

### System Integration

- [ ] Finance system respects `enableFinanceSystem`
- [ ] Lease system respects `enableLeaseSystem`
- [ ] Search system respects `enableUsedVehicleSearch`
- [ ] Sale system respects `enableVehicleSaleSystem`
- [ ] Repair system respects `enableRepairSystem`
- [ ] Trade-in system respects `enableTradeInSystem`
- [ ] Credit system respects `enableCreditSystem`

### UI

- [ ] ESC menu toggles appear in correct location
- [ ] Toggles reflect current state on open
- [ ] State changes save immediately
- [ ] Advanced dialog shows all settings by category
- [ ] Settings labels are localized

### Edge Cases

- [ ] Disabling finance mid-game (existing loans continue)
- [ ] Disabling search with active searches
- [ ] Disabling sale with active listings
- [ ] Changing interest rate mid-loan (existing loans unaffected)

---

## Translation Keys Needed

Add to `translations/translation_en.xml`:

```xml
<!-- Settings Section -->
<text name="usedplus_settings_header" text="UsedPlus Options"/>
<text name="usedplus_setting_finance" text="Vehicle/Land Financing"/>
<text name="usedplus_setting_lease" text="Lease-to-Own"/>
<text name="usedplus_setting_search" text="Used Vehicle Search"/>
<text name="usedplus_setting_sale" text="Vehicle Sale Agents"/>
<text name="usedplus_setting_repair" text="Partial Repair/Paint"/>
<text name="usedplus_setting_tradein" text="Trade-In System"/>
<text name="usedplus_setting_credit" text="Credit Scoring"/>
<text name="usedplus_setting_tirewear" text="Tire Wear"/>
<text name="usedplus_setting_malfunctions" text="Malfunctions"/>
<text name="usedplus_setting_advanced" text="Advanced Settings..."/>
<text name="usedplus_setting_requires_admin" text="Only the server admin can change these settings."/>

<!-- Presets -->
<text name="usedplus_preset_casual" text="Casual"/>
<text name="usedplus_preset_realistic" text="Realistic"/>
<text name="usedplus_preset_hardcore" text="Hardcore"/>
<text name="usedplus_preset_apply" text="Apply Preset"/>

<!-- Advanced Dialog -->
<text name="usedplus_adv_title" text="UsedPlus Advanced Settings"/>
<text name="usedplus_adv_finance_section" text="Finance Settings"/>
<text name="usedplus_adv_lease_section" text="Lease Settings"/>
<text name="usedplus_adv_search_section" text="Search Settings"/>
<text name="usedplus_adv_sale_section" text="Sale Settings"/>
<text name="usedplus_adv_repair_section" text="Repair Settings"/>
<text name="usedplus_adv_tradein_section" text="Trade-In Settings"/>
<text name="usedplus_adv_credit_section" text="Credit Settings"/>
<text name="usedplus_adv_reset" text="Reset to Defaults"/>
```
