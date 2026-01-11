--[[
    FS25_UsedPlus - Inspection Report Dialog

    Shows detailed inspection report for used vehicles before purchase.
    Reveals hidden reliability scores that player paid to inspect.
    Pattern from: ScreenElement (NOT MessageDialog - that causes conflicts)

    Responsibilities:
    - Display vehicle info and price
    - Show reliability ratings (engine, hydraulic, electrical)
    - v2.1.0: Show RVB parts breakdown when data available
    - v2.1.0: Show UYT tire conditions when data available
    - Display inspector notes based on condition
    - Allow player to proceed with purchase or cancel
]]

InspectionReportDialog = {}
local InspectionReportDialog_mt = Class(InspectionReportDialog, ScreenElement)

-- Dialog instance
InspectionReportDialog.INSTANCE = nil

--[[
    Constructor - extends ScreenElement, NOT MessageDialog
]]
function InspectionReportDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or InspectionReportDialog_mt)

    self.listing = nil
    self.onPurchaseCallback = nil
    self.callbackTarget = nil
    self.isBackAllowed = true

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function InspectionReportDialog.getInstance()
    if InspectionReportDialog.INSTANCE == nil then
        InspectionReportDialog.INSTANCE = InspectionReportDialog.new()

        -- Load XML - use UsedPlus.MOD_DIR which persists after mod load
        local xmlPath = UsedPlus.MOD_DIR .. "gui/InspectionReportDialog.xml"
        g_gui:loadGui(xmlPath, "InspectionReportDialog", InspectionReportDialog.INSTANCE)

        UsedPlus.logDebug("InspectionReportDialog created and loaded from: " .. xmlPath)
    end
    return InspectionReportDialog.INSTANCE
end

--[[
    Show dialog with inspection data
    @param listing - The used vehicle listing with usedPlusData
    @param farmId - Farm ID for purchase and Go Back
    @param onPurchaseCallback - Function to call if player clicks Buy (from preview dialog)
    @param callbackTarget - Target object for callback (preview dialog instance)
    @param originalPurchaseCallback - Original callback from UsedVehicleManager
    @param originalCallbackTarget - Original target from UsedVehicleManager
]]
function InspectionReportDialog:show(listing, farmId, onPurchaseCallback, callbackTarget, originalPurchaseCallback, originalCallbackTarget)
    self.listing = listing
    self.farmId = farmId
    self.onPurchaseCallback = onPurchaseCallback
    self.callbackTarget = callbackTarget
    -- Store original callbacks for Go Back functionality
    self.originalPurchaseCallback = originalPurchaseCallback
    self.originalCallbackTarget = originalCallbackTarget

    UsedPlus.logDebug(string.format("InspectionReportDialog:show - listing=%s, farmId=%s",
        tostring(listing and listing.storeItemName), tostring(farmId)))

    g_gui:showDialog("InspectionReportDialog")
end

--[[
    Called when dialog opens
]]
function InspectionReportDialog:onOpen()
    InspectionReportDialog:superClass().onOpen(self)

    -- Update display with listing data
    if self.listing then
        self:updateDisplay()
    end
end

--[[
    Called when dialog closes
]]
function InspectionReportDialog:onClose()
    InspectionReportDialog:superClass().onClose(self)
end

--[[
    Update all display elements with inspection data
]]
function InspectionReportDialog:updateDisplay()
    local listing = self.listing
    if listing == nil then return end

    -- Get store item for image
    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(listing.storeItemName or "Unknown Vehicle")
    end

    -- Vehicle details
    if self.vehicleDetailsText then
        local hours = listing.operatingHours or 0
        local age = listing.age or 0
        local damage = math.floor((listing.damage or 0) * 100)
        self.vehicleDetailsText:setText(string.format("Hours: %d | Age: %d yrs | Damage: %d%%",
            hours, age, damage))
    end

    -- Listed Price (seller's asking price)
    local listedPrice = listing.price or 0
    if self.priceText then
        self.priceText:setText(g_i18n:formatMoney(listedPrice, 0, true, true))
    end

    -- Vehicle image
    if self.vehicleImage and storeItem then
        local imagePath = storeItem.imageFilename
        if imagePath then
            self.vehicleImage:setImageFilename(imagePath)
        end
    end

    -- Update reliability displays
    local usedPlusData = listing.usedPlusData
    local engineRel = 0.5
    local hydraulicRel = 0.5
    local electricalRel = 0.5

    if usedPlusData then
        engineRel = usedPlusData.engineReliability or 1.0
        hydraulicRel = usedPlusData.hydraulicReliability or 1.0
        electricalRel = usedPlusData.electricalReliability or 1.0

        self:updateReliabilityRating("engine", engineRel)
        self:updateReliabilityRating("hydraulic", hydraulicRel)
        self:updateReliabilityRating("electrical", electricalRel)

        -- v1.4.0: Display mechanic quote based on workhorse/lemon DNA
        local quote = "Vehicle condition assessed."
        if usedPlusData.workhorseLemonScale and UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
            quote = UsedPlusMaintenance.getInspectorQuote(usedPlusData.workhorseLemonScale)
        end
        if self.mechanicQuoteText then
            self.mechanicQuoteText:setText('"' .. quote .. '"')
        end

        -- v1.9.4: Display fluid/oil assessment from mechanic
        local fluidComment = nil
        if UsedPlusMaintenance and UsedPlusMaintenance.getFluidInspectorComment then
            fluidComment = UsedPlusMaintenance.getFluidInspectorComment(usedPlusData)
        end
        if self.fluidAssessmentText and fluidComment then
            self.fluidAssessmentText:setText(fluidComment)
            -- Color based on severity (red if leaks, orange if low, green if good)
            if usedPlusData.hasOilLeak or usedPlusData.hasHydraulicLeak or usedPlusData.hasFuelLeak then
                self.fluidAssessmentText:setTextColor(1, 0.4, 0.4, 1)  -- Red for leaks
            elseif (usedPlusData.oilLevel or 1) < 0.5 or (usedPlusData.hydraulicFluidLevel or 1) < 0.5 then
                self.fluidAssessmentText:setTextColor(1, 0.7, 0.3, 1)  -- Orange for low
            else
                self.fluidAssessmentText:setTextColor(0.7, 0.9, 0.7, 1)  -- Light green for good
            end
        end

        -- Legacy notes elements (keep for compatibility, may be removed later)
        if self.notesText then
            self.notesText:setText("")
        end
        if self.notesText2 then
            self.notesText2:setText("")
        end
    else
        -- No inspection data - show defaults
        self:updateReliabilityRating("engine", 0.5)
        self:updateReliabilityRating("hydraulic", 0.5)
        self:updateReliabilityRating("electrical", 0.5)

        if self.mechanicQuoteText then
            self.mechanicQuoteText:setText('"' .. g_i18n:getText("usedplus_inspection_noData") .. '"')
        end
    end

    -- v2.1.2: Integrate RVB parts INTO mechanical assessment (not separate section)
    -- If RVB data exists, show detailed breakdown under Engine/Electrical
    self:displayIntegratedRVBData(listing)

    -- v2.1.0: Display tire conditions if data exists
    self:displayTireConditions(listing)

    -- Calculate overall condition and costs
    local avgReliability = (engineRel + hydraulicRel + electricalRel) / 3
    local overallPercent = math.floor(avgReliability * 100)

    -- Overall rating
    if self.overallRatingText then
        self.overallRatingText:setText(string.format("%d%%", overallPercent))
        if avgReliability >= 0.7 then
            self.overallRatingText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif avgReliability >= 0.5 then
            self.overallRatingText:setTextColor(1, 0.85, 0.2, 1)  -- Gold
        else
            self.overallRatingText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        end
    end

    -- Estimated repair cost (based on reliability deficit)
    local repairDeficit = 1.0 - avgReliability
    local basePrice = storeItem and storeItem.price or listedPrice * 1.5
    local estimatedRepairCost = math.floor(basePrice * repairDeficit * 0.15)  -- ~15% of new price per 100% damage

    if self.repairCostText then
        self.repairCostText:setText(g_i18n:formatMoney(estimatedRepairCost, 0, true, true))
    end

    -- Post-repair value estimate
    local postRepairValue = math.floor(listedPrice + (estimatedRepairCost * 0.5))  -- Repairs add ~50% of their cost to value
    if self.postRepairValueText then
        self.postRepairValueText:setText(g_i18n:formatMoney(postRepairValue, 0, true, true))
    end

    -- Generate recommendation based on overall condition
    if self.recommendationText then
        if avgReliability >= 0.75 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_excellent"))
            self.recommendationText:setTextColor(0.4, 1, 0.5, 1)
        elseif avgReliability >= 0.6 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_good"))
            self.recommendationText:setTextColor(0.8, 1, 0.7, 1)
        elseif avgReliability >= 0.45 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_fair"))
            self.recommendationText:setTextColor(1, 0.85, 0.4, 1)
        else
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_poor"))
            self.recommendationText:setTextColor(1, 0.5, 0.4, 1)
        end
    end
end

--[[
    Update a single reliability rating display
    @param componentType - "engine", "hydraulic", or "electrical"
    @param reliability - 0.0 to 1.0
]]
function InspectionReportDialog:updateReliabilityRating(componentType, reliability)
    local percentage = math.floor(reliability * 100)

    -- Get rating text (safely handle if function doesn't exist)
    local ratingText = "Unknown"
    if UsedPlusMaintenance and UsedPlusMaintenance.getRatingText then
        ratingText = UsedPlusMaintenance.getRatingText(reliability)
    elseif reliability >= 0.75 then
        ratingText = "Excellent"
    elseif reliability >= 0.6 then
        ratingText = "Good"
    elseif reliability >= 0.45 then
        ratingText = "Fair"
    elseif reliability >= 0.3 then
        ratingText = "Poor"
    else
        ratingText = "Critical"
    end

    -- Determine color based on rating
    local r, g, b = 1, 1, 1
    if reliability >= 0.7 then
        r, g, b = 0.3, 1, 0.4  -- Green
    elseif reliability >= 0.5 then
        r, g, b = 1, 0.85, 0.2  -- Gold
    elseif reliability >= 0.35 then
        r, g, b = 1, 0.6, 0.3  -- Orange
    else
        r, g, b = 1, 0.4, 0.4  -- Red
    end

    -- Update percentage text
    local percentElement = self[componentType .. "RatingText"]
    if percentElement then
        percentElement:setText(string.format("%d%%", percentage))
        percentElement:setTextColor(r, g, b, 1)
    end

    -- Update status text (separate element)
    local statusElement = self[componentType .. "StatusText"]
    if statusElement then
        statusElement:setText(ratingText)
        statusElement:setTextColor(r, g, b, 1)
    end
end

--[[
    Calculate inspection cost
    Base $200 + 1% of vehicle price, capped at $2000
]]
function InspectionReportDialog.calculateInspectionCost(vehiclePrice)
    local baseCost = UsedPlusMaintenance.CONFIG.inspectionCostBase or 200
    local percentCost = (vehiclePrice or 0) * (UsedPlusMaintenance.CONFIG.inspectionCostPercent or 0.01)
    local totalCost = baseCost + percentCost
    return math.min(totalCost, 2000)
end

--[[
    Close this dialog
]]
function InspectionReportDialog:close()
    g_gui:closeDialogByName("InspectionReportDialog")
end

--[[
    Button handler: Purchase - buy the vehicle
]]
function InspectionReportDialog:onClickBuy()
    UsedPlus.logDebug("InspectionReportDialog: onClickBuy called")

    local listing = self.listing
    local callback = self.onPurchaseCallback
    local target = self.callbackTarget

    self:close()

    UsedPlus.logDebug(string.format("InspectionReportDialog: callback=%s, target=%s, listing=%s",
        tostring(callback), tostring(target), tostring(listing and listing.storeItemName)))

    if callback then
        if target then
            UsedPlus.logDebug("InspectionReportDialog: Calling callback with target")
            callback(target, true, listing)
        else
            UsedPlus.logDebug("InspectionReportDialog: Calling callback without target")
            callback(true, listing)
        end
    else
        UsedPlus.logWarn("InspectionReportDialog: No callback set!")
    end
end

--[[
    Button handler: Decline - reject the offer entirely
]]
function InspectionReportDialog:onClickDecline()
    UsedPlus.logDebug("InspectionReportDialog: onClickDecline called")
    self:close()

    if self.onPurchaseCallback then
        if self.callbackTarget then
            self.onPurchaseCallback(self.callbackTarget, false, self.listing)
        else
            self.onPurchaseCallback(false, self.listing)
        end
    end
end

--[[
    Button handler: Go Back - return to UsedVehiclePreviewDialog
]]
function InspectionReportDialog:onClickGoBack()
    UsedPlus.logDebug("InspectionReportDialog: onClickGoBack called")

    local listing = self.listing
    local farmId = self.farmId
    local callback = self.originalPurchaseCallback
    local target = self.originalCallbackTarget

    self:close()

    -- Re-show the preview dialog
    local previewDialog = UsedVehiclePreviewDialog.getInstance()
    previewDialog:show(listing, farmId, callback, target)
end

--[[
    Handle ESC key - same as Go Back
]]
function InspectionReportDialog:onClickBack()
    self:onClickGoBack()
end

--[[
    Legacy handler for old XML
]]
function InspectionReportDialog:onClickCancel()
    self:onClickDecline()
end

--[[
    v2.1.2: Display INTEGRATED RVB data within Mechanical Assessment
    Instead of a separate section, shows RVB parts as sub-components under Engine/Electrical

    Layout when RVB data exists:
    - Engine section shows: Engine Core, Thermostat
    - Electrical section shows: Generator, Battery, Starter, Glow Plug
    - Hydraulic remains as-is (RVB doesn't track it)

    The main Engine/Hydraulic/Electrical percentages are now DERIVED from RVB parts
    (see UsedVehicleManager.generateUsedVehicleListingFromData)
]]
function InspectionReportDialog:displayIntegratedRVBData(listing)
    local rvbData = listing.rvbPartsData
    local hasRvbData = rvbData ~= nil and next(rvbData) ~= nil

    -- Hide the old separate RVB section (if it exists in XML)
    if self.rvbSectionContainer then
        self.rvbSectionContainer:setVisible(false)
    end

    -- Show/hide the integrated sub-component elements
    if self.engineSubComponentsContainer then
        self.engineSubComponentsContainer:setVisible(hasRvbData)
    end
    if self.electricalSubComponentsContainer then
        self.electricalSubComponentsContainer:setVisible(hasRvbData)
    end

    if not hasRvbData then
        return
    end

    -- Display Engine sub-components (Engine Core + Thermostat)
    local engineParts = {
        { key = "ENGINE", element = "engineCoreText", label = "engineCoreLabel" },
        { key = "THERMOSTAT", element = "thermostatText", label = "thermostatLabel" }
    }
    for _, part in ipairs(engineParts) do
        local element = self[part.element]
        if element then
            local partData = rvbData[part.key]
            if partData then
                local life = partData.life or 1.0
                local lifePercent = math.floor(life * 100)
                local r, g, b = self:getConditionColor(life)
                element:setText(string.format("%d%%", lifePercent))
                element:setTextColor(r, g, b, 1)
            else
                element:setText("--")
                element:setTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    -- Display Electrical sub-components (Generator, Battery, Starter, Glow Plug)
    local electricalParts = {
        { key = "GENERATOR", element = "generatorText" },
        { key = "BATTERY", element = "batteryText" },
        { key = "SELFSTARTER", element = "starterText" },
        { key = "GLOWPLUG", element = "glowPlugText" }
    }
    for _, part in ipairs(electricalParts) do
        local element = self[part.element]
        if element then
            local partData = rvbData[part.key]
            if partData then
                local life = partData.life or 1.0
                local lifePercent = math.floor(life * 100)
                local r, g, b = self:getConditionColor(life)
                element:setText(string.format("%d%%", lifePercent))
                element:setTextColor(r, g, b, 1)
            else
                element:setText("--")
                element:setTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    UsedPlus.logDebug("InspectionReportDialog: Displayed integrated RVB component data")
end

--[[
    DEPRECATED: Old separate RVB section display
    Kept for backwards compatibility but now hidden - use displayIntegratedRVBData instead
]]
function InspectionReportDialog:displayRVBPartsData(listing)
    -- Redirect to integrated display
    self:displayIntegratedRVBData(listing)
end

--[[
    v2.1.0: Display tire conditions
    Shows per-wheel conditions when tireConditions exists in listing
]]
function InspectionReportDialog:displayTireConditions(listing)
    -- Check if listing has tire data
    local tireData = listing.tireConditions
    local hasTireData = tireData ~= nil and (tireData.FL or tireData.FR or tireData.RL or tireData.RR)

    -- Toggle visibility of tire section
    if self.tireSectionContainer then
        self.tireSectionContainer:setVisible(hasTireData)
    end

    if not hasTireData then
        return
    end

    -- Display each tire
    local tireElements = {
        { key = "FL", element = "tireFLText" },
        { key = "FR", element = "tireFRText" },
        { key = "RL", element = "tireRLText" },
        { key = "RR", element = "tireRRText" }
    }

    local worstCondition = 1.0
    local worstTire = nil

    for _, tireInfo in ipairs(tireElements) do
        local element = self[tireInfo.element]
        if element then
            local condition = tireData[tireInfo.key] or 1.0
            local conditionPercent = math.floor(condition * 100)
            local r, g, b = self:getConditionColor(condition)

            element:setText(string.format("%d%%", conditionPercent))
            element:setTextColor(r, g, b, 1)

            if condition < worstCondition then
                worstCondition = condition
                worstTire = tireInfo.key
            end
        end
    end

    -- Display worst tire indicator
    if self.tireWorstText and worstTire then
        local worstPercent = math.floor(worstCondition * 100)
        local r, g, b = self:getConditionColor(worstCondition)
        self.tireWorstText:setText(string.format("%s: %d%%", worstTire, worstPercent))
        self.tireWorstText:setTextColor(r, g, b, 1)
    end

    UsedPlus.logDebug("InspectionReportDialog: Displayed tire conditions")
end

--[[
    Helper: Get color based on condition value
    Green (good) -> Yellow -> Orange -> Red (critical)
]]
function InspectionReportDialog:getConditionColor(condition)
    if condition >= 0.75 then
        return 0.3, 1, 0.4  -- Green
    elseif condition >= 0.50 then
        return 1, 0.85, 0.2  -- Gold/Yellow
    elseif condition >= 0.30 then
        return 1, 0.6, 0.3  -- Orange
    else
        return 1, 0.4, 0.4  -- Red
    end
end

UsedPlus.logInfo("InspectionReportDialog loaded (v2.1.0 - RVB/UYT holistic inspection)")
