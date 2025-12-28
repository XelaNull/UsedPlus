--[[
    FS25_UsedPlus - Field Service Kit Dialog

    Multi-step diagnosis minigame dialog for emergency field repairs.
    Steps:
    1. System Selection - Player guesses which system failed
    2. Diagnosis - Player sees symptoms and picks likely cause
    3. Results - Shows repair outcome and applies to vehicle

    v1.8.0 - Field Service Kit System
]]

FieldServiceKitDialog = {}
local FieldServiceKitDialog_mt = Class(FieldServiceKitDialog, MessageDialog)

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
]]
function FieldServiceKitDialog:displaySystemSelection(vehicleName, maintSpec)
    -- v1.8.0: Get diagnostic data from ModCompatibility (includes RVB data if available)
    local diagData = ModCompatibility.getOBDDiagnosticData(self.vehicle)

    -- Get reliability values (uses RVB-derived values if RVB is installed)
    local engineRel = math.floor(diagData.engine.reliability * 100)
    local elecRel = math.floor(diagData.electrical.reliability * 100)
    local hydRel = math.floor(diagData.hydraulic.reliability * 100)

    local isDisabled = maintSpec.isDisabled or false
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

    -- Show/hide step containers
    self:setStepVisibility(FieldServiceKitDialog.STEP_SYSTEM_SELECT)

    -- Show tire button if flat tire detected
    if self.tireButton ~= nil then
        self.tireButton:setVisible(self.hasFlatTire)
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

    -- Display diagnosis options
    if self.diagButton1 ~= nil and self.currentScenario.diagnoses[1] then
        self.diagButton1:setText("[A] " .. g_i18n:getText(self.currentScenario.diagnoses[1]))
    end
    if self.diagButton2 ~= nil and self.currentScenario.diagnoses[2] then
        self.diagButton2:setText("[B] " .. g_i18n:getText(self.currentScenario.diagnoses[2]))
    end
    if self.diagButton3 ~= nil and self.currentScenario.diagnoses[3] then
        self.diagButton3:setText("[C] " .. g_i18n:getText(self.currentScenario.diagnoses[3]))
    end
    if self.diagButton4 ~= nil and self.currentScenario.diagnoses[4] then
        self.diagButton4:setText("[D] " .. g_i18n:getText(self.currentScenario.diagnoses[4]))
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_DIAGNOSIS)
end

--[[
    Display Step 3: Results
]]
function FieldServiceKitDialog:displayResults()
    if self.repairResult == nil then
        return
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance

    -- Result title based on outcome
    local titleKey = "usedplus_fsk_result_title_" .. self.repairResult.outcome
    if self.resultTitleText ~= nil then
        self.resultTitleText:setText(g_i18n:getText(titleKey) or "REPAIR COMPLETE")

        if self.repairResult.outcome == DiagnosisData.OUTCOME_PERFECT then
            self.resultTitleText:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
        elseif self.repairResult.outcome == DiagnosisData.OUTCOME_GOOD then
            self.resultTitleText:setTextColor(1, 0.7, 0, 1)  -- Orange
        else
            self.resultTitleText:setTextColor(1, 0.4, 0.4, 1)  -- Red-ish
        end
    end

    -- Result message
    if self.resultMessageText ~= nil then
        self.resultMessageText:setText(g_i18n:getText(self.repairResult.messageKey) or "Repairs applied.")
    end

    -- Show before/after values
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
        self:setReliabilityColor(self.afterRelText, afterRel)
    end
    if self.boostText ~= nil then
        self.boostText:setText(string.format("+%d%%", math.floor(self.repairResult.reliabilityBoost * 100)))
        self.boostText:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
    end

    -- Diagnosis feedback
    if self.diagnosisFeedbackText ~= nil then
        if self.repairResult.wasCorrectSystem and self.repairResult.wasCorrectDiagnosis then
            self.diagnosisFeedbackText:setText(g_i18n:getText("usedplus_fsk_feedback_perfect") or "Correct diagnosis!")
            self.diagnosisFeedbackText:setTextColor(0.2, 0.8, 0.2, 1)
        elseif self.repairResult.wasCorrectSystem then
            self.diagnosisFeedbackText:setText(g_i18n:getText("usedplus_fsk_feedback_partial") or "Right system, but diagnosis was off.")
            self.diagnosisFeedbackText:setTextColor(1, 0.7, 0, 1)
        else
            self.diagnosisFeedbackText:setText(g_i18n:getText("usedplus_fsk_feedback_wrong") or "Wrong system - general maintenance applied.")
            self.diagnosisFeedbackText:setTextColor(1, 0.4, 0.4, 1)
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

    -- Update button text based on step
    if self.okButton ~= nil then
        if activeStep == FieldServiceKitDialog.STEP_RESULTS then
            self.okButton:setText(g_i18n:getText("button_ok") or "OK")
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
]]
function FieldServiceKitDialog:onOkClick()
    self:consumeAndClose()
end

--[[
    Cancel button - close without consuming (only in system select step)
]]
function FieldServiceKitDialog:onCancelClick()
    if self.currentStep == FieldServiceKitDialog.STEP_SYSTEM_SELECT then
        -- Allow cancel only before starting repair
        self:close()
    else
        -- Once repair started, must complete
        g_gui:showInfoDialog({
            text = g_i18n:getText("usedplus_fsk_cannot_cancel") or "Repair in progress - cannot cancel."
        })
    end
end

--[[
    Consume the kit and close dialog
]]
function FieldServiceKitDialog:consumeAndClose()
    -- Tell kit to consume itself
    if self.kit ~= nil then
        self.kit:consumeKit()
    end

    self:close()
end

function FieldServiceKitDialog:close()
    g_gui:closeDialogByName("FieldServiceKitDialog")
end
