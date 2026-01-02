--[[
    FS25_UsedPlus - Settings Sync Event

    Synchronizes settings changes in multiplayer.

    Two modes:
    1. Single setting change (key/value pair)
    2. Bulk sync (all settings at once, used on player join)

    Only players with master rights can change settings.
    Server broadcasts changes to all clients.
]]

UsedPlusSettingsEvent = {}
local UsedPlusSettingsEvent_mt = Class(UsedPlusSettingsEvent, Event)

InitEventClass(UsedPlusSettingsEvent, "UsedPlusSettingsEvent")

-- Event types
UsedPlusSettingsEvent.TYPE_SINGLE = 1    -- Single setting change
UsedPlusSettingsEvent.TYPE_BULK = 2      -- All settings (sync on join)
UsedPlusSettingsEvent.TYPE_PRESET = 3    -- Apply preset

function UsedPlusSettingsEvent.emptyNew()
    local self = Event.new(UsedPlusSettingsEvent_mt)
    self.eventType = UsedPlusSettingsEvent.TYPE_SINGLE
    self.key = nil
    self.value = nil
    self.settings = nil
    self.presetName = nil
    return self
end

--[[
    Create event for single setting change
    @param key - Setting key
    @param value - New value
]]
function UsedPlusSettingsEvent.newSingle(key, value)
    local self = UsedPlusSettingsEvent.emptyNew()
    self.eventType = UsedPlusSettingsEvent.TYPE_SINGLE
    self.key = key
    self.value = value
    return self
end

--[[
    Create event for bulk settings sync
    @param settings - Table of all settings
]]
function UsedPlusSettingsEvent.newBulk(settings)
    local self = UsedPlusSettingsEvent.emptyNew()
    self.eventType = UsedPlusSettingsEvent.TYPE_BULK
    self.settings = settings
    return self
end

--[[
    Create event for preset application
    @param presetName - Name of preset to apply
]]
function UsedPlusSettingsEvent.newPreset(presetName)
    local self = UsedPlusSettingsEvent.emptyNew()
    self.eventType = UsedPlusSettingsEvent.TYPE_PRESET
    self.presetName = presetName
    return self
end

function UsedPlusSettingsEvent:readStream(streamId, connection)
    self.eventType = streamReadUInt8(streamId)

    if self.eventType == UsedPlusSettingsEvent.TYPE_SINGLE then
        -- Read single key/value
        self.key = streamReadString(streamId)
        local valueType = streamReadUInt8(streamId)

        if valueType == 1 then
            self.value = streamReadBool(streamId)
        elseif valueType == 2 then
            self.value = streamReadFloat32(streamId)
        else
            self.value = streamReadString(streamId)
        end

    elseif self.eventType == UsedPlusSettingsEvent.TYPE_BULK then
        -- Read all settings
        self.settings = {}
        local count = streamReadUInt16(streamId)

        for i = 1, count do
            local key = streamReadString(streamId)
            local valueType = streamReadUInt8(streamId)
            local value

            if valueType == 1 then
                value = streamReadBool(streamId)
            elseif valueType == 2 then
                value = streamReadFloat32(streamId)
            else
                value = streamReadString(streamId)
            end

            self.settings[key] = value
        end

    elseif self.eventType == UsedPlusSettingsEvent.TYPE_PRESET then
        -- Read preset name
        self.presetName = streamReadString(streamId)
    end

    self:run(connection)
end

function UsedPlusSettingsEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.eventType)

    if self.eventType == UsedPlusSettingsEvent.TYPE_SINGLE then
        -- Write single key/value
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

    elseif self.eventType == UsedPlusSettingsEvent.TYPE_BULK then
        -- Count settings
        local count = 0
        for _ in pairs(self.settings) do
            count = count + 1
        end

        streamWriteUInt16(streamId, count)

        -- Write each setting
        for key, value in pairs(self.settings) do
            streamWriteString(streamId, key)

            local valueType = type(value)
            if valueType == "boolean" then
                streamWriteUInt8(streamId, 1)
                streamWriteBool(streamId, value)
            elseif valueType == "number" then
                streamWriteUInt8(streamId, 2)
                streamWriteFloat32(streamId, value)
            else
                streamWriteUInt8(streamId, 3)
                streamWriteString(streamId, tostring(value))
            end
        end

    elseif self.eventType == UsedPlusSettingsEvent.TYPE_PRESET then
        -- Write preset name
        streamWriteString(streamId, self.presetName)
    end
end

function UsedPlusSettingsEvent:run(connection)
    if g_server ~= nil then
        -- Server received event from client
        -- Check if sender has master rights
        if not self:senderHasMasterRights(connection) then
            UsedPlus.logWarn("UsedPlusSettingsEvent: Rejected - sender lacks master rights")
            return
        end

        -- Apply the change
        if self.eventType == UsedPlusSettingsEvent.TYPE_SINGLE then
            UsedPlusSettings:set(self.key, self.value, false, false)
        elseif self.eventType == UsedPlusSettingsEvent.TYPE_BULK then
            UsedPlusSettings:applyFromNetwork(self.settings)
        elseif self.eventType == UsedPlusSettingsEvent.TYPE_PRESET then
            UsedPlusSettings:applyPreset(self.presetName)
        end

        -- Broadcast to all clients
        g_server:broadcastEvent(self, false)

    else
        -- Client received event from server
        if self.eventType == UsedPlusSettingsEvent.TYPE_SINGLE then
            UsedPlusSettings:set(self.key, self.value, true, false)  -- Skip save on client
        elseif self.eventType == UsedPlusSettingsEvent.TYPE_BULK then
            UsedPlusSettings:applyFromNetwork(self.settings)
        elseif self.eventType == UsedPlusSettingsEvent.TYPE_PRESET then
            UsedPlusSettings:applyPreset(self.presetName)
        end
    end
end

--[[
    Check if the connection sender has master rights
    @param connection - Network connection
    @return boolean
]]
function UsedPlusSettingsEvent:senderHasMasterRights(connection)
    if connection == nil then
        return true  -- Local/server
    end

    -- Find player by connection
    local player = g_currentMission:getPlayerByConnection(connection)
    if player == nil then
        return false
    end

    -- Check master rights
    if player.isMasterUser then
        return true
    end

    -- Alternative check via user manager
    if g_currentMission.userManager then
        local user = g_currentMission.userManager:getUserByConnection(connection)
        if user and user:getIsMasterUser() then
            return true
        end
    end

    return false
end

--[[
    Send a single setting change to server
    @param key - Setting key
    @param value - New value
]]
function UsedPlusSettingsEvent.sendSingleToServer(key, value)
    if g_client then
        g_client:getServerConnection():sendEvent(UsedPlusSettingsEvent.newSingle(key, value))
    end
end

--[[
    Send a preset application to server
    @param presetName - Preset name
]]
function UsedPlusSettingsEvent.sendPresetToServer(presetName)
    if g_client then
        g_client:getServerConnection():sendEvent(UsedPlusSettingsEvent.newPreset(presetName))
    end
end

--[[
    Send all settings to a specific connection (for player join sync)
    @param connection - Target connection
]]
function UsedPlusSettingsEvent.sendAllToConnection(connection)
    if g_server then
        local settings = UsedPlusSettings:getAllSettings()
        connection:sendEvent(UsedPlusSettingsEvent.newBulk(settings))
    end
end

UsedPlus.logInfo("UsedPlusSettingsEvent loaded")
