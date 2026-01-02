--[[
    FS25_UsedPlus - Shop Config Screen Extension

    Extends game's shop screen with Unified Purchase Dialog
    Single "Buy Options" button opens unified dialog for Cash/Finance/Lease
    Pattern from: BuyUsedEquipment (working reference mod)
    Uses button cloning and setStoreItem hook

    Also adds "Inspect" button for owned vehicles to view maintenance/reliability data
]]

ShopConfigScreenExtension = {}

-- Dialog loading now handled by DialogLoader utility

-- Store current item for shop hooks
ShopConfigScreenExtension.currentStoreItem = nil
ShopConfigScreenExtension.currentShopScreen = nil
ShopConfigScreenExtension.currentVehicle = nil  -- Set when viewing owned vehicle

--[[
    Hook callback for shop item selection
    This hook fires every time player selects/views an item in shop
    NEW: Intercepts Buy and Lease buttons to open UnifiedPurchaseDialog
]]
function ShopConfigScreenExtension.setStoreItemHook(self, superFunc, storeItem, ...)
    UsedPlus.logDebug(string.format("ShopConfigScreenExtension.setStoreItemHook called - storeItem: %s",
        tostring(storeItem and storeItem.name or "nil")))

    -- Call original function first and capture return value
    local result = superFunc(self, storeItem, ...)

    -- Wrap our customizations in pcall to prevent breaking the shop if something errors
    local success, err = pcall(function()
        ShopConfigScreenExtension.applyCustomizations(self, storeItem)
    end)

    if not success then
        UsedPlus.logError("ShopConfigScreenExtension error: " .. tostring(err))
    end

    -- Return original function's result to maintain shop flow
    UsedPlus.logDebug("ShopConfigScreenExtension.setStoreItemHook completed successfully")
    return result
end

--[[
    Apply our customizations (separated to allow pcall wrapping)
    v1.7.1: This now only handles button CREATION (Search Used, Inspect).
    Button callback overrides are handled in updateButtonsHook where we have vehicle context.
]]
function ShopConfigScreenExtension.applyCustomizations(self, storeItem)
    local buyButton = self.buyButton

    -- Store reference for any potential future use
    ShopConfigScreenExtension.currentStoreItem = storeItem
    ShopConfigScreenExtension.currentShopScreen = self

    -- v1.8.1: Check if HirePurchasing handles financing
    -- If HP is installed, skip Finance button creation (HP provides its own)
    local shouldShowFinance = ModCompatibility.shouldShowFinanceButton()

    -- Create Finance button (between Buy and Search Used)
    if shouldShowFinance and not self.usedPlusFinanceButton and buyButton then
        local parent = buyButton.parent
        self.usedPlusFinanceButton = buyButton:clone(parent)
        self.usedPlusFinanceButton.name = "usedPlusFinanceButton"
        self.usedPlusFinanceButton.inputActionName = "MENU_EXTRA_2"
        self.usedPlusFinanceButton:setText(g_i18n:getText("usedplus_button_finance") or "Finance")
        self.usedPlusFinanceButton:setVisible(false)  -- Hidden by default, shown for new items

        -- Position Finance button right after Buy in the array
        if parent and parent.elements then
            -- Find and remove from current position
            for i = #parent.elements, 1, -1 do
                if parent.elements[i] == self.usedPlusFinanceButton then
                    table.remove(parent.elements, i)
                    break
                end
            end

            -- Find Buy button position
            local buyIndex = nil
            for i, elem in ipairs(parent.elements) do
                if elem == buyButton then
                    buyIndex = i
                    break
                end
            end

            if buyIndex then
                -- Insert right after Buy (display: Buy | Finance)
                table.insert(parent.elements, buyIndex + 1, self.usedPlusFinanceButton)
                UsedPlus.logDebug(string.format("Inserted Finance at index %d (after Buy)", buyIndex + 1))
            end
        end

        UsedPlus.logDebug("Finance button created with inputActionName: MENU_EXTRA_2")
    elseif not shouldShowFinance then
        UsedPlus.logDebug("Finance button skipped - HirePurchasing detected")
    end

    -- v1.8.1: Check if BuyUsedEquipment handles used search
    -- If BUE is installed, skip Search Used button creation (BUE provides its own)
    local shouldShowSearch = ModCompatibility.shouldShowSearchButton()

    -- Create Search Used button (after Finance)
    if shouldShowSearch and not self.usedPlusSearchButton and buyButton then
        local parent = buyButton.parent

        -- Log what the Buy button uses for reference
        UsedPlus.logDebug(string.format("Buy button inputActionName: %s", tostring(buyButton.inputActionName)))

        self.usedPlusSearchButton = buyButton:clone(parent)
        self.usedPlusSearchButton.name = "usedPlusSearchButton"
        self.usedPlusSearchButton.inputActionName = "MENU_EXTRA_1"

        -- Position Search Used after Finance in the array
        if parent and parent.elements then
            -- Find and remove from current position
            for i = #parent.elements, 1, -1 do
                if parent.elements[i] == self.usedPlusSearchButton then
                    table.remove(parent.elements, i)
                    break
                end
            end

            -- Find Finance button position (or Buy if Finance doesn't exist)
            local insertAfter = self.usedPlusFinanceButton or buyButton
            local insertIndex = nil
            for i, elem in ipairs(parent.elements) do
                if elem == insertAfter then
                    insertIndex = i
                    break
                end
            end

            if insertIndex then
                -- Insert after Finance (display: Buy | Finance | Search Used)
                table.insert(parent.elements, insertIndex + 1, self.usedPlusSearchButton)
                UsedPlus.logDebug(string.format("Inserted Search Used at index %d (after Finance)", insertIndex + 1))
            else
                -- Fallback: add to end
                table.insert(parent.elements, self.usedPlusSearchButton)
                UsedPlus.logDebug("Added Search Used to end of elements")
            end
        end

        UsedPlus.logDebug("Search Used button created with inputActionName: MENU_EXTRA_1")
    elseif not shouldShowSearch then
        UsedPlus.logDebug("Search Used button skipped - BuyUsedEquipment detected")
    end

    -- Update Search Used callback EVERY TIME setStoreItem is called
    if self.usedPlusSearchButton then
        self.usedPlusSearchButton.onClickCallback = function()
            ShopConfigScreenExtension.onSearchClick(self, storeItem)
        end
        self.usedPlusSearchButton:setText(g_i18n:getText("usedplus_button_searchUsed"))
        local canSearch = ShopConfigScreenExtension.canSearchItem(storeItem)
        self.usedPlusSearchButton:setDisabled(not canSearch)
        self.usedPlusSearchButton:setVisible(canSearch)
    end

    -- Create Inspect button for owned vehicles (maintenance report)
    if not self.usedPlusInspectButton and buyButton then
        local parent = buyButton.parent
        self.usedPlusInspectButton = buyButton:clone(parent)
        self.usedPlusInspectButton.name = "usedPlusInspectButton"
        self.usedPlusInspectButton.inputActionName = "MENU_EXTRA_1"  -- Q key typically
        self.usedPlusInspectButton:setText(g_i18n:getText("usedplus_button_inspect") or "Inspect")
        self.usedPlusInspectButton:setVisible(false)  -- Hidden by default, shown for owned vehicles

        UsedPlus.logDebug("Inspect button created in shop")
    end

    -- Create Tires button for owned vehicles (tire replacement service)
    if not self.usedPlusTiresButton and buyButton then
        local parent = buyButton.parent
        self.usedPlusTiresButton = buyButton:clone(parent)
        self.usedPlusTiresButton.name = "usedPlusTiresButton"
        self.usedPlusTiresButton.inputActionName = "MENU_EXTRA_3"
        self.usedPlusTiresButton:setText(g_i18n:getText("usedplus_button_tires") or "Tires")
        self.usedPlusTiresButton:setVisible(false)  -- Hidden by default, shown for owned vehicles

        UsedPlus.logDebug("Tires button created in shop")
    end

    -- NOTE: Fluids button removed in v1.8.0 - Players now use Oil Service Barrel/Tank placeables
    -- to refill engine oil and hydraulic fluid by driving near them
end

--[[
    Install hooks at load time with safety check
    ShopConfigScreen should exist when mods load
]]
if ShopConfigScreen ~= nil and ShopConfigScreen.setStoreItem ~= nil then
    ShopConfigScreen.setStoreItem = Utils.overwrittenFunction(
        ShopConfigScreen.setStoreItem,
        ShopConfigScreenExtension.setStoreItemHook
    )
    UsedPlus.logDebug("ShopConfigScreenExtension setStoreItem hook installed")
else
    UsedPlus.logWarn("ShopConfigScreen not available at load time")
end

--[[
    Hook updateButtons to show/hide Inspect button for owned vehicles
    updateButtons(storeItem, vehicle, saleItem) - vehicle is set when viewing owned vehicle

    v1.7.2: SIMPLE CALLBACK SWAP APPROACH
    For each update, we ACTIVELY SET the callback based on context:
    - Owned vehicle: Restore original callback (let game handle customization natively)
    - New item: Set our UnifiedPurchaseDialog callback
    This is cleaner than a wrapper because we explicitly control what happens.
]]
function ShopConfigScreenExtension.updateButtonsHook(self, storeItem, vehicle, saleItem)
    -- Wrap in pcall to prevent breaking the shop if something errors
    local success, err = pcall(function()
        -- Store current vehicle for inspect handler
        ShopConfigScreenExtension.currentVehicle = vehicle

        local isOwnedVehicle = vehicle ~= nil

        -- Store original callbacks ONCE (before we ever override)
        -- These are the VANILLA game callbacks we want to restore for owned vehicles
        if self.buyButton and not self.usedPlusOriginalBuyCallback then
            self.usedPlusOriginalBuyCallback = self.buyButton.onClickCallback
            self.usedPlusOriginalBuyOnClick = self.buyButton.onClick  -- String method name
            UsedPlus.logDebug("Stored original Buy button callback")
        end
        if self.leaseButton and not self.usedPlusOriginalLeaseCallback then
            self.usedPlusOriginalLeaseCallback = self.leaseButton.onClickCallback
            UsedPlus.logDebug("Stored original Lease button callback")
        end

        -- v1.7.2: ACTIVE CALLBACK SWAP (every update, not a one-time wrapper)
        if self.buyButton then
            if isOwnedVehicle then
                -- OWNED VEHICLE: Restore original game callback completely
                -- Don't touch it - let the game handle customization natively
                self.buyButton.onClickCallback = self.usedPlusOriginalBuyCallback
                UsedPlus.logDebug("Buy button: restored original callback for owned vehicle")
            else
                -- NEW ITEM: Set our UnifiedPurchaseDialog callback
                local shopScreen = self
                local currentStoreItem = storeItem
                self.buyButton.onClickCallback = function()
                    UsedPlus.logDebug("Buy button clicked - new item: " .. tostring(currentStoreItem and currentStoreItem.name or "nil"))
                    if currentStoreItem and ShopConfigScreenExtension.canFinanceItem(currentStoreItem) then
                        ShopConfigScreenExtension.onUnifiedBuyClick(shopScreen, currentStoreItem, UnifiedPurchaseDialog.MODE_CASH)
                    elseif shopScreen.usedPlusOriginalBuyCallback then
                        -- Fallback to original for non-financeable items
                        shopScreen.usedPlusOriginalBuyCallback()
                    end
                end
                UsedPlus.logDebug("Buy button: set UsedPlus callback for new item")
            end
        end

        -- v1.4.0: Check settings system for lease feature toggle
        if self.leaseButton then
            local leaseEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Lease")
            if isOwnedVehicle or not leaseEnabled then
                -- OWNED VEHICLE or LEASE DISABLED: Restore original game callback
                self.leaseButton.onClickCallback = self.usedPlusOriginalLeaseCallback
                UsedPlus.logDebug("Lease button: restored original callback for owned vehicle or disabled system")
            else
                -- NEW ITEM: Set our UnifiedPurchaseDialog callback
                local shopScreen = self
                local currentStoreItem = storeItem
                self.leaseButton.onClickCallback = function()
                    UsedPlus.logDebug("Lease button clicked - new item: " .. tostring(currentStoreItem and currentStoreItem.name or "nil"))
                    if currentStoreItem and ShopConfigScreenExtension.canLeaseItem(currentStoreItem) then
                        ShopConfigScreenExtension.onUnifiedBuyClick(shopScreen, currentStoreItem, UnifiedPurchaseDialog.MODE_LEASE)
                    elseif shopScreen.usedPlusOriginalLeaseCallback then
                        -- Fallback to original for non-leaseable items
                        shopScreen.usedPlusOriginalLeaseCallback()
                    end
                end
                UsedPlus.logDebug("Lease button: set UsedPlus callback for new item")
            end
        end

        -- Update Finance button visibility and callback (button created in applyCustomizations)
        -- v1.8.1: Also check if HirePurchasing handles financing
        -- v1.4.0: Check settings system for feature toggles
        if self.usedPlusFinanceButton then
            local financeEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
            local showFinanceButton = financeEnabled and
                                       ModCompatibility.shouldShowFinanceButton() and
                                       not isOwnedVehicle and
                                       ShopConfigScreenExtension.canFinanceItem(storeItem)
            self.usedPlusFinanceButton:setVisible(showFinanceButton)
            self.usedPlusFinanceButton:setDisabled(not showFinanceButton)

            if showFinanceButton then
                self.usedPlusFinanceButton.onClickCallback = function()
                    ShopConfigScreenExtension.onUnifiedBuyClick(self, storeItem, UnifiedPurchaseDialog.MODE_FINANCE)
                end
            end
        end

        -- Show/hide Inspect button based on whether this is an owned vehicle
        if self.usedPlusInspectButton then
            self.usedPlusInspectButton:setVisible(isOwnedVehicle)
            self.usedPlusInspectButton:setDisabled(not isOwnedVehicle)

            if isOwnedVehicle then
                self.usedPlusInspectButton.onClickCallback = function()
                    ShopConfigScreenExtension.onInspectClick(self, vehicle)
                end
            end
        end

        -- Show/hide Tires button for owned vehicles (tire service)
        -- v1.4.0: Check settings system for tire wear feature toggle
        if self.usedPlusTiresButton then
            local tireWearEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("TireWear")
            local showTiresButton = tireWearEnabled and isOwnedVehicle
            self.usedPlusTiresButton:setVisible(showTiresButton)
            self.usedPlusTiresButton:setDisabled(not showTiresButton)

            if showTiresButton then
                self.usedPlusTiresButton.onClickCallback = function()
                    ShopConfigScreenExtension.onTiresClick(self, vehicle)
                end
            end
        end

        -- NOTE: Fluids button removed in v1.8.0 - use Oil Service Barrel/Tank placeables

        if isOwnedVehicle then
            local vehicleName = vehicle.getName and vehicle:getName() or "Unknown"
            UsedPlus.logDebug("Service buttons shown for owned vehicle: " .. tostring(vehicleName))
        end

        -- Hide Search Used button for owned vehicles (can't search for something you own)
        -- v1.8.1: Also check if BuyUsedEquipment handles used search
        -- v1.4.0: Check settings system for used vehicle search feature toggle
        if self.usedPlusSearchButton then
            local searchEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("UsedVehicleSearch")
            local isNewItem = vehicle == nil and saleItem == nil
            local showSearchButton = searchEnabled and
                                      ModCompatibility.shouldShowSearchButton() and
                                      isNewItem and
                                      ShopConfigScreenExtension.canSearchItem(storeItem)
            self.usedPlusSearchButton:setVisible(showSearchButton)
        end
    end)

    if not success then
        UsedPlus.logError("ShopConfigScreenExtension updateButtons error: " .. tostring(err))
    end
end

if ShopConfigScreen ~= nil and ShopConfigScreen.updateButtons ~= nil then
    ShopConfigScreen.updateButtons = Utils.appendedFunction(
        ShopConfigScreen.updateButtons,
        ShopConfigScreenExtension.updateButtonsHook
    )
    UsedPlus.logDebug("ShopConfigScreenExtension updateButtons hook installed")
end

--[[
    Note on UnifiedPurchaseDialog approach
    We intercept both Buy and Lease buttons to open our UnifiedPurchaseDialog.
    This provides a unified experience with Cash/Finance/Lease modes in one dialog.
    Trade-In is integrated into the UnifiedPurchaseDialog for all purchase modes.
]]

--[[
    Item qualification functions
]]
function ShopConfigScreenExtension.canFinanceItem(storeItem)
    if storeItem == nil then
        return false
    end

    -- Can finance vehicles and placeables
    local isVehicle = storeItem.species == StoreSpecies.VEHICLE
    local isPlaceable = storeItem.categoryName == "PLACEABLES"

    if not (isVehicle or isPlaceable) then
        return false
    end

    -- v1.9.8: Exclude hand tools from financing (Field Service Kit, etc.)
    -- These are simple objects that should use vanilla buy dialog, not UnifiedPurchaseDialog
    -- Hand tools have financeCategory="SHOP_HANDTOOL_BUY" in their storeData
    if storeItem.financeCategory == "SHOP_HANDTOOL_BUY" then
        UsedPlus.logDebug("canFinanceItem: Excluding hand tool: " .. tostring(storeItem.name))
        return false
    end

    -- Check minimum financing amount
    -- Banks don't process loans for trivially small amounts
    local price = storeItem.price or 0
    if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
        local meetsMinimum, _ = FinanceCalculations.meetsMinimumAmount(price, "VEHICLE_FINANCE")
        if not meetsMinimum then
            return false
        end
    end

    return true
end

function ShopConfigScreenExtension.canSearchItem(storeItem)
    if storeItem == nil then
        return false
    end

    -- Can only search for vehicles (not hand tools)
    if storeItem.species ~= StoreSpecies.VEHICLE then
        return false
    end

    -- v1.9.8: Exclude hand tools from used search (Field Service Kit, etc.)
    if storeItem.financeCategory == "SHOP_HANDTOOL_BUY" then
        return false
    end

    return true
end

--[[
    Can this item be leased?
    Leasing is vehicles only (not land, not placeables, not hand tools)
    Also requires minimum value threshold
]]
function ShopConfigScreenExtension.canLeaseItem(storeItem)
    if storeItem == nil then
        return false
    end

    -- Can only lease vehicles (not placeables or land)
    if storeItem.species ~= StoreSpecies.VEHICLE then
        return false
    end

    -- v1.9.8: Exclude hand tools from leasing (Field Service Kit, etc.)
    if storeItem.financeCategory == "SHOP_HANDTOOL_BUY" then
        return false
    end

    -- Check minimum lease amount
    -- Leasing has higher administrative overhead than financing
    local price = storeItem.price or 0
    if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
        local meetsMinimum, _ = FinanceCalculations.meetsMinimumAmount(price, "VEHICLE_LEASE")
        if not meetsMinimum then
            return false
        end
    end

    return true
end

--[[
    Check if player has any vehicles to trade in
]]
function ShopConfigScreenExtension.canTradeInForItem(storeItem)
    if storeItem == nil then
        return false
    end

    -- Can only trade in for vehicle purchases
    if storeItem.species ~= StoreSpecies.VEHICLE then
        return false
    end

    -- Check if player has any eligible vehicles
    if TradeInCalculations then
        local farmId = g_currentMission:getFarmId()
        local eligible = TradeInCalculations.getEligibleVehicles(farmId)
        return #eligible > 0
    end

    return false
end

--[[
    Get current configurations from shop screen
    Returns table of configName -> selectedIndex
]]
function ShopConfigScreenExtension.getCurrentConfigurations(shopScreen)
    local configurations = {}

    -- Try multiple methods to get configurations
    -- Method 1: shopScreen.configurations (direct property)
    if shopScreen and shopScreen.configurations and type(shopScreen.configurations) == "table" then
        for configKey, selectedIndex in pairs(shopScreen.configurations) do
            if type(selectedIndex) == "number" then
                configurations[configKey] = selectedIndex
            end
        end
        if next(configurations) then
            UsedPlus.logTrace("Got configurations from shopScreen.configurations")
        end
    end

    -- Method 2: g_shopConfigScreen.configurations (global)
    if not next(configurations) and g_shopConfigScreen and g_shopConfigScreen.configurations and type(g_shopConfigScreen.configurations) == "table" then
        for configKey, selectedIndex in pairs(g_shopConfigScreen.configurations) do
            if type(selectedIndex) == "number" then
                configurations[configKey] = selectedIndex
            end
        end
        if next(configurations) then
            UsedPlus.logTrace("Got configurations from g_shopConfigScreen.configurations")
        end
    end

    -- Method 3: Try configurationItems array (UI elements)
    if not next(configurations) then
        local configScreen = shopScreen or g_shopConfigScreen
        if configScreen and configScreen.configurationItems then
            for _, item in pairs(configScreen.configurationItems) do
                if item.name and item.state then
                    configurations[item.name] = item.state
                elseif item.name and item.currentIndex then
                    configurations[item.name] = item.currentIndex
                end
            end
            if next(configurations) then
                UsedPlus.logTrace("Got configurations from configurationItems")
            end
        end
    end

    -- Debug log configurations
    local count = 0
    for k, v in pairs(configurations) do
        UsedPlus.logTrace(string.format("  Config: %s = %s", tostring(k), tostring(v)))
        count = count + 1
    end
    UsedPlus.logDebug(string.format("Total configurations captured: %d", count))

    return configurations
end

--[[
    Unified Buy click handler
    Refactored to use DialogLoader for centralized loading
]]
function ShopConfigScreenExtension.onUnifiedBuyClick(shopScreen, storeItem, initialMode)
    UsedPlus.logDebug("Unified Buy clicked for: " .. tostring(storeItem.name) .. " mode: " .. tostring(initialMode))

    g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)

    -- Use DialogLoader for lazy loading (need to call two methods)
    if not DialogLoader.ensureLoaded("UnifiedPurchaseDialog") then
        return
    end

    local dialog = DialogLoader.getDialog("UnifiedPurchaseDialog")
    if dialog then
        -- Get the configured price for the item
        local price = storeItem.price or 0
        if shopScreen and shopScreen.totalPrice then
            price = shopScreen.totalPrice
        end

        dialog:setVehicleData(storeItem, price, nil)
        dialog:setInitialMode(initialMode or UnifiedPurchaseDialog.MODE_CASH)
        g_gui:showDialog("UnifiedPurchaseDialog")
    end
end

--[[
    Search Used click handler
    Refactored to use DialogLoader for centralized loading
]]
function ShopConfigScreenExtension.onSearchClick(shopScreen, storeItem)
    UsedPlus.logDebug("Search Used button clicked for: " .. tostring(storeItem.name))

    g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)

    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("UsedSearchDialog", "setData", storeItem, storeItem.xmlFilename, farmId)
end

--[[
    Inspect button click handler
    Shows MaintenanceReportDialog for the owned vehicle
]]
function ShopConfigScreenExtension.onInspectClick(shopScreen, vehicle)
    if vehicle == nil then
        UsedPlus.logDebug("Inspect clicked but no vehicle")
        return
    end

    UsedPlus.logDebug("Inspect button clicked for: " .. tostring(vehicle:getName()))

    g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)

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

    InfoDialog.show(info)
end

--[[
    Tires button click handler
    Shows TiresDialog for tire replacement service
]]
function ShopConfigScreenExtension.onTiresClick(shopScreen, vehicle)
    if vehicle == nil then
        UsedPlus.logDebug("Tires clicked but no vehicle")
        return
    end

    UsedPlus.logDebug("Tires button clicked for: " .. tostring(vehicle:getName()))

    g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)

    -- Use DialogLoader for centralized lazy loading
    local farmId = g_currentMission:getFarmId()
    DialogLoader.show("TiresDialog", "setVehicle", vehicle, farmId)
end

-- NOTE: onFluidsClick removed in v1.8.0 - use Oil Service Barrel/Tank placeables

UsedPlus.logInfo("ShopConfigScreenExtension loaded")
