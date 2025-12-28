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
VehicleSellingPointExtension.pendingSellCallback = nil
VehicleSellingPointExtension.sellItemDialogHooked = false
VehicleSellingPointExtension.sellButtonHooked = false

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
            local stackNames = {}
            for i, d in ipairs(g_gui.dialogStack) do
                table.insert(stackNames, d.name or "?")
            end
            table.insert(stateInfo, string.format("dialogStack=%d [%s]", #g_gui.dialogStack, table.concat(stackNames, ",")))
        end

        -- Check modal/blocking state
        if g_gui.isInputDisabledForFocus then
            table.insert(stateInfo, "inputDisabledForFocus=true")
        end
        if g_gui.currentDialog then
            local cdName = g_gui.currentDialog.name or "?"
            table.insert(stateInfo, string.format("currentDialog=%s", cdName))
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
    -- Callback receives BOTH agentTier and priceTier from dual-tier system
    local callback = function(agentTier, priceTier)
        if agentTier ~= nil then
            -- Player selected tiers - create listing
            VehicleSellingPointExtension.createSaleListing(vehicle, farmId, agentTier, priceTier)
        else
            UsedPlus.logDebug("Sale dialog cancelled")
        end

        -- TEMPORARILY DISABLED: Calling the original callback may be causing issues
        -- Clear the pending callback reference
        if VehicleSellingPointExtension.pendingSellCallback then
            UsedPlus.logDebug(">>> NOT calling original callback (disabled for testing) <<<")
            VehicleSellingPointExtension.pendingSellCallback = nil
        end
    end

    return DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)
end

--[[
    Create a sale listing through VehicleSaleManager
    @param vehicle - The vehicle to sell
    @param farmId - The owning farm
    @param agentTier - Selected agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Selected price tier (1=Quick, 2=Market, 3=Premium)
]]
function VehicleSellingPointExtension.createSaleListing(vehicle, farmId, agentTier, priceTier)
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("VehicleSaleManager not initialized")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Sale system error. Please try again."
        )
        return
    end

    -- Default priceTier for legacy compatibility
    priceTier = priceTier or 2

    -- Create listing through manager (passes both tiers)
    local listing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier)

    if listing then
        UsedPlus.logDebug(string.format("Created sale listing: %s (Agent %d, Price %d, ID: %s)",
            listing.vehicleName, agentTier, priceTier, listing.id))

        -- Show styled confirmation dialog
        VehicleSellingPointExtension.showSaleListingConfirmation(vehicle, agentTier, priceTier)
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Failed to create sale listing. Please try again."
        )
    end

    -- Cleanup: Clear our stored state
    UsedPlus.logDebug(">>> SALE COMPLETE <<<")
    VehicleSellingPointExtension.logGuiState("SALE_COMPLETE")

    VehicleSellingPointExtension.currentVehicle = nil
    VehicleSellingPointExtension.pendingRepairCallback = nil
    VehicleSellingPointExtension.pendingRepairVehicle = nil
    VehicleSellingPointExtension.pendingSellCallback = nil
    VehicleSellingPointExtension.bypassInterception = false
end

--[[
    Show the SaleListingInitiatedDialog with listing details
    @param vehicle - The vehicle being sold
    @param agentTier - Agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Price tier (1=Quick, 2=Market, 3=Premium)
]]
function VehicleSellingPointExtension.showSaleListingConfirmation(vehicle, agentTier, priceTier)
    -- Get tier definitions from SellVehicleDialog or VehicleSaleListing
    local agentOptions = SellVehicleDialog and SellVehicleDialog.AGENT_OPTIONS
    local priceOptions = SellVehicleDialog and SellVehicleDialog.PRICE_OPTIONS

    -- Fallback to VehicleSaleListing if SellVehicleDialog not available
    if not agentOptions then
        agentOptions = VehicleSaleListing and VehicleSaleListing.AGENT_TIERS
    end
    if not priceOptions then
        priceOptions = VehicleSaleListing and VehicleSaleListing.PRICE_TIERS
    end

    if not agentOptions or not priceOptions then
        UsedPlus.logError("Cannot show confirmation - tier definitions not found")
        return
    end

    -- Find agent option (array for SellVehicleDialog, keyed for VehicleSaleListing)
    local agentOption = nil
    if agentOptions[1] and agentOptions[1].tier ~= nil then
        -- SellVehicleDialog format (array with tier field)
        for _, opt in ipairs(agentOptions) do
            if opt.tier == agentTier then
                agentOption = opt
                break
            end
        end
    else
        -- VehicleSaleListing format (keyed by tier)
        agentOption = agentOptions[agentTier]
    end

    local priceOption = priceOptions[priceTier]

    if not agentOption or not priceOption then
        UsedPlus.logError(string.format("Invalid tier values: agent=%s, price=%s", tostring(agentTier), tostring(priceTier)))
        return
    end

    -- Get vanilla sell price
    local vanillaSellPrice = 0
    if vehicle and vehicle.getSellPrice then
        vanillaSellPrice = vehicle:getSellPrice()
    end

    -- Calculate expected price range
    local minPrice = math.floor(vanillaSellPrice * priceOption.priceMultiplierMin)
    local maxPrice = math.floor(vanillaSellPrice * priceOption.priceMultiplierMax)

    -- Calculate agent fee (percentage of expected mid-price)
    local expectedMid = (minPrice + maxPrice) / 2
    local agentFee = 0
    local isPrivateSale = (agentOption.feePercent == 0) or (agentTier == 0)
    if not isPrivateSale then
        agentFee = math.max(50, math.floor(expectedMid * agentOption.feePercent))
    end

    -- Calculate combined success rate
    local successRate = math.max(0.10, math.min(0.98,
        agentOption.baseSuccessRate + (priceOption.successModifier or 0)))

    -- Get vehicle name
    local vehicleName = "Unknown Vehicle"
    if vehicle and vehicle.configFileName then
        local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        if UIHelper and UIHelper.Vehicle and UIHelper.Vehicle.getFullName then
            vehicleName = UIHelper.Vehicle.getFullName(storeItem)
        elseif storeItem and storeItem.name then
            vehicleName = storeItem.name
        end
    end

    -- Show dialog with details
    local details = {
        vehicleName = vehicleName,
        agentName = agentOption.name,
        agentFee = agentFee,
        isPrivateSale = isPrivateSale,
        priceTierName = priceOption.name,
        minPrice = minPrice,
        maxPrice = maxPrice,
        minMonths = agentOption.minMonths,
        maxMonths = agentOption.maxMonths,
        successRate = successRate
    }

    SaleListingInitiatedDialog.showWithDetails(details)
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
            if name == "SellItemDialog" then
                UsedPlus.logDebug("Intercepting SellItemDialog - showing UsedPlus SellVehicleDialog instead")

                -- Try to get the vehicle from various sources
                local vehicle = nil

                -- Method 1: Check if we stored a reference from InGameMenuVehiclesFrameExtension
                if InGameMenuVehiclesFrameExtension and InGameMenuVehiclesFrameExtension.lastSelectedVehicle then
                    vehicle = InGameMenuVehiclesFrameExtension.lastSelectedVehicle
                    UsedPlus.logDebug("Got vehicle from InGameMenuVehiclesFrameExtension.lastSelectedVehicle")
                end

                -- Method 2: Search through InGameMenu's pages array
                if vehicle == nil and g_currentMission and g_currentMission.inGameMenu then
                    local inGameMenu = g_currentMission.inGameMenu
                    -- Try pageFrames array
                    if inGameMenu.pageFrames then
                        for i, frame in ipairs(inGameMenu.pageFrames) do
                            if frame and frame.getSelectedVehicle then
                                local v = frame:getSelectedVehicle()
                                if v then
                                    vehicle = v
                                    UsedPlus.logDebug("Got vehicle from inGameMenu.pageFrames[" .. i .. "]")
                                    break
                                end
                            end
                        end
                    end
                    -- Try pages array
                    if vehicle == nil and inGameMenu.pages then
                        for i, page in ipairs(inGameMenu.pages) do
                            local frame = page.element or page
                            if frame and frame.getSelectedVehicle then
                                local v = frame:getSelectedVehicle()
                                if v then
                                    vehicle = v
                                    UsedPlus.logDebug("Got vehicle from inGameMenu.pages[" .. i .. "]")
                                    break
                                end
                            end
                        end
                    end
                end

                -- Method 3: Try g_gui.screenControllers
                if vehicle == nil and g_gui and g_gui.screenControllers then
                    for screenClass, controller in pairs(g_gui.screenControllers) do
                        if controller and controller.getSelectedVehicle then
                            local v = controller:getSelectedVehicle()
                            if v then
                                vehicle = v
                                UsedPlus.logDebug("Got vehicle from g_gui.screenControllers")
                                break
                            end
                        end
                        -- Check pages inside controller
                        if controller and controller.pageFrames then
                            for i, frame in ipairs(controller.pageFrames) do
                                if frame and frame.getSelectedVehicle then
                                    local v = frame:getSelectedVehicle()
                                    if v then
                                        vehicle = v
                                        UsedPlus.logDebug("Got vehicle from controller.pageFrames[" .. i .. "]")
                                        break
                                    end
                                end
                            end
                        end
                        if vehicle then break end
                    end
                end

                -- Method 4: Try InGameMenuVehiclesFrame class directly if instance exists
                if vehicle == nil and InGameMenuVehiclesFrame then
                    -- Look through g_gui.guis for the vehicles frame
                    if g_gui and g_gui.guis then
                        for guiName, gui in pairs(g_gui.guis) do
                            if gui and gui.target and gui.target.getSelectedVehicle then
                                local v = gui.target:getSelectedVehicle()
                                if v then
                                    vehicle = v
                                    UsedPlus.logDebug("Got vehicle from g_gui.guis." .. guiName .. ".target")
                                    break
                                end
                            end
                        end
                    end
                end

                -- Method 5: Check SellItemDialog itself for vehicle reference
                if vehicle == nil and g_gui.guis and g_gui.guis.SellItemDialog then
                    local sellDialog = g_gui.guis.SellItemDialog
                    UsedPlus.logDebug("Checking SellItemDialog properties:")
                    -- Log what properties exist
                    for k, v in pairs(sellDialog) do
                        if type(v) ~= "function" then
                            UsedPlus.logDebug("  SellItemDialog." .. tostring(k) .. " = " .. type(v))
                        end
                    end
                    if sellDialog.target then
                        local target = sellDialog.target
                        vehicle = target.vehicle or target.selectedVehicle or target.currentVehicle or target.item
                        if target.object then
                            vehicle = target.object
                        end
                        if vehicle then
                            UsedPlus.logDebug("Got vehicle from SellItemDialog.target")
                        end
                    end
                    -- Check object directly on dialog
                    if vehicle == nil then
                        vehicle = sellDialog.vehicle or sellDialog.object or sellDialog.item or sellDialog.selectedVehicle
                        if vehicle then
                            UsedPlus.logDebug("Got vehicle directly from SellItemDialog")
                        end
                    end
                end

                if vehicle and g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                    local farmId = g_currentMission:getFarmId()
                    UsedPlus.logInfo("Successfully found vehicle for SellItemDialog intercept: " .. tostring(vehicle.configFileName))

                    -- Show our dialog instead
                    local callback = function(agentTier, priceTier)
                        if agentTier ~= nil then
                            -- Create sale listing
                            local listing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier or 2)
                            if listing then
                                UsedPlus.logInfo(string.format("Created sale listing for %s", listing.vehicleName))
                                -- Show confirmation
                                VehicleSellingPointExtension.showSaleListingConfirmation(vehicle, agentTier, priceTier)
                            end
                        end
                    end

                    DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)

                    -- DON'T show the vanilla dialog
                    return
                else
                    UsedPlus.logDebug("Could not find vehicle for SellItemDialog intercept, falling back to vanilla")
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

--[[
    Hook WorkshopScreen's sell button to show our dialog instead
]]
function VehicleSellingPointExtension.hookSellButton()
    if VehicleSellingPointExtension.sellButtonHooked then
        return
    end

    -- Hook WorkshopScreen.onClickSell if it exists
    if WorkshopScreen ~= nil and WorkshopScreen.onClickSell ~= nil then
        local originalOnClickSell = WorkshopScreen.onClickSell
        WorkshopScreen.onClickSell = function(self, ...)
            UsedPlus.logDebug(">>> WorkshopScreen.onClickSell intercepted <<<")

            local vehicle = self.vehicle
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

                -- Show OUR dialog instead of calling original
                UsedPlus.logDebug(">>> Showing our SellVehicleDialog <<<")
                VehicleSellingPointExtension.showSellVehicleDialog(vehicle, farmId)
                -- DON'T call original - we handle it completely
                return
            end

            -- No vehicle, let original handle it
            return originalOnClickSell(self, ...)
        end
        VehicleSellingPointExtension.sellButtonHooked = true
        UsedPlus.logDebug(">>> WorkshopScreen.onClickSell hooked <<<")
    else
        UsedPlus.logDebug("WorkshopScreen.onClickSell not found")
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

-- Hook the sell button at load time
if WorkshopScreen ~= nil then
    VehicleSellingPointExtension.hookSellButton()
else
    UsedPlus.logDebug("WorkshopScreen not available for sell button hook")
end

-- Also register for mission start to ensure hooks are in place
if Mission00 ~= nil then
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission,
        function(self)
            UsedPlus.logDebug("Mission started - ensuring hooks are installed")
            VehicleSellingPointExtension.hookAllDialogs()
            VehicleSellingPointExtension.hookSellButton()
        end
    )
    UsedPlus.logDebug("Mission00.onStartMission hook installed")
end

UsedPlus.logInfo("VehicleSellingPointExtension loaded")
