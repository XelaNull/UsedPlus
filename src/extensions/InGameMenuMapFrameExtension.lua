--[[
    FS25_UsedPlus - InGameMenuMapFrame Extension

    Adds "Finance Land" option to farmland context menu
    Pattern from: FS25_FieldLeasing mod (working reference)

    This adds a "Finance Land" option alongside "Visit", "Buy", "Tag Place"
    when clicking on unowned farmland in the map.

    Key hooks:
    - onLoadMapFinished: Register new action in InGameMenuMapFrame.ACTIONS
    - setMapInputContext: Control when action is visible (when Buy is available)
]]

InGameMenuMapFrameExtension = {}

-- Dialog loading now handled by DialogLoader utility

--[[
    Hook onLoadMapFinished to register new actions
    Register REPAIR_VEHICLE, FINANCE_LAND, and LEASE_LAND actions
    Also intercept BUY to open our unified dialog
]]
function InGameMenuMapFrameExtension.onLoadMapFinished(self, superFunc)
    -- Call original function FIRST so base game contextActions are set up
    superFunc(self)

    -- Count existing actions to get next ID for vehicle-related actions
    local count = 0
    for _ in pairs(InGameMenuMapFrame.ACTIONS) do
        count = count + 1
    end

    -- Register REPAIR_VEHICLE action if not already added (at end, for vehicles)
    if InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE == nil then
        InGameMenuMapFrame.ACTIONS["REPAIR_VEHICLE"] = count + 1
        count = count + 1

        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] = {
            ["title"] = g_i18n:getText("usedplus_button_repairVehicle"),
            ["callback"] = InGameMenuMapFrameExtension.onRepairVehicle,
            ["isActive"] = false
        }

        UsedPlus.logDebug("Registered REPAIR_VEHICLE action in InGameMenuMapFrame (ID=" .. tostring(InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE) .. ")")
    end

    -- Override the BUY action callback to open our dialog for farmland
    -- BUY is typically ID 11 in FS25
    if InGameMenuMapFrame.ACTIONS.BUY and self.contextActions[InGameMenuMapFrame.ACTIONS.BUY] then
        -- Store original callback
        InGameMenuMapFrameExtension.originalBuyCallback = self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback
        -- Replace with our callback
        self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback = InGameMenuMapFrameExtension.onBuyFarmland
        UsedPlus.logDebug("Intercepted BUY action callback (ID=" .. tostring(InGameMenuMapFrame.ACTIONS.BUY) .. ")")

        -- Register FINANCE and LEASE right after BUY
        -- Use IDs 12 and 13 to appear immediately after BUY (ID 11)
        local buyId = InGameMenuMapFrame.ACTIONS.BUY

        if InGameMenuMapFrame.ACTIONS.FINANCE_LAND == nil then
            InGameMenuMapFrame.ACTIONS["FINANCE_LAND"] = buyId + 1

            self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND] = {
                ["title"] = g_i18n:getText("usedplus_action_financeLand") or "Finance",
                ["callback"] = InGameMenuMapFrameExtension.onFinanceLand,
                ["isActive"] = false
            }

            UsedPlus.logDebug("Registered FINANCE_LAND action (ID=" .. tostring(buyId + 1) .. ")")
        end

        if InGameMenuMapFrame.ACTIONS.LEASE_LAND == nil then
            InGameMenuMapFrame.ACTIONS["LEASE_LAND"] = buyId + 2

            self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND] = {
                ["title"] = g_i18n:getText("usedplus_action_leaseLand") or "Lease",
                ["callback"] = InGameMenuMapFrameExtension.onLeaseLand,
                ["isActive"] = false
            }

            UsedPlus.logDebug("Registered LEASE_LAND action (ID=" .. tostring(buyId + 2) .. ")")
        end
    else
        UsedPlus.logWarn("Could not intercept BUY action")
    end
end

--[[
    Hook setMapInputContext to show Repair, Finance Land, and Lease Land options
]]
function InGameMenuMapFrameExtension.setMapInputContext(self, superFunc, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)

    -- Show "Repair Vehicle" when "Sell Vehicle" is available (owned vehicle selected)
    if sellVehicleActive and self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE].isActive = false
    end

    -- Show "Finance Land" when "Buy Farmland" is available (unowned farmland selected)
    if buyFarmlandActive and self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND].isActive = false
    end

    -- Show "Lease Land" when "Buy Farmland" is available (unowned farmland selected)
    if buyFarmlandActive and self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND].isActive = false
    end

    -- Call original function
    superFunc(self, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)
end

--[[
    Install hooks at load time with safety check
    InGameMenuMapFrame should exist when mods load
]]
if InGameMenuMapFrame ~= nil then
    -- Hook into onLoadMapFinished
    if InGameMenuMapFrame.onLoadMapFinished ~= nil then
        InGameMenuMapFrame.onLoadMapFinished = Utils.overwrittenFunction(
            InGameMenuMapFrame.onLoadMapFinished,
            InGameMenuMapFrameExtension.onLoadMapFinished
        )
        UsedPlus.logDebug("InGameMenuMapFrame.onLoadMapFinished hook installed")
    end

    -- Hook into setMapInputContext
    if InGameMenuMapFrame.setMapInputContext ~= nil then
        InGameMenuMapFrame.setMapInputContext = Utils.overwrittenFunction(
            InGameMenuMapFrame.setMapInputContext,
            InGameMenuMapFrameExtension.setMapInputContext
        )
        UsedPlus.logDebug("InGameMenuMapFrame.setMapInputContext hook installed")
    end
else
    UsedPlus.logWarn("InGameMenuMapFrame not available at load time")
end

--[[
    Callback when "Finance Land" is clicked
    Opens UnifiedLandPurchaseDialog in Finance mode
]]
function InGameMenuMapFrameExtension.onFinanceLand(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onFinanceLand called")
    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onFinanceLand: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onFinanceLand: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onFinanceLand: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_FINANCE)
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onFinanceLand: Dialog shown")
    else
        UsedPlus.logError("onFinanceLand: Dialog not found")
    end

    return true
end

--[[
    Callback when "Lease Land" is clicked
    Opens UnifiedLandPurchaseDialog in Lease mode
]]
function InGameMenuMapFrameExtension.onLeaseLand(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onLeaseLand called")
    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onLeaseLand: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onLeaseLand: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onLeaseLand: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_LEASE)
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onLeaseLand: Dialog shown")
    else
        UsedPlus.logError("onLeaseLand: Dialog not found")
    end

    return true
end

--[[
    Callback when "Repair Vehicle" is clicked
    Refactored to use DialogLoader for centralized loading
]]
function InGameMenuMapFrameExtension.onRepairVehicle(inGameMenuMapFrame, element)
    -- Get the selected vehicle from the current hotspot
    local vehicle = nil

    if inGameMenuMapFrame.currentHotspot ~= nil then
        -- Try to get vehicle from hotspot
        if InGameMenuMapUtil and InGameMenuMapUtil.getHotspotVehicle then
            vehicle = InGameMenuMapUtil.getHotspotVehicle(inGameMenuMapFrame.currentHotspot)
        end

        -- Fallback: try direct vehicle reference
        if vehicle == nil and inGameMenuMapFrame.currentHotspot.vehicle then
            vehicle = inGameMenuMapFrame.currentHotspot.vehicle
        end
    end

    if vehicle == nil then
        UsedPlus.logError("No vehicle selected for repair")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "No vehicle selected"
        )
        return true
    end

    local farmId = g_currentMission:getFarmId()

    -- Check if player owns the vehicle
    if vehicle.ownerFarmId ~= farmId then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "You do not own this vehicle"
        )
        return true
    end

    -- Use DialogLoader for centralized lazy loading
    local shown = DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId)

    if shown then
        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
    end

    return true
end

--[[
    Callback when "Buy" farmland is clicked
    Opens UnifiedLandPurchaseDialog in Cash mode (default)
]]
function InGameMenuMapFrameExtension.onBuyFarmland(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onBuyFarmland called - intercepted Buy action")
    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onBuyFarmland: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onBuyFarmland: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onBuyFarmland: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_CASH)  -- Default to cash mode
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onBuyFarmland: Dialog shown")
    else
        UsedPlus.logError("onBuyFarmland: Dialog not found")
    end

    return true
end

UsedPlus.logInfo("InGameMenuMapFrameExtension loaded")
