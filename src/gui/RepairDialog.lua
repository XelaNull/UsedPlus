--[[
    FS25_UsedPlus - Repair Dialog

     Custom repair dialog with fine-grained percentage control
     Pattern from: FinanceDialog (working reference)
     Reference: FS25_ADVANCED_PATTERNS.md - Shop UI Customization

    Features:
    - Slider control (1-100%) for repair percentage
    - Separate modes for repair-only and repaint-only
    - Real-time cost preview as slider moves
    - Payment options: Cash or Finance
    - Vehicle current status display

    Modes:
    - "repair" - Mechanical repair only
    - "repaint" - Cosmetic repaint only
    - "both" - Combined (legacy, not used for workshop intercept)
]]

RepairDialog = {}
local RepairDialog_mt = Class(RepairDialog, MessageDialog)

-- Mode constants
RepairDialog.MODE_REPAIR = "repair"
RepairDialog.MODE_REPAINT = "repaint"
RepairDialog.MODE_BOTH = "both"

--[[
     Constructor
]]
function RepairDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or RepairDialog_mt)

    self.i18n = i18n or g_i18n

    -- Vehicle data
    self.vehicle = nil
    self.vehicleName = ""
    self.basePrice = 0
    self.farmId = 0

    -- Dialog mode (repair, repaint, or both)
    self.mode = RepairDialog.MODE_BOTH

    -- Current condition (0-1 scale)
    self.currentDamage = 0      -- 0 = perfect, 1 = destroyed
    self.currentWear = 0        -- 0 = perfect, 1 = needs full repaint

    -- Slider values (0-100 percentage)
    self.repairPercent = 50     -- Default 50% repair
    self.repaintPercent = 50    -- Default 50% repaint

    -- Calculated costs
    self.repairCost = 0
    self.repaintCost = 0
    self.totalCost = 0

    -- Full repair costs (for reference)
    self.fullRepairCost = 0
    self.fullRepaintCost = 0

    return self
end

--[[
     Called when GUI elements are ready
     Element references auto-populated by g_gui based on XML id attributes
     No manual caching needed - removed redundant self.x = self.x patterns
]]
function RepairDialog:onGuiSetupFinished()
    RepairDialog:superClass().onGuiSetupFinished(self)
    -- UI elements automatically available via XML id attributes:
    -- vehicleNameText, vehicleImageElement
    -- currentConditionText, currentConditionBar, currentPaintText, currentPaintBar
    -- repairSlider, repairPercentText, repairCostText, repairAfterText
    -- repaintSlider, repaintPercentText, repaintCostText, repaintAfterText
    -- workSlider, workPercentText, workCostText, workAfterText, workSectionTitle, workSliderLabel
    -- totalCostText, playerMoneyText
    -- payCashButton, financeButton, cancelButton
end

--[[
     Set vehicle data for repair
    @param vehicle - The vehicle object to repair
    @param farmId - Farm ID that owns the vehicle
    @param mode - Optional mode: "repair", "repaint", or "both" (default: "both")
    @param rvbRepairCost - Optional: RVB's calculated repair cost (used when called from RVB Workshop)
]]
function RepairDialog:setVehicle(vehicle, farmId, mode, rvbRepairCost)
    self.vehicle = vehicle
    self.farmId = farmId
    self.mode = mode or RepairDialog.MODE_BOTH
    self.rvbRepairCost = rvbRepairCost  -- Store RVB cost for later use

    if vehicle == nil then
        UsedPlus.logError("RepairDialog:setVehicle - No vehicle provided")
        return
    end

    UsedPlus.logDebug(string.format("RepairDialog:setVehicle mode=%s", self.mode))

    -- Get store item and vehicle name using consolidated utility
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    self.storeItem = storeItem
    self.vehicleName = UIHelper.Vehicle.getFullName(storeItem)
    self.basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000) or 10000

    -- Get current damage and wear (0-1 scale, 0 = perfect)
    if vehicle.getDamageAmount then
        self.currentDamage = vehicle:getDamageAmount() or 0
    else
        self.currentDamage = 0
    end

    if vehicle.getWearTotalAmount then
        self.currentWear = vehicle:getWearTotalAmount() or 0
    else
        self.currentWear = 0
    end

    -- Get cost multipliers from settings (v2.0.0: separate paint multiplier)
    local repairMultiplier = UsedPlusSettings and UsedPlusSettings:get("repairCostMultiplier") or 1.0
    local paintMultiplier = UsedPlusSettings and UsedPlusSettings:get("paintCostMultiplier") or 1.0

    -- Calculate full repair cost
    -- v2.1.2: Use RVB's calculated repair cost if provided (from RVB Workshop integration)
    if self.rvbRepairCost and self.rvbRepairCost > 0 then
        self.fullRepairCost = self.rvbRepairCost
        UsedPlus.logDebug(string.format("RepairDialog: Using RVB repair cost: $%d", self.fullRepairCost))
    elseif Wearable and Wearable.calculateRepairPrice then
        self.fullRepairCost = Wearable.calculateRepairPrice(self.basePrice, self.currentDamage) or 0
        -- Apply settings multiplier (only when not using RVB cost)
        self.fullRepairCost = math.floor(self.fullRepairCost * repairMultiplier)
    else
        -- Fallback calculation: damage% * 25% of base price
        self.fullRepairCost = math.floor(self.basePrice * self.currentDamage * 0.25)
        -- Apply settings multiplier
        self.fullRepairCost = math.floor(self.fullRepairCost * repairMultiplier)
    end

    if Wearable and Wearable.calculateRepaintPrice then
        self.fullRepaintCost = Wearable.calculateRepaintPrice(self.basePrice, self.currentWear) or 0
    else
        -- Fallback calculation: wear% * 15% of base price
        self.fullRepaintCost = math.floor(self.basePrice * self.currentWear * 0.15)
    end
    -- Apply settings multiplier to repaint (v2.0.0: uses separate paintCostMultiplier)
    self.fullRepaintCost = math.floor(self.fullRepaintCost * paintMultiplier)

    -- Reset sliders to sensible defaults
    -- If vehicle needs minimal repair, default to 100%
    -- If vehicle needs major repair, default to 50%
    if self.currentDamage < 0.2 then
        self.repairPercent = 100
    else
        self.repairPercent = 50
    end

    if self.currentWear < 0.2 then
        self.repaintPercent = 100
    else
        self.repaintPercent = 50
    end

    -- Calculate initial costs
    self:calculateCosts()

    -- Update UI
    self:updateDisplay()

    UsedPlus.logDebug(string.format("RepairDialog loaded for: %s", self.vehicleName))
    UsedPlus.logTrace(string.format("  Base price: $%d", self.basePrice))
    UsedPlus.logTrace(string.format("  Current damage: %.1f%%", self.currentDamage * 100))
    UsedPlus.logTrace(string.format("  Current wear: %.1f%%", self.currentWear * 100))
    UsedPlus.logTrace(string.format("  Full repair cost: $%d", self.fullRepairCost))
    UsedPlus.logTrace(string.format("  Full repaint cost: $%d", self.fullRepaintCost))
end

--[[
     Calculate repair and repaint costs based on slider percentages and mode
]]
function RepairDialog:calculateCosts()
    -- Reset costs
    self.repairCost = 0
    self.repaintCost = 0

    -- Calculate based on mode
    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        -- Repair cost is proportional to percentage selected
        self.repairCost = math.floor(self.fullRepairCost * (self.repairPercent / 100))
    end

    if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
        -- Repaint cost is proportional to percentage selected
        self.repaintCost = math.floor(self.fullRepaintCost * (self.repaintPercent / 100))
    end

    -- Total cost (only active modes)
    self.totalCost = self.repairCost + self.repaintCost
end

--[[
     Calculate condition after repair
    @return newCondition (0-1 where 1 = 100% healthy)
]]
function RepairDialog:getConditionAfterRepair()
    -- Current condition as percentage (1 - damage)
    local currentCondition = 1 - self.currentDamage

    -- Damage that will be removed
    local damageToRemove = self.currentDamage * (self.repairPercent / 100)

    -- New condition
    local newCondition = currentCondition + damageToRemove

    return math.min(1, newCondition)
end

--[[
     Calculate paint condition after repaint
    @return newPaintCondition (0-1 where 1 = 100% fresh paint)
]]
function RepairDialog:getPaintAfterRepaint()
    -- Current paint condition (1 - wear)
    local currentPaint = 1 - self.currentWear

    -- Wear that will be removed
    local wearToRemove = self.currentWear * (self.repaintPercent / 100)

    -- New paint condition
    local newPaint = currentPaint + wearToRemove

    return math.min(1, newPaint)
end

--[[
     Update all UI elements based on mode
     Refactored to use UIHelper for consistent formatting
    Uses unified work section that adapts to repair or repaint mode
]]
function RepairDialog:updateDisplay()
    -- Determine which mode we're in
    local isRepairMode = (self.mode == RepairDialog.MODE_REPAIR)
    local isRepaintMode = (self.mode == RepairDialog.MODE_REPAINT)

    -- Set vehicle image
    if self.vehicleImageElement and self.storeItem then
        UIHelper.Image.setStoreItemImage(self.vehicleImageElement, self.storeItem)
    end

    -- Update button highlights based on current selection
    self:updateButtonHighlights()

    -- Update dialog title based on mode
    local title = "Vehicle Service"
    if isRepairMode then
        title = g_i18n:getText("usedplus_repair_title_mechanical") or "Mechanical Repair"
    elseif isRepaintMode then
        title = g_i18n:getText("usedplus_repair_title_repaint") or "Repaint Vehicle"
    else
        title = g_i18n:getText("usedplus_repair_title") or "Vehicle Service"
    end
    UIHelper.Element.setText(self.dialogTitleElement, title)

    -- Vehicle name
    UIHelper.Element.setText(self.vehicleNameText, self.vehicleName)

    -- Hide/show status sections based on mode
    UIHelper.Element.setVisible(self.repairStatusSection, isRepairMode)
    UIHelper.Element.setVisible(self.repaintStatusSection, isRepaintMode)

    -- Update work section title and labels based on mode
    local sectionTitle = isRepairMode
        and (g_i18n:getText("usedplus_repair_mechanical") or "MECHANICAL REPAIR")
        or (g_i18n:getText("usedplus_repair_cosmetic") or "PAINT & COSMETICS")
    UIHelper.Element.setText(self.workSectionTitle, sectionTitle)
    UIHelper.Element.setText(self.workSliderLabel, isRepairMode and "Repair:" or "Repaint:")

    -- Set explanatory text based on mode
    local explainKey = isRepairMode and "usedplus_rp_percentExplain" or "usedplus_rp_percentExplainPaint"
    UIHelper.Element.setText(self.percentExplainText, g_i18n:getText(explainKey))

    -- Current condition displays (using UIHelper.Vehicle pattern)
    UIHelper.Vehicle.displayCondition(
        self.currentConditionText,
        self.currentPaintText,
        self.currentConditionBar,
        self.currentPaintBar,
        self.currentDamage,
        self.currentWear
    )

    -- Work section values (unified slider/buttons)
    local workPercent, workCost, workAfter
    if isRepairMode then
        workPercent = self.repairPercent
        workCost = self.repairCost
        workAfter = math.floor(self:getConditionAfterRepair() * 100)
    else
        workPercent = self.repaintPercent
        workCost = self.repaintCost
        workAfter = math.floor(self:getPaintAfterRepaint() * 100)
    end

    -- Update work slider
    if self.workSlider then
        self.workSlider:setValue(workPercent / 100)
        local needsWork = isRepairMode and (self.currentDamage >= 0.01) or (self.currentWear >= 0.01)
        self.workSlider:setDisabled(not needsWork)
    end

    -- Work section text displays
    UIHelper.Element.setText(self.workPercentText, UIHelper.Text.formatPercent(workPercent, false))
    UIHelper.Element.setText(self.workCostText, UIHelper.Text.formatMoney(workCost))
    UIHelper.Element.setText(self.workAfterText, UIHelper.Text.formatPercent(workAfter, false))

    -- Total cost (orange for expense)
    UIHelper.Element.setTextWithColor(self.totalCostText,
        UIHelper.Text.formatMoney(self.totalCost), UIHelper.Colors.COST_ORANGE)

    -- Result in payment section (shows what condition will be after work)
    UIHelper.Element.setText(self.paymentResultText, string.format("→ %d%%", workAfter))

    -- Enable/disable pay cash button based on funds (game UI shows player money)
    if self.payCashButton then
        local playerMoney = 0
        local farm = g_farmManager:getFarmById(self.farmId)
        if farm then
            playerMoney = farm.money or 0
        end
        local canAfford = playerMoney >= self.totalCost and self.totalCost > 0
        self.payCashButton:setDisabled(not canAfford)
    end

    -- Finance button - enabled if there's a cost AND player qualifies for financing
    if self.financeButton then
        local canFinanceRepair = true
        local financeDisabledReason = nil

        -- Check credit qualification
        if CreditScore and CreditScore.canFinance then
            local canFinance, minRequired, currentScore = CreditScore.canFinance(self.farmId, "REPAIR")
            if not canFinance then
                canFinanceRepair = false
                local template = g_i18n:getText("usedplus_credit_needScore")
                financeDisabledReason = string.format(template, currentScore, minRequired)
            end
        end

        -- Disable if no cost or can't qualify
        local shouldDisable = (self.totalCost <= 0) or (not canFinanceRepair)
        self.financeButton:setDisabled(shouldDisable)

        -- Show tooltip/reason if disabled due to credit
        if self.financeDisabledText then
            if financeDisabledReason then
                self.financeDisabledText:setText(financeDisabledReason)
                self.financeDisabledText:setVisible(true)
            else
                self.financeDisabledText:setVisible(false)
            end
        end
    end
end

--[[
     Unified work slider changed callback
    Note: FS25 slider callbacks can pass (value) or (slider, value) depending on context
]]
function RepairDialog:onWorkSliderChanged(sliderOrValue, value)
    -- Handle both callback signatures: (value) and (slider, value)
    local actualValue = value
    if actualValue == nil then
        -- First argument is the value, not the slider
        if type(sliderOrValue) == "number" then
            actualValue = sliderOrValue
        elseif type(sliderOrValue) == "table" and sliderOrValue.sliderValue then
            actualValue = sliderOrValue.sliderValue
        elseif self.workSlider then
            actualValue = self.workSlider.sliderValue or 0.5
        else
            actualValue = 0.5
        end
    end

    -- Ensure actualValue is a number
    if type(actualValue) ~= "number" then
        actualValue = 0.5
    end

    -- Convert 0-1 to 0-100 percentage, round to nearest 5%
    local percent = math.floor((actualValue * 100) / 5 + 0.5) * 5
    percent = math.max(0, math.min(100, percent))

    -- Update the appropriate percent based on mode
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = percent
    else
        self.repaintPercent = percent
    end

    self:calculateCosts()
    self:updateDisplay()
end

--[[
     Pay cash button clicked - shows confirmation dialog first
]]
function RepairDialog:onPayCash()
    if self.totalCost <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "No repairs selected"
        )
        return
    end

    -- Check funds
    local farm = g_farmManager:getFarmById(self.farmId)
    if not farm or farm.money < self.totalCost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Insufficient funds. Need %s", UIHelper.Text.formatMoney(self.totalCost))
        )
        return
    end

    -- Build confirmation message
    local serviceType = (self.mode == RepairDialog.MODE_REPAIR) and "Mechanical Repair" or "Repaint"
    local workPercent = (self.mode == RepairDialog.MODE_REPAIR) and self.repairPercent or self.repaintPercent

    local confirmMessage = string.format(
        "Confirm %s Payment\n\nVehicle: %s\nService: %d%% %s\n\nTotal Cost: %s\n\nProceed with payment?",
        serviceType,
        self.vehicleName,
        workPercent,
        serviceType,
        g_i18n:formatMoney(self.totalCost, 0, true, true)
    )

    -- Set bypass flag so VehicleSellingPointExtension doesn't intercept this dialog
    -- and create an infinite loop of RepairDialog → YesNoDialog → RepairDialog
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = true
    end

    -- Show confirmation dialog using FS25's YesNoDialog.show()
    -- Signature: YesNoDialog.show(callback, target, text, title, yesText, noText)
    YesNoDialog.show(
        self.onPayCashConfirmed,
        self,
        confirmMessage,
        "Confirm Payment"
    )
end

--[[
    Callback when user confirms Pay Cash
    @param yes - true if user clicked Yes
]]
function RepairDialog:onPayCashConfirmed(yes)
    -- Reset bypass flag (whether confirmed or cancelled)
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = false
    end

    if not yes then
        return  -- User cancelled
    end

    -- Determine what to send based on mode (only send values for active mode)
    local sendRepairPercent = 0
    local sendRepaintPercent = 0

    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        sendRepairPercent = self.repairPercent / 100
    end
    if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
        sendRepaintPercent = self.repaintPercent / 100
    end

    -- Send repair event to server
    RepairVehicleEvent.sendToServer(
        self.vehicle,
        self.farmId,
        sendRepairPercent,
        sendRepaintPercent,
        self.totalCost,
        false  -- Not financed
    )

    -- Close dialog
    self:close()

    -- Show success notification
    local repairInfo = ""
    if self.repairPercent > 0 and self.currentDamage > 0.01 then
        repairInfo = string.format("%d%% mechanical repair", self.repairPercent)
    end
    if self.repaintPercent > 0 and self.currentWear > 0.01 then
        if repairInfo ~= "" then
            repairInfo = repairInfo .. ", "
        end
        repairInfo = repairInfo .. string.format("%d%% repaint", self.repaintPercent)
    end

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Repair complete!\n%s\nCost: %s",
            repairInfo,
            UIHelper.Text.formatMoney(self.totalCost))
    )

    -- Refresh the WorkshopScreen to show updated values
    RepairDialog.refreshWorkshopScreen()
end

--[[
     Refresh the WorkshopScreen to show updated damage/wear values
    Called after repair is applied
     This function explores various methods to refresh the workshop UI
]]
function RepairDialog.refreshWorkshopScreen()
    UsedPlus.logTrace("refreshWorkshopScreen called")

    -- The WorkshopScreen GUI is accessed via g_gui.guis.WorkshopScreen
    local workshopGui = g_gui and g_gui.guis and g_gui.guis.WorkshopScreen
    if not workshopGui then
        UsedPlus.logTrace("WorkshopScreen GUI not found")
        return
    end

    local workshopScreen = workshopGui.target or workshopGui

    -- Get vehicle to read updated values
    local vehicle = workshopScreen.vehicle or (g_workshopScreen and g_workshopScreen.vehicle)
    if not vehicle then
        UsedPlus.logTrace("No vehicle found for refresh")
        return
    end

    -- Get current wear/damage from vehicle
    local currentWear = vehicle.getWearTotalAmount and vehicle:getWearTotalAmount() or 0
    local currentDamage = vehicle.getDamageAmount and vehicle:getDamageAmount() or 0

    UsedPlus.logTrace(string.format("Vehicle state - wear: %.1f%%, damage: %.1f%%",
        currentWear * 100, currentDamage * 100))

    -- Try to find and update condition/wear display elements
    local elementsToTry = {
        "conditionBar", "wearBar", "damageBar", "paintBar",
        "conditionValue", "wearValue", "damageValue", "paintValue",
        "vehicleCondition", "vehicleWear", "vehicleDamage", "vehiclePaint"
    }

    for _, elemName in ipairs(elementsToTry) do
        local elem = workshopScreen[elemName]
        if elem then
            if elem.setValue then
                if string.find(elemName:lower(), "wear") or string.find(elemName:lower(), "paint") then
                    elem:setValue(1 - currentWear)
                elseif string.find(elemName:lower(), "damage") or string.find(elemName:lower(), "condition") then
                    elem:setValue(1 - currentDamage)
                end
            end
            if elem.setText then
                if string.find(elemName:lower(), "wear") or string.find(elemName:lower(), "paint") then
                    elem:setText(string.format("%.0f%%", (1 - currentWear) * 100))
                elseif string.find(elemName:lower(), "damage") or string.find(elemName:lower(), "condition") then
                    elem:setText(string.format("%.0f%%", (1 - currentDamage) * 100))
                end
            end
        end
    end

    -- Try various refresh methods
    if workshopScreen.updateVehicleInfo then workshopScreen:updateVehicleInfo() end
    if workshopScreen.updateDisplay then workshopScreen:updateDisplay() end

    -- Try to refresh the vehicle list
    if workshopScreen.list then
        local list = workshopScreen.list
        if list.reloadData then list:reloadData() end
        if list.updateItemPositions then list:updateItemPositions() end
        if list.updateContents then list:updateContents() end

        if list.getSelectedElementIndex and list.setSelectedIndex then
            local idx = list:getSelectedElementIndex()
            if idx then list:setSelectedIndex(idx) end
        end
    end

    -- Try to trigger vehicle update
    if workshopScreen.onVehicleChanged then workshopScreen:onVehicleChanged(vehicle) end
    if workshopScreen.setVehicle then workshopScreen:setVehicle(vehicle) end
    if workshopScreen.updateButtons then workshopScreen:updateButtons() end
    if workshopScreen.updateMenuButtons then workshopScreen:updateMenuButtons() end
    if workshopScreen.onMenuUpdate then workshopScreen:onMenuUpdate() end

    -- Try to trigger list selection refresh
    if workshopScreen.onListSelectionChanged then
        local selectedIdx = 1
        if workshopScreen.list and workshopScreen.list.getSelectedElementIndex then
            selectedIdx = workshopScreen.list:getSelectedElementIndex() or 1
        end
        workshopScreen:onListSelectionChanged(selectedIdx)
    end

    -- Force vehicle dirty flags
    if vehicle.setDirty then vehicle:setDirty() end
    if vehicle.raiseActive then vehicle:raiseActive() end

    UsedPlus.logTrace("refreshWorkshopScreen complete")
end

--[[
     Finance button clicked - open full RepairFinanceDialog
    Allows user to select term, down payment, and see full payment details
]]
function RepairDialog:onFinanceRepair()
    if self.totalCost <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "No repairs selected"
        )
        return
    end

    -- Capture data before closing (only send values for active mode)
    local capturedVehicle = self.vehicle
    local capturedFarmId = self.farmId
    local capturedTotalCost = self.totalCost
    local capturedMode = self.mode

    -- Only send percent for the active mode
    local capturedRepairPercent = 0
    local capturedRepaintPercent = 0
    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        capturedRepairPercent = self.repairPercent
    end
    if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
        capturedRepaintPercent = self.repaintPercent
    end

    -- Close this dialog
    self:close()

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("RepairFinanceDialog", "setData",
        capturedVehicle,
        capturedFarmId,
        capturedTotalCost,
        capturedRepairPercent,
        capturedRepaintPercent,
        capturedMode
    )
end

--[[
     Cancel button clicked
]]
function RepairDialog:onCancel()
    self:close()
end

--[[
     Update button background highlights to show current selection
]]
function RepairDialog:updateButtonHighlights()
    local currentPercent = (self.mode == RepairDialog.MODE_REPAIR) and self.repairPercent or self.repaintPercent

    -- Define colors for normal, selected, and 100% states
    local normalColor = {0.15, 0.15, 0.18, 1}      -- Dark gray
    local selectedColor = {0.2, 0.4, 0.6, 1}       -- Blue highlight
    local fullNormalColor = {0.15, 0.25, 0.15, 1}  -- Green tint for 100%
    local fullSelectedColor = {0.2, 0.5, 0.25, 1}  -- Bright green when selected

    -- Helper to set button background color
    local function setButtonColor(element, color)
        if element and element.setImageColor then
            element:setImageColor(nil, color[1], color[2], color[3], color[4])
        end
    end

    -- Update each button's background
    setButtonColor(self.btn25Bg, currentPercent == 25 and selectedColor or normalColor)
    setButtonColor(self.btn50Bg, currentPercent == 50 and selectedColor or normalColor)
    setButtonColor(self.btn75Bg, currentPercent == 75 and selectedColor or normalColor)
    setButtonColor(self.btn100Bg, currentPercent == 100 and fullSelectedColor or fullNormalColor)
end

--[[
     Quick buttons (preset percentages) - unified for both modes
]]
function RepairDialog:onQuickButton25()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 25
    else
        self.repaintPercent = 25
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton50()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 50
    else
        self.repaintPercent = 50
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton75()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 75
    else
        self.repaintPercent = 75
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton100()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 100
    else
        self.repaintPercent = 100
    end
    self:calculateCosts()
    self:updateDisplay()
end

UsedPlus.logInfo("RepairDialog loaded")
