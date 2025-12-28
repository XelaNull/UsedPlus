--[[
    FS25_UsedPlus - Dialog Loader Utility

    Centralized dialog loading and management
    Eliminates 200+ lines of duplicated dialog loading patterns

    Features:
    - Central registry of all dialogs with their configurations
    - Lazy loading (dialogs only loaded when first used)
    - Unified show/hide API with data setting
    - Automatic fallback handling (dialog.target vs direct)
    - Error logging on failures

    Usage:
        -- Simple show (no data)
        DialogLoader.show("FinancialDashboard")

        -- Show with data method call
        DialogLoader.show("TakeLoanDialog", "setFarmId", farmId)

        -- Show with multiple data args
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId)

        -- Show with callback
        DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)
]]

DialogLoader = {}

-- Central dialog registry
-- Each entry: { class = DialogClass, xml = "path/to/dialog.xml" }
DialogLoader.dialogs = {}

-- Track which dialogs have been loaded
DialogLoader.loaded = {}

--[[
    Register a dialog with the loader
    Call this at mod load time for each dialog class

    @param name - Dialog name (matches g_gui.guis key)
    @param dialogClass - The dialog class (e.g., TakeLoanDialog)
    @param xmlPath - Path relative to MOD_DIR (e.g., "gui/TakeLoanDialog.xml")
]]
function DialogLoader.register(name, dialogClass, xmlPath)
    DialogLoader.dialogs[name] = {
        class = dialogClass,
        xml = xmlPath
    }
    DialogLoader.loaded[name] = false
end

--[[
    Ensure a dialog is loaded (lazy loading)
    Returns true if dialog is ready to use

    @param name - Dialog name
    @return boolean - true if loaded successfully
]]
function DialogLoader.ensureLoaded(name)
    -- Already loaded?
    if DialogLoader.loaded[name] then
        return true
    end

    -- Get registration
    local registration = DialogLoader.dialogs[name]
    if not registration then
        UsedPlus.logError(string.format("DialogLoader: Dialog '%s' not registered", name))
        return false
    end

    -- Load the dialog
    local dialogClass = registration.class
    local xmlPath = UsedPlus.MOD_DIR .. registration.xml

    if not dialogClass then
        UsedPlus.logError(string.format("DialogLoader: Dialog class for '%s' is nil", name))
        return false
    end

    local dialog = dialogClass.new(nil, nil, g_i18n)
    g_gui:loadGui(xmlPath, name, dialog)

    DialogLoader.loaded[name] = true
    UsedPlus.logDebug(string.format("DialogLoader: Loaded '%s'", name))

    return true
end

--[[
    Get dialog instance (target or direct)
    Handles the target wrapper pattern used by g_gui

    @param name - Dialog name
    @return dialog instance or nil
]]
function DialogLoader.getDialog(name)
    local guiDialog = g_gui.guis[name]
    if guiDialog == nil then
        return nil
    end

    -- g_gui wraps dialogs - get the actual instance
    if guiDialog.target ~= nil then
        return guiDialog.target
    end

    -- Direct reference (some older patterns)
    return guiDialog
end

--[[
    Show a dialog with optional data setting
    This is the main API - replaces all the scattered patterns

    @param name - Dialog name
    @param dataMethod - Optional: method name to call for setting data (e.g., "setFarmId")
    @param ... - Optional: arguments to pass to dataMethod
    @return boolean - true if dialog was shown successfully
]]
function DialogLoader.show(name, dataMethod, ...)
    -- Ensure loaded
    if not DialogLoader.ensureLoaded(name) then
        UsedPlus.logError(string.format("DialogLoader: Failed to load '%s'", name))
        return false
    end

    -- Get dialog instance
    local dialog = DialogLoader.getDialog(name)
    if dialog == nil then
        UsedPlus.logError(string.format("DialogLoader: '%s' not found in g_gui.guis after loading", name))
        -- Reset loaded flag so we try again next time
        DialogLoader.loaded[name] = false
        return false
    end

    -- Call data method if provided
    if dataMethod then
        local method = dialog[dataMethod]
        if method and type(method) == "function" then
            method(dialog, ...)
            UsedPlus.logTrace(string.format("DialogLoader: Called %s:%s()", name, dataMethod))
        else
            UsedPlus.logWarn(string.format("DialogLoader: Method '%s' not found on '%s'", dataMethod, name))
        end
    end

    -- Show the dialog
    g_gui:showDialog(name)
    UsedPlus.logDebug(string.format("DialogLoader: Showed '%s'", name))

    return true
end

--[[
    Check if a dialog is currently visible
    @param name - Dialog name
    @return boolean
]]
function DialogLoader.isVisible(name)
    local currentDialog = g_gui:getIsDialogVisible()
    if currentDialog and currentDialog.name == name then
        return true
    end
    return false
end

--[[
    Close a specific dialog if it's open
    @param name - Dialog name
]]
function DialogLoader.close(name)
    local dialog = DialogLoader.getDialog(name)
    if dialog and dialog.close then
        dialog:close()
    end
end

--[[
    Register all UsedPlus dialogs
    Called from main.lua after all dialog classes are loaded
]]
function DialogLoader.registerAll()
    -- Finance/Loan dialogs
    if TakeLoanDialog then
        DialogLoader.register("TakeLoanDialog", TakeLoanDialog, "gui/TakeLoanDialog.xml")
    end

    if FinancialDashboard then
        DialogLoader.register("FinancialDashboard", FinancialDashboard, "gui/FinancialDashboard.xml")
    end

    if CreditReportDialog then
        DialogLoader.register("CreditReportDialog", CreditReportDialog, "gui/CreditReportDialog.xml")
    end

    if PaymentConfigDialog then
        DialogLoader.register("PaymentConfigDialog", PaymentConfigDialog, "gui/PaymentConfigDialog.xml")
    end

    -- Land dialogs
    if LandFinanceDialog then
        DialogLoader.register("LandFinanceDialog", LandFinanceDialog, "gui/LandFinanceDialog.xml")
    end

    if LandLeaseDialog then
        DialogLoader.register("LandLeaseDialog", LandLeaseDialog, "gui/LandLeaseDialog.xml")
    end

    if UnifiedLandPurchaseDialog then
        DialogLoader.register("UnifiedLandPurchaseDialog", UnifiedLandPurchaseDialog, "gui/UnifiedLandPurchaseDialog.xml")
    end

    -- Vehicle dialogs
    if RepairDialog then
        DialogLoader.register("RepairDialog", RepairDialog, "gui/RepairDialog.xml")
    end

    if RepairFinanceDialog then
        DialogLoader.register("RepairFinanceDialog", RepairFinanceDialog, "gui/RepairFinanceDialog.xml")
    end

    if SellVehicleDialog then
        DialogLoader.register("SellVehicleDialog", SellVehicleDialog, "gui/SellVehicleDialog.xml")
    end

    if SaleOfferDialog then
        DialogLoader.register("SaleOfferDialog", SaleOfferDialog, "gui/SaleOfferDialog.xml")
    end

    -- Purchase dialogs
    if UnifiedPurchaseDialog then
        DialogLoader.register("UnifiedPurchaseDialog", UnifiedPurchaseDialog, "gui/UnifiedPurchaseDialog.xml")
    end

    if UsedSearchDialog then
        DialogLoader.register("UsedSearchDialog", UsedSearchDialog, "gui/UsedSearchDialog.xml")
    end

    -- Lease end dialogs
    if LeaseEndDialog then
        DialogLoader.register("LeaseEndDialog", LeaseEndDialog, "gui/LeaseEndDialog.xml")
    end

    if LeaseRenewalDialog then
        DialogLoader.register("LeaseRenewalDialog", LeaseRenewalDialog, "gui/LeaseRenewalDialog.xml")
    end

    -- Simple confirmation dialog (reusable info popup)
    if ConfirmationDialog then
        DialogLoader.register("ConfirmationDialog", ConfirmationDialog, "gui/ConfirmationDialog.xml")
    end

    -- Maintenance/Inspection dialogs (Phase 4)
    if UsedVehiclePreviewDialog then
        DialogLoader.register("UsedVehiclePreviewDialog", UsedVehiclePreviewDialog, "gui/UsedVehiclePreviewDialog.xml")
    end

    if InspectionReportDialog then
        DialogLoader.register("InspectionReportDialog", InspectionReportDialog, "gui/InspectionReportDialog.xml")
    end

    if MaintenanceReportDialog then
        DialogLoader.register("MaintenanceReportDialog", MaintenanceReportDialog, "gui/MaintenanceReportDialog.xml")
    end

    -- v1.5.1: Search expiration dialog with renewal option
    if SearchExpiredDialog then
        DialogLoader.register("SearchExpiredDialog", SearchExpiredDialog, "gui/SearchExpiredDialog.xml")
    end

    UsedPlus.logInfo("DialogLoader: Registered all dialogs")
end

--[[
    Reset all loaded flags (for testing/reload)
]]
function DialogLoader.resetAll()
    for name, _ in pairs(DialogLoader.loaded) do
        DialogLoader.loaded[name] = false
    end
end

UsedPlus.logInfo("DialogLoader loaded")
