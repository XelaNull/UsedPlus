--[[
    FS25_UsedPlus - Repossession Notification Dialog

    Shows player what was repossessed due to loan default.
    Handles:
    - Single vehicle repossession (financed vehicle default)
    - Multiple vehicle repossession (cash loan collateral)
    - Land seizure (financed land default)

    Player must acknowledge this dialog - it's a critical event.
]]

RepossessionDialog = {}
local RepossessionDialog_mt = Class(RepossessionDialog, MessageDialog)

-- Type of repossession for display customization
RepossessionDialog.TYPE = {
    VEHICLE = 1,        -- Single financed vehicle
    LAND = 2,           -- Financed land
    COLLATERAL = 3,     -- Cash loan collateral (multiple items)
}

-- Control element references
RepossessionDialog.CONTROLS = {
    "itemNameText",
    "itemValueText",
    "missedPaymentsText",
    "balanceOwedText",
    "creditWarningText",
    "additionalItemsText"
}

--[[
    Constructor
]]
function RepossessionDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or RepossessionDialog_mt)

    self.i18n = i18n or g_i18n

    -- Data
    self.repossessionType = RepossessionDialog.TYPE.VEHICLE
    self.itemName = ""
    self.itemValue = 0
    self.missedPayments = 3
    self.balanceOwed = 0
    self.additionalItems = {}  -- For multiple collateral items
    self.callback = nil

    return self
end

--[[
    Set data for the dialog (called by DialogLoader or directly)
    @param data - Table with repossession details:
        - type: RepossessionDialog.TYPE value
        - itemName: Primary item name
        - itemValue: Primary item value
        - missedPayments: Number of missed payments
        - balanceOwed: Outstanding balance when defaulted
        - additionalItems: Array of {name, value} for extra items (collateral)
    @param callback - Optional callback when dialog closes
]]
function RepossessionDialog:setData(data, callback)
    if not data then
        UsedPlus.logError("RepossessionDialog:setData - data is nil")
        return
    end

    self.repossessionType = data.type or RepossessionDialog.TYPE.VEHICLE
    self.itemName = data.itemName or "Unknown"
    self.itemValue = data.itemValue or 0
    self.missedPayments = data.missedPayments or 3
    self.balanceOwed = data.balanceOwed or 0
    self.additionalItems = data.additionalItems or {}
    self.callback = callback

    UsedPlus.logDebug(string.format("RepossessionDialog:setData - type=%d, item=%s, value=%d",
        self.repossessionType, self.itemName, self.itemValue))
end

--[[
    onOpen callback - update display when dialog opens
]]
function RepossessionDialog:onOpen()
    RepossessionDialog:superClass().onOpen(self)

    -- Assign controls
    self:assignControls()

    -- Update display
    self:updateDisplay()
end

--[[
    Assign control elements from XML
]]
function RepossessionDialog:assignControls()
    for _, name in pairs(RepossessionDialog.CONTROLS) do
        if self[name] == nil then
            self[name] = self.target and self.target[name]
        end
    end
end

--[[
    Update all display elements
]]
function RepossessionDialog:updateDisplay()
    -- Item name
    if self.itemNameText then
        self.itemNameText:setText(self.itemName)
    end

    -- Item value
    if self.itemValueText then
        self.itemValueText:setText(g_i18n:formatMoney(self.itemValue, 0, true, true))
    end

    -- Missed payments
    if self.missedPaymentsText then
        self.missedPaymentsText:setText(string.format("%d consecutive", self.missedPayments))
    end

    -- Balance owed (now cleared by repossession)
    if self.balanceOwedText then
        if self.balanceOwed > 0 then
            self.balanceOwedText:setText(g_i18n:formatMoney(self.balanceOwed, 0, true, true) .. " (cleared)")
        else
            self.balanceOwedText:setText("$0 (cleared)")
        end
    end

    -- Credit warning
    if self.creditWarningText then
        local warningText = self.i18n:getText("usedplus_rp_creditImpact")
        if not warningText or warningText == "usedplus_rp_creditImpact" then
            warningText = "This repossession severely impacts your credit score. Future financing will be more expensive or denied."
        end
        self.creditWarningText:setText(warningText)
    end

    -- Additional items (for multiple collateral)
    if self.additionalItemsText then
        if #self.additionalItems > 0 then
            local totalExtra = 0
            for _, item in ipairs(self.additionalItems) do
                totalExtra = totalExtra + (item.value or 0)
            end
            local additionalText = string.format("+ %d additional items repossessed (%s total)",
                #self.additionalItems,
                g_i18n:formatMoney(totalExtra, 0, true, true))
            self.additionalItemsText:setText(additionalText)
        else
            self.additionalItemsText:setText("")
        end
    end
end

--[[
    OK button handler
]]
function RepossessionDialog:onClickOk()
    self:close()
end

--[[
    Close the dialog
]]
function RepossessionDialog:close()
    -- Call callback if set
    if self.callback then
        self.callback()
    end

    g_gui:closeDialogByName("RepossessionDialog")
end

--[[
    Static method to show repossession for a single vehicle
    @param vehicleName - Name of the vehicle
    @param vehicleValue - Value of the vehicle
    @param missedPayments - Number of missed payments
    @param balanceOwed - Outstanding balance
    @param callback - Optional callback when closed
]]
function RepossessionDialog.showVehicleRepossession(vehicleName, vehicleValue, missedPayments, balanceOwed, callback)
    local data = {
        type = RepossessionDialog.TYPE.VEHICLE,
        itemName = vehicleName,
        itemValue = vehicleValue,
        missedPayments = missedPayments or 3,
        balanceOwed = balanceOwed or 0,
        additionalItems = {}
    }

    return DialogLoader.show("RepossessionDialog", "setData", data, callback)
end

--[[
    Static method to show repossession for land seizure
    @param landName - Name of the land/field
    @param landValue - Value of the land
    @param missedPayments - Number of missed payments
    @param balanceOwed - Outstanding balance
    @param callback - Optional callback when closed
]]
function RepossessionDialog.showLandSeizure(landName, landValue, missedPayments, balanceOwed, callback)
    local data = {
        type = RepossessionDialog.TYPE.LAND,
        itemName = landName,
        itemValue = landValue,
        missedPayments = missedPayments or 3,
        balanceOwed = balanceOwed or 0,
        additionalItems = {}
    }

    return DialogLoader.show("RepossessionDialog", "setData", data, callback)
end

--[[
    Static method to show repossession for collateral (cash loan default)
    @param repossessedItems - Array of {name, value} for each repossessed item
    @param missedPayments - Number of missed payments
    @param balanceOwed - Outstanding balance
    @param callback - Optional callback when closed
]]
function RepossessionDialog.showCollateralRepossession(repossessedItems, missedPayments, balanceOwed, callback)
    if not repossessedItems or #repossessedItems == 0 then
        UsedPlus.logWarn("RepossessionDialog.showCollateralRepossession - no items to show")
        return false
    end

    -- First item is the "primary" item shown prominently
    local primaryItem = repossessedItems[1]

    -- Rest are "additional items"
    local additionalItems = {}
    for i = 2, #repossessedItems do
        table.insert(additionalItems, repossessedItems[i])
    end

    local data = {
        type = RepossessionDialog.TYPE.COLLATERAL,
        itemName = primaryItem.name or "Unknown Vehicle",
        itemValue = primaryItem.value or 0,
        missedPayments = missedPayments or 3,
        balanceOwed = balanceOwed or 0,
        additionalItems = additionalItems
    }

    return DialogLoader.show("RepossessionDialog", "setData", data, callback)
end

UsedPlus.logInfo("RepossessionDialog loaded")
