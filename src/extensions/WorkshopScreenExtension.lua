--[[
    FS25_UsedPlus - Workshop Screen Extension

    Adds "Inspect" button to the workshop screen (alongside Repair, Repaint, etc.)
    Shows MaintenanceReportDialog for the current vehicle

    The workshop screen is shown when you press R on an owned vehicle.
    It has buttons: Repair, Repaint, Customize, Sell, Back
    We add: Inspect (shows maintenance/reliability report)
]]

WorkshopScreenExtension = {}

WorkshopScreenExtension.isInitialized = false
WorkshopScreenExtension.inspectButtonCreated = false

--[[
    Initialize the extension
    Called from main.lua after mission starts
]]
function WorkshopScreenExtension:init()
    if self.isInitialized then
        UsedPlus.logDebug("WorkshopScreenExtension already initialized")
        return
    end

    -- Hook WorkshopScreen
    self:hookWorkshopScreen()

    self.isInitialized = true
    UsedPlus.logDebug("WorkshopScreenExtension initialized")
end

--[[
    Log all properties on an object for debugging
]]
function WorkshopScreenExtension:logProperties(obj, name)
    if obj == nil then
        UsedPlus.logDebug(string.format("WorkshopScreenExtension: %s is nil", name))
        return
    end

    local props = {}
    for k, v in pairs(obj) do
        -- Safely convert key to string
        local keyStr = tostring(k)
        local vtype = type(v)
        if vtype == "table" or vtype == "userdata" then
            table.insert(props, keyStr .. "=" .. vtype)
        elseif vtype ~= "function" then
            table.insert(props, keyStr .. "=" .. tostring(v))
        end
    end

    table.sort(props)
    UsedPlus.logDebug(string.format("WorkshopScreenExtension: %s properties: %s",
        name, table.concat(props, ", ")))
end

--[[
    Hook WorkshopScreen to add our Inspect button
]]
function WorkshopScreenExtension:hookWorkshopScreen()
    if WorkshopScreen == nil then
        UsedPlus.logWarn("WorkshopScreenExtension: WorkshopScreen class not found")
        return
    end

    -- Hook onOpen to create/show our button
    if WorkshopScreen.onOpen ~= nil then
        WorkshopScreen.onOpen = Utils.appendedFunction(
            WorkshopScreen.onOpen,
            WorkshopScreenExtension.onWorkshopOpen
        )
        UsedPlus.logDebug("WorkshopScreenExtension: Hooked onOpen")
    end

    -- Hook setVehicle to update button when vehicle changes
    if WorkshopScreen.setVehicle ~= nil then
        WorkshopScreen.setVehicle = Utils.appendedFunction(
            WorkshopScreen.setVehicle,
            WorkshopScreenExtension.onSetVehicle
        )
        UsedPlus.logDebug("WorkshopScreenExtension: Hooked setVehicle")
    end
end

--[[
    Called when workshop screen opens
    Try to find and clone a button
]]
function WorkshopScreenExtension.onWorkshopOpen(screen)
    UsedPlus.logDebug("WorkshopScreenExtension: Workshop opened")

    -- Log screen properties to find buttons
    WorkshopScreenExtension:logProperties(screen, "WorkshopScreen instance")

    -- v2.1.2: Hide vanilla repaint button when RVB is installed
    -- Repaint is available in RVB's Workshop dialog instead
    WorkshopScreenExtension:hideRepaintButtonForRVB(screen)

    -- Try to create inspect button by cloning an existing button
    WorkshopScreenExtension:tryCreateInspectButton(screen)

    -- Hook the sell button to show our dialog instead
    WorkshopScreenExtension:hookSellButton(screen)
end

--[[
    v2.1.2: Hide the vanilla Repaint button when RVB is installed
    Repaint functionality is available in RVB's Workshop dialog instead
]]
function WorkshopScreenExtension:hideRepaintButtonForRVB(screen)
    -- Only hide if RVB is installed
    if not ModCompatibility or not ModCompatibility.rvbInstalled then
        return
    end

    -- Find and hide the repaint button
    if screen.repaintButton then
        screen.repaintButton:setVisible(false)
        UsedPlus.logDebug("WorkshopScreenExtension: Hidden vanilla repaintButton (RVB installed)")
    else
        -- Try alternative names
        local buttonNames = {"repaintButton", "buttonRepaint", "btnRepaint"}
        for _, name in ipairs(buttonNames) do
            if screen[name] and screen[name].setVisible then
                screen[name]:setVisible(false)
                UsedPlus.logDebug(string.format("WorkshopScreenExtension: Hidden %s (RVB installed)", name))
                break
            end
        end
    end
end

--[[
    Hook the sell button to show our custom sell dialog
]]
function WorkshopScreenExtension:hookSellButton(screen)
    if screen.sellButton == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: No sellButton found")
        return
    end

    -- Check if already hooked (to avoid double-hooking)
    if screen.sellButtonHooked then
        return
    end

    -- Log what the button currently has
    UsedPlus.logDebug(string.format("WorkshopScreenExtension: sellButton.onClickCallback type = %s",
        type(screen.sellButton.onClickCallback)))

    -- Store original callback
    local originalCallback = screen.sellButton.onClickCallback

    -- Direct property assignment (NOT setCallback which broke the button)
    screen.sellButton.onClickCallback = function(button, ...)
        UsedPlus.logDebug(">>> Sell button callback intercepted <<<")

        local vehicle = screen.vehicle
        if vehicle then
            local farmId = g_currentMission:getFarmId()

            -- Check ownership
            if vehicle.propertyState ~= VehiclePropertyState.OWNED then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_INFO,
                    "Leased vehicles cannot be sold."
                )
                return
            end

            -- Check UsedPlus lease
            if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_ERROR,
                    g_i18n:getText("usedplus_error_cannotSellLeasedVehicle")
                )
                return
            end

            -- Check if already listed
            if g_vehicleSaleManager and g_vehicleSaleManager:isVehicleListed(vehicle) then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_INFO,
                    "This vehicle is already listed for sale."
                )
                return
            end

            -- Show our dialog
            UsedPlus.logDebug(">>> Showing SellVehicleDialog <<<")
            if VehicleSellingPointExtension and VehicleSellingPointExtension.showSellVehicleDialog then
                VehicleSellingPointExtension.showSellVehicleDialog(vehicle, farmId)
            end
            return
        end

        -- No vehicle or fallback - call original
        UsedPlus.logDebug(">>> Calling original callback <<<")
        if originalCallback then
            return originalCallback(button, ...)
        end
    end

    screen.sellButtonHooked = true
    UsedPlus.logDebug("WorkshopScreenExtension: Sell button hooked (direct callback)")
end

--[[
    Called when vehicle is set/changed
    THIS is where we need to create the button since onOpen doesn't fire
]]
function WorkshopScreenExtension.onSetVehicle(screen, vehicle)
    if vehicle then
        UsedPlus.logDebug(string.format("WorkshopScreenExtension: Vehicle set to %s",
            vehicle:getName() or "unknown"))

        -- Log screen properties to find buttons
        WorkshopScreenExtension:logProperties(screen, "WorkshopScreen instance")

        -- v2.1.2: Hide vanilla repaint button when RVB is installed
        WorkshopScreenExtension:hideRepaintButtonForRVB(screen)

        -- Try to create inspect button
        WorkshopScreenExtension:tryCreateInspectButton(screen)

        -- Hook the sell button (may only exist after vehicle is set)
        WorkshopScreenExtension:hookSellButton(screen)
    end
end

--[[
    Try to find an existing button and clone it for Inspect
]]
function WorkshopScreenExtension:tryCreateInspectButton(screen)
    if screen == nil then
        return
    end

    -- Skip if RVB is installed - they have their own Workshop button
    -- that opens a comprehensive diagnostics dialog. Our data is injected there instead.
    if ModCompatibility and ModCompatibility.rvbInstalled then
        UsedPlus.logDebug("WorkshopScreenExtension: RVB installed, skipping Inspect button (using RVB integration)")
        return
    end

    -- Already created?
    if screen.usedPlusInspectButton then
        UsedPlus.logDebug("WorkshopScreenExtension: Inspect button already exists")
        return
    end

    -- Try to find a button to clone
    -- Common button property names to try
    local buttonNames = {
        "repairButton", "sellButton", "repaintButton", "configureButton",
        "customizeButton", "backButton", "buttonRepair", "buttonSell",
        "buttonBack", "btnRepair", "btnSell", "btnBack"
    }

    local sourceButton = nil
    local foundName = nil

    for _, name in ipairs(buttonNames) do
        if screen[name] and type(screen[name]) == "table" then
            sourceButton = screen[name]
            foundName = name
            UsedPlus.logDebug(string.format("WorkshopScreenExtension: Found button '%s'", name))
            break
        end
    end

    -- If no named button found, try to find any button element
    if sourceButton == nil then
        for k, v in pairs(screen) do
            if type(v) == "table" and v.clone and v.setText then
                sourceButton = v
                foundName = k
                UsedPlus.logDebug(string.format("WorkshopScreenExtension: Found cloneable element '%s'", k))
                break
            end
        end
    end

    if sourceButton == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: No button found to clone")
        -- Try alternative: look for buttonBox or similar container
        if screen.buttonBox then
            UsedPlus.logDebug("WorkshopScreenExtension: Found buttonBox, looking for children")
            WorkshopScreenExtension:logProperties(screen.buttonBox, "buttonBox")
        end
        return
    end

    -- Clone the button
    UsedPlus.logDebug(string.format("WorkshopScreenExtension: Cloning button from '%s'", foundName))

    local parent = sourceButton.parent
    if parent == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: Source button has no parent")
        return
    end

    local inspectButton = sourceButton:clone(parent)
    if inspectButton == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: Failed to clone button")
        return
    end

    inspectButton.name = "usedPlusInspectButton"
    inspectButton:setText(g_i18n:getText("usedplus_button_inspect") or "Inspect")

    -- IMPORTANT: Explicitly enable the button (source button might have been disabled)
    if inspectButton.setDisabled then
        inspectButton:setDisabled(false)
    end

    -- Set click callback
    inspectButton.onClickCallback = function()
        WorkshopScreenExtension:onInspectClick(screen)
    end

    -- Try to set input action
    if inspectButton.inputActionName ~= nil then
        inspectButton.inputActionName = "MENU_EXTRA_1"
    end

    screen.usedPlusInspectButton = inspectButton
    UsedPlus.logDebug("WorkshopScreenExtension: Inspect button created successfully!")

    -- Now create the Tires button
    WorkshopScreenExtension:tryCreateTiresButton(screen, sourceButton, parent)
end

--[[
    Create Tires button for tire replacement service
    Called from tryCreateInspectButton after Inspect button is created
]]
function WorkshopScreenExtension:tryCreateTiresButton(screen, sourceButton, parent)
    if screen == nil or sourceButton == nil or parent == nil then
        return
    end

    -- Already created?
    if screen.usedPlusTiresButton then
        UsedPlus.logDebug("WorkshopScreenExtension: Tires button already exists")
        return
    end

    -- Clone the source button
    local tiresButton = sourceButton:clone(parent)
    if tiresButton == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: Failed to clone button for Tires")
        return
    end

    tiresButton.name = "usedPlusTiresButton"
    tiresButton:setText(g_i18n:getText("usedplus_button_tires") or "Tires")

    -- IMPORTANT: Explicitly enable the button
    if tiresButton.setDisabled then
        tiresButton:setDisabled(false)
    end

    -- Set click callback
    tiresButton.onClickCallback = function()
        WorkshopScreenExtension:onTiresClick(screen)
    end

    -- Try to set input action
    if tiresButton.inputActionName ~= nil then
        tiresButton.inputActionName = "MENU_EXTRA_2"
    end

    screen.usedPlusTiresButton = tiresButton
    UsedPlus.logDebug("WorkshopScreenExtension: Tires button created successfully!")
end

--[[
    Handle Tires button click
    Shows TiresDialog for tire replacement
]]
function WorkshopScreenExtension:onTiresClick(screen)
    local vehicle = nil

    if screen and screen.vehicle then
        vehicle = screen.vehicle
    elseif g_workshopScreen and g_workshopScreen.vehicle then
        vehicle = g_workshopScreen.vehicle
    end

    if vehicle == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: No vehicle for tire service")
        g_currentMission:showBlinkingWarning("No vehicle selected", 2000)
        return
    end

    UsedPlus.logDebug(string.format("WorkshopScreenExtension: Opening tires dialog for %s", vehicle:getName()))

    -- Play click sound
    if g_workshopScreen and g_workshopScreen.playSample then
        g_workshopScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end

    -- Use DialogLoader for centralized lazy loading
    local farmId = g_currentMission:getFarmId()
    DialogLoader.show("TiresDialog", "setVehicle", vehicle, farmId)
end

--[[
    Handle Inspect button click
    Now implements paid inspection with caching
]]
function WorkshopScreenExtension:onInspectClick(screen)
    local vehicle = nil

    if screen and screen.vehicle then
        vehicle = screen.vehicle
    elseif g_workshopScreen and g_workshopScreen.vehicle then
        vehicle = g_workshopScreen.vehicle
    end

    if vehicle == nil then
        UsedPlus.logDebug("WorkshopScreenExtension: No vehicle for inspection")
        g_currentMission:showBlinkingWarning("No vehicle selected", 2000)
        return
    end

    UsedPlus.logDebug(string.format("WorkshopScreenExtension: Inspecting %s", vehicle:getName()))

    -- Play click sound
    if g_workshopScreen and g_workshopScreen.playSample then
        g_workshopScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end

    -- Store vehicle reference for callbacks
    WorkshopScreenExtension.pendingInspectionVehicle = vehicle

    -- Check if we have a valid cached inspection
    if UsedPlusMaintenance and UsedPlusMaintenance.isInspectionCacheValid then
        local isCacheValid = UsedPlusMaintenance.isInspectionCacheValid(vehicle)

        if isCacheValid then
            -- Show info that nothing has changed, then show cached report
            UsedPlus.logDebug("WorkshopScreenExtension: Using cached inspection (no charge)")
            WorkshopScreenExtension:showCachedInspectionMessage(vehicle)
            return
        end
    end

    -- No valid cache - show payment confirmation
    WorkshopScreenExtension:showInspectionPaymentConfirmation(vehicle)
end

--[[
    Show message that cached inspection is being used (no charge)
]]
function WorkshopScreenExtension:showCachedInspectionMessage(vehicle)
    -- Store vehicle for callback
    WorkshopScreenExtension.cachedInspectionVehicle = vehicle

    InfoDialog.show(
        "Vehicle condition unchanged since last inspection.\nViewing previous report (no charge).",
        WorkshopScreenExtension.onCachedInspectionMessageClosed,
        WorkshopScreenExtension,
        DialogElement.TYPE_INFO
    )
end

--[[
    Callback when cached inspection message is closed
]]
function WorkshopScreenExtension:onCachedInspectionMessageClosed()
    local vehicle = WorkshopScreenExtension.cachedInspectionVehicle
    WorkshopScreenExtension.cachedInspectionVehicle = nil

    if vehicle then
        WorkshopScreenExtension:showMaintenanceReport(vehicle)
    end
end

--[[
    Show payment confirmation dialog for inspection fee
]]
function WorkshopScreenExtension:showInspectionPaymentConfirmation(vehicle)
    local fee = UsedPlusMaintenance.INSPECTION_FEE or 500
    local feeFormatted = g_i18n:formatMoney(fee, 0, true, true)

    -- Check if player can afford it
    local playerFarm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    local currentMoney = playerFarm and playerFarm.money or 0

    if currentMoney < fee then
        InfoDialog.show(
            string.format("Inspection fee: %s\n\nInsufficient funds for inspection.", feeFormatted),
            nil,
            nil,
            DialogElement.TYPE_WARNING
        )
        return
    end

    -- Set bypass flag so VehicleSellingPointExtension doesn't intercept this dialog
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = true
    end

    -- Show confirmation dialog using FS25 pattern
    local dialog = g_gui:showDialog("YesNoDialog")
    if dialog and dialog.target then
        dialog.target:setTitle("Vehicle Inspection")
        dialog.target:setText(string.format(
            "The mechanic will inspect your vehicle for %s.\n\n" ..
            "This will provide a detailed maintenance report\n" ..
            "showing engine, hydraulic, and electrical reliability.\n\n" ..
            "Proceed with inspection?",
            feeFormatted
        ))
        dialog.target:setCallback(WorkshopScreenExtension.onInspectionPaymentConfirmed, WorkshopScreenExtension)
    end
end

--[[
    Callback when player confirms or declines inspection payment
]]
function WorkshopScreenExtension:onInspectionPaymentConfirmed(yes)
    local vehicle = WorkshopScreenExtension.pendingInspectionVehicle

    if not yes then
        UsedPlus.logDebug("WorkshopScreenExtension: Inspection payment declined")
        WorkshopScreenExtension.pendingInspectionVehicle = nil
        return
    end

    if vehicle == nil then
        UsedPlus.logWarn("WorkshopScreenExtension: No pending vehicle for inspection")
        return
    end

    local fee = UsedPlusMaintenance.INSPECTION_FEE or 500

    -- Deduct the fee
    local farmId = g_currentMission:getFarmId()
    g_currentMission:addMoney(-fee, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true, true)

    UsedPlus.logDebug(string.format("WorkshopScreenExtension: Charged %d for inspection", fee))

    -- Update the inspection cache
    if UsedPlusMaintenance and UsedPlusMaintenance.updateInspectionCache then
        UsedPlusMaintenance.updateInspectionCache(vehicle)
        UsedPlus.logDebug("WorkshopScreenExtension: Updated inspection cache")
    end

    -- Show the maintenance report
    WorkshopScreenExtension:showMaintenanceReport(vehicle)

    -- Clear pending vehicle
    WorkshopScreenExtension.pendingInspectionVehicle = nil
end

--[[
    Show the MaintenanceReportDialog for a vehicle
]]
function WorkshopScreenExtension:showMaintenanceReport(vehicle)
    if vehicle == nil then
        return
    end

    -- Show MaintenanceReportDialog
    if MaintenanceReportDialog then
        local dialog = MaintenanceReportDialog.getInstance()
        if dialog then
            dialog:show(vehicle)
            return
        end
    end

    -- Fallback: Show simple info dialog
    local info = "Maintenance information not available."

    if UsedPlusMaintenance and UsedPlusMaintenance.getReliabilityData then
        local data = UsedPlusMaintenance.getReliabilityData(vehicle)
        if data then
            info = string.format(
                "=== Maintenance Report ===\n" ..
                "Vehicle: %s\n\n" ..
                "Engine Reliability: %d%%\n" ..
                "Hydraulic Reliability: %d%%\n" ..
                "Electrical Reliability: %d%%\n\n" ..
                "Breakdowns: %d\n" ..
                "Repairs: %d",
                vehicle:getName() or "Unknown",
                math.floor((data.engineReliability or 1) * 100),
                math.floor((data.hydraulicReliability or 1) * 100),
                math.floor((data.electricalReliability or 1) * 100),
                data.failureCount or 0,
                data.repairCount or 0
            )
        end
    end

    InfoDialog.show(info, nil, nil, DialogElement.TYPE_INFO)
end

--[[
    Restore original behavior
]]
function WorkshopScreenExtension:restore()
    self.isInitialized = false
end

UsedPlus.logInfo("WorkshopScreenExtension loaded")
