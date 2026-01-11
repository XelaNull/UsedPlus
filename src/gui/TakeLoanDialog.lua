--[[
    FS25_UsedPlus - Take Loan Dialog

     Dialog for taking out general cash loans
     Pattern from: EnhancedLoanSystem TakeLoanDialog
     Integrates with UsedPlus credit score and finance manager

    Features:
    - Collateral-based maximum loan amount
    - Credit score affects max loan and interest rate
    - Real-time payment calculation as amount/term changes
    - Annuity-based repayment (constant monthly payment)
    - Shows total interest cost
]]

TakeLoanDialog = {}
local TakeLoanDialog_mt = Class(TakeLoanDialog, MessageDialog)

-- Loan term options (in years) - max 15 years for cash loans
TakeLoanDialog.TERM_OPTIONS = {1, 2, 3, 5, 7, 10, 15}

-- Amount step options
TakeLoanDialog.AMOUNT_STEPS = {1000, 5000, 10000, 25000, 50000, 100000}

-- Credit-based loan limits
-- Multiplier: What percentage of collateral can be borrowed
-- Cap: Absolute maximum loan regardless of collateral
-- Uses CreditScore tier levels (1=Excellent, 5=Very Poor)
TakeLoanDialog.CREDIT_LOAN_LIMITS = {
    [1] = { multiplier = 1.00, cap = 5000000, name = "Excellent" },  -- 750+: 100%, max $5M
    [2] = { multiplier = 0.80, cap = 2000000, name = "Good" },       -- 700-749: 80%, max $2M
    [3] = { multiplier = 0.60, cap = 500000, name = "Fair" },        -- 650-699: 60%, max $500k
    [4] = { multiplier = 0.40, cap = 250000, name = "Poor" },        -- 600-649: 40%, max $250k
    [5] = { multiplier = 0.20, cap = 100000, name = "Very Poor" },   -- <600: 20%, max $100k
}

--[[
     Constructor
]]
function TakeLoanDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or TakeLoanDialog_mt)

    self.i18n = i18n or g_i18n

    -- Farm data
    self.farmId = 0
    self.farmMoney = 0

    -- Collateral data
    self.vehicleCollateral = 0
    self.landCollateral = 0
    self.totalCollateral = 0
    self.existingDebt = 0

    -- Credit data
    self.creditScore = 650
    self.creditRating = "Fair"  -- Capitalized to match CreditScore.getRating() output
    self.creditMultiplier = 0.6  -- Default to Fair tier multiplier
    self.creditCap = 500000      -- Default to Fair tier cap

    -- Loan parameters
    self.maxLoanAmount = 0
    self.loanAmount = 0
    self.termYears = 5
    self.termIndex = 4  -- Index in TERM_OPTIONS (5 years)
    self.amountStepIndex = 3  -- Index in AMOUNT_STEPS ($25,000)

    -- Calculated values
    self.interestRate = 0.08  -- 8% base
    self.monthlyPayment = 0
    self.totalPayment = 0
    self.totalInterest = 0

    -- Collateral selection (for cash loans)
    self.selectedCollateral = {}  -- Array of selected collateral items
    self.selectedCollateralValue = 0  -- Total value of selected collateral

    -- Eligible assets for collateral (built in calculateCollateral)
    self.eligibleAssets = {}  -- Array of {type, id, name, value, selected}
    self.maxDisplayRows = 5   -- Number of rows in the UI
    self.pageOffset = 0       -- Current page offset (0-indexed)

    return self
end

--[[
     Called when GUI elements are ready
     Element references are auto-populated by g_gui based on XML id attributes
     No manual caching needed - removed redundant self.x = self.x patterns
]]
function TakeLoanDialog:onGuiSetupFinished()
    TakeLoanDialog:superClass().onGuiSetupFinished(self)
    -- UI elements automatically available via XML id attributes:
    -- creditScoreText, creditRatingText, interestRateText
    -- vehicleCollateralText, landCollateralText, existingDebtText, maxLoanText
    -- loanAmountSlider (MultiTextOption), termSlider (MultiTextOption)
    -- monthlyPaymentText, yearlyPaymentText, totalPaymentText, totalInterestText
    -- acceptButton, cancelButton
end

--[[
     Initialize dialog with farm data
    @param farmId - Farm ID taking the loan
]]
function TakeLoanDialog:setFarmId(farmId)
    self.farmId = farmId

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError("TakeLoanDialog - Farm not found")
        return
    end

    self.farmMoney = farm.money or 0
    self.pageOffset = 0  -- Reset pagination

    -- Calculate collateral values
    self:calculateCollateral(farm)

    -- Get credit score and adjust parameters
    self:calculateCreditParameters()

    -- Calculate maximum loan amount
    self:calculateMaxLoanAmount()

    -- Populate MultiTextOption dropdowns with appropriate choices
    self:populateLoanAmountOptions()
    self:populateTermOptions()

    -- Note: Collateral is now manually selected via UI (all assets selected by default)

    -- Calculate payments based on defaults
    self:calculatePayments()

    -- Update display
    self:updateDisplay()

    UsedPlus.logDebug(string.format("TakeLoanDialog initialized for farm %d", farmId))
    UsedPlus.logTrace(string.format("  Credit Score: %d (%s)", self.creditScore, self.creditRating))
    UsedPlus.logTrace(string.format("  Vehicle Collateral: $%d", self.vehicleCollateral))
    UsedPlus.logTrace(string.format("  Land Collateral: $%d", self.landCollateral))
    UsedPlus.logTrace(string.format("  Existing Debt: $%d", self.existingDebt))
    UsedPlus.logTrace(string.format("  Max Loan: $%d", self.maxLoanAmount))
    UsedPlus.logTrace(string.format("  Interest Rate: %.2f%%", self.interestRate * 100))
end

--[[
     Calculate collateral from vehicles and land
     Pattern from: EnhancedLoanSystem (50% vehicles, 60% land)
     Only count UNENCUMBERED assets (not already financed/mortgaged)
     Now builds eligibleAssets list for UI selection
]]
function TakeLoanDialog:calculateCollateral(farm)
    -- Reset eligible assets list
    self.eligibleAssets = {}

    -- First, build lookup of already-pledged/financed items using UNIQUE identifiers
    -- This prevents the same vehicle from being pledged to multiple loans
    local excludedLandIds = {}
    local excludedVehicleIds = {}

    self.existingDebt = 0
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farm.farmId)
        if deals then
            for _, deal in pairs(deals) do
                if deal.status == "active" then
                    self.existingDebt = self.existingDebt + (deal.currentBalance or 0)

                    -- Track PRIMARY financed items
                    if deal.itemType == "land" and deal.itemId then
                        excludedLandIds[tostring(deal.itemId)] = true
                    elseif deal.itemType == "vehicle" then
                        -- For financed vehicles, get unique ID from the actual vehicle object
                        if deal.objectId then
                            local vehicle = NetworkUtil.getObject(deal.objectId)
                            if vehicle and CollateralUtils then
                                local uniqueId = CollateralUtils.getVehicleIdentifier(vehicle)
                                excludedVehicleIds[uniqueId] = true
                            end
                        end
                    end

                    -- CRITICAL: Track vehicles pledged as COLLATERAL for loans
                    -- collateralItems stores vehicleId in unique format from CollateralUtils
                    if deal.collateralItems then
                        for _, item in ipairs(deal.collateralItems) do
                            if item.vehicleId then
                                -- vehicleId is already in unique format (e.g., "id:123" or "obj:456:config")
                                excludedVehicleIds[item.vehicleId] = true
                            end
                            if item.type == "land" and item.id then
                                excludedLandIds[tostring(item.id)] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Vehicle collateral (50% of depreciated value)
    -- Only count vehicles that are NOT already financed or pledged
    self.vehicleCollateral = 0
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farm.farmId and
           vehicle.propertyState == VehiclePropertyState.OWNED then
            -- Get UNIQUE vehicle identifier (distinguishes between identical vehicles)
            local vehicleUniqueId = ""
            if CollateralUtils and CollateralUtils.getVehicleIdentifier then
                vehicleUniqueId = CollateralUtils.getVehicleIdentifier(vehicle)
            else
                -- Fallback: use object ID + config (still unique per instance)
                local objectId = NetworkUtil.getObjectId(vehicle) or 0
                vehicleUniqueId = string.format("obj:%d:%s", objectId, vehicle.configFileName or "")
            end

            -- Check if this specific vehicle instance is already pledged/financed
            local isExcluded = excludedVehicleIds[vehicleUniqueId] or false
            if not isExcluded then
                local sellPrice = vehicle:getSellPrice() or 0
                local collateralValue = math.floor(sellPrice * 0.5)

                if collateralValue > 0 then
                    -- Get vehicle name and category using consolidated utilities
                    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
                    local vehicleName = UIHelper.Vehicle.getFullName(storeItem)
                    local vehicleCategory = UIHelper.Vehicle.getCategoryName(storeItem)

                    -- Store with UNIQUE vehicleId for proper tracking
                    table.insert(self.eligibleAssets, {
                        type = "vehicle",
                        vehicleId = vehicleUniqueId,  -- Unique per instance!
                        id = vehicle.configFileName,   -- Keep for display/lookup
                        objectId = NetworkUtil.getObjectId(vehicle),
                        configFile = vehicle.configFileName,
                        name = vehicleName,
                        category = vehicleCategory,
                        value = collateralValue,
                        selected = true,  -- Default selected
                        vehicle = vehicle
                    })

                    self.vehicleCollateral = self.vehicleCollateral + collateralValue
                end
            end
        end
    end

    -- Land collateral (60% of purchase price)
    -- Must use g_farmlandManager:getFarmlands() and getFarmlandOwner() methods
    -- Only count land that is NOT already financed/mortgaged
    self.landCollateral = 0
    if g_farmlandManager then
        local farmlands = g_farmlandManager:getFarmlands()
        if farmlands then
            for _, farmland in pairs(farmlands) do
                local ownerId = g_farmlandManager:getFarmlandOwner(farmland.id)
                if ownerId == farm.farmId then
                    -- Check if this land is already financed or pledged as collateral
                    local isExcluded = excludedLandIds[tostring(farmland.id)] or false
                    if not isExcluded then
                        local collateralValue = math.floor((farmland.price or 0) * 0.6)

                        if collateralValue > 0 then
                            table.insert(self.eligibleAssets, {
                                type = "land",
                                id = farmland.id,
                                name = string.format("Land Parcel #%d", farmland.id),
                                category = "Land",
                                value = collateralValue,
                                selected = true,  -- Default selected
                                farmland = farmland
                            })

                            self.landCollateral = self.landCollateral + collateralValue
                        end
                    end
                end
            end
        end
    end

    -- Sort assets by value (highest first)
    table.sort(self.eligibleAssets, function(a, b) return a.value > b.value end)

    -- Calculate selected collateral value
    self:recalculateSelectedCollateral()

    UsedPlus.logDebug(string.format("Found %d eligible assets for collateral", #self.eligibleAssets))
end

--[[
    Recalculate selected collateral value based on current selections
]]
function TakeLoanDialog:recalculateSelectedCollateral()
    self.selectedCollateralValue = 0
    self.selectedCollateral = {}

    for _, asset in ipairs(self.eligibleAssets) do
        if asset.selected then
            self.selectedCollateralValue = self.selectedCollateralValue + asset.value
            table.insert(self.selectedCollateral, asset)
        end
    end

    -- Total collateral (cash + selected assets)
    self.totalCollateral = self.farmMoney + self.selectedCollateralValue
end

--[[
    v2.0.0: Helper function to check if credit system is enabled
]]
function TakeLoanDialog.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true  -- Default to enabled
end

--[[
     Calculate credit-based parameters
     Uses UsedPlus CreditScore system with stricter loan limits
     v2.0.0: Respects enableCreditSystem setting - uses defaults when disabled

     Credit affects:
     1. Interest rate (higher rate for lower scores)
     2. Collateral multiplier (% of collateral you can borrow)
     3. Absolute loan cap (hard limit regardless of collateral)
]]
function TakeLoanDialog:calculateCreditParameters()
    -- Get credit score and tier level
    local creditLevel = 3  -- Default to Fair
    local creditEnabled = TakeLoanDialog.isCreditSystemEnabled()

    if creditEnabled and CreditScore then
        self.creditScore = CreditScore.calculate(self.farmId)
        self.creditRating, creditLevel = CreditScore.getRating(self.creditScore)

        -- Interest rate adjustment based on credit
        local baseRate = 0.08  -- 8% base rate
        local adjustment = CreditScore.getInterestAdjustment(self.creditScore) / 100
        self.interestRate = baseRate + adjustment

        -- Clamp interest rate (cash loans are riskier, so higher floor)
        self.interestRate = math.max(0.05, math.min(0.18, self.interestRate))
    else
        -- Credit system disabled - use defaults
        self.creditScore = 650
        self.creditRating = "Fair"
        self.interestRate = 0.08
        creditLevel = 3
    end

    -- Get loan limits from credit tier
    local limits = TakeLoanDialog.CREDIT_LOAN_LIMITS[creditLevel] or TakeLoanDialog.CREDIT_LOAN_LIMITS[3]
    self.creditMultiplier = limits.multiplier
    self.creditCap = limits.cap

    UsedPlus.logDebug(string.format("Credit tier %d (%s): %.0f%% multiplier, $%d cap",
        creditLevel, limits.name, limits.multiplier * 100, limits.cap))
end

--[[
     Calculate maximum loan amount based on collateral and credit
     Formula: min(Collateral × Credit Multiplier - Existing Debt, Credit Cap)

     Two limits applied:
     1. Collateral-based: Can only borrow % of assets based on credit
     2. Absolute cap: Hard limit based on credit tier (even billionaires with bad credit get limited)
]]
function TakeLoanDialog:calculateMaxLoanAmount()
    -- Base max from collateral (already reduced by credit multiplier)
    local collateralMax = self.totalCollateral * self.creditMultiplier

    -- Subtract existing debt (prevents over-leveraging)
    -- Penalty: existing debt counts 1.5x against borrowing capacity
    local adjustedMax = collateralMax - (self.existingDebt * 1.5)

    -- Floor at 0, round to nearest $1000
    adjustedMax = math.max(0, math.floor(adjustedMax / 1000) * 1000)

    -- Apply credit-based absolute cap (the real limiter for poor credit)
    local creditCap = self.creditCap or 500000
    self.maxLoanAmount = math.min(adjustedMax, creditCap)

    UsedPlus.logDebug(string.format("Max loan calc: Collateral $%d × %.0f%% = $%d, after debt = $%d, credit cap = $%d, final = $%d",
        self.totalCollateral, self.creditMultiplier * 100, math.floor(collateralMax),
        math.floor(adjustedMax), creditCap, self.maxLoanAmount))
end

-- Note: Old selectCollateralForLoan() removed - now using manual selection via UI

--[[
     Calculate monthly payment using centralized formula
     Refactored to use FinanceCalculations.calculateMonthlyPayment()
]]
function TakeLoanDialog:calculatePayments()
    if self.loanAmount <= 0 or self.termYears <= 0 then
        self.monthlyPayment = 0
        self.totalPayment = 0
        self.totalInterest = 0
        return
    end

    local months = self.termYears * 12

    -- Use centralized calculation function
    self.monthlyPayment, self.totalInterest = FinanceCalculations.calculateMonthlyPayment(
        self.loanAmount,
        self.interestRate,
        months
    )

    -- Total payment over loan life
    self.totalPayment = self.monthlyPayment * months
end

--[[
     Populate the loan amount MultiTextOption with amount choices
     Creates discrete choices based on max loan amount
]]
function TakeLoanDialog:populateLoanAmountOptions()
    if self.loanAmountSlider == nil then
        return
    end

    -- Generate amount options based on max loan
    self.amountOptions = {}
    local step = math.max(10000, math.floor(self.maxLoanAmount / 20 / 10000) * 10000)  -- Round to $10k

    for amount = step, self.maxLoanAmount, step do
        table.insert(self.amountOptions, amount)
    end

    -- Ensure max is included
    if #self.amountOptions == 0 or self.amountOptions[#self.amountOptions] ~= self.maxLoanAmount then
        table.insert(self.amountOptions, self.maxLoanAmount)
    end

    -- Create text labels
    local texts = {}
    for _, amount in ipairs(self.amountOptions) do
        table.insert(texts, g_i18n:formatMoney(amount, 0, true, true))
    end

    self.loanAmountSlider:setTexts(texts)

    -- Set default to 50% of options
    local defaultIndex = math.ceil(#self.amountOptions / 2)
    self.amountIndex = defaultIndex
    self.loanAmountSlider:setState(defaultIndex)
    self.loanAmount = self.amountOptions[defaultIndex] or 0
end

--[[
     Populate the term MultiTextOption with year choices
     Refactored to use UIHelper.Element.populateTermSelector
]]
function TakeLoanDialog:populateTermOptions()
    if self.termSlider == nil then return end
    UIHelper.Element.populateTermSelector(self.termSlider, TakeLoanDialog.TERM_OPTIONS, "year", self.termIndex)
end

--[[
     Update all UI elements
     Refactored to use UIHelper for consistent formatting and color coding
     v2.0.0: Respects enableCreditSystem setting - hides credit section when disabled
]]
function TakeLoanDialog:updateDisplay()
    local creditEnabled = TakeLoanDialog.isCreditSystemEnabled()

    -- v2.0.0: Hide credit section when credit system disabled
    if self.creditSection then
        self.creditSection:setVisible(creditEnabled)
    end

    -- Credit info - score only (rating shown in table with highlighting)
    if creditEnabled then
        UIHelper.Credit.display(self.creditScoreText, nil, self.creditScore)
        -- Highlight the user's current credit tier in the rating table
        self:highlightCreditTier()
    end

    -- Interest rate (orange = cost)
    UIHelper.Finance.displayInterestRate(self.interestRateText, self.interestRate)

    -- Populate the collateral asset list
    self:populateAssetList()

    -- Selected collateral total (green = assets)
    UIHelper.Finance.displayAssetValue(self.selectedCollateralText, self.selectedCollateralValue)

    -- Existing debt (red = liability)
    UIHelper.Finance.displayDebt(self.existingDebtText, self.existingDebt)

    -- Max loan available (green = opportunity)
    UIHelper.Finance.displayTotalCost(self.maxLoanText, self.maxLoanAmount)

    -- Payment preview
    UIHelper.Finance.displayMonthlyPayment(self.monthlyPaymentText, self.monthlyPayment)
    UIHelper.Element.setText(self.yearlyPaymentText, UIHelper.Text.formatMoney(self.monthlyPayment * 12))
    UIHelper.Element.setText(self.totalPaymentText, UIHelper.Text.formatMoney(self.totalPayment))

    -- Total interest (orange = cost)
    UIHelper.Element.setTextWithColor(self.totalInterestText, UIHelper.Text.formatMoney(self.totalInterest), UIHelper.Colors.COST_ORANGE)

    -- Update info text with collateral information
    if self.infoText then
        local infoMsg = "Loan funds deposited immediately. Payments auto-deducted monthly."
        if #self.selectedCollateral > 0 then
            infoMsg = string.format("%d asset(s) pledged as collateral. Miss 3 payments = repossession!", #self.selectedCollateral)
        end
        self.infoText:setText(infoMsg)
    end

    -- Enable/disable accept button
    if self.acceptButton then
        local canAccept = self.loanAmount > 0 and self.loanAmount <= self.maxLoanAmount
        self.acceptButton:setDisabled(not canAccept)
    end
end

--[[
    Populate the asset list UI with eligible assets
    Shows up to maxDisplayRows assets with pagination, with checkboxes for selection
]]
function TakeLoanDialog:populateAssetList()
    -- Colors for row backgrounds
    local selectedColor = {0.15, 0.25, 0.15, 0.8}  -- Green tint when selected
    local unselectedColor = {0.1, 0.1, 0.14, 0.6}  -- Gray when unselected

    local totalAssets = #self.eligibleAssets
    local totalPages = math.max(1, math.ceil(totalAssets / self.maxDisplayRows))
    local currentPage = math.floor(self.pageOffset / self.maxDisplayRows) + 1

    for i = 1, self.maxDisplayRows do
        local rowElement = self["assetRow" .. i]
        local rowBg = self["assetRow" .. i .. "Bg"]
        local checkElement = self["assetRow" .. i .. "Check"]
        local nameElement = self["assetRow" .. i .. "Name"]
        local categoryElement = self["assetRow" .. i .. "Category"]
        local valueElement = self["assetRow" .. i .. "Value"]
        local btnElement = self["assetBtn" .. i]

        -- Calculate actual asset index with pagination offset
        local assetIndex = self.pageOffset + i
        local asset = self.eligibleAssets[assetIndex]

        if asset and rowElement then
            -- Show this row
            UIHelper.Element.setVisible(rowElement, true)
            if btnElement then UIHelper.Element.setVisible(btnElement, true) end

            -- Set checkbox (☑ or ☐)
            if checkElement then
                checkElement:setText(asset.selected and "☑" or "☐")
                -- Green when selected, gray when not
                if asset.selected then
                    checkElement:setTextColor(0.3, 1, 0.4, 1)
                else
                    checkElement:setTextColor(0.5, 0.5, 0.5, 1)
                end
            end

            -- Set name (with type prefix)
            if nameElement then
                local prefix = asset.type == "land" and "🏞️ " or "🚜 "
                nameElement:setText(prefix .. asset.name)
            end

            -- Set category
            if categoryElement then
                categoryElement:setText(asset.category or "")
            end

            -- Set value
            if valueElement then
                valueElement:setText(g_i18n:formatMoney(asset.value))
            end

            -- Set row background color
            if rowBg and rowBg.setImageColor then
                local color = asset.selected and selectedColor or unselectedColor
                rowBg:setImageColor(nil, color[1], color[2], color[3], color[4])
            end
        else
            -- Hide unused rows
            if rowElement then UIHelper.Element.setVisible(rowElement, false) end
            if btnElement then UIHelper.Element.setVisible(btnElement, false) end
        end
    end

    -- Update page indicator
    if self.pageIndicatorText then
        self.pageIndicatorText:setText(string.format("%d / %d", currentPage, totalPages))
    end

    -- Enable/disable pagination buttons
    if self.prevPageBtn then
        self.prevPageBtn:setDisabled(self.pageOffset == 0)
    end
    if self.nextPageBtn then
        local maxOffset = math.max(0, totalAssets - self.maxDisplayRows)
        self.nextPageBtn:setDisabled(self.pageOffset >= maxOffset)
    end
end

--[[
    Toggle asset selection at given row index (1-5)
    Accounts for pagination offset
]]
function TakeLoanDialog:toggleAsset(rowIndex)
    -- Convert row index to actual asset index with pagination
    local assetIndex = self.pageOffset + rowIndex
    local asset = self.eligibleAssets[assetIndex]
    if asset then
        asset.selected = not asset.selected
        UsedPlus.logDebug(string.format("Toggled asset %d (%s): %s",
            assetIndex, asset.name, asset.selected and "selected" or "unselected"))

        -- Recalculate collateral and max loan
        self:recalculateSelectedCollateral()
        self:calculateMaxLoanAmount()
        self:populateLoanAmountOptions()

        -- Recalculate payments with new constraints
        self:calculatePayments()
        self:updateDisplay()
    end
end

-- Row click handlers
function TakeLoanDialog:onAssetRow1Click()
    self:toggleAsset(1)
end

function TakeLoanDialog:onAssetRow2Click()
    self:toggleAsset(2)
end

function TakeLoanDialog:onAssetRow3Click()
    self:toggleAsset(3)
end

function TakeLoanDialog:onAssetRow4Click()
    self:toggleAsset(4)
end

function TakeLoanDialog:onAssetRow5Click()
    self:toggleAsset(5)
end

--[[
    Pagination: Show previous page of assets
]]
function TakeLoanDialog:onPrevPage()
    if self.pageOffset > 0 then
        self.pageOffset = math.max(0, self.pageOffset - self.maxDisplayRows)
        self:populateAssetList()
    end
end

--[[
    Pagination: Show next page of assets
]]
function TakeLoanDialog:onNextPage()
    local maxOffset = math.max(0, #self.eligibleAssets - self.maxDisplayRows)
    if self.pageOffset < maxOffset then
        self.pageOffset = math.min(maxOffset, self.pageOffset + self.maxDisplayRows)
        self:populateAssetList()
    end
end

--[[
    Highlight the user's credit tier in the rating table
    Dims all rows except the one matching user's score
    Tiers match CreditSystem.lua getRating() function
]]
function TakeLoanDialog:highlightCreditTier()
    local score = self.creditScore or 650

    -- Define which element to highlight based on score (matches CreditSystem.lua)
    local activeRating = nil
    if score >= 750 then
        activeRating = "ratingExcellent"
    elseif score >= 700 then
        activeRating = "ratingGood"
    elseif score >= 650 then
        activeRating = "ratingFair"
    elseif score >= 600 then
        activeRating = "ratingPoor"
    else  -- < 600
        activeRating = "ratingVeryPoor"
    end

    -- All rating row IDs (5 tiers matching CreditSystem.lua)
    local ratingRows = {
        "ratingExcellent", "ratingGood", "ratingFair",
        "ratingPoor", "ratingVeryPoor"
    }

    -- Highlight active, dim others
    for _, rowId in ipairs(ratingRows) do
        local element = self[rowId]
        if element then
            if rowId == activeRating then
                -- Highlighted row - gold/yellow, bold
                element:setTextColor(1, 0.85, 0.2, 1)
            else
                -- Dimmed row - gray
                element:setTextColor(0.4, 0.4, 0.4, 1)
            end
        end
    end
end

--[[
     Loan amount MultiTextOption changed
     Called when user selects a different amount from dropdown
]]
function TakeLoanDialog:onLoanAmountChanged()
    if self.loanAmountSlider == nil or self.amountOptions == nil then
        return
    end

    -- Get selected state from MultiTextOption
    local state = self.loanAmountSlider:getState()
    if state > 0 and state <= #self.amountOptions then
        self.amountIndex = state
        self.loanAmount = self.amountOptions[state]

        -- Note: Collateral selection is now manual via UI, no auto-select needed

        self:calculatePayments()
        self:updateDisplay()
    end
end

--[[
     Term MultiTextOption changed
     Called when user selects a different term from dropdown
]]
function TakeLoanDialog:onTermChanged()
    if self.termSlider == nil then
        return
    end

    -- Get selected state from MultiTextOption
    local state = self.termSlider:getState()
    if state > 0 and state <= #TakeLoanDialog.TERM_OPTIONS then
        self.termIndex = state
        self.termYears = TakeLoanDialog.TERM_OPTIONS[state]

        self:calculatePayments()
        self:updateDisplay()
    end
end

--[[
     Accept loan button clicked
]]
function TakeLoanDialog:onAcceptLoan()
    if self.loanAmount <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "Please select a loan amount"
        )
        return
    end

    if self.loanAmount > self.maxLoanAmount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Loan amount exceeds maximum allowed"
        )
        return
    end

    -- Warn if no collateral is selected
    if #self.selectedCollateral == 0 and self.loanAmount > 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Please select at least one asset as collateral"
        )
        return
    end

    -- Calculate credit score impact (loan taking has -5 impact per CreditHistory.EVENT_TYPES.LOAN_TAKEN)
    local currentScore = self.creditScore
    local creditImpact = -5  -- LOAN_TAKEN event
    local newScore = math.max(CreditScore.MIN_SCORE, currentScore + creditImpact)
    local currentRating = self.creditRating
    local newRating = CreditScore.getRating(newScore)

    -- Store loan details for confirmation dialog (before closing)
    local loanDetails = {
        amount = self.loanAmount,
        termYears = self.termYears,
        interestRate = self.interestRate,
        monthlyPayment = self.monthlyPayment,
        yearlyPayment = self.monthlyPayment * 12,
        totalPayment = self.totalPayment,
        totalInterest = self.totalInterest,
        collateralCount = #self.selectedCollateral,
        -- Credit impact info
        previousScore = currentScore,
        previousRating = currentRating,
        creditImpact = creditImpact,
        newScore = newScore,
        newRating = newRating
    }

    -- Send loan event to server with collateral
    TakeLoanEvent.sendToServer(
        self.farmId,
        self.loanAmount,
        self.termYears,
        self.interestRate,
        self.monthlyPayment,
        self.selectedCollateral  -- Pass the selected collateral items
    )

    -- Close dialog
    self:close()

    -- Refresh the ESC menu page to show the new loan
    if FinanceManagerFrame and FinanceManagerFrame.refresh then
        FinanceManagerFrame.refresh()
    end

    -- Show confirmation dialog with full loan terms
    self:showLoanConfirmationDialog(loanDetails)
end

--[[
    Show a confirmation dialog with full loan terms after loan is executed
    @param details - Table with loan details (amount, term, rates, payments, credit impact)
]]
function TakeLoanDialog:showLoanConfirmationDialog(details)
    -- Use styled LoanApprovedDialog instead of plain InfoDialog
    LoanApprovedDialog.show(details)
end

--[[
     Cancel button clicked
]]
function TakeLoanDialog:onCancel()
    self:close()
end

UsedPlus.logInfo("TakeLoanDialog loaded")
