--[[
    FS25_UsedPlus - Sell Vehicle Dialog

     Dialog for selecting agent tier AND price tier when selling a vehicle
     DUAL-TIER SYSTEM: Player chooses agent reach AND asking price separately
     Pattern from LeaseDialog.lua (MultiTextOption dropdown)

    Features:
    - Shows vehicle info and vanilla sell price
    - MultiTextOption dropdown for AGENT tier (Local/Regional/National)
    - MultiTextOption dropdown for PRICE tier (Quick/Market/Premium)
    - Combined expected price range, success rate, and time
    - Premium tier locked if vehicle condition doesn't meet requirements
    - Comparison with trade-in option
]]

SellVehicleDialog = {}
local SellVehicleDialog_mt = Class(SellVehicleDialog, MessageDialog)

-- Agent tier options (reach and timing) - mirrors VehicleSaleListing.AGENT_TIERS
-- Tier 0 = Private Sale (no agent), Tiers 1-3 = Professional agents
SellVehicleDialog.AGENT_OPTIONS = {
    {
        tier = 0,
        label = "Private Sale (3-6 mo)",
        name = "Private Sale",
        feePercent = 0.00,
        minMonths = 3,
        maxMonths = 6,
        baseSuccessRate = 0.50,
        noPremium = true,  -- Private buyers skeptical of premium pricing
    },
    {
        tier = 1,
        label = "Local Agent (1-2 mo)",
        name = "Local Agent",
        feePercent = 0.02,
        minMonths = 1,
        maxMonths = 2,
        baseSuccessRate = 0.70,
    },
    {
        tier = 2,
        label = "Regional Agent (2-4 mo)",
        name = "Regional Agent",
        feePercent = 0.04,
        minMonths = 2,
        maxMonths = 4,
        baseSuccessRate = 0.85,
    },
    {
        tier = 3,
        label = "National Agent (4-6 mo)",
        name = "National Agent",
        feePercent = 0.06,
        minMonths = 4,
        maxMonths = 6,
        baseSuccessRate = 0.95,
    }
}

-- Price tier options (asking price) - mirrors VehicleSaleListing.PRICE_TIERS
SellVehicleDialog.PRICE_OPTIONS = {
    {
        tier = 1,
        label = "Quick Sale (75-85%)",
        name = "Quick Sale",
        priceMultiplierMin = 0.75,
        priceMultiplierMax = 0.85,
        successModifier = 0.15,
        requiresCondition = 0,
        requiresPaint = 0,
    },
    {
        tier = 2,
        label = "Market Price (95-105%)",
        name = "Market Price",
        priceMultiplierMin = 0.95,
        priceMultiplierMax = 1.05,
        successModifier = 0.00,
        requiresCondition = 0,
        requiresPaint = 0,
    },
    {
        tier = 3,
        label = "Premium (115-130%)",
        name = "Premium Price",
        priceMultiplierMin = 1.15,
        priceMultiplierMax = 1.30,
        successModifier = -0.20,
        requiresCondition = 95,
        requiresPaint = 80,
    }
}

-- Legacy compatibility
SellVehicleDialog.TIER_OPTIONS = SellVehicleDialog.AGENT_OPTIONS

--[[
     Constructor
]]
function SellVehicleDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or SellVehicleDialog_mt)

    self.i18n = i18n or g_i18n

    -- Data
    self.vehicle = nil
    self.farmId = nil
    self.vanillaSellPrice = 0
    self.selectedAgentTier = 2  -- Default to Regional (index 3 in AGENT_OPTIONS)
    self.selectedPriceTier = 2  -- Default to Market
    self.selectedAgentIndex = 3 -- Index in AGENT_OPTIONS array (1=Private, 2=Local, 3=Regional, 4=National)
    self.callback = nil
    self.repairPercent = 100
    self.paintPercent = 100

    -- Legacy alias
    self.selectedTier = 2

    return self
end

--[[
     Set vehicle to sell
    @param vehicle - The vehicle object
    @param farmId - The owning farm
    @param callback - Function called with (agentTier, priceTier) on confirm, or nil on cancel
]]
function SellVehicleDialog:setVehicle(vehicle, farmId, callback)
    self.vehicle = vehicle
    self.farmId = farmId
    self.callback = callback
    self.selectedAgentTier = 2  -- Default Regional (tier value)
    self.selectedAgentIndex = 3 -- Default Regional (index in AGENT_OPTIONS: 1=Private, 2=Local, 3=Regional, 4=National)
    self.selectedPriceTier = 2  -- Default Market

    -- Get vanilla sell price
    self.vanillaSellPrice = 0
    if vehicle and vehicle.getSellPrice then
        self.vanillaSellPrice = vehicle:getSellPrice()
    end

    -- Get vehicle condition
    self.repairPercent = 100
    self.paintPercent = 100
    if TradeInCalculations then
        local damage = TradeInCalculations.getVehicleDamage(vehicle)
        local wear = TradeInCalculations.getVehicleWear(vehicle)
        self.repairPercent = math.floor((1 - damage) * 100)
        self.paintPercent = math.floor((1 - wear) * 100)
    end

    UsedPlus.logDebug(string.format("SellVehicleDialog: Set vehicle with vanilla sell price $%d, condition %d%%, paint %d%%",
        self.vanillaSellPrice, self.repairPercent, self.paintPercent))
end

--[[
     Called when dialog opens
]]
function SellVehicleDialog:onOpen()
    SellVehicleDialog:superClass().onOpen(self)

    -- Reset close guard
    self.isClosing = false

    -- Initialize agent tier dropdown
    if self.agentTierSlider then
        local agentTexts = {}
        for _, option in ipairs(SellVehicleDialog.AGENT_OPTIONS) do
            table.insert(agentTexts, option.label)
        end
        self.agentTierSlider:setTexts(agentTexts)
        self.agentTierSlider:setState(3)  -- Default to Regional (index 3: Private=1, Local=2, Regional=3, National=4)
    end

    -- Legacy support - if only tierSlider exists, use it for agent tier
    if self.tierSlider and not self.agentTierSlider then
        local agentTexts = {}
        for _, option in ipairs(SellVehicleDialog.AGENT_OPTIONS) do
            table.insert(agentTexts, option.label)
        end
        self.tierSlider:setTexts(agentTexts)
        self.tierSlider:setState(3)
        self.agentTierSlider = self.tierSlider  -- Alias for compatibility
    end

    -- Initialize price tier dropdown (with agent index for Premium check)
    self:updatePriceTierDropdown(3)  -- Default agent index is 3 (Regional)

    self:updateVehicleDisplay()
    self:updatePreview()
    self:updateComparisonDisplay()

    -- Check listing limit and show warning if at max
    self:updateListingLimitStatus()
end

--[[
     Check if farm has reached max sale listings and update UI accordingly
]]
function SellVehicleDialog:updateListingLimitStatus()
    self.canCreateListing = true
    local warningMsg = nil

    if g_vehicleSaleManager and self.farmId then
        local canCreate, currentCount, maxAllowed = g_vehicleSaleManager:canCreateListing(self.farmId)
        if not canCreate then
            self.canCreateListing = false
            warningMsg = string.format(
                g_i18n:getText("usedplus_error_maxSaleListings") or "Maximum %d vehicles can be listed for sale at once.",
                maxAllowed
            )
        end
    end

    -- Show/hide warning text
    if self.listingLimitWarningText then
        if warningMsg then
            self.listingLimitWarningText:setText(warningMsg)
            self.listingLimitWarningText:setVisible(true)
            self.listingLimitWarningText:setTextColor(1, 0.3, 0.3, 1)
        else
            self.listingLimitWarningText:setVisible(false)
        end
    end

    -- Disable confirm button if at limit
    if self.confirmButton then
        self.confirmButton:setDisabled(not self.canCreateListing)
    end
end

--[[
     Check if a price tier is available based on vehicle condition AND agent selection
     @param priceTierIndex - 1, 2, or 3
     @param agentIndex - optional, index in AGENT_OPTIONS (1=Private, 2=Local, etc.)
     @return canUse (bool), reason (string or nil)
]]
function SellVehicleDialog:canUsePriceTier(priceTierIndex, agentIndex)
    local option = SellVehicleDialog.PRICE_OPTIONS[priceTierIndex]
    if not option then
        return false, "Invalid tier"
    end

    -- Check if Private Sale blocks Premium pricing
    if agentIndex then
        local agentOption = SellVehicleDialog.AGENT_OPTIONS[agentIndex]
        if agentOption and agentOption.noPremium and priceTierIndex == 3 then
            return false, "Private buyers won't pay premium prices"
        end
    end

    if option.requiresCondition > 0 and self.repairPercent < option.requiresCondition then
        return false, string.format("Requires %d%% condition (currently %d%%)",
            option.requiresCondition, self.repairPercent)
    end

    if option.requiresPaint > 0 and self.paintPercent < option.requiresPaint then
        return false, string.format("Requires %d%% paint (currently %d%%)",
            option.requiresPaint, self.paintPercent)
    end

    return true, nil
end

--[[
     Update price tier dropdown based on current agent selection
     @param agentIndex - index in AGENT_OPTIONS (1=Private, 2=Local, 3=Regional, 4=National)
]]
function SellVehicleDialog:updatePriceTierDropdown(agentIndex)
    if not self.priceTierSlider then return end

    local currentState = self.priceTierSlider:getState()
    local priceTexts = {}

    for i, option in ipairs(SellVehicleDialog.PRICE_OPTIONS) do
        -- Check if price tier is available (considering agent selection)
        local canUse, reason = self:canUsePriceTier(i, agentIndex)
        if canUse then
            table.insert(priceTexts, option.label)
        else
            table.insert(priceTexts, option.label .. " (LOCKED)")
        end
    end

    self.priceTierSlider:setTexts(priceTexts)

    -- If current selection is now locked, reset to Market (index 2)
    local canUseCurrent = self:canUsePriceTier(currentState, agentIndex)
    if not canUseCurrent and currentState ~= 2 then
        self.priceTierSlider:setState(2)
    else
        self.priceTierSlider:setState(currentState)
    end
end

--[[
     Update vehicle info display
]]
function SellVehicleDialog:updateVehicleDisplay()
    if self.vehicle == nil then return end

    -- Get store item for name and image
    local storeItem = nil
    -- Get store item and vehicle name using consolidated utility
    if self.vehicle.configFileName then
        storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
    end
    UIHelper.Element.setText(self.vehicleNameText, UIHelper.Vehicle.getFullName(storeItem))

    -- Update vehicle image
    UIHelper.Image.setStoreItemImage(self.vehicleImage, storeItem)

    -- Update vehicle details (condition summary)
    local damage = (100 - self.repairPercent) / 100
    local wear = (100 - self.paintPercent) / 100
    if UIHelper.Vehicle and UIHelper.Vehicle.displayConditionSummary then
        UIHelper.Vehicle.displayConditionSummary(self.vehicleDetailsText, damage, wear)
    else
        UIHelper.Element.setText(self.vehicleDetailsText,
            string.format("Condition: %d%% | Paint: %d%%", self.repairPercent, self.paintPercent))
    end

    -- Update vanilla sell price (FMV baseline)
    UIHelper.Element.setText(self.vanillaPriceText,
        string.format("Fair Market Value: %s", UIHelper.Text.formatMoney(self.vanillaSellPrice)))
end

--[[
     Update preview based on selected agent tier AND price tier
]]
function SellVehicleDialog:updatePreview()
    -- Get selected agent tier (index 1=Private, 2=Local, 3=Regional, 4=National)
    local agentIndex = 3  -- Default to Regional
    if self.agentTierSlider then
        agentIndex = self.agentTierSlider:getState()
    elseif self.tierSlider then
        agentIndex = self.tierSlider:getState()
    end
    local agentOption = SellVehicleDialog.AGENT_OPTIONS[agentIndex] or SellVehicleDialog.AGENT_OPTIONS[3]
    self.selectedAgentTier = agentOption.tier
    self.selectedAgentIndex = agentIndex

    -- Get selected price tier
    local priceIndex = 2
    if self.priceTierSlider then
        priceIndex = self.priceTierSlider:getState()
    end
    local priceOption = SellVehicleDialog.PRICE_OPTIONS[priceIndex] or SellVehicleDialog.PRICE_OPTIONS[2]
    self.selectedPriceTier = priceOption.tier

    -- Check if selected price tier is available (pass agentIndex for Private Sale check)
    local canUsePriceTier, lockReason = self:canUsePriceTier(priceIndex, agentIndex)

    -- Calculate expected return range (from price tier)
    local minReturn = math.floor(self.vanillaSellPrice * priceOption.priceMultiplierMin)
    local maxReturn = math.floor(self.vanillaSellPrice * priceOption.priceMultiplierMax)

    -- Calculate agent fee (percentage of expected price from agent tier)
    -- Private Sale (tier 0) has no fee
    local expectedMid = (minReturn + maxReturn) / 2
    local agentFee = 0
    if agentOption.feePercent > 0 then
        agentFee = math.max(50, math.floor(expectedMid * agentOption.feePercent))
    end

    -- Calculate net after fee
    local netMin = minReturn - agentFee
    local netMax = maxReturn - agentFee

    -- Calculate combined success rate
    local combinedSuccess = math.max(0.10, math.min(0.98,
        agentOption.baseSuccessRate + (priceOption.successModifier or 0)))

    -- Update selected agent tier display
    UIHelper.Element.setText(self.selectedTierText,
        string.format("%s + %s", agentOption.name, priceOption.name))

    -- Update expected return range
    UIHelper.Element.setText(self.expectedRangeText,
        UIHelper.Text.formatRange(minReturn, maxReturn))

    -- Update return percent range
    UIHelper.Element.setText(self.returnPercentText,
        UIHelper.Text.formatPercentRange(priceOption.priceMultiplierMin, priceOption.priceMultiplierMax))

    -- Update agent fee (show "No Fee" for Private Sale)
    if agentFee == 0 then
        UIHelper.Element.setTextWithColor(self.selectedFeeText, "No Fee", UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setText(self.selectedFeeText,
            string.format("%s (%.0f%%)", UIHelper.Text.formatMoney(agentFee), agentOption.feePercent * 100))
    end

    -- Update expected time (from agent tier, in months)
    UIHelper.Element.setText(self.expectedTimeText,
        string.format("%d-%d months", agentOption.minMonths, agentOption.maxMonths))

    -- Update success rate display (if element exists)
    if self.successRateText then
        UIHelper.Element.setText(self.successRateText, string.format("%.0f%%", combinedSuccess * 100))
        -- Color code based on success rate
        if combinedSuccess >= 0.80 then
            self.successRateText:setTextColor(0.3, 0.9, 0.3, 1)  -- Green
        elseif combinedSuccess >= 0.60 then
            self.successRateText:setTextColor(0.9, 0.9, 0.3, 1)  -- Yellow
        else
            self.successRateText:setTextColor(0.9, 0.5, 0.3, 1)  -- Orange
        end
    end

    -- Update net after fee (green - money you'll receive)
    if canUsePriceTier then
        UIHelper.Element.setTextWithColor(self.netAfterFeeText,
            UIHelper.Text.formatRange(netMin, netMax),
            UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setTextWithColor(self.netAfterFeeText,
            lockReason or "Unavailable",
            UIHelper.Colors.WARNING_RED or {1, 0.4, 0.3, 1})
    end

    -- Update lock warning if present
    if self.lockWarningText then
        if canUsePriceTier then
            UIHelper.Element.setText(self.lockWarningText, "")
            self.lockWarningText:setVisible(false)
        else
            UIHelper.Element.setText(self.lockWarningText, lockReason)
            self.lockWarningText:setVisible(true)
        end
    end
end

--[[
     Update comparison display (trade-in alternative only)
     Note: Vanilla instant sell removed from display since it's disabled
]]
function SellVehicleDialog:updateComparisonDisplay()
    -- Trade-in comparison (50-65% of vanilla sell)
    local tradeInMin = math.floor(self.vanillaSellPrice * 0.50)
    local tradeInMax = math.floor(self.vanillaSellPrice * 0.65)
    UIHelper.Element.setText(self.tradeInCompareText,
        string.format("%s - %s (50-65%%)",
            UIHelper.Text.formatMoney(tradeInMin),
            UIHelper.Text.formatMoney(tradeInMax)))
end

--[[
     Callback when agent tier dropdown changes
]]
function SellVehicleDialog:onAgentTierChanged()
    -- Get new agent index and refresh price tier dropdown (may lock/unlock Premium)
    local agentIndex = 3
    if self.agentTierSlider then
        agentIndex = self.agentTierSlider:getState()
    elseif self.tierSlider then
        agentIndex = self.tierSlider:getState()
    end

    self:updatePriceTierDropdown(agentIndex)
    self:updatePreview()
end

--[[
     Callback when price tier dropdown changes
]]
function SellVehicleDialog:onPriceTierChanged()
    self:updatePreview()
end

--[[
     Legacy callback (for old tierSlider)
]]
function SellVehicleDialog:onTierChanged()
    self:updatePreview()
end

--[[
     Handle confirm button click
]]
function SellVehicleDialog:onClickConfirm()
    -- Check listing limit first (backup check)
    if g_vehicleSaleManager and self.farmId then
        local canCreate, currentCount, maxAllowed = g_vehicleSaleManager:canCreateListing(self.farmId)
        if not canCreate then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                string.format(g_i18n:getText("usedplus_error_maxSaleListings") or "Maximum %d vehicles can be listed for sale at once.", maxAllowed)
            )
            return
        end
    end

    -- Get selected agent tier (index 1=Private, 2=Local, 3=Regional, 4=National)
    local agentIndex = 3  -- Default to Regional
    if self.agentTierSlider then
        agentIndex = self.agentTierSlider:getState()
    elseif self.tierSlider then
        agentIndex = self.tierSlider:getState()
    end
    local agentOption = SellVehicleDialog.AGENT_OPTIONS[agentIndex]

    -- Get selected price tier
    local priceIndex = 2
    if self.priceTierSlider then
        priceIndex = self.priceTierSlider:getState()
    end
    local priceOption = SellVehicleDialog.PRICE_OPTIONS[priceIndex]

    if not agentOption or not priceOption then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Please select a sales option and price tier."
        )
        return
    end

    -- Check if price tier is available (pass agentIndex for Private Sale check)
    local canUsePriceTier, lockReason = self:canUsePriceTier(priceIndex, agentIndex)
    if not canUsePriceTier then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            lockReason or "Premium pricing requires better vehicle condition."
        )
        return
    end

    -- Calculate agent fee (Private Sale has no fee)
    local minReturn = math.floor(self.vanillaSellPrice * priceOption.priceMultiplierMin)
    local maxReturn = math.floor(self.vanillaSellPrice * priceOption.priceMultiplierMax)
    local expectedMid = (minReturn + maxReturn) / 2
    local agentFee = 0
    if agentOption.feePercent > 0 then
        agentFee = math.max(50, math.floor(expectedMid * agentOption.feePercent))
    end

    -- Check if farm has enough money for agent fee (skip if no fee)
    if agentFee > 0 then
        local farm = g_farmManager:getFarmById(self.farmId)
        if farm and farm.money < agentFee then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format("Insufficient funds. Agent fee: %s",
                    UIHelper.Text.formatMoney(agentFee))
            )
            return
        end
    end

    -- Call callback with BOTH selected tiers
    if self.callback then
        self.callback(agentOption.tier, priceOption.tier)
    end

    UsedPlus.logDebug(string.format("Confirmed %s + %s (Agent %d, Price %d)",
        agentOption.name, priceOption.name, agentOption.tier, priceOption.tier))
    self:close()
end

--[[
     Handle cancel button click
]]
function SellVehicleDialog:onClickCancel()
    -- Call callback with nil to indicate cancel
    if self.callback then
        self.callback(nil, nil)
    end

    UsedPlus.logDebug("Sell dialog cancelled")
    self:close()
end

--[[
     Override close() to properly close through g_gui
     This ensures ESC key and all close paths properly decrement dialog count
]]
function SellVehicleDialog:close()
    -- Guard against multiple close calls (closeDialogByName may call back to close)
    if self.isClosing then
        return
    end
    self.isClosing = true

    UsedPlus.logDebug(">>> SellVehicleDialog:close() calling closeDialogByName <<<")

    -- Use closeDialogByName - this properly decrements the dialog count
    g_gui:closeDialogByName("SellVehicleDialog")

    -- Log final state
    if VehicleSellingPointExtension and VehicleSellingPointExtension.logGuiState then
        VehicleSellingPointExtension.logGuiState("CLOSE_COMPLETE")
    end
end

--[[
     Dialog closed - cleanup
     Note: This is called by g_gui:closeDialog() - we just do cleanup here
]]
function SellVehicleDialog:onClose()
    UsedPlus.logDebug(">>> SellVehicleDialog:onClose() STARTING <<<")

    -- Log GUI state
    if VehicleSellingPointExtension and VehicleSellingPointExtension.logGuiState then
        VehicleSellingPointExtension.logGuiState("SELL_DIALOG_ONCLOSE_START")
    end

    -- Clear our data
    self.vehicle = nil
    self.farmId = nil
    self.vanillaSellPrice = 0
    self.callback = nil

    -- Call superclass onClose
    UsedPlus.logDebug(">>> SellVehicleDialog:onClose() calling superclass <<<")
    SellVehicleDialog:superClass().onClose(self)

    -- Log GUI state after close
    if VehicleSellingPointExtension and VehicleSellingPointExtension.logGuiState then
        VehicleSellingPointExtension.logGuiState("SELL_DIALOG_ONCLOSE_COMPLETE")
    end
    UsedPlus.logDebug(">>> SellVehicleDialog:onClose() COMPLETE <<<")
end

UsedPlus.logInfo("SellVehicleDialog loaded (dual-tier system)")
