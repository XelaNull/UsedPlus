--[[
    FS25_UsedPlus - Field Service Kit Vehicle Specialization

    A consumable hand tool that allows emergency field repairs on disabled vehicles.
    Player carries the kit to a broken vehicle, activates it, and plays a diagnosis
    minigame to attempt repairs. Kit is consumed after single use.

    Based on: FS25_MobileServiceKit by w33zl (with acknowledgment)

    v1.8.0 - Field Service Kit System
]]

FieldServiceKit = {}
FieldServiceKit.MOD_NAME = g_currentModName or "FS25_UsedPlus"

local SPEC_NAME = "spec_fieldServiceKit"

function FieldServiceKit.prerequisitesPresent(specializations)
    return true
end

function FieldServiceKit.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "findNearbyVehicles", FieldServiceKit.findNearbyVehicles)
    SpecializationUtil.registerFunction(vehicleType, "getTargetVehicle", FieldServiceKit.getTargetVehicle)
    SpecializationUtil.registerFunction(vehicleType, "activateFieldService", FieldServiceKit.activateFieldService)
    SpecializationUtil.registerFunction(vehicleType, "consumeKit", FieldServiceKit.consumeKit)
end

function FieldServiceKit.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", FieldServiceKit)
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

    -- Create activatable for player interaction
    spec.activatable = FieldServiceKitActivatable.new(self)

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

    UsedPlus.logDebug("FieldServiceKit loaded - tier: " .. spec.kitTier)
end

function FieldServiceKit:onDelete()
    local spec = self[SPEC_NAME]

    if spec.playerTriggerNode ~= nil then
        removeTrigger(spec.playerTriggerNode)
    end

    if spec.vehicleTriggerNode ~= nil then
        removeTrigger(spec.vehicleTriggerNode)
    end

    if spec.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end

function FieldServiceKit:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[SPEC_NAME]

    if spec.isConsumed then
        return
    end

    -- Update nearby vehicle detection
    self:findNearbyVehicles()

    -- Update activatable state
    if spec.activatable ~= nil then
        local canActivate = spec.targetVehicle ~= nil

        if canActivate and not spec.activatable.isActive then
            g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
            spec.activatable.isActive = true
        elseif not canActivate and spec.activatable.isActive then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
            spec.activatable.isActive = false
        end
    end
end

--[[
    Find vehicles within detection radius that have UsedPlusMaintenance
]]
function FieldServiceKit:findNearbyVehicles()
    local spec = self[SPEC_NAME]
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil

    if self.rootNode == nil then
        return
    end

    local x, y, z = getWorldTranslation(self.rootNode)
    local radiusSq = spec.detectionRadius * spec.detectionRadius

    -- Check all vehicles in mission
    if g_currentMission ~= nil and g_currentMission.vehicles ~= nil then
        for _, vehicle in pairs(g_currentMission.vehicles) do
            if vehicle ~= self and vehicle.rootNode ~= nil then
                -- Check if vehicle has our maintenance system
                local maintSpec = vehicle.spec_usedPlusMaintenance
                if maintSpec ~= nil then
                    local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                    local distSq = (x - vx)^2 + (y - vy)^2 + (z - vz)^2

                    if distSq <= radiusSq then
                        -- Check if vehicle needs service (disabled or low reliability)
                        local needsService = maintSpec.isDisabled or
                                            maintSpec.engineReliability < 0.5 or
                                            maintSpec.electricalReliability < 0.5 or
                                            maintSpec.hydraulicReliability < 0.5

                        if needsService then
                            table.insert(spec.nearbyVehicles, {
                                vehicle = vehicle,
                                distance = math.sqrt(distSq),
                                isDisabled = maintSpec.isDisabled or false,
                                failedSystem = maintSpec.lastFailedSystem
                            })
                        end
                    end
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
]]
function FieldServiceKit:activateFieldService()
    local spec = self[SPEC_NAME]

    if spec.targetVehicle == nil then
        UsedPlus.logDebug("FieldServiceKit: No target vehicle")
        return false
    end

    if spec.isConsumed then
        UsedPlus.logDebug("FieldServiceKit: Already consumed")
        return false
    end

    UsedPlus.logDebug("FieldServiceKit: Activating for " .. tostring(spec.targetVehicle.vehicle:getName()))

    -- Open the field service dialog
    local dialog = g_gui:showDialog("FieldServiceKitDialog")
    if dialog ~= nil and dialog.target ~= nil then
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

    -- Remove from activatable system
    if spec.activatable ~= nil and spec.activatable.isActive then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        spec.activatable.isActive = false
    end

    -- Schedule vehicle deletion after a short delay
    g_currentMission:addGameTimeUpdateable(function(dt)
        if self.isDeleted then
            return true  -- Stop updating
        end

        -- Delete the vehicle (the kit)
        if g_server ~= nil then
            g_currentMission:removeVehicle(self)
        end

        return true  -- Stop updating after deletion
    end)
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

--[[
    Register action events for the kit
]]
function FieldServiceKit:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self[SPEC_NAME]

        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            -- Register activation action (R key by default, same as workshop)
            local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.IMPLEMENT_EXTRA3, self, FieldServiceKit.actionEventActivate, false, true, false, true, nil)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
        end
    end
end

function FieldServiceKit.actionEventActivate(self, actionName, inputValue, callbackState, isAnalog)
    self:activateFieldService()
end


--[[
    FieldServiceKitActivatable - Activatable object for player interaction
    Shows "Use Field Service Kit" prompt when near a serviceable vehicle
]]
FieldServiceKitActivatable = {}
local FieldServiceKitActivatable_mt = Class(FieldServiceKitActivatable)

function FieldServiceKitActivatable.new(kit)
    local self = setmetatable({}, FieldServiceKitActivatable_mt)

    self.kit = kit
    self.isActive = false
    self.activateText = g_i18n:getText("usedplus_fsk_activate") or "Use Field Service Kit"

    return self
end

function FieldServiceKitActivatable:getIsActivatable()
    if self.kit == nil or self.kit[SPEC_NAME] == nil then
        return false
    end

    local spec = self.kit[SPEC_NAME]
    return spec.targetVehicle ~= nil and not spec.isConsumed
end

function FieldServiceKitActivatable:run()
    if self.kit ~= nil then
        self.kit:activateFieldService()
    end
end

function FieldServiceKitActivatable:getActivateText()
    local spec = self.kit[SPEC_NAME]

    if spec.targetVehicle ~= nil then
        local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
        local status = spec.targetVehicle.isDisabled and "DISABLED" or "Needs Service"
        return string.format("%s (%s - %s)", self.activateText, vehicleName, status)
    end

    return self.activateText
end

function FieldServiceKitActivatable:getDistance(x, y, z)
    if self.kit.rootNode ~= nil then
        local kx, ky, kz = getWorldTranslation(self.kit.rootNode)
        return MathUtil.vector3Length(x - kx, y - ky, z - kz)
    end
    return math.huge
end
