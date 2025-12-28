--[[
    FS25_UsedPlus - Oil Service Point Placeable Specialization

    Allows players to refill engine oil and hydraulic fluid by driving
    their vehicle near an oil barrel or service tank.

    Two modes:
    1. Service Point Mode (default) - Infinite supply, cost based on vehicle value
    2. Fillable Tank Mode - Has storage, consumes MOTOROIL fill type if available
       (Compatible with FS25_CrudeOilProduction mod)

    Pattern from: Fuel tank placeables, trigger-based actions
    Model adapted from: FS25_Fuel_Barrel by Gian FS (with acknowledgment)

    v1.8.0 - Oil Service Point System
]]

OilServicePoint = {}
OilServicePoint.MOD_NAME = g_currentModName or "FS25_UsedPlus"

-- Check if MOTOROIL fill type exists (from Crude Oil Production mod)
OilServicePoint.MOTOROIL_AVAILABLE = false

-- Specialization registration
function OilServicePoint.prerequisitesPresent(specializations)
    return true
end

function OilServicePoint.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "getVehicleInTrigger", OilServicePoint.getVehicleInTrigger)
    SpecializationUtil.registerFunction(placeableType, "canRefillOil", OilServicePoint.canRefillOil)
    SpecializationUtil.registerFunction(placeableType, "canRefillHydraulic", OilServicePoint.canRefillHydraulic)
    SpecializationUtil.registerFunction(placeableType, "getOilRefillCost", OilServicePoint.getOilRefillCost)
    SpecializationUtil.registerFunction(placeableType, "getHydraulicRefillCost", OilServicePoint.getHydraulicRefillCost)
    SpecializationUtil.registerFunction(placeableType, "refillOil", OilServicePoint.refillOil)
    SpecializationUtil.registerFunction(placeableType, "refillHydraulic", OilServicePoint.refillHydraulic)
end

function OilServicePoint.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", OilServicePoint)
end

function OilServicePoint.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("OilServicePoint")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".oilServicePoint#triggerNode", "Trigger node for vehicle detection")
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#oilCostMultiplier", "Cost multiplier for oil refill (default 0.01 = 1% of vehicle value)", 0.01)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#hydraulicCostMultiplier", "Cost multiplier for hydraulic fluid refill (default 0.008 = 0.8% of vehicle value)", 0.008)
    schema:register(XMLValueType.BOOL, basePath .. ".oilServicePoint#useFillableStorage", "If true, consumes MOTOROIL from storage instead of infinite supply", false)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#storageCapacity", "Storage capacity in liters (only used if useFillableStorage=true)", 500)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#litersPerOilChange", "Liters of oil consumed per full oil change (default 10L)", 10)
    schema:setXMLSpecializationType()
end

--[[
    Check if MOTOROIL fill type is available (from Crude Oil Production mod)
]]
function OilServicePoint.checkMotorOilAvailable()
    if g_fillTypeManager then
        local fillType = g_fillTypeManager:getFillTypeByName("MOTOROIL")
        if fillType ~= nil then
            OilServicePoint.MOTOROIL_AVAILABLE = true
            UsedPlus.logInfo("OilServicePoint: MOTOROIL fill type detected (Crude Oil Production mod compatible)")
            return true
        end
    end
    OilServicePoint.MOTOROIL_AVAILABLE = false
    return false
end

function OilServicePoint:onLoad(savegame)
    local spec = self.spec_oilServicePoint
    if spec == nil then
        self.spec_oilServicePoint = {}
        spec = self.spec_oilServicePoint
    end

    local xmlFile = self.xmlFile

    -- Load trigger node
    spec.triggerNode = xmlFile:getValue("placeable.oilServicePoint#triggerNode", nil, self.components, self.i3dMappings)

    -- Cost multipliers (used in service point mode)
    spec.oilCostMultiplier = xmlFile:getValue("placeable.oilServicePoint#oilCostMultiplier", 0.01)
    spec.hydraulicCostMultiplier = xmlFile:getValue("placeable.oilServicePoint#hydraulicCostMultiplier", 0.008)

    -- Fillable storage mode (for Crude Oil Production compatibility)
    spec.useFillableStorage = xmlFile:getValue("placeable.oilServicePoint#useFillableStorage", false)
    spec.storageCapacity = xmlFile:getValue("placeable.oilServicePoint#storageCapacity", 500)
    spec.litersPerOilChange = xmlFile:getValue("placeable.oilServicePoint#litersPerOilChange", 10)
    spec.currentOilStorage = 0  -- Current oil in storage (liters)

    -- Check if MOTOROIL fill type is available
    OilServicePoint.checkMotorOilAvailable()

    -- If fillable storage mode but no MOTOROIL available, fall back to service point mode
    if spec.useFillableStorage and not OilServicePoint.MOTOROIL_AVAILABLE then
        UsedPlus.logWarning("OilServicePoint: useFillableStorage=true but MOTOROIL fill type not found. Install Crude Oil Production mod or use service point mode.")
        spec.useFillableStorage = false
    end

    -- Track vehicles in trigger
    spec.vehiclesInTrigger = {}
    spec.activationTimer = 0
    spec.updateInterval = 250 -- ms between updates

    -- Register trigger callback
    if spec.triggerNode ~= nil then
        addTrigger(spec.triggerNode, "oilServiceTriggerCallback", self)
        UsedPlus.logDebug("OilServicePoint: Trigger registered at node " .. tostring(spec.triggerNode))
    else
        UsedPlus.logWarning("OilServicePoint: No trigger node found!")
    end

    -- Input action binding
    spec.inputAction = InputAction.ACTIVATE_OBJECT

    -- Action text elements
    spec.oilActionText = g_i18n:getText("usedplus_oil_refillAction") or "Refill Engine Oil"
    spec.hydraulicActionText = g_i18n:getText("usedplus_hydraulic_refillAction") or "Refill Hydraulic Fluid"

    -- Log mode
    if spec.useFillableStorage then
        UsedPlus.logInfo(string.format("OilServicePoint loaded (Fillable Tank Mode - %dL capacity)", spec.storageCapacity))
    else
        UsedPlus.logInfo("OilServicePoint loaded (Service Point Mode - infinite supply)")
    end
end

function OilServicePoint:onDelete()
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    if spec.triggerNode ~= nil then
        removeTrigger(spec.triggerNode)
    end

    spec.vehiclesInTrigger = {}
end

--[[
    Trigger callback - called when objects enter/exit the trigger zone
]]
function OilServicePoint:oilServiceTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- Get the vehicle from the trigger object
    local vehicle = g_currentMission.nodeToObject[otherId]
    if vehicle == nil then
        vehicle = g_currentMission.nodeToObject[otherShapeId]
    end

    -- Must be a vehicle with our maintenance spec
    if vehicle == nil or vehicle.spec_usedPlusMaintenance == nil then
        return
    end

    if onEnter then
        spec.vehiclesInTrigger[vehicle] = true
        UsedPlus.logDebug("OilServicePoint: Vehicle entered trigger - " .. (vehicle:getName() or "unknown"))
    elseif onLeave then
        spec.vehiclesInTrigger[vehicle] = nil
        UsedPlus.logDebug("OilServicePoint: Vehicle left trigger - " .. (vehicle:getName() or "unknown"))
    end
end

function OilServicePoint:onUpdate(dt)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- Throttle updates
    spec.activationTimer = spec.activationTimer + dt
    if spec.activationTimer < spec.updateInterval then
        return
    end
    spec.activationTimer = 0

    -- Check if player is in a vehicle in the trigger
    local playerVehicle = self:getVehicleInTrigger()
    if playerVehicle == nil then
        return
    end

    -- Show action prompts if refill is available
    local canOil = self:canRefillOil(playerVehicle)
    local canHydraulic = self:canRefillHydraulic(playerVehicle)

    if canOil then
        local cost = self:getOilRefillCost(playerVehicle)
        local actionText = string.format("%s - %s", spec.oilActionText, g_i18n:formatMoney(cost, 0, true, true))

        g_currentMission:addActivatableObject(OilServiceActivatable.new(self, playerVehicle, "oil", actionText, cost))
    end

    if canHydraulic then
        local cost = self:getHydraulicRefillCost(playerVehicle)
        local actionText = string.format("%s - %s", spec.hydraulicActionText, g_i18n:formatMoney(cost, 0, true, true))

        g_currentMission:addActivatableObject(OilServiceActivatable.new(self, playerVehicle, "hydraulic", actionText, cost))
    end
end

--[[
    Get the player's current vehicle if it's in the trigger zone
]]
function OilServicePoint:getVehicleInTrigger()
    local spec = self.spec_oilServicePoint
    if spec == nil then return nil end

    local controlledVehicle = g_currentMission.controlledVehicle
    if controlledVehicle == nil then
        return nil
    end

    -- Check if the controlled vehicle (or its root) is in our trigger
    if spec.vehiclesInTrigger[controlledVehicle] then
        return controlledVehicle
    end

    -- Check attached implements too
    for vehicle, _ in pairs(spec.vehiclesInTrigger) do
        if vehicle.rootVehicle == controlledVehicle then
            return vehicle
        end
    end

    return nil
end

--[[
    Check if vehicle needs oil refill
]]
function OilServicePoint:canRefillOil(vehicle)
    if vehicle == nil then return false end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return false end

    local oilLevel = spec.oilLevel or 1.0
    return oilLevel < 0.99  -- Allow refill if below 99%
end

--[[
    Check if vehicle needs hydraulic fluid refill
]]
function OilServicePoint:canRefillHydraulic(vehicle)
    if vehicle == nil then return false end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return false end

    local hydraulicLevel = spec.hydraulicFluidLevel or 1.0
    return hydraulicLevel < 0.99  -- Allow refill if below 99%
end

--[[
    Calculate oil refill cost based on vehicle value and amount needed
]]
function OilServicePoint:getOilRefillCost(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    -- Get vehicle base price
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = 10000
    if storeItem then
        basePrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000
    end

    -- Cost = basePrice * multiplier * amountNeeded
    local oilNeeded = 1.0 - (maintSpec.oilLevel or 1.0)
    local cost = basePrice * spec.oilCostMultiplier * oilNeeded

    return math.max(1, math.floor(cost))
end

--[[
    Calculate hydraulic fluid refill cost
]]
function OilServicePoint:getHydraulicRefillCost(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    -- Get vehicle base price
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = 10000
    if storeItem then
        basePrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000
    end

    -- Cost = basePrice * multiplier * amountNeeded
    local hydraulicNeeded = 1.0 - (maintSpec.hydraulicFluidLevel or 1.0)
    local cost = basePrice * spec.hydraulicCostMultiplier * hydraulicNeeded

    return math.max(1, math.floor(cost))
end

--[[
    Check if there's enough oil in storage (fillable mode only)
]]
function OilServicePoint:hasEnoughOilInStorage(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil then return true end  -- Service point mode = infinite

    if not spec.useFillableStorage then
        return true  -- Service point mode = infinite
    end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local oilNeeded = (1.0 - (maintSpec.oilLevel or 1.0)) * spec.litersPerOilChange
    return spec.currentOilStorage >= oilNeeded
end

--[[
    Get the amount of oil needed in liters
]]
function OilServicePoint:getOilLitersNeeded(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    local oilNeeded = (1.0 - (maintSpec.oilLevel or 1.0)) * spec.litersPerOilChange
    return oilNeeded
end

--[[
    Perform oil refill
]]
function OilServicePoint:refillOil(vehicle, noEventSend)
    if vehicle == nil then return false end

    local spec = self.spec_oilServicePoint
    if spec == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local farmId = vehicle:getOwnerFarmId()
    local vehicleName = vehicle:getName() or "Vehicle"

    if spec.useFillableStorage then
        -- FILLABLE STORAGE MODE: Consume from storage
        local oilNeeded = self:getOilLitersNeeded(vehicle)

        if spec.currentOilStorage < oilNeeded then
            g_currentMission:showBlinkingWarning(
                string.format(g_i18n:getText("usedplus_oil_notEnoughStorage") or "Not enough oil in tank! Need %.1fL, have %.1fL", oilNeeded, spec.currentOilStorage),
                2000
            )
            return false
        end

        -- Consume oil from storage
        spec.currentOilStorage = spec.currentOilStorage - oilNeeded

        -- Set oil level to 100%
        maintSpec.oilLevel = 1.0

        -- Clear oil leak if present
        if maintSpec.hasOilLeak then
            maintSpec.hasOilLeak = false
        end

        -- Show confirmation
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedplus_oil_refillCompleteStorage") or "Engine oil refilled - %.1fL used (%.1fL remaining)", oilNeeded, spec.currentOilStorage),
            2000
        )

        UsedPlus.logInfo(string.format("OilServicePoint: Refilled oil for %s, used %.1fL (%.1fL remaining)", vehicleName, oilNeeded, spec.currentOilStorage))

    else
        -- SERVICE POINT MODE: Charge money, infinite supply
        local cost = self:getOilRefillCost(vehicle)

        -- Check if player can afford it
        if g_currentMission:getMoney(farmId) < cost then
            g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_warning_notEnoughMoney") or "Not enough money!", 2000)
            return false
        end

        -- Deduct money
        g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true, true)

        -- Set oil level to 100%
        maintSpec.oilLevel = 1.0

        -- Clear oil leak if present
        if maintSpec.hasOilLeak then
            maintSpec.hasOilLeak = false
        end

        -- Show confirmation
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedplus_oil_refillComplete") or "Engine oil refilled - %s", g_i18n:formatMoney(cost, 0, true, true)),
            2000
        )

        UsedPlus.logInfo(string.format("OilServicePoint: Refilled oil for %s, cost %s", vehicleName, g_i18n:formatMoney(cost, 0, true, true)))
    end

    -- TODO: Send event for multiplayer sync
    -- if not noEventSend then
    --     OilRefillEvent.sendEvent(vehicle, "oil")
    -- end

    return true
end

--[[
    Perform hydraulic fluid refill
]]
function OilServicePoint:refillHydraulic(vehicle, noEventSend)
    if vehicle == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local cost = self:getHydraulicRefillCost(vehicle)
    local farmId = vehicle:getOwnerFarmId()

    -- Check if player can afford it
    if g_currentMission:getMoney(farmId) < cost then
        g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_warning_notEnoughMoney") or "Not enough money!", 2000)
        return false
    end

    -- Deduct money
    g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true, true)

    -- Set hydraulic level to 100%
    maintSpec.hydraulicFluidLevel = 1.0

    -- Clear hydraulic leak if present
    if maintSpec.hasHydraulicLeak then
        maintSpec.hasHydraulicLeak = false
    end

    -- Show confirmation
    local vehicleName = vehicle:getName() or "Vehicle"
    g_currentMission:showBlinkingWarning(
        string.format(g_i18n:getText("usedplus_hydraulic_refillComplete") or "Hydraulic fluid refilled - %s", g_i18n:formatMoney(cost, 0, true, true)),
        2000
    )

    UsedPlus.logInfo(string.format("OilServicePoint: Refilled hydraulic for %s, cost %s", vehicleName, g_i18n:formatMoney(cost, 0, true, true)))

    return true
end

-- Multiplayer sync stubs
function OilServicePoint:onReadStream(streamId, connection)
    -- TODO: Implement multiplayer sync
end

function OilServicePoint:onWriteStream(streamId, connection)
    -- TODO: Implement multiplayer sync
end

--[[
    ============================================================================
    OilServiceActivatable - Activatable object for action prompts
    ============================================================================
]]
OilServiceActivatable = {}
local OilServiceActivatable_mt = Class(OilServiceActivatable)

function OilServiceActivatable.new(servicePoint, vehicle, fluidType, actionText, cost)
    local self = setmetatable({}, OilServiceActivatable_mt)

    self.servicePoint = servicePoint
    self.vehicle = vehicle
    self.fluidType = fluidType  -- "oil" or "hydraulic"
    self.actionText = actionText
    self.cost = cost
    self.activateText = actionText

    return self
end

function OilServiceActivatable:getIsActivatable()
    if self.vehicle == nil or self.servicePoint == nil then
        return false
    end

    -- Check vehicle is still in trigger and still needs refill
    if self.fluidType == "oil" then
        return self.servicePoint:canRefillOil(self.vehicle)
    else
        return self.servicePoint:canRefillHydraulic(self.vehicle)
    end
end

function OilServiceActivatable:run()
    if self.fluidType == "oil" then
        self.servicePoint:refillOil(self.vehicle)
    else
        self.servicePoint:refillHydraulic(self.vehicle)
    end
end

function OilServiceActivatable:getDistance(x, y, z)
    -- Return small distance so it's always activatable when in trigger
    return 1
end

UsedPlus.logInfo("OilServicePoint.lua loaded")
