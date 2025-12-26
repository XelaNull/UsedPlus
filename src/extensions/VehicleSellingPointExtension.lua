--[[
    FS25_UsedPlus - VehicleSellingPoint Extension

    Intercepts game's repair/repaint Yes/No confirmation dialogs
    Strategy: Hook g_gui:showYesNoDialog and detect repair/repaint by message text

    When the game shows a repair/repaint confirmation dialog, we intercept it
    and show our custom dialog instead.
]]

VehicleSellingPointExtension = {}

-- Dialog loading now handled by DialogLoader utility

-- Store reference to current vehicle being serviced
VehicleSellingPointExtension.currentVehicle = nil
VehicleSellingPointExtension.currentWorkshopScreen = nil

-- Store original dialog functions for calling
VehicleSellingPointExtension.originalShowYesNoDialog = nil
VehicleSellingPointExtension.originalShowDialog = nil

-- Tracking for intercepted dialogs
VehicleSellingPointExtension.pendingRepairCallback = nil
VehicleSellingPointExtension.pendingRepairVehicle = nil

-- Flag to bypass interception for our own finance confirmation
VehicleSellingPointExtension.bypassInterception = false

-- Debug flags
VehicleSellingPointExtension.DEBUG_PASSTHROUGH_ALL = false  -- Set to true to disable all interception
VehicleSellingPointExtension.DEBUG_VERBOSE = true  -- Enable verbose logging

--[[
    Debug helper to log GUI state
]]
function VehicleSellingPointExtension.logGuiState(context)
    if not VehicleSellingPointExtension.DEBUG_VERBOSE then return end

    local stateInfo = {}

    -- Check g_gui state
    if g_gui then
        table.insert(stateInfo, string.format("g_gui exists"))

        -- Check currentGui
        if g_gui.currentGui then
            local name = g_gui.currentGui.name or "unknown"
            table.insert(stateInfo, string.format("currentGui=%s", name))
        else
            table.insert(stateInfo, "currentGui=nil")
        end

        -- Check currentGuiName
        if g_gui.currentGuiName then
            table.insert(stateInfo, string.format("currentGuiName=%s", g_gui.currentGuiName))
        end

        -- Check dialogs
        if g_gui.dialogs then
            local dialogCount = 0
            local dialogNames = {}
            for name, dialog in pairs(g_gui.dialogs) do
                dialogCount = dialogCount + 1
                if dialog.isOpen then
                    table.insert(dialogNames, name .. "(OPEN)")
                end
            end
            table.insert(stateInfo, string.format("dialogs=%d", dialogCount))
            if #dialogNames > 0 then
                table.insert(stateInfo, "openDialogs=" .. table.concat(dialogNames, ","))
            end
        end

        -- Check dialogStack
        if g_gui.dialogStack then
            table.insert(stateInfo, string.format("dialogStack=%d", #g_gui.dialogStack))
        end

        -- Check if input is blocked
        if g_gui.inputDisabled then
            table.insert(stateInfo, "inputDisabled=true")
        end

        -- Check guis table for SellItemDialog state
        if g_gui.guis then
            local sellDialog = g_gui.guis.SellItemDialog
            if sellDialog then
                local isOpen = sellDialog.isOpen
                local isVisible = sellDialog.visible
                table.insert(stateInfo, string.format("SellItemDialog(isOpen=%s,visible=%s)",
                    tostring(isOpen), tostring(isVisible)))
            end
        end
    else
        table.insert(stateInfo, "g_gui=nil!")
    end

    UsedPlus.logDebug(string.format("[GUI STATE @ %s] %s", context, table.concat(stateInfo, " | ")))
end

--[[
    Load and show our custom repair dialog
    @param vehicle - The vehicle to repair/repaint
    @param mode - "repair", "repaint", or "both"
]]
function VehicleSellingPointExtension.showRepairDialog(vehicle, mode)
    if vehicle == nil then
        UsedPlus.logDebug("showRepairDialog: No vehicle provided")
        return false
    end

    -- Default mode
    mode = mode or RepairDialog.MODE_BOTH

    local farmId = g_currentMission:getFarmId()

    -- Check ownership
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logDebug("showRepairDialog: Vehicle not owned by current farm")
        return false
    end

    -- Store reference
    VehicleSellingPointExtension.currentVehicle = vehicle

    -- Use DialogLoader for centralized lazy loading
    local shown = DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, mode)
    return shown
end

--[[
    Load and show our custom sell vehicle dialog
    Refactored to use DialogLoader for centralized loading
    @param vehicle - The vehicle to sell
    @param farmId - The owning farm ID
]]
function VehicleSellingPointExtension.showSellVehicleDialog(vehicle, farmId)
    if vehicle == nil then
        UsedPlus.logDebug("showSellVehicleDialog: No vehicle provided")
        return false
    end

    -- Use DialogLoader with callback
    local callback = function(selectedTier)
        if selectedTier then
            -- Player selected a tier - create listing
            VehicleSellingPointExtension.createSaleListing(vehicle, farmId, selectedTier)
        else
            UsedPlus.logDebug("Sale dialog cancelled")
        end
    end

    return DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)
end

--[[
    Create a sale listing through VehicleSaleManager
    @param vehicle - The vehicle to sell
    @param farmId - The owning farm
    @param saleTier - Selected agent tier (1-3)
]]
function VehicleSellingPointExtension.createSaleListing(vehicle, farmId, saleTier)
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("VehicleSaleManager not initialized")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Sale system error. Please try again."
        )
        return
    end

    -- Create listing through manager
    local listing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, saleTier)

    if listing then
        UsedPlus.logDebug(string.format("Created sale listing: %s (Tier %d, ID: %s)",
            listing.vehicleName, saleTier, listing.id))
        -- Notification is shown by VehicleSaleManager
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Failed to create sale listing. Please try again."
        )
    end

    -- Cleanup: Clear all our stored state to prevent any lingering references
    UsedPlus.logDebug(">>> SALE COMPLETE - Starting cleanup <<<")
    VehicleSellingPointExtension.logGuiState("SALE_COMPLETE_BEFORE_CLEANUP")

    VehicleSellingPointExtension.currentVehicle = nil
    VehicleSellingPointExtension.currentWorkshopScreen = nil
    VehicleSellingPointExtension.pendingRepairCallback = nil
    VehicleSellingPointExtension.pendingRepairVehicle = nil
    VehicleSellingPointExtension.bypassInterception = false

    -- Try to close any dialogs that might be in a partial state
    pcall(function()
        if g_gui then
            g_gui:closeDialogByName("SellItemDialog")
            g_gui:closeDialogByName("YesNoDialog")
            UsedPlus.logDebug(">>> Cleanup: Called closeDialogByName for SellItemDialog and YesNoDialog <<<")
        end
    end)

    VehicleSellingPointExtension.logGuiState("SALE_COMPLETE_AFTER_CLEANUP")
    UsedPlus.logDebug(">>> Sale listing creation complete, state cleaned up <<<")
end

--[[
    Intercept showYesNoDialog to detect repair/repaint dialogs
    We detect based on the dialog text containing repair/repaint cost info
]]
function VehicleSellingPointExtension.hookShowYesNoDialog()
    if g_gui == nil then
        UsedPlus.logDebug("g_gui not available, skipping showYesNoDialog hook")
        return
    end

    -- Save original function
    VehicleSellingPointExtension.originalShowYesNoDialog = g_gui.showYesNoDialog

    -- Override with our interceptor
    g_gui.showYesNoDialog = function(guiSelf, args)
        -- Check if we should bypass interception (for our own finance confirmation)
        if VehicleSellingPointExtension.bypassInterception then
            VehicleSellingPointExtension.bypassInterception = false
            UsedPlus.logTrace("Bypassing interception for our own dialog")
            return VehicleSellingPointExtension.originalShowYesNoDialog(guiSelf, args)
        end

        local text = args.text or ""
        local callback = args.callback
        local target = args.target

        UsedPlus.logTrace(string.format("showYesNoDialog intercepted: text='%s'", string.sub(text, 1, 100)))

        -- Check if this is a repair dialog
        -- The game's repair dialog text typically contains the repair cost
        local isRepair = false
        local isRepaint = false
        local vehicle = nil

        -- Look for repair/repaint keywords in multiple languages
        local textLower = string.lower(text)

        -- English detection
        if string.find(textLower, "repair") and not string.find(textLower, "paint") then
            isRepair = true
            UsedPlus.logTrace("Detected REPAIR dialog")
        elseif string.find(textLower, "repaint") or (string.find(textLower, "paint") and not string.find(textLower, "repair")) then
            isRepaint = true
            UsedPlus.logTrace("Detected REPAINT dialog")
        end

        -- German detection
        if string.find(textLower, "reparieren") or string.find(textLower, "reparatur") then
            isRepair = true
            UsedPlus.logTrace("Detected REPAIR dialog (German)")
        elseif string.find(textLower, "lackieren") or string.find(textLower, "lackierung") then
            isRepaint = true
            UsedPlus.logTrace("Detected REPAINT dialog (German)")
        end

        -- If this is a repair or repaint dialog, try to find the vehicle
        if isRepair or isRepaint then
            -- Try to get vehicle from target (WorkshopScreen)
            if target ~= nil and target.vehicle ~= nil then
                vehicle = target.vehicle
                UsedPlus.logTrace(string.format("Got vehicle from target: %s", tostring(vehicle.configFileName)))
            end

            -- Try to get vehicle from current workshop screen
            if vehicle == nil and VehicleSellingPointExtension.currentWorkshopScreen ~= nil then
                vehicle = VehicleSellingPointExtension.currentWorkshopScreen.vehicle
                UsedPlus.logTrace("Got vehicle from stored workshop screen")
            end

            -- Try to get vehicle from g_currentMission.controlledVehicle
            if vehicle == nil and g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil then
                vehicle = g_currentMission.controlledVehicle
                UsedPlus.logTrace("Got vehicle from controlled vehicle")
            end

            -- Try to find vehicle from mobile workshop vehicles (e.g., MobileServiceKit)
            if vehicle == nil and g_currentMission ~= nil then
                for _, v in pairs(g_currentMission.vehicleSystem.vehicles or {}) do
                    for specName, spec in pairs(v) do
                        if type(spec) == "table" and spec.sellingPoint ~= nil and spec.sellingPoint.currentVehicle ~= nil then
                            vehicle = spec.sellingPoint.currentVehicle
                            UsedPlus.logTrace("Got vehicle from mobile workshop (MobileServiceKit)")
                            break
                        end
                    end
                    if vehicle ~= nil then break end
                end
            end

            -- If we found a vehicle, show our custom dialog instead
            if vehicle ~= nil then
                -- Store the callback in case user wants to do vanilla repair
                VehicleSellingPointExtension.pendingRepairCallback = callback
                VehicleSellingPointExtension.pendingRepairVehicle = vehicle

                -- Determine mode
                local mode = RepairDialog.MODE_BOTH
                if isRepair and not isRepaint then
                    mode = RepairDialog.MODE_REPAIR
                elseif isRepaint and not isRepair then
                    mode = RepairDialog.MODE_REPAINT
                end

                -- Show our custom dialog
                local success = VehicleSellingPointExtension.showRepairDialog(vehicle, mode)

                if success then
                    UsedPlus.logDebug("Intercepted and replaced repair dialog with custom dialog")
                    return -- Don't show the original dialog
                else
                    UsedPlus.logDebug("Failed to show custom dialog, falling back to vanilla")
                end
            else
                UsedPlus.logTrace("Could not find vehicle for repair dialog")
            end
        end

        -- If not intercepted, call original
        VehicleSellingPointExtension.originalShowYesNoDialog(guiSelf, args)
    end

    UsedPlus.logDebug("g_gui.showYesNoDialog hooked successfully")
end

--[[
    Hook WorkshopScreen.onOpen to capture the current workshop screen
    This helps us get the vehicle reference when the dialog is shown
]]
function VehicleSellingPointExtension.hookWorkshopScreen()
    if WorkshopScreen == nil then
        UsedPlus.logDebug("WorkshopScreen not available")
        return
    end

    -- Hook onOpen to capture the workshop screen reference
    if WorkshopScreen.onOpen ~= nil then
        WorkshopScreen.onOpen = Utils.appendedFunction(WorkshopScreen.onOpen,
            function(self)
                UsedPlus.logTrace("WorkshopScreen.onOpen called")
                VehicleSellingPointExtension.currentWorkshopScreen = self
                if self.vehicle then
                    local vehicleName = "Unknown"
                    local storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
                    if storeItem then
                        vehicleName = storeItem.name or vehicleName
                    end
                    UsedPlus.logTrace(string.format("WorkshopScreen opened for: %s", vehicleName))
                end
            end
        )
        UsedPlus.logDebug("WorkshopScreen.onOpen hooked")
    end

    -- Hook onClose to clear the reference
    if WorkshopScreen.onClose ~= nil then
        WorkshopScreen.onClose = Utils.appendedFunction(WorkshopScreen.onClose,
            function(self)
                UsedPlus.logTrace("WorkshopScreen.onClose called")
                VehicleSellingPointExtension.currentWorkshopScreen = nil
            end
        )
        UsedPlus.logDebug("WorkshopScreen.onClose hooked")
    end
end

--[[
    Initialize hooks when mission starts
    We need to wait for g_gui to be available
]]
function VehicleSellingPointExtension.init()
    UsedPlus.logDebug("VehicleSellingPointExtension.init called")

    -- Hook showYesNoDialog
    VehicleSellingPointExtension.hookShowYesNoDialog()

    -- Hook WorkshopScreen
    VehicleSellingPointExtension.hookWorkshopScreen()
end

--[[
    Hook g_gui:showDialog to intercept YesNoDialog for repair/repaint
    The game calls g_gui:showDialog("YesNoDialog") for repair/repaint confirmations
]]
function VehicleSellingPointExtension.hookAllDialogs()
    if g_gui == nil then
        UsedPlus.logDebug("g_gui not available for dialog hooks")
        return
    end

    -- Only hook showDialog once
    if VehicleSellingPointExtension.originalShowDialog ~= nil then
        UsedPlus.logTrace("showDialog already hooked")
        return
    end

    -- Hook showDialog - this is the one the game uses
    if g_gui.showDialog ~= nil then
        VehicleSellingPointExtension.originalShowDialog = g_gui.showDialog
        g_gui.showDialog = function(guiSelf, name, ...)
            -- Always log dialog opens for debugging (DEBUG level to appear in log)
            UsedPlus.logDebug(string.format("=== showDialog called: name='%s' ===", tostring(name)))

            -- TEMPORARY DEBUG: Pass through ALL dialogs to test if our hook is causing shop issues
            -- Comment out to re-enable interception
            if VehicleSellingPointExtension.DEBUG_PASSTHROUGH_ALL then
                return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
            end

            -- Check if we should bypass interception (for our own finance confirmation dialog)
            if VehicleSellingPointExtension.bypassInterception then
                VehicleSellingPointExtension.bypassInterception = false
                UsedPlus.logTrace("Bypassing interception for our own dialog")
                return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
            end

            -- Intercept SellItemDialog (ESC -> Vehicles -> Sell)
            -- This is the vanilla vehicle sell dialog - we replace it with our agent-based system
            if name == "SellItemDialog" then
                UsedPlus.logDebug(">>> INTERCEPTING SellItemDialog <<<")
                VehicleSellingPointExtension.logGuiState("BEFORE_SELLITEM_INTERCEPT")

                -- Get the vehicle that's being sold from the dialog
                local sellDialog = g_gui.guis.SellItemDialog
                local vehicle = nil

                if sellDialog and sellDialog.target then
                    -- The SellItemDialog stores the item/vehicle info
                    local target = sellDialog.target
                    if target.vehicle then
                        vehicle = target.vehicle
                    elseif target.item then
                        vehicle = target.item
                    elseif target.currentVehicle then
                        vehicle = target.currentVehicle
                    end
                end

                -- Try to get from InGameMenu's vehicles frame
                if vehicle == nil then
                    local inGameMenu = g_gui.screenControllers[InGameMenu]
                    if inGameMenu then
                        -- Try various ways to get the selected vehicle
                        for pageName, page in pairs(inGameMenu) do
                            if type(page) == "table" and page.getSelectedVehicle then
                                vehicle = page:getSelectedVehicle()
                                if vehicle then
                                    UsedPlus.logTrace(string.format("Got vehicle from %s.getSelectedVehicle()", pageName))
                                    break
                                end
                            end
                            if type(page) == "table" and page.selectedVehicle then
                                vehicle = page.selectedVehicle
                                if vehicle then
                                    UsedPlus.logTrace(string.format("Got vehicle from %s.selectedVehicle", pageName))
                                    break
                                end
                            end
                        end
                    end
                end

                -- Also try g_currentMission sources
                if vehicle == nil and g_currentMission then
                    if g_currentMission.controlledVehicle then
                        vehicle = g_currentMission.controlledVehicle
                        UsedPlus.logTrace("Got vehicle from controlledVehicle")
                    end
                end

                if vehicle ~= nil then
                    local farmId = g_currentMission:getFarmId()

                    -- Check if vehicle is owned (not leased)
                    if vehicle.propertyState ~= VehiclePropertyState.OWNED then
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            "Leased vehicles cannot be sold. Terminate the lease first."
                        )
                        return -- Don't show any dialog
                    end

                    -- Check if vehicle is leased via UsedPlus
                    if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_ERROR,
                            g_i18n:getText("usedplus_error_cannotSellLeasedVehicle")
                        )
                        return -- Don't show any dialog
                    end

                    -- Check if already listed
                    if g_vehicleSaleManager and g_vehicleSaleManager:isVehicleListed(vehicle) then
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            "This vehicle is already listed for sale."
                        )
                        return -- Don't show any dialog
                    end

                    -- Check if vehicle is pledged as collateral for a cash loan
                    if CollateralUtils and CollateralUtils.isVehiclePledged then
                        local isPledged, deal = CollateralUtils.isVehiclePledged(vehicle)
                        if isPledged then
                            local loanBalance = deal and deal.currentBalance or 0
                            g_currentMission:addIngameNotification(
                                FSBaseMission.INGAME_NOTIFICATION_ERROR,
                                string.format("This vehicle is pledged as collateral for a %s loan.\nPay off the loan first to sell.",
                                    g_i18n:formatMoney(loanBalance, 0, true, true))
                            )
                            return -- Don't show any dialog
                        end
                    end

                    -- Show our custom sell dialog
                    UsedPlus.logDebug(string.format(">>> Showing SellVehicleDialog for: %s <<<", vehicle:getName()))
                    VehicleSellingPointExtension.logGuiState("BEFORE_SHOW_OUR_DIALOG")

                    local result = VehicleSellingPointExtension.showSellVehicleDialog(vehicle, farmId)

                    UsedPlus.logDebug(string.format(">>> SellVehicleDialog shown, result=%s <<<", tostring(result)))
                    VehicleSellingPointExtension.logGuiState("AFTER_SHOW_OUR_DIALOG")

                    -- Clear any GUI blocking state that might have been set
                    -- The game may have prepared for SellItemDialog to open
                    pcall(function()
                        if g_gui then
                            -- Try to close SellItemDialog if it exists in any state
                            g_gui:closeDialogByName("SellItemDialog")
                            UsedPlus.logDebug(">>> Attempted closeDialogByName(SellItemDialog) <<<")
                        end
                    end)

                    VehicleSellingPointExtension.logGuiState("AFTER_CLEANUP_ATTEMPT")

                    -- Return the result to prevent caller from waiting for nil response
                    UsedPlus.logDebug(string.format(">>> Returning from SellItemDialog intercept with: %s <<<", tostring(result or true)))
                    return result or true
                else
                    UsedPlus.logTrace("Could not find vehicle for SellItemDialog, showing vanilla")
                end
            end

            -- Check if this is a YesNoDialog (repair/repaint confirmation)
            if name == "YesNoDialog" then
                -- Get the YesNoDialog instance to check its text
                local dialog = g_gui.guis.YesNoDialog
                if dialog ~= nil then
                    -- The dialog text is set before showDialog is called
                    -- We need to check if it's a repair/repaint dialog
                    local dialogTarget = dialog.target or dialog
                    local text = ""

                    -- Debug: dump all properties to find where text is stored
                    UsedPlus.logTrace("YesNoDialog properties:")
                    for k, v in pairs(dialogTarget) do
                        local vType = type(v)
                        if vType == "string" and #v > 0 and #v < 200 then
                            UsedPlus.logTrace(string.format("  %s = '%s'", tostring(k), v))
                        elseif vType == "table" then
                            -- Check for text in nested tables
                            if v.text then
                                UsedPlus.logTrace(string.format("  %s.text = '%s'", tostring(k), tostring(v.text)))
                            end
                        end
                    end

                    -- Try multiple ways to get the dialog text
                    if dialogTarget.text then
                        text = dialogTarget.text
                    elseif dialogTarget.messageText and dialogTarget.messageText.text then
                        text = dialogTarget.messageText.text
                    elseif dialogTarget.dialogText then
                        text = dialogTarget.dialogText
                    elseif dialogTarget.yesNoDialogText then
                        text = dialogTarget.yesNoDialogText
                    end

                    -- Also try to get from the dialog element hierarchy
                    if text == "" and dialogTarget.dialogTextElement then
                        text = dialogTarget.dialogTextElement.text or ""
                    end

                    UsedPlus.logTrace(string.format("YesNoDialog text: '%s'", string.sub(tostring(text), 1, 100)))

                    local textLower = string.lower(tostring(text))

                    -- Detect repair dialog
                    local isRepair = string.find(textLower, "repair") and not string.find(textLower, "paint")
                    local isRepaint = string.find(textLower, "repaint") or string.find(textLower, "paint")

                    -- German detection
                    if string.find(textLower, "reparieren") or string.find(textLower, "reparatur") then
                        isRepair = true
                    end
                    if string.find(textLower, "lackieren") or string.find(textLower, "lackierung") then
                        isRepaint = true
                    end

                    if isRepair or isRepaint then
                        UsedPlus.logTrace(string.format("Detected %s dialog!", isRepair and "REPAIR" or "REPAINT"))

                        -- Try to get the vehicle from multiple sources
                        local vehicle = nil

                        -- From stored workshop screen
                        if VehicleSellingPointExtension.currentWorkshopScreen ~= nil and VehicleSellingPointExtension.currentWorkshopScreen.vehicle ~= nil then
                            vehicle = VehicleSellingPointExtension.currentWorkshopScreen.vehicle
                            UsedPlus.logTrace("Got vehicle from stored WorkshopScreen")
                        end

                        -- Try g_workshopScreen global
                        if vehicle == nil and g_workshopScreen ~= nil and g_workshopScreen.vehicle ~= nil then
                            vehicle = g_workshopScreen.vehicle
                            UsedPlus.logTrace("Got vehicle from g_workshopScreen")
                        end

                        -- Try from current GUI's target (the WorkshopScreen that triggered the dialog)
                        if vehicle == nil and g_gui.currentGui ~= nil then
                            local currentTarget = g_gui.currentGui.target or g_gui.currentGui
                            if currentTarget.vehicle ~= nil then
                                vehicle = currentTarget.vehicle
                                UsedPlus.logTrace("Got vehicle from g_gui.currentGui")
                            end
                        end

                        -- Try from g_currentMission.interactiveVehicle
                        if vehicle == nil and g_currentMission ~= nil and g_currentMission.interactiveVehicle ~= nil then
                            vehicle = g_currentMission.interactiveVehicle
                            UsedPlus.logTrace("Got vehicle from interactiveVehicle")
                        end

                        -- From controlled vehicle (player is in vehicle)
                        if vehicle == nil and g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil then
                            vehicle = g_currentMission.controlledVehicle
                            UsedPlus.logTrace("Got vehicle from controlledVehicle")
                        end

                        -- Try to find vehicle from VehicleSellingPoint's current object
                        if vehicle == nil then
                            -- Iterate through placeables to find a vehicle selling point with active vehicle
                            if g_currentMission.placeableSystem ~= nil then
                                for _, placeable in pairs(g_currentMission.placeableSystem.placeables or {}) do
                                    if placeable.spec_vehicleSellingPoint ~= nil then
                                        local sp = placeable.spec_vehicleSellingPoint
                                        if sp.currentVehicle ~= nil then
                                            vehicle = sp.currentVehicle
                                            UsedPlus.logTrace("Got vehicle from placeable VehicleSellingPoint")
                                            break
                                        end
                                    end
                                end
                            end
                        end

                        -- Try to find vehicle from mobile workshop vehicles (e.g., MobileServiceKit)
                        -- These are vehicles with VehicleSellingPoint or VehicleWorkshop specialization
                        if vehicle == nil then
                            for _, v in pairs(g_currentMission.vehicleSystem.vehicles or {}) do
                                -- Check for any spec that might have a selling point
                                for specName, spec in pairs(v) do
                                    if type(spec) == "table" and spec.sellingPoint ~= nil and spec.sellingPoint.currentVehicle ~= nil then
                                        vehicle = spec.sellingPoint.currentVehicle
                                        UsedPlus.logTrace("Got vehicle from mobile workshop (MobileServiceKit or similar)")
                                        break
                                    end
                                end
                                if vehicle ~= nil then break end
                            end
                        end

                        UsedPlus.logTrace(string.format("Vehicle found: %s", tostring(vehicle ~= nil)))

                        if vehicle ~= nil then
                            local mode = RepairDialog.MODE_BOTH
                            if isRepair and not isRepaint then
                                mode = RepairDialog.MODE_REPAIR
                            elseif isRepaint and not isRepair then
                                mode = RepairDialog.MODE_REPAINT
                            end

                            -- Show our custom dialog instead
                            local success = VehicleSellingPointExtension.showRepairDialog(vehicle, mode)
                            if success then
                                UsedPlus.logDebug("Intercepted YesNoDialog and showed custom repair dialog")
                                return -- Don't show the original YesNoDialog
                            end
                        else
                            UsedPlus.logTrace("Could not find vehicle, showing vanilla dialog")
                        end
                    end
                end
            end

            -- Call original for non-repair dialogs or if we couldn't intercept
            return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
        end
        UsedPlus.logDebug("showDialog hooked for YesNoDialog interception")
    end
end

-- Install hooks at load time
if g_gui ~= nil then
    VehicleSellingPointExtension.hookAllDialogs()
    UsedPlus.logDebug("Dialog hooks installed at load time")
else
    UsedPlus.logDebug("g_gui not available at load time, will hook later")
end

if WorkshopScreen ~= nil then
    VehicleSellingPointExtension.hookWorkshopScreen()
    UsedPlus.logDebug("WorkshopScreen hooked at load time")
else
    UsedPlus.logDebug("WorkshopScreen not available at load time")
end

-- Also register for mission start to ensure hooks are in place
if Mission00 ~= nil then
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission,
        function(self)
            UsedPlus.logDebug("Mission started - ensuring hooks are installed")
            VehicleSellingPointExtension.hookAllDialogs()
        end
    )
    UsedPlus.logDebug("Mission00.onStartMission hook installed")
end

UsedPlus.logInfo("VehicleSellingPointExtension loaded")
