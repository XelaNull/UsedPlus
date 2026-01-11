--[[
    FS25_UsedPlus - UIHelper.lua

    Centralized UI utility module for consistent formatting and display
    Eliminates duplicate formatting code across 15+ dialogs
    All dialogs should use these helpers instead of inline formatting

    Modules:
    - UIHelper.Colors: Theme color palette
    - UIHelper.Text: Text formatting (money, percent, rates, terms, conditions)
    - UIHelper.Image: Vehicle/store item image loading
    - UIHelper.Credit: Credit score display with color coding
    - UIHelper.Element: GUI element manipulation helpers
]]

UIHelper = {}

-- ============================================================================
-- COLOR PALETTE
-- Centralized color definitions used across all dialogs
-- Previously 15+ dialogs defined these colors inline
-- ============================================================================

UIHelper.Colors = {
    -- Text colors
    WHITE = {1, 1, 1, 1},
    GRAY = {0.7, 0.7, 0.7, 1},
    DARK_GRAY = {0.6, 0.6, 0.6, 1},
    LIGHT_GRAY = {0.8, 0.8, 0.8, 1},

    -- Financial colors
    MONEY_GREEN = {0.3, 1, 0.3, 1},
    MONEY_LIGHT_GREEN = {0.5, 0.9, 0.5, 1},
    COST_ORANGE = {1, 0.6, 0.3, 1},
    DEBT_RED = {1, 0.5, 0.5, 1},
    WARNING_RED = {1, 0.4, 0.4, 1},

    -- Accent colors
    GOLD = {1, 0.8, 0, 1},
    HIGHLIGHT_GOLD = {1, 0.9, 0.5, 1},
    BLUE = {0.4, 0.7, 1, 1},

    -- Credit score colors
    CREDIT_EXCELLENT = {0, 1, 0, 1},        -- Green (750+)
    CREDIT_GOOD = {0.7, 0.7, 0, 1},         -- Yellow (670-749)
    CREDIT_FAIR = {1, 0.6, 0, 1},           -- Orange (580-669)
    CREDIT_POOR = {1, 0.3, 0.3, 1},         -- Red (<580)

    -- Trend colors
    TREND_UP = {0, 1, 0, 1},
    TREND_DOWN = {1, 0, 0, 1},
    TREND_STABLE = {1, 1, 1, 1},

    -- Background colors
    ROW_HIGHLIGHT = {0.2, 0.2, 0.2, 0.5},
    SECTION_BG = {0.15, 0.15, 0.15, 0.8},
}

-- ============================================================================
-- TEXT FORMATTING
-- Unified text formatting to replace 140+ inline format calls
-- ============================================================================

UIHelper.Text = {}

--[[
    Format currency amount
    @param amount - Number to format
    @param decimals - Decimal places (default 0)
    @param showSign - Show +/- sign (default true for negative)
    @param absolute - Use absolute value for display (default true)
    @return Formatted string like "$125,000"
]]
function UIHelper.Text.formatMoney(amount, decimals, showSign, absolute)
    decimals = decimals or 0
    showSign = showSign ~= false
    absolute = absolute ~= false
    return g_i18n:formatMoney(amount, decimals, showSign, absolute)
end

--[[
    Format money with explicit label prefix
    @param label - Label text (e.g., "Price", "Down Payment")
    @param amount - Number to format
    @return Formatted string like "Price: $125,000"
]]
function UIHelper.Text.formatMoneyWithLabel(label, amount)
    return string.format("%s: %s", label, UIHelper.Text.formatMoney(amount))
end

--[[
    Format percentage value
    @param value - Value to format (0.25 for 25%, or 25 for 25%)
    @param isDecimal - If true, value is decimal (0.25 = 25%), else raw (25 = 25%)
    @param decimals - Decimal places (default 0)
    @return Formatted string like "25%" or "25.50%"
]]
function UIHelper.Text.formatPercent(value, isDecimal, decimals)
    decimals = decimals or 0
    local pct = isDecimal and (value * 100) or value
    return string.format("%." .. decimals .. "f%%", pct)
end

--[[
    Format interest rate (always expects decimal, e.g., 0.08 for 8%)
    @param rateDecimal - Interest rate as decimal (0.08 = 8%)
    @param decimals - Decimal places (default 2)
    @return Formatted string like "8.00%"
]]
function UIHelper.Text.formatInterestRate(rateDecimal, decimals)
    decimals = decimals or 2
    return string.format("%." .. decimals .. "f%%", rateDecimal * 100)
end

--[[
    Format interest rate with credit rating
    @param rateDecimal - Interest rate as decimal
    @param creditRating - Credit rating string (e.g., "Good", "Excellent")
    @return Formatted string like "8.00% (Good)"
]]
function UIHelper.Text.formatInterestRateWithRating(rateDecimal, creditRating)
    return string.format("%.2f%% (%s)", rateDecimal * 100, creditRating or "Unknown")
end

--[[
    Format credit score with rating
    @param score - Numeric credit score
    @param rating - Rating string (optional, will be calculated if not provided)
    @return Formatted string like "720 (Good)"
]]
function UIHelper.Text.formatCreditScore(score, rating)
    if not rating and CreditScore then
        rating = CreditScore.getRating(score)
    end
    return string.format("%d (%s)", score, rating or "Unknown")
end

--[[
    Format term duration
    @param count - Number of units
    @param unit - Unit type: "year", "month", "day", "hour"
    @return Formatted string like "5 Years" or "1 Month"
]]
function UIHelper.Text.formatTerm(count, unit)
    unit = unit or "year"
    local singular = unit:sub(1,1):upper() .. unit:sub(2)
    local plural = singular .. "s"

    if count == 1 then
        return string.format("%d %s", count, singular)
    else
        return string.format("%d %s", count, plural)
    end
end

--[[
    Format term with abbreviated unit
    @param count - Number of units
    @param unit - Unit type: "year", "month"
    @return Formatted string like "5yr" or "12mo"
]]
function UIHelper.Text.formatTermShort(count, unit)
    local abbrev = {year = "yr", month = "mo", day = "d", hour = "hr"}
    return string.format("%d%s", count, abbrev[unit] or unit)
end

--[[
    Format vehicle/equipment condition from damage value
    @param damage - Damage value (0 = perfect, 1 = destroyed)
    @return Formatted string like "85%"
]]
function UIHelper.Text.formatCondition(damage)
    local percent = math.floor((1 - (damage or 0)) * 100)
    return string.format("%d%%", percent)
end

--[[
    Format condition with label
    @param damage - Damage value
    @param label - Label (default "Condition")
    @return Formatted string like "Condition: 85%"
]]
function UIHelper.Text.formatConditionWithLabel(damage, label)
    label = label or "Condition"
    return string.format("%s: %s", label, UIHelper.Text.formatCondition(damage))
end

--[[
    Format range of values
    @param min - Minimum value
    @param max - Maximum value
    @param formatter - Optional formatter function (default formatMoney)
    @return Formatted string like "$50,000 - $75,000"
]]
function UIHelper.Text.formatRange(min, max, formatter)
    formatter = formatter or UIHelper.Text.formatMoney
    return string.format("%s - %s", formatter(min), formatter(max))
end

--[[
    Format percentage range
    @param minPct - Minimum percentage (as decimal, e.g., 0.60 for 60%)
    @param maxPct - Maximum percentage (as decimal)
    @return Formatted string like "60-75%"
]]
function UIHelper.Text.formatPercentRange(minPct, maxPct)
    return string.format("%d-%d%%", math.floor(minPct * 100), math.floor(maxPct * 100))
end

--[[
    Format time duration in hours
    @param hours - Number of hours
    @return Formatted string like "2 days, 5 hours" or "12 hours"
]]
function UIHelper.Text.formatHours(hours)
    if hours > 24 then
        local days = math.floor(hours / 24)
        local remainingHours = hours % 24
        if remainingHours > 0 then
            return string.format("%d days, %d hours", days, remainingHours)
        else
            return string.format("%d days", days)
        end
    else
        return string.format("%d hours", hours)
    end
end

--[[
    Format number with thousands separator
    @param num - Number to format
    @param decimals - Decimal places (default 0)
    @return Formatted string like "1,234,567"
]]
function UIHelper.Text.formatNumber(num, decimals)
    decimals = decimals or 0
    return g_i18n:formatNumber(num, decimals)
end

-- ============================================================================
-- IMAGE HANDLING
-- Simplified vehicle image loading following RVB's working pattern
--
-- IMPORTANT: Proper image display requires BOTH:
-- 1. Correct XML profile (see docs/VEHICLE_IMAGE_DISPLAY.md):
--    - extends="baseReference"
--    - size="200px 200px" (SQUARE)
--    - imageSliceId="noSlice" (CRITICAL)
-- 2. Simple setImageFilename() call (this file handles that)
--
-- The XML profile does all the heavy lifting. These helpers just load the image.
-- ============================================================================

UIHelper.Image = {}

--[[
    Universal image setter - ONE function to handle all image sources

    IMPORTANT: The XML profile MUST have imageSliceId="noSlice" for correct display.
    See docs/VEHICLE_IMAGE_DISPLAY.md for the required profile pattern.

    @param imageElement - Bitmap element with setImageFilename method
    @param source - Can be:
                    - storeItem (table with .imageFilename)
                    - vehicle (table with .configFileName - will look up storeItem)
                    - string (direct image path)
                    - nil (hides the element)
    @return boolean - True if image was set successfully

    Examples:
        UIHelper.Image.set(self.vehicleImage, storeItem)           -- from store item
        UIHelper.Image.set(self.vehicleImage, vehicle)             -- from vehicle object
        UIHelper.Image.set(self.vehicleImage, "path/to/image.png") -- from path string
        UIHelper.Image.set(self.vehicleImage, listing.vehicleImageFile) -- from saved path
]]
function UIHelper.Image.set(imageElement, source)
    if not imageElement then
        return false
    end

    -- No source = hide element
    if not source then
        if imageElement.setVisible then
            imageElement:setVisible(false)
        end
        return false
    end

    local imagePath = nil

    -- Determine source type and extract image path
    if type(source) == "string" then
        -- Direct path string
        imagePath = source

    elseif type(source) == "table" then
        if source.imageFilename then
            -- It's a storeItem (has imageFilename property)
            imagePath = source.imageFilename
            if (not imagePath or imagePath == "") and source.imageFilenameFallback then
                imagePath = source.imageFilenameFallback
            end

        elseif source.configFileName then
            -- It's a vehicle (has configFileName) - look up storeItem
            local storeItem = g_storeManager:getItemByXMLFilename(source.configFileName)
            if storeItem then
                imagePath = storeItem.imageFilename
                if (not imagePath or imagePath == "") and storeItem.imageFilenameFallback then
                    imagePath = storeItem.imageFilenameFallback
                end
            end

        elseif source.vehicleImageFile then
            -- It's a listing object (has vehicleImageFile property)
            imagePath = source.vehicleImageFile
        end
    end

    -- Set the image or hide if no valid path
    if imagePath and imagePath ~= "" then
        imageElement:setImageFilename(imagePath)
        if imageElement.setVisible then
            imageElement:setVisible(true)
        end
        return true
    else
        if imageElement.setVisible then
            imageElement:setVisible(false)
        end
        return false
    end
end

-- ============================================================================
-- BACKWARD COMPATIBILITY ALIASES
-- These delegate to the unified set() function
-- ============================================================================

function UIHelper.Image.setStoreItemImage(imageElement, storeItem)
    return UIHelper.Image.set(imageElement, storeItem)
end

function UIHelper.Image.setVehicleImage(imageElement, vehicle)
    return UIHelper.Image.set(imageElement, vehicle)
end

function UIHelper.Image.setImagePath(imageElement, imagePath)
    return UIHelper.Image.set(imageElement, imagePath)
end

-- DEPRECATED: "Scaled" approach is obsolete with proper XML profiles
function UIHelper.Image.setStoreItemImageScaled(imageElement, storeItem, maxWidth, maxHeight)
    return UIHelper.Image.set(imageElement, storeItem)
end

-- ============================================================================
-- CREDIT DISPLAY
-- Unified credit score display with consistent color coding
-- ============================================================================

UIHelper.Credit = {}

--[[
    Get color for credit score
    @param score - Numeric credit score (300-850)
    @return Color table {r, g, b, a}
]]
function UIHelper.Credit.getScoreColor(score)
    if score >= 750 then
        return UIHelper.Colors.CREDIT_EXCELLENT
    elseif score >= 670 then
        return UIHelper.Colors.CREDIT_GOOD
    elseif score >= 580 then
        return UIHelper.Colors.CREDIT_FAIR
    else
        return UIHelper.Colors.CREDIT_POOR
    end
end

--[[
    Get credit rating text
    @param score - Numeric credit score
    @return Rating string
]]
function UIHelper.Credit.getRating(score)
    if CreditScore and CreditScore.getRating then
        return CreditScore.getRating(score)
    end

    -- Fallback if CreditScore not available
    if score >= 750 then
        return "Excellent"
    elseif score >= 670 then
        return "Good"
    elseif score >= 580 then
        return "Fair"
    else
        return "Poor"
    end
end

--[[
    Display credit score on text element(s)
    @param scoreElement - Text element for score number
    @param ratingElement - Text element for rating text (optional)
    @param score - Numeric credit score
    @param withColor - Apply color to score element (default true)
]]
function UIHelper.Credit.display(scoreElement, ratingElement, score, withColor)
    withColor = withColor ~= false  -- default true

    if scoreElement then
        scoreElement:setText(tostring(score))

        if withColor and scoreElement.setTextColor then
            local color = UIHelper.Credit.getScoreColor(score)
            scoreElement:setTextColor(unpack(color))
        end
    end

    if ratingElement then
        local rating = UIHelper.Credit.getRating(score)
        ratingElement:setText(string.format("(%s)", rating))
    end
end

--[[
    Display credit score with combined text (score and rating in one element)
    @param element - Text element for combined display
    @param score - Numeric credit score
    @param withColor - Apply color (default true)
]]
function UIHelper.Credit.displayCombined(element, score, withColor)
    withColor = withColor ~= false

    if element then
        local rating = UIHelper.Credit.getRating(score)
        element:setText(string.format("%d (%s)", score, rating))

        if withColor and element.setTextColor then
            local color = UIHelper.Credit.getScoreColor(score)
            element:setTextColor(unpack(color))
        end
    end
end

--[[
    Get trend display info
    @param trend - Trend value (positive = improving, negative = declining)
    @return table with {text, color}
]]
function UIHelper.Credit.getTrendDisplay(trend)
    if trend > 0 then
        return {text = "Improving", color = UIHelper.Colors.TREND_UP}
    elseif trend < 0 then
        return {text = "Declining", color = UIHelper.Colors.TREND_DOWN}
    else
        return {text = "Stable", color = UIHelper.Colors.TREND_STABLE}
    end
end

-- ============================================================================
-- ELEMENT HELPERS
-- Common GUI element manipulation patterns
-- ============================================================================

UIHelper.Element = {}

--[[
    Safely set text on element (with nil check)
    @param element - Text element
    @param text - Text to set
]]
function UIHelper.Element.setText(element, text)
    if element and element.setText then
        element:setText(text or "")
    end
end

--[[
    Safely set text with color
    @param element - Text element
    @param text - Text to set
    @param color - Color table {r, g, b, a}
]]
function UIHelper.Element.setTextWithColor(element, text, color)
    if element then
        if element.setText then
            element:setText(text or "")
        end
        if element.setTextColor and color then
            element:setTextColor(unpack(color))
        end
    end
end

--[[
    Safely set visibility
    @param element - GUI element
    @param visible - Boolean visibility
]]
function UIHelper.Element.setVisible(element, visible)
    if element and element.setVisible then
        element:setVisible(visible == true)
    end
end

--[[
    Safely set multiple elements visible/hidden
    @param elements - Table of GUI elements
    @param visible - Boolean visibility
]]
function UIHelper.Element.setMultipleVisible(elements, visible)
    for _, element in ipairs(elements) do
        UIHelper.Element.setVisible(element, visible)
    end
end

--[[
    Populate MultiTextOption with values
    @param element - MultiTextOption element
    @param values - Array of values
    @param formatter - Optional formatter function for each value
    @param initialState - Initial state index (1-based, default 1)
]]
function UIHelper.Element.populateMultiTextOption(element, values, formatter, initialState)
    if not element or not values then return end

    local texts = {}
    for _, value in ipairs(values) do
        if formatter then
            table.insert(texts, formatter(value))
        else
            table.insert(texts, tostring(value))
        end
    end

    element:setTexts(texts)
    element:setState(initialState or 1)
end

--[[
    Populate term selector (common pattern)
    @param element - MultiTextOption element
    @param terms - Array of term values
    @param unit - Unit type ("year" or "month")
    @param initialState - Initial state (default 1)
]]
function UIHelper.Element.populateTermSelector(element, terms, unit, initialState)
    UIHelper.Element.populateMultiTextOption(element, terms, function(val)
        return UIHelper.Text.formatTerm(val, unit)
    end, initialState)
end

--[[
    Populate percentage selector (common pattern)
    @param element - MultiTextOption element
    @param percentages - Array of percentage values (e.g., {0, 5, 10, 15, 20})
    @param initialState - Initial state (default 1)
]]
function UIHelper.Element.populatePercentSelector(element, percentages, initialState)
    UIHelper.Element.populateMultiTextOption(element, percentages, function(val)
        return UIHelper.Text.formatPercent(val, false, 0)
    end, initialState)
end

-- ============================================================================
-- FINANCIAL DISPLAY HELPERS
-- Common financial information display patterns
-- ============================================================================

UIHelper.Finance = {}

--[[
    Display monthly payment
    @param element - Text element
    @param amount - Payment amount
    @param withColor - Apply green color (default true)
]]
function UIHelper.Finance.displayMonthlyPayment(element, amount, withColor)
    withColor = withColor ~= false
    if element then
        element:setText(UIHelper.Text.formatMoney(amount))
        if withColor and element.setTextColor then
            element:setTextColor(unpack(UIHelper.Colors.HIGHLIGHT_GOLD))
        end
    end
end

--[[
    Display total cost
    @param element - Text element
    @param amount - Total amount
    @param withColor - Apply green color (default true)
]]
function UIHelper.Finance.displayTotalCost(element, amount, withColor)
    withColor = withColor ~= false
    if element then
        element:setText(UIHelper.Text.formatMoney(amount))
        if withColor and element.setTextColor then
            element:setTextColor(unpack(UIHelper.Colors.MONEY_GREEN))
        end
    end
end

--[[
    Display interest rate
    @param element - Text element
    @param rate - Interest rate as decimal (0.08 = 8%)
    @param withColor - Apply orange color (default true)
]]
function UIHelper.Finance.displayInterestRate(element, rate, withColor)
    withColor = withColor ~= false
    if element then
        element:setText(UIHelper.Text.formatInterestRate(rate))
        if withColor and element.setTextColor then
            element:setTextColor(unpack(UIHelper.Colors.COST_ORANGE))
        end
    end
end

--[[
    Display debt/balance (negative connotation)
    @param element - Text element
    @param amount - Debt amount
    @param withColor - Apply red color (default true)
]]
function UIHelper.Finance.displayDebt(element, amount, withColor)
    withColor = withColor ~= false
    if element then
        element:setText(UIHelper.Text.formatMoney(amount))
        if withColor and element.setTextColor then
            element:setTextColor(unpack(UIHelper.Colors.DEBT_RED))
        end
    end
end

--[[
    Display collateral/asset value
    @param element - Text element
    @param amount - Asset value
    @param withColor - Apply green color (default true)
]]
function UIHelper.Finance.displayAssetValue(element, amount, withColor)
    withColor = withColor ~= false
    if element then
        element:setText(UIHelper.Text.formatMoney(amount))
        if withColor and element.setTextColor then
            element:setTextColor(unpack(UIHelper.Colors.MONEY_GREEN))
        end
    end
end

-- ============================================================================
-- VEHICLE DISPLAY HELPERS
-- Common vehicle information display patterns
-- ============================================================================

UIHelper.Vehicle = {}

--[[
    Display vehicle condition (repair + paint)
    @param repairElement - Text element for repair percentage
    @param paintElement - Text element for paint percentage
    @param repairBar - Optional progress bar for repair
    @param paintBar - Optional progress bar for paint
    @param damage - Damage value (0-1, where 0 = perfect)
    @param wear - Wear value (0-1, where 0 = perfect)
]]
function UIHelper.Vehicle.displayCondition(repairElement, paintElement, repairBar, paintBar, damage, wear)
    local repairPercent = math.floor((1 - (damage or 0)) * 100)
    local paintPercent = math.floor((1 - (wear or 0)) * 100)

    if repairElement then
        repairElement:setText(string.format("%d%%", repairPercent))
    end

    if paintElement then
        paintElement:setText(string.format("%d%%", paintPercent))
    end

    if repairBar and repairBar.setValue then
        repairBar:setValue(repairPercent / 100)
    end

    if paintBar and paintBar.setValue then
        paintBar:setValue(paintPercent / 100)
    end
end

--[[
    Display combined condition summary
    @param element - Text element
    @param damage - Damage value
    @param wear - Wear value
    @return Average condition percentage
]]
function UIHelper.Vehicle.displayConditionSummary(element, damage, wear)
    local repairPercent = math.floor((1 - (damage or 0)) * 100)
    local paintPercent = math.floor((1 - (wear or 0)) * 100)
    local avgCondition = math.floor((repairPercent + paintPercent) / 2)

    if element then
        element:setText(string.format("Condition: %d%% (Repair: %d%%, Paint: %d%%)",
            avgCondition, repairPercent, paintPercent))
    end

    return avgCondition
end

--[[
    Display "USED" badge for used vehicles
    @param element - Text element for badge
    @param isUsed - Boolean, is this a used vehicle
    @param condition - Condition percentage (optional)
]]
function UIHelper.Vehicle.displayUsedBadge(element, isUsed, condition)
    if element then
        if isUsed then
            if condition then
                element:setText(string.format("USED - %d%% Condition", condition))
            else
                element:setText("USED")
            end
            element:setVisible(true)
        else
            element:setVisible(false)
        end
    end
end

--[[
    Resolve a potentially localized string value
    FS25 can store names as strings, l10n tables with .text, or arrays
    @param value - String, table with .text, or array
    @param fallback - Fallback value if resolution fails (default "Unknown")
    @return Resolved string
]]
function UIHelper.Vehicle.resolveL10nString(value, fallback)
    fallback = fallback or "Unknown"
    if value == nil then
        return fallback
    elseif type(value) == "string" then
        return value
    elseif type(value) == "table" then
        -- Could be l10n table with .text property or array
        return value.text or value[1] or tostring(value)
    else
        return tostring(value)
    end
end

--[[
    Get full vehicle name with brand prefix (e.g., "John Deere 6R 150")
    Consolidates duplicated pattern from 9+ files.
    Handles l10n tables for both brand and model names.
    @param storeItem - Store item from g_storeManager
    @return Full vehicle name string (brand + model)
]]
function UIHelper.Vehicle.getFullName(storeItem)
    if not storeItem then
        return "Unknown Vehicle"
    end

    -- Get model name (might be string or l10n table)
    local modelName = UIHelper.Vehicle.resolveL10nString(storeItem.name, "Vehicle")

    -- Try to get brand name
    if storeItem.brandIndex and g_brandManager then
        local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
        if brand then
            local brandName = UIHelper.Vehicle.resolveL10nString(brand.title or brand.name)
            if brandName and brandName ~= "Unknown" then
                return brandName .. " " .. modelName
            end
        end
    end

    return modelName
end

--[[
    Get full vehicle name from a vehicle object
    Convenience wrapper that first looks up the storeItem
    @param vehicle - Vehicle object with configFileName
    @return Full vehicle name string (brand + model)
]]
function UIHelper.Vehicle.getFullNameFromVehicle(vehicle)
    if not vehicle then
        return "Unknown Vehicle"
    end

    local storeItem = nil
    if vehicle.configFileName then
        storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    end

    return UIHelper.Vehicle.getFullName(storeItem)
end

--[[
    Get human-readable category name from store item
    Handles l10n keys (starting with $) and plain text
    @param storeItem - Store item from g_storeManager
    @return Category display name
]]
function UIHelper.Vehicle.getCategoryName(storeItem)
    if not storeItem then
        return "Equipment"
    end

    local categoryKey = storeItem.categoryName or storeItem.category
    if not categoryKey then
        return "Equipment"
    end

    local category = g_storeManager:getCategoryByName(categoryKey)
    if category and category.title then
        -- category.title might be plain text or l10n key (starting with $)
        local title = category.title
        if type(title) == "string" and title:sub(1, 1) == "$" then
            return g_i18n:getText(title:sub(2)) or categoryKey
        else
            return UIHelper.Vehicle.resolveL10nString(title, categoryKey)
        end
    end

    return categoryKey
end

-- ============================================================================

UsedPlus.logInfo("UIHelper loaded")
