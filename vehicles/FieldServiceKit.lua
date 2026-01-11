--[[
    FS25_UsedPlus - OBD Scanner Vehicle Specialization

    A consumable hand tool that allows emergency field repairs on disabled vehicles.
    Player carries the scanner to a broken vehicle, activates it, and plays a diagnosis
    minigame to attempt repairs. Scanner is consumed after single use.

    Based on: FS25_MobileServiceKit by w33zl (with acknowledgment)

    v1.8.0 - Field Service Kit System
    v2.0.0 - Full RVB/UYT cross-mod integration
            - findNearbyVehicles() now detects RVB part failures and UYT tire wear
            - Activation prompt shows specific warning sources (RVB, Tires, Engine, etc.)
            - Renamed from Field Service Kit to OBD Scanner
    v2.0.1 - Fixed activation prompt not appearing
            - Now uses g_localPlayer pattern (FS25 standard) instead of g_currentMission.player
            - Added raiseActive() to ensure onUpdate calls continue for ground objects
            - Pattern from: OilServicePoint.lua which works correctly
            - Changed keybind from R to O (custom USEDPLUS_ACTIVATE_OBD action)
            - Avoids conflict with Realistic Breakdowns jumper cable
    v2.0.2 - Fixed keybind prompt not showing for ground objects
            - setActionEventTextVisibility only works for vehicle controls (when IN a vehicle)
            - Now uses addExtraPrintText for on-foot prompt display
            - Uses getDigitalInputAxis for direct input checking (respects key rebinding)
            - Removed callback-based approach which doesn't work for non-controlled objects
    v2.0.3 - Implemented proper on-foot input using PlayerInputComponent pattern
            - Pattern from: FS25_CutOpenBale - hooks PlayerInputComponent.registerGlobalPlayerActionEvents
            - Global action event registration works for on-foot interactions
            - Proper keybind display with O key (no conflict with RVB jumper cable)
]]

FieldServiceKit = {}
FieldServiceKit.MOD_NAME = g_currentModName or "FS25_UsedPlus"

-- Global tracking for on-foot input system
FieldServiceKit.instances = {}           -- All active OBD scanner instances
FieldServiceKit.actionEventId = nil      -- Global action event ID
FieldServiceKit.nearestScanner = nil     -- Currently nearest scanner to player
FieldServiceKit.scannerText = ""         -- Current action text

local SPEC_NAME = "spec_fieldServiceKit"

function FieldServiceKit.prerequisitesPresent(specializations)
    return true
end

function FieldServiceKit.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "findNearbyVehicles", FieldServiceKit.findNearbyVehicles)
    SpecializationUtil.registerFunction(vehicleType, "getTargetVehicle", FieldServiceKit.getTargetVehicle)
    SpecializationUtil.registerFunction(vehicleType, "activateFieldService", FieldServiceKit.activateFieldService)
    SpecializationUtil.registerFunction(vehicleType, "consumeKit", FieldServiceKit.consumeKit)
    SpecializationUtil.registerFunction(vehicleType, "updateActionEventText", FieldServiceKit.updateActionEventText)
    SpecializationUtil.registerFunction(vehicleType, "onActivateOBD", FieldServiceKit.onActivateOBD)
    SpecializationUtil.registerFunction(vehicleType, "getActivatePromptText", FieldServiceKit.getActivatePromptText)
end

function FieldServiceKit.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", FieldServiceKit)
end

--[[
    v2.0.3: Global callback when O key is pressed (on-foot)
    Called by the global player action event system
]]
function FieldServiceKit.onGlobalActivateOBD()
    if FieldServiceKit.nearestScanner ~= nil then
        local scanner = FieldServiceKit.nearestScanner
        local spec = scanner[SPEC_NAME]
        if spec ~= nil and not spec.isConsumed then
            scanner:activateFieldService()
        end
    end
end

--[[
    v2.0.3: Update action event visibility based on nearest scanner
    Called from onUpdate of each scanner instance
]]
function FieldServiceKit.updateGlobalActionEvent()
    if FieldServiceKit.actionEventId == nil then
        return
    end

    local hasNearbyScanner = FieldServiceKit.nearestScanner ~= nil
    g_inputBinding:setActionEventActive(FieldServiceKit.actionEventId, hasNearbyScanner)
    g_inputBinding:setActionEventTextVisibility(FieldServiceKit.actionEventId, hasNearbyScanner)

    if hasNearbyScanner then
        g_inputBinding:setActionEventText(FieldServiceKit.actionEventId, FieldServiceKit.scannerText)
        g_inputBinding:setActionEventTextPriority(FieldServiceKit.actionEventId, GS_PRIO_VERY_HIGH)
    end
end

--[[
    v2.0.3: Hook into PlayerInputComponent to register global on-foot action
    Pattern from: FS25_CutOpenBale
]]
function FieldServiceKit.registerGlobalPlayerActionEvents()
    if FieldServiceKit.actionEventId == nil then
        -- Use InputAction.ACTIONNAME pattern (not string) for proper registration
        local actionId = InputAction.USEDPLUS_ACTIVATE_OBD
        if actionId == nil then
            UsedPlus.logInfo("OBD Scanner: InputAction.USEDPLUS_ACTIVATE_OBD not found, trying string")
            actionId = "USEDPLUS_ACTIVATE_OBD"
        else
            UsedPlus.logInfo("OBD Scanner: Found InputAction.USEDPLUS_ACTIVATE_OBD")
        end

        -- v2.0.3: Match CutBale pattern exactly:
        -- Param 2 is a string identifier, not a target object
        -- Callback is a plain function reference
        local valid, eventId = g_inputBinding:registerActionEvent(
            actionId,                            -- Action from modDesc.xml
            "USEDPLUS_ACTIVATE_OBD",             -- String identifier (CutBale pattern)
            FieldServiceKit.onGlobalActivateOBD, -- Callback function
            false,                               -- triggerUp
            true,                                -- triggerDown (fire when pressed)
            false,                               -- triggerAlways
            true                                 -- startActive
        )

        UsedPlus.logInfo("OBD Scanner: registerActionEvent returned valid=" .. tostring(valid) .. ", eventId=" .. tostring(eventId))

        if valid then
            FieldServiceKit.actionEventId = eventId
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
            g_inputBinding:setActionEventActive(eventId, false)  -- Start hidden
            g_inputBinding:setActionEventTextVisibility(eventId, false)
            UsedPlus.logInfo("OBD Scanner: Global action event registered (O key), eventId=" .. tostring(eventId))
        else
            UsedPlus.logInfo("OBD Scanner: Failed to register global action event")
        end
    end
end

-- Hook into PlayerInputComponent.registerGlobalPlayerActionEvents
-- This is called when the player spawns/loads
if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        FieldServiceKit.registerGlobalPlayerActionEvents
    )
    UsedPlus.logInfo("OBD Scanner: Hooked PlayerInputComponent.registerGlobalPlayerActionEvents")
else
    -- Fallback: Hook when the script is loaded by the game
    -- This handles cases where PlayerInputComponent isn't available at load time
    UsedPlus.logInfo("OBD Scanner: PlayerInputComponent not available yet")

    -- Try again after a delay using Mission00.onStartMission
    if Mission00 ~= nil then
        Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission or function() end, function()
            if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
                if FieldServiceKit.hookInstalled ~= true then
                    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
                        PlayerInputComponent.registerGlobalPlayerActionEvents,
                        FieldServiceKit.registerGlobalPlayerActionEvents
                    )
                    FieldServiceKit.hookInstalled = true
                    UsedPlus.logInfo("OBD Scanner: Late-hooked PlayerInputComponent (via Mission00)")
                end
            end
        end)
    end
end

function FieldServiceKit.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("FieldServiceKit")

    schema:register(XMLValueType.STRING, "vehicle.fieldServiceKit#kitTier", "Kit tier: basic, professional, or master", "basic")
    schema:register(XMLValueType.FLOAT, "vehicle.fieldServiceKit#detectionRadius", "Radius to detect nearby vehicles", 5.0)
    schema:register(XMLValueType.NODE_INDEX, "vehicle.fieldServiceKit#playerTriggerNode", "Trigger node for player activation")
    schema:register(XMLValueType.NODE_INDEX, "vehicle.fieldServiceKit#vehicleTriggerNode", "Trigger node for vehicle detection")

    schema:setXMLSpecializationType()
end

function FieldServiceKit:onLoad(savegame)
    self[SPEC_NAME] = {}
    local spec = self[SPEC_NAME]

    -- Load configuration from XML
    spec.kitTier = self.xmlFile:getValue("vehicle.fieldServiceKit#kitTier", "basic")
    spec.detectionRadius = self.xmlFile:getValue("vehicle.fieldServiceKit#detectionRadius", 5.0)

    -- State tracking
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil
    spec.isActivated = false
    spec.isConsumed = false
    spec.playerNearby = false

    -- v2.0.1: Removed activatable system - using custom input instead to avoid R key conflict
    -- The activatable system forces use of ACTIVATE action (R key) which conflicts with
    -- Realistic Breakdowns jumper cable. Now using custom USEDPLUS_ACTIVATE_OBD action (O key).

    -- Load trigger nodes
    local playerTriggerNode = self.xmlFile:getValue("vehicle.fieldServiceKit#playerTriggerNode", nil, self.components, self.i3dMappings)
    local vehicleTriggerNode = self.xmlFile:getValue("vehicle.fieldServiceKit#vehicleTriggerNode", nil, self.components, self.i3dMappings)

    -- Set up player trigger if node exists
    if playerTriggerNode ~= nil then
        spec.playerTriggerNode = playerTriggerNode
        addTrigger(playerTriggerNode, "playerTriggerCallback", self)
    end

    -- Set up vehicle detection trigger if node exists
    if vehicleTriggerNode ~= nil then
        spec.vehicleTriggerNode = vehicleTriggerNode
        addTrigger(vehicleTriggerNode, "vehicleTriggerCallback", self)
    end

    -- v2.0.3: Register this scanner instance globally for proximity detection
    table.insert(FieldServiceKit.instances, self)

    -- Request updates - critical for objects on the ground to receive onUpdate calls
    -- Pattern from: OilServicePoint.lua
    self:raiseActive()

    UsedPlus.logInfo("FieldServiceKit loaded - tier: " .. spec.kitTier .. " (v2.0.3 - PlayerInputComponent pattern)")
end

function FieldServiceKit:onDelete()
    local spec = self[SPEC_NAME]

    if spec.playerTriggerNode ~= nil then
        removeTrigger(spec.playerTriggerNode)
    end

    if spec.vehicleTriggerNode ~= nil then
        removeTrigger(spec.vehicleTriggerNode)
    end

    -- v2.0.3: Unregister this scanner instance from global tracking
    for i, instance in ipairs(FieldServiceKit.instances) do
        if instance == self then
            table.remove(FieldServiceKit.instances, i)
            break
        end
    end

    -- Clear nearest scanner if it was this one
    if FieldServiceKit.nearestScanner == self then
        FieldServiceKit.nearestScanner = nil
        FieldServiceKit.updateGlobalActionEvent()
    end
end

function FieldServiceKit:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[SPEC_NAME]

    -- Keep requesting updates (critical for objects on the ground)
    -- Pattern from: OilServicePoint.lua which works correctly
    self:raiseActive()

    -- Handle consumed kit - make invisible and stop all processing
    if spec.pendingDeletion then
        -- Clear flag first to prevent multiple processing
        spec.pendingDeletion = false

        -- If this was the nearest scanner, clear it
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
            FieldServiceKit.updateGlobalActionEvent()
        end

        -- Hide the kit visually instead of deleting (safer)
        if self.rootNode ~= nil then
            setVisibility(self.rootNode, false)
        end

        UsedPlus.logInfo("FieldServiceKit: Kit consumed and hidden")
        return
    end

    if spec.isConsumed then
        -- If this was the nearest scanner, clear it
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
            FieldServiceKit.updateGlobalActionEvent()
        end
        return
    end

    -- Update nearby vehicle detection (finds ANY vehicle, not just broken ones)
    self:findNearbyVehicles()

    -- v2.0.3: Check player proximity and update global action event
    local playerNearby = false
    local playerDistance = 999999
    local activationRadius = 2.5  -- meters

    if self.rootNode ~= nil and g_localPlayer ~= nil then
        -- Check if player is on foot (not in a vehicle)
        local isOnFoot = true
        if g_localPlayer.getIsInVehicle ~= nil then
            isOnFoot = not g_localPlayer:getIsInVehicle()
        end
        if g_currentMission.controlledVehicle ~= nil then
            isOnFoot = false
        end

        if isOnFoot then
            local kx, ky, kz = getWorldTranslation(self.rootNode)
            local px, py, pz
            if g_localPlayer.getPosition ~= nil then
                px, py, pz = g_localPlayer:getPosition()
            elseif g_localPlayer.rootNode ~= nil then
                px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
            end

            if px ~= nil then
                playerDistance = MathUtil.vector2Length(kx - px, kz - pz)
                playerNearby = playerDistance <= activationRadius
            end
        end
    end

    spec.playerNearby = playerNearby
    spec.playerDistance = playerDistance

    -- v2.0.3: Update global nearest scanner tracking
    -- Each scanner checks if it's the closest one to the player
    if playerNearby and not spec.isConsumed then
        local currentNearest = FieldServiceKit.nearestScanner
        local shouldBeNearest = false

        if currentNearest == nil then
            shouldBeNearest = true
        elseif currentNearest == self then
            shouldBeNearest = true
        else
            -- Check if we're closer than the current nearest
            local currentSpec = currentNearest[SPEC_NAME]
            if currentSpec == nil or currentSpec.playerDistance == nil or playerDistance < currentSpec.playerDistance then
                shouldBeNearest = true
            end
        end

        if shouldBeNearest then
            FieldServiceKit.nearestScanner = self
            -- Build the action text
            local actionText = g_i18n:getText("usedplus_fsk_activate") or "Use OBD Scanner"
            if spec.targetVehicle ~= nil then
                local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
                actionText = actionText .. " - " .. vehicleName
            end
            FieldServiceKit.scannerText = actionText
            FieldServiceKit.updateGlobalActionEvent()
        end
    else
        -- Player not nearby this scanner - clear if we were the nearest
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
            FieldServiceKit.updateGlobalActionEvent()
        end
    end
end

--[[
    Update the action event text to show vehicle info
]]
function FieldServiceKit:updateActionEventText()
    local spec = self[SPEC_NAME]
    if spec.actionEventId == nil then return end

    local baseText = g_i18n:getText("usedplus_fsk_activate") or "Use OBD Scanner"

    if spec.targetVehicle ~= nil then
        local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
        local target = spec.targetVehicle

        if target.isDisabled then
            baseText = string.format("%s - %s (DISABLED)", baseText, vehicleName)
        elseif target.needsService then
            -- Show specific warning source
            local warnings = {}
            if target.hasRVBIssue then table.insert(warnings, "RVB") end
            if target.hasUYTIssue then table.insert(warnings, "Tires") end
            if target.hasMaintenance then
                local maintSpec = target.vehicle.spec_usedPlusMaintenance
                if maintSpec then
                    if maintSpec.engineReliability < 0.5 then table.insert(warnings, "Engine") end
                    if maintSpec.electricalReliability < 0.5 then table.insert(warnings, "Electrical") end
                    if maintSpec.hydraulicReliability < 0.5 then table.insert(warnings, "Hydraulic") end
                end
            end
            if #warnings > 0 then
                baseText = string.format("%s - %s (%s)", baseText, vehicleName, table.concat(warnings, ", "))
            else
                baseText = string.format("%s - %s (Needs Service)", baseText, vehicleName)
            end
        else
            baseText = string.format("%s - %s", baseText, vehicleName)
        end
    end

    g_inputBinding:setActionEventText(spec.actionEventId, baseText)
end

--[[
    Callback when our custom O key action is triggered
]]
function FieldServiceKit:onActivateOBD(actionName, inputValue, callbackState, isAnalog)
    local spec = self[SPEC_NAME]
    if spec.playerNearby and not spec.isConsumed then
        self:activateFieldService()
    end
end

--[[
    Get the prompt text to display when player is near the kit
    v2.0.1: Shows vehicle info and key binding
]]
function FieldServiceKit:getActivatePromptText()
    local spec = self[SPEC_NAME]

    -- Get the key name for our action (with safe fallback)
    local keyName = "O"  -- Default fallback
    if g_inputBinding.getFirstActiveBinding ~= nil then
        local success, actionBinding = pcall(function()
            return g_inputBinding:getFirstActiveBinding("USEDPLUS_ACTIVATE_OBD")
        end)
        if success and actionBinding ~= nil and actionBinding.getKeyName ~= nil then
            keyName = actionBinding:getKeyName() or "O"
        end
    end

    -- Base prompt
    local baseText = g_i18n:getText("usedplus_fsk_activate") or "Use OBD Scanner"

    -- Add vehicle info if we have a target
    if spec.targetVehicle ~= nil then
        local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
        local target = spec.targetVehicle

        if target.isDisabled then
            baseText = string.format("%s - %s (DISABLED)", baseText, vehicleName)
        elseif target.needsService then
            -- Show specific warning source
            local warnings = {}
            if target.hasRVBIssue then table.insert(warnings, "RVB") end
            if target.hasUYTIssue then table.insert(warnings, "Tires") end
            if target.hasMaintenance then
                local maintSpec = target.vehicle.spec_usedPlusMaintenance
                if maintSpec then
                    if maintSpec.engineReliability < 0.5 then table.insert(warnings, "Engine") end
                    if maintSpec.electricalReliability < 0.5 then table.insert(warnings, "Electrical") end
                    if maintSpec.hydraulicReliability < 0.5 then table.insert(warnings, "Hydraulic") end
                end
            end
            if #warnings > 0 then
                baseText = string.format("%s - %s (%s)", baseText, vehicleName, table.concat(warnings, ", "))
            else
                baseText = string.format("%s - %s (Needs Service)", baseText, vehicleName)
            end
        else
            baseText = string.format("%s - %s", baseText, vehicleName)
        end
    end

    -- Format with key binding
    return string.format("[%s] %s", keyName, baseText)
end

--[[
    Find vehicles within detection radius
    v1.9.9: Find ANY vehicle for OBD scanning, not just broken ones
    v2.0.0: Uses ModCompatibility for RVB/UYT cross-mod detection
    The scanner can diagnose any vehicle's health status
]]
function FieldServiceKit:findNearbyVehicles()
    local spec = self[SPEC_NAME]
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil

    if self.rootNode == nil then
        UsedPlus.logInfo("FieldServiceKit:findNearbyVehicles - rootNode is nil!")
        return
    end

    local x, y, z = getWorldTranslation(self.rootNode)
    -- v2.0.3: Increased detection radius to 15m for better usability
    local radius = spec.detectionRadius or 15.0
    local radiusSq = radius * radius

    -- DEBUG: Removed verbose logging - was flooding logs

    -- Check all vehicles in mission
    -- v2.0.3: Use g_currentMission.vehicleSystem.vehicles (FS25 standard pattern)
    if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= self and vehicle.rootNode ~= nil then
                local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                local distSq = (x - vx)^2 + (y - vy)^2 + (z - vz)^2
                local dist = math.sqrt(distSq)

                if distSq <= radiusSq then
                    -- v2.0.0: Use ModCompatibility for cross-mod health detection
                    local maintSpec = vehicle.spec_usedPlusMaintenance
                    local isDisabled = maintSpec and maintSpec.isDisabled or false
                    local needsService = false
                    local hasRVBIssue = false
                    local hasUYTIssue = false

                    -- Check UsedPlus maintenance if available
                    if maintSpec then
                        needsService = isDisabled or
                                      maintSpec.engineReliability < 0.5 or
                                      maintSpec.electricalReliability < 0.5 or
                                      maintSpec.hydraulicReliability < 0.5
                    end

                    -- v2.0.0: Check RVB part failures via ModCompatibility
                    if ModCompatibility and ModCompatibility.rvbInstalled then
                        -- Check engine parts
                        if ModCompatibility.isRVBPartFailed(vehicle, "ENGINE") or
                           ModCompatibility.isRVBPartFailed(vehicle, "THERMOSTAT") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "ENGINE") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "THERMOSTAT") then
                            hasRVBIssue = true
                        end

                        -- Check electrical parts
                        if ModCompatibility.isRVBPartFailed(vehicle, "GENERATOR") or
                           ModCompatibility.isRVBPartFailed(vehicle, "BATTERY") or
                           ModCompatibility.isRVBPartFailed(vehicle, "SELFSTARTER") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "GENERATOR") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "BATTERY") then
                            hasRVBIssue = true
                        end

                        -- Check for low part life (<30%)
                        local engineLife = ModCompatibility.getRVBPartLife(vehicle, "ENGINE")
                        local genLife = ModCompatibility.getRVBPartLife(vehicle, "GENERATOR")
                        local batLife = ModCompatibility.getRVBPartLife(vehicle, "BATTERY")
                        if engineLife < 0.3 or genLife < 0.3 or batLife < 0.3 then
                            hasRVBIssue = true
                        end
                    end

                    -- v2.0.0: Check UYT tire wear via ModCompatibility
                    if ModCompatibility and ModCompatibility.uytInstalled then
                        local maxWear = ModCompatibility.getUYTMaxTireWear(vehicle)
                        if maxWear > 0.8 then  -- >80% worn
                            hasUYTIssue = true
                        end
                    end

                    -- Combine all sources for needsService indicator
                    needsService = needsService or hasRVBIssue or hasUYTIssue

                    -- Add ANY vehicle within range (OBD scanner can diagnose any vehicle)
                    table.insert(spec.nearbyVehicles, {
                        vehicle = vehicle,
                        distance = math.sqrt(distSq),
                        isDisabled = isDisabled,
                        needsService = needsService,
                        hasRVBIssue = hasRVBIssue,
                        hasUYTIssue = hasUYTIssue,
                        hasMaintenance = maintSpec ~= nil,
                        failedSystem = maintSpec and maintSpec.lastFailedSystem or nil
                    })
                end
            end
        end
    end

    -- Sort by distance and pick closest
    table.sort(spec.nearbyVehicles, function(a, b) return a.distance < b.distance end)

    if #spec.nearbyVehicles > 0 then
        spec.targetVehicle = spec.nearbyVehicles[1]
    end
end

--[[
    Get the current target vehicle (closest serviceable vehicle)
]]
function FieldServiceKit:getTargetVehicle()
    local spec = self[SPEC_NAME]
    return spec.targetVehicle
end

--[[
    Activate field service - opens the diagnosis dialog
    v1.9.9: Shows message if no vehicle nearby, otherwise opens OBD Scanner
]]
function FieldServiceKit:activateFieldService()
    local spec = self[SPEC_NAME]
    if spec == nil or spec.isConsumed then
        return false
    end

    -- Re-scan for vehicles at activation time
    self:findNearbyVehicles()

    if spec.targetVehicle == nil then
        -- No vehicle nearby - show info message
        local infoText = g_i18n:getText("usedplus_fsk_noVehicle") or "No vehicle detected within range. Move the scanner closer to a vehicle."
        if InfoDialog ~= nil and InfoDialog.show ~= nil then
            InfoDialog.show(infoText)
        else
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, infoText)
        end
        return false
    end

    -- Ensure dialog is registered before showing
    if FieldServiceKitDialog ~= nil and FieldServiceKitDialog.register ~= nil then
        FieldServiceKitDialog.register()
    else
        UsedPlus.logError("FieldServiceKit: FieldServiceKitDialog class not found!")
        return false
    end

    -- Open the field service dialog
    local dialog = g_gui:showDialog("FieldServiceKitDialog")
    if dialog == nil then
        UsedPlus.logError("FieldServiceKit: Dialog failed to open")
        return false
    end

    if dialog.target ~= nil then
        dialog.target:setData(spec.targetVehicle.vehicle, self, spec.kitTier)
    end

    return true
end

--[[
    Consume the kit after use - schedules deletion
]]
function FieldServiceKit:consumeKit()
    local spec = self[SPEC_NAME]

    if spec.isConsumed then
        return
    end

    spec.isConsumed = true
    UsedPlus.logInfo("FieldServiceKit consumed - scheduling deletion")

    -- Disable our custom input action
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
        g_inputBinding:setActionEventTextVisibility(spec.actionEventId, false)
        spec.actionEventActive = false
    end

    -- Mark for deletion on next update cycle
    -- We use a flag instead of immediate deletion to avoid issues during event handling
    spec.pendingDeletion = true
    UsedPlus.logInfo("FieldServiceKit: Kit marked for deletion")
end

--[[
    Player trigger callback - when player enters/exits trigger zone
]]
function FieldServiceKit:playerTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if not onEnter and not onLeave then
        return
    end

    local spec = self[SPEC_NAME]

    -- Check if it's the player
    if g_currentMission.player ~= nil and g_currentMission.player.rootNode == otherId then
        if onEnter then
            spec.playerInTrigger = true
        elseif onLeave then
            spec.playerInTrigger = false
        end
    end
end

--[[
    Vehicle trigger callback - when vehicles enter/exit detection zone
]]
function FieldServiceKit:vehicleTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    -- Vehicle detection is handled in onUpdate via findNearbyVehicles()
    -- This callback could be used for more precise collision-based detection
end

-- v2.0.1: Removed onRegisterActionEvents and FieldServiceKitActivatable class
-- Now using direct g_inputBinding:registerActionEvent() in onLoad for custom O key binding
-- This avoids conflict with Realistic Breakdowns jumper cable (R key)
-- The activatable system forces use of ACTIVATE action which is always bound to R
