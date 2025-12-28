--[[
    FS25_UsedPlus - Fluids Service Dialog

    Allows player to refill engine oil and hydraulic fluid.
    Shows current levels and calculated refill costs.

    Pattern from: TiresDialog, RepairDialog

    v1.7.0 - Tire and Fluid System
]]

FluidsDialog = {}
local FluidsDialog_mt = Class(FluidsDialog, MessageDialog)

-- Singleton instance
FluidsDialog.INSTANCE = nil

--[[
    Constructor
]]
function FluidsDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or FluidsDialog_mt)

    -- Vehicle data
    self.vehicle = nil
    self.vehicleName = ""
    self.storeItem = nil
    self.basePrice = 0
    self.farmId = 0

    -- Current fluid levels (0-1)
    self.oilLevel = 1.0
    self.hydraulicFluidLevel = 1.0

    -- Leak status
    self.hasOilLeak = false
    self.hasHydraulicLeak = false

    -- Selection state
    self.oilSelected = false
    self.hydraulicSelected = false

    -- Calculated costs
    self.oilCost = 0
    self.hydraulicCost = 0

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function FluidsDialog.getInstance()
    if FluidsDialog.INSTANCE == nil then
        FluidsDialog.INSTANCE = FluidsDialog.new()

        local xmlPath = UsedPlus.MOD_DIR .. "gui/FluidsDialog.xml"
        g_gui:loadGui(xmlPath, "FluidsDialog", FluidsDialog.INSTANCE)

        UsedPlus.logDebug("FluidsDialog created and loaded from: " .. xmlPath)
    end
    return FluidsDialog.INSTANCE
end

--[[
    Called when GUI elements are ready
]]
function FluidsDialog:onGuiSetupFinished()
    FluidsDialog:superClass().onGuiSetupFinished(self)
end

--[[
    Set vehicle data for fluid service
    @param vehicle - The vehicle object
    @param farmId - Farm ID that owns the vehicle
]]
function FluidsDialog:setVehicle(vehicle, farmId)
    self.vehicle = vehicle
    self.farmId = farmId

    if vehicle == nil then
        UsedPlus.logError("FluidsDialog:setVehicle - No vehicle provided")
        return
    end

    -- Get store item and vehicle name
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    self.storeItem = storeItem
    self.vehicleName = storeItem and storeItem.name or vehicle:getName() or "Unknown Vehicle"
    self.basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000) or 10000

    -- Get current fluid levels from UsedPlusMaintenance
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        self.oilLevel = spec.oilLevel or 1.0
        self.hydraulicFluidLevel = spec.hydraulicFluidLevel or 1.0
        self.hasOilLeak = spec.hasOilLeak or false
        self.hasHydraulicLeak = spec.hasHydraulicLeak or false
    else
        self.oilLevel = 1.0
        self.hydraulicFluidLevel = 1.0
        self.hasOilLeak = false
        self.hasHydraulicLeak = false
    end

    -- Reset selection
    self.oilSelected = false
    self.hydraulicSelected = false

    -- Calculate refill costs
    self:calculateCosts()

    UsedPlus.logDebug(string.format("FluidsDialog:setVehicle %s - oil=%.0f%%, hydraulic=%.0f%%",
        self.vehicleName, self.oilLevel * 100, self.hydraulicFluidLevel * 100))
end

--[[
    Calculate fluid refill costs based on vehicle base price
    Pattern: Fluids cost ~1% of vehicle price for full refill, scaled by amount needed
]]
function FluidsDialog:calculateCosts()
    local baseFluidCost = self.basePrice * 0.01  -- 1% of vehicle price for full refill

    -- Oil cost based on amount to refill
    local oilNeeded = 1.0 - self.oilLevel
    self.oilCost = math.floor(baseFluidCost * oilNeeded)

    -- Hydraulic fluid cost based on amount to refill
    local hydraulicNeeded = 1.0 - self.hydraulicFluidLevel
    self.hydraulicCost = math.floor(baseFluidCost * hydraulicNeeded)

    UsedPlus.logDebug(string.format("FluidsDialog costs: Oil=$%d (need %.0f%%), Hydraulic=$%d (need %.0f%%)",
        self.oilCost, oilNeeded * 100, self.hydraulicCost, hydraulicNeeded * 100))
end

--[[
    Called when dialog opens
]]
function FluidsDialog:onOpen()
    FluidsDialog:superClass().onOpen(self)
    self:updateDisplay()
end

--[[
    Update all display elements
]]
function FluidsDialog:updateDisplay()
    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(self.vehicleName)
    end

    -- Vehicle image
    if self.vehicleImageElement and self.storeItem then
        local imagePath = self.storeItem.imageFilename
        if imagePath then
            self.vehicleImageElement:setImageFilename(imagePath)
        end
    end

    -- Oil level
    if self.oilLevelText then
        local oilPercent = math.floor(self.oilLevel * 100)
        self.oilLevelText:setText(string.format("%d%%", oilPercent))
        self:setLevelColor(self.oilLevelText, self.oilLevel)
    end

    -- Hydraulic fluid level
    if self.hydraulicLevelText then
        local hydraulicPercent = math.floor(self.hydraulicFluidLevel * 100)
        self.hydraulicLevelText:setText(string.format("%d%%", hydraulicPercent))
        self:setLevelColor(self.hydraulicLevelText, self.hydraulicFluidLevel)
    end

    -- Leak warnings
    if self.oilLeakWarningText then
        local warnings = {}
        if self.hasOilLeak then
            table.insert(warnings, g_i18n:getText("usedplus_fluids_oilLeakWarning") or "OIL LEAK DETECTED")
        end
        if self.hasHydraulicLeak then
            table.insert(warnings, g_i18n:getText("usedplus_fluids_hydraulicLeakWarning") or "HYDRAULIC LEAK DETECTED")
        end

        if #warnings > 0 then
            self.oilLeakWarningText:setText(table.concat(warnings, " | "))
            self.oilLeakWarningText:setVisible(true)
        else
            self.oilLeakWarningText:setVisible(false)
        end
    end

    -- Oil service card
    if self.oilCostText then
        if self.oilCost > 0 then
            self.oilCostText:setText(g_i18n:formatMoney(self.oilCost, 0, true, true))
        else
            self.oilCostText:setText(g_i18n:getText("usedplus_fluids_full") or "Full")
        end
    end
    if self.oilStatusText then
        local oilNeeded = 1.0 - self.oilLevel
        if oilNeeded > 0 then
            self.oilStatusText:setText(string.format(g_i18n:getText("usedplus_fluids_refillAmount") or "Refill: %.0f%%", oilNeeded * 100))
        else
            self.oilStatusText:setText(g_i18n:getText("usedplus_fluids_noRefillNeeded") or "No refill needed")
        end
    end

    -- Hydraulic service card
    if self.hydraulicCostText then
        if self.hydraulicCost > 0 then
            self.hydraulicCostText:setText(g_i18n:formatMoney(self.hydraulicCost, 0, true, true))
        else
            self.hydraulicCostText:setText(g_i18n:getText("usedplus_fluids_full") or "Full")
        end
    end
    if self.hydraulicStatusText then
        local hydraulicNeeded = 1.0 - self.hydraulicFluidLevel
        if hydraulicNeeded > 0 then
            self.hydraulicStatusText:setText(string.format(g_i18n:getText("usedplus_fluids_refillAmount") or "Refill: %.0f%%", hydraulicNeeded * 100))
        else
            self.hydraulicStatusText:setText(g_i18n:getText("usedplus_fluids_noRefillNeeded") or "No refill needed")
        end
    end

    -- Update card highlights
    self:updateCardHighlights()

    -- Update payment summary
    self:updatePaymentSummary()
end

--[[
    Set color based on fluid level
]]
function FluidsDialog:setLevelColor(element, level)
    if level >= 0.7 then
        element:setTextColor(0.3, 1, 0.4, 1)  -- Green
    elseif level >= 0.4 then
        element:setTextColor(1, 0.85, 0.2, 1)  -- Yellow
    else
        element:setTextColor(1, 0.4, 0.4, 1)  -- Red
    end
end

--[[
    Update card highlight colors based on selection
]]
function FluidsDialog:updateCardHighlights()
    local defaultColor = {0.12, 0.12, 0.15, 1}
    local selectedColor = {0.2, 0.35, 0.2, 1}  -- Green tint for selected
    local disabledColor = {0.08, 0.08, 0.1, 0.6}  -- Dim for full

    -- Oil card
    if self.oilCardBg then
        if self.oilCost == 0 then
            self.oilCardBg:setImageColor(nil, unpack(disabledColor))
        elseif self.oilSelected then
            self.oilCardBg:setImageColor(nil, unpack(selectedColor))
        else
            self.oilCardBg:setImageColor(nil, unpack(defaultColor))
        end
    end

    -- Hydraulic card
    if self.hydraulicCardBg then
        if self.hydraulicCost == 0 then
            self.hydraulicCardBg:setImageColor(nil, unpack(disabledColor))
        elseif self.hydraulicSelected then
            self.hydraulicCardBg:setImageColor(nil, unpack(selectedColor))
        else
            self.hydraulicCardBg:setImageColor(nil, unpack(defaultColor))
        end
    end
end

--[[
    Update payment summary based on selection
]]
function FluidsDialog:updatePaymentSummary()
    local services = {}
    local totalCost = 0

    if self.oilSelected and self.oilCost > 0 then
        table.insert(services, g_i18n:getText("usedplus_fluids_oil") or "Oil")
        totalCost = totalCost + self.oilCost
    end

    if self.hydraulicSelected and self.hydraulicCost > 0 then
        table.insert(services, g_i18n:getText("usedplus_fluids_hydraulic") or "Hydraulic")
        totalCost = totalCost + self.hydraulicCost
    end

    if self.selectedServicesText then
        if #services > 0 then
            self.selectedServicesText:setText(table.concat(services, ", "))
        else
            self.selectedServicesText:setText(g_i18n:getText("usedplus_fluids_selectServices") or "Select services...")
        end
    end

    if self.totalCostText then
        self.totalCostText:setText(g_i18n:formatMoney(totalCost, 0, true, true))
    end
end

--[[
    Button callbacks - toggle selection
]]
function FluidsDialog:onClickOil()
    if self.oilCost > 0 then
        self.oilSelected = not self.oilSelected
        self:updateCardHighlights()
        self:updatePaymentSummary()
        UsedPlus.logDebug("FluidsDialog: Oil " .. (self.oilSelected and "selected" or "deselected"))
    end
end

function FluidsDialog:onClickHydraulic()
    if self.hydraulicCost > 0 then
        self.hydraulicSelected = not self.hydraulicSelected
        self:updateCardHighlights()
        self:updatePaymentSummary()
        UsedPlus.logDebug("FluidsDialog: Hydraulic " .. (self.hydraulicSelected and "selected" or "deselected"))
    end
end

--[[
    Confirm button - process fluid refills
]]
function FluidsDialog:onConfirm()
    local totalCost = 0
    local servicesPerformed = {}

    if self.oilSelected and self.oilCost > 0 then
        totalCost = totalCost + self.oilCost
        table.insert(servicesPerformed, "Oil")
    end

    if self.hydraulicSelected and self.hydraulicCost > 0 then
        totalCost = totalCost + self.hydraulicCost
        table.insert(servicesPerformed, "Hydraulic")
    end

    if #servicesPerformed == 0 then
        g_gui:showInfoDialog({
            text = g_i18n:getText("usedplus_fluids_selectFirst") or "Please select at least one service."
        })
        return
    end

    -- Check if player can afford it
    if g_currentMission:getMoney(self.farmId) < totalCost then
        g_gui:showInfoDialog({
            text = g_i18n:getText("usedplus_error_insufficientFunds") or "Insufficient funds!"
        })
        return
    end

    -- Deduct money
    g_currentMission:addMoney(-totalCost, self.farmId, MoneyType.VEHICLE_REPAIR, true)

    -- Apply fluid refills
    if self.vehicle and self.vehicle.spec_usedPlusMaintenance then
        if self.oilSelected and self.oilCost > 0 then
            UsedPlusMaintenance.refillOil(self.vehicle)
        end
        if self.hydraulicSelected and self.hydraulicCost > 0 then
            UsedPlusMaintenance.refillHydraulicFluid(self.vehicle)
        end

        UsedPlus.logInfo(string.format("Fluids refilled on %s: %s for %s",
            self.vehicleName, table.concat(servicesPerformed, ", "), g_i18n:formatMoney(totalCost, 0, true, true)))
    end

    -- Close dialog
    self:close()

    -- Show confirmation
    g_gui:showInfoDialog({
        text = string.format(g_i18n:getText("usedplus_fluids_refilled") or "Fluids refilled: %s",
            table.concat(servicesPerformed, ", "))
    })
end

--[[
    Cancel button
]]
function FluidsDialog:onCancel()
    self:close()
end

function FluidsDialog:onClose()
    FluidsDialog:superClass().onClose(self)
end

UsedPlus.logInfo("FluidsDialog loaded")
