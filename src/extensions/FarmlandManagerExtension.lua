--[[
    FS25_UsedPlus - Farmland Manager Extension

    Extends farmland purchasing to add finance option
    Pattern from: Game's farmland purchase system
    Reference: FS25_ADVANCED_PATTERNS.md - Extension Pattern

    Responsibilities:
    - Add "Finance Land" button to farmland purchase dialog
    - Open UnifiedLandPurchaseDialog when button clicked
    - Handle financed land purchase (ownership transfers immediately)
    - Prevent selling financed land if proceeds < remaining balance
    - Track land finance deals

    Uses Utils.overwrittenFunction to extend FarmlandManager methods
]]

FarmlandManagerExtension = {}

-- Dialog loading now handled by DialogLoader utility

--[[
    Initialize extension
]]
function FarmlandManagerExtension:init()
    UsedPlus.logDebug("Initializing FarmlandManagerExtension")

    -- Hook farmland purchase dialog
    if g_gui.screenControllers[FarmlandScreen] then
        FarmlandScreen.onClickBuyLand = Utils.overwrittenFunction(
            FarmlandScreen.onClickBuyLand,
            FarmlandManagerExtension.onClickBuyLand
        )
    end

    -- Hook farmland sell validation
    FarmlandManager.buyFarmland = Utils.overwrittenFunction(
        FarmlandManager.buyFarmland,
        FarmlandManagerExtension.buyFarmland
    )

    FarmlandManager.sellFarmland = Utils.overwrittenFunction(
        FarmlandManager.sellFarmland,
        FarmlandManagerExtension.sellFarmland
    )

    UsedPlus.logDebug("FarmlandManagerExtension initialized")
    return true
end

--[[
    Override buy land button to open UnifiedLandPurchaseDialog
    Dialog provides Cash, Finance, and Lease options
]]
function FarmlandManagerExtension.onClickBuyLand(self, superFunc)
    -- Get selected farmland
    local farmland = self.farmland
    if farmland == nil then
        UsedPlus.logWarn("No farmland selected")
        return superFunc(self)
    end

    -- Get land price
    local price = g_farmlandManager:getFarmlandPricePerHa(farmland.id) * farmland.areaInSqMeters / 10000

    -- Store reference for potential fallback
    FarmlandManagerExtension.pendingFarmland = farmland
    FarmlandManagerExtension.pendingPrice = price
    FarmlandManagerExtension.pendingFarmId = g_currentMission:getFarmId()
    FarmlandManagerExtension.pendingSuperFunc = superFunc
    FarmlandManagerExtension.pendingSelf = self

    -- Use DialogLoader for centralized lazy loading
    local shown = DialogLoader.show("UnifiedLandPurchaseDialog", "setLandData", farmland.id, farmland, price)

    if not shown then
        -- Fallback to original behavior
        UsedPlus.logWarn("UnifiedLandPurchaseDialog not found, using vanilla purchase")
        return superFunc(self)
    end
end

--[[
    Override buyFarmland to handle financed purchases
    Not currently used (finance handled via FinanceVehicleEvent)
    Kept for potential direct integration
]]
function FarmlandManagerExtension.buyFarmland(self, superFunc, farmId, farmlandId, price, ...)
    -- Check if this is a financed purchase
    -- (Would be flagged by FinanceVehicleEvent if implemented)

    -- For now, just call original function
    return superFunc(self, farmId, farmlandId, price, ...)
end

--[[
    Override sellFarmland to check finance deals
]]
function FarmlandManagerExtension.sellFarmland(self, superFunc, farmId, farmlandId, ...)
    -- Check if land is financed
    local dealId = string.format("LAND_%d", farmlandId)
    local deal = g_financeManager:getDealById(dealId)

    if deal and deal.itemType == "land" and deal.itemId == farmlandId then
        -- Land is financed, check if sale proceeds cover balance
        local farmland = g_farmlandManager:getFarmlandById(farmlandId)
        if farmland then
            local salePrice = farmland.price

            if salePrice < deal.currentBalance then
                UsedPlus.logWarn(string.format("Land sale price ($%.2f) < remaining balance ($%.2f)",
                    salePrice, deal.currentBalance))

                -- Show error notification
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    string.format(g_i18n:getText("usedplus_error_insufficientSalePrice"),
                        g_i18n:formatMoney(deal.currentBalance), g_i18n:formatMoney(salePrice))
                )

                return false
            end

            UsedPlus.logDebug(string.format("Selling financed land: Field %d (Sale: $%.2f, Balance: $%.2f)",
                farmlandId, salePrice, deal.currentBalance))

            -- Proceed with sale
            local success = superFunc(self, farmId, farmlandId, ...)

            if success then
                -- Pay off finance deal
                deal.status = "completed"
                deal.currentBalance = 0

                -- Remove from active deals
                g_financeManager.deals[deal.id] = nil
                local farmDeals = g_financeManager.dealsByFarm[deal.farmId]
                if farmDeals then
                    for i, d in ipairs(farmDeals) do
                        if d.id == deal.id then
                            table.remove(farmDeals, i)
                            break
                        end
                    end
                end

                UsedPlus.logDebug(string.format("Land finance deal %s paid off from sale", deal.id))
            end

            return success
        end
    end

    -- Not financed, call original
    return superFunc(self, farmId, farmlandId, ...)
end

UsedPlus.logInfo("FarmlandManagerExtension loaded")
