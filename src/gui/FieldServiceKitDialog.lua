--[[
    FS25_UsedPlus - Field Service Kit Dialog (OBD Scanner)

    Multi-step diagnosis minigame dialog for emergency field repairs.
    Steps:
    1. System Selection - Player guesses which system failed
    2. Diagnosis - Player sees symptoms and picks likely cause
    3. Results - Shows repair outcome and applies to vehicle

    v1.8.0 - Field Service Kit System
    v2.0.0 - Full RVB/UYT cross-mod integration
            - Shows individual RVB part statuses (Engine, Thermostat, Generator, etc.)
            - Shows UYT tire wear breakdown per wheel
            - Color-coded health indicators with fault/prefault warnings
    v2.3.0 - Fixed button styling to use triple-element pattern (Bitmap + invisible Button + Text)
            - Matches mod's perfected custom button style
            - All dialogs now use consistent button pattern
            - Added hover effect for diagnosis buttons
            - Removed [A] [B] [C] [D] prefixes from options
            - Redesigned results screen with prominent success/failure display
]]

FieldServiceKitDialog = {}
local FieldServiceKitDialog_mt = Class(FieldServiceKitDialog, MessageDialog)

-- Registration pattern (same as other dialogs)
FieldServiceKitDialog.instance = nil
FieldServiceKitDialog.xmlPath = nil

--[[
    Register the dialog with g_gui
    Must be called before the dialog can be shown
]]
function FieldServiceKitDialog.register()
    if FieldServiceKitDialog.instance == nil then
        UsedPlus.logInfo("FieldServiceKitDialog: Registering dialog")

        -- Set XML path - use UsedPlus.MOD_DIR which persists after mod load
        if FieldServiceKitDialog.xmlPath == nil then
            FieldServiceKitDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/FieldServiceKitDialog.xml"
        end

        UsedPlus.logInfo("FieldServiceKitDialog: Loading XML from: " .. tostring(FieldServiceKitDialog.xmlPath))

        -- Create instance and load GUI
        FieldServiceKitDialog.instance = FieldServiceKitDialog.new()
        g_gui:loadGui(FieldServiceKitDialog.xmlPath, "FieldServiceKitDialog", FieldServiceKitDialog.instance)

        UsedPlus.logInfo("FieldServiceKitDialog: Registration complete")
    end
end

FieldServiceKitDialog.STEP_SYSTEM_SELECT = 1
FieldServiceKitDialog.STEP_DIAGNOSIS = 2
FieldServiceKitDialog.STEP_RESULTS = 3
FieldServiceKitDialog.STEP_TIRE_REPAIR = 4

function FieldServiceKitDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or FieldServiceKitDialog_mt)

    self.vehicle = nil
    self.kit = nil
    self.kitTier = "basic"
    self.currentStep = FieldServiceKitDialog.STEP_SYSTEM_SELECT
    self.selectedSystem = nil
    self.actualFailedSystem = nil
    self.currentScenario = nil
    self.selectedDiagnosis = nil
    self.repairResult = nil
    self.hasFlatTire = false

    return self
end

function FieldServiceKitDialog:onOpen()
    FieldServiceKitDialog:superClass().onOpen(self)
    self:updateDisplay()
end

function FieldServiceKitDialog:onCreate()
    FieldServiceKitDialog:superClass().onCreate(self)
end

--[[
    Set data for the dialog
    @param vehicle - The vehicle to repair
    @param kit - The field service kit being used
    @param kitTier - "basic", "professional", or "master"
]]
function FieldServiceKitDialog:setData(vehicle, kit, kitTier)
    self.vehicle = vehicle
    self.kit = kit
    self.kitTier = kitTier or "basic"
    self.currentStep = FieldServiceKitDialog.STEP_SYSTEM_SELECT
    self.selectedSystem = nil
    self.selectedDiagnosis = nil
    self.repairResult = nil

    -- Determine actual failed system from vehicle maintenance spec
    -- Uses lastFailedSystem if a real failure was recorded, otherwise falls back to lowest reliability
    -- Player must use scanner hints to deduce the correct system (not just pick lowest %)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        self.actualFailedSystem = maintSpec.lastFailedSystem or self:determineFailedSystem(maintSpec)
        self.hasFlatTire = self:checkForFlatTire(vehicle)
    end

    self:updateDisplay()
end

--[[
    Determine which system most likely failed based on reliability values
]]
function FieldServiceKitDialog:determineFailedSystem(maintSpec)
    local engine = maintSpec.engineReliability or 1.0
    local electrical = maintSpec.electricalReliability or 1.0
    local hydraulic = maintSpec.hydraulicReliability or 1.0

    -- Return the system with lowest reliability
    if engine <= electrical and engine <= hydraulic then
        return DiagnosisData.SYSTEM_ENGINE
    elseif electrical <= engine and electrical <= hydraulic then
        return DiagnosisData.SYSTEM_ELECTRICAL
    else
        return DiagnosisData.SYSTEM_HYDRAULIC
    end
end

--[[
    Check if vehicle has a flat tire
]]
function FieldServiceKitDialog:checkForFlatTire(vehicle)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil and maintSpec.tireConditions ~= nil then
        for _, condition in pairs(maintSpec.tireConditions) do
            if condition <= 0.01 then
                return true
            end
        end
    end
    return false
end

--[[
    Update the dialog display based on current step
]]
function FieldServiceKitDialog:updateDisplay()
    if self.vehicle == nil then
        return
    end

    local vehicleName = self.vehicle:getName() or "Vehicle"
    local maintSpec = self.vehicle.spec_usedPlusMaintenance

    if self.currentStep == FieldServiceKitDialog.STEP_SYSTEM_SELECT then
        self:displaySystemSelection(vehicleName, maintSpec)
    elseif self.currentStep == FieldServiceKitDialog.STEP_DIAGNOSIS then
        self:displayDiagnosis()
    elseif self.currentStep == FieldServiceKitDialog.STEP_RESULTS then
        self:displayResults()
    elseif self.currentStep == FieldServiceKitDialog.STEP_TIRE_REPAIR then
        self:displayTireRepair()
    end
end

--[[
    Display Step 1: System Selection
    v1.8.0: Uses ModCompatibility to show RVB part details when available
    v2.0.0: Shows detailed RVB part status and UYT tire wear in dedicated sections
]]
function FieldServiceKitDialog:displaySystemSelection(vehicleName, maintSpec)
    -- v1.8.0: Get diagnostic data from ModCompatibility (includes RVB data if available)
    local diagData = ModCompatibility.getOBDDiagnosticData(self.vehicle)

    -- Get reliability values (uses RVB-derived values if RVB is installed)
    local engineRel = math.floor(diagData.engine.reliability * 100)
    local elecRel = math.floor(diagData.electrical.reliability * 100)
    local hydRel = math.floor(diagData.hydraulic.reliability * 100)

    local isDisabled = maintSpec and maintSpec.isDisabled or false
    local statusText = isDisabled and g_i18n:getText("usedplus_fsk_status_disabled") or g_i18n:getText("usedplus_fsk_status_needs_service")

    -- v1.8.0: Store diagnostic data for later steps (RVB repair integration)
    self.diagnosticData = diagData

    -- Update UI elements
    if self.vehicleNameText ~= nil then
        self.vehicleNameText:setText(vehicleName)
    end

    if self.statusText ~= nil then
        self.statusText:setText(statusText)
        if isDisabled then
            self.statusText:setTextColor(1, 0.2, 0.2, 1)  -- Red
        else
            self.statusText:setTextColor(1, 0.7, 0, 1)  -- Orange
        end
    end

    -- Update reliability displays
    if self.engineRelText ~= nil then
        self.engineRelText:setText(string.format("%d%%", engineRel))
        self:setReliabilityColor(self.engineRelText, engineRel)
    end

    if self.electricalRelText ~= nil then
        self.electricalRelText:setText(string.format("%d%%", elecRel))
        self:setReliabilityColor(self.electricalRelText, elecRel)
    end

    if self.hydraulicRelText ~= nil then
        self.hydraulicRelText:setText(string.format("%d%%", hydRel))
        self:setReliabilityColor(self.hydraulicRelText, hydRel)
    end

    -- v2.1.0: Display scanner readout hints for the actual failed system
    -- These help the player deduce which system to select
    self:displayScannerHints()

    -- v2.0.0: Display RVB part details if RVB is installed
    self:displayRVBDetails(diagData)

    -- v2.0.0: Display UYT tire details if UYT is installed
    self:displayUYTDetails(diagData)

    -- Show/hide step containers
    self:setStepVisibility(FieldServiceKitDialog.STEP_SYSTEM_SELECT)

    -- Show tire button if flat tire detected
    if self.tireButton ~= nil then
        self.tireButton:setVisible(self.hasFlatTire)
    end
end

--[[
    v2.1.0: Display scanner readout hints
    Shows 2 diagnostic hints based on the actual failed system
    Player uses these to deduce which system to select
]]
function FieldServiceKitDialog:displayScannerHints()
    if self.actualFailedSystem == nil then
        -- No failure detected, show generic message
        if self.scannerHint1Text ~= nil then
            self.scannerHint1Text:setText(g_i18n:getText("usedplus_fsk_hint_no_faults") or "No critical faults detected")
        end
        if self.scannerHint2Text ~= nil then
            self.scannerHint2Text:setText(g_i18n:getText("usedplus_fsk_hint_preventive") or "Preventive maintenance recommended")
        end
        return
    end

    -- Get 2 random hints for the actual failed system
    local hints = DiagnosisData.getSystemHints(self.actualFailedSystem, 2)

    -- Display hint 1
    if self.scannerHint1Text ~= nil then
        if hints[1] ~= nil then
            local hintText = g_i18n:getText(hints[1])
            self.scannerHint1Text:setText(">> " .. (hintText or hints[1]))
        else
            self.scannerHint1Text:setText("")
        end
    end

    -- Display hint 2
    if self.scannerHint2Text ~= nil then
        if hints[2] ~= nil then
            local hintText = g_i18n:getText(hints[2])
            self.scannerHint2Text:setText(">> " .. (hintText or hints[2]))
        else
            self.scannerHint2Text:setText("")
        end
    end

    UsedPlus.logInfo(string.format("Scanner hints displayed for system: %s", self.actualFailedSystem))
end

--[[
    v2.0.0: Display RVB part details in dedicated section
    Shows individual part life percentages and fault indicators
]]
function FieldServiceKitDialog:displayRVBDetails(diagData)
    -- Show/hide RVB container based on whether RVB data is available
    if self.rvbDetailContainer ~= nil then
        self.rvbDetailContainer:setVisible(diagData.hasRVBData)
    end

    if not diagData.hasRVBData then
        return
    end

    local faultCount = 0

    -- Display engine parts
    for _, part in ipairs(diagData.engine.rvbParts or {}) do
        local elementId = "rvb" .. part.name:gsub(" ", "") .. "Text"
        local element = self[elementId]
        if element ~= nil then
            local lifePercent = math.floor(part.life * 100)
            local statusStr = string.format("%d%%", lifePercent)

            -- Add fault/prefault indicator
            if part.fault then
                statusStr = statusStr .. " FAULT"
                faultCount = faultCount + 1
            elseif part.prefault then
                statusStr = statusStr .. " !"
            end

            element:setText(statusStr)
            self:setRVBPartColor(element, part.life, part.fault, part.prefault)
        end
    end

    -- Display electrical parts
    for _, part in ipairs(diagData.electrical.rvbParts or {}) do
        local elementId = "rvb" .. part.name:gsub(" ", "") .. "Text"
        local element = self[elementId]
        if element ~= nil then
            local lifePercent = math.floor(part.life * 100)
            local statusStr = string.format("%d%%", lifePercent)

            if part.fault then
                statusStr = statusStr .. " FAULT"
                faultCount = faultCount + 1
            elseif part.prefault then
                statusStr = statusStr .. " !"
            end

            element:setText(statusStr)
            self:setRVBPartColor(element, part.life, part.fault, part.prefault)
        end
    end

    -- Display fault count
    if self.rvbFaultCountText ~= nil then
        if faultCount > 0 then
            self.rvbFaultCountText:setText(tostring(faultCount))
            self.rvbFaultCountText:setTextColor(1, 0.3, 0.3, 1)  -- Red
        else
            self.rvbFaultCountText:setText("None")
            self.rvbFaultCountText:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
        end
    end
end

--[[
    v2.0.0: Display UYT tire wear details in dedicated section
]]
function FieldServiceKitDialog:displayUYTDetails(diagData)
    -- Show/hide UYT container based on whether UYT data is available
    if self.uytTireContainer ~= nil then
        self.uytTireContainer:setVisible(diagData.hasUYTData)
    end

    if not diagData.hasUYTData then
        return
    end

    local worstWear = 0
    local tirePositions = {"FL", "FR", "RL", "RR"}

    for i, tire in ipairs(diagData.tires or {}) do
        local position = tirePositions[i] or tostring(i)
        local elementId = "uytTire" .. position .. "Text"
        local element = self[elementId]

        if element ~= nil then
            local wearPercent = math.floor(tire.wear * 100)
            local conditionPercent = math.floor(tire.condition * 100)
            element:setText(string.format("%d%%", conditionPercent))
            self:setTireConditionColor(element, tire.condition)

            if tire.wear > worstWear then
                worstWear = tire.wear
            end
        end
    end

    -- Display worst tire status
    if self.uytWorstTireText ~= nil then
        local worstCondition = 1 - worstWear
        local worstPercent = math.floor(worstCondition * 100)
        self.uytWorstTireText:setText(string.format("%d%%", worstPercent))
        self:setTireConditionColor(self.uytWorstTireText, worstCondition)
    end
end

--[[
    v2.0.0: Set color for RVB part status based on life and fault state
]]
function FieldServiceKitDialog:setRVBPartColor(element, life, hasFault, hasPrefault)
    if element == nil then return end

    if hasFault then
        element:setTextColor(1, 0.2, 0.2, 1)  -- Red for fault
    elseif hasPrefault then
        element:setTextColor(1, 0.6, 0, 1)  -- Orange for prefault
    elseif life >= 0.7 then
        element:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
    elseif life >= 0.4 then
        element:setTextColor(1, 0.8, 0.2, 1)  -- Yellow
    elseif life >= 0.2 then
        element:setTextColor(1, 0.5, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.3, 0.3, 1)  -- Red
    end
end

--[[
    v2.0.0: Set color for tire condition
]]
function FieldServiceKitDialog:setTireConditionColor(element, condition)
    if element == nil then return end

    if condition >= 0.7 then
        element:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
    elseif condition >= 0.4 then
        element:setTextColor(1, 0.8, 0.2, 1)  -- Yellow
    elseif condition >= 0.2 then
        element:setTextColor(1, 0.5, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.3, 0.3, 1)  -- Red
    end
end

--[[
    Display Step 2: Diagnosis (symptoms and diagnosis options)
]]
function FieldServiceKitDialog:displayDiagnosis()
    if self.selectedSystem == nil then
        return
    end

    -- Get scenario for selected system
    self.currentScenario = DiagnosisData.getRandomScenario(self.selectedSystem)

    if self.currentScenario == nil then
        UsedPlus.logDebug("FieldServiceKitDialog: No scenario found for system: " .. tostring(self.selectedSystem))
        return
    end

    -- Display system name
    local systemName = g_i18n:getText("usedplus_fsk_system_" .. self.selectedSystem) or self.selectedSystem
    if self.systemNameText ~= nil then
        self.systemNameText:setText(string.format("%s %s", systemName, g_i18n:getText("usedplus_fsk_diagnosis") or "DIAGNOSIS"))
    end

    -- Display symptoms
    if self.symptom1Text ~= nil and self.currentScenario.symptoms[1] then
        self.symptom1Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[1]))
    end
    if self.symptom2Text ~= nil and self.currentScenario.symptoms[2] then
        self.symptom2Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[2]))
    end
    if self.symptom3Text ~= nil and self.currentScenario.symptoms[3] then
        self.symptom3Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[3]))
    end

    -- Display diagnosis options (no letter prefix - hover effect shows selection)
    if self.diagButton1 ~= nil and self.currentScenario.diagnoses[1] then
        self.diagButton1:setText(g_i18n:getText(self.currentScenario.diagnoses[1]))
    end
    if self.diagButton2 ~= nil and self.currentScenario.diagnoses[2] then
        self.diagButton2:setText(g_i18n:getText(self.currentScenario.diagnoses[2]))
    end
    if self.diagButton3 ~= nil and self.currentScenario.diagnoses[3] then
        self.diagButton3:setText(g_i18n:getText(self.currentScenario.diagnoses[3]))
    end
    if self.diagButton4 ~= nil and self.currentScenario.diagnoses[4] then
        self.diagButton4:setText(g_i18n:getText(self.currentScenario.diagnoses[4]))
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_DIAGNOSIS)
end

--[[
    Display Step 3: Results (Redesigned v2.3.0)
    Prominent success/failure display with diagnosis details
]]
function FieldServiceKitDialog:displayResults()
    if self.repairResult == nil then
        return
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    local isCorrect = self.repairResult.wasCorrectSystem and self.repairResult.wasCorrectDiagnosis
    local isPartial = self.repairResult.wasCorrectSystem and not self.repairResult.wasCorrectDiagnosis

    -- ========== OUTCOME HEADER ==========
    -- Set icon and background color based on outcome
    if self.outcomeIcon ~= nil then
        if isCorrect then
            self.outcomeIcon:setText("✓")
            self.outcomeIcon:setTextColor(0.3, 1, 0.4, 1)
        elseif isPartial then
            self.outcomeIcon:setText("~")
            self.outcomeIcon:setTextColor(1, 0.7, 0.2, 1)
        else
            self.outcomeIcon:setText("✗")
            self.outcomeIcon:setTextColor(1, 0.4, 0.4, 1)
        end
    end

    if self.outcomeBg ~= nil then
        if isCorrect then
            -- Green success background
            self.outcomeBg:setImageColor(nil, 0.08, 0.22, 0.08, 0.95)
        elseif isPartial then
            -- Orange partial background
            self.outcomeBg:setImageColor(nil, 0.22, 0.16, 0.06, 0.95)
        else
            -- Red failure background
            self.outcomeBg:setImageColor(nil, 0.22, 0.08, 0.08, 0.95)
        end
    end

    -- Outcome title
    if self.resultTitleText ~= nil then
        if isCorrect then
            self.resultTitleText:setText("CORRECT DIAGNOSIS!")
            self.resultTitleText:setTextColor(0.4, 1, 0.5, 1)
        elseif isPartial then
            self.resultTitleText:setText("PARTIAL MATCH")
            self.resultTitleText:setTextColor(1, 0.8, 0.3, 1)
        else
            self.resultTitleText:setText("WRONG DIAGNOSIS")
            self.resultTitleText:setTextColor(1, 0.5, 0.5, 1)
        end
    end

    -- Outcome subtitle
    if self.resultMessageText ~= nil then
        if isCorrect then
            self.resultMessageText:setText("Excellent work! Full repair bonus applied.")
        elseif isPartial then
            self.resultMessageText:setText("Right system, but incorrect cause identified.")
        else
            self.resultMessageText:setText("General maintenance applied with reduced effect.")
        end
    end

    -- ========== DIAGNOSIS DETAILS ==========
    -- Show what the player diagnosed
    if self.playerDiagnosisText ~= nil and self.currentScenario ~= nil then
        local playerDiag = self.currentScenario.diagnoses[self.selectedDiagnosis]
        if playerDiag ~= nil then
            self.playerDiagnosisText:setText(g_i18n:getText(playerDiag) or "Unknown")
        end
    end

    -- Show correct answer (only if wrong)
    if self.correctDiagLabel ~= nil then
        self.correctDiagLabel:setVisible(not isCorrect)
    end
    if self.correctDiagnosisText ~= nil then
        self.correctDiagnosisText:setVisible(not isCorrect)
        if not isCorrect and self.currentScenario ~= nil then
            local correctDiag = self.currentScenario.diagnoses[self.currentScenario.correctDiagnosis]
            if correctDiag ~= nil then
                self.correctDiagnosisText:setText(g_i18n:getText(correctDiag) or "Unknown")
            end
        end
    end

    -- ========== RELIABILITY SECTION ==========
    -- Update header based on outcome
    if self.reliabilityHeader ~= nil then
        if isCorrect then
            self.reliabilityHeader:setText("RELIABILITY RESTORED")
            self.reliabilityHeader:setTextColor(0.3, 1, 0.4, 1)
        elseif isPartial then
            self.reliabilityHeader:setText("PARTIAL RESTORATION")
            self.reliabilityHeader:setTextColor(1, 0.8, 0.3, 1)
        else
            self.reliabilityHeader:setText("MINIMAL IMPROVEMENT")
            self.reliabilityHeader:setTextColor(1, 0.5, 0.5, 1)
        end
    end

    -- Calculate before/after values
    local systemKey = self.selectedSystem or self.actualFailedSystem
    local beforeRel = 0
    local afterRel = 0

    if maintSpec ~= nil then
        if systemKey == DiagnosisData.SYSTEM_ENGINE then
            afterRel = math.floor(maintSpec.engineReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        elseif systemKey == DiagnosisData.SYSTEM_ELECTRICAL then
            afterRel = math.floor(maintSpec.electricalReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        elseif systemKey == DiagnosisData.SYSTEM_HYDRAULIC then
            afterRel = math.floor(maintSpec.hydraulicReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        end
    end

    if self.beforeRelText ~= nil then
        self.beforeRelText:setText(string.format("%d%%", math.max(0, beforeRel)))
    end
    if self.afterRelText ~= nil then
        self.afterRelText:setText(string.format("%d%%", afterRel))
    end
    if self.boostText ~= nil then
        local boostPercent = math.floor(self.repairResult.reliabilityBoost * 100)
        self.boostText:setText(string.format("+%d%%", boostPercent))
        -- Color based on boost amount
        if boostPercent >= 30 then
            self.boostText:setTextColor(0.3, 1, 0.4, 1)  -- Green for big boost
        elseif boostPercent >= 15 then
            self.boostText:setTextColor(1, 0.8, 0.3, 1)  -- Yellow for medium
        else
            self.boostText:setTextColor(1, 0.5, 0.5, 1)  -- Red-ish for small
        end
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_RESULTS)
end

--[[
    Display tire repair options
]]
function FieldServiceKitDialog:displayTireRepair()
    self:setStepVisibility(FieldServiceKitDialog.STEP_TIRE_REPAIR)
end

--[[
    Set visibility of step containers
]]
function FieldServiceKitDialog:setStepVisibility(activeStep)
    if self.systemSelectContainer ~= nil then
        self.systemSelectContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_SYSTEM_SELECT)
    end
    if self.diagnosisContainer ~= nil then
        self.diagnosisContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_DIAGNOSIS)
    end
    if self.resultsContainer ~= nil then
        self.resultsContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_RESULTS)
    end
    if self.tireRepairContainer ~= nil then
        self.tireRepairContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_TIRE_REPAIR)
    end

    -- Update button visibility based on step
    if self.okButton ~= nil then
        if activeStep == FieldServiceKitDialog.STEP_RESULTS then
            self.okButton:setText(g_i18n:getText("button_ok") or "OK")
            self.okButton:setVisible(true)  -- Show OK button on results screen
        else
            self.okButton:setVisible(false)
        end
    end

    if self.cancelButton ~= nil then
        self.cancelButton:setVisible(activeStep ~= FieldServiceKitDialog.STEP_RESULTS)
    end
end

--[[
    Set text color based on reliability value
]]
function FieldServiceKitDialog:setReliabilityColor(element, value)
    if element == nil then return end

    if value >= 70 then
        element:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
    elseif value >= 40 then
        element:setTextColor(1, 0.7, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.2, 0.2, 1)  -- Red
    end
end

-- v2.2.1: Removed custom hover effect code - buttonActivate profile provides built-in hover styling

--[[
    System selection button handlers
]]
function FieldServiceKitDialog:onEngineClick()
    self.selectedSystem = DiagnosisData.SYSTEM_ENGINE
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onElectricalClick()
    self.selectedSystem = DiagnosisData.SYSTEM_ELECTRICAL
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onHydraulicClick()
    self.selectedSystem = DiagnosisData.SYSTEM_HYDRAULIC
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onTireClick()
    self.currentStep = FieldServiceKitDialog.STEP_TIRE_REPAIR
    self:updateDisplay()
end

--[[
    Diagnosis selection handlers
]]
function FieldServiceKitDialog:onDiagnosis1Click()
    self:applyRepair(1)
end

function FieldServiceKitDialog:onDiagnosis2Click()
    self:applyRepair(2)
end

function FieldServiceKitDialog:onDiagnosis3Click()
    self:applyRepair(3)
end

function FieldServiceKitDialog:onDiagnosis4Click()
    self:applyRepair(4)
end

--[[
    Hover effect handlers for diagnosis buttons
    Changes background color when mouse hovers over button
]]
function FieldServiceKitDialog:onDiagBtnHighlight(element)
    -- Derive background ID from button ID (diagBtn1 -> diagBtn1Bg)
    if element ~= nil and element.id ~= nil then
        local bgId = element.id .. "Bg"
        local bg = self[bgId]
        if bg ~= nil then
            -- Highlight color: lighter blue-ish
            bg:setImageColor(nil, 0.22, 0.28, 0.38, 1)
        end
    end
end

function FieldServiceKitDialog:onDiagBtnUnhighlight(element)
    -- Restore normal background color
    if element ~= nil and element.id ~= nil then
        local bgId = element.id .. "Bg"
        local bg = self[bgId]
        if bg ~= nil then
            -- Normal color (matches fskDiagBtnBg profile)
            bg:setImageColor(nil, 0.12, 0.12, 0.16, 1)
        end
    end
end

--[[
    Apply the repair based on diagnosis choice
    v1.8.0: Also applies repairs to RVB parts when RVB is installed
]]
function FieldServiceKitDialog:applyRepair(diagnosisIndex)
    self.selectedDiagnosis = diagnosisIndex

    -- Calculate outcome
    self.repairResult = DiagnosisData.calculateOutcome(
        self.actualFailedSystem,
        self.selectedSystem,
        self.currentScenario,
        diagnosisIndex,
        self.kitTier
    )

    -- Apply repair to vehicle
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        -- Apply reliability boost to the ACTUAL failed system (not player's guess)
        if self.actualFailedSystem == DiagnosisData.SYSTEM_ENGINE then
            maintSpec.engineReliability = math.min(1.0, maintSpec.engineReliability + self.repairResult.reliabilityBoost)
        elseif self.actualFailedSystem == DiagnosisData.SYSTEM_ELECTRICAL then
            maintSpec.electricalReliability = math.min(1.0, maintSpec.electricalReliability + self.repairResult.reliabilityBoost)
        elseif self.actualFailedSystem == DiagnosisData.SYSTEM_HYDRAULIC then
            maintSpec.hydraulicReliability = math.min(1.0, maintSpec.hydraulicReliability + self.repairResult.reliabilityBoost)
        end

        -- If vehicle was disabled, restore to functional (barely)
        if maintSpec.isDisabled then
            maintSpec.isDisabled = false
            -- Set function level based on repair outcome
            -- This would require additional tracking in the maintenance spec
        end

        -- v1.8.0: Apply repairs to RVB parts if RVB is installed
        -- This is the key integration - successful OBD diagnosis reduces RVB operating hours
        if ModCompatibility.rvbInstalled then
            -- Calculate hours reduction based on repair quality
            -- Perfect diagnosis = 50 hours, Good = 25 hours, Partial = 10 hours
            local hoursReduction = 10
            local clearFaults = false

            if self.repairResult.outcome == DiagnosisData.OUTCOME_PERFECT then
                hoursReduction = 50
                clearFaults = true  -- Perfect diagnosis clears fault codes
            elseif self.repairResult.outcome == DiagnosisData.OUTCOME_GOOD then
                hoursReduction = 25
                clearFaults = true
            end

            -- Apply to RVB based on which system was diagnosed
            ModCompatibility.applyOBDRepairToRVB(
                self.vehicle,
                self.selectedSystem,  -- Use player's selected system (they chose to work on it)
                hoursReduction,
                clearFaults
            )

            UsedPlus.logInfo(string.format("RVB repair applied: %s hours reduced by %d, faults cleared: %s",
                self.selectedSystem, hoursReduction, tostring(clearFaults)))
        end

        UsedPlus.logInfo(string.format("Field repair applied: %s reliability +%.1f%%, outcome: %s",
            self.actualFailedSystem,
            self.repairResult.reliabilityBoost * 100,
            self.repairResult.outcome))
    end

    -- Move to results step
    self.currentStep = FieldServiceKitDialog.STEP_RESULTS
    self:updateDisplay()
end

--[[
    Tire repair handlers
]]
function FieldServiceKitDialog:onTirePatchClick()
    self:applyTireRepair("patch")
end

function FieldServiceKitDialog:onTirePlugClick()
    self:applyTireRepair("plug")
end

function FieldServiceKitDialog:applyTireRepair(repairType)
    local result = DiagnosisData.calculateTireOutcome(repairType, self.kitTier)

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil and maintSpec.tireConditions ~= nil then
        -- Find and repair the flat tire(s)
        for i, condition in pairs(maintSpec.tireConditions) do
            if condition <= 0.01 then
                maintSpec.tireConditions[i] = result.conditionRestore
                UsedPlus.logInfo(string.format("Tire %d repaired with %s: %.0f%% condition",
                    i, repairType, result.conditionRestore * 100))
            end
        end
    end

    -- Consume kit and close
    self:consumeAndClose()
end

--[[
    OK button - close and consume kit
    Note: Button callback from XML onClick="onOkClick"
]]
function FieldServiceKitDialog:onOkClick()
    UsedPlus.logInfo("FieldServiceKitDialog: OK button clicked")
    self:consumeAndClose()
end

--[[
    Cancel button - close dialog
    Note: Kit is only consumed when repair is actually completed via OK button
]]
function FieldServiceKitDialog:onCancelClick()
    UsedPlus.logInfo("FieldServiceKitDialog: Cancel clicked, currentStep=" .. tostring(self.currentStep))
    self:close()
end

--[[
    Consume the kit and close dialog
]]
function FieldServiceKitDialog:consumeAndClose()
    UsedPlus.logInfo("FieldServiceKitDialog: consumeAndClose called")

    -- Tell kit to consume itself
    if self.kit ~= nil then
        UsedPlus.logInfo("FieldServiceKitDialog: Consuming kit")
        self.kit:consumeKit()
    else
        UsedPlus.logInfo("FieldServiceKitDialog: No kit reference to consume")
    end

    self:close()
end

function FieldServiceKitDialog:close()
    UsedPlus.logInfo("FieldServiceKitDialog: Closing dialog")
    g_gui:closeDialogByName("FieldServiceKitDialog")
end
