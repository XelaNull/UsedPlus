--[[
    FS25_UsedPlus - Search Expired Dialog

    Popup shown when an agent search's term has ended.
    Offers player the option to renew the search or dismiss.

    Pattern from: LeaseRenewalDialog
]]

SearchExpiredDialog = {}
local SearchExpiredDialog_mt = Class(SearchExpiredDialog, MessageDialog)

SearchExpiredDialog.CONTROLS = {
    "titleText",
    "vehicleNameText",
    "vehicleImage",  -- v2.1.2: Added vehicle preview image
    "searchTierText",
    "qualityTierText",
    "durationText",
    "resultsText",
    "renewCostText",
    "renewButton",
    "closeButton"
}

--[[
    Constructor
]]
function SearchExpiredDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or SearchExpiredDialog_mt)
    self.isLoaded = false

    -- Search data
    self.searchData = nil
    self.foundCount = 0
    self.renewCost = 0
    self.callback = nil

    return self
end

--[[
    Set data for the dialog (called by DialogLoader)
    @param searchData - The completed search
    @param foundCount - Number of vehicles found
    @param renewCost - Cost to renew the search
    @param callback - Function(renewChoice) called on close, true if renewing
]]
function SearchExpiredDialog:setData(searchData, foundCount, renewCost, callback)
    self.searchData = searchData
    self.foundCount = foundCount or 0
    self.renewCost = renewCost or 0
    self.callback = callback

    UsedPlus.logDebug(string.format("SearchExpiredDialog:setData - %s, %d found, $%d renewal",
        searchData and searchData.id or "nil", self.foundCount, self.renewCost))
end

--[[
    onOpen callback
]]
function SearchExpiredDialog:onOpen()
    SearchExpiredDialog:superClass().onOpen(self)

    -- Assign controls and update display
    self:assignControls()
    self:updateDisplay()
end

--[[
    Assign control elements from XML
]]
function SearchExpiredDialog:assignControls()
    for _, name in pairs(SearchExpiredDialog.CONTROLS) do
        if self[name] == nil then
            self[name] = self.target and self.target[name]
        end
    end
end

--[[
    Static show method - uses DialogLoader for proper instance management
    @param searchData - The completed search
    @param foundCount - Number of vehicles found
    @param renewCost - Cost to renew the search
    @param callback - Function(renewChoice) called on close
]]
function SearchExpiredDialog.showWithData(searchData, foundCount, renewCost, callback)
    -- Use DialogLoader for consistent instance management
    -- setData is called first, then onOpen triggers updateDisplay
    return DialogLoader.show("SearchExpiredDialog", "setData", searchData, foundCount, renewCost, callback)
end

--[[
    Update display with current data
    v2.1.2: Fixed property names (searchLevel not tier, qualityLevel not qualityTier)
            Added vehicle preview image
]]
function SearchExpiredDialog:updateDisplay()
    if self.searchData == nil then
        return
    end

    local search = self.searchData

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(search.storeItemName or "Unknown Vehicle")
    end

    -- v2.1.2: Vehicle preview image
    if self.vehicleImage then
        local storeItem = g_storeManager:getItemByXMLFilename(search.storeItemIndex)
        if storeItem and storeItem.imageFilename then
            self.vehicleImage:setImageFilename(storeItem.imageFilename)
            self.vehicleImage:setVisible(true)
        else
            self.vehicleImage:setVisible(false)
        end
    end

    -- Search tier (FIXED: search.searchLevel not search.tier)
    if self.searchTierText then
        local tierInfo = UsedVehicleSearch.SEARCH_TIERS[search.searchLevel] or {}
        self.searchTierText:setText(tierInfo.name or "Unknown")
    end

    -- Quality tier (FIXED: search.qualityLevel not search.qualityTier)
    if self.qualityTierText then
        local qualityInfo = UsedVehicleSearch.QUALITY_TIERS[search.qualityLevel] or {}
        self.qualityTierText:setText(qualityInfo.name or "Any")
    end

    -- Duration (FIXED: search.searchLevel not search.tier)
    if self.durationText then
        local tierInfo = UsedVehicleSearch.SEARCH_TIERS[search.searchLevel] or {}
        local months = tierInfo.maxMonths or 1
        self.durationText:setText(string.format("%d month%s", months, months == 1 and "" or "s"))
    end

    -- Results
    if self.resultsText then
        if self.foundCount > 0 then
            self.resultsText:setText(string.format("%d vehicle%s found", self.foundCount, self.foundCount == 1 and "" or "s"))
            self.resultsText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        else
            self.resultsText:setText("No vehicles found")
            self.resultsText:setTextColor(1, 0.6, 0.4, 1)  -- Orange/red
        end
    end

    -- Renew cost
    if self.renewCostText then
        self.renewCostText:setText(g_i18n:formatMoney(self.renewCost, 0, true, true))
    end
end

--[[
    Renew button clicked
]]
function SearchExpiredDialog:onClickRenew()
    -- Check if player has enough money
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if farm.money < self.renewCost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Insufficient funds to renew search."
        )
        return
    end

    -- Close dialog
    self:close()

    -- Callback with renew choice
    if self.callback then
        self.callback(true)
    end
end

--[[
    Close/Dismiss button clicked
]]
function SearchExpiredDialog:onClickClose()
    self:close()

    -- Callback with no renew
    if self.callback then
        self.callback(false)
    end
end

--[[
    Close the dialog
]]
function SearchExpiredDialog:close()
    g_gui:closeDialogByName("SearchExpiredDialog")
end

UsedPlus.logInfo("SearchExpiredDialog loaded")
