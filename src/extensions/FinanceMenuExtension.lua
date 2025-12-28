--[[
    FS25_UsedPlus - Finance Menu Extension

    Overrides vanilla loan borrowing to require credit-based loans through UsedPlus.
    Pattern from: FS25_EnhancedLoanSystem hasPlayerLoanPermission override

    This extension:
    - Disables vanilla "Borrow" button (forces use of TakeLoanDialog with credit requirements)
    - Still allows "Repay" for existing vanilla loans (so players can pay down old loans)
    - Shows notification directing players to Financial Dashboard for new loans
]]

FinanceMenuExtension = {}

--[[
    Override hasPlayerLoanPermission to disable vanilla borrowing
    Players must use our credit-based TakeLoanDialog instead

    This returns false to disable the vanilla borrow button.
    Repay functionality is handled separately and still works.
]]
function FinanceMenuExtension.hasPlayerLoanPermission(self, superFunc)
    -- Disable vanilla borrowing - players must use UsedPlus loans with credit requirements
    -- superFunc would return true if player has farm permission, but we override to false
    return false
end

--[[
    Hook to show notification when player tries to use disabled borrow button
    (In case the button is visible but disabled)
]]
function FinanceMenuExtension.onClickBorrow(self, superFunc)
    -- Show notification directing to our loan system
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        g_i18n:getText("usedplus_loan_useFinancialDashboard") or "Use Financial Dashboard to take credit-based loans"
    )

    -- Don't call superFunc - block vanilla borrowing
    return
end

--[[
    Install hooks at load time
]]
function FinanceMenuExtension.install()
    -- Hook hasPlayerLoanPermission to disable vanilla borrowing
    if InGameMenuStatisticsFrame ~= nil then
        if InGameMenuStatisticsFrame.hasPlayerLoanPermission ~= nil then
            InGameMenuStatisticsFrame.hasPlayerLoanPermission = Utils.overwrittenFunction(
                InGameMenuStatisticsFrame.hasPlayerLoanPermission,
                FinanceMenuExtension.hasPlayerLoanPermission
            )
            UsedPlus.logDebug("InGameMenuStatisticsFrame.hasPlayerLoanPermission hook installed - vanilla borrowing disabled")
        else
            UsedPlus.logWarn("InGameMenuStatisticsFrame.hasPlayerLoanPermission not found")
        end
    else
        UsedPlus.logWarn("InGameMenuStatisticsFrame not available at load time")
    end
end

-- Install hooks
FinanceMenuExtension.install()

UsedPlus.logInfo("FinanceMenuExtension loaded - vanilla borrowing disabled, use Financial Dashboard for loans")
