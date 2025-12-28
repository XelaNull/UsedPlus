--[[
    FS25_UsedPlus - Sale Listing Initiated Confirmation Dialog

    Styled dialog showing sale listing details after agent is hired.
    Matches styling of SearchInitiatedDialog.

    Shows:
    - Vehicle being sold
    - Agent type (Private/Local/Regional/National)
    - Agent fee charged
    - Expected asking price range
    - Expected sale timeline
]]

SaleListingInitiatedDialog = {}
local SaleListingInitiatedDialog_mt = Class(SaleListingInitiatedDialog, ScreenElement)

-- Static instance
SaleListingInitiatedDialog.instance = nil
SaleListingInitiatedDialog.xmlPath = nil

--[[
    Get or create dialog instance
]]
function SaleListingInitiatedDialog.getInstance()
    if SaleListingInitiatedDialog.instance == nil then
        if SaleListingInitiatedDialog.xmlPath == nil then
            SaleListingInitiatedDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/SaleListingInitiatedDialog.xml"
        end

        SaleListingInitiatedDialog.instance = SaleListingInitiatedDialog.new()
        g_gui:loadGui(SaleListingInitiatedDialog.xmlPath, "SaleListingInitiatedDialog", SaleListingInitiatedDialog.instance)

        UsedPlus.logDebug("SaleListingInitiatedDialog created and loaded")
    end

    return SaleListingInitiatedDialog.instance
end

--[[
    Constructor
]]
function SaleListingInitiatedDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SaleListingInitiatedDialog_mt)
    self.isBackAllowed = true
    return self
end

--[[
    Called when dialog is created
]]
function SaleListingInitiatedDialog:onCreate()
    -- No superclass call needed for ScreenElement
end

--[[
    Show dialog with sale listing details
    @param details - Table with listing details:
        vehicleName     - Name of the vehicle being sold
        agentName       - Agent type name (e.g., "Regional Agent")
        agentFee        - Fee paid to agent (0 for Private Sale)
        isPrivateSale   - Boolean, true if no agent (Private Sale)
        priceTierName   - Price tier name (e.g., "Market Price")
        minPrice        - Minimum expected price
        maxPrice        - Maximum expected price
        minMonths       - Minimum months to sell
        maxMonths       - Maximum months to sell
        successRate     - Expected success rate (0-1)
]]
function SaleListingInitiatedDialog:show(details)
    if details == nil then
        UsedPlus.logError("SaleListingInitiatedDialog:show called with nil details")
        return
    end

    -- Populate fields
    self:updateDisplay(details)

    -- Show the dialog
    g_gui:showDialog("SaleListingInitiatedDialog")
end

--[[
    Static convenience method to show dialog
    Can be called without getting instance first
]]
function SaleListingInitiatedDialog.showWithDetails(details)
    local dialog = SaleListingInitiatedDialog.getInstance()
    if dialog then
        dialog:show(details)
    end
end

--[[
    Update all display fields
]]
function SaleListingInitiatedDialog:updateDisplay(details)
    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(details.vehicleName or "Unknown Vehicle")
    end

    -- Agent type
    if self.agentTypeText then
        self.agentTypeText:setText(details.agentName or "Agent")
    end

    -- Agent fee (or "No Fee" for Private Sale)
    if self.agentFeeText then
        if details.isPrivateSale or details.agentFee == 0 then
            self.agentFeeText:setText("No Fee")
            self.agentFeeText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        else
            local feeStr = g_i18n:formatMoney(details.agentFee, 0, true, true)
            self.agentFeeText:setText(feeStr)
            self.agentFeeText:setTextColor(1, 0.5, 0.4, 1)  -- Red/orange
        end
    end

    -- Price tier
    if self.priceTierText then
        self.priceTierText:setText(details.priceTierName or "Market Price")
    end

    -- Expected price range
    if self.priceRangeText then
        local minPrice = details.minPrice or 0
        local maxPrice = details.maxPrice or 0
        local minStr = g_i18n:formatMoney(minPrice, 0, true, true)
        local maxStr = g_i18n:formatMoney(maxPrice, 0, true, true)
        self.priceRangeText:setText(string.format("%s - %s", minStr, maxStr))
    end

    -- Expected timeline
    if self.timelineText then
        local minMonths = details.minMonths or 1
        local maxMonths = details.maxMonths or 3
        if minMonths == maxMonths then
            self.timelineText:setText(string.format("%d month(s)", minMonths))
        else
            self.timelineText:setText(string.format("%d - %d months", minMonths, maxMonths))
        end
    end

    -- Success rate
    if self.successRateText then
        local successRate = details.successRate or 0.85
        local successPct = math.floor(successRate * 100)
        self.successRateText:setText(string.format("%d%%", successPct))

        -- Color code based on success rate
        if successRate >= 0.80 then
            self.successRateText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif successRate >= 0.60 then
            self.successRateText:setTextColor(0.9, 0.9, 0.3, 1)  -- Yellow
        else
            self.successRateText:setTextColor(1, 0.6, 0.3, 1)  -- Orange
        end
    end
end

--[[
    Handle OK button click
]]
function SaleListingInitiatedDialog:onClickOk()
    g_gui:changeScreen(nil)
end

--[[
    Handle ESC key / back button
]]
function SaleListingInitiatedDialog:onClickBack()
    g_gui:changeScreen(nil)
    return true
end

--[[
    Called when dialog opens
]]
function SaleListingInitiatedDialog:onOpen()
    SaleListingInitiatedDialog:superClass().onOpen(self)
end

--[[
    Called when dialog closes
]]
function SaleListingInitiatedDialog:onClose()
    SaleListingInitiatedDialog:superClass().onClose(self)
end

UsedPlus.logInfo("SaleListingInitiatedDialog loaded")
