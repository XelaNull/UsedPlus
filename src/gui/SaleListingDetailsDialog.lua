--[[
    SaleListingDetailsDialog.lua
    Dialog showing comprehensive details about a vehicle sale listing

    Displays:
    - Vehicle info and condition
    - Agent tier and fee details
    - Price tier and expected range
    - Value comparison (vs vanilla sell, trade-in)
    - Offer history
]]

SaleListingDetailsDialog = {}
-- Use ScreenElement, NOT MessageDialog (MessageDialog lacks registerControls)
local SaleListingDetailsDialog_mt = Class(SaleListingDetailsDialog, ScreenElement)

-- Static instance
SaleListingDetailsDialog.instance = nil
SaleListingDetailsDialog.xmlPath = nil

--[[
    Get or create dialog instance
]]
function SaleListingDetailsDialog.getInstance()
    if SaleListingDetailsDialog.instance == nil then
        if SaleListingDetailsDialog.xmlPath == nil then
            SaleListingDetailsDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/SaleListingDetailsDialog.xml"
        end

        SaleListingDetailsDialog.instance = SaleListingDetailsDialog.new()
        g_gui:loadGui(SaleListingDetailsDialog.xmlPath, "SaleListingDetailsDialog", SaleListingDetailsDialog.instance)
    end

    return SaleListingDetailsDialog.instance
end

--[[
    Constructor
]]
function SaleListingDetailsDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SaleListingDetailsDialog_mt)

    self.listing = nil
    self.isBackAllowed = true

    return self
end

--[[
    Called when dialog is created
]]
function SaleListingDetailsDialog:onCreate()
    -- No superclass call needed for ScreenElement
end

--[[
    Show dialog with listing information
    @param listing - VehicleSaleListing object
]]
function SaleListingDetailsDialog:show(listing)
    if listing == nil then
        UsedPlus.logError("SaleListingDetailsDialog:show called with nil listing")
        return
    end

    self.listing = listing

    -- Populate all fields
    self:updateDisplay()

    -- Show the dialog
    g_gui:showDialog("SaleListingDetailsDialog")
end

--[[
    Update all display fields with listing data
    Uses UIHelper for consistent styling across UsedPlus dialogs
]]
function SaleListingDetailsDialog:updateDisplay()
    if self.listing == nil then return end

    local listing = self.listing

    -- Vehicle Info
    UIHelper.Element.setText(self.vehicleNameText, listing.vehicleName or "Unknown Vehicle")

    if self.conditionText then
        local repairPct = listing.repairPercent or 100
        local paintPct = listing.paintPercent or 100
        self.conditionText:setText(string.format("%d%% / %d%%", repairPct, paintPct))

        -- Color based on condition (green if good, gold if fair, red if poor)
        local avgCondition = (repairPct + paintPct) / 2
        if avgCondition >= 80 then
            self.conditionText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif avgCondition >= 50 then
            self.conditionText:setTextColor(1, 0.85, 0.2, 1)  -- Gold
        else
            self.conditionText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        end
    end

    UIHelper.Element.setText(self.hoursText, tostring(listing.operatingHours or 0))

    -- Status with dynamic coloring
    if self.statusText then
        local statusText = listing:getStatusText()
        self.statusText:setText(statusText)

        -- Color based on status
        if listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
            self.statusText:setTextColor(0.3, 1, 0.4, 1)  -- Green - offer ready!
        elseif listing.status == VehicleSaleListing.STATUS.ACTIVE then
            self.statusText:setTextColor(1, 0.85, 0.2, 1)  -- Gold - searching
        elseif listing.status == VehicleSaleListing.STATUS.SOLD then
            self.statusText:setTextColor(0.3, 1, 0.4, 1)  -- Green - sold
        elseif listing.status == VehicleSaleListing.STATUS.EXPIRED then
            self.statusText:setTextColor(1, 0.4, 0.4, 1)  -- Red - expired
        else
            self.statusText:setTextColor(0.7, 0.7, 0.7, 1)
        end
    end

    UIHelper.Element.setText(self.timeRemainingText, listing:getRemainingTime())

    -- Agent Tier
    local agentTier = listing:getAgentTierConfig()
    UIHelper.Element.setText(self.agentTierText, agentTier.name or "Unknown")

    if self.agentFeeText then
        local feePercent = (agentTier.feePercent or 0) * 100
        if feePercent == 0 then
            UIHelper.Element.setTextWithColor(self.agentFeeText, "No Fee", UIHelper.Colors.MONEY_GREEN)
        else
            self.agentFeeText:setText(string.format("%s (%.0f%%)",
                UIHelper.Text.formatMoney(listing.agentFee or 0), feePercent))
        end
    end

    if self.baseSuccessText then
        local baseSuccess = (agentTier.baseSuccessRate or 0) * 100
        self.baseSuccessText:setText(string.format("%.0f%%", baseSuccess))
        -- Color based on success rate
        if baseSuccess >= 85 then
            self.baseSuccessText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif baseSuccess >= 70 then
            self.baseSuccessText:setTextColor(1, 0.85, 0.2, 1)  -- Gold
        else
            self.baseSuccessText:setTextColor(1, 0.6, 0.2, 1)  -- Orange
        end
    end

    -- Price Tier
    local priceTier = listing:getPriceTierConfig()
    UIHelper.Element.setText(self.priceTierText, priceTier.name or "Unknown")

    if self.priceRangeText then
        self.priceRangeText:setText(UIHelper.Text.formatRange(
            listing.expectedMinPrice or 0,
            listing.expectedMaxPrice or 0))
    end

    if self.successModText then
        local successMod = (priceTier.successModifier or 0) * 100
        local modText = string.format("%+.0f%%", successMod)
        self.successModText:setText(modText)

        -- Color: green if positive, red if negative, white if zero
        if successMod > 0 then
            self.successModText:setTextColor(0.3, 1, 0.4, 1)
        elseif successMod < 0 then
            self.successModText:setTextColor(1, 0.4, 0.4, 1)
        else
            self.successModText:setTextColor(0.7, 0.7, 0.7, 1)
        end
    end

    -- Value Comparison
    local vanillaSell = listing.vanillaSellPrice or 0
    UIHelper.Element.setText(self.vanillaSellText, UIHelper.Text.formatMoney(vanillaSell))

    if self.tradeInValueText then
        -- Trade-in is roughly 50-65% of vanilla
        local tradeInEstimate = math.floor(vanillaSell * 0.575)  -- Midpoint of 50-65%
        self.tradeInValueText:setText(UIHelper.Text.formatMoney(tradeInEstimate))
    end

    -- Expected value (midpoint of range)
    local expectedMid = math.floor(((listing.expectedMinPrice or 0) + (listing.expectedMaxPrice or 0)) / 2)
    UIHelper.Element.setText(self.expectedValueText, UIHelper.Text.formatMoney(expectedMid))

    -- Bonus vs vanilla
    if self.bonusVsVanillaText then
        local bonus = expectedMid - vanillaSell
        local bonusPercent = 0
        if vanillaSell > 0 then
            bonusPercent = math.floor((bonus / vanillaSell) * 100)
        end

        if bonus >= 0 then
            self.bonusVsVanillaText:setText(string.format("+%s (+%d%%)",
                UIHelper.Text.formatMoney(bonus), bonusPercent))
            self.bonusVsVanillaText:setTextColor(0.4, 1, 0.5, 1)  -- Bright green
        else
            self.bonusVsVanillaText:setText(string.format("%s (%d%%)",
                UIHelper.Text.formatMoney(bonus), bonusPercent))
            self.bonusVsVanillaText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        end
    end

    -- Net amount (expected minus fee) - gold for emphasis
    if self.netAmountText then
        local netAmount = expectedMid - (listing.agentFee or 0)
        UIHelper.Element.setTextWithColor(self.netAmountText,
            UIHelper.Text.formatMoney(netAmount), UIHelper.Colors.GOLD)
    end

    -- Offer History
    UIHelper.Element.setText(self.offersReceivedText, tostring(listing.offersReceived or 0))
    UIHelper.Element.setText(self.offersDeclinedText, tostring(listing.offersDeclined or 0))

    if self.listedDurationText then
        local hoursElapsed = listing.hoursElapsed or 0
        self.listedDurationText:setText(UIHelper.Text.formatHours(hoursElapsed))
    end

    -- Info text - tips based on status
    if self.infoText then
        local tipText = "Higher agent tiers have wider reach but longer wait times."

        if listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
            tipText = "You have a pending offer! Accept from the Finance Manager."
        elseif listing.offersDeclined and listing.offersDeclined > 0 then
            tipText = "Declining offers reduces remaining time for new offers."
        elseif listing.priceTier == 3 then
            tipText = "Premium pricing requires patience - fewer buyers can afford it."
        elseif listing.priceTier == 1 then
            tipText = "Quick sale pricing attracts buyers fast but at a discount."
        end

        self.infoText:setText(tipText)
    end
end

--[[
    Handle close button click
]]
function SaleListingDetailsDialog:onCloseDialog()
    g_gui:closeDialogByName("SaleListingDetailsDialog")
end

--[[
    Called when dialog closes
]]
function SaleListingDetailsDialog:onClose()
    SaleListingDetailsDialog:superClass().onClose(self)
    self.listing = nil
end

UsedPlus.logInfo("SaleListingDetailsDialog loaded")
