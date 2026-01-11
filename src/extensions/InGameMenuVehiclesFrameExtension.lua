--[[
    FS25_UsedPlus - InGameMenu Vehicles Frame Extension

    Hooks the Sell button in ESC -> Vehicles page
    Replaces vanilla instant-sell with agent-based sale system
    Pattern from: ShopConfigScreenExtension (hook existing UI)

    Flow:
    1. Player selects vehicle in ESC -> Vehicles
    2. Player clicks "Sell"
    3. Instead of vanilla confirmation, show SellVehicleDialog
    4. Player selects agent tier
    5. Create VehicleSaleListing and start agent search
    6. Vehicle remains in inventory until sold
]]

InGameMenuVehiclesFrameExtension = {}

-- Store reference to original sell function
InGameMenuVehiclesFrameExtension.originalOnClickSell = nil
InGameMenuVehiclesFrameExtension.originalGetDisplayName = nil
InGameMenuVehiclesFrameExtension.isInitialized = false

-- Store selected vehicle for cross-extension access
InGameMenuVehiclesFrameExtension.lastSelectedVehicle = nil
InGameMenuVehiclesFrameExtension.lastSelectedFrame = nil

--[[
    Initialize the extension
    Called from main.lua after mission starts
]]
function InGameMenuVehiclesFrameExtension:init()
    if self.isInitialized then
        UsedPlus.logDebug("InGameMenuVehiclesFrameExtension already initialized")
        return
    end

    -- Hook InGameMenuVehiclesFrame.onClickSell
    self:hookSellButton()

    -- Hook vehicle display name to show (LEASED) indicator
    self:hookVehicleDisplayName()

    -- Hook menu buttons to add "Maintenance" button
    self:hookMenuButtons()

    -- Hook YesNoDialog to intercept vehicle sell confirmations
    self:hookYesNoDialog()

    self.isInitialized = true
    UsedPlus.logDebug("InGameMenuVehiclesFrameExtension initialized")
end

--[[
    Hook YesNoDialog.show to intercept vehicle sell confirmations
    This is the most reliable way to catch sell actions
]]
function InGameMenuVehiclesFrameExtension:hookYesNoDialog()
    if self.originalYesNoDialogShow then
        UsedPlus.logDebug("YesNoDialog already hooked")
        return
    end

    if YesNoDialog == nil or YesNoDialog.show == nil then
        UsedPlus.logWarn("YesNoDialog not found, cannot hook")
        return
    end

    self.originalYesNoDialogShow = YesNoDialog.show

    YesNoDialog.show = function(callback, target, text, ...)
        -- Check if this is a vehicle sell confirmation
        local isSellConfirmation = false
        local sellText1 = g_i18n:getText("ui_youWantToSellVehicle")
        local sellText2 = g_i18n:getText("shop_doYouWantToSellItem")

        -- Safely convert text to string (may be table/localized text object)
        local textStr = type(text) == "string" and text or tostring(text or "")
        local textLower = textStr:lower()

        if text and (text == sellText1 or text == sellText2 or
                     string.find(textLower, "sell") or
                     string.find(textLower, "verkauf")) then
            isSellConfirmation = true
        end

        UsedPlus.logDebug(string.format("YesNoDialog.show intercepted: text='%s', isSell=%s",
            tostring(text):sub(1, 50), tostring(isSellConfirmation)))

        -- v1.4.0: Check settings system for vehicle sale feature toggle
        local saleEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("VehicleSale")
        if isSellConfirmation and saleEnabled and g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
            -- Try to get the vehicle from the current context
            local vehicle = nil

            -- Method 1: Check if we're on the Vehicles page
            if g_currentMission and g_currentMission.inGameMenu then
                local inGameMenu = g_currentMission.inGameMenu
                if inGameMenu.pageVehicles and inGameMenu.pageVehicles.getSelectedVehicle then
                    vehicle = inGameMenu.pageVehicles:getSelectedVehicle()
                end
            end

            -- Method 2: Try g_inGameMenu
            if vehicle == nil and g_inGameMenu and g_inGameMenu.pageVehicles then
                if g_inGameMenu.pageVehicles.getSelectedVehicle then
                    vehicle = g_inGameMenu.pageVehicles:getSelectedVehicle()
                end
            end

            -- Method 3: Check target for vehicle reference
            if vehicle == nil and target then
                if target.selectedVehicle then
                    vehicle = target.selectedVehicle
                elseif target.items and target.itemsList and target.itemsList.selectedIndex then
                    vehicle = target.items[target.itemsList.selectedIndex]
                end
            end

            if vehicle then
                UsedPlus.logInfo("Intercepted vehicle sell - showing UsedPlus dialog instead")
                local farmId = g_currentMission:getFarmId()
                InGameMenuVehiclesFrameExtension:showSellDialog(vehicle, farmId, nil)
                return  -- Don't show the vanilla YesNoDialog
            else
                UsedPlus.logDebug("Could not find vehicle for sell intercept, falling back to vanilla")
            end
        end

        -- Call original for non-sell dialogs or if we couldn't intercept
        return InGameMenuVehiclesFrameExtension.originalYesNoDialogShow(callback, target, text, ...)
    end

    UsedPlus.logInfo("Hooked YesNoDialog.show for vehicle sell intercept")
end

--[[
    Hook menu buttons - append to updateMenuButtons to swap sell callback
    Same pattern as ShopConfigScreenExtension.updateButtonsHook
]]
function InGameMenuVehiclesFrameExtension:hookMenuButtons()
    -- Already hooked?
    if self.menuButtonsHooked then
        UsedPlus.logDebug("Menu buttons already hooked, skipping")
        return true
    end

    local targetClass = InGameMenuVehiclesFrame

    if targetClass == nil then
        UsedPlus.logWarn("InGameMenuVehiclesFrame not found")
        return false
    end

    -- Hook onFrameOpen to capture frame reference when page opens
    if targetClass.onFrameOpen then
        targetClass.onFrameOpen = Utils.appendedFunction(
            targetClass.onFrameOpen,
            function(frame, ...)
                InGameMenuVehiclesFrameExtension.lastSelectedFrame = frame
                if frame and frame.getSelectedVehicle then
                    InGameMenuVehiclesFrameExtension.lastSelectedVehicle = frame:getSelectedVehicle()
                    UsedPlus.logDebug("Vehicles page opened - stored frame and vehicle")
                end
            end
        )
        UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onFrameOpen")
    end

    -- Hook updateMenuButtons - this is called when selection changes
    if targetClass.updateMenuButtons then
        targetClass.updateMenuButtons = Utils.appendedFunction(
            targetClass.updateMenuButtons,
            InGameMenuVehiclesFrameExtension.updateMenuButtonsHook
        )
        UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.updateMenuButtons")
        self.menuButtonsHooked = true
        return true
    end

    -- Also hook onListSelectionChanged to capture vehicle on selection
    if targetClass.onListSelectionChanged then
        targetClass.onListSelectionChanged = Utils.appendedFunction(
            targetClass.onListSelectionChanged,
            function(frame, ...)
                -- Store selected vehicle whenever selection changes
                if frame and frame.getSelectedVehicle then
                    InGameMenuVehiclesFrameExtension.lastSelectedVehicle = frame:getSelectedVehicle()
                    InGameMenuVehiclesFrameExtension.lastSelectedFrame = frame
                    if InGameMenuVehiclesFrameExtension.lastSelectedVehicle then
                        UsedPlus.logDebug("Selection changed - stored vehicle: " .. tostring(InGameMenuVehiclesFrameExtension.lastSelectedVehicle.configFileName))
                    end
                end
                InGameMenuVehiclesFrameExtension.updateMenuButtonsHook(frame)
            end
        )
        UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onListSelectionChanged")
    end

    -- If we couldn't hook updateMenuButtons, use onListSelectionChanged as primary
    if not self.menuButtonsHooked and targetClass.onListSelectionChanged then
        self.menuButtonsHooked = true
        return true
    end

    UsedPlus.logWarn("Could not find updateMenuButtons or onListSelectionChanged to hook")
    return false
end

--[[
    Hook that runs after updateMenuButtons - swaps sell button callback
    Same pattern as ShopConfigScreenExtension.updateButtonsHook
]]
function InGameMenuVehiclesFrameExtension.updateMenuButtonsHook(frame)
    -- Store frame and selected vehicle for cross-extension access
    InGameMenuVehiclesFrameExtension.lastSelectedFrame = frame
    if frame and frame.getSelectedVehicle then
        InGameMenuVehiclesFrameExtension.lastSelectedVehicle = frame:getSelectedVehicle()
        if InGameMenuVehiclesFrameExtension.lastSelectedVehicle then
            UsedPlus.logDebug("Stored lastSelectedVehicle: " .. tostring(InGameMenuVehiclesFrameExtension.lastSelectedVehicle.configFileName))
        end
    end

    -- Find and override the sell button callback directly
    local success, err = pcall(function()
        -- Look for sellButton on the frame
        if frame.sellButton then
            -- Store original callback ONCE
            if not frame.usedPlusOriginalSellCallback then
                frame.usedPlusOriginalSellCallback = frame.sellButton.onClickCallback
                UsedPlus.logDebug("Stored original sellButton.onClickCallback")
            end

            -- Replace callback with our override
            frame.sellButton.onClickCallback = function()
                local vehicle = nil
                if frame.getSelectedVehicle then
                    vehicle = frame:getSelectedVehicle()
                end

                if vehicle and g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                    UsedPlus.logDebug("Sell button clicked - showing UsedPlus dialog")
                    InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
                elseif frame.usedPlusOriginalSellCallback then
                    UsedPlus.logDebug("Sell button - falling back to vanilla")
                    frame.usedPlusOriginalSellCallback()
                end
            end
        end

        -- Also check for button in menuButtons array
        if frame.menuButtons then
            for i, button in ipairs(frame.menuButtons) do
                local buttonText = ""
                if button.text then
                    buttonText = button.text
                elseif button.getText then
                    buttonText = button:getText() or ""
                end

                local isSellButton = string.find(buttonText:lower(), "sell") ~= nil
                                  or string.find(buttonText:lower(), "verkauf") ~= nil
                                  or buttonText == g_i18n:getText("ui_sellItem")

                if isSellButton then
                    -- Store original
                    if not button.usedPlusOriginalCallback then
                        button.usedPlusOriginalCallback = button.onClickCallback or button.callback
                    end

                    -- Replace callback
                    local originalCallback = button.usedPlusOriginalCallback
                    local newCallback = function()
                        local vehicle = nil
                        if frame.getSelectedVehicle then
                            vehicle = frame:getSelectedVehicle()
                        end

                        if vehicle and g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                            UsedPlus.logDebug("Sell menu button clicked - showing UsedPlus dialog")
                            InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
                        elseif originalCallback then
                            originalCallback()
                        end
                    end

                    button.onClickCallback = newCallback
                    button.callback = newCallback
                    UsedPlus.logDebug("Swapped callback for sell button in menuButtons array")
                end
            end
        end
    end)

    if not success then
        UsedPlus.logError("updateMenuButtonsHook error: " .. tostring(err))
    end
end

--[[
    Hook vehicle display name in vehicle lists
    Appends "(LEASED)" to leased vehicle names
]]
function InGameMenuVehiclesFrameExtension:hookVehicleDisplayName()
    -- Hook Vehicle:getName() to append lease status
    if Vehicle == nil then
        UsedPlus.logWarn("Vehicle class not found, cannot hook getName")
        return
    end

    -- Store original getName function
    self.originalGetDisplayName = Vehicle.getName

    -- Replace with our version
    Vehicle.getName = function(vehicle)
        local name = InGameMenuVehiclesFrameExtension.originalGetDisplayName(vehicle)

        -- Check if vehicle is leased via UsedPlus system
        if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
            name = name .. " (LEASED)"
        end

        -- Check if vehicle is pledged as collateral for a cash loan
        if CollateralUtils and CollateralUtils.isVehiclePledged then
            local isPledged = CollateralUtils.isVehiclePledged(vehicle)
            if isPledged then
                name = name .. " (PLEDGED)"
            end
        end

        -- Check maintenance status (Phase 5)
        local maintenanceIndicator = InGameMenuVehiclesFrameExtension.getMaintenanceIndicator(vehicle)
        if maintenanceIndicator then
            name = name .. " " .. maintenanceIndicator
        end

        return name
    end

    UsedPlus.logDebug("Hooked Vehicle.getName for lease and maintenance indicators")
end

--[[
    Hook the sell button in InGameMenuVehiclesFrame
    Replaces onClickSell with our custom version
    Tries multiple approaches: global class, InGameMenu screen controller, g_inGameMenu
    Also hooks onButtonSell and inputEvent for keybind handling
]]
function InGameMenuVehiclesFrameExtension:hookSellButton()
    -- Already hooked?
    if self.originalOnClickSell then
        UsedPlus.logDebug("Sell button already hooked, skipping")
        return true
    end

    -- Try 1: Global InGameMenuVehiclesFrame class - check multiple method names
    if InGameMenuVehiclesFrame ~= nil then
        -- Try onClickSell
        if InGameMenuVehiclesFrame.onClickSell ~= nil then
            self.originalOnClickSell = InGameMenuVehiclesFrame.onClickSell

            InGameMenuVehiclesFrame.onClickSell = function(frame)
                InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
            end

            UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onClickSell")
        end

        -- Also try onButtonSell (some FS versions use this)
        if InGameMenuVehiclesFrame.onButtonSell ~= nil then
            self.originalOnButtonSell = InGameMenuVehiclesFrame.onButtonSell

            InGameMenuVehiclesFrame.onButtonSell = function(frame)
                if g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                    InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
                elseif InGameMenuVehiclesFrameExtension.originalOnButtonSell then
                    InGameMenuVehiclesFrameExtension.originalOnButtonSell(frame)
                end
            end

            UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onButtonSell")
        end

        -- Hook inputEvent to catch keybind presses
        if InGameMenuVehiclesFrame.inputEvent ~= nil then
            self.originalInputEvent = InGameMenuVehiclesFrame.inputEvent

            InGameMenuVehiclesFrame.inputEvent = function(frame, action, value, eventUsed)
                -- Check for sell-related input actions
                if action == InputAction.MENU_CANCEL or action == InputAction.MENU_EXTRA_2 then
                    -- This might be the sell keybind - check if we should intercept
                    local vehicle = nil
                    if frame and frame.getSelectedVehicle then
                        vehicle = frame:getSelectedVehicle()
                    end

                    if vehicle and g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                        UsedPlus.logDebug("Intercepted sell keybind via inputEvent")
                        InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
                        return true  -- Consume the event
                    end
                end

                -- Call original
                if InGameMenuVehiclesFrameExtension.originalInputEvent then
                    return InGameMenuVehiclesFrameExtension.originalInputEvent(frame, action, value, eventUsed)
                end
            end

            UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.inputEvent")
        end

        self.isInitialized = true
        return true
    end

    -- Try 2: Via g_gui.screenControllers[InGameMenu]
    if g_gui and g_gui.screenControllers and InGameMenu then
        local inGameMenu = g_gui.screenControllers[InGameMenu]
        if inGameMenu and inGameMenu.pageVehicles and inGameMenu.pageVehicles.onClickSell then
            local frame = inGameMenu.pageVehicles
            self.originalOnClickSell = frame.onClickSell

            frame.onClickSell = function(self)
                if g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                    InGameMenuVehiclesFrameExtension:onClickSellOverride(self)
                elseif InGameMenuVehiclesFrameExtension.originalOnClickSell then
                    InGameMenuVehiclesFrameExtension.originalOnClickSell(self)
                end
            end

            self.isInitialized = true
            UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onClickSell via g_gui.screenControllers")
            return true
        end
    end

    -- Try 3: Via g_inGameMenu global
    if g_inGameMenu and g_inGameMenu.pageVehicles and g_inGameMenu.pageVehicles.onClickSell then
        local frame = g_inGameMenu.pageVehicles
        self.originalOnClickSell = frame.onClickSell

        frame.onClickSell = function(self)
            if g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                InGameMenuVehiclesFrameExtension:onClickSellOverride(self)
            elseif InGameMenuVehiclesFrameExtension.originalOnClickSell then
                InGameMenuVehiclesFrameExtension.originalOnClickSell(self)
            end
        end

        self.isInitialized = true
        UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onClickSell via g_inGameMenu")
        return true
    end

    UsedPlus.logWarn("InGameMenuVehiclesFrame not found, cannot hook sell button (will retry on menu open)")
    return false
end

--[[
    Override for sell button click
    Shows our SellVehicleDialog instead of vanilla confirmation
    @param frame - The InGameMenuVehiclesFrame instance
]]
function InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
    -- Get selected vehicle
    local vehicle = frame:getSelectedVehicle()
    if vehicle == nil then
        UsedPlus.logDebug("No vehicle selected for sale")
        return
    end

    -- Get farm ID
    local farmId = g_currentMission:getFarmId()

    -- Check ownership
    if vehicle.ownerFarmId ~= farmId then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "You do not own this vehicle."
        )
        return
    end

    -- Check if vehicle is owned (not leased via vanilla system)
    if vehicle.propertyState ~= VehiclePropertyState.OWNED then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Leased vehicles cannot be sold. Terminate the lease first."
        )
        return
    end

    -- Check if vehicle is leased via UsedPlus lease system
    if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            g_i18n:getText("usedplus_error_cannotSellLeasedVehicle")
        )
        return
    end

    -- Check if vehicle is financed
    if TradeInCalculations and TradeInCalculations.isVehicleFinanced then
        if TradeInCalculations.isVehicleFinanced(vehicle, farmId) then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                "Financed vehicles cannot be sold until loan is paid off."
            )
            return
        end
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
            return
        end
    end

    -- Check if already listed for sale
    if g_vehicleSaleManager and g_vehicleSaleManager:isVehicleListed(vehicle) then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "This vehicle is already listed for sale."
        )
        return
    end

    -- Show our custom sell dialog
    self:showSellDialog(vehicle, farmId, frame)
end

--[[
    Show the SellVehicleDialog
    Refactored to use DialogLoader for centralized loading
    @param vehicle - The vehicle to sell
    @param farmId - The owning farm
    @param frame - The vehicles frame (to refresh after)
]]
function InGameMenuVehiclesFrameExtension:showSellDialog(vehicle, farmId, frame)
    -- Use DialogLoader with callback
    -- Callback receives BOTH agentTier and priceTier from dual-tier system
    local callback = function(agentTier, priceTier)
        if agentTier ~= nil then
            -- Player selected tiers - create listing
            self:createSaleListing(vehicle, farmId, agentTier, priceTier, frame)
        else
            -- Player cancelled
            UsedPlus.logDebug("Sale dialog cancelled")
        end
    end

    DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)
end

--[[
    Create a sale listing through the VehicleSaleManager
    @param vehicle - The vehicle to sell
    @param farmId - The owning farm
    @param agentTier - Selected agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Selected price tier (1=Quick, 2=Market, 3=Premium)
    @param frame - The vehicles frame (to refresh)
]]
function InGameMenuVehiclesFrameExtension:createSaleListing(vehicle, farmId, agentTier, priceTier, frame)
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("VehicleSaleManager not initialized")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Sale system error. Please try again."
        )
        return
    end

    -- Default priceTier if not provided (legacy compatibility)
    priceTier = priceTier or 2

    -- Create listing through manager (passes agent tier, priceTier is stored in listing)
    local listing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier)

    if listing then
        UsedPlus.logDebug(string.format("Created sale listing: %s (Agent %d, Price %d, ID: %s)",
            listing.vehicleName, agentTier, priceTier, listing.id))

        -- Show styled confirmation dialog
        self:showSaleListingConfirmation(vehicle, agentTier, priceTier)
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Failed to create sale listing. Please try again."
        )
    end
end

--[[
    Show the SaleListingInitiatedDialog with listing details
    @param vehicle - The vehicle being sold
    @param agentTier - Agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Price tier (1=Quick, 2=Market, 3=Premium)
]]
function InGameMenuVehiclesFrameExtension:showSaleListingConfirmation(vehicle, agentTier, priceTier)
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
    Get maintenance status indicator for vehicle name display
    Returns nil if no indicator needed, or a string like "[NEEDS SERVICE]"
    Phase 5 feature
    @param vehicle - The vehicle to check
    @return string indicator or nil
]]
function InGameMenuVehiclesFrameExtension.getMaintenanceIndicator(vehicle)
    -- Check if UsedPlusMaintenance is available
    if UsedPlusMaintenance == nil or UsedPlusMaintenance.getReliabilityData == nil then
        return nil
    end

    local reliabilityData = UsedPlusMaintenance.getReliabilityData(vehicle)
    if reliabilityData == nil then
        return nil
    end

    -- Only show indicator for used-purchased vehicles
    if not reliabilityData.purchasedUsed then
        return nil
    end

    -- Check average reliability
    local avgRel = reliabilityData.avgReliability or 1.0

    -- Show different indicators based on condition
    if avgRel < 0.3 then
        return "[CRITICAL]"
    elseif avgRel < 0.5 then
        return "[NEEDS SERVICE]"
    elseif avgRel < 0.6 then
        return "[WORN]"
    end

    -- No indicator if reliability is acceptable
    return nil
end

--[[
    Get detailed maintenance info for tooltip or detail display
    Phase 5 feature
    @param vehicle - The vehicle to check
    @return table with formatted info or nil
]]
function InGameMenuVehiclesFrameExtension.getMaintenanceDetails(vehicle)
    if UsedPlusMaintenance == nil or UsedPlusMaintenance.getReliabilityData == nil then
        return nil
    end

    local data = UsedPlusMaintenance.getReliabilityData(vehicle)
    if data == nil then
        return nil
    end

    -- Get rating texts
    local engineRating, engineIcon = UsedPlusMaintenance.getRatingText(data.engineReliability)
    local hydraulicRating, hydraulicIcon = UsedPlusMaintenance.getRatingText(data.hydraulicReliability)
    local electricalRating, electricalIcon = UsedPlusMaintenance.getRatingText(data.electricalReliability)

    return {
        purchasedUsed = data.purchasedUsed,
        wasInspected = data.wasInspected,

        engineReliability = math.floor(data.engineReliability * 100),
        engineRating = engineRating,
        engineIcon = engineIcon,

        hydraulicReliability = math.floor(data.hydraulicReliability * 100),
        hydraulicRating = hydraulicRating,
        hydraulicIcon = hydraulicIcon,

        electricalReliability = math.floor(data.electricalReliability * 100),
        electricalRating = electricalRating,
        electricalIcon = electricalIcon,

        avgReliability = math.floor(data.avgReliability * 100),
        failureCount = data.failureCount,
        repairCount = data.repairCount,
    }
end

--[[
    Format maintenance details as multi-line string
    Useful for tooltips or info panels
    @param vehicle - The vehicle to check
    @return formatted string or nil
]]
function InGameMenuVehiclesFrameExtension.formatMaintenanceInfo(vehicle)
    local details = InGameMenuVehiclesFrameExtension.getMaintenanceDetails(vehicle)
    if details == nil or not details.purchasedUsed then
        return nil
    end

    local lines = {}
    table.insert(lines, "=== Maintenance History ===")
    table.insert(lines, string.format("Engine: %d%% %s", details.engineReliability, details.engineIcon))
    table.insert(lines, string.format("Hydraulics: %d%% %s", details.hydraulicReliability, details.hydraulicIcon))
    table.insert(lines, string.format("Electrical: %d%% %s", details.electricalReliability, details.electricalIcon))
    table.insert(lines, "")
    table.insert(lines, string.format("Breakdowns: %d", details.failureCount))
    table.insert(lines, string.format("Repairs: %d", details.repairCount))

    if details.wasInspected then
        table.insert(lines, "(Inspected before purchase)")
    end

    return table.concat(lines, "\n")
end

--[[
    Get the selected vehicle from the frame
    Helper method that handles different ways to get selected vehicle
    @param frame - The InGameMenuVehiclesFrame
    @return vehicle or nil
]]
function InGameMenuVehiclesFrameExtension.getSelectedVehicle(frame)
    -- Try different methods to get selected vehicle
    if frame.selectedVehicle then
        return frame.selectedVehicle
    end

    if frame.getSelectedVehicle then
        return frame:getSelectedVehicle()
    end

    -- Try getting from list selection
    if frame.vehicleList and frame.vehicleList.selectedIndex then
        local index = frame.vehicleList.selectedIndex
        if frame.vehicles and frame.vehicles[index] then
            return frame.vehicles[index]
        end
    end

    return nil
end

--[[
    Show maintenance report for a vehicle
    Can be called from anywhere with a vehicle reference
    @param vehicle - The vehicle to show maintenance for
]]
function InGameMenuVehiclesFrameExtension.showMaintenanceReport(vehicle)
    if vehicle == nil then
        UsedPlus.logDebug("showMaintenanceReport: No vehicle provided")
        return false
    end

    -- Check if MaintenanceReportDialog is available
    if MaintenanceReportDialog == nil then
        UsedPlus.logWarn("MaintenanceReportDialog not loaded")
        -- Fallback: show info as a simple message
        local info = InGameMenuVehiclesFrameExtension.formatMaintenanceInfo(vehicle)
        if info then
            InfoDialog.show(info)
        else
            InfoDialog.show("No maintenance data available for this vehicle.")
        end
        return true
    end

    -- Show the maintenance report dialog
    local dialog = MaintenanceReportDialog.getInstance()
    dialog:show(vehicle)
    return true
end

--[[
    Show maintenance report for currently selected vehicle in vehicles frame
    Used by keybind or button
    @param frame - The InGameMenuVehiclesFrame (optional, will try to find)
]]
function InGameMenuVehiclesFrameExtension.showMaintenanceReportForSelected(frame)
    -- Try to get the frame if not provided
    if frame == nil then
        if g_gui and g_gui.currentGui and g_gui.currentGui.target then
            frame = g_gui.currentGui.target
        end
    end

    local vehicle = InGameMenuVehiclesFrameExtension.getSelectedVehicle(frame)
    if vehicle then
        InGameMenuVehiclesFrameExtension.showMaintenanceReport(vehicle)
    else
        UsedPlus.logDebug("showMaintenanceReportForSelected: No vehicle selected")
        g_currentMission:showBlinkingWarning("No vehicle selected", 2000)
    end
end

--[[
    Restore original sell behavior
    Called on mod unload
]]
function InGameMenuVehiclesFrameExtension:restore()
    if self.originalOnClickSell and InGameMenuVehiclesFrame then
        InGameMenuVehiclesFrame.onClickSell = self.originalOnClickSell
        UsedPlus.logDebug("Restored original InGameMenuVehiclesFrame.onClickSell")
    end

    if self.originalGetDisplayName and Vehicle then
        Vehicle.getName = self.originalGetDisplayName
        UsedPlus.logDebug("Restored original Vehicle.getName")
    end

    if self.originalYesNoDialogShow and YesNoDialog then
        YesNoDialog.show = self.originalYesNoDialogShow
        UsedPlus.logDebug("Restored original YesNoDialog.show")
    end

    -- Note: Utils.appendedFunction hooks cannot be cleanly restored
    -- The menuButtonsHooked flag prevents re-hooking

    self.isInitialized = false
    self.menuButtonsHooked = false
end

-- Track if we've hooked InGameMenu.onOpen
InGameMenuVehiclesFrameExtension.inGameMenuHooked = false

--[[
    Try to install the hook dynamically when InGameMenu opens
    This catches the frame after it's actually created
]]
function InGameMenuVehiclesFrameExtension.onInGameMenuOpen(inGameMenu, superFunc)
    -- Call original first
    if superFunc then
        superFunc(inGameMenu)
    end

    -- Try to install our hook if not already done
    if not InGameMenuVehiclesFrameExtension.isInitialized then
        -- Check if InGameMenuVehiclesFrame now exists
        if InGameMenuVehiclesFrame and InGameMenuVehiclesFrame.onClickSell then
            InGameMenuVehiclesFrameExtension:hookSellButton()
            InGameMenuVehiclesFrameExtension:hookVehicleDisplayName()
            InGameMenuVehiclesFrameExtension:hookMenuButtons()
        else
            -- Try to find it via the inGameMenu's pages
            if inGameMenu and inGameMenu.pageVehicles and inGameMenu.pageVehicles.onClickSell then
                -- The frame exists as a page - hook it directly
                local frame = inGameMenu.pageVehicles
                if not InGameMenuVehiclesFrameExtension.originalOnClickSell then
                    InGameMenuVehiclesFrameExtension.originalOnClickSell = frame.onClickSell

                    frame.onClickSell = function(self)
                        if g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
                            InGameMenuVehiclesFrameExtension:onClickSellOverride(self)
                        elseif InGameMenuVehiclesFrameExtension.originalOnClickSell then
                            InGameMenuVehiclesFrameExtension.originalOnClickSell(self)
                        end
                    end

                    InGameMenuVehiclesFrameExtension.isInitialized = true
                    UsedPlus.logInfo("Hooked InGameMenuVehiclesFrame.onClickSell via InGameMenu.pageVehicles")
                end
            end
        end
    end
end

-- Try to install hook at load time
-- This runs at script load time, but InGameMenuVehiclesFrame may not exist yet
-- The init() function will also try to install the hook after mission loads
if InGameMenuVehiclesFrame and InGameMenuVehiclesFrame.onClickSell then
    InGameMenuVehiclesFrameExtension.originalOnClickSell = InGameMenuVehiclesFrame.onClickSell

    InGameMenuVehiclesFrame.onClickSell = function(frame)
        -- Only use our override if manager is ready
        if g_vehicleSaleManager and UsedPlus and UsedPlus.instance then
            InGameMenuVehiclesFrameExtension:onClickSellOverride(frame)
        elseif InGameMenuVehiclesFrameExtension.originalOnClickSell then
            -- Fall back to original if not initialized
            InGameMenuVehiclesFrameExtension.originalOnClickSell(frame)
        end
    end

    InGameMenuVehiclesFrameExtension.isInitialized = true
    UsedPlus.logDebug("InGameMenuVehiclesFrameExtension: Sell button hook installed at load time")
else
    UsedPlus.logDebug("InGameMenuVehiclesFrameExtension: Hook will be installed after mission loads or menu opens")

    -- Hook InGameMenu.onOpen to install hooks when menu first opens
    if InGameMenu and InGameMenu.onOpen then
        InGameMenu.onOpen = Utils.overwrittenFunction(
            InGameMenu.onOpen,
            InGameMenuVehiclesFrameExtension.onInGameMenuOpen
        )
        InGameMenuVehiclesFrameExtension.inGameMenuHooked = true
        UsedPlus.logDebug("InGameMenuVehiclesFrameExtension: InGameMenu.onOpen hooked")
    end
end

UsedPlus.logInfo("InGameMenuVehiclesFrameExtension loaded")
