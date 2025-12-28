--[[
    FS25_UsedPlus - Main Initialization

    main.lua is the entry point that initializes the mod
    Pattern from: EnhancedLoanSystem, BuyUsedEquipment main initialization
    Reference: FS25_ADVANCED_PATTERNS.md - Game System Modification via Function Hooking

    Responsibilities:
    - Initialize global managers (g_financeManager, g_usedVehicleManager)
    - Hook into mission lifecycle (load, save, start)
    - Extend game classes (Farm, ShopConfigScreen, etc.)
    - Register GUI screens
    - Subscribe to game events

    Load order:
    - UsedPlusCore.lua loads FIRST (defines UsedPlus global and logging)
    - This file loads LAST (after all dependencies) to set up lifecycle hooks
]]

-- UsedPlus global is already defined by UsedPlusCore.lua
-- Just set up the class metatable for instance methods
local UsedPlus_mt = Class(UsedPlus)

--[[
    Constructor
    Creates singleton instance
]]
function UsedPlus.new()
    local self = setmetatable({}, UsedPlus_mt)

    self.isInitialized = false

    return self
end

--[[
    Initialize mod after mission loads
    Called from mission lifecycle hook
]]
function UsedPlus:initialize()
    if self.isInitialized then
        UsedPlus.logWarn("Already initialized, skipping")
        return
    end

    UsedPlus.logInfo("Initializing mod...")

    -- Create global managers (pattern from EnhancedLoanSystem)
    g_financeManager = FinanceManager.new()
    g_usedVehicleManager = UsedVehicleManager.new()
    g_vehicleSaleManager = VehicleSaleManager.new()  -- NEW - Agent-based vehicle sales

    -- Register managers with mission for event handling
    if g_currentMission then
        addModEventListener(g_financeManager)
        addModEventListener(g_usedVehicleManager)
        addModEventListener(g_vehicleSaleManager)  -- NEW
    end

    -- Initialize extensions that require delayed initialization
    -- Note: ShopConfigScreenExtension and InGameMenuMapFrameExtension
    -- install hooks at load time with safety checks

    if FarmlandManagerExtension and FarmlandManagerExtension.init then
        FarmlandManagerExtension:init()
    end

    if VehicleExtension and VehicleExtension.init then
        VehicleExtension:init()
    end

    -- Initialize vehicle sell hook (ESC -> Vehicles -> Sell button)
    -- This must be called after mission loads because InGameMenuVehiclesFrame
    -- may not exist at script load time
    if InGameMenuVehiclesFrameExtension and InGameMenuVehiclesFrameExtension.init then
        InGameMenuVehiclesFrameExtension:init()
    end

    -- Initialize workshop screen hook (Repair/Repaint screen -> Inspect button)
    if WorkshopScreenExtension and WorkshopScreenExtension.init then
        WorkshopScreenExtension:init()
    end

    -- Register GUI screens (will be populated when GUI classes exist)
    -- g_gui:loadProfiles is handled by modDesc.xml <gui> entries

    -- Register all dialogs with DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.registerAll then
        DialogLoader.registerAll()
    end

    -- Register input actions for hotkeys
    self:registerInputActions()

    self.isInitialized = true

    UsedPlus.logInfo("Initialization complete")
    UsedPlus.logDebug("FinanceManager: " .. tostring(g_financeManager ~= nil))
    UsedPlus.logDebug("UsedVehicleManager: " .. tostring(g_usedVehicleManager ~= nil))
end

--[[
    Mission lifecycle hooks
    Pattern from: EnhancedLoanSystem, BuyUsedEquipment
    Hook into mission load/save/start for mod integration
]]

-- Hook mission load finished (before mission starts)
Mission00.loadMission00Finished = Utils.appendedFunction(
    Mission00.loadMission00Finished,
    function(mission)
        UsedPlus.logInfo("Mission load finished, initializing mod")

        if UsedPlus.instance == nil then
            UsedPlus.instance = UsedPlus.new()
        end

        UsedPlus.instance:initialize()

        -- v1.8.0: Initialize cross-mod compatibility (RVB, UYT detection)
        ModCompatibility.init()
    end
)

-- Hook mission start (after map fully loaded)
Mission00.onStartMission = Utils.appendedFunction(
    Mission00.onStartMission,
    function(mission)
        UsedPlus.logInfo("Mission started")

        -- Initialize managers (call loadMapFinished)
        UsedPlus.logDebug("Initializing managers...")
        if g_financeManager and g_financeManager.loadMapFinished then
            g_financeManager:loadMapFinished()
            UsedPlus.logDebug("FinanceManager initialized")
        end

        if g_usedVehicleManager and g_usedVehicleManager.loadMapFinished then
            g_usedVehicleManager:loadMapFinished()
            UsedPlus.logDebug("UsedVehicleManager initialized")
        end

        -- NEW - Initialize Vehicle Sale Manager for agent-based sales
        if g_vehicleSaleManager and g_vehicleSaleManager.loadMapFinished then
            g_vehicleSaleManager:loadMapFinished()
            UsedPlus.logDebug("VehicleSaleManager initialized")
        end

        -- ESC InGameMenu integration using EnhancedLoanSystem pattern
        UsedPlus.logDebug("Adding InGameMenu (ESC) integration...")

        -- Create frame instance and store global reference for refresh
        local financeFrame = FinanceManagerFrame.new()
        g_usedPlusFinanceFrame = financeFrame

        -- Load GUI XML
        local xmlPath = Utils.getFilename("gui/FinanceManagerFrame.xml", UsedPlus.MOD_DIR)
        g_gui:loadGui(xmlPath, "usedPlusManager", financeFrame, true)

        -- Initialize frame
        if financeFrame then
            -- Add to InGameMenu (following EnhancedLoanSystem pattern)
            UsedPlus.addInGameMenuPage(financeFrame, "InGameMenuUsedPlus", {0, 0, 1024, 1024}, 3, function() return true end)
            UsedPlus.logInfo("Finance Manager page added to InGameMenu (ESC)")
        else
            UsedPlus.logError("Failed to create FinanceManagerFrame")
        end
    end
)

-- ESC Menu integration moved to loadMapFinished hook (see below)

-- Shop Menu Page Injection Function
-- Pattern from GarageMenu mod (working example)
function UsedPlus.addShopMenuPage(frame, pageName, uvs, predicateFunc, insertAfter)
    UsedPlus.logDebug(string.format("addShopMenuPage called for: %s", pageName))

    -- Remove existing control ID to avoid warnings
    g_shopMenu.controlIDs[pageName] = nil

    -- Find insertion position
    local targetPosition = 0
    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[insertAfter] then
            targetPosition = i + 1
            break
        end
    end
    UsedPlus.logTrace(string.format("  Target position: %d", targetPosition))

    -- Add frame to menu
    g_shopMenu[pageName] = frame
    g_shopMenu.pagingElement:addElement(g_shopMenu[pageName])
    g_shopMenu:exposeControlsAsFields(pageName)
    UsedPlus.logTrace("  Added to shop menu")

    -- Reorder in elements array
    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.elements, i)
            table.insert(g_shopMenu.pagingElement.elements, targetPosition, child)
            break
        end
    end

    -- Reorder in pages array
    for i = 1, #g_shopMenu.pagingElement.pages do
        local child = g_shopMenu.pagingElement.pages[i]
        if child.element == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.pages, i)
            table.insert(g_shopMenu.pagingElement.pages, targetPosition, child)
            break
        end
    end
    UsedPlus.logTrace("  Reordered in arrays")

    -- Update layout
    g_shopMenu.pagingElement:updateAbsolutePosition()
    g_shopMenu.pagingElement:updatePageMapping()

    -- Register page with predicate
    g_shopMenu:registerPage(g_shopMenu[pageName], nil, predicateFunc)
    UsedPlus.logTrace("  Registered page")

    -- Add tab icon
    local iconFileName = Utils.getFilename("icon.dds", UsedPlus.MOD_DIR)
    g_shopMenu:addPageTab(g_shopMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
    UsedPlus.logTrace("  Added icon tab")

    -- Reorder in pageFrames array
    for i = 1, #g_shopMenu.pageFrames do
        local child = g_shopMenu.pageFrames[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pageFrames, i)
            table.insert(g_shopMenu.pageFrames, targetPosition, child)
            break
        end
    end

    -- Rebuild tab list
    g_shopMenu:rebuildTabList()
    UsedPlus.logDebug("  Shop menu page injection complete")
end

-- InGame Menu Page Injection Function
-- Pattern from EnhancedLoanSystem mod (proven working example)
function UsedPlus.addInGameMenuPage(frame, pageName, uvs, position, predicateFunc)
    UsedPlus.logDebug(string.format("addInGameMenuPage called for: %s at position %d", pageName, position))

    -- Get InGameMenu controller
    local inGameMenu = g_gui.screenControllers[InGameMenu]

    if not inGameMenu then
        UsedPlus.logError("InGameMenu controller not found")
        return
    end

    -- Remove existing control ID to avoid warnings
    inGameMenu.controlIDs[pageName] = nil
    UsedPlus.logTrace("  Cleared control ID")

    -- Add frame to menu
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    UsedPlus.logTrace("  Frame added to pagingElement")

    -- Expose controls as fields
    inGameMenu:exposeControlsAsFields(pageName)

    -- Reorder in elements array
    for i = 1, #inGameMenu.pagingElement.elements do
        local child = inGameMenu.pagingElement.elements[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.elements, i)
            table.insert(inGameMenu.pagingElement.elements, position, child)
            UsedPlus.logTrace(string.format("  Reordered in elements array at index %d", position))
            break
        end
    end

    -- Reorder in pages array
    for i = 1, #inGameMenu.pagingElement.pages do
        local child = inGameMenu.pagingElement.pages[i]
        if child.element == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, position, child)
            UsedPlus.logTrace(string.format("  Reordered in pages array at index %d", position))
            break
        end
    end

    -- Update layout
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    UsedPlus.logTrace("  Layout updated")

    -- Register page with predicate
    inGameMenu:registerPage(inGameMenu[pageName], position, predicateFunc)
    UsedPlus.logTrace("  Page registered")

    -- Add tab icon
    local iconFileName = Utils.getFilename("icon.dds", UsedPlus.MOD_DIR)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
    UsedPlus.logTrace("  Tab icon added")

    -- Reorder in pageFrames array
    for i = 1, #inGameMenu.pageFrames do
        local child = inGameMenu.pageFrames[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pageFrames, i)
            table.insert(inGameMenu.pageFrames, position, child)
            UsedPlus.logTrace(string.format("  Reordered in pageFrames array at index %d", position))
            break
        end
    end

    -- Rebuild tab list
    inGameMenu:rebuildTabList()
    UsedPlus.logDebug("  InGameMenu integration complete!")
end

-- Hook savegame load (load mod data from savegame)
FSBaseMission.loadItemsFinished = Utils.appendedFunction(
    FSBaseMission.loadItemsFinished,
    function(mission, missionInfo, missionDynamicInfo)
        if g_financeManager then
            g_financeManager:loadFromXMLFile(missionInfo)
        end

        if g_usedVehicleManager then
            g_usedVehicleManager:loadFromXMLFile(missionInfo)
        end

        -- NEW - Load vehicle sale listings
        if g_vehicleSaleManager then
            g_vehicleSaleManager:loadFromXMLFile(missionInfo)
        end

        UsedPlus.logInfo("Savegame data loaded")
    end
)

-- Hook savegame save (save mod data to savegame)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
    FSCareerMissionInfo.saveToXMLFile,
    function(missionInfo)
        if g_financeManager then
            g_financeManager:saveToXMLFile(missionInfo)
        end

        if g_usedVehicleManager then
            g_usedVehicleManager:saveToXMLFile(missionInfo)
        end

        -- NEW - Save vehicle sale listings
        if g_vehicleSaleManager then
            g_vehicleSaleManager:saveToXMLFile(missionInfo)
        end

        UsedPlus.logInfo("Savegame data saved")
    end
)

--[[
    Farm class extension
    Pattern from: BuyUsedEquipment FarmExtension
    Add custom data to Farm for tracking deals and searches
]]

-- Extend Farm constructor to add custom data
local originalFarmNew = Farm.new
function Farm.new(...)
    local farm = originalFarmNew(...)

    if farm ~= nil then
        -- Add custom farm data structures
        farm.financeDeals = {}        -- Active finance/lease deals
        farm.usedVehicleSearches = {} -- Active search requests (for buying)
        farm.vehicleSaleListings = {} -- NEW - Active sale listings (for selling)

        UsedPlus.logDebug("Extended Farm " .. tostring(farm.farmId))
    end

    return farm
end

-- Extend Farm save to persist custom data
Farm.saveToXMLFile = Utils.appendedFunction(
    Farm.saveToXMLFile,
    function(self, xmlFile, key)
        -- Farm-specific data saved by managers
        -- This hook ensures farm extensions are preserved
    end
)

-- Extend Farm load to restore custom data
local originalFarmLoadFromXMLFile = Farm.loadFromXMLFile
function Farm.loadFromXMLFile(self, xmlFile, key)
    local success = originalFarmLoadFromXMLFile(self, xmlFile, key)

    if success then
        -- Initialize custom data structures if not present
        self.financeDeals = self.financeDeals or {}
        self.usedVehicleSearches = self.usedVehicleSearches or {}
        self.vehicleSaleListings = self.vehicleSaleListings or {}  -- NEW
    end

    return success
end

--[[
    Input action registration
    Allows player to open Finance Manager with hotkey (Ctrl+F)
]]
function UsedPlus:registerInputActions()
    -- Input action defined in modDesc.xml <actions>
    -- Action name: USEDPLUS_OPEN_FINANCE_MANAGER

    -- Register input action handler
    local _, eventId = g_inputBinding:registerActionEvent(
        InputAction.USEDPLUS_OPEN_FINANCE_MANAGER,
        self,
        function()
            UsedPlus.instance:onOpenFinanceManager()
        end,
        false,
        true,
        false,
        true
    )

    if eventId then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("usedplus_action_openFinanceManager"))
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        UsedPlus.logInfo("Finance Manager hotkey registered (Shift+F)")
    end
end

--[[
    Open Finance Manager dialog
    Called by hotkey or ESC menu button
]]
function UsedPlus:onOpenFinanceManager()
    -- Open Finance Manager Frame
    local financeManagerFrame = g_gui:showDialog("FinanceManagerFrame")
    if financeManagerFrame then
        UsedPlus.logDebug("Finance Manager opened")
    else
        UsedPlus.logError("Failed to open Finance Manager")
    end
end

--[[
    ESC Menu Integration
    TODO: Add Finance Manager button to in-game menu
    For now, use Shift+F hotkey to access Finance Manager
]]
-- ESC menu integration disabled temporarily - needs further investigation
-- User can access Finance Manager via Shift+F hotkey

--[[
    Cleanup on mission unload
    Free resources and unregister managers
]]
Mission00.delete = Utils.prependedFunction(
    Mission00.delete,
    function(mission)
        UsedPlus.logInfo("Mission unloading, cleaning up")

        -- Managers handle their own cleanup via delete()
        if g_financeManager then
            g_financeManager:delete()
            g_financeManager = nil
        end

        if g_usedVehicleManager then
            g_usedVehicleManager:delete()
            g_usedVehicleManager = nil
        end

        -- NEW - Cleanup vehicle sale manager
        if g_vehicleSaleManager then
            g_vehicleSaleManager:delete()
            g_vehicleSaleManager = nil
        end

        if UsedPlus.instance then
            UsedPlus.instance.isInitialized = false
        end
    end
)

--[[
    Console commands (admin-level)
    Pattern from: MoneyCommandMod
    Available to admins regardless of debug mode
]]

-- Admin permission check (3-tier system from MoneyCommandMod)
function UsedPlus:isAdmin()
    if g_currentMission:getIsServer() then
        return true
    elseif g_currentMission.isMasterUser then
        return true
    elseif g_currentMission.userManager and g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId) then
        local user = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
        if user and user:getIsMasterUser() then
            return true
        end
    end
    return false
end

-- Add money console command
-- NOTE: Console commands use UsedPlus table directly (not instance) because addConsoleCommand
-- is called at load time before instance exists. We use UsedPlus.isAdmin() as static function.
addConsoleCommand("upAddMoney", "Add money to your farm (admin only). Usage: upAddMoney <amount>", "consoleCommandAddMoney", UsedPlus)

function UsedPlus.consoleCommandAddMoney(self, amountStr)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Validate amount parameter
    local amount = tonumber(amountStr)
    if not amount then
        return "Error: Invalid amount. Usage: upAddMoney <amount>"
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if not farm then
        return "Error: Farm not found."
    end

    -- Add/remove money
    farm:changeBalance(amount, MoneyType.OTHER)

    local action = amount >= 0 and "added to" or "removed from"
    print(string.format("[UsedPlus] %s %s farm (new balance: %s)",
        g_i18n:formatMoney(math.abs(amount), 0, true, true),
        action,
        g_i18n:formatMoney(farm.money, 0, true, true)))

    return string.format("%s %s your farm. New balance: %s",
        g_i18n:formatMoney(math.abs(amount), 0, true, true),
        action,
        g_i18n:formatMoney(farm.money, 0, true, true))
end

-- Set money console command (sets exact amount)
addConsoleCommand("upSetMoney", "Set your farm's money to exact amount (admin only). Usage: upSetMoney <amount>", "consoleCommandSetMoney", UsedPlus)

function UsedPlus.consoleCommandSetMoney(self, amountStr)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Validate amount parameter
    local amount = tonumber(amountStr)
    if not amount or amount < 0 then
        return "Error: Invalid amount. Usage: upSetMoney <amount> (must be >= 0)"
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if not farm then
        return "Error: Farm not found."
    end

    -- Calculate difference and apply
    local currentMoney = farm.money
    local difference = amount - currentMoney
    farm:changeBalance(difference, MoneyType.OTHER)

    print(string.format("[UsedPlus] Farm money set to %s (was %s)",
        g_i18n:formatMoney(amount, 0, true, true),
        g_i18n:formatMoney(currentMoney, 0, true, true)))

    return string.format("Farm money set to %s (was %s)",
        g_i18n:formatMoney(amount, 0, true, true),
        g_i18n:formatMoney(currentMoney, 0, true, true))
end

-- Set credit score console command (for testing)
addConsoleCommand("upSetCredit", "Adjust credit score factors (admin only). Usage: upSetCredit info", "consoleCommandSetCredit", UsedPlus)

function UsedPlus.consoleCommandSetCredit(self, action)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then
        return "Error: Farm not found."
    end

    -- Calculate and display credit info
    local score = CreditScore.calculate(farmId)
    local rating, level = CreditScore.getRating(score)
    local adjustment = CreditScore.getInterestAdjustment(score)
    local assets = CreditScore.calculateAssets(farm)
    local debt = CreditScore.calculateDebt(farm)
    local ratio = assets > 0 and (debt / assets * 100) or 0

    print("[UsedPlus] === Credit Score Report ===")
    print(string.format("  Score: %d (%s)", score, rating))
    print(string.format("  Interest Adjustment: %+.1f%%", adjustment))
    print(string.format("  Total Assets: %s", g_i18n:formatMoney(assets, 0, true, true)))
    print(string.format("  Total Debt: %s", g_i18n:formatMoney(debt, 0, true, true)))
    print(string.format("  Debt-to-Asset Ratio: %.1f%%", ratio))
    print("[UsedPlus] ===========================")

    return string.format("Credit Score: %d (%s) | Interest: %+.1f%% | Debt Ratio: %.1f%%",
        score, rating, adjustment, ratio)
end

-- Pay off all finance deals (admin command)
addConsoleCommand("upPayoffAll", "Pay off all finance deals instantly (admin only)", "consoleCommandPayoffAll", UsedPlus)

function UsedPlus.consoleCommandPayoffAll(self)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    if not g_financeManager then
        return "Error: Finance Manager not initialized."
    end

    local farmId = g_currentMission:getFarmId()
    local deals = g_financeManager:getDealsForFarm(farmId)

    if not deals or #deals == 0 then
        return "No active finance deals to pay off."
    end

    local paidCount = 0
    local totalPaid = 0

    for _, deal in ipairs(deals) do
        if deal.status == "active" then
            local balance = deal.currentBalance or 0
            deal.currentBalance = 0
            deal.status = "paid"
            deal.monthsPaid = deal.termMonths
            paidCount = paidCount + 1
            totalPaid = totalPaid + balance
        end
    end

    print(string.format("[UsedPlus] Paid off %d deals, total: %s",
        paidCount, g_i18n:formatMoney(totalPaid, 0, true, true)))

    return string.format("Paid off %d deals (%s total)", paidCount,
        g_i18n:formatMoney(totalPaid, 0, true, true))
end

--[[
    Debug console commands (if DEBUG mode enabled)
    Useful for testing and troubleshooting
]]
if UsedPlus.DEBUG then
    -- Add console command to check credit score
    addConsoleCommand("upCreditScore", "Display current farm's credit score", "consoleCommandCreditScore", UsedPlus)

    function UsedPlus:consoleCommandCreditScore()
        local farmId = g_currentMission.player.farmId
        local score = CreditScore.calculate(farmId)
        local rating, level = CreditScore.getRating(score)

        print(string.format("[UsedPlus] Credit Score: %d (%s)", score, rating))

        return string.format("Credit Score: %d (%s)", score, rating)
    end

    -- Add console command to list active deals
    addConsoleCommand("upListDeals", "List all active finance/lease deals", "consoleCommandListDeals", UsedPlus)

    function UsedPlus:consoleCommandListDeals()
        if g_financeManager == nil then
            print("[UsedPlus] FinanceManager not initialized")
            return "FinanceManager not initialized"
        end

        local farmId = g_currentMission.player.farmId
        local deals = g_financeManager:getDealsForFarm(farmId)

        if #deals == 0 then
            print("[UsedPlus] No active deals for farm " .. farmId)
            return "No active deals"
        end

        print(string.format("[UsedPlus] Active deals for farm %d:", farmId))
        for i, deal in ipairs(deals) do
            print(string.format("  %d. %s - $%.2f balance, %d/%d months",
                i, deal.itemName, deal.currentBalance, deal.monthsPaid, deal.termMonths))
        end

        return string.format("%d active deals", #deals)
    end

    -- Add console command to list active searches
    addConsoleCommand("upListSearches", "List all active used vehicle searches", "consoleCommandListSearches", UsedPlus)

    function UsedPlus:consoleCommandListSearches()
        if g_usedVehicleManager == nil then
            print("[UsedPlus] UsedVehicleManager not initialized")
            return "UsedVehicleManager not initialized"
        end

        local farmId = g_currentMission.player.farmId
        local farm = g_farmManager:getFarmById(farmId)

        if farm.usedVehicleSearches == nil or #farm.usedVehicleSearches == 0 then
            print("[UsedPlus] No active searches for farm " .. farmId)
            return "No active searches"
        end

        print(string.format("[UsedPlus] Active searches for farm %d:", farmId))
        for i, search in ipairs(farm.usedVehicleSearches) do
            print(string.format("  %d. %s - %s, TTL: %d hours",
                i, search.storeItemName, search:getTierName(), search.ttl))
        end

        return string.format("%d active searches", #farm.usedVehicleSearches)
    end
end

UsedPlus.logInfo("Main initialization loaded")
