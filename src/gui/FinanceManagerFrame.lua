--[[
    FS25_UsedPlus - Finance Manager Frame (ESC Menu Page)
    Three-column layout showing Finances, Searches, and Stats simultaneously
    Uses row-based table display with proper column alignment
]]

FinanceManagerFrame = {}
FinanceManagerFrame._mt = Class(FinanceManagerFrame, TabbedMenuFrameElement)

-- Static instance reference for external refresh calls
FinanceManagerFrame.instance = nil

-- Constants
FinanceManagerFrame.MAX_FINANCE_ROWS = 9
FinanceManagerFrame.MAX_SEARCH_ROWS = 5
FinanceManagerFrame.MAX_SALE_ROWS = 3  -- Agent-based vehicle sale listings

function FinanceManagerFrame.new()
    local self = FinanceManagerFrame:superClass().new(nil, FinanceManagerFrame._mt)

    self.name = "financeManagerFrame"

    -- Store row element references
    self.financeRows = {}
    self.searchRows = {}
    self.saleRows = {}  -- Agent-based vehicle sale listings

    -- Track active sale listings for button handlers
    self.activeSaleListings = {}

    -- Track selected deal for payments
    self.selectedDealId = nil

    -- Menu buttons (required by TabbedMenuFrameElement)
    self.btnBack = {
        inputAction = InputAction.MENU_BACK
    }

    self.btnPreviousPage = {
        text = g_i18n:getText("usedplus_button_prevPage"),
        inputAction = InputAction.MENU_PAGE_PREV
    }

    self.btnNextPage = {
        text = g_i18n:getText("usedplus_button_nextPage"),
        inputAction = InputAction.MENU_PAGE_NEXT
    }

    self.btnDashboard = {
        text = "Credit Report",
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function()
            self:onCreditReportClick()
        end
    }

    self.btnTakeLoan = {
        text = "Take Loan",
        inputAction = InputAction.MENU_EXTRA_1,
        callback = function()
            self:onTakeLoanClick()
        end
    }

    self:setMenuButtonInfo({
        self.btnBack,
        self.btnNextPage,
        self.btnPreviousPage,
        self.btnDashboard,
        self.btnTakeLoan
    })

    return self
end

function FinanceManagerFrame:onGuiSetupFinished()
    FinanceManagerFrame:superClass().onGuiSetupFinished(self)

    -- Cache references to finance row elements (selection-based, no per-row buttons)
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        local rowId = "financeRow" .. i
        self.financeRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            type = self[rowId .. "Type"],
            item = self[rowId .. "Item"],
            balance = self[rowId .. "Balance"],
            monthly = self[rowId .. "Monthly"],
            progress = self[rowId .. "Progress"],
            remaining = self[rowId .. "Remaining"]
        }
    end

    -- Track selected finance row index (-1 = none selected)
    self.selectedFinanceRowIndex = -1

    -- Cache reference to finance table container for mouse hit detection
    self.financeTableContainer = self.financeTableContainer  -- XML id="financeTableContainer"

    -- Note: We store the row Y positions for click detection (in pixels, relative to container)
    self.financeRowPositions = {
        [0] = 324,  -- Row 0 at top
        [1] = 288,
        [2] = 252,
        [3] = 216,
        [4] = 180,
        [5] = 144,
        [6] = 108,
        [7] = 72,
        [8] = 36
    }
    self.financeRowHeight = 36  -- Each row is 36px tall

    -- Cache references to search row elements (including new hidden-style button elements)
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        local rowId = "searchRow" .. i
        self.searchRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            item = self[rowId .. "Item"],
            price = self[rowId .. "Price"],
            tier = self[rowId .. "Tier"],
            chance = self[rowId .. "Chance"],
            time = self[rowId .. "Time"],
            -- Hidden-style info button elements
            infoBtn = self[rowId .. "InfoBtn"],
            infoBtnBg = self[rowId .. "InfoBtnBg"],
            infoBtnText = self[rowId .. "InfoBtnText"],
            -- Hidden-style cancel button elements
            cancelBtn = self[rowId .. "CancelBtn"],
            cancelBtnBg = self[rowId .. "CancelBtnBg"],
            cancelBtnText = self[rowId .. "CancelBtnText"]
        }
    end

    -- Cache references to sale listing row elements
    -- Each button now has 3 parts: Bg (background), Btn (button), Text (label)
    for i = 0, FinanceManagerFrame.MAX_SALE_ROWS - 1 do
        local rowId = "saleRow" .. i
        self.saleRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            item = self[rowId .. "Item"],
            tier = self[rowId .. "Tier"],
            status = self[rowId .. "Status"],
            time = self[rowId .. "Time"],
            -- Info button (always visible)
            infoBtn = self[rowId .. "InfoBtn"],
            infoBtnBg = self[rowId .. "InfoBtnBg"],
            infoBtnText = self[rowId .. "InfoBtnText"],
            -- Accept button (for pending offers)
            acceptBtn = self[rowId .. "AcceptBtn"],
            acceptBtnBg = self[rowId .. "AcceptBtnBg"],
            acceptBtnText = self[rowId .. "AcceptBtnText"],
            -- Decline button (for pending offers)
            declineBtn = self[rowId .. "DeclineBtn"],
            declineBtnBg = self[rowId .. "DeclineBtnBg"],
            declineBtnText = self[rowId .. "DeclineBtnText"],
            -- Cancel button (for active listings)
            cancelBtn = self[rowId .. "CancelBtn"],
            cancelBtnBg = self[rowId .. "CancelBtnBg"],
            cancelBtnText = self[rowId .. "CancelBtnText"]
        }
    end

    -- Cache references to action button elements (cell-based buttons)
    -- Each button has: invisible focusable button, background bitmap, text label
    self.actionButtons = {
        pay = {
            btn = self.paySelectedBtn,
            bg = self.payBtnBg,
            text = self.payBtnText,
            enabledBgColor = {0.2, 0.4, 0.2, 1},      -- Green-ish when enabled
            disabledBgColor = {0.15, 0.15, 0.15, 1},  -- Dark gray when disabled
            focusBgColor = {0.3, 0.5, 0.3, 1},        -- Brighter green on focus
            enabledTextColor = {1, 1, 1, 1},          -- White text when enabled
            disabledTextColor = {0.4, 0.4, 0.4, 1}    -- Gray text when disabled
        },
        info = {
            btn = self.infoSelectedBtn,
            bg = self.infoBtnBg,
            text = self.infoBtnText,
            enabledBgColor = {0.2, 0.3, 0.4, 1},      -- Blue-ish when enabled
            disabledBgColor = {0.15, 0.15, 0.15, 1},
            focusBgColor = {0.3, 0.4, 0.5, 1},
            enabledTextColor = {1, 1, 1, 1},
            disabledTextColor = {0.4, 0.4, 0.4, 1}
        },
        payAll = {
            btn = self.payAllBtn,
            bg = self.payAllBtnBg,
            text = self.payAllBtnText,
            enabledBgColor = {0.2, 0.35, 0.2, 1},     -- Distinct green for Pay All
            disabledBgColor = {0.15, 0.15, 0.15, 1},
            focusBgColor = {0.3, 0.45, 0.3, 1},
            enabledTextColor = {1, 1, 1, 1},
            disabledTextColor = {0.4, 0.4, 0.4, 1}
        }
    }

    -- Set up focus handlers for controller navigation highlighting
    self:setupActionButtonFocusHandlers()
end

--[[
    Set up focus enter/leave handlers for action buttons
    This provides visual feedback when navigating with controller
]]
function FinanceManagerFrame:setupActionButtonFocusHandlers()
    for name, btnData in pairs(self.actionButtons) do
        if btnData.btn then
            -- Store reference to self for use in callbacks
            local frame = self
            local buttonName = name

            -- Override onFocusEnter to highlight
            btnData.btn.onFocusEnter = function(element)
                frame:onActionButtonFocusEnter(buttonName)
            end

            -- Override onFocusLeave to unhighlight
            btnData.btn.onFocusLeave = function(element)
                frame:onActionButtonFocusLeave(buttonName)
            end
        end
    end
end

--[[
    Handle focus enter on action button - highlight the background
]]
function FinanceManagerFrame:onActionButtonFocusEnter(buttonName)
    local btnData = self.actionButtons[buttonName]
    if not btnData or not btnData.bg then return end

    -- Only highlight if button is enabled
    if btnData.btn and not btnData.btn:getIsDisabled() then
        btnData.bg:setImageColor(nil, unpack(btnData.focusBgColor))
    end
end

--[[
    Handle focus leave on action button - restore normal background
]]
function FinanceManagerFrame:onActionButtonFocusLeave(buttonName)
    local btnData = self.actionButtons[buttonName]
    if not btnData or not btnData.bg then return end

    -- Restore appropriate color based on enabled/disabled state
    if btnData.btn and btnData.btn:getIsDisabled() then
        btnData.bg:setImageColor(nil, unpack(btnData.disabledBgColor))
    else
        btnData.bg:setImageColor(nil, unpack(btnData.enabledBgColor))
    end
end

function FinanceManagerFrame:onFrameOpen()
    FinanceManagerFrame:superClass().onFrameOpen(self)
    FinanceManagerFrame.instance = self  -- Store instance for external refresh
    self:setMenuButtonInfoDirty()
    self:updateDisplay()
end

function FinanceManagerFrame:onFrameClose()
    FinanceManagerFrame:superClass().onFrameClose(self)
end

--[[
    Static method to refresh the frame from external code (e.g., after accepting a loan)
]]
function FinanceManagerFrame.refresh()
    if FinanceManagerFrame.instance then
        FinanceManagerFrame.instance:updateDisplay()
        UsedPlus.logTrace("FinanceManagerFrame refreshed")
    end
end

--[[
    Update all three sections
]]
function FinanceManagerFrame:updateDisplay()
    -- Get current player's farm ID
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end
    local farmId = farm.farmId

    self:updateFinancesSection(farmId, farm)
    self:updateSearchesSection(farmId)
    self:updateSaleListings(farmId)  -- Agent-based vehicle sales
    self:updateStatsSection(farmId, farm)
end

--[[
    Update Finances section (left column) with row-based table display
]]
function FinanceManagerFrame:updateFinancesSection(farmId, farm)
    local totalFinanced = 0
    local totalMonthly = 0
    local totalInterestPaid = 0
    local dealCount = 0

    -- First, hide all rows and show empty state
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        if self.financeRows[i] and self.financeRows[i].row then
            self.financeRows[i].row:setVisible(false)
        end
    end

    if self.financeEmptyText then
        self.financeEmptyText:setVisible(true)
    end

    -- Store active deals for payment selection
    self.activeDeals = {}

    -- v1.7.3: Calculate UsedPlus loan balances to subtract from farm.loan
    -- farm.loan includes ALL loans (vanilla + UsedPlus), so we need to find the true vanilla amount
    local usedPlusLoanTotal = 0
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" and deal.currentBalance then
                    usedPlusLoanTotal = usedPlusLoanTotal + deal.currentBalance
                end
            end
        end
    end

    -- v1.7.3: Check for vanilla bank loan (farm.loan minus UsedPlus loans)
    local rowIndex = 0
    local farm = g_farmManager:getFarmById(farmId)
    local vanillaLoanAmount = 0
    if farm and farm.loan then
        vanillaLoanAmount = math.max(0, farm.loan - usedPlusLoanTotal)
    end

    if vanillaLoanAmount > 0 then
        -- Create a pseudo-deal for the vanilla loan display
        local vanillaLoanDeal = {
            id = "VANILLA_LOAN",
            dealType = 0,  -- Special type for vanilla loan
            itemName = g_i18n:getText("usedplus_vanillaLoan") or "Bank Loan",
            currentBalance = vanillaLoanAmount,
            monthlyPayment = 0,  -- Vanilla loans don't have structured payments
            interestRate = 0,
            termMonths = 0,
            monthsPaid = 0,
            totalInterestPaid = 0,
            status = "active",
            isVanillaLoan = true,
        }
        table.insert(self.activeDeals, vanillaLoanDeal)

        -- Update row for vanilla loan
        local row = self.financeRows[rowIndex]
        if row then
            if row.row then row.row:setVisible(true) end
            if row.type then row.type:setText("BANK") end
            if row.item then row.item:setText(vanillaLoanDeal.itemName) end
            if row.balance then row.balance:setText(g_i18n:formatMoney(vanillaLoanAmount, 0, true, true)) end
            if row.monthly then row.monthly:setText("--") end  -- No structured payment
            if row.progress then row.progress:setText("--") end
            if row.remaining then row.remaining:setText("--") end
        end

        totalFinanced = totalFinanced + vanillaLoanAmount
        dealCount = dealCount + 1
        rowIndex = rowIndex + 1
    end

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals and #deals > 0 then
            for _, deal in ipairs(deals) do
                if deal.status == "active" and rowIndex < FinanceManagerFrame.MAX_FINANCE_ROWS then
                    -- Store deal reference
                    table.insert(self.activeDeals, deal)

                    -- Deal type and name
                    -- dealType: 1=finance, 2=vehicle lease, 3=land lease, 4=cash loan
                    local dealType
                    if deal.dealType == 2 then
                        dealType = "LEASE"
                    elseif deal.dealType == 3 then
                        dealType = "LAND"
                    elseif deal.dealType == 4 then
                        dealType = "LOAN"
                    else
                        dealType = "FIN"
                    end
                    local itemName = deal.itemName or "Unknown"

                    -- Truncate item name if too long (reduced for 11px font)
                    if #itemName > 20 then
                        itemName = string.sub(itemName, 1, 18) .. ".."
                    end

                    -- Financial details from FinanceDeal structure
                    local currentBalance = deal.currentBalance or 0
                    -- Use configured payment (respects payment mode) instead of raw monthlyPayment
                    local monthlyPayment = deal.getConfiguredPayment and deal:getConfiguredPayment() or deal.monthlyPayment or 0
                    local interestRate = (deal.interestRate or 0) * 100
                    local termMonths = deal.termMonths or 0
                    local monthsPaid = deal.monthsPaid or 0
                    local interestPaid = deal.totalInterestPaid or 0

                    -- Accumulate totals
                    totalFinanced = totalFinanced + currentBalance
                    totalMonthly = totalMonthly + monthlyPayment
                    totalInterestPaid = totalInterestPaid + interestPaid
                    dealCount = dealCount + 1

                    -- Format values
                    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
                    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
                    local progressStr = string.format("%d/%d", monthsPaid, termMonths)
                    local remainingMonths = termMonths - monthsPaid
                    local remainingStr = string.format("%dmo", remainingMonths)

                    -- Update row elements
                    local row = self.financeRows[rowIndex]
                    if row then
                        if row.row then row.row:setVisible(true) end
                        if row.type then row.type:setText(dealType) end
                        if row.item then row.item:setText(itemName) end
                        if row.balance then row.balance:setText(balanceStr) end
                        if row.monthly then row.monthly:setText(monthlyStr) end
                        if row.progress then row.progress:setText(progressStr) end
                        if row.remaining then row.remaining:setText(remainingStr) end
                    end

                    rowIndex = rowIndex + 1
                end
            end

            -- Hide empty text if we have deals
            if rowIndex > 0 and self.financeEmptyText then
                self.financeEmptyText:setVisible(false)
            end
        end
    end

    -- Update summary bar
    if self.totalFinancedText then
        self.totalFinancedText:setText(g_i18n:formatMoney(totalFinanced, 0, true, true))
    end
    if self.monthlyTotalText then
        self.monthlyTotalText:setText(g_i18n:formatMoney(totalMonthly, 0, true, true) .. "/mo")
    end
    if self.totalInterestText then
        self.totalInterestText:setText(g_i18n:formatMoney(totalInterestPaid, 0, true, true))
    end
    if self.dealsCountText then
        self.dealsCountText:setText(tostring(dealCount))
    end

    -- Update PAY ALL button state (enable only if there are deals with payments due)
    if self.payAllBtn then
        local canPayAll = dealCount > 0 and totalMonthly > 0
        self.payAllBtn:setDisabled(not canPayAll)
    end

    -- Reset selection when data changes
    self.selectedFinanceRowIndex = -1
    self.selectedDealId = nil

    -- Update action buttons (disabled until row is selected)
    self:updateFinanceActionButtons()
end

--[[
    Update the action buttons based on current selection
    Also updates visual appearance (background and text colors)
]]
function FinanceManagerFrame:updateFinanceActionButtons()
    local hasSelection = self.selectedFinanceRowIndex >= 0 and self.activeDeals and self.activeDeals[self.selectedFinanceRowIndex + 1]
    local hasAnyDeals = self.activeDeals and #self.activeDeals > 0

    -- Update PAY and INFO button states (require selection)
    self:setActionButtonEnabled("pay", hasSelection)
    self:setActionButtonEnabled("info", hasSelection)

    -- Update PAY ALL button state (enabled if any deals exist)
    self:setActionButtonEnabled("payAll", hasAnyDeals)

    -- Update selection text (optional, for debugging/feedback)
    if self.selectedDealText then
        if hasSelection then
            local deal = self.activeDeals[self.selectedFinanceRowIndex + 1]
            local itemName = deal.itemName or "Unknown"
            if #itemName > 20 then
                itemName = string.sub(itemName, 1, 18) .. ".."
            end
            self.selectedDealText:setText(itemName)
            self.selectedDealText:setVisible(true)
        else
            self.selectedDealText:setText(g_i18n:getText("usedplus_manager_clickToSelect"))
            self.selectedDealText:setVisible(true)
        end
    end
end

--[[
    Set an action button's enabled/disabled state with proper visual feedback
    @param buttonName - "pay", "info", or "payAll"
    @param enabled - true to enable, false to disable
]]
function FinanceManagerFrame:setActionButtonEnabled(buttonName, enabled)
    local btnData = self.actionButtons and self.actionButtons[buttonName]
    if not btnData then return end

    -- Update button disabled state
    if btnData.btn then
        btnData.btn:setDisabled(not enabled)
    end

    -- Update background color
    if btnData.bg then
        if enabled then
            btnData.bg:setImageColor(nil, unpack(btnData.enabledBgColor))
        else
            btnData.bg:setImageColor(nil, unpack(btnData.disabledBgColor))
        end
    end

    -- Update text color
    if btnData.text then
        if enabled then
            btnData.text:setTextColor(unpack(btnData.enabledTextColor))
        else
            btnData.text:setTextColor(unpack(btnData.disabledTextColor))
        end
    end
end

--[[
    Select a finance row by index and highlight it
    @param rowIndex - The row index (0-8) to select, or -1 to deselect
]]
function FinanceManagerFrame:selectFinanceRow(rowIndex)
    -- Deselect previous row
    if self.selectedFinanceRowIndex >= 0 then
        local prevRow = self.financeRows[self.selectedFinanceRowIndex]
        if prevRow and prevRow.bg then
            -- Restore alternating row colors
            local bgColor = (self.selectedFinanceRowIndex % 2 == 0) and {0.1, 0.1, 0.1, 1} or {0.12, 0.12, 0.12, 1}
            prevRow.bg:setImageColor(nil, unpack(bgColor))
        end
    end

    -- Select new row
    self.selectedFinanceRowIndex = rowIndex

    if rowIndex >= 0 then
        local newRow = self.financeRows[rowIndex]
        if newRow and newRow.bg then
            -- Highlight selected row with golden color
            newRow.bg:setImageColor(nil, 0.3, 0.25, 0.1, 1)
        end

        -- Store selected deal ID
        if self.activeDeals and self.activeDeals[rowIndex + 1] then
            self.selectedDealId = self.activeDeals[rowIndex + 1].id
        end
    else
        self.selectedDealId = nil
    end

    -- Update action buttons
    self:updateFinanceActionButtons()
end

--[[
    Handle mouse events for row selection
    This replaces the per-row button approach with direct mouse hit detection
]]
function FinanceManagerFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    -- Call parent first
    if FinanceManagerFrame:superClass().mouseEvent ~= nil then
        eventUsed = FinanceManagerFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    end

    -- Only handle left mouse button release (click complete)
    if not isUp or button ~= Input.MOUSE_BUTTON_LEFT then
        return eventUsed
    end

    -- Check if we have an active finance table to click on
    if not self.financeTableContainer or not self.financeTableContainer:getIsVisible() then
        return eventUsed
    end

    -- Get container's absolute screen position and size
    local containerX = self.financeTableContainer.absPosition[1]
    local containerY = self.financeTableContainer.absPosition[2]
    local containerW = self.financeTableContainer.absSize[1]
    local containerH = self.financeTableContainer.absSize[2]

    -- Check if click is inside the finance table container
    if posX >= containerX and posX <= containerX + containerW and
       posY >= containerY and posY <= containerY + containerH then

        -- Calculate relative position within container (0,0 = bottom-left)
        local relativeY = posY - containerY

        -- Convert to pixel space (container is 360px tall)
        local containerHeightPx = 360
        local pixelY = (relativeY / containerH) * containerHeightPx

        -- Find which row was clicked (rows go from bottom to top in Y)
        -- Row 8 is at 36px, Row 0 is at 324px
        local clickedRow = -1
        for rowIndex = 0, 8 do
            local rowY = self.financeRowPositions[rowIndex]
            if pixelY >= rowY and pixelY < rowY + self.financeRowHeight then
                clickedRow = rowIndex
                break
            end
        end

        -- If a valid row was clicked and it has data, select it
        if clickedRow >= 0 and self.activeDeals and self.activeDeals[clickedRow + 1] then
            self:selectFinanceRow(clickedRow)
            return true  -- Event consumed
        end
    end

    return eventUsed
end

--[[
    PAY button clicked for selected row
]]
function FinanceManagerFrame:onPaySelected()
    if self.selectedFinanceRowIndex < 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_selectDealFirst")
        )
        return
    end

    self:onPayRowClick(self.selectedFinanceRowIndex)
end

--[[
    INFO button clicked for selected row
]]
function FinanceManagerFrame:onInfoSelected()
    if self.selectedFinanceRowIndex < 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_selectDealFirst")
        )
        return
    end

    self:onInfoRowClick(self.selectedFinanceRowIndex)
end

--[[
    Update Searches section (center column) with row-based table display
    Shows both active searches AND available listings (results ready for purchase)
    Newest items appear at top
]]
function FinanceManagerFrame:updateSearchesSection(farmId)
    local searchCount = 0
    local totalCost = 0
    local maxSearches = FinanceManagerFrame.MAX_SEARCH_ROWS

    -- First, hide all rows and show empty state
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        if self.searchRows[i] and self.searchRows[i].row then
            self.searchRows[i].row:setVisible(false)
        end
    end

    if self.searchEmptyText then
        self.searchEmptyText:setVisible(true)
        self.searchEmptyText:setText(string.format("No searches (0/%d). Start from Shop.", maxSearches))
    end

    -- Store ordered list for button handlers
    -- Each entry has: {type="search"|"listing", data=search|listing}
    self.activeSearchList = {}

    if g_usedVehicleManager then
        local displayItems = {}

        -- Collect active searches
        local searches = g_usedVehicleManager:getSearchesForFarm(farmId) or {}
        for _, search in ipairs(searches) do
            if search.status == "active" then
                table.insert(displayItems, {
                    type = "search",
                    data = search,
                    sortTime = search.startTime or 0,
                    isReady = false
                })
            end
        end

        -- Collect available listings (completed search results)
        local listings = g_usedVehicleManager:getListingsForFarm(farmId) or {}
        for _, listing in ipairs(listings) do
            table.insert(displayItems, {
                type = "listing",
                data = listing,
                sortTime = listing.createdTime or (g_currentMission and g_currentMission.time or 0),
                isReady = true
            })
        end

        -- Sort by time descending (newest first)
        table.sort(displayItems, function(a, b)
            return (a.sortTime or 0) > (b.sortTime or 0)
        end)

        local rowIndex = 0
        for _, item in ipairs(displayItems) do
            if rowIndex >= FinanceManagerFrame.MAX_SEARCH_ROWS then
                break
            end

            -- Store for button handlers
            self.activeSearchList[rowIndex] = item

            local isReady = item.isReady
            local itemName, searchLevel, ttl, basePrice

            if item.type == "search" then
                local search = item.data
                itemName = search.storeItemName or "Unknown"
                searchLevel = search.searchLevel or 1
                ttl = search.ttl or 0
                basePrice = search.basePrice or 0
                totalCost = totalCost + (search.searchCost or 0)
            else
                local listing = item.data
                itemName = listing.storeItemName or "Unknown"
                searchLevel = listing.searchLevel or 1
                ttl = 0
                basePrice = listing.price or 0
            end

            -- Truncate item name if too long
            if #itemName > 18 then
                itemName = string.sub(itemName, 1, 16) .. ".."
            end

            searchCount = searchCount + 1

            -- Tier info
            local tierNames = {"Local", "Regional", "National"}
            local successRates = {40, 70, 85}
            local tierName = tierNames[searchLevel] or "Local"
            local successRate = successRates[searchLevel] or 40

            -- Time display
            local timeStr
            if isReady then
                timeStr = "Ready!"
            else
                local monthsLeft = math.ceil(ttl / 24)
                local hoursLeft = ttl % 24
                if monthsLeft > 0 then
                    timeStr = string.format("%dmo", monthsLeft)
                elseif hoursLeft > 0 then
                    timeStr = string.format("%dhr", hoursLeft)
                else
                    timeStr = "Soon"
                end
            end

            -- Format values
            local priceStr = g_i18n:formatMoney(basePrice, 0, true, true)
            local chanceStr = isReady and "100%" or string.format("%d%%", successRate)

            -- Update row elements
            local row = self.searchRows[rowIndex]
            if row then
                if row.row then row.row:setVisible(true) end
                if row.item then row.item:setText(itemName) end
                if row.price then row.price:setText(priceStr) end
                if row.tier then row.tier:setText(tierName) end
                if row.chance then row.chance:setText(chanceStr) end
                if row.time then
                    row.time:setText(timeStr)
                    if isReady then
                        row.time:setTextColor(0.4, 1, 0.5, 1)  -- Green for ready
                    else
                        row.time:setTextColor(0.7, 0.7, 0.7, 1)
                    end
                end

                -- Row background - greenish for ready listings
                if row.bg then
                    if isReady then
                        row.bg:setImageColor(nil, 0.1, 0.15, 0.1, 1)
                    else
                        local bgColor = (rowIndex % 2 == 0) and 0.1 or 0.12
                        row.bg:setImageColor(nil, bgColor, bgColor, bgColor, 1)
                    end
                end

                -- Info button - green for ready, show "!" for ready, "?" for active
                if row.infoBtn then row.infoBtn:setVisible(true) end
                if row.infoBtnBg then
                    row.infoBtnBg:setVisible(true)
                    if isReady then
                        row.infoBtnBg:setImageColor(nil, 0.15, 0.25, 0.15, 1)
                    else
                        row.infoBtnBg:setImageColor(nil, 0.18, 0.18, 0.18, 1)
                    end
                end
                if row.infoBtnText then
                    row.infoBtnText:setVisible(true)
                    if isReady then
                        row.infoBtnText:setText("!")
                        row.infoBtnText:setTextColor(0.4, 1, 0.5, 1)
                    else
                        row.infoBtnText:setText("?")
                        row.infoBtnText:setTextColor(1, 1, 1, 1)
                    end
                end

                -- Cancel button - only visible for active searches, not ready listings
                local showCancel = not isReady
                if row.cancelBtn then row.cancelBtn:setVisible(showCancel) end
                if row.cancelBtnBg then row.cancelBtnBg:setVisible(showCancel) end
                if row.cancelBtnText then row.cancelBtnText:setVisible(showCancel) end
            end

            rowIndex = rowIndex + 1
        end

        -- Hide empty text if we have items
        if rowIndex > 0 and self.searchEmptyText then
            self.searchEmptyText:setVisible(false)
        end
    end

    -- Update summary bar
    if self.searchesCountText then
        self.searchesCountText:setText(string.format("%d/%d", searchCount, maxSearches))
    end
    if self.searchesTotalCostText then
        self.searchesTotalCostText:setText(g_i18n:formatMoney(totalCost, 0, true, true))
    end

    -- These would need lifetime tracking - set to 0 for now
    if self.searchesSuccessCountText then
        self.searchesSuccessCountText:setText("0")
    end
    if self.searchesFailedCountText then
        self.searchesFailedCountText:setText("0")
    end
end

--[[
     Update Sale Listings section (center column, above searches)
     Shows active vehicle sale listings with agent tier, status, and offer buttons
]]
function FinanceManagerFrame:updateSaleListings(farmId)
    local listingCount = 0
    local pendingOffers = 0

    -- First, hide all rows and show empty state
    for i = 0, FinanceManagerFrame.MAX_SALE_ROWS - 1 do
        if self.saleRows[i] and self.saleRows[i].row then
            self.saleRows[i].row:setVisible(false)
        end
    end

    if self.saleEmptyText then
        self.saleEmptyText:setVisible(true)
    end

    -- Clear active listings for button handlers
    self.activeSaleListings = {}

    -- Get listings from VehicleSaleManager
    if g_vehicleSaleManager then
        local listings = g_vehicleSaleManager:getListingsForFarm(farmId)
        if listings and #listings > 0 then
            local rowIndex = 0

            for _, listing in ipairs(listings) do
                -- Only show active or pending offer listings
                -- Use VehicleSaleListing status constants for correct comparison
                local isActiveOrPending = (listing.status == "active" or
                                          listing.status == "pending" or
                                          listing.status == VehicleSaleListing.STATUS.ACTIVE or
                                          listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
                if isActiveOrPending and rowIndex < FinanceManagerFrame.MAX_SALE_ROWS then
                    -- Store listing reference for button handlers
                    table.insert(self.activeSaleListings, listing)

                    -- Get listing details
                    local itemName = listing.vehicleName or "Unknown Vehicle"
                    local tierConfig = VehicleSaleListing.SALE_TIERS[listing.agentTier] or VehicleSaleListing.SALE_TIERS[1]
                    local tierName = tierConfig.name or "Local"
                    local status = listing.status or "active"
                    -- VehicleSaleListing uses "pending" not "pending_offer"
                    local hasPendingOffer = (status == "pending" or
                                            status == VehicleSaleListing.STATUS.OFFER_PENDING)

                    -- Truncate item name if too long (reduced for 11px font)
                    if #itemName > 18 then
                        itemName = string.sub(itemName, 1, 16) .. ".."
                    end

                    -- Calculate time remaining
                    local ttl = listing.ttl or 0
                    local monthsLeft = math.ceil(ttl / 24)
                    local hoursLeft = ttl % 24
                    local timeStr
                    if monthsLeft > 0 then
                        timeStr = string.format("%dmo left", monthsLeft)
                    elseif hoursLeft > 0 then
                        timeStr = string.format("%dhr left", hoursLeft)
                    else
                        timeStr = "Expiring"
                    end

                    -- Status text
                    local statusText
                    if hasPendingOffer then
                        local offerAmount = listing.currentOffer or 0
                        statusText = string.format("OFFER: %s", g_i18n:formatMoney(offerAmount, 0, true, true))
                        pendingOffers = pendingOffers + 1
                    else
                        statusText = "Searching..."
                    end

                    listingCount = listingCount + 1

                    -- Update row elements
                    local row = self.saleRows[rowIndex]
                    if row then
                        if row.row then row.row:setVisible(true) end
                        if row.item then row.item:setText(itemName) end
                        if row.tier then row.tier:setText(tierName) end
                        if row.status then
                            row.status:setText(statusText)
                            -- Green text for pending offers, gray for searching
                            if hasPendingOffer then
                                row.status:setTextColor(0.4, 1, 0.4, 1)  -- Bright green
                            else
                                row.status:setTextColor(0.7, 0.7, 0.7, 1)  -- Gray
                            end
                        end
                        if row.time then row.time:setText(timeStr) end

                        -- Info button (always visible when row is visible)
                        if row.infoBtn then row.infoBtn:setVisible(true) end
                        if row.infoBtnBg then row.infoBtnBg:setVisible(true) end
                        if row.infoBtnText then row.infoBtnText:setVisible(true) end

                        -- Show Accept/Decline buttons only for pending offers
                        -- Each button has 3 parts: Bg, Btn, Text
                        if row.acceptBtn then row.acceptBtn:setVisible(hasPendingOffer) end
                        if row.acceptBtnBg then row.acceptBtnBg:setVisible(hasPendingOffer) end
                        if row.acceptBtnText then row.acceptBtnText:setVisible(hasPendingOffer) end

                        if row.declineBtn then row.declineBtn:setVisible(hasPendingOffer) end
                        if row.declineBtnBg then row.declineBtnBg:setVisible(hasPendingOffer) end
                        if row.declineBtnText then row.declineBtnText:setVisible(hasPendingOffer) end

                        -- Show Cancel button only for active listings (no pending offer)

                        if row.cancelBtn then row.cancelBtn:setVisible(not hasPendingOffer) end
                        if row.cancelBtnBg then row.cancelBtnBg:setVisible(not hasPendingOffer) end
                        if row.cancelBtnText then row.cancelBtnText:setVisible(not hasPendingOffer) end

                        -- Highlight row background for pending offers
                        if row.bg then
                            if hasPendingOffer then
                                row.bg:setImageColor(nil, 0.15, 0.25, 0.15, 1)  -- Green tint
                            else
                                row.bg:setImageColor(nil, 0.1, 0.12, 0.1, 1)  -- Default dark
                            end
                        end
                    end

                    rowIndex = rowIndex + 1
                end
            end

            -- Hide empty text if we have listings
            if rowIndex > 0 and self.saleEmptyText then
                self.saleEmptyText:setVisible(false)
            end
        end
    end

    -- Update listings count text
    if self.saleListingsCountText then
        if pendingOffers > 0 then
            self.saleListingsCountText:setText(string.format("%d listings (%d offers!)", listingCount, pendingOffers))
            self.saleListingsCountText:setTextColor(0.4, 1, 0.4, 1)  -- Green if offers pending
        else
            self.saleListingsCountText:setText(string.format("%d listings", listingCount))
            self.saleListingsCountText:setTextColor(0.6, 0.6, 0.6, 1)  -- Gray normal
        end
    end
end

--[[
     Accept Sale Offer button handlers (per-row)
]]
function FinanceManagerFrame:onAcceptSale0()
    self:onAcceptSaleClick(0)
end

function FinanceManagerFrame:onAcceptSale1()
    self:onAcceptSaleClick(1)
end

function FinanceManagerFrame:onAcceptSale2()
    self:onAcceptSaleClick(2)
end

--[[
     Decline Sale Offer button handlers (per-row)
]]
function FinanceManagerFrame:onDeclineSale0()
    self:onDeclineSaleClick(0)
end

function FinanceManagerFrame:onDeclineSale1()
    self:onDeclineSaleClick(1)
end

function FinanceManagerFrame:onDeclineSale2()
    self:onDeclineSaleClick(2)
end

--[[
     Cancel Sale Listing button handlers (per-row)
]]
function FinanceManagerFrame:onCancelSale0()
    self:onCancelSaleClick(0)
end

function FinanceManagerFrame:onCancelSale1()
    self:onCancelSaleClick(1)
end

function FinanceManagerFrame:onCancelSale2()
    self:onCancelSaleClick(2)
end

--[[
    Edit Sale Price button handlers (per-row)
]]
function FinanceManagerFrame:onEditSale0()
    self:onEditSaleClick(0)
end

function FinanceManagerFrame:onEditSale1()
    self:onEditSaleClick(1)
end

function FinanceManagerFrame:onEditSale2()
    self:onEditSaleClick(2)
end

--[[
    Info Sale Listing button handlers (per-row)
    Opens SaleListingDetailsDialog for the listing in that row
]]
function FinanceManagerFrame:onInfoSale0()
    self:onInfoSaleClick(0)
end

function FinanceManagerFrame:onInfoSale1()
    self:onInfoSaleClick(1)
end

function FinanceManagerFrame:onInfoSale2()
    self:onInfoSaleClick(2)
end

--[[
    Handle Info button click for a specific sale row
    Opens the SaleListingDetailsDialog for the listing in that row
    @param rowIndex - The row index (0-2) that was clicked
]]
function FinanceManagerFrame:onInfoSaleClick(rowIndex)
    -- Check if we have active listings and the row index is valid
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        return
    end

    -- Get the listing for this row (1-indexed in Lua table)
    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Show listing details dialog
    if SaleListingDetailsDialog then
        local dialog = SaleListingDetailsDialog.getInstance()
        dialog:show(listing)
    end
end

--[[
    Cancel Search button handlers (per-row)
]]
function FinanceManagerFrame:onCancelSearch0()
    self:onCancelSearchClick(0)
end

function FinanceManagerFrame:onCancelSearch1()
    self:onCancelSearchClick(1)
end

function FinanceManagerFrame:onCancelSearch2()
    self:onCancelSearchClick(2)
end

function FinanceManagerFrame:onCancelSearch3()
    self:onCancelSearchClick(3)
end

function FinanceManagerFrame:onCancelSearch4()
    self:onCancelSearchClick(4)
end

--[[
    Info Search button handlers (per-row)
    Opens SearchDetailsDialog for the search in that row
]]
function FinanceManagerFrame:onInfoSearch0()
    self:onInfoSearchClick(0)
end

function FinanceManagerFrame:onInfoSearch1()
    self:onInfoSearchClick(1)
end

function FinanceManagerFrame:onInfoSearch2()
    self:onInfoSearchClick(2)
end

function FinanceManagerFrame:onInfoSearch3()
    self:onInfoSearchClick(3)
end

function FinanceManagerFrame:onInfoSearch4()
    self:onInfoSearchClick(4)
end

--[[
    Handle Info button click for a specific search row
    For active searches: Opens the SearchDetailsDialog
    For ready listings: Opens the purchase preview dialog
    @param rowIndex - The row index (0-4) that was clicked
]]
function FinanceManagerFrame:onInfoSearchClick(rowIndex)
    -- Use the cached activeSearchList populated by updateSearchesSection
    local item = self.activeSearchList and self.activeSearchList[rowIndex]
    if not item then
        UsedPlus.logDebug(string.format("onInfoSearchClick: No item at row %d", rowIndex))
        return
    end

    local farmId = g_currentMission:getFarmId()

    if item.type == "listing" then
        -- Ready listing - show the purchase preview dialog
        local listing = item.data
        UsedPlus.logDebug(string.format("onInfoSearchClick: Showing purchase dialog for listing %s",
            listing.storeItemName or "Unknown"))

        if g_usedVehicleManager and g_usedVehicleManager.showSearchResultDialog then
            g_usedVehicleManager:showSearchResultDialog(listing, farmId)
        end
    else
        -- Active search - show search details dialog
        local search = item.data
        UsedPlus.logDebug(string.format("onInfoSearchClick: Showing details for search %s",
            search.storeItemName or "Unknown"))

        if SearchDetailsDialog then
            local dialog = SearchDetailsDialog.getInstance()
            dialog:show(search)
        end
    end
end

--[[
    Handle Cancel button click for a specific search row
    Only works for active searches (not ready listings)
    @param rowIndex - The row index (0-4) that was clicked
]]
function FinanceManagerFrame:onCancelSearchClick(rowIndex)
    -- Use the cached activeSearchList populated by updateSearchesSection
    local item = self.activeSearchList and self.activeSearchList[rowIndex]
    if not item then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSearchInRow")
        )
        return
    end

    -- Only cancel active searches, not ready listings
    if item.type ~= "search" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotCancelReady")
        )
        return
    end

    local search = item.data
    if not search then
        return
    end

    -- Only cancel active searches
    if search.status ~= "active" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_searchNotActive")
        )
        return
    end

    -- Show confirmation dialog warning about no refund
    local itemName = search.storeItemName or "Unknown"
    local searchFee = search.searchCost or 0
    local message = string.format(
        "Cancel search for %s?\n\n" ..
        "WARNING: The agent fee of %s will NOT be refunded.\n\n" ..
        "The search will be terminated immediately.",
        itemName,
        g_i18n:formatMoney(searchFee, 0, true, true)
    )

    YesNoDialog.show(
        function(yes)
            if yes then
                -- Send cancel event
                if CancelSearchEvent then
                    CancelSearchEvent.sendToServer(search.id)
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        "Error: CancelSearchEvent not available"
                    )
                end
                -- Refresh display
                self:updateDisplay()
            end
        end,
        nil,  -- target
        message,  -- text
        "Cancel Search"  -- title
    )
end

--[[
     Handle Accept button click for a specific sale listing row
    @param rowIndex - The row index (0-2) that was clicked
]]
function FinanceManagerFrame:onAcceptSaleClick(rowIndex)
    -- Check if we have active listings and the row index is valid
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    -- Get the listing for this row (1-indexed in Lua table)
    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing has pending offer
    -- VehicleSaleListing uses "pending" not "pending_offer"
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if not isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noOfferPending")
        )
        return
    end

    -- Show confirmation dialog
    local offerAmount = listing.currentOffer or 0
    local vehicleName = listing.vehicleName or "Unknown"
    local message = string.format(
        "Accept offer of %s for %s?\n\nThe vehicle will be sold and removed from your farm.",
        g_i18n:formatMoney(offerAmount, 0, true, true),
        vehicleName
    )

    -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog (which doesn't exist in FS25)
    YesNoDialog.show(
        function(yes)
            if yes then
                -- Send accept event
                if AcceptSaleOfferEvent then
                    AcceptSaleOfferEvent.sendToServer(listing.id)
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notify_vehicleSold"), vehicleName, g_i18n:formatMoney(offerAmount, 0, true, true))
                    )
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        "Error: AcceptSaleOfferEvent not available"
                    )
                end
                -- Refresh display
                self:updateDisplay()
            end
        end,
        nil,  -- target
        message,  -- text
        "Accept Sale Offer"  -- title
    )
end

--[[
     Handle Decline button click for a specific sale listing row
    @param rowIndex - The row index (0-2) that was clicked
]]
function FinanceManagerFrame:onDeclineSaleClick(rowIndex)
    -- Check if we have active listings and the row index is valid
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    -- Get the listing for this row (1-indexed in Lua table)
    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing has pending offer
    -- VehicleSaleListing uses "pending" not "pending_offer"
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if not isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noOfferToDecline")
        )
        return
    end

    -- Show confirmation dialog
    local offerAmount = listing.currentOffer or 0
    local vehicleName = listing.vehicleName or "Unknown"
    local message = string.format(
        "Decline offer of %s for %s?\n\nThe agent will continue searching for other buyers.",
        g_i18n:formatMoney(offerAmount, 0, true, true),
        vehicleName
    )

    -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog
    YesNoDialog.show(
        function(yes)
            if yes then
                -- Send decline event
                if DeclineSaleOfferEvent then
                    DeclineSaleOfferEvent.sendToServer(listing.id)
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        g_i18n:getText("usedplus_notify_offerDeclined")
                    )
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        "Error: DeclineSaleOfferEvent not available"
                    )
                end
                -- Refresh display
                self:updateDisplay()
            end
        end,
        nil,  -- target
        message,  -- text
        "Decline Sale Offer"  -- title
    )
end

--[[
     Handle Cancel button click for a specific sale listing row
     Cancels an active listing (no pending offer) - agent fee is lost
    @param rowIndex - The row index (0-2) that was clicked
]]
function FinanceManagerFrame:onCancelSaleClick(rowIndex)
    -- Check if we have active listings and the row index is valid
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    -- Get the listing for this row (1-indexed in Lua table)
    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing does NOT have pending offer (can only cancel active listings)
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotCancelPendingOffer")
        )
        return
    end

    -- Show confirmation dialog warning about lost agent fee
    local vehicleName = listing.vehicleName or "Unknown"
    local agentFee = listing.agentFee or 0
    local message = string.format(
        "Cancel sale listing for %s?\n\n" ..
        "WARNING: The agent fee of %s will NOT be refunded.\n\n" ..
        "The vehicle will remain in your possession.",
        vehicleName,
        g_i18n:formatMoney(agentFee, 0, true, true)
    )

    YesNoDialog.show(
        function(yes)
            if yes then
                -- Send cancel event
                if SaleListingActionEvent then
                    SaleListingActionEvent.cancelListing(listing.id)
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        string.format(g_i18n:getText("usedplus_notify_listingCancelled"), vehicleName)
                    )
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        "Error: SaleListingActionEvent not available"
                    )
                end
                -- Refresh display
                self:updateDisplay()
            end
        end,
        nil,  -- target
        message,  -- text
        "Cancel Sale Listing"  -- title
    )
end

--[[
    Handle Edit Price button click for a specific sale row
    @param rowIndex - The row index (0-2) that was clicked
]]
function FinanceManagerFrame:onEditSaleClick(rowIndex)
    -- Check if we have active listings and the row index is valid
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    -- Get the listing for this row (1-indexed in Lua table)
    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing is in searching status (can only edit active listings without pending offers)
    if listing.status ~= "searching" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotModifyPendingOffer")
        )
        return
    end

    -- Store listing reference for callback
    self.pendingEditListing = listing

    -- Use TextInputDialog to get new price
    local currentPrice = listing.askingPrice or 0
    local vehicleName = listing.vehicleName or "Unknown"

    g_gui:showTextInputDialog({
        callback = function(text, args)
            self:onEditPriceInputComplete(text)
        end,
        target = self,
        dialogPrompt = string.format("Enter new asking price for %s\n(Current: %s)",
            vehicleName, g_i18n:formatMoney(currentPrice, 0, true, true)),
        defaultText = tostring(math.floor(currentPrice)),
        maxCharacters = 10,
        confirmText = "Update Price"
    })
end

--[[
    Handle text input completion for price edit
    @param text - The entered text (should be a number)
]]
function FinanceManagerFrame:onEditPriceInputComplete(text)
    local listing = self.pendingEditListing
    self.pendingEditListing = nil

    if text == nil or text == "" or listing == nil then
        return
    end

    -- Parse the entered value
    local newPrice = tonumber(text)
    if newPrice == nil or newPrice <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_invalidPrice")
        )
        return
    end

    -- Send the modify event
    if ModifyListingPriceEvent then
        ModifyListingPriceEvent.sendToServer(listing.id, newPrice)
        -- Refresh display after short delay
        self:updateDisplay()
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Error: ModifyListingPriceEvent not available"
        )
    end
end

--[[
    Update Stats section (right column) with credit score and lifetime stats
]]
function FinanceManagerFrame:updateStatsSection(farmId, farm)
    -- Calculate Credit Score
    -- Default to realistic base score (650) not unrealistic 999
    local score = 650  -- Base FICO-like score for new farms
    local rating = "fair"  -- Fair rating for base score
    local interestAdj = 1.0  -- Fair tier adjustment
    local assets = 0
    local debt = 0

    if CreditScore then
        score = CreditScore.calculate(farmId)
        rating = CreditScore.getRating(score)
        interestAdj = CreditScore.getInterestAdjustment(score)

        -- Get assets and debt for display
        assets = CreditScore.calculateAssets(farm)
        debt = CreditScore.calculateDebt(farm)
    end

    -- Rating is now returned directly as display text from CreditScore.getRating()
    local ratingText = rating or "Unknown"

    -- Interest adjustment text
    local adjText = interestAdj >= 0 and string.format("+%.1f%% interest", interestAdj) or string.format("%.1f%% interest", interestAdj)

    -- Update credit score display
    if self.creditScoreValueText then
        self.creditScoreValueText:setText(tostring(score))
    end
    if self.creditRatingText then
        self.creditRatingText:setText(ratingText)
    end
    if self.interestAdjustText then
        self.interestAdjustText:setText(adjText)
    end
    if self.assetsText then
        self.assetsText:setText(string.format(g_i18n:getText("usedplus_manager_assetsLabel"), g_i18n:formatMoney(assets, 0, true, true)))
    end
    if self.debtText then
        self.debtText:setText(string.format(g_i18n:getText("usedplus_manager_debtLabel"), g_i18n:formatMoney(debt, 0, true, true)))
    end

    -- Highlight the current credit tier in the Credit Ranges box
    self:highlightCreditTier(score)

    -- Calculate lifetime statistics from current deals
    local lifetimeFinanced = 0
    local lifetimeInterest = 0
    local lifetimePayments = 0
    local activeDeals = 0

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals then
            for _, deal in ipairs(deals) do
                -- Count all deals (active and completed would both be in the list)
                lifetimeFinanced = lifetimeFinanced + (deal.amountFinanced or 0)
                lifetimeInterest = lifetimeInterest + (deal.totalInterestPaid or 0)
                lifetimePayments = lifetimePayments + (deal.monthsPaid or 0)
                if deal.status == "active" then
                    activeDeals = activeDeals + 1
                end
            end
        end
    end

    -- Update lifetime finance stats
    if self.lifetimeDealsText then
        self.lifetimeDealsText:setText(tostring(activeDeals))
    end
    if self.lifetimeFinancedText then
        self.lifetimeFinancedText:setText(g_i18n:formatMoney(lifetimeFinanced, 0, true, true))
    end
    if self.lifetimeInterestText then
        self.lifetimeInterestText:setText(g_i18n:formatMoney(lifetimeInterest, 0, true, true))
    end
    if self.lifetimePaymentsText then
        self.lifetimePaymentsText:setText(tostring(lifetimePayments))
    end

    -- Search statistics from FinanceManager
    local stats = g_financeManager:getStatistics(farmId)
    if self.lifetimeSearchesText then
        self.lifetimeSearchesText:setText(tostring(stats.searchesStarted or 0))
    end
    if self.lifetimeFoundText then
        self.lifetimeFoundText:setText(tostring(stats.searchesSucceeded or 0))
    end
    if self.lifetimeFeesText then
        self.lifetimeFeesText:setText(g_i18n:formatMoney(stats.totalSearchFees or 0, 0, true, true))
    end
    if self.lifetimeSuccessRateText then
        local totalSearches = stats.searchesStarted or 0
        local found = stats.searchesSucceeded or 0
        if totalSearches > 0 then
            local rate = math.floor((found / totalSearches) * 100)
            self.lifetimeSuccessRateText:setText(string.format("%d%%", rate))
        else
            self.lifetimeSuccessRateText:setText("N/A")
        end
    end
    if self.lifetimeSavingsText then
        self.lifetimeSavingsText:setText(g_i18n:formatMoney(stats.totalSavingsFromUsed or 0, 0, true, true))
    end

    -- Display credit history summary
    if CreditHistory then
        local summary = CreditHistory.getSummary(farmId)

        -- Update credit history stats if elements exist
        if self.paymentsOnTimeText then
            self.paymentsOnTimeText:setText(tostring(summary.paymentsOnTime or 0))
        end
        if self.paymentsMissedText then
            self.paymentsMissedText:setText(tostring(summary.paymentsMissed or 0))
            -- Color red if any missed
            if summary.paymentsMissed > 0 then
                self.paymentsMissedText:setTextColor(0.8, 0.2, 0.2, 1)
            else
                self.paymentsMissedText:setTextColor(0.2, 0.8, 0.2, 1)
            end
        end
        if self.dealsCompletedText then
            self.dealsCompletedText:setText(tostring(summary.dealsCompleted or 0))
        end
        if self.creditTrendText then
            local netChange = summary.netChange or 0
            local trendText = ""
            if netChange > 20 then
                trendText = "Trending Up"
                self.creditTrendText:setTextColor(0.2, 0.8, 0.2, 1)
            elseif netChange > 0 then
                trendText = "Slightly Up"
                self.creditTrendText:setTextColor(0.4, 0.7, 0.2, 1)
            elseif netChange < -20 then
                trendText = "Trending Down"
                self.creditTrendText:setTextColor(0.8, 0.2, 0.2, 1)
            elseif netChange < 0 then
                trendText = "Slightly Down"
                self.creditTrendText:setTextColor(0.8, 0.6, 0.2, 1)
            else
                trendText = "Stable"
                self.creditTrendText:setTextColor(0.7, 0.7, 0.7, 1)
            end
            self.creditTrendText:setText(trendText)
        end
        if self.historyAdjustmentText then
            local adjustment = CreditHistory.getScoreAdjustment(farmId)
            self.historyAdjustmentText:setText(string.format("History: %+d pts", adjustment))
        end
    end
end

--[[
    Highlight the current credit tier in the Credit Ranges box
    Shows player which tier they're currently in
    @param score - The player's current credit score (300-850)
]]
function FinanceManagerFrame:highlightCreditTier(score)
    -- Define tier thresholds (matches CreditScore.lua)
    local tiers = {
        {name = "Excellent", minScore = 750, bgId = "tierExcellentBg"},
        {name = "Good",      minScore = 700, bgId = "tierGoodBg"},
        {name = "Fair",      minScore = 650, bgId = "tierFairBg"},
        {name = "Poor",      minScore = 600, bgId = "tierPoorBg"},
        {name = "VeryPoor",  minScore = 300, bgId = "tierVeryPoorBg"}
    }

    -- Highlight color (bright golden/orange to stand out)
    local highlightColor = {0.8, 0.5, 0.1, 0.6}  -- Orange-gold, semi-transparent
    local noHighlightColor = {0, 0, 0, 0}  -- Fully transparent

    -- Determine which tier the score falls into
    local currentTier = nil
    for _, tier in ipairs(tiers) do
        if score >= tier.minScore then
            currentTier = tier.name
            break
        end
    end

    -- Update all tier backgrounds
    for _, tier in ipairs(tiers) do
        local bgElement = self[tier.bgId]
        if bgElement then
            if tier.name == currentTier then
                -- Highlight this tier
                bgElement:setImageColor(nil, unpack(highlightColor))
            else
                -- Clear highlight
                bgElement:setImageColor(nil, unpack(noHighlightColor))
            end
        end
    end
end

--[[
    Per-row PAY button handlers (onPayRow0 through onPayRow9)
    Each opens a payment dialog for the specific deal in that row
]]
function FinanceManagerFrame:onPayRow0()
    self:onPayRowClick(0)
end

function FinanceManagerFrame:onPayRow1()
    self:onPayRowClick(1)
end

function FinanceManagerFrame:onPayRow2()
    self:onPayRowClick(2)
end

function FinanceManagerFrame:onPayRow3()
    self:onPayRowClick(3)
end

function FinanceManagerFrame:onPayRow4()
    self:onPayRowClick(4)
end

function FinanceManagerFrame:onPayRow5()
    self:onPayRowClick(5)
end

function FinanceManagerFrame:onPayRow6()
    self:onPayRowClick(6)
end

function FinanceManagerFrame:onPayRow7()
    self:onPayRowClick(7)
end

function FinanceManagerFrame:onPayRow8()
    self:onPayRowClick(8)
end

function FinanceManagerFrame:onPayRow9()
    self:onPayRowClick(9)
end

--[[
    Per-row INFO button handlers (onInfoRow0 through onInfoRow8)
    Each opens the deal details dialog for the specific deal in that row
]]
function FinanceManagerFrame:onInfoRow0()
    self:onInfoRowClick(0)
end

function FinanceManagerFrame:onInfoRow1()
    self:onInfoRowClick(1)
end

function FinanceManagerFrame:onInfoRow2()
    self:onInfoRowClick(2)
end

function FinanceManagerFrame:onInfoRow3()
    self:onInfoRowClick(3)
end

function FinanceManagerFrame:onInfoRow4()
    self:onInfoRowClick(4)
end

function FinanceManagerFrame:onInfoRow5()
    self:onInfoRowClick(5)
end

function FinanceManagerFrame:onInfoRow6()
    self:onInfoRowClick(6)
end

function FinanceManagerFrame:onInfoRow7()
    self:onInfoRowClick(7)
end

function FinanceManagerFrame:onInfoRow8()
    self:onInfoRowClick(8)
end

--[[
    Handle INFO button click for a specific row
    Opens the DealDetailsDialog for the deal in that row
    @param rowIndex - The row index (0-8) that was clicked
]]
function FinanceManagerFrame:onInfoRowClick(rowIndex)
    -- Check if we have active deals and the row index is valid
    if not self.activeDeals or rowIndex >= #self.activeDeals then
        return
    end

    -- Get the deal for this row (1-indexed in Lua table)
    local deal = self.activeDeals[rowIndex + 1]
    if not deal then
        return
    end

    -- Show deal details dialog
    if DealDetailsDialog then
        local dialog = DealDetailsDialog.getInstance()
        dialog:show(deal, function()
            -- Refresh display after dialog closes
            self:updateDisplay()
        end)
    end
end

--[[
    Handle PAY button click for a specific row
    @param rowIndex - The row index (0-9) that was clicked
]]
function FinanceManagerFrame:onPayRowClick(rowIndex)
    -- Get current player's farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    -- Check if we have active deals and the row index is valid
    if not self.activeDeals or rowIndex >= #self.activeDeals then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noDealInRow")
        )
        return
    end

    -- Get the deal for this row (1-indexed in Lua table)
    local deal = self.activeDeals[rowIndex + 1]
    if not deal then
        return
    end

    -- Show payment options dialog for this specific deal
    self:showPaymentOptionsDialog(deal, farm)
end

--[[
    Show payment options dialog with Early Payment and Full Payoff options
    @param deal - The finance deal to make payment on
    @param farm - The player's farm
]]
function FinanceManagerFrame:showPaymentOptionsDialog(deal, farm)
    local currentBalance = deal.currentBalance or 0
    local monthlyPayment = deal.monthlyPayment or 0
    local itemName = deal.itemName or "Unknown"
    local farmMoney = farm.money or 0

    -- Check deal type: 2=vehicle lease, 3=land lease
    local isVehicleLease = (deal.dealType == 2)
    local isLandLease = (deal.dealType == 3)

    -- Calculate payoff penalty (5% of remaining balance for finance, residual for lease)
    local payoffPenalty = currentBalance * 0.05
    local totalPayoff = currentBalance + payoffPenalty

    -- For vehicle leases, calculate termination fee
    local terminationFee = 0
    if isVehicleLease and deal.calculateTerminationFee then
        terminationFee = deal:calculateTerminationFee()
    elseif isVehicleLease then
        -- Fallback calculation: 50% of remaining obligation
        local remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        local remainingPayments = monthlyPayment * remainingMonths
        local residualValue = deal.residualValue or 0
        terminationFee = (remainingPayments + residualValue) * 0.50
    end

    -- For land leases, calculate buyout price
    local buyoutPrice = 0
    if isLandLease and deal.calculateBuyoutPrice then
        buyoutPrice = deal:calculateBuyoutPrice()
    elseif isLandLease then
        -- Fallback: base buyout price
        buyoutPrice = deal.baseBuyoutPrice or deal.landPrice or 0
    end

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
    local penaltyStr = g_i18n:formatMoney(payoffPenalty, 0, true, true)
    local totalPayoffStr = g_i18n:formatMoney(totalPayoff, 0, true, true)
    local terminationStr = g_i18n:formatMoney(terminationFee, 0, true, true)
    local buyoutStr = g_i18n:formatMoney(buyoutPrice, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)

    -- Determine what payments are possible
    local canPayMonthly = farmMoney >= monthlyPayment
    local canPayFull = farmMoney >= totalPayoff
    local canTerminate = isVehicleLease and farmMoney >= terminationFee
    local canBuyout = isLandLease and farmMoney >= buyoutPrice

    -- Build message
    local message
    if isVehicleLease then
        message = string.format(
            "%s (LEASE)\n\nRemaining: %s\nMonthly: %s\nYour Money: %s\n",
            itemName, balanceStr, monthlyStr, moneyStr
        )
        if canTerminate then
            message = message .. string.format("\nTermination Fee: %s", terminationStr)
        end
    elseif isLandLease then
        local remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        message = string.format(
            "%s (LAND LEASE)\n\nRemaining: %d months\nMonthly: %s\nBuyout: %s\nYour Money: %s",
            itemName, remainingMonths, monthlyStr, buyoutStr, moneyStr
        )
    else
        -- Finance deal - simple message for early payment
        message = string.format(
            "%s\n\nBalance: %s\nMonthly: %s\nYour Money: %s",
            itemName, balanceStr, monthlyStr, moneyStr
        )
    end

    -- Store deal reference for callback
    self.pendingPaymentDeal = deal
    self.pendingPayoffAmount = totalPayoff
    self.pendingMonthlyAmount = monthlyPayment
    self.pendingTerminationFee = terminationFee
    self.pendingBuyoutPrice = buyoutPrice

    -- Different options based on deal type
    if isVehicleLease then
        -- Vehicle Lease options: Pay Monthly, Buyout Now, or Terminate Early
        -- Calculate equity and buyout price for vehicle lease
        local baseCost = deal.baseCost or 0
        local residualValue = deal.residualValue or 0
        local totalDepreciation = baseCost - residualValue
        local monthsPaid = deal.monthsPaid or 0
        local termMonths = deal.termMonths or 12

        -- Calculate equity using FinanceCalculations
        local equityAccumulated = 0
        if FinanceCalculations and FinanceCalculations.calculateLeaseEquity then
            equityAccumulated = FinanceCalculations.calculateLeaseEquity(monthlyPayment, monthsPaid, totalDepreciation, termMonths)
        else
            -- Fallback: Simple proportional equity calculation
            local progressPercent = monthsPaid / termMonths
            equityAccumulated = totalDepreciation * progressPercent
        end

        -- Calculate buyout price = residual - equity (minimum $0)
        local vehicleBuyoutPrice = math.max(0, residualValue - equityAccumulated)

        -- Security deposit refund
        local securityDeposit = deal.securityDeposit or 0
        local depositRefund = securityDeposit  -- Full refund on buyout

        -- Net cost to player = buyout price - deposit refund
        local netBuyoutCost = vehicleBuyoutPrice - depositRefund

        -- Store for callback
        self.pendingVehicleBuyoutPrice = vehicleBuyoutPrice
        self.pendingVehicleEquity = equityAccumulated
        self.pendingVehicleDepositRefund = depositRefund

        local vehicleBuyoutStr = g_i18n:formatMoney(vehicleBuyoutPrice, 0, true, true)
        local equityStr = g_i18n:formatMoney(equityAccumulated, 0, true, true)
        local canBuyout = farmMoney >= netBuyoutCost

        -- Update message to show buyout info
        message = string.format(
            "%s (LEASE)\n\nRemaining: %s\nMonthly: %s\nEquity Accumulated: %s\nBuyout Price: %s\nYour Money: %s",
            itemName, balanceStr, monthlyStr, equityStr, vehicleBuyoutStr, moneyStr
        )
        if depositRefund > 0 then
            message = message .. string.format("\n(Deposit refund: %s)", g_i18n:formatMoney(depositRefund, 0, true, true))
        end

        local options = {}

        if canPayMonthly then
            table.insert(options, {text = "Pay Monthly (" .. monthlyStr .. ")", callback = function() self:onPayMonthlyConfirm() end})
        end
        if canBuyout then
            local buyoutLabel = netBuyoutCost > 0
                and string.format("Buyout Now (%s)", g_i18n:formatMoney(netBuyoutCost, 0, true, true))
                or "Buyout Now (FREE - Equity covers it!)"
            table.insert(options, {text = buyoutLabel, callback = function() self:onVehicleLeaseBuyoutConfirm() end})
        end
        if canTerminate then
            table.insert(options, {text = "Terminate Early (" .. terminationStr .. ")", callback = function() self:onTerminateLeaseConfirm() end})
        end
        table.insert(options, {text = "Cancel"})

        if #options > 1 then
            -- Use YesNoDialog for simple monthly payment (most common action)
            if canPayMonthly then
                YesNoDialog.show(
                    function(yes)
                        if yes then
                            self:onPayMonthlyConfirm()
                        end
                    end,
                    nil,
                    message .. "\n\nMake monthly lease payment?",
                    "Lease Payment"
                )
            end
        else
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format(g_i18n:getText("usedplus_error_insufficientFundsPayment"), monthlyStr)
            )
        end
    elseif isLandLease then
        -- Land Lease options: Pay Monthly, Buyout, or Terminate
        local options = {}

        if canPayMonthly then
            table.insert(options, {text = "Pay Monthly (" .. monthlyStr .. ")", callback = function() self:onPayMonthlyConfirm() end})
        end
        if canBuyout then
            table.insert(options, {text = "Buyout Land (" .. buyoutStr .. ")", callback = function() self:onLandLeaseBuyoutConfirm() end})
        end
        table.insert(options, {text = "Terminate Lease", callback = function() self:onLandLeaseTerminateConfirm() end})
        table.insert(options, {text = "Cancel"})

        -- Use YesNoDialog for simple monthly payment (most common action)
        if canPayMonthly then
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:onPayMonthlyConfirm()
                    end
                end,
                nil,
                message .. "\n\nMake monthly land lease payment?",
                "Land Lease Payment"
            )
        else
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                g_i18n:getText("usedplus_error_noPaymentOptions")
            )
        end
    else
        -- Finance options: Pay Monthly or Payoff
        if canPayFull then
            -- Use YesNoDialog - ask about monthly payment first (most common)
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:onPayMonthlyConfirm()
                    end
                end,
                nil,
                message .. "\n\nMake early payment of " .. monthlyStr .. "?",
                "Early Payment"
            )
        elseif canPayMonthly then
            -- Can only afford monthly payment
            -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog (which doesn't exist in FS25)
            -- Signature: YesNoDialog.show(callback, target, text, title, yesText, noText, ...)
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:processPayment(deal, monthlyPayment)
                    end
                end,
                nil,  -- target
                message .. "\n\nMake early monthly payment?",  -- text
                "Early Payment"  -- title
            )
        else
            -- Can't afford any payment
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format(g_i18n:getText("usedplus_error_insufficientFundsPayment"), monthlyStr)
            )
        end
    end
end

--[[
    Callback for monthly payment confirmation
]]
function FinanceManagerFrame:onPayMonthlyConfirm()
    if self.pendingPaymentDeal and self.pendingMonthlyAmount then
        self:processPayment(self.pendingPaymentDeal, self.pendingMonthlyAmount)
    end
    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
end

--[[
    Callback for full payoff confirmation
]]
function FinanceManagerFrame:onPayoffConfirm()
    if self.pendingPaymentDeal and self.pendingPayoffAmount then
        -- Payoff includes the penalty - this closes the deal
        self:processPayoff(self.pendingPaymentDeal, self.pendingPayoffAmount)
    end
    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
end

--[[
     Callback for lease early termination confirmation
]]
function FinanceManagerFrame:onTerminateLeaseConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        -- Show confirmation dialog before terminating
        local terminationFee = self.pendingTerminationFee or 0
        local itemName = deal.itemName or "Unknown"

        -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog
        YesNoDialog.show(
            function(yes)
                if yes then
                    -- Send termination event
                    if TerminateLeaseEvent then
                        TerminateLeaseEvent.sendToServer(deal.id, farm.farmId)
                    else
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                            "Error: TerminateLeaseEvent not available"
                        )
                    end
                    -- Refresh display
                    self:updateDisplay()
                end
            end,
            nil,  -- target
            string.format(
                "Are you sure you want to terminate the lease for %s?\n\n" ..
                "Termination Fee: %s\n\n" ..
                "The vehicle will be returned to the dealer and you will lose all payments made.",
                itemName, g_i18n:formatMoney(terminationFee, 0, true, true)
            ),  -- text
            "Confirm Lease Termination"  -- title
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
end

--[[
     Callback for vehicle lease early buyout confirmation
     Sends LeaseRenewalEvent with ACTION_BUYOUT to server
     Uses calculated equity to reduce buyout price
]]
function FinanceManagerFrame:onVehicleLeaseBuyoutConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        -- Get calculated values from showPaymentOptionsDialog
        local buyoutPrice = self.pendingVehicleBuyoutPrice or 0
        local equityApplied = self.pendingVehicleEquity or 0
        local depositRefund = self.pendingVehicleDepositRefund or 0
        local vehicleName = deal.vehicleName or deal.itemName or "Unknown Vehicle"

        -- Net cost = buyout - deposit refund
        local netCost = buyoutPrice - depositRefund

        -- Show confirmation dialog with breakdown
        local confirmMessage
        if depositRefund > 0 then
            confirmMessage = string.format(
                "Buy out your lease for %s?\n\n" ..
                "Buyout Price: %s\n" ..
                "Equity Applied: -%s\n" ..
                "Security Deposit Refund: +%s\n" ..
                "Net Cost: %s\n\n" ..
                "The vehicle will become fully yours.",
                vehicleName,
                g_i18n:formatMoney(deal.residualValue or 0, 0, true, true),
                g_i18n:formatMoney(equityApplied, 0, true, true),
                g_i18n:formatMoney(depositRefund, 0, true, true),
                g_i18n:formatMoney(netCost, 0, true, true)
            )
        else
            confirmMessage = string.format(
                "Buy out your lease for %s?\n\n" ..
                "Buyout Price: %s\n" ..
                "Equity Applied: -%s\n" ..
                "Final Cost: %s\n\n" ..
                "The vehicle will become fully yours.",
                vehicleName,
                g_i18n:formatMoney(deal.residualValue or 0, 0, true, true),
                g_i18n:formatMoney(equityApplied, 0, true, true),
                g_i18n:formatMoney(buyoutPrice, 0, true, true)
            )
        end

        YesNoDialog.show(
            function(yes)
                if yes then
                    -- Send LeaseRenewalEvent with ACTION_BUYOUT
                    if LeaseRenewalEvent then
                        LeaseRenewalEvent.sendToServer(deal.id, LeaseRenewalEvent.ACTION_BUYOUT, {
                            buyoutPrice = buyoutPrice,
                            equityApplied = equityApplied,
                            depositRefund = depositRefund
                        })
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_OK,
                            string.format(g_i18n:getText("usedplus_notify_vehicleNowYours"), vehicleName)
                        )
                    else
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                            "Error: LeaseRenewalEvent not available"
                        )
                    end
                    -- Refresh display
                    self:updateDisplay()
                end
            end,
            nil,  -- target
            confirmMessage,
            "Confirm Vehicle Buyout"
        )
    end

    -- Clean up pending state
    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingVehicleBuyoutPrice = nil
    self.pendingVehicleEquity = nil
    self.pendingVehicleDepositRefund = nil
end

--[[
     Callback for land lease buyout confirmation
     Sends LandLeaseBuyoutEvent to server
]]
function FinanceManagerFrame:onLandLeaseBuyoutConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        -- Calculate buyout price
        local buyoutPrice = self.pendingBuyoutPrice or 0
        if buyoutPrice <= 0 and deal.calculateBuyoutPrice then
            buyoutPrice = deal:calculateBuyoutPrice()
        end
        local landName = deal.landName or deal.itemName or "Unknown Land"

        -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog
        YesNoDialog.show(
            function(yes)
                if yes then
                    -- Send buyout event
                    if LandLeaseBuyoutEvent then
                        LandLeaseBuyoutEvent.sendToServer(deal.id)
                    else
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                            "Error: LandLeaseBuyoutEvent not available"
                        )
                    end
                    -- Refresh display
                    self:updateDisplay()
                end
            end,
            nil,  -- target
            string.format(
                "Are you sure you want to buy out the lease for %s?\n\n" ..
                "Buyout Price: %s\n\n" ..
                "The land will become fully yours with no further payments.",
                landName, g_i18n:formatMoney(buyoutPrice, 0, true, true)
            ),  -- text
            "Confirm Land Buyout"  -- title
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingBuyoutPrice = nil
end

--[[
     Callback for land lease termination confirmation
     Uses TerminateLeaseEvent - land reverts to NPC, payments lost
]]
function FinanceManagerFrame:onLandLeaseTerminateConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        local landName = deal.landName or deal.itemName or "Unknown Land"
        local monthsPaid = deal.monthsPaid or 0
        local monthlyPayment = deal.monthlyPayment or 0
        local totalPaid = monthsPaid * monthlyPayment

        -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog
        YesNoDialog.show(
            function(yes)
                if yes then
                    -- Send termination event
                    if TerminateLeaseEvent then
                        TerminateLeaseEvent.sendToServer(deal.id, farm.farmId)
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            string.format(g_i18n:getText("usedplus_notify_landLeaseTerminated"), landName)
                        )
                    else
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                            "Error: TerminateLeaseEvent not available"
                        )
                    end
                    -- Refresh display
                    self:updateDisplay()
                end
            end,
            nil,  -- target
            string.format(
                "WARNING: Terminate lease for %s?\n\n" ..
                "• Land will revert to NPC ownership\n" ..
                "• All %d payments (%s) will be lost\n" ..
                "• Your credit score will be penalized\n\n" ..
                "Are you sure you want to proceed?",
                landName, monthsPaid, g_i18n:formatMoney(totalPaid, 0, true, true)
            ),  -- text
            "Terminate Land Lease"  -- title
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingBuyoutPrice = nil
end

--[[
    Process a full payoff on a finance deal (closes the loan with penalty)
]]
function FinanceManagerFrame:processPayoff(deal, amount)
    if not deal or not amount or amount <= 0 then
        return
    end

    -- Get farm for money check
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end

    -- Check funds
    if farm.money < amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_insufficientFundsPayoff")
        )
        return
    end

    -- Use the FinancePaymentEvent if available (with payoff flag)
    if FinancePaymentEvent and FinancePaymentEvent.sendPayoffToServer then
        FinancePaymentEvent.sendPayoffToServer(deal.id, amount, farm.farmId)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
        )
    elseif FinancePaymentEvent then
        -- Fallback: send as regular payment (full balance will close deal)
        local event = FinancePaymentEvent.new(deal.id, amount, farm.farmId, true)  -- true = isPayoff
        event:sendToServer(deal.id, amount, farm.farmId, true)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
        )
    else
        -- Direct payoff (single player fallback)
        if g_financeManager then
            if g_financeManager.payoffDeal then
                local success = g_financeManager:payoffDeal(deal.id, amount, farm.farmId)
                if success then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
                    )
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        g_i18n:getText("usedplus_error_payoffFailed")
                    )
                end
            elseif g_financeManager.makePayment then
                -- Use regular payment with full amount
                local success = g_financeManager:makePayment(deal.id, amount, farm.farmId)
                if success then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
                    )
                end
            end
        end
    end

    -- Refresh display after payoff
    self:updateDisplay()
end

--[[
    Handler for "Make Early Payment" button click (legacy - kept for compatibility)
    Opens a dialog to select payment amount for an active deal
]]
function FinanceManagerFrame:onMakePaymentClick()
    -- Get current player's farm ID
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end
    local farmId = farm.farmId

    -- Check if we have active deals
    if not self.activeDeals or #self.activeDeals == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noActiveDeals")
        )
        return
    end

    -- Get selected deal (default to first)
    local selectedDeal = nil
    for _, deal in ipairs(self.activeDeals) do
        if deal.id == self.selectedDealId then
            selectedDeal = deal
            break
        end
    end

    if not selectedDeal then
        selectedDeal = self.activeDeals[1]
    end

    -- Try to open FinanceDetailFrame dialog
    if g_gui then
        local detailFrame = g_gui:showDialog("FinanceDetailFrame")
        if detailFrame and detailFrame.target then
            detailFrame.target:setDealId(selectedDeal.id)
            UsedPlus.logDebug(string.format("Opened payment dialog for deal: %s", selectedDeal.id))
        else
            -- Fallback: Show payment confirmation dialog
            self:showPaymentConfirmation(selectedDeal, farm)
        end
    else
        self:showPaymentConfirmation(selectedDeal, farm)
    end
end

--[[
    Show a simple payment confirmation with options
]]
function FinanceManagerFrame:showPaymentConfirmation(deal, farm)
    local currentBalance = deal.currentBalance or 0
    local monthlyPayment = deal.monthlyPayment or 0
    local itemName = deal.itemName or "Unknown"

    -- Check if player can afford payments
    local farmMoney = farm.money or 0

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)

    -- Create message based on affordability
    local message = string.format(
        "Make payment on: %s\n\nCurrent Balance: %s\nMonthly Payment: %s\nYour Money: %s",
        itemName, balanceStr, monthlyStr, moneyStr
    )

    -- Determine what payments are possible
    local canPayMonthly = farmMoney >= monthlyPayment
    local canPayFull = farmMoney >= currentBalance

    if canPayFull then
        message = message .. "\n\nYou can pay off the full balance!"
    elseif canPayMonthly then
        message = message .. "\n\nYou can make an early monthly payment."
    else
        message = message .. "\n\ng_i18n:getText("usedplus_error_insufficientFundsForPayment")."
    end

    -- Use YesNoDialog.show() instead of g_gui:showYesNoDialog
    if canPayMonthly or canPayFull then
        YesNoDialog.show(
            function(yes)
                if yes then
                    self:processPayment(deal, monthlyPayment)
                end
            end,
            nil,  -- target
            message .. "\n\nMake a monthly payment now?",  -- text
            "Early Payment"  -- title
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsNeedHave"), monthlyStr, moneyStr)
        )
    end
end

--[[
    Process an early payment on a finance deal
]]
function FinanceManagerFrame:processPayment(deal, amount)
    if not deal or not amount or amount <= 0 then
        return
    end

    -- Get farm for money check
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end

    -- Check funds
    if farm.money < amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_insufficientFundsForPayment")
        )
        return
    end

    -- Use the FinancePaymentEvent if available
    if FinancePaymentEvent then
        -- Create and send payment event (handles multiplayer sync)
        local event = FinancePaymentEvent.new(deal.id, amount, farm.farmId)
        event:sendToServer(deal.id, amount, farm.farmId)

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_paymentProcessed"), g_i18n:formatMoney(amount, 0, true, true))
        )
    else
        -- Direct payment (single player fallback)
        if g_financeManager and g_financeManager.makePayment then
            local success = g_financeManager:makePayment(deal.id, amount, farm.farmId)
            if success then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notify_paymentProcessed"), g_i18n:formatMoney(amount, 0, true, true))
                )
            else
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    g_i18n:getText("usedplus_error_paymentFailed")
                )
            end
        end
    end

    -- Refresh display after payment
    self:updateDisplay()
end

--[[
     Take Loan button clicked - opens TakeLoanDialog
     Refactored to use DialogLoader for centralized loading
]]
function FinanceManagerFrame:onTakeLoanClick()
    -- Get current player's farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("TakeLoanDialog", "setFarmId", farm.farmId)
end

--[[
     Credit Report button clicked - opens CreditReportDialog
     Refactored to use DialogLoader for centralized loading
]]
function FinanceManagerFrame:onCreditReportClick()
    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("CreditReportDialog")
end

--[[
    PAY ALL button clicked - bulk pay all monthly payments at once
    Shows confirmation dialog with total amount before processing
]]
function FinanceManagerFrame:onPayAll()
    -- Get current player's farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    -- Check if there are any active deals
    if not self.activeDeals or #self.activeDeals == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noDealsToPayAll")
        )
        return
    end

    -- Calculate total monthly payments
    local totalPayment = 0
    local payableDeals = {}

    for _, deal in ipairs(self.activeDeals) do
        if deal.status == "active" then
            local monthlyPayment = deal.getConfiguredPayment and deal:getConfiguredPayment() or deal.monthlyPayment or 0
            if monthlyPayment > 0 then
                totalPayment = totalPayment + monthlyPayment
                table.insert(payableDeals, {deal = deal, amount = monthlyPayment})
            end
        end
    end

    -- Check if there's anything to pay
    if totalPayment <= 0 or #payableDeals == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noPaymentsDue")
        )
        return
    end

    -- Check if player can afford total payment
    local farmMoney = farm.money or 0
    if totalPayment > farmMoney then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsNeedHave"),
                g_i18n:formatMoney(totalPayment, 0, true, true),
                g_i18n:formatMoney(farmMoney, 0, true, true))
        )
        return
    end

    -- Store data for callback
    self.bulkPaymentData = {
        deals = payableDeals,
        totalAmount = totalPayment,
        farm = farm
    }

    -- Show confirmation dialog
    local message = string.format(
        "Pay all %d finance deals?\n\nTotal: %s\nBalance after: %s",
        #payableDeals,
        g_i18n:formatMoney(totalPayment, 0, true, true),
        g_i18n:formatMoney(farmMoney - totalPayment, 0, true, true)
    )

    -- Use YesNoDialog.show() - correct FS25 pattern
    YesNoDialog.show(
        function(yes)
            self:onBulkPaymentConfirm(yes)
        end,
        nil,  -- target
        message,
        "Bulk Payment"
    )
end

--[[
    Callback for bulk payment confirmation dialog
    @param yes - true if user confirmed, false if cancelled
]]
function FinanceManagerFrame:onBulkPaymentConfirm(yes)
    if not yes or not self.bulkPaymentData then
        self.bulkPaymentData = nil
        return
    end

    local data = self.bulkPaymentData
    local successCount = 0
    local failCount = 0

    -- Process each payment
    for _, paymentInfo in ipairs(data.deals) do
        local deal = paymentInfo.deal
        local amount = paymentInfo.amount

        if FinancePaymentEvent then
            local event = FinancePaymentEvent.new(deal.id, amount, data.farm.farmId)
            event:sendToServer(deal.id, amount, data.farm.farmId)
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    -- Show result notification
    if failCount == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_paidDealsTotal"),
                successCount,
                g_i18n:formatMoney(data.totalAmount, 0, true, true))
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_notify_paidDealsSomeFailed"), successCount, failCount)
        )
    end

    -- Clean up and refresh display
    self.bulkPaymentData = nil
    self:updateDisplay()
end

UsedPlus.logInfo("FinanceManagerFrame loaded (row-based tables)")
