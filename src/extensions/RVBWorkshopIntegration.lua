--[[
    FS25_UsedPlus - RVB Workshop Integration

    When Real Vehicle Breakdowns (RVB) is installed, this extension:
    1. Hides our Inspect button (RVB has their own Workshop button)
    2. Injects UsedPlus data into RVB's Workshop Dialog settingsBox
    3. Adds our unique data (Hydraulics, Maintenance Grade) alongside RVB's info
    4. Adds a Repaint button to RVB's dialog (alongside Repair)
    5. Shows Mechanic's Assessment quote (workhorse/lemon hint)
    6. v2.2.0: Hooks RVB repair/service completion for DNA degradation
    7. v2.2.0: Monitors RVB faults for breakdown degradation

    The integration is seamless - our data appears in the same visual style
    as RVB's existing vehicle info rows.

    v2.1.1 - Fixed timing issue: Hook installed on first dialog open (not mission load)
             The rvbWorkshopDialog class doesn't exist until first opened by player
    v2.1.2 - Added Repaint button to RVB's Workshop dialog
    v2.3.1 - Added Mechanic's Assessment using workhorse/lemon quote system
    v2.2.0 - Progressive degradation: DNA affects RVB part lifetimes
             - Hooks RVB service/repair completion for repair degradation
             - Monitors RVB fault states for breakdown degradation
]]

RVBWorkshopIntegration = {}
RVBWorkshopIntegration.isInitialized = false
RVBWorkshopIntegration.isHooked = false
RVBWorkshopIntegration.showDialogHooked = false
RVBWorkshopIntegration.repaintButtonAdded = false

-- v2.2.0: Track previous fault states for breakdown detection
RVBWorkshopIntegration.previousFaultStates = {}  -- { [vehicle] = { [partKey] = faultState, ... } }
RVBWorkshopIntegration.serviceHooked = false

--[[
    Initialize the integration
    Called from main.lua after ModCompatibility.init()

    NOTE: We can't hook rvbWorkshopDialog.updateScreen here because the class
    doesn't exist yet! RVB creates it lazily on first open. Instead, we hook
    showDialog to catch when it's first opened and install our hook then.
]]
function RVBWorkshopIntegration:init()
    if self.isInitialized then
        UsedPlus.logDebug("RVBWorkshopIntegration already initialized")
        return
    end

    -- Only initialize if RVB is installed
    if not ModCompatibility or not ModCompatibility.rvbInstalled then
        UsedPlus.logDebug("RVBWorkshopIntegration: RVB not installed, skipping")
        return
    end

    -- Hook showDialog to catch when rvbWorkshopDialog is first opened
    self:hookShowDialog()

    self.isInitialized = true
    UsedPlus.logInfo("RVBWorkshopIntegration initialized - waiting for RVB Workshop to open")
end

--[[
    Hook g_gui.showDialog to detect when rvbWorkshopDialog is opened
    This is where we'll install our updateScreen hook
]]
function RVBWorkshopIntegration:hookShowDialog()
    if self.showDialogHooked then
        return
    end

    -- Store original showDialog function
    local originalShowDialog = g_gui.showDialog

    if originalShowDialog == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: g_gui.showDialog not found")
        return
    end

    -- Replace with hooked version
    g_gui.showDialog = function(guiSelf, name, ...)
        -- Call original first
        local result = originalShowDialog(guiSelf, name, ...)

        -- Check if this is the RVB Workshop dialog being opened
        if name == "rvbWorkshopDialog" then
            UsedPlus.logDebug("RVBWorkshopIntegration: rvbWorkshopDialog opened")

            -- Try to install our hook on the dialog class (only once)
            if not RVBWorkshopIntegration.isHooked then
                RVBWorkshopIntegration:tryHookUpdateScreen()
            end
        end

        return result
    end

    self.showDialogHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked g_gui.showDialog for RVB detection")
end

--[[
    Try to hook rvbWorkshopDialog:updateScreen
    Called when the dialog is first opened (class now exists)
]]
function RVBWorkshopIntegration:tryHookUpdateScreen()
    if self.isHooked then
        return true
    end

    -- Method 1: Try global class (older RVB versions)
    local dialogClass = rvbWorkshopDialog

    -- Method 2: Try to get from g_gui.guis (dialog instance)
    if dialogClass == nil and g_gui and g_gui.guis then
        local guiEntry = g_gui.guis.rvbWorkshopDialog
        if guiEntry then
            -- The target contains the actual dialog controller
            dialogClass = guiEntry.target
            UsedPlus.logDebug("RVBWorkshopIntegration: Found dialog via g_gui.guis.rvbWorkshopDialog.target")
        end
    end

    -- Method 3: Try _G global table
    if dialogClass == nil and _G then
        dialogClass = _G.rvbWorkshopDialog
        if dialogClass then
            UsedPlus.logDebug("RVBWorkshopIntegration: Found dialog via _G.rvbWorkshopDialog")
        end
    end

    if dialogClass == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: rvbWorkshopDialog class still not found")
        -- Try to log what IS in g_gui.guis for debugging
        if g_gui and g_gui.guis and g_gui.guis.rvbWorkshopDialog then
            local entry = g_gui.guis.rvbWorkshopDialog
            UsedPlus.logDebug(string.format("RVBWorkshopIntegration: g_gui.guis.rvbWorkshopDialog exists, type=%s", type(entry)))
            if type(entry) == "table" then
                for k, v in pairs(entry) do
                    UsedPlus.logDebug(string.format("  .%s = %s", tostring(k), type(v)))
                end
            end
        end
        return false
    end

    -- Get the updateScreen function - could be on the class or metatable
    local originalUpdateScreen = dialogClass.updateScreen

    -- Try metatable if not found directly
    if originalUpdateScreen == nil then
        local mt = getmetatable(dialogClass)
        if mt and mt.__index then
            originalUpdateScreen = mt.__index.updateScreen
            UsedPlus.logDebug("RVBWorkshopIntegration: Found updateScreen in metatable")
        end
    end

    if originalUpdateScreen == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: rvbWorkshopDialog.updateScreen not found")
        -- Log available methods for debugging
        UsedPlus.logDebug("RVBWorkshopIntegration: Available methods on dialogClass:")
        for k, v in pairs(dialogClass) do
            if type(v) == "function" then
                UsedPlus.logDebug(string.format("  %s()", tostring(k)))
            end
        end
        return false
    end

    -- Replace with hooked version
    dialogClass.updateScreen = function(dialogSelf)
        -- Call original first (this populates RVB's data)
        local result = originalUpdateScreen(dialogSelf)

        -- Then inject our data at the end
        RVBWorkshopIntegration:injectUsedPlusData(dialogSelf)

        -- Hook RVB's native Repair button to use our partial repair dialog
        RVBWorkshopIntegration:hookRepairButton(dialogSelf)

        -- v2.2.0: Hook Service button for degradation tracking
        RVBWorkshopIntegration:hookServiceButton(dialogSelf)

        -- v2.2.0: Initialize fault tracking for this vehicle
        if dialogSelf.vehicle then
            RVBWorkshopIntegration:initializeFaultTracking(dialogSelf.vehicle)
        end

        -- Add Repaint and Tires buttons if not already added
        RVBWorkshopIntegration:injectRepaintButton(dialogSelf)
        RVBWorkshopIntegration:injectTiresButton(dialogSelf)

        return result
    end

    self.isHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Successfully hooked rvbWorkshopDialog.updateScreen!")

    -- IMPORTANT: The dialog is already open when we hook, so updateScreen was already called.
    -- We need to inject our data/button NOW for the current dialog instance.
    UsedPlus.logDebug("RVBWorkshopIntegration: Injecting into already-open dialog...")
    RVBWorkshopIntegration:injectUsedPlusData(dialogClass)
    RVBWorkshopIntegration:hookRepairButton(dialogClass)
    RVBWorkshopIntegration:hookServiceButton(dialogClass)
    if dialogClass.vehicle then
        RVBWorkshopIntegration:initializeFaultTracking(dialogClass.vehicle)
    end
    RVBWorkshopIntegration:injectRepaintButton(dialogClass)
    RVBWorkshopIntegration:injectTiresButton(dialogClass)

    return true
end

--[[
    Hook RVB's native Repair button to redirect to our partial repair dialog
    Uses RVB's calculated repair cost
]]
function RVBWorkshopIntegration:hookRepairButton(dialog)
    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusRepairHooked then
        return
    end

    -- Find RVB's repair button
    local repairButton = dialog.repairButton
    if repairButton == nil then
        -- Try to find by iterating elements
        local buttonsBox = dialog.buttonsBox
        if buttonsBox and buttonsBox.elements then
            for _, element in ipairs(buttonsBox.elements) do
                if element.id == "repairButton" or element.name == "repairButton" then
                    repairButton = element
                    break
                end
            end
        end
    end

    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find repair button to hook")
        return
    end

    -- Store original callback for potential fallback
    local originalCallback = repairButton.onClickCallback

    -- Replace with our callback
    repairButton.onClickCallback = function()
        RVBWorkshopIntegration:onRVBRepairButtonClick(dialog)
    end

    dialog.usedPlusRepairHooked = true
    UsedPlus.logDebug("RVBWorkshopIntegration: Hooked RVB repair button")
end

--[[
    Handle RVB's Repair button click
    Shows our RepairDialog in MODE_REPAIR with RVB's calculated cost
]]
function RVBWorkshopIntegration:onRVBRepairButtonClick(dialog)
    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for repair")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: RVB Repair clicked for %s", vehicle:getName()))

    -- Get RVB's calculated repair cost from the dialog if available
    local rvbRepairCost = nil
    if dialog.repairCost then
        rvbRepairCost = dialog.repairCost
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Using RVB repair cost: %d", rvbRepairCost))
    end

    -- Play click sound
    if g_soundPlayer then
        g_soundPlayer:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end

    -- Close RVB dialog first
    if dialog.close then
        dialog:close()
    elseif g_gui.closeDialog then
        g_gui:closeDialog()
    end

    -- Show our RepairDialog in REPAIR mode
    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.show then
        -- Pass RVB cost as optional 4th parameter
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, RepairDialog.MODE_REPAIR, rvbRepairCost)
    else
        -- Fallback: direct dialog creation
        if VehicleSellingPointExtension and VehicleSellingPointExtension.showRepairDialog then
            VehicleSellingPointExtension.showRepairDialog(vehicle, RepairDialog.MODE_REPAIR)
        end
    end
end

--[[
    Inject a Repaint button into RVB's Workshop dialog
    Clones the Repair button and places it after Repair, before Back
]]
function RVBWorkshopIntegration:injectRepaintButton(dialog)
    UsedPlus.logDebug("RVBWorkshopIntegration:injectRepaintButton called")

    if dialog == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: dialog is nil")
        return
    end

    -- Only add once per dialog instance
    if dialog.usedPlusRepaintButton then
        -- Button exists, just update its state
        UsedPlus.logDebug("RVBWorkshopIntegration: Repaint button already exists, updating state")
        self:updateRepaintButtonState(dialog)
        return
    end

    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: buttonsBox not found, listing dialog properties:")
        for k, v in pairs(dialog) do
            if type(v) == "table" then
                UsedPlus.logDebug(string.format("  dialog.%s = table", tostring(k)))
            end
        end
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Found buttonsBox with %d elements",
        buttonsBox.elements and #buttonsBox.elements or 0))

    -- Find the repair button to clone
    local repairButton = dialog.repairButton
    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: dialog.repairButton not found, searching buttonsBox.elements...")
        -- Try to find by iterating elements
        for i, element in ipairs(buttonsBox.elements or {}) do
            local elemId = element.id or element.name or "unknown"
            UsedPlus.logDebug(string.format("  buttonsBox.elements[%d]: id=%s, name=%s",
                i, tostring(element.id), tostring(element.name)))
            if element.id == "repairButton" or element.name == "repairButton" then
                repairButton = element
                UsedPlus.logDebug("RVBWorkshopIntegration: Found repairButton in elements!")
                break
            end
        end
    end

    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find repair button to clone")
        return
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: Found repairButton, attempting to clone...")

    -- Clone the repair button
    local success, repaintButton = pcall(function()
        return repairButton:clone(buttonsBox)
    end)

    if not success then
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Clone failed with error: %s", tostring(repaintButton)))
        return
    end

    if repaintButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Clone returned nil")
        return
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: Successfully cloned button!")

    -- Configure the repaint button
    repaintButton.id = "usedPlusRepaintButton"
    repaintButton.name = "usedPlusRepaintButton"
    repaintButton:setText(g_i18n:getText("usedplus_button_repaint") or "Repaint")

    -- Set click callback
    repaintButton.onClickCallback = function()
        RVBWorkshopIntegration:onRepaintButtonClick(dialog)
    end

    -- Also try setting via target pattern (RVB uses this)
    repaintButton.target = RVBWorkshopIntegration
    repaintButton.onClickCallbackFunction = "onRepaintButtonClick"

    -- Store reference
    dialog.usedPlusRepaintButton = repaintButton

    -- Add a separator before the repaint button (for visual consistency)
    -- Find separator template from buttonsBox
    local separatorTemplate = nil
    for _, element in ipairs(buttonsBox.elements or {}) do
        if element.profile and string.find(element.profile, "Separator") then
            separatorTemplate = element
            break
        end
    end

    if separatorTemplate then
        local separator = separatorTemplate:clone(buttonsBox)
        if separator then
            dialog.usedPlusRepaintSeparator = separator
        end
    end

    -- Reorder elements to place Repaint after Repair, before Back
    -- The buttonsBox has: Reset, sep, Battery, sep, Inspect, sep, Service, sep, Repair, sep, Back
    -- We want: Reset, sep, Battery, sep, Inspect, sep, Service, sep, Repair, sep, Repaint, sep, Back
    self:reorderRepaintButton(dialog)

    -- Update button state based on vehicle
    self:updateRepaintButtonState(dialog)

    -- Refresh the layout
    if buttonsBox.invalidateLayout then
        buttonsBox:invalidateLayout()
    end

    UsedPlus.logInfo("RVBWorkshopIntegration: Added Repaint button to RVB Workshop dialog")
end

--[[
    Reorder elements so Repaint button is after Repair but before Back
]]
function RVBWorkshopIntegration:reorderRepaintButton(dialog)
    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil or buttonsBox.elements == nil then
        return
    end

    local repaintButton = dialog.usedPlusRepaintButton
    local repaintSeparator = dialog.usedPlusRepaintSeparator
    local okButton = dialog.okButton  -- Back button has id="okButton"

    if repaintButton == nil then
        return
    end

    -- Find indices
    local repaintIdx = nil
    local separatorIdx = nil
    local backIdx = nil

    for i, element in ipairs(buttonsBox.elements) do
        if element == repaintButton then
            repaintIdx = i
        elseif element == repaintSeparator then
            separatorIdx = i
        elseif element == okButton or element.id == "okButton" then
            backIdx = i
        end
    end

    -- If back button found, move repaint button and separator before it
    if backIdx and repaintIdx and repaintIdx > backIdx then
        -- Remove and reinsert at correct position
        table.remove(buttonsBox.elements, repaintIdx)
        if separatorIdx and separatorIdx > repaintIdx then
            separatorIdx = separatorIdx - 1
        end
        if separatorIdx then
            table.remove(buttonsBox.elements, separatorIdx)
        end

        -- Recalculate back index
        for i, element in ipairs(buttonsBox.elements) do
            if element == okButton or element.id == "okButton" then
                backIdx = i
                break
            end
        end

        -- Insert separator and button before back
        if repaintSeparator then
            table.insert(buttonsBox.elements, backIdx, repaintSeparator)
            backIdx = backIdx + 1
        end
        table.insert(buttonsBox.elements, backIdx, repaintButton)
    end
end

--[[
    Update the Repaint button state based on vehicle condition
]]
function RVBWorkshopIntegration:updateRepaintButtonState(dialog)
    local repaintButton = dialog.usedPlusRepaintButton
    if repaintButton == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        if repaintButton.setDisabled then
            repaintButton:setDisabled(true)
        end
        return
    end

    -- Get wear amount
    local wear = 0
    if vehicle.getWearTotalAmount then
        wear = vehicle:getWearTotalAmount() or 0
    end

    -- Calculate repaint cost (similar to RepairDialog logic)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000) or 10000

    local repaintCost = 0
    if Wearable and Wearable.calculateRepaintPrice then
        repaintCost = Wearable.calculateRepaintPrice(basePrice, wear) or 0
    else
        repaintCost = math.floor(basePrice * wear * 0.15)
    end

    -- Apply settings multiplier
    local paintMultiplier = UsedPlusSettings and UsedPlusSettings:get("paintCostMultiplier") or 1.0
    repaintCost = math.floor(repaintCost * paintMultiplier)

    -- Update button text with cost
    local buttonText = g_i18n:getText("usedplus_button_repaint") or "Repaint"
    if repaintCost > 0 then
        buttonText = string.format("%s (%s)", buttonText, g_i18n:formatMoney(repaintCost, 0, true, true))
    end
    repaintButton:setText(buttonText)

    -- Disable if no wear to fix
    local hasWear = wear > 0.01
    if repaintButton.setDisabled then
        repaintButton:setDisabled(not hasWear)
    end
end

--[[
    Handle Repaint button click
    Shows our RepairDialog in MODE_REPAINT
]]
function RVBWorkshopIntegration:onRepaintButtonClick(dialog)
    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for repaint")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Repaint clicked for %s", vehicle:getName()))

    -- Play click sound
    if g_soundPlayer then
        g_soundPlayer:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end

    -- Close RVB dialog first
    if dialog.close then
        dialog:close()
    elseif g_gui.closeDialog then
        g_gui:closeDialog()
    end

    -- Show our RepairDialog in REPAINT mode
    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.show then
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, RepairDialog.MODE_REPAINT)
    else
        -- Fallback: direct dialog creation
        if VehicleSellingPointExtension and VehicleSellingPointExtension.showRepairDialog then
            VehicleSellingPointExtension.showRepairDialog(vehicle, RepairDialog.MODE_REPAINT)
        end
    end
end

--[[
    Inject a Tires button into RVB's Workshop dialog
    Clones the Repair button and places it after Repaint
]]
function RVBWorkshopIntegration:injectTiresButton(dialog)
    UsedPlus.logDebug("RVBWorkshopIntegration:injectTiresButton called")

    if dialog == nil then
        return
    end

    -- Only add once per dialog instance
    if dialog.usedPlusTiresButton then
        UsedPlus.logDebug("RVBWorkshopIntegration: Tires button already exists, updating state")
        self:updateTiresButtonState(dialog)
        return
    end

    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil then
        return
    end

    -- Find the repair button to clone (or use repaint if it exists)
    local sourceButton = dialog.usedPlusRepaintButton or dialog.repairButton
    if sourceButton == nil then
        -- Try to find by iterating elements
        for _, element in ipairs(buttonsBox.elements or {}) do
            if element.id == "repairButton" or element.name == "repairButton" then
                sourceButton = element
                break
            end
        end
    end

    if sourceButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find button to clone for Tires")
        return
    end

    -- Clone the button
    local success, tiresButton = pcall(function()
        return sourceButton:clone(buttonsBox)
    end)

    if not success or tiresButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Failed to clone button for Tires")
        return
    end

    -- Configure the tires button
    tiresButton.id = "usedPlusTiresButton"
    tiresButton.name = "usedPlusTiresButton"
    tiresButton:setText(g_i18n:getText("usedplus_button_tires") or "Tires")

    -- Set click callback
    tiresButton.onClickCallback = function()
        RVBWorkshopIntegration:onTiresButtonClick(dialog)
    end

    -- Store reference
    dialog.usedPlusTiresButton = tiresButton

    -- Update button state based on vehicle
    self:updateTiresButtonState(dialog)

    -- Refresh the layout
    if buttonsBox.invalidateLayout then
        buttonsBox:invalidateLayout()
    end

    UsedPlus.logInfo("RVBWorkshopIntegration: Added Tires button to RVB Workshop dialog")
end

--[[
    Update the Tires button state based on vehicle tire condition
]]
function RVBWorkshopIntegration:updateTiresButtonState(dialog)
    local tiresButton = dialog.usedPlusTiresButton
    if tiresButton == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        if tiresButton.setDisabled then
            tiresButton:setDisabled(true)
        end
        return
    end

    -- Check if vehicle has tires that can be serviced
    local hasTires = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil
    if tiresButton.setDisabled then
        tiresButton:setDisabled(not hasTires)
    end
end

--[[
    Handle Tires button click
    Shows our TiresDialog
]]
function RVBWorkshopIntegration:onTiresButtonClick(dialog)
    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for tires service")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Tires clicked for %s", vehicle:getName()))

    -- Play click sound
    if g_soundPlayer then
        g_soundPlayer:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end

    -- Close RVB dialog first
    if dialog.close then
        dialog:close()
    elseif g_gui.closeDialog then
        g_gui:closeDialog()
    end

    -- Show our TiresDialog
    local farmId = g_currentMission:getFarmId()

    if DialogLoader and DialogLoader.show then
        DialogLoader.show("TiresDialog", "setVehicle", vehicle, farmId)
    end
end

--[[============================================================================
    v2.2.0: Progressive Degradation Hooks
    - Service button hook: Apply repair degradation when RVB service completes
    - Fault monitoring: Apply breakdown degradation when RVB parts fail
============================================================================]]

--[[
    Hook RVB's Service button to apply degradation after service completes
    This catches repairs that don't go through our RepairDialog
]]
function RVBWorkshopIntegration:hookServiceButton(dialog)
    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusServiceHooked then
        return
    end

    -- Find RVB's service button
    local serviceButton = dialog.serviceButton
    if serviceButton == nil then
        -- Try to find by iterating elements
        local buttonsBox = dialog.buttonsBox
        if buttonsBox and buttonsBox.elements then
            for _, element in ipairs(buttonsBox.elements) do
                if element.id == "serviceButton" or element.name == "serviceButton" then
                    serviceButton = element
                    break
                end
            end
        end
    end

    if serviceButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find service button to hook")
        return
    end

    -- Store original callback
    local originalCallback = serviceButton.onClickCallback

    -- Wrap with our degradation logic
    serviceButton.onClickCallback = function()
        local vehicle = dialog.vehicle
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Service button clicked for %s",
            vehicle and vehicle:getName() or "nil"))

        -- Call original service first
        if originalCallback then
            originalCallback()
        end

        -- Apply degradation after service completes
        -- Note: Service in RVB typically resets wear/fixes minor issues
        if vehicle and ModCompatibility and ModCompatibility.applyRVBRepairDegradation then
            ModCompatibility.applyRVBRepairDegradation(vehicle)
            UsedPlus.logDebug("RVBWorkshopIntegration: Applied repair degradation after RVB service")
        end
    end

    dialog.usedPlusServiceHooked = true
    UsedPlus.logDebug("RVBWorkshopIntegration: Hooked RVB service button for degradation")
end

--[[
    Initialize fault state tracking for a vehicle
    Called when dialog opens to establish baseline
]]
function RVBWorkshopIntegration:initializeFaultTracking(vehicle)
    if vehicle == nil then
        return
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        return
    end

    -- Initialize tracking table for this vehicle
    if self.previousFaultStates[vehicle] == nil then
        self.previousFaultStates[vehicle] = {}
    end

    -- Record current fault states as baseline
    for partKey, part in pairs(rvb.parts) do
        local currentState = part.fault or "empty"
        self.previousFaultStates[vehicle][partKey] = currentState
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Initialized fault tracking for %s (%d parts)",
        vehicle:getName(), self:countParts(rvb.parts)))
end

--[[
    Check for new faults since last check
    Called periodically or when dialog updates
]]
function RVBWorkshopIntegration:checkForNewFaults(vehicle)
    if vehicle == nil then
        return
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        return
    end

    -- Initialize if not done yet
    if self.previousFaultStates[vehicle] == nil then
        self:initializeFaultTracking(vehicle)
        return  -- No comparison possible on first check
    end

    -- Check each part for new faults
    for partKey, part in pairs(rvb.parts) do
        local currentState = part.fault or "empty"
        local previousState = self.previousFaultStates[vehicle][partKey] or "empty"

        -- Detect transition TO "fault" state (breakdown occurred)
        if currentState == "fault" and previousState ~= "fault" then
            UsedPlus.logDebug(string.format(
                "RVBWorkshopIntegration: NEW FAULT detected! Part=%s, was=%s, now=%s",
                partKey, previousState, currentState))

            -- Apply breakdown degradation
            if ModCompatibility and ModCompatibility.applyRVBBreakdownDegradation then
                ModCompatibility.applyRVBBreakdownDegradation(vehicle, partKey)
            end
        end

        -- Update tracking
        self.previousFaultStates[vehicle][partKey] = currentState
    end
end

--[[
    Count parts in a table (utility)
]]
function RVBWorkshopIntegration:countParts(partsTable)
    local count = 0
    for _ in pairs(partsTable) do
        count = count + 1
    end
    return count
end

--[[
    Clean up fault tracking when vehicle is sold/removed
]]
function RVBWorkshopIntegration:cleanupFaultTracking(vehicle)
    if vehicle and self.previousFaultStates[vehicle] then
        self.previousFaultStates[vehicle] = nil
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Cleaned up fault tracking for %s",
            vehicle:getName()))
    end
end

--[[
    Periodic fault check for all vehicles with RVB data
    Called from UsedPlusMaintenance:onUpdate or message center subscription
]]
function RVBWorkshopIntegration:updateFaultMonitoring()
    if not ModCompatibility or not ModCompatibility.rvbInstalled then
        return
    end

    -- Check all vehicles with UsedPlus maintenance spec
    if g_currentMission and g_currentMission.vehicles then
        for _, vehicle in ipairs(g_currentMission.vehicles) do
            if vehicle.spec_usedPlusMaintenance and vehicle.spec_faultData then
                self:checkForNewFaults(vehicle)
            end
        end
    end
end

--[[
    Inject UsedPlus data into RVB's settingsBox
    Called after RVB populates their vehicle info
]]
function RVBWorkshopIntegration:injectUsedPlusData(dialog)
    if dialog == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration:injectUsedPlusData - dialog is nil")
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration:injectUsedPlusData - vehicle is nil")
        return
    end

    local settingsBox = dialog.settingsBox
    local templateRow = dialog.templateVehicleInfo

    if settingsBox == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Missing settingsBox")
        return
    end

    if templateRow == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Missing templateVehicleInfo")
        return
    end

    -- Get UsedPlus maintenance data
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Vehicle has no UsedPlusMaintenance spec")
        return
    end

    -- Prepare our data rows
    local usedPlusData = self:collectUsedPlusData(vehicle, spec)

    if #usedPlusData == 0 then
        UsedPlus.logDebug("RVBWorkshopIntegration: No UsedPlus data to inject")
        return
    end

    -- Get alternating color state from existing rows
    local rowCount = #settingsBox.elements
    local alternating = (rowCount % 2 == 0)

    -- Check if AISettingsDialog color exists
    local colorTable = AISettingsDialog and AISettingsDialog.COLOR_ALTERNATING
    if colorTable == nil then
        -- Fallback colors if AISettingsDialog not available
        colorTable = {
            [true] = {0.03, 0.03, 0.03, 1},
            [false] = {0.05, 0.05, 0.05, 1}
        }
    end

    -- Add a subtle header/divider row
    local dividerRow = templateRow:clone(settingsBox)
    if dividerRow then
        dividerRow:setVisible(true)
        local divColor = colorTable[alternating]
        if divColor then
            dividerRow:setImageColor(nil, unpack(divColor))
        end
        local divLabel = dividerRow:getDescendantByName("label")
        local divValue = dividerRow:getDescendantByName("value")
        if divLabel then
            divLabel:setText("— UsedPlus —")
            -- Make it slightly dimmer to look like a section header
            if divLabel.setTextColor then
                divLabel:setTextColor(0.6, 0.7, 0.8, 1)
            end
        end
        if divValue then
            divValue:setText("")
        end
        alternating = not alternating
    end

    -- Add our data rows
    for _, dataRow in ipairs(usedPlusData) do
        local element = templateRow:clone(settingsBox)
        if element then
            element:setVisible(true)
            local color = colorTable[alternating]
            if color then
                element:setImageColor(nil, unpack(color))
            end

            local label = element:getDescendantByName("label")
            local value = element:getDescendantByName("value")

            if label then
                label:setText(tostring(dataRow[1]))
            end
            if value then
                value:setText(tostring(dataRow[2]))
                -- Color code the value based on type
                if dataRow[3] and value.setTextColor then
                    value:setTextColor(unpack(dataRow[3]))
                end
            end

            alternating = not alternating
        end
    end

    -- Add Mechanic's Assessment as special centered section
    self:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)

    -- Refresh the layout
    if settingsBox.invalidateLayout then
        settingsBox:invalidateLayout()
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Injected %d UsedPlus rows for %s",
        #usedPlusData, vehicle:getName()))
end

--[[
    Collect UsedPlus data for display
    Returns array of {label, value, [color]} tuples
]]
function RVBWorkshopIntegration:collectUsedPlusData(vehicle, spec)
    local data = {}

    -- Color constants (R, G, B, A)
    local COLOR_GREEN = {0.3, 1.0, 0.4, 1}
    local COLOR_YELLOW = {1.0, 0.85, 0.2, 1}
    local COLOR_ORANGE = {1.0, 0.6, 0.2, 1}
    local COLOR_RED = {1.0, 0.4, 0.4, 1}

    -- Helper: get color based on percentage
    local function getConditionColor(pct)
        if pct >= 80 then return COLOR_GREEN
        elseif pct >= 60 then return COLOR_YELLOW
        elseif pct >= 40 then return COLOR_ORANGE
        else return COLOR_RED end
    end

    -- 1. Hydraulic System (unique to UsedPlus - RVB doesn't track this)
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    local hydraulicPct = math.floor(hydraulicReliability * 100)
    table.insert(data, {
        g_i18n:getText("usedplus_hydraulic_system") or "Hydraulic System",
        string.format("%d%%", hydraulicPct),
        getConditionColor(hydraulicPct)
    })

    -- 2. Maintenance Grade (our overall assessment)
    local grade = "Unknown"
    local gradeColor = COLOR_YELLOW

    -- Calculate overall reliability
    local engineRel = spec.engineReliability or 1.0
    local elecRel = spec.electricalReliability or 1.0
    local avgReliability = (hydraulicReliability + engineRel + elecRel) / 3

    if avgReliability >= 0.9 then
        grade = g_i18n:getText("usedplus_grade_excellent") or "Excellent"
        gradeColor = COLOR_GREEN
    elseif avgReliability >= 0.75 then
        grade = g_i18n:getText("usedplus_grade_good") or "Good"
        gradeColor = COLOR_GREEN
    elseif avgReliability >= 0.5 then
        grade = g_i18n:getText("usedplus_grade_fair") or "Fair"
        gradeColor = COLOR_YELLOW
    elseif avgReliability >= 0.3 then
        grade = g_i18n:getText("usedplus_grade_poor") or "Poor"
        gradeColor = COLOR_ORANGE
    else
        grade = g_i18n:getText("usedplus_grade_critical") or "Critical"
        gradeColor = COLOR_RED
    end

    table.insert(data, {
        g_i18n:getText("usedplus_maintenance_grade") or "Maintenance",
        grade,
        gradeColor
    })

    -- 3. Service History (if there's notable history)
    local failureCount = spec.failureCount or 0
    local repairCount = spec.repairCount or 0

    if failureCount > 0 or repairCount > 0 then
        local historyText = string.format("%d repairs, %d breakdowns", repairCount, failureCount)
        local historyColor = COLOR_YELLOW
        if failureCount > 3 then
            historyColor = COLOR_ORANGE
        elseif failureCount == 0 and repairCount > 0 then
            historyColor = COLOR_GREEN
        end

        table.insert(data, {
            g_i18n:getText("usedplus_service_history") or "History",
            historyText,
            historyColor
        })
    end

    -- NOTE: Mechanic's Assessment is now handled separately in injectUsedPlusData()
    -- to allow for special centered display formatting

    return data
end

--[[
    Fallback quote generation if main quote system unavailable
    Uses workhorseLemonScale (the vehicle's hidden DNA)
]]
function RVBWorkshopIntegration:generateFallbackQuote(workhorseLemonScale)
    if workhorseLemonScale >= 0.9 then
        return "Exceptional build quality"
    elseif workhorseLemonScale >= 0.7 then
        return "Solid machine"
    elseif workhorseLemonScale >= 0.5 then
        return "Average, nothing special"
    elseif workhorseLemonScale >= 0.3 then
        return "Shows some quirks"
    else
        return "Keep your mechanic's number handy"
    end
end

--[[
    Inject Mechanic's Assessment as a centered display section
    Creates a visually distinct area with header + quote
]]
function RVBWorkshopIntegration:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)
    local vehicle = dialog.vehicle
    if vehicle == nil then
        return
    end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return
    end

    -- Get workhorse/lemon scale and quote
    local workhorseLemonScale = spec.workhorseLemonScale or 0.5
    local mechanicQuote = nil

    -- Get the proper inspector quote based on workhorse/lemon DNA
    if UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
        mechanicQuote = UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    end

    -- Fallback if quote system not available
    if mechanicQuote == nil or mechanicQuote == "" then
        mechanicQuote = self:generateFallbackQuote(workhorseLemonScale)
    end

    if mechanicQuote == nil or mechanicQuote == "" then
        return
    end

    -- Determine quote color based on workhorse/lemon scale
    local quoteColor = {0.85, 0.85, 0.7, 1}  -- Default warm beige
    if workhorseLemonScale >= 0.7 then
        quoteColor = {0.6, 0.95, 0.65, 1}  -- Greenish for workhorses
    elseif workhorseLemonScale <= 0.3 then
        quoteColor = {0.95, 0.6, 0.55, 1}  -- Reddish for lemons
    end

    -- Row 1: Header "MECHANIC'S ASSESSMENT" - centered
    local headerRow = templateRow:clone(settingsBox)
    if headerRow then
        headerRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            headerRow:setImageColor(nil, unpack(color))
        end

        local label = headerRow:getDescendantByName("label")
        local value = headerRow:getDescendantByName("value")

        if label then
            label:setText(g_i18n:getText("usedplus_mechanic_assessment") or "MECHANIC'S ASSESSMENT")
            -- Style as centered header
            if label.setTextColor then
                label:setTextColor(0.9, 0.8, 0.5, 1)  -- Gold header color
            end
            if label.setTextBold then
                label:setTextBold(true)
            end
            -- Center the text by adjusting alignment if possible
            if label.setTextAlignment then
                label:setTextAlignment(RenderText.ALIGN_CENTER)
            end
        end
        if value then
            value:setText("")  -- Empty value column
        end

        alternating = not alternating
    end

    -- Row 2: The quote itself - centered with italic feel
    local quoteRow = templateRow:clone(settingsBox)
    if quoteRow then
        quoteRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            quoteRow:setImageColor(nil, unpack(color))
        end

        local label = quoteRow:getDescendantByName("label")
        local value = quoteRow:getDescendantByName("value")

        if label then
            -- Format as quote with quotation marks
            label:setText(string.format('"%s"', mechanicQuote))
            if label.setTextColor then
                label:setTextColor(unpack(quoteColor))
            end
            -- Center the quote text
            if label.setTextAlignment then
                label:setTextAlignment(RenderText.ALIGN_CENTER)
            end
        end
        if value then
            value:setText("")  -- Empty value column
        end
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Added Mechanic's Assessment for %s (scale=%.2f)",
        vehicle:getName(), workhorseLemonScale))
end

--[[
    Delayed initialization (called after ModCompatibility.init)
]]
function RVBWorkshopIntegration:delayedInit()
    UsedPlus.logDebug("RVBWorkshopIntegration:delayedInit called")
    if not self.isInitialized then
        self:init()
    end
end

UsedPlus.logInfo("RVBWorkshopIntegration loaded")
