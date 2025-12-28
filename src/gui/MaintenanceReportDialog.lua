--[[
    FS25_UsedPlus - Maintenance Report Dialog

    Shows maintenance status and reliability for OWNED vehicles.
    Accessible from ESC -> Vehicles menu.
    Pattern from: InspectionReportDialog (similar structure, simpler flow)

    Key difference from InspectionReportDialog:
    - No purchase callbacks/buttons
    - Works with vehicle objects, not listings
    - Shows maintenance history (repairs, breakdowns)
]]

MaintenanceReportDialog = {}
local MaintenanceReportDialog_mt = Class(MaintenanceReportDialog, ScreenElement)

-- Dialog instance
MaintenanceReportDialog.INSTANCE = nil

--[[
    Constructor - extends ScreenElement
]]
function MaintenanceReportDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or MaintenanceReportDialog_mt)

    self.vehicle = nil
    self.isBackAllowed = true

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function MaintenanceReportDialog.getInstance()
    if MaintenanceReportDialog.INSTANCE == nil then
        MaintenanceReportDialog.INSTANCE = MaintenanceReportDialog.new()

        -- Load XML - use UsedPlus.MOD_DIR which persists after mod load
        local xmlPath = UsedPlus.MOD_DIR .. "gui/MaintenanceReportDialog.xml"
        g_gui:loadGui(xmlPath, "MaintenanceReportDialog", MaintenanceReportDialog.INSTANCE)

        UsedPlus.logDebug("MaintenanceReportDialog created and loaded from: " .. xmlPath)
    end
    return MaintenanceReportDialog.INSTANCE
end

--[[
    Show dialog for an owned vehicle
    @param vehicle - The vehicle object to show maintenance for
]]
function MaintenanceReportDialog:show(vehicle)
    if vehicle == nil then
        UsedPlus.logWarn("MaintenanceReportDialog:show called with nil vehicle")
        return
    end

    self.vehicle = vehicle
    UsedPlus.logDebug(string.format("MaintenanceReportDialog:show - vehicle=%s", tostring(vehicle:getName())))

    g_gui:showDialog("MaintenanceReportDialog")
end

--[[
    Called when dialog opens
]]
function MaintenanceReportDialog:onOpen()
    MaintenanceReportDialog:superClass().onOpen(self)

    if self.vehicle then
        self:updateDisplay()
    end
end

--[[
    Called when dialog closes
]]
function MaintenanceReportDialog:onClose()
    MaintenanceReportDialog:superClass().onClose(self)
end

--[[
    Update all display elements with vehicle maintenance data
]]
function MaintenanceReportDialog:updateDisplay()
    local vehicle = self.vehicle
    if vehicle == nil then return end

    -- Get store item for image and name
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)

    -- Vehicle name using consolidated utility
    if self.vehicleNameText then
        self.vehicleNameText:setText(UIHelper.Vehicle.getFullName(storeItem))
    end

    -- Vehicle details (hours, age, damage)
    if self.vehicleDetailsText then
        local hours = 0
        if vehicle.getOperatingTime then
            hours = math.floor((vehicle:getOperatingTime() or 0) / 3600000)
        end

        local age = 0
        if vehicle.age then
            age = math.floor((vehicle.age or 0) / 12)  -- age is in months
        end

        local damage = 0
        if vehicle.getDamageAmount then
            damage = math.floor((vehicle:getDamageAmount() or 0) * 100)
        end

        self.vehicleDetailsText:setText(string.format("Hours: %s | Age: %d years | Damage: %d%%",
            g_i18n:formatNumber(hours), age, damage))
    end

    -- Vehicle image
    if self.vehicleImage and storeItem then
        if UIHelper and UIHelper.Image and UIHelper.Image.setStoreItemImage then
            UIHelper.Image.setStoreItemImage(self.vehicleImage, storeItem)
        else
            local imagePath = storeItem.imageFilename
            if imagePath then
                self.vehicleImage:setImageFilename(imagePath)
            end
        end
    end

    -- Get maintenance data
    local maintenanceData = nil
    if UsedPlusMaintenance and UsedPlusMaintenance.getReliabilityData then
        maintenanceData = UsedPlusMaintenance.getReliabilityData(vehicle)
    end

    if maintenanceData then
        -- Update reliability displays
        self:updateReliabilityRating("engine", maintenanceData.engineReliability or 1.0)
        self:updateReliabilityRating("hydraulic", maintenanceData.hydraulicReliability or 1.0)
        self:updateReliabilityRating("electrical", maintenanceData.electricalReliability or 1.0)

        -- Update overall rating
        local avgRel = ((maintenanceData.engineReliability or 1.0) +
                       (maintenanceData.hydraulicReliability or 1.0) +
                       (maintenanceData.electricalReliability or 1.0)) / 3
        self:updateOverallRating(avgRel)

        -- Update history stats
        if self.breakdownsText then
            self.breakdownsText:setText(string.format("%d", maintenanceData.failureCount or 0))
        end

        if self.repairsText then
            self.repairsText:setText(string.format("%d", maintenanceData.repairCount or 0))
        end

        -- Update inspected status
        if self.inspectedText then
            if maintenanceData.wasInspected then
                self.inspectedText:setText(g_i18n:getText("usedplus_common_yes"))
                self.inspectedText:setTextColor(0.4, 1, 0.5, 1)
            else
                self.inspectedText:setText(g_i18n:getText("usedplus_common_no"))
                self.inspectedText:setTextColor(0.7, 0.7, 0.7, 1)
            end
        end

        -- Update resale impact
        if self.resaleImpactText then
            local resaleModifier = maintenanceData.resaleModifier or 1.0
            local impactPercent = math.floor((resaleModifier - 1.0) * 100)
            if impactPercent >= 0 then
                self.resaleImpactText:setText(string.format("+%d%%", impactPercent))
                self.resaleImpactText:setTextColor(0.4, 1, 0.5, 1)
            else
                self.resaleImpactText:setText(string.format("%d%%", impactPercent))
                self.resaleImpactText:setTextColor(1, 0.4, 0.4, 1)
            end
        end

        -- Show purchase origin
        if self.originText then
            if maintenanceData.purchasedUsed then
                self.originText:setText(g_i18n:getText("usedplus_maintenance_purchasedUsed"))
                self.originText:setTextColor(1, 0.7, 0.3, 1)  -- Orange for used
            else
                self.originText:setText(g_i18n:getText("usedplus_maintenance_purchasedNew"))
                self.originText:setTextColor(0.5, 0.85, 1, 1)  -- Light blue for new
            end
        end

        -- v1.5.1: Generate mechanic's assessment quote
        self:updateMechanicQuote(maintenanceData)

        -- v1.5.1: Show operating hours
        if self.hoursText then
            local hours = 0
            if vehicle.getOperatingTime then
                hours = math.floor((vehicle:getOperatingTime() or 0) / 3600000)
            end
            self.hoursText:setText(g_i18n:formatNumber(hours))
        end

        -- Generate status notes
        self:updateStatusNotes(maintenanceData)
    else
        -- No maintenance data - show defaults for new vehicle
        self:updateReliabilityRating("engine", 1.0)
        self:updateReliabilityRating("hydraulic", 1.0)
        self:updateReliabilityRating("electrical", 1.0)
        self:updateOverallRating(1.0)

        if self.breakdownsText then
            self.breakdownsText:setText("0")
        end
        if self.repairsText then
            self.repairsText:setText("0")
        end
        if self.inspectedText then
            self.inspectedText:setText(g_i18n:getText("usedplus_common_na"))
            self.inspectedText:setTextColor(0.6, 0.6, 0.6, 1)
        end
        if self.resaleImpactText then
            self.resaleImpactText:setText("0%")
            self.resaleImpactText:setTextColor(0.4, 1, 0.5, 1)
        end
        if self.originText then
            self.originText:setText(g_i18n:getText("usedplus_maintenance_purchasedNew"))
            self.originText:setTextColor(0.5, 0.85, 1, 1)
        end
        if self.notesText then
            self.notesText:setText(g_i18n:getText("usedplus_maintenance_excellentCondition"))
        end
        if self.notesText2 then
            self.notesText2:setText("")
        end

        -- v1.5.1: Set mechanic quote defaults for new vehicles
        if self.mechanicQuoteText then
            -- New vehicle gets legendary tier quote
            local quote = "Vehicle condition assessed."
            if UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
                quote = UsedPlusMaintenance.getInspectorQuote(1.0)  -- 100% reliability
            end
            self.mechanicQuoteText:setText('"' .. quote .. '"')
        end

        -- v1.5.1: Show operating hours for new vehicles
        if self.hoursText then
            local hours = 0
            if vehicle and vehicle.getOperatingTime then
                hours = math.floor((vehicle:getOperatingTime() or 0) / 3600000)
            end
            self.hoursText:setText(g_i18n:formatNumber(hours))
        end
    end
end

--[[
    Update a reliability rating display
    @param componentName - "engine", "hydraulic", or "electrical"
    @param reliability - 0.0 to 1.0
]]
function MaintenanceReportDialog:updateReliabilityRating(componentName, reliability)
    local percentElement = self[componentName .. "RatingText"]
    local statusElement = self[componentName .. "StatusText"]

    local percent = math.floor(reliability * 100)
    local rating = self:getRatingText(reliability)

    -- Get color based on reliability
    local r, g, b = self:getReliabilityColor(reliability)

    -- Update percentage text
    if percentElement then
        percentElement:setText(string.format("%d%%", percent))
        percentElement:setTextColor(r, g, b, 1)
    end

    -- Update status text
    if statusElement then
        statusElement:setText(rating)
        statusElement:setTextColor(r, g, b, 1)
    end
end

--[[
    Update overall rating display
    @param avgReliability - Average reliability 0.0 to 1.0
]]
function MaintenanceReportDialog:updateOverallRating(avgReliability)
    local percent = math.floor(avgReliability * 100)
    local rating = self:getRatingText(avgReliability)
    local r, g, b = self:getReliabilityColor(avgReliability)

    if self.overallRatingText then
        self.overallRatingText:setText(string.format("%d%%", percent))
        -- Overall uses gold color
        self.overallRatingText:setTextColor(1, 0.85, 0.2, 1)
    end

    if self.conditionText then
        self.conditionText:setText(rating)
        self.conditionText:setTextColor(r, g, b, 1)
    end
end

--[[
    Get color for reliability value
    @param reliability - 0.0 to 1.0
    @return r, g, b values
]]
function MaintenanceReportDialog:getReliabilityColor(reliability)
    if reliability >= 0.8 then
        return 0.4, 1, 0.5  -- Green
    elseif reliability >= 0.5 then
        return 1, 0.8, 0.2  -- Yellow/Orange
    else
        return 1, 0.4, 0.4  -- Red
    end
end

--[[
    Get rating text for reliability value
    @param reliability - 0.0 to 1.0
    @return text, icon
]]
function MaintenanceReportDialog:getRatingText(reliability)
    if reliability >= 0.9 then
        return "Excellent", "[OK]"
    elseif reliability >= 0.7 then
        return "Good", "[OK]"
    elseif reliability >= 0.5 then
        return "Acceptable", "[!]"
    elseif reliability >= 0.3 then
        return "Below Average", "[!]"
    else
        return "Poor", "[!!]"
    end
end

--[[
    Update status notes based on maintenance data
]]
function MaintenanceReportDialog:updateStatusNotes(data)
    if self.notesText == nil then return end

    local line1 = ""
    local line2 = ""

    -- Check each system
    local avgRel = ((data.engineReliability or 1) + (data.hydraulicReliability or 1) + (data.electricalReliability or 1)) / 3

    if avgRel >= 0.8 then
        line1 = "All systems operating normally. No maintenance concerns."
    elseif avgRel >= 0.5 then
        -- Moderate wear
        local issues = {}
        if (data.engineReliability or 1) < 0.7 then
            table.insert(issues, "engine")
        end
        if (data.hydraulicReliability or 1) < 0.7 then
            table.insert(issues, "hydraulics")
        end
        if (data.electricalReliability or 1) < 0.7 then
            table.insert(issues, "electrical")
        end

        if #issues > 0 then
            line1 = "Some wear detected in: " .. table.concat(issues, ", ") .. "."
            line2 = "Regular maintenance recommended to prevent breakdowns."
        else
            line1 = "Vehicle showing normal wear for its age."
        end
    else
        -- Poor condition
        local criticalIssues = {}
        if (data.engineReliability or 1) < 0.5 then
            table.insert(criticalIssues, "Engine may stall under heavy load")
        end
        if (data.hydraulicReliability or 1) < 0.5 then
            table.insert(criticalIssues, "Hydraulics may drift or fail")
        end
        if (data.electricalReliability or 1) < 0.5 then
            table.insert(criticalIssues, "Electrical cutouts likely")
        end

        line1 = "WARNING: Vehicle in poor condition - breakdowns expected."
        if #criticalIssues > 0 then
            line2 = criticalIssues[1] .. "."
        end
    end

    -- Check breakdown history
    if data.failureCount and data.failureCount > 3 then
        if line2 == "" then
            line2 = string.format("History of %d breakdown(s) on record.", data.failureCount)
        end
    end

    self.notesText:setText(line1)
    if self.notesText2 then
        self.notesText2:setText(line2)
    end
end

--[[
    v1.5.1: Generate mechanic's assessment quote based on reliability data
    Uses the same quote system as InspectionReportDialog for consistency
]]
function MaintenanceReportDialog:updateMechanicQuote(data)
    if self.mechanicQuoteText == nil then return end

    -- Calculate overall reliability scale (same concept as workhorseLemonScale)
    local avgReliability = ((data.engineReliability or 1) +
                          (data.hydraulicReliability or 1) +
                          (data.electricalReliability or 1)) / 3

    -- Get quote using the maintenance system's quote function
    local quote = "Vehicle condition assessed."
    if UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
        quote = UsedPlusMaintenance.getInspectorQuote(avgReliability)
    end

    -- Display the quote with proper formatting
    self.mechanicQuoteText:setText('"' .. quote .. '"')
end

--[[
    Calculate inspection cost for a vehicle (for informational purposes)
]]
function MaintenanceReportDialog.calculateInspectionCost(vehiclePrice)
    -- 2% of vehicle price, minimum $500, maximum $5000
    local cost = vehiclePrice * 0.02
    return math.max(500, math.min(5000, math.floor(cost)))
end

--[[
    Button handler: Close dialog
]]
function MaintenanceReportDialog:onClickClose()
    g_gui:closeDialogByName("MaintenanceReportDialog")
end

--[[
    Handle ESC key - same as close
]]
function MaintenanceReportDialog:onClickBack()
    self:onClickClose()
end

UsedPlus.logInfo("MaintenanceReportDialog loaded")
