-- ============================================================================
-- MUMMUFRAMES PARTY FRAMES MODULE
-- ============================================================================
-- Manages custom party member unit frames with health, power, and aura displays.
--
-- ARCHITECTURE (Three-Layer Design):
--   Layer 1: Blizzard's CompactPartyFrame runs passively in the background,
--            managed by AuraHandle for visibility (alpha/scale only).
--   Layer 2: SecureGroupHeaderTemplate header ('mummuFramesPartyHeader') owns
--            unit attribution and child visibility via secure attributes.
--            In combat, only the header can modify unit assignments.
--   Layer 3: Visual sub-frames (health bar, power bar, auras, overlays) are
--            lazily attached to header children in normal Lua via BuildFrameVisuals.
--
-- MODES:
--   Real Mode:    Header manages live party members; frames map 1:1 to actual units.
--   Preview Mode: Header hidden; test frames shown with static data for positioning.
--   Test Mode:    Periodic ticker updates fake data; preview-only use case.
--
-- UNIT MAPPING:
--   During combat, the header may reassign children to different units.
--   Maps are rebuilt at safe times (combat-end) with safety-net retries.
--   GUID->DisplayedUnit and DisplayedUnit->Frame mappings enable correct aura dispatch.
-- ============================================================================

local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util
local L = ns.L

-- ============================================================================
-- CONFIGURATION CONSTANTS
-- ============================================================================

-- Runtime owner for secure party headers, preview frames, and party refresh logic.
local PartyFrames = ns.Object:Extend()

-- Texture and visual constants
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local MAX_PARTY_TEST_FRAMES = 5  -- Maximum frames in test/solo preview mode

-- Test mode unit lists for frame preview
local TEST_UNITS_WITH_PLAYER = { "player", "party1", "party2", "party3", "party4" }
local TEST_UNITS_NO_PLAYER = { "party1", "party2", "party3", "party4" }
local MEMBER_REFRESH_FULL = {
    vitals = true,
    auras = true,
}
local MEMBER_REFRESH_VITALS_ONLY = {
    vitals = true,
}
local MEMBER_REFRESH_AURAS_ONLY = {
    auras = true,
}
local OFFLINE_HEALTH_COLOR = { r = 0.38, g = 0.38, b = 0.38 }
local OFFLINE_POWER_COLOR = { r = 0.34, g = 0.34, b = 0.34 }
local DISCONNECTED_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\disconnected.png"
local SUMMON_PENDING_ICON_ATLAS = "RaidFrame-Icon-SummonPending"
local ROLE_ICON_ATLAS_BY_ROLE = {
    TANK = "UI-LFG-RoleIcon-Tank",
    HEALER = "UI-LFG-RoleIcon-Healer",
    DAMAGER = "UI-LFG-RoleIcon-DPS",
}
local GROUP_LEADER_ICON_ATLAS = "UI-HUD-UnitFrame-Player-Group-LeaderIcon"
local ROLE_SORT_PRIORITY = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
    NONE = 4,
}
local TEST_NAME_BY_UNIT = {
    player = UnitName("player") or "Player",
    party1 = "Party Member 1",
    party2 = "Party Member 2",
    party3 = "Party Member 3",
    party4 = "Party Member 4",
}
-- Synthetic preview roles so edit/test mode mirrors the live role bucket order.
local PREVIEW_ROLE_BY_UNIT = {
    party1 = "TANK",
    party2 = "HEALER",
    party3 = "DAMAGER",
    party4 = "NONE",
}
local HEALER_SPEC_BY_CLASS = {
    PRIEST = { [256] = true, [257] = true }, -- Discipline / Holy
    PALADIN = { [65] = true }, -- Holy
    MONK = { [270] = true }, -- Mistweaver
    DRUID = { [105] = true }, -- Restoration
    SHAMAN = { [264] = true }, -- Restoration
}
local POWER_TYPE_MANA = (_G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.Mana) or ((type(_G.SPELL_POWER_MANA) ~= "nil" and _G.SPELL_POWER_MANA) or 0)
local POWER_TYPE_RUNIC = (_G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.RunicPower) or (type(_G.SPELL_POWER_RUNIC_POWER) ~= "nil" and _G.SPELL_POWER_RUNIC_POWER or 6)
local PARTY_CATEGORY_HOME = (_G.Enum and _G.Enum.PartyCategory and _G.Enum.PartyCategory.Home) or 1
local PARTY_CATEGORY_INSTANCE = (_G.Enum and _G.Enum.PartyCategory and _G.Enum.PartyCategory.Instance) or 2
local ROLE_GROUPING_ORDER_ASC = "TANK,HEALER,DAMAGER,NONE"
local LEADER_ACTION_BUTTON_GAP = 4
local LEADER_ACTION_BUTTON_OFFSET_Y = 4
local PULL_ACTION_COMMAND = "/pull 9"
local LEADER_ACTION_TEXT_COLOR = { 0.96, 0.98, 1.00, 1.00 }
local LEADER_ACTION_BACKGROUND_COLOR = { 0.08, 0.09, 0.11, 0.96 }
local LEADER_ACTION_BACKGROUND_HOVER_COLOR = { 0.11, 0.13, 0.16, 0.98 }
local LEADER_ACTION_BACKGROUND_PRESSED_COLOR = { 0.16, 0.18, 0.22, 1.00 }
local LEADER_ACTION_BORDER_COLOR = { 1.00, 1.00, 1.00, 0.12 }
local LEADER_ACTION_BORDER_HOVER_COLOR = { 1.00, 1.00, 1.00, 0.20 }
local LEADER_ACTION_BORDER_PRESSED_COLOR = { 1.00, 1.00, 1.00, 0.26 }
local LEADER_ACTION_READY_ACCENT_COLOR = { 0.25, 0.88, 0.64, 0.95 }
local LEADER_ACTION_PULL_ACCENT_COLOR = { 1.00, 0.76, 0.28, 0.95 }

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Display unit tooltip on mouse-over; supports both secure frames and fallback tooltip APIs.
local function showUnitTooltip(frame)
    if not frame then
        return
    end

    local unit = nil
    if type(frame.GetAttribute) == "function" then
        local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if okAttr and type(attrUnit) == "string" and attrUnit ~= "" then
            unit = attrUnit
        end
    end
    if not unit then
        unit = frame.unit or frame.displayedUnit or nil
    end
    if not unit then
        return
    end

    if type(UnitFrame_OnEnter) == "function" then
        local ok = pcall(UnitFrame_OnEnter, frame)
        if ok then
            return
        end
    end

    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", 0, -2)
    end
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

-- Hide unit tooltip.
local function hideUnitTooltip(frame)
    if not frame then
        return
    end

    if type(UnitFrame_OnLeave) == "function" then
        UnitFrame_OnLeave(frame)
        return
    end

    GameTooltip:Hide()
end

-- Compute health/power as a percentage (0-100).
local function computePercent(value, maxValue)
    return (value / maxValue) * 100
end

-- Return numeric value or fallback, safely coercing via tostring() roundtrip.
local function getSafeNumericValue(value, fallback)
    if type(value) == "number" then
        local okString, asString = pcall(tostring, value)
        if okString and type(asString) == "string" then
            local parsed = tonumber(asString)
            if type(parsed) == "number" then
                return parsed
            end
        end
        return fallback
    end

    if type(value) == "string" then
        local parsed = tonumber(value)
        if type(parsed) == "number" then
            return parsed
        end
        return fallback
    end

    local okCoerced, coerced = pcall(tonumber, value)
    if okCoerced and type(coerced) == "number" then
        return coerced
    end

    return fallback
end

-- Return the displayed unit token currently mapped to the given GUID.
local function getDisplayedUnitForGUID(guidToUnitMap, guid)
    if type(guidToUnitMap) ~= "table" or type(guid) ~= "string" or guid == "" then
        return nil
    end

    local okMapped, mappedUnit = pcall(function()
        return guidToUnitMap[guid]
    end)
    if okMapped and type(mappedUnit) == "string" and mappedUnit ~= "" then
        return mappedUnit
    end
    return nil
end

-- Store the displayed unit token currently associated with the given GUID.
local function setDisplayedUnitForGUID(guidToUnitMap, guid, displayedUnit)
    if
        type(guidToUnitMap) ~= "table"
        or type(guid) ~= "string"
        or guid == ""
        or type(displayedUnit) ~= "string"
        or displayedUnit == ""
    then
        return
    end

    pcall(function()
        guidToUnitMap[guid] = displayedUnit
    end)
end

-- Safely read a unit GUID without letting API faults escape.
local function getUnitGUIDSafe(unitToken)
    if Util and type(Util.GetUnitGUIDSafe) == "function" then
        return Util:GetUnitGUIDSafe(unitToken)
    end

    return nil
end

-- Accept only the party tokens this module knows how to display.
local function normalizePartyDisplayedUnit(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if unitToken == "player" or string.match(unitToken, "^party%d+$") then
        return unitToken
    end
    return nil
end

-- Read the secure unit currently assigned to a party frame.
-- Prefer the live secure attribute because header children may be recycled or
-- reordered while their plain Lua backup fields still hold an older unit token.
local function getCurrentPartyFrameDisplayedUnit(frame)
    if type(frame) ~= "table" then
        return nil
    end

    if type(frame.GetAttribute) == "function" then
        local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if okAttr then
            local normalizedAttrUnit = normalizePartyDisplayedUnit(attrUnit)
            if normalizedAttrUnit then
                frame.unit = normalizedAttrUnit
                frame.displayedUnit = normalizedAttrUnit
                return normalizedAttrUnit
            end
            return nil
        end
    end

    local cachedUnit = normalizePartyDisplayedUnit(frame.displayedUnit or frame.unit)
    if cachedUnit then
        frame.unit = cachedUnit
        frame.displayedUnit = cachedUnit
        return cachedUnit
    end

    return nil
end

local function normalizeRoleToken(roleToken)
    if roleToken == "TANK" or roleToken == "HEALER" or roleToken == "DAMAGER" then
        return roleToken
    end
    return "NONE"
end

-- Resolve the default Blizzard role atlas for a role token.
local function resolveRoleIconAtlas(roleToken)
    local normalizedRole = normalizeRoleToken(roleToken)
    if normalizedRole == "NONE" then
        return nil
    end

    if type(GetIconForRole) == "function" then
        local atlas = GetIconForRole(normalizedRole, false)
        if type(atlas) == "string" and atlas ~= "" then
            return atlas
        end
    end

    return ROLE_ICON_ATLAS_BY_ROLE[normalizedRole]
end

local function shouldShowLeaderIcon(unitToken, previewMode)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end

    if previewMode then
        return unitToken == "player"
    end

    if type(UnitIsGroupLeader) ~= "function" then
        return false
    end

    local okLeader, isLeader = pcall(UnitIsGroupLeader, unitToken)
    if not okLeader then
        return false
    end

    return Util:SafeBoolean(isLeader, false)
end

local function isPlayerGroupLeader()
    if type(UnitIsGroupLeader) ~= "function" then
        return false
    end

    local okLeader, isLeader = pcall(UnitIsGroupLeader, "player")
    if not okLeader then
        return false
    end

    return Util:SafeBoolean(isLeader, false)
end

local function executeSlashCommand(commandText)
    if type(commandText) ~= "string" or commandText == "" then
        return false
    end

    local trimmedCommand = string.match(commandText, "^%s*(.-)%s*$")
    if not trimmedCommand or trimmedCommand == "" then
        return false
    end

    local slashCommand, arguments = string.match(trimmedCommand, "^(%S+)%s*(.-)%s*$")
    if type(slashCommand) ~= "string" or string.sub(slashCommand, 1, 1) ~= "/" then
        return false
    end

    local slashHandlers = _G.SlashCmdList
    if type(slashHandlers) ~= "table" then
        return false
    end

    local normalizedCommand = string.lower(slashCommand)
    for slashKey, handler in pairs(slashHandlers) do
        if type(slashKey) == "string" and type(handler) == "function" then
            for aliasIndex = 1, 20 do
                local alias = _G["SLASH_" .. slashKey .. aliasIndex]
                if type(alias) ~= "string" then
                    break
                end
                if string.lower(alias) == normalizedCommand then
                    local okRun = pcall(handler, arguments or "", nil)
                    return okRun == true
                end
            end
        end
    end

    return false
end

local function setLeaderActionButtonVisualState(button, state)
    if type(button) ~= "table" then
        return
    end

    local backgroundColor = LEADER_ACTION_BACKGROUND_COLOR
    local borderColor = LEADER_ACTION_BORDER_COLOR
    local highlightAlpha = 0
    if state == "pressed" then
        backgroundColor = LEADER_ACTION_BACKGROUND_PRESSED_COLOR
        borderColor = LEADER_ACTION_BORDER_PRESSED_COLOR
        highlightAlpha = 0.10
    elseif state == "hover" then
        backgroundColor = LEADER_ACTION_BACKGROUND_HOVER_COLOR
        borderColor = LEADER_ACTION_BORDER_HOVER_COLOR
        highlightAlpha = 0.06
    end

    if button.Background then
        button.Background:SetColorTexture(
            backgroundColor[1],
            backgroundColor[2],
            backgroundColor[3],
            backgroundColor[4]
        )
    end
    if button.HighlightFill then
        button.HighlightFill:SetAlpha(highlightAlpha)
    end
    if button.BorderTop then
        button.BorderTop:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        button.BorderBottom:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        button.BorderLeft:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        button.BorderRight:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
end

local function createLeaderActionButton(parent, labelText, accentColor)
    local button = CreateFrame("Button", nil, parent)
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(parent:GetFrameLevel() + 1)

    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetAllPoints()

    button.HighlightFill = button:CreateTexture(nil, "ARTWORK")
    button.HighlightFill:SetAllPoints()
    button.HighlightFill:SetColorTexture(1, 1, 1, 1)
    button.HighlightFill:SetAlpha(0)

    button.Accent = button:CreateTexture(nil, "BORDER")
    button.Accent:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.Accent:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.Accent:SetHeight(2)
    button.Accent:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], accentColor[4])

    button.BorderTop = button:CreateTexture(nil, "BORDER")
    button.BorderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.BorderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.BorderTop:SetHeight(1)

    button.BorderBottom = button:CreateTexture(nil, "BORDER")
    button.BorderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.BorderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.BorderBottom:SetHeight(1)

    button.BorderLeft = button:CreateTexture(nil, "BORDER")
    button.BorderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.BorderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.BorderLeft:SetWidth(1)

    button.BorderRight = button:CreateTexture(nil, "BORDER")
    button.BorderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.BorderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.BorderRight:SetWidth(1)

    button.Label = button:CreateFontString(nil, "OVERLAY")
    button.Label:SetPoint("CENTER", button, "CENTER", 0, 0)
    Style:ApplyFont(button.Label, 11, "OUTLINE")
    if not button.Label:GetFont() and GameFontNormalSmall then
        button.Label:SetFontObject(GameFontNormalSmall)
    end
    button.Label:SetTextColor(
        LEADER_ACTION_TEXT_COLOR[1],
        LEADER_ACTION_TEXT_COLOR[2],
        LEADER_ACTION_TEXT_COLOR[3],
        LEADER_ACTION_TEXT_COLOR[4]
    )
    button.Label:SetText(labelText)

    button:SetScript("OnEnter", function(selfButton)
        if selfButton:IsMouseEnabled() then
            setLeaderActionButtonVisualState(selfButton, "hover")
        end
    end)
    button:SetScript("OnLeave", function(selfButton)
        setLeaderActionButtonVisualState(selfButton, "normal")
    end)
    button:SetScript("OnMouseDown", function(selfButton)
        if selfButton:IsMouseEnabled() then
            setLeaderActionButtonVisualState(selfButton, "pressed")
        end
    end)
    button:SetScript("OnMouseUp", function(selfButton)
        if selfButton:IsMouseEnabled() and selfButton:IsMouseOver() then
            setLeaderActionButtonVisualState(selfButton, "hover")
        else
            setLeaderActionButtonVisualState(selfButton, "normal")
        end
    end)

    setLeaderActionButtonVisualState(button, "normal")
    return button
end

local function copyUnitList(units)
    if type(units) ~= "table" then
        return {}
    end

    local copy = {}
    for i = 1, #units do
        copy[i] = units[i]
    end
    return copy
end

local function refreshIncomingCastBoard(owner, runtimeState)
    if not owner or not owner.addon or type(owner.addon.GetModule) ~= "function" then
        return
    end

    local castBoard = owner.addon:GetModule("incomingCastBoard")
    if not castBoard or castBoard.enabled ~= true or type(castBoard.RefreshLayout) ~= "function" then
        return
    end

    castBoard:RefreshLayout(runtimeState)
end

-- Return whether the unit currently has a pending summon.
local function hasIncomingSummonPending(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end

    if C_IncomingSummon and type(C_IncomingSummon.IncomingSummonStatus) == "function" then
        local okStatus, status = pcall(C_IncomingSummon.IncomingSummonStatus, unitToken)
        if okStatus then
            local numericStatus = getSafeNumericValue(status, nil)
            if type(numericStatus) == "number" then
                local roundedStatus = math.floor(numericStatus + 0.5)
                return roundedStatus == 1
            end
        end
    end

    if C_IncomingSummon and type(C_IncomingSummon.HasIncomingSummon) == "function" then
        local okHas, hasSummon = pcall(C_IncomingSummon.HasIncomingSummon, unitToken)
        if okHas then
            return Util:SafeBoolean(hasSummon, false)
        end
    end

    return false
end

local function refreshPartyMemberRangeState(owner, frame, unitToken, previewMode, testMode, inRangeState)
    if not owner or not frame then
        return false
    end

    local exists = UnitExists(unitToken)
    local isConnected = true
    if not previewMode and not testMode and exists and type(UnitIsConnected) == "function" then
        isConnected = Util:SafeBoolean(UnitIsConnected(unitToken), true)
    end

    if owner.rangeHandle and type(owner.rangeHandle.ApplyGroupFrameAlpha) == "function" then
        return owner.rangeHandle:ApplyGroupFrameAlpha(frame, unitToken, {
            exists = exists,
            isConnected = isConnected,
            previewMode = previewMode,
            testMode = testMode,
            rangeValue = inRangeState,
        })
    end

    if previewMode or testMode or not exists then
        frame:SetAlpha(1)
    elseif not isConnected then
        frame:SetAlpha(0.7)
    else
        frame:SetAlpha(1)
    end
    return true
end

-- Set status bar value safely.
local function setStatusBarValueSafe(statusBar, currentValue, maxValue)
    if not statusBar then
        return
    end

    local okRange = pcall(statusBar.SetMinMaxValues, statusBar, 0, maxValue or 1)
    if not okRange then
        statusBar:SetMinMaxValues(0, 1)
    end

    local okValue = pcall(statusBar.SetValue, statusBar, currentValue or 0)
    if not okValue then
        statusBar:SetValue(0)
    end
end

-- Return whether player is grouped in the requested category.
-- Uses pcall to stay resilient across API variants.
local function isInGroupCategory(category)
    if type(IsInGroup) ~= "function" then
        return false
    end

    local okGrouped, isGrouped = pcall(IsInGroup, category)
    if okGrouped and type(isGrouped) == "boolean" then
        return isGrouped
    end
    return false
end

-- Return whether player is in a raid for the requested category.
-- Uses pcall to avoid hard faults in restricted/edge API states.
local function isInRaidCategory(category)
    if type(IsInRaid) ~= "function" then
        return false
    end

    local okRaid, inRaid = pcall(IsInRaid, category)
    if okRaid and type(inRaid) == "boolean" then
        return inRaid
    end
    return false
end

-- Count currently accessible party unit tokens (party1-party4).
local function getLivePartyUnitCount()
    if type(UnitExists) ~= "function" then
        return 0
    end

    local liveCount = 0
    for i = 1, 4 do
        if UnitExists("party" .. i) then
            liveCount = liveCount + 1
        end
    end
    return liveCount
end

-- Return player specialization id.
local function getPlayerSpecializationID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local currentSpecIndex = GetSpecialization()
    if type(currentSpecIndex) ~= "number" then
        return nil
    end

    local specID = GetSpecializationInfo(currentSpecIndex)
    if type(specID) ~= "number" then
        return nil
    end

    return specID
end

-- ============================================================================
-- PARTYFRAMES CLASS DEFINITION
-- ============================================================================

-- Initialize party frames state. Called once on class instantiation.
function PartyFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    self.unitFrames = nil
    self.rangeHandle = nil
    self.container = nil
    self.leaderActionBar = nil
    self.header = nil          -- SecureGroupHeaderTemplate frame
    self.testFrames = {}       -- fixed pool for preview/test mode only
    self.frames = {}           -- active frame set; populated by RefreshAll
    self._testTicker = nil
    self.editModeActive = false
    self.editModeCallbacksRegistered = false
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self._testMemberStateByUnit = nil
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    self._combatRemapRetryAt = 0
    self._lastLiveUnitsToShow = nil
    self._perfCountersEnabled = false
    self._perfCounters = {}
end

-- Initialize party frames module. Called by addon before OnEnable.
function PartyFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable party frames module. Sets up frames, events, and applies initial config.
function PartyFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")
    self.unitFrames = self.addon:GetModule("unitFrames")
    self.rangeHandle = self.addon:GetModule("rangeHandle")
    self:CreatePartyFrames()
    self:RegisterEvents()
    self:RegisterEditModeCallbacks()
    self._combatRemapRetryAt = 0
    self._lastLiveUnitsToShow = nil
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame.editModeActive == true) and true or false
    if self.editModeActive then
        self:EnsureEditModeSelection()
        if self.container and self.container.EditModeSelection then
            self.container.EditModeSelection:Show()
        end
    end
    self:ApplyBlizzardPartyFrameVisibility()
    self:RefreshAll(true)
end

-- Disable party frames module. Cleans up frames, unregisters events, and hides UI.
function PartyFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:UnregisterEditModeCallbacks()
    self.editModeActive = false
    self.rangeHandle = nil
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self._combatRemapRetryAt = 0
    self._testMemberStateByUnit = nil
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    self._lastLiveUnitsToShow = nil
    ns.activeMummuPartyFrames = {}
    self:HideLeaderActionButtons()
    self:StopTestTicker()
    self:SetBlizzardPartyFramesHidden(false)
    if self.container then
        self.container:StopMovingOrSizing()
        self.container._editModeMoving = false
        if self.container.EditModeSelection then
            self.container.EditModeSelection:Hide()
        end
        self.container:Hide()
    end
end

-- ============================================================================
-- TEST MODE UTILITIES
-- ============================================================================

-- Generate random static test data for one member (health, power, absorb).
function PartyFrames:CreateStaticTestMemberState(unitToken, showPowerBar)
    local displayName = TEST_NAME_BY_UNIT[unitToken] or unitToken
    if unitToken == "player" then
        displayName = UnitName("player") or displayName
    end

    local state = {
        name = displayName,
        health = math.random(35, 100),
        maxHealth = 100,
        power = showPowerBar and math.random(20, 100) or 0,
        maxPower = showPowerBar and 100 or 1,
        absorb = math.random(0, 35),
    }

    return state
end

-- Get or create cached static test state for a specific unit.
function PartyFrames:GetOrCreateStaticTestMemberState(unitToken, showPowerBar)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    self._testMemberStateByUnit = self._testMemberStateByUnit or {}
    local state = self._testMemberStateByUnit[unitToken]
    if state then
        return state
    end

    state = self:CreateStaticTestMemberState(unitToken, showPowerBar)
    self._testMemberStateByUnit[unitToken] = state
    return state
end

-- Ensure test member states exist for all units in the show list; prune others.
function PartyFrames:EnsureStaticTestMemberStates(unitsToShow)
    if type(unitsToShow) ~= "table" then
        return
    end

    self._testMemberStateByUnit = self._testMemberStateByUnit or {}
    local seen = {}
    for i = 1, #unitsToShow do
        local unitToken = unitsToShow[i]
        if type(unitToken) == "string" then
            seen[unitToken] = true
            self:GetOrCreateStaticTestMemberState(unitToken, self:ShouldShowPowerBar(unitToken))
        end
    end

    for unitToken in pairs(self._testMemberStateByUnit) do
        if not seen[unitToken] then
            self._testMemberStateByUnit[unitToken] = nil
        end
    end
end

-- ============================================================================
-- FRAME CREATION & VISUALS
-- ============================================================================

-- Create the party container, secure header, and preview frames.
-- AuraHandle keeps Blizzard's party frames suppressed; this module owns the
-- secure header and lazily attaches visual sub-frames to its children.
function PartyFrames:CreatePartyFrames()
    if self.container then
        return self.container
    end

    if not self.globalFrames then
        return nil
    end

    -- Positioning/EditMode container (plain, non-protected frame).
    local container = CreateFrame("Frame", "mummuFramesPartyContainer", UIParent)
    container:SetFrameStrata("LOW")
    container.unitToken = "party"
    container:Hide()
    self.container = container

    -- SecureGroupHeaderTemplate header: manages unit attribution for real party members.
    -- Children are SecureUnitButtonTemplate buttons created and assigned by the header's
    -- restricted attribute code, so unit assignment is never done from normal Lua in combat.
    local header = CreateFrame("Frame", "mummuFramesPartyHeader", container, "SecureGroupHeaderTemplate")
    header:SetFrameStrata("LOW")
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    -- initialConfigFunction runs in the restricted execution environment; only
    -- SetAttribute calls are permitted here.  Click registration and visual
    -- sub-frames are applied in normal Lua by BuildFrameVisuals, called lazily
    -- from the RefreshAll real-mode loop the first time each child is seen.
    header:SetAttribute("initialConfigFunction", [[
        self:SetAttribute("type1", "target")
        self:SetAttribute("*type2", "togglemenu")
    ]])
    header:SetAllPoints(container)
    self.header = header
    self:ApplyHeaderConfiguration("vertical", 24, 180, 34, true, true)

    -- Separate pool of test frames used exclusively in preview/test mode.
    -- These are plain children of the container, never touched by the secure header.
    self.testFrames = {}
    for i = 1, MAX_PARTY_TEST_FRAMES do
        local defaultUnitToken = (i <= 4) and ("party" .. i) or "player"
        local testFrame = CreateFrame(
            "Button",
            "mummuFramesPartyTestFrame" .. i,
            container,
            "SecureUnitButtonTemplate"
        )
        testFrame:SetAttribute("unit", defaultUnitToken)
        testFrame:SetAttribute("type1", "target")
        testFrame:SetAttribute("*type2", "togglemenu")
        testFrame:RegisterForClicks("AnyDown", "AnyUp")
        testFrame.unit = defaultUnitToken
        testFrame.displayedUnit = defaultUnitToken
        if self.globalFrames and type(self.globalFrames.RegisterClickCastFrame) == "function" then
            self.globalFrames:RegisterClickCastFrame(testFrame)
        end
        testFrame:Hide()
        self:BuildFrameVisuals(testFrame)
        self.testFrames[i] = testFrame
    end

    -- self.frames starts empty; RefreshAll populates it from either header children or testFrames.
    self.frames = {}

    return container
end

-- Return the top-level live/preview party container used by companion modules.
function PartyFrames:GetContainerFrame()
    return self.container
end

-- Return whether party frames are currently presenting preview/test content.
function PartyFrames:IsPreviewModeActive()
    if self.editModeActive == true then
        return true
    end
    if self.dataHandle and type(self.dataHandle.GetProfile) == "function" then
        local profile = self.dataHandle:GetProfile()
        return profile and profile.testMode == true or false
    end
    return false
end

-- Push layout and sorting attributes into the secure party header.
function PartyFrames:ApplyHeaderConfiguration(orientation, spacing, width, height, showPlayer, showSelfWithoutGroup)
    if not self.header then
        return
    end

    local layoutOrientation = (orientation == "horizontal") and "horizontal" or "vertical"
    local growthPoint = "TOP"
    local xOffset = 0
    local yOffset = -spacing
    local columnAnchorPoint = "LEFT"

    if layoutOrientation == "horizontal" then
        growthPoint = "LEFT"
        xOffset = spacing
        yOffset = 0
        columnAnchorPoint = "TOP"
    end

    -- Keep the secure header in a single explicit growth axis and let role
    -- grouping decide the visual order.
    self.header:SetAttribute("showParty", true)
    self.header:SetAttribute("showRaid", false)
    self.header:SetAttribute("showPlayer", showPlayer == true)
    self.header:SetAttribute("showSolo", showSelfWithoutGroup == true)
    self.header:SetAttribute("groupFilter", nil)
    self.header:SetAttribute("roleFilter", nil)
    self.header:SetAttribute("strictFiltering", false)
    self.header:SetAttribute("groupBy", "ASSIGNEDROLE")
    self.header:SetAttribute("groupingOrder", ROLE_GROUPING_ORDER_ASC)
    self.header:SetAttribute("sortMethod", "INDEX")
    self.header:SetAttribute("sortDir", "ASC")
    self.header:SetAttribute("nameList", nil)
    self.header:SetAttribute("point", growthPoint)
    self.header:SetAttribute("xOffset", xOffset)
    self.header:SetAttribute("yOffset", yOffset)
    self.header:SetAttribute("columnSpacing", 0)
    self.header:SetAttribute("columnAnchorPoint", columnAnchorPoint)
    self.header:SetAttribute("unitsPerColumn", MAX_PARTY_TEST_FRAMES)
    self.header:SetAttribute("maxColumns", 1)
    self.header:SetAttribute("frameWidth", width)
    self.header:SetAttribute("frameHeight", height)
    self.header:SetAttribute("maxDisplayed", MAX_PARTY_TEST_FRAMES)
end

-- Attach visual sub-frames to a party member button (health bar, power bar, auras, overlays).
-- Idempotent: safe to call multiple times. Called for both header-managed children and test frames.
function PartyFrames:BuildFrameVisuals(frame)
    if not frame or frame._mummuVisualsBuilt then
        return
    end

    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame._mummuIsGroupFrame = true
    frame._mummuIsPartyFrame = true

    if type(frame.RegisterForClicks) == "function" then
        frame:RegisterForClicks("AnyDown", "AnyUp")
    end
    if self.globalFrames and type(self.globalFrames.RegisterClickCastFrame) == "function" then
        self.globalFrames:RegisterClickCastFrame(frame)
    end
    frame:SetScript("OnEnter", showUnitTooltip)
    frame:SetScript("OnLeave", hideUnitTooltip)

    frame.Background = Style:CreateBackground(frame, 0.06, 0.06, 0.07, 0.9)
    frame.HealthBar = self.globalFrames:CreateStatusBar(frame, "health")
    frame.PowerBar = self.globalFrames:CreateStatusBar(frame, "primaryPower")

    frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.NameText:SetJustifyH("LEFT")
    frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.HealthText:SetJustifyH("RIGHT")
    frame.RoleIconOverlay = CreateFrame("Frame", nil, frame)
    frame.RoleIconOverlay:SetAllPoints(frame)
    frame.RoleIconOverlay:SetFrameStrata("DIALOG")
    frame.RoleIconOverlay:SetFrameLevel(frame:GetFrameLevel() + 40)
    frame.RoleIcon = frame.RoleIconOverlay:CreateTexture(nil, "OVERLAY")
    frame.RoleIcon:SetAlpha(0.95)
    frame.RoleIcon:Hide()
    frame.LeaderIcon = frame.RoleIconOverlay:CreateTexture(nil, "OVERLAY")
    frame.LeaderIcon:SetAlpha(0.95)
    frame.LeaderIcon:Hide()
    if self.globalFrames and type(self.globalFrames.CreateReadyCheckIndicator) == "function" then
        self.globalFrames:CreateReadyCheckIndicator(frame, frame.RoleIconOverlay)
    end

    frame.AbsorbOverlayFrame = CreateFrame("Frame", nil, frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
    frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
    frame.AbsorbOverlayFrame:Hide()

    frame.AbsorbOverlayBar = CreateFrame("StatusBar", nil, frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetAllPoints(frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
    frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    frame.AbsorbOverlayBar:Hide()

    if self.globalFrames and type(self.globalFrames.CreateGroupDispelIndicator) == "function" then
        self.globalFrames:CreateGroupDispelIndicator(frame, frame.HealthBar)
    else
        frame.DispelOverlay = frame.HealthBar:CreateTexture(nil, "OVERLAY")
        frame.DispelOverlay:SetAllPoints(frame.HealthBar)
        frame.DispelOverlay:Hide()
    end

    frame.DisconnectedOverlay = CreateFrame("Frame", nil, frame)
    frame.DisconnectedOverlay:SetAllPoints(frame)
    frame.DisconnectedOverlay:SetFrameStrata(frame:GetFrameStrata())
    frame.DisconnectedOverlay:SetFrameLevel(frame:GetFrameLevel() + 40)
    frame.DisconnectedIcon = frame.DisconnectedOverlay:CreateTexture(nil, "OVERLAY")
    frame.DisconnectedIcon:SetTexture(DISCONNECTED_ICON_TEXTURE)
    frame.DisconnectedIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.DisconnectedIcon:SetAlpha(0.95)
    frame.DisconnectedIcon:Hide()

    frame.SummonOverlay = CreateFrame("Frame", nil, frame)
    frame.SummonOverlay:SetAllPoints(frame)
    frame.SummonOverlay:SetFrameStrata(frame:GetFrameStrata())
    frame.SummonOverlay:SetFrameLevel(frame:GetFrameLevel() + 39)
    frame.SummonIcon = frame.SummonOverlay:CreateTexture(nil, "OVERLAY")
    if type(frame.SummonIcon.SetAtlas) == "function" then
        frame.SummonIcon:SetAtlas(SUMMON_PENDING_ICON_ATLAS, true)
    end
    frame.SummonIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.SummonIcon:SetAlpha(0.95)
    frame.SummonIcon:Hide()

    frame.TargetHighlight = CreateFrame("Frame", nil, frame)
    frame.TargetHighlight:SetAllPoints(frame)
    frame.TargetHighlight:SetFrameStrata(frame:GetFrameStrata())
    frame.TargetHighlight:SetFrameLevel(frame:GetFrameLevel() + 35)
    if type(frame.TargetHighlight.SetIgnoreParentAlpha) == "function" then
        -- Keep the border readable even when the base frame is dimmed for range/offline state.
        frame.TargetHighlight:SetIgnoreParentAlpha(true)
    end
    frame.TargetHighlight:Hide()

    local targetHighlightBorder = 2
    local targetHighlightColor = { 1, 0.84, 0.18, 0.95 }
    frame.TargetHighlight.Top = frame.TargetHighlight:CreateTexture(nil, "OVERLAY")
    frame.TargetHighlight.Top:SetPoint("TOPLEFT", frame.TargetHighlight, "TOPLEFT", 0, 0)
    frame.TargetHighlight.Top:SetPoint("TOPRIGHT", frame.TargetHighlight, "TOPRIGHT", 0, 0)
    frame.TargetHighlight.Top:SetHeight(targetHighlightBorder)
    frame.TargetHighlight.Top:SetColorTexture(
        targetHighlightColor[1], targetHighlightColor[2],
        targetHighlightColor[3], targetHighlightColor[4]
    )
    frame.TargetHighlight.Bottom = frame.TargetHighlight:CreateTexture(nil, "OVERLAY")
    frame.TargetHighlight.Bottom:SetPoint("BOTTOMLEFT", frame.TargetHighlight, "BOTTOMLEFT", 0, 0)
    frame.TargetHighlight.Bottom:SetPoint("BOTTOMRIGHT", frame.TargetHighlight, "BOTTOMRIGHT", 0, 0)
    frame.TargetHighlight.Bottom:SetHeight(targetHighlightBorder)
    frame.TargetHighlight.Bottom:SetColorTexture(
        targetHighlightColor[1], targetHighlightColor[2],
        targetHighlightColor[3], targetHighlightColor[4]
    )
    frame.TargetHighlight.Left = frame.TargetHighlight:CreateTexture(nil, "OVERLAY")
    frame.TargetHighlight.Left:SetPoint("TOPLEFT", frame.TargetHighlight, "TOPLEFT", 0, 0)
    frame.TargetHighlight.Left:SetPoint("BOTTOMLEFT", frame.TargetHighlight, "BOTTOMLEFT", 0, 0)
    frame.TargetHighlight.Left:SetWidth(targetHighlightBorder)
    frame.TargetHighlight.Left:SetColorTexture(
        targetHighlightColor[1], targetHighlightColor[2],
        targetHighlightColor[3], targetHighlightColor[4]
    )
    frame.TargetHighlight.Right = frame.TargetHighlight:CreateTexture(nil, "OVERLAY")
    frame.TargetHighlight.Right:SetPoint("TOPRIGHT", frame.TargetHighlight, "TOPRIGHT", 0, 0)
    frame.TargetHighlight.Right:SetPoint("BOTTOMRIGHT", frame.TargetHighlight, "BOTTOMRIGHT", 0, 0)
    frame.TargetHighlight.Right:SetWidth(targetHighlightBorder)
    frame.TargetHighlight.Right:SetColorTexture(
        targetHighlightColor[1], targetHighlightColor[2],
        targetHighlightColor[3], targetHighlightColor[4]
    )

    if ns.AuraHandle and type(ns.AuraHandle.PrimeTrackedAuraIndicators) == "function" then
        ns.AuraHandle:PrimeTrackedAuraIndicators(frame)
    end

    frame._mummuVisualsBuilt = true
end

-- ============================================================================
-- BLIZZARD FRAME & CONFIG MANAGEMENT
-- ============================================================================

-- Hide or show Blizzard's party frame based on config. Controls visibility via
-- AuraHandle (alpha/scale only), never direct frame Show/Hide.
function PartyFrames:SetBlizzardPartyFramesHidden(shouldHide)
    if ns.AuraHandle then
        ns.AuraHandle:SetBlizzardFramesHidden("party", shouldHide, "partyFrames")
    end
end

-- Apply Blizzard party frame visibility by config.
local function getPerfNowMilliseconds()
    if type(debugprofilestop) == "function" then
        local okNow, now = pcall(debugprofilestop)
        if okNow and type(now) == "number" then
            return now
        end
    end
    if type(GetTimePreciseSec) == "function" then
        local okNow, now = pcall(GetTimePreciseSec)
        if okNow and type(now) == "number" then
            return now * 1000
        end
    end
    if type(GetTime) == "function" then
        local okNow, now = pcall(GetTime)
        if okNow and type(now) == "number" then
            return now * 1000
        end
    end
    return 0
end

local function startPerfCounters(owner)
    if not owner or owner._perfCountersEnabled ~= true then
        return nil
    end
    return getPerfNowMilliseconds()
end

local function recordPerfCounters(owner, label, startedAt)
    if not owner or owner._perfCountersEnabled ~= true or type(label) ~= "string" or type(startedAt) ~= "number" then
        return
    end

    owner._perfCounters = owner._perfCounters or {}
    local elapsed = getPerfNowMilliseconds() - startedAt
    if elapsed < 0 then
        elapsed = 0
    end

    local counter = owner._perfCounters[label]
    if type(counter) ~= "table" then
        counter = { count = 0, totalMs = 0, maxMs = 0 }
        owner._perfCounters[label] = counter
    end

    counter.count = counter.count + 1
    counter.totalMs = counter.totalMs + elapsed
    if elapsed > counter.maxMs then
        counter.maxMs = elapsed
    end
end

local function finishPerfCounters(owner, label, startedAt, ...)
    recordPerfCounters(owner, label, startedAt)
    return ...
end

local function copyPerfCounters(counters)
    local copy = {}
    if type(counters) ~= "table" then
        return copy
    end

    for label, counter in pairs(counters) do
        if type(label) == "string" and type(counter) == "table" then
            copy[label] = {
                count = tonumber(counter.count) or 0,
                totalMs = tonumber(counter.totalMs) or 0,
                maxMs = tonumber(counter.maxMs) or 0,
            }
        end
    end

    return copy
end

local function buildPartyRuntimeState(self, profileOverride, partyConfigOverride)
    if not self or not self.dataHandle then
        return nil
    end

    local profile = profileOverride or self.dataHandle:GetProfile()
    local partyConfig = partyConfigOverride or self.dataHandle:GetUnitConfig("party") or {}
    local testMode = profile and profile.testMode == true
    local previewMode = testMode or self.editModeActive

    return {
        profile = profile,
        partyConfig = partyConfig,
        testMode = testMode,
        previewMode = previewMode,
        addonEnabled = profile and profile.enabled ~= false,
    }
end

function PartyFrames:CreateLeaderActionButtons()
    if not self.container then
        return nil
    end
    if self.leaderActionBar then
        return self.leaderActionBar
    end

    local actionBar = CreateFrame("Frame", nil, self.container)
    actionBar:SetFrameStrata("MEDIUM")
    actionBar:SetFrameLevel(self.container:GetFrameLevel() + 60)
    actionBar:Hide()

    local readyButton = createLeaderActionButton(actionBar, "Ready", LEADER_ACTION_READY_ACCENT_COLOR)
    readyButton:SetScript("OnClick", function()
        if not isPlayerGroupLeader() or type(DoReadyCheck) ~= "function" then
            return
        end
        pcall(DoReadyCheck)
    end)

    local pullButton = createLeaderActionButton(actionBar, "Pull", LEADER_ACTION_PULL_ACCENT_COLOR)
    pullButton:SetScript("OnClick", function()
        if not isPlayerGroupLeader() then
            return
        end
        if executeSlashCommand(PULL_ACTION_COMMAND) then
            return
        end
        if C_PartyInfo and type(C_PartyInfo.DoCountdown) == "function" then
            local okCountdown = pcall(C_PartyInfo.DoCountdown, 9)
            if okCountdown then
                return
            end
        end
        Util:Print("Unable to start /pull 9.")
    end)

    actionBar.ReadyButton = readyButton
    actionBar.PullButton = pullButton
    self.leaderActionBar = actionBar
    return actionBar
end

function PartyFrames:RefreshLeaderActionSelectionBounds()
    if not self.container or not self.container.EditModeSelection then
        return
    end

    local selection = self.container.EditModeSelection
    local extraTop = 0
    if self.leaderActionBar and self.leaderActionBar:IsShown() then
        local actionBarHeight = self.leaderActionBar:GetHeight() or 0
        local actionBarOffset = tonumber(self.leaderActionBar._mummuOffsetY) or LEADER_ACTION_BUTTON_OFFSET_Y
        extraTop = actionBarHeight + actionBarOffset
        if Style:IsPixelPerfectEnabled() then
            extraTop = Style:Snap(extraTop)
        else
            extraTop = math.floor(extraTop + 0.5)
        end
    end

    selection:ClearAllPoints()
    selection:SetPoint("TOPLEFT", self.container, "TOPLEFT", 0, extraTop)
    selection:SetPoint("BOTTOMRIGHT", self.container, "BOTTOMRIGHT", 0, 0)
end

function PartyFrames:HideLeaderActionButtons()
    if self.leaderActionBar then
        self.leaderActionBar:Hide()
    end
    self:RefreshLeaderActionSelectionBounds()
end

function PartyFrames:RefreshLeaderActionButtons(runtimeState, frameHeight, inAnyGroup, inAnyRaid)
    local actionBar = self:CreateLeaderActionButtons()
    if not actionBar then
        return
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    local grouped = type(inAnyGroup) == "boolean" and inAnyGroup
        or (isInGroupCategory(PARTY_CATEGORY_HOME) or isInGroupCategory(PARTY_CATEGORY_INSTANCE))
    local raided = type(inAnyRaid) == "boolean" and inAnyRaid
        or (isInRaidCategory(PARTY_CATEGORY_HOME) or isInRaidCategory(PARTY_CATEGORY_INSTANCE))
    local showEditModeSample = self.editModeActive == true
    local shouldShowLive = state
        and state.previewMode ~= true
        and state.addonEnabled ~= false
        and state.partyConfig
        and state.partyConfig.enabled ~= false
        and grouped
        and not raided
        and isPlayerGroupLeader()
    local shouldShow = showEditModeSample or shouldShowLive

    if not shouldShow then
        actionBar:Hide()
        self:RefreshLeaderActionSelectionBounds()
        return
    end

    local pixelPerfect = Style:IsPixelPerfectEnabled()
    local buttonHeight = Util:Clamp(math.floor(((tonumber(frameHeight) or 34) * 0.58) + 0.5), 18, 22)
    local readyWidth = Util:Clamp(math.floor((buttonHeight * 2.8) + 0.5), 46, 68)
    local pullWidth = Util:Clamp(math.floor((buttonHeight * 2.4) + 0.5), 40, 60)
    local gap = LEADER_ACTION_BUTTON_GAP
    local offsetY = LEADER_ACTION_BUTTON_OFFSET_Y

    if pixelPerfect then
        buttonHeight = Style:Snap(buttonHeight)
        readyWidth = Style:Snap(readyWidth)
        pullWidth = Style:Snap(pullWidth)
        gap = Style:Snap(gap)
        offsetY = Style:Snap(offsetY)
    else
        buttonHeight = math.floor(buttonHeight + 0.5)
        readyWidth = math.floor(readyWidth + 0.5)
        pullWidth = math.floor(pullWidth + 0.5)
        gap = math.floor(gap + 0.5)
        offsetY = math.floor(offsetY + 0.5)
    end

    actionBar:ClearAllPoints()
    actionBar:SetPoint("BOTTOMLEFT", self.container, "TOPLEFT", 0, offsetY)
    actionBar:SetSize(readyWidth + gap + pullWidth, buttonHeight)
    actionBar._mummuOffsetY = offsetY

    actionBar.ReadyButton:ClearAllPoints()
    actionBar.ReadyButton:SetPoint("LEFT", actionBar, "LEFT", 0, 0)
    actionBar.ReadyButton:SetSize(readyWidth, buttonHeight)

    actionBar.PullButton:ClearAllPoints()
    actionBar.PullButton:SetPoint("LEFT", actionBar.ReadyButton, "RIGHT", gap, 0)
    actionBar.PullButton:SetSize(pullWidth, buttonHeight)

    if actionBar.ReadyButton.Label then
        Style:ApplyFont(actionBar.ReadyButton.Label, math.max(10, math.floor((buttonHeight * 0.54) + 0.5)), "OUTLINE")
    end
    if actionBar.PullButton.Label then
        Style:ApplyFont(actionBar.PullButton.Label, math.max(10, math.floor((buttonHeight * 0.54) + 0.5)), "OUTLINE")
    end

    if type(actionBar.ReadyButton.EnableMouse) == "function" then
        actionBar.ReadyButton:EnableMouse(not showEditModeSample)
    end
    if type(actionBar.PullButton.EnableMouse) == "function" then
        actionBar.PullButton:EnableMouse(not showEditModeSample)
    end
    actionBar:SetAlpha(showEditModeSample and 0.96 or 1)

    actionBar:Show()
    self:RefreshLeaderActionSelectionBounds()
end

function PartyFrames:ApplyBlizzardPartyFrameVisibility(runtimeState)
    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return
    end

    local shouldHide = state.addonEnabled and state.partyConfig and state.partyConfig.hideBlizzardFrame == true
    self:SetBlizzardPartyFramesHidden(shouldHide)
end

-- Register party frame events.
function PartyFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_DISABLED", self.OnCombatStarted)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "PLAYER_TARGET_CHANGED", self.OnTargetChanged)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PARTY_LEADER_CHANGED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "READY_CHECK", self.OnReadyCheckChanged)
    ns.EventRouter:Register(self, "READY_CHECK_CONFIRM", self.OnReadyCheckChanged)
    ns.EventRouter:Register(self, "READY_CHECK_FINISHED", self.OnReadyCheckChanged)
    ns.EventRouter:Register(self, "PLAYER_ROLES_ASSIGNED", self.OnRoleAssignmentChanged)
    ns.EventRouter:Register(self, "ROLE_CHANGED_INFORM", self.OnRoleAssignmentChanged)
    ns.EventRouter:Register(self, "PLAYER_SPECIALIZATION_CHANGED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_TALENT_UPDATE", self.OnWorldEvent)
    -- Non-range group unit events are routed centrally by AuraHandle.
end

-- Register for EditMode callbacks (enter/exit events).
function PartyFrames:RegisterEditModeCallbacks()
    if self.editModeCallbacksRegistered then
        return
    end

    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    EventRegistry:RegisterCallback("EditMode.Enter", self.OnEditModeEnter, self)
    EventRegistry:RegisterCallback("EditMode.Exit", self.OnEditModeExit, self)
    self.editModeCallbacksRegistered = true
end

-- Unregister from EditMode callbacks.
function PartyFrames:UnregisterEditModeCallbacks()
    if not self.editModeCallbacksRegistered then
        return
    end

    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end

    self.editModeCallbacksRegistered = false
end

-- Ensure EditMode selection frame exists for the party container.
function PartyFrames:EnsureEditModeSelection()
    if not self.container or not self.unitFrames then
        return
    end

    if type(self.unitFrames.EnsureEditModeSelection) == "function" then
        self.unitFrames:EnsureEditModeSelection(self.container)
    end

    local selection = self.container.EditModeSelection
    if selection and selection.Label and selection.Label.SetText then
        selection.Label:SetText((L and L.CONFIG_TAB_PARTY) or "Party")
    end
    self:RefreshLeaderActionSelectionBounds()
end

-- Handle EditMode entering; show selection UI and refresh frames.
function PartyFrames:OnEditModeEnter()
    self.editModeActive = true
    self:EnsureEditModeSelection()
    if self.container and self.container.EditModeSelection then
        self.container.EditModeSelection:Show()
    end
    self:RefreshAll(true)
end

-- Handle EditMode exiting; hide selection UI and restore live frames.
function PartyFrames:OnEditModeExit()
    self.editModeActive = false
    if self.container then
        self.container:StopMovingOrSizing()
        self.container._editModeMoving = false
        if self.container.EditModeSelection then
            self.container.EditModeSelection:Hide()
        end
    end
    self:RefreshAll(true)
end

-- Apply one layout-affecting refresh path with combat-safe deferral.
function PartyFrames:HandleLayoutAffectingChange(reason)
    local refreshReason = type(reason) == "string" and reason or "world"
    if InCombatLockdown() then
        self.pendingLayoutRefresh = true
        self:RebuildDisplayedUnitMap(true)
        self:ScheduleMapRebuildSafetyNet(refreshReason .. "_combat", true)
        return
    end
    self:RefreshAll(true)
    self:RebuildDisplayedUnitMap(false)
    self:ScheduleMapRebuildSafetyNet(refreshReason, false)
end

-- Handle world/roster/specialization change events; rebuild unit maps with combat awareness.
function PartyFrames:OnWorldEvent()
    self:HandleLayoutAffectingChange("world")
end

-- Re-apply the secure header ordering when party role assignments change.
function PartyFrames:OnRoleAssignmentChanged()
    self:HandleLayoutAffectingChange("role_changed")
end

-- Refresh only the ready-check overlay state for active party frames.
function PartyFrames:RefreshReadyCheckIndicators(eventName, runtimeState)
    if not self.globalFrames or type(self.globalFrames.RefreshReadyCheckIndicator) ~= "function" then
        return
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return
    end

    local previewMode = state.previewMode == true or state.testMode == true
    for index = 1, #(self.frames or {}) do
        local frame = self.frames[index]
        if frame then
            local displayedUnit = getCurrentPartyFrameDisplayedUnit(frame) or frame.displayedUnit or frame.unit
            self.globalFrames:RefreshReadyCheckIndicator(frame, displayedUnit, eventName, previewMode)
        end
    end
end

-- Handle ready-check events without forcing aura re-renders.
function PartyFrames:OnReadyCheckChanged(eventName)
    self:RefreshReadyCheckIndicators(eventName)
end

-- Handle player's current target changing; refresh target highlight.
function PartyFrames:OnTargetChanged()
    self:RefreshAll(false)
end

-- Handle entering combat; prevent layout/visibility churn and keep map warm.
function PartyFrames:OnCombatStarted()
    self:RefreshAll(false)
    self:RebuildDisplayedUnitMap(true)
    self:ScheduleMapRebuildSafetyNet("combat_started", true)
    self.pendingLayoutRefresh = true
end

-- Handle exiting combat; apply any deferred layout changes and rebuild unit maps.
function PartyFrames:OnCombatEnded()
    if self.pendingLayoutRefresh then
        self.pendingLayoutRefresh = false
        self:RefreshAll(true)
        self:ScheduleMapRebuildSafetyNet("combat_ended_layout", false)
        return
    end

    self:RefreshAll(false)
    self:ScheduleMapRebuildSafetyNet("combat_ended", false)
end

-- ============================================================================
-- UNIT MAPPING & RESOLUTION
-- ============================================================================
-- Maps maintain consistency between:
--   1. GUID -> DisplayedUnit (which unit token is showing that player)
--   2. DisplayedUnit -> Frame (which frame is showing that unit)
-- These maps are rebuilt at safe times (non-combat) or with combat workarounds.

-- Rebuild displayed-unit map from the SecureGroupHeaderTemplate header's current children.
-- In real mode, the header owns unit attribution; we just read its current state.
-- In preview/test mode, we read self.testFrames instead.
-- allowHidden=true retains the previous map entry for any unit that existed before (combat safety).
function PartyFrames:RebuildDisplayedUnitMap(allowHidden, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    local frameByDisplayedUnit = {}
    local displayedUnitByGUID = {}
    local includeHidden = allowHidden == true
    local previousFrameByDisplayedUnit =
        type(self._frameByDisplayedUnit) == "table" and self._frameByDisplayedUnit or {}

    -- Determine the candidate frame pool.
    local candidateFrames
    local state = runtimeState or buildPartyRuntimeState(self)
    local isPreview = state and state.previewMode == true
    if isPreview and type(self.testFrames) == "table" then
        candidateFrames = self.testFrames
    elseif type(self.frames) == "table" and #self.frames > 0 then
        -- Use the live active frame list from the last RefreshAll.
        -- This includes the solo player frame when not in a group.
        candidateFrames = self.frames
    elseif self.header then
        -- Fallback before first RefreshAll has run.
        candidateFrames = {}
        local children = { self.header:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child and child._mummuVisualsBuilt then
                candidateFrames[#candidateFrames + 1] = child
            end
        end
    end

    if not candidateFrames then
        self._frameByDisplayedUnit = frameByDisplayedUnit
        self._displayedUnitByGUID = displayedUnitByGUID
        return finishPerfCounters(self, "RebuildDisplayedUnitMap", perfStartedAt, 0)
    end

    for i = 1, #candidateFrames do
        local frame = candidateFrames[i]
        if frame then
            local isShown = type(frame.IsShown) == "function" and frame:IsShown() or true

            if includeHidden or isShown then
                local displayedUnit = getCurrentPartyFrameDisplayedUnit(frame)

                local shouldMapUnit = false
                if displayedUnit == "player" then
                    shouldMapUnit = true
                elseif displayedUnit and UnitExists(displayedUnit) then
                    shouldMapUnit = true
                elseif displayedUnit and includeHidden and InCombatLockdown() then
                    shouldMapUnit = previousFrameByDisplayedUnit[displayedUnit] == frame
                end

                if displayedUnit and shouldMapUnit and not frameByDisplayedUnit[displayedUnit] then
                    frameByDisplayedUnit[displayedUnit] = frame
                    frame.unit = displayedUnit
                    frame.displayedUnit = displayedUnit
                    local guid = getUnitGUIDSafe(displayedUnit)
                    if guid then
                        setDisplayedUnitForGUID(displayedUnitByGUID, guid, displayedUnit)
                    end
                end
            end
        end
    end

    -- In combat: carry forward any previously-mapped units that are still valid but
    -- whose frames may temporarily be hidden by the header mid-roster-transition.
    if includeHidden and InCombatLockdown() then
        for unitToken, previousFrame in pairs(previousFrameByDisplayedUnit) do
            local isPartyUnit = type(unitToken) == "string"
                and (unitToken == "player" or string.match(unitToken, "^party%d+$"))
            if isPartyUnit and previousFrame and not frameByDisplayedUnit[unitToken] then
                if unitToken == "player" or UnitExists(unitToken) then
                    frameByDisplayedUnit[unitToken] = previousFrame
                    previousFrame.unit = unitToken
                    previousFrame.displayedUnit = unitToken
                    local guid = getUnitGUIDSafe(unitToken)
                    if guid then
                        setDisplayedUnitForGUID(displayedUnitByGUID, guid, unitToken)
                    end
                end
            end
        end
    end

    self._frameByDisplayedUnit = frameByDisplayedUnit
    self._displayedUnitByGUID = displayedUnitByGUID

    local mappedCount = 0
    for _ in pairs(frameByDisplayedUnit) do
        mappedCount = mappedCount + 1
    end

    return finishPerfCounters(self, "RebuildDisplayedUnitMap", perfStartedAt, mappedCount)
end

-- Schedule repeated map rebuilds (safety net) to heal secure-header/roster transition drift.
-- Runs immediately and at delayed intervals to ensure map consistency during transitions.
function PartyFrames:ScheduleMapRebuildSafetyNet(reason, allowHidden)
    local includeHidden = allowHidden == true
    self._mapRebuildSafetyToken = (self._mapRebuildSafetyToken or 0) + 1
    local token = self._mapRebuildSafetyToken

    -- Rebuild once per scheduled pass while ignoring stale timer callbacks.
    local function runPass(tag)
        if self._mapRebuildSafetyToken ~= token then
            return
        end
        if not self.dataHandle then
            return
        end

        self:RebuildDisplayedUnitMap(includeHidden)
    end

    runPass("immediate")
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    C_Timer.After(0.1, function() runPass("delay_0.1") end)
    C_Timer.After(0.4, function() runPass("delay_0.4") end)
    C_Timer.After(1.0, function() runPass("delay_1.0") end)
end

-- Ensure one party unit token is mapped to the header child that already owns it.
-- This is intentionally strict: we never "borrow" an arbitrary child for another
-- unit token, because that can render incorrect data during combat remaps.
function PartyFrames:EnsureMappedFrameForUnit(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if unitToken ~= "player" and not string.match(unitToken, "^party%d+$") then
        return nil
    end
    if not self.header then
        return nil
    end

    self._frameByDisplayedUnit = self._frameByDisplayedUnit or {}
    local existing = self._frameByDisplayedUnit[unitToken]
    if existing then
        return existing
    end

    -- Collect header children and look for one already holding this unit.
    local children = { self.header:GetChildren() }
    local matched = nil
    for i = 1, #children do
        local child = children[i]
        if child and child._mummuVisualsBuilt then
            local childUnit = getCurrentPartyFrameDisplayedUnit(child)
            if childUnit == unitToken then
                matched = child
                break
            end
        end
    end

    if not matched then
        return nil
    end

    -- Update backup fields (safe in combat since these are plain Lua fields, not secure attributes).
    for mappedUnit, mappedFrame in pairs(self._frameByDisplayedUnit) do
        if mappedFrame == matched and mappedUnit ~= unitToken then
            self._frameByDisplayedUnit[mappedUnit] = nil
        end
    end

    matched.unit = unitToken
    matched.displayedUnit = unitToken

    self._frameByDisplayedUnit[unitToken] = matched
    self._displayedUnitByGUID = self._displayedUnitByGUID or {}
    local unitGUID = getUnitGUIDSafe(unitToken)
    if unitGUID then
        setDisplayedUnitForGUID(self._displayedUnitByGUID, unitGUID, unitToken)
    end

    return matched
end

-- Refresh one currently-displayed party unit frame (full refresh).
-- Never forces secure frame visibility in combat; only updates existing visuals.
function PartyFrames:RefreshDisplayedUnit(unitToken, refreshOptions, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, true)
    end

    if not state.addonEnabled or state.partyConfig.enabled == false then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end

    local displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    if not displayedUnit and InCombatLockdown() then
        self:RebuildDisplayedUnitMap(true, state)
        displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    end
    if not displayedUnit and InCombatLockdown() then
        local ensuredFrame = self:EnsureMappedFrameForUnit(unitToken)
        if ensuredFrame then
            displayedUnit = unitToken
        end
    end
    if not displayedUnit then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end

    local frame = self._frameByDisplayedUnit and self._frameByDisplayedUnit[displayedUnit] or nil
    if not frame then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end

    self:RefreshMember(
        frame,
        getCurrentPartyFrameDisplayedUnit(frame) or displayedUnit,
        state.partyConfig,
        false,
        false,
        false,
        refreshOptions or MEMBER_REFRESH_FULL
    )
    return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, true)
end

-- Refresh one already-resolved party frame directly (hook-path parity with Danders addon).
-- Never forces secure frame visibility in combat; only updates existing visuals.
function PartyFrames:RefreshDisplayedMappedFrame(frame, unitToken, refreshOptions, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(frame) ~= "table" or type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, true)
    end

    if not state.addonEnabled or state.partyConfig.enabled == false then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end

    local displayedUnit = getCurrentPartyFrameDisplayedUnit(frame) or unitToken
    self:RefreshMember(
        frame,
        displayedUnit,
        state.partyConfig,
        false,
        false,
        false,
        refreshOptions or MEMBER_REFRESH_AURAS_ONLY
    )

    return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, true)
end

-- Refresh only the connection/range alpha for the currently displayed party frame.
function PartyFrames:RefreshDisplayedUnitRangeState(unitToken, inRangeState, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, true)
    end

    if not state.addonEnabled or state.partyConfig.enabled == false then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end

    local displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    if not displayedUnit and InCombatLockdown() then
        self:RebuildDisplayedUnitMap(true, state)
        displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    end
    if not displayedUnit and InCombatLockdown() then
        local ensuredFrame = self:EnsureMappedFrameForUnit(unitToken)
        if ensuredFrame then
            displayedUnit = unitToken
        end
    end
    if not displayedUnit then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end

    local frame = self._frameByDisplayedUnit and self._frameByDisplayedUnit[displayedUnit] or nil
    if not frame then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end

    return finishPerfCounters(
        self,
        "RefreshDisplayedUnitRangeState",
        perfStartedAt,
        self:RefreshDisplayedMappedFrameRangeState(frame, displayedUnit, inRangeState, state)
    )
end

-- Refresh only the connection/range alpha for a known mapped party frame.
function PartyFrames:RefreshDisplayedMappedFrameRangeState(frame, unitToken, inRangeState, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(frame) ~= "table" or type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, true)
    end

    if not state.addonEnabled or state.partyConfig.enabled == false then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end

    local displayedUnit = getCurrentPartyFrameDisplayedUnit(frame) or unitToken
    return finishPerfCounters(
        self,
        "RefreshDisplayedMappedFrameRangeState",
        perfStartedAt,
        refreshPartyMemberRangeState(self, frame, displayedUnit, false, false, inRangeState)
    )
end

-- Resolve a unit token to its currently-displayed party unit token.
-- Uses GUID->DisplayedUnit map first, then direct lookup, then GUID comparison,
-- finally UnitIsUnit() fallback for maximum reliability.
function PartyFrames:ResolveDisplayedUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    local frameByDisplayedUnit = self._frameByDisplayedUnit
    if type(frameByDisplayedUnit) ~= "table" then
        return nil
    end

    local displayedUnitByGUID = self._displayedUnitByGUID
    if type(displayedUnitByGUID) == "table" then
        local guid = getUnitGUIDSafe(unitToken)
        if guid then
            local mappedUnit = getDisplayedUnitForGUID(displayedUnitByGUID, guid)
            if type(mappedUnit) == "string" and frameByDisplayedUnit[mappedUnit] then
                return mappedUnit
            end
        end
    end

    local okDirect, directFrame = pcall(function()
        return frameByDisplayedUnit[unitToken]
    end)
    if okDirect and directFrame then
        return unitToken
    end

    local guid = getUnitGUIDSafe(unitToken)
    if guid then
        for displayedUnit, frame in pairs(frameByDisplayedUnit) do
            if frame then
                local displayedGUID = getUnitGUIDSafe(displayedUnit)
                if displayedGUID and displayedGUID == guid then
                    return displayedUnit
                end
            end
        end
    end

    if type(self.frames) == "table" then
        for i = 1, #self.frames do
            local frame = self.frames[i]
            if frame then
                local candidateUnit = frame.displayedUnit
                    or frame.unit
                candidateUnit = getCurrentPartyFrameDisplayedUnit(frame) or candidateUnit
                if type(candidateUnit) == "string" and candidateUnit ~= "" then
                    if guid and getUnitGUIDSafe(candidateUnit) == guid then
                        return candidateUnit
                    end
                    if type(UnitIsUnit) == "function" then
                        local okMatch, isSameUnit = pcall(UnitIsUnit, candidateUnit, unitToken)
                        if okMatch and isSameUnit then
                            return candidateUnit
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Refresh only vitals on currently shown party frames.
function PartyFrames:RefreshAllVitalsOnly(runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
    end
    if not state.addonEnabled or state.partyConfig.enabled == false then
        return finishPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
    end

    local frameByDisplayedUnit = self._frameByDisplayedUnit
    if type(frameByDisplayedUnit) ~= "table" then
        return finishPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
    end

    for displayedUnit, frame in pairs(frameByDisplayedUnit) do
        if frame then
            self:RefreshMember(
                frame,
                getCurrentPartyFrameDisplayedUnit(frame) or displayedUnit,
                state.partyConfig,
                false,
                false,
                false,
                MEMBER_REFRESH_VITALS_ONLY
            )
        end
    end
    recordPerfCounters(self, "RefreshAllVitalsOnly", perfStartedAt)
end

-- Refresh alpha-only range state for every currently displayed live party frame.
-- RangeHandle owns the actual range cache and simply asks party frames to
-- re-apply the latest alpha for each displayed unit.
function PartyFrames:RefreshAllDisplayedRangeStates(runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end
    if state.previewMode or not state.addonEnabled or state.partyConfig.enabled == false or getLivePartyUnitCount() == 0 then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    local frameByDisplayedUnit = self._frameByDisplayedUnit
    if type(frameByDisplayedUnit) ~= "table" then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    for displayedUnit, frame in pairs(frameByDisplayedUnit) do
        if frame and (type(frame.IsShown) ~= "function" or frame:IsShown()) then
            refreshPartyMemberRangeState(self, frame, getCurrentPartyFrameDisplayedUnit(frame) or displayedUnit, false, false)
        end
    end
    recordPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
end

-- Stop the periodic test mode ticker (updates fake data for preview).
function PartyFrames:StopTestTicker()
    local ticker = self._testTicker
    if ticker and type(ticker.Cancel) == "function" then
        ticker:Cancel()
    end
    self._testTicker = nil
end

-- Start periodic test mode ticker if not already running.
-- Ticker periodically refreshes frames to animate test data.
function PartyFrames:EnsureTestTicker()
    if self._testTicker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end

    self._testTicker = C_Timer.NewTicker(1.5, function()
        self:RefreshAll(false)
    end)
end

-- ============================================================================
-- FRAME STYLING & LAYOUT
-- ============================================================================

-- Apply frame styling: dimensions, borders, text insets, power bar height,
-- and optional role-icon spacing.
-- Deferred to combat-end if called during combat (pendingLayoutRefresh flag).
function PartyFrames:ApplyMemberStyle(frame, partyConfig, showPowerBar, showRoleIcon)
    if not frame or not partyConfig then
        return
    end

    if InCombatLockdown() then
        self.pendingLayoutRefresh = true
        return false
    end

    local width = Util:Clamp(tonumber(partyConfig.width) or 180, 80, 500)
    local height = Util:Clamp(tonumber(partyConfig.height) or 34, 16, 120)
    local powerHeight = Util:Clamp(tonumber(partyConfig.powerHeight) or 8, 4, height - 4)
    local fontSize = Util:Clamp(tonumber(partyConfig.fontSize) or 11, 8, 22)
    local pixelPerfect = Style:IsPixelPerfectEnabled()

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
        powerHeight = Style:Snap(powerHeight)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        powerHeight = math.floor(powerHeight + 0.5)
    end

    frame:SetSize(width, height)
    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(6) or 6
    local roleIconSize = math.max(8, math.floor((height * 0.285) + 0.5))
    if pixelPerfect then
        roleIconSize = Style:Snap(roleIconSize)
    end

    Style:ApplyStatusBarTexture(frame.HealthBar)
    Style:ApplyStatusBarTexture(frame.PowerBar)
    Style:ApplyStatusBarBacking(frame.HealthBar, "health")
    Style:ApplyStatusBarBacking(frame.PowerBar, "primaryPower")

    frame.HealthBar:ClearAllPoints()
    frame.PowerBar:ClearAllPoints()
    frame.PowerBar:SetHeight(powerHeight)

    if showPowerBar then
        frame.PowerBar:Show()
        frame.PowerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
        frame.PowerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)

        frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
        frame.HealthBar:SetPoint("BOTTOMLEFT", frame.PowerBar, "TOPLEFT", 0, border)
        frame.HealthBar:SetPoint("BOTTOMRIGHT", frame.PowerBar, "TOPRIGHT", 0, border)
    else
        frame.PowerBar:Hide()
        frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
        frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
        frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
    end

    if frame.RoleIcon then
        frame.RoleIcon:ClearAllPoints()
        frame.RoleIcon:SetPoint("CENTER", frame.HealthBar, "TOPLEFT", border, -border)
        frame.RoleIcon:SetSize(roleIconSize, roleIconSize)
        if not showRoleIcon then
            frame.RoleIcon:Hide()
        end
    end
    if frame.LeaderIcon then
        frame.LeaderIcon:ClearAllPoints()
        frame.LeaderIcon:SetPoint("CENTER", frame, "LEFT", border, 0)
        frame.LeaderIcon:SetSize(roleIconSize, roleIconSize)
    end
    if frame.ReadyCheckIndicator and self.globalFrames and type(self.globalFrames.LayoutReadyCheckIndicator) == "function" then
        self.globalFrames:LayoutReadyCheckIndicator(frame, height)
    end
    if self.globalFrames and type(self.globalFrames.LayoutGroupDispelIndicator) == "function" then
        self.globalFrames:LayoutGroupDispelIndicator(frame, height)
    elseif frame.DispelOverlay then
        frame.DispelOverlay:SetAllPoints(frame.HealthBar)
    end

    frame.NameText:ClearAllPoints()
    frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
    frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

    frame.HealthText:ClearAllPoints()
    frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")
    frame.NameText:SetTextColor(1, 1, 1, 1)
    frame.HealthText:SetTextColor(1, 1, 1, 1)
    if frame.DisconnectedIcon then
        local disconnectedIconSize = math.max(12, math.floor((height * 0.62) + 0.5))
        if pixelPerfect then
            disconnectedIconSize = Style:Snap(disconnectedIconSize)
        end
        frame.DisconnectedIcon:SetSize(disconnectedIconSize, disconnectedIconSize)
    end
    return true
end

-- Return the player's best-known role token even without a party assignment.
function PartyFrames:GetPlayerRoleToken()
    local assignedRole = normalizeRoleToken(
        type(UnitGroupRolesAssigned) == "function" and UnitGroupRolesAssigned("player") or nil
    )
    if assignedRole ~= "NONE" then
        return assignedRole
    end

    if type(GetSpecialization) == "function" and type(GetSpecializationRole) == "function" then
        local currentSpecIndex = GetSpecialization()
        if type(currentSpecIndex) == "number" then
            local specRole = normalizeRoleToken(GetSpecializationRole(currentSpecIndex))
            if specRole ~= "NONE" then
                return specRole
            end
        end
    end

    if self:ShouldShowPowerBar("player") then
        return "HEALER"
    end

    return "DAMAGER"
end

-- Determine if power bar should be shown for a party unit.
-- Shows for all Death Knights (runic power) and healer spec members (mana).
function PartyFrames:ShouldShowPowerBar(unitToken)
    local _, classToken = UnitClass(unitToken)
    if classToken == "DEATHKNIGHT" then
        return true
    end

    local healerSpecs = HEALER_SPEC_BY_CLASS[classToken or ""]
    if not healerSpecs then
        return false
    end

    if unitToken == "player" then
        local specID = getPlayerSpecializationID()
        return specID and healerSpecs[specID] == true or false
    end

    local assignedRole = type(UnitGroupRolesAssigned) == "function" and UnitGroupRolesAssigned(unitToken) or nil
    return assignedRole == "HEALER"
end

-- Return the role token that should be displayed on the frame.
function PartyFrames:GetDisplayRoleForUnit(unitToken, previewMode, testMode)
    if previewMode or testMode then
        return self:GetPreviewRoleForUnit(unitToken)
    end

    if unitToken == "player" then
        return self:GetPlayerRoleToken()
    end

    return normalizeRoleToken(
        type(UnitGroupRolesAssigned) == "function" and UnitGroupRolesAssigned(unitToken) or nil
    )
end

-- Get sort priority value for a given role (for ranking in frame layout).
function PartyFrames:GetRoleSortPriority(roleToken)
    local normalized = normalizeRoleToken(roleToken)
    return ROLE_SORT_PRIORITY[normalized] or ROLE_SORT_PRIORITY.NONE
end

-- Return a deterministic preview role for a unit token.
function PartyFrames:GetPreviewRoleForUnit(unitToken)
    if unitToken == "player" then
        return self:GetPlayerRoleToken()
    end

    return PREVIEW_ROLE_BY_UNIT[unitToken] or "NONE"
end

-- Return preview units in the same role bucket order as the live header.
function PartyFrames:BuildPreviewUnitsToShow(showPlayer)
    local unitsToShow = copyUnitList(showPlayer and TEST_UNITS_WITH_PLAYER or TEST_UNITS_NO_PLAYER)
    self:SortUnitsByRole(unitsToShow, function(unitToken)
        return self:GetPreviewRoleForUnit(unitToken)
    end)
    return unitsToShow
end

-- Sort a unit list in-place by role: tanks first, healers second, dps third,
-- others last. Optional roleResolver lets preview mode inject synthetic roles
-- while preserving original order within each role tier.
function PartyFrames:SortUnitsByRole(unitsToShow, roleResolver)
    if type(unitsToShow) ~= "table" or #unitsToShow <= 1 then
        return
    end

    local resolveRole = type(roleResolver) == "function" and roleResolver or nil
    local originalIndexByUnit = {}
    for index = 1, #unitsToShow do
        originalIndexByUnit[unitsToShow[index]] = index
    end

    table.sort(unitsToShow, function(a, b)
        local aRole = normalizeRoleToken(type(resolveRole) == "function" and resolveRole(a) or nil)
        local bRole = normalizeRoleToken(type(resolveRole) == "function" and resolveRole(b) or nil)
        local aPriority = self:GetRoleSortPriority(aRole)
        local bPriority = self:GetRoleSortPriority(bRole)
        if aPriority ~= bPriority then
            return aPriority < bPriority
        end
        return (originalIndexByUnit[a] or 999) < (originalIndexByUnit[b] or 999)
    end)
end

-- ============================================================================
-- MEMBER REFRESH (SINGLE UNIT)
-- ============================================================================

-- Refresh visual state of one party member frame: apply style, update vitals,
-- update role and status icons, and refresh aura visuals.
-- Supports preview mode (fake data), test mode (periodic animation), and real mode.
function PartyFrames:RefreshMember(frame, unitToken, partyConfig, previewMode, testMode, forceStyle, refreshOptions)
    local perfStartedAt = startPerfCounters(self)
    if not frame then
        return finishPerfCounters(self, "RefreshMember", perfStartedAt)
    end

    refreshOptions = refreshOptions or MEMBER_REFRESH_FULL
    local refreshVitals = refreshOptions.vitals == true
    local refreshAuras = refreshOptions.auras == true

    local showPowerBar = self:ShouldShowPowerBar(unitToken)
    local displayRole = self:GetDisplayRoleForUnit(unitToken, previewMode, testMode)
    local roleIconAtlas = partyConfig.showRoleIcon ~= false and resolveRoleIconAtlas(displayRole) or nil
    local showRoleIcon = roleIconAtlas ~= nil
    local showLeaderIcon = shouldShowLeaderIcon(unitToken, previewMode or testMode)
    local needsStyle = forceStyle == true
        or frame._mummuStyleApplied ~= true
        or frame._mummuShowPowerBar ~= showPowerBar
        or frame._mummuShowRoleIcon ~= showRoleIcon
    if needsStyle then
        local applied = self:ApplyMemberStyle(frame, partyConfig, showPowerBar, showRoleIcon)
        if applied then
            frame._mummuStyleApplied = true
            frame._mummuShowPowerBar = showPowerBar
            frame._mummuShowRoleIcon = showRoleIcon
        elseif frame._mummuStyleApplied ~= true then
            -- Style never applied (e.g. new frame created in combat lockdown).
            -- FontStrings have no font yet; skip refresh to avoid "Font not set" errors.
            -- pendingLayoutRefresh is set by ApplyMemberStyle so this will be retried post-combat.
            return finishPerfCounters(self, "RefreshMember", perfStartedAt)
        end
    end

    local exists = UnitExists(unitToken)
    local _, classToken = UnitClass(unitToken)
    local isConnected = true
    local isAFK = false
    local hasPendingSummon = false

    if not previewMode and not testMode and exists then
        if type(UnitIsConnected) == "function" then
            isConnected = Util:SafeBoolean(UnitIsConnected(unitToken), true)
        end
        if isConnected and type(UnitIsAFK) == "function" then
            isAFK = Util:SafeBoolean(UnitIsAFK(unitToken), false)
        end
        if isConnected then
            hasPendingSummon = hasIncomingSummonPending(unitToken)
        end
    end

    if not refreshVitals and not refreshAuras then
        return finishPerfCounters(self, "RefreshMember", perfStartedAt)
    end

    local name = TEST_NAME_BY_UNIT[unitToken] or unitToken
    local health = math.random(35, 100)
    local maxHealth = 100
    local power = math.random(20, 100)
    local maxPower = 100
    local powerForBar = power
    local maxPowerForBar = maxPower
    local powerTypeForBar = nil
    local powerTokenForBar = nil
    if showPowerBar then
        if classToken == "DEATHKNIGHT" then
            powerTypeForBar = POWER_TYPE_RUNIC
            powerTokenForBar = "RUNIC_POWER"
        else
            powerTypeForBar = POWER_TYPE_MANA
            powerTokenForBar = "MANA"
        end
    end
    local absorb = math.random(0, 35)
    local absorbForBar = absorb
    local absorbMaxForBar = maxHealth
    local testState = nil

    if refreshVitals and testMode then
        testState = self:GetOrCreateStaticTestMemberState(unitToken, showPowerBar)
        if testState then
            name = testState.name or name
            health = testState.health or health
            maxHealth = testState.maxHealth or maxHealth
            powerForBar = testState.power or powerForBar
            maxPowerForBar = testState.maxPower or maxPowerForBar
            power = powerForBar
            maxPower = maxPowerForBar
            absorbForBar = testState.absorb or absorbForBar
            absorbMaxForBar = testState.maxHealth or absorbMaxForBar
        end
    end

    if refreshVitals and not testMode and not previewMode and exists then
        name = UnitName(unitToken) or name
        health = UnitHealth(unitToken) or 0
        maxHealth = UnitHealthMax(unitToken) or 1
        if showPowerBar and powerTypeForBar ~= nil then
            powerForBar = UnitPower(unitToken, powerTypeForBar) or 0
            maxPowerForBar = UnitPowerMax(unitToken, powerTypeForBar) or 1
        else
            powerForBar = UnitPower(unitToken) or 0
            maxPowerForBar = UnitPowerMax(unitToken) or 1
        end
        power = powerForBar
        maxPower = maxPowerForBar
        absorbForBar = type(UnitGetTotalAbsorbs) == "function" and (UnitGetTotalAbsorbs(unitToken) or 0) or 0
        absorbMaxForBar = UnitHealthMax(unitToken) or maxHealth
    end

    if refreshVitals then
        local useLiveUnitValues = not testMode and not previewMode and exists
        local darkModeEnabled = Style:IsDarkModeEnabled()
        local barHealth = health
        local barMaxHealth = maxHealth
        local barPower = powerForBar
        local barMaxPower = maxPowerForBar

        if not useLiveUnitValues then
            maxHealth = getSafeNumericValue(maxHealth, 100) or 100
            if maxHealth <= 0 then
                maxHealth = 100
            end
            health = getSafeNumericValue(health, maxHealth) or maxHealth
            power = getSafeNumericValue(powerForBar, 0) or 0
            maxPower = getSafeNumericValue(maxPowerForBar, 100) or 100
            if maxPower <= 0 then
                maxPower = 100
            end
            health = Util:Clamp(health, 0, maxHealth)
            power = Util:Clamp(power, 0, maxPower)
            barHealth = health
            barMaxHealth = maxHealth
            barPower = power
            barMaxPower = maxPower
        else
            if barMaxHealth == nil then
                barMaxHealth = 1
            end
            if barHealth == nil then
                barHealth = 0
            end
            if barMaxPower == nil then
                barMaxPower = 1
            end
            if barPower == nil then
                barPower = 0
            end
        end

        absorb = getSafeNumericValue(absorbForBar, 0) or 0
        local barFillAlpha = 1

        local healthColor = { r = 0.2, g = 0.78, b = 0.3 }
        if not isConnected then
            healthColor = OFFLINE_HEALTH_COLOR
        elseif darkModeEnabled then
            healthColor = {
                r = Style.DARK_MODE_GRANITE_COLOR[1],
                g = Style.DARK_MODE_GRANITE_COLOR[2],
                b = Style.DARK_MODE_GRANITE_COLOR[3],
            }
            barFillAlpha = Style.DARK_MODE_GRANITE_COLOR[4]
        elseif exists and UnitIsPlayer(unitToken) then
            local classColor = classToken and RAID_CLASS_COLORS[classToken]
            if classColor then
                healthColor = { r = classColor.r, g = classColor.g, b = classColor.b }
            end
        end
        frame.HealthBar:SetStatusBarColor(healthColor.r, healthColor.g, healthColor.b, barFillAlpha)

        local powerColor = (powerTokenForBar and PowerBarColor[powerTokenForBar]) or PowerBarColor[powerTypeForBar] or { r = 0.2, g = 0.45, b = 0.85 }
        if not isConnected then
            powerColor = OFFLINE_POWER_COLOR
            barHealth = 0
            barMaxHealth = 1
            barPower = 0
            barMaxPower = 1
            absorbForBar = 0
            absorbMaxForBar = 1
        elseif darkModeEnabled then
            powerColor = {
                r = Style.DARK_MODE_GRANITE_COLOR[1],
                g = Style.DARK_MODE_GRANITE_COLOR[2],
                b = Style.DARK_MODE_GRANITE_COLOR[3],
            }
        end
        frame.PowerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b, barFillAlpha)

        setStatusBarValueSafe(frame.HealthBar, barHealth, barMaxHealth)
        if showPowerBar then
            setStatusBarValueSafe(frame.PowerBar, barPower, barMaxPower)
        end

        if frame.RoleIcon then
            if roleIconAtlas then
                frame.RoleIcon:SetAtlas(roleIconAtlas, false)
                frame.RoleIcon:Show()
            else
                frame.RoleIcon:Hide()
            end
        end
        if frame.LeaderIcon then
            if showLeaderIcon and type(frame.LeaderIcon.SetAtlas) == "function" then
                frame.LeaderIcon:SetAtlas(GROUP_LEADER_ICON_ATLAS, false)
                frame.LeaderIcon:Show()
            elseif showLeaderIcon then
                frame.LeaderIcon:SetTexture("Interface\\GROUPFRAME\\UI-Group-LeaderIcon")
                frame.LeaderIcon:Show()
            else
                frame.LeaderIcon:Hide()
            end
        end
        if self.globalFrames and type(self.globalFrames.RefreshReadyCheckIndicator) == "function" then
            self.globalFrames:RefreshReadyCheckIndicator(frame, unitToken, nil, previewMode or testMode)
        end

        frame.NameText:SetText(name)
        local healthPercent = 0
        if useLiveUnitValues and type(UnitHealthPercent) == "function" then
            local curve = (_G.CurveConstants and _G.CurveConstants.ScaleTo100) or nil
            local okPercent, rawPercent = pcall(UnitHealthPercent, unitToken, true, curve)
            if okPercent and type(rawPercent) == "number" then
                healthPercent = rawPercent
            end
        else
            local okHealthPercent, computedHealthPercent = pcall(computePercent, health, maxHealth)
            if okHealthPercent and type(computedHealthPercent) == "number" then
                healthPercent = computedHealthPercent
            end
        end
        if not isConnected then
            frame.HealthText:SetText("OFFLINE")
        elseif isAFK then
            frame.HealthText:SetText("AFK")
        else
            frame.HealthText:SetText(string.format("%.0f%%", healthPercent))
        end

        if not isConnected then
            frame.NameText:SetTextColor(0.72, 0.72, 0.72, 1)
            frame.HealthText:SetTextColor(0.72, 0.72, 0.72, 1)
        elseif isAFK then
            frame.NameText:SetTextColor(1, 1, 1, 1)
            frame.HealthText:SetTextColor(1, 0.82, 0.2, 1)
        else
            if darkModeEnabled then
                local nameR, nameG, nameB = Style:GetClassTextColor(classToken)
                if nameR and nameG and nameB then
                    frame.NameText:SetTextColor(nameR, nameG, nameB, 1)
                else
                    frame.NameText:SetTextColor(1, 1, 1, 1)
                end
            else
                frame.NameText:SetTextColor(1, 1, 1, 1)
            end
            frame.HealthText:SetTextColor(1, 1, 1, 1)
        end

        if frame.DisconnectedIcon then
            frame.DisconnectedIcon:SetShown(not previewMode and not testMode and exists and not isConnected)
        end
        if frame.SummonIcon then
            frame.SummonIcon:SetShown(not previewMode and not testMode and exists and isConnected and hasPendingSummon)
        end

        if frame.TargetHighlight then
            frame.TargetHighlight:SetShown(exists and UnitIsUnit(unitToken, "target"))
        end

        refreshPartyMemberRangeState(self, frame, unitToken, previewMode, testMode)

        local shouldShowAbsorb = false
        if previewMode then
            shouldShowAbsorb = absorb > 0
        elseif exists and isConnected then
            shouldShowAbsorb = true
        end

        if shouldShowAbsorb then
            setStatusBarValueSafe(frame.AbsorbOverlayBar, absorbForBar, absorbMaxForBar)
            frame.AbsorbOverlayFrame:Show()
            frame.AbsorbOverlayBar:Show()
        else
            frame.AbsorbOverlayBar:Hide()
            frame.AbsorbOverlayFrame:Hide()
        end
    end

    if refreshAuras and ns.AuraHandle and type(ns.AuraHandle.RefreshGroupAuras) == "function" then
        ns.AuraHandle:RefreshGroupAuras(frame, unitToken, exists == true, previewMode or testMode)
    end
    recordPerfCounters(self, "RefreshMember", perfStartedAt)
end

-- ============================================================================
-- FULL REFRESH (ALL FRAMES)
-- ============================================================================

-- Refresh all party frames and container layout.
-- Handles both real mode (header-managed frames) and preview/test mode (fake data).
--
-- Real mode (Layer 2 / Layer 3):
--   The SecureGroupHeaderTemplate header manages which children are shown and
--   what unit each child is assigned to — entirely via secure attributes.
--   We only push layout configuration into the header's attributes and call
--   RefreshMember on currently-assigned children to update their display.
--   No Show()/Hide() or SetAttribute("unit") calls on children in combat.
--
-- Preview / test mode:
--   The header is hidden; test frames are shown with static/animated fake data.
--   User can position and style without a real party present.
function PartyFrames:RefreshAll(forceLayout, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not self.dataHandle then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    self:CreatePartyFrames()
    if not self.container or not self.header then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    local state = runtimeState or buildPartyRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end
    local profile = state.profile
    local partyConfig = state.partyConfig
    local testMode = state.testMode
    local previewMode = state.previewMode
    local addonEnabled = state.addonEnabled
    local inCombat = InCombatLockdown()
    local shouldApplyLayout = (forceLayout == true) or (self.layoutInitialized ~= true)

    -- Layer 3: delegate Blizzard frame visibility to AuraHandle (alpha/scale only).
    self:ApplyBlizzardPartyFrameVisibility(state)

    -- Addon disabled: hide everything.
    if not previewMode and (not addonEnabled or partyConfig.enabled == false) then
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        ns.activeMummuPartyFrames = {}
        self:HideLeaderActionButtons()
        self:StopTestTicker()
        if inCombat then
            self.pendingLayoutRefresh = true
        else
            self.header:Hide()
            for i = 1, #self.testFrames do
                self.testFrames[i]:Hide()
            end
            self.container:Hide()
        end
        refreshIncomingCastBoard(self, state)
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    -- Read layout config.
    local showPlayer = partyConfig.showPlayer ~= false
    local showSelfWithoutGroup = partyConfig.showSelfWithoutGroup ~= false
    local inHomeGroup = isInGroupCategory(PARTY_CATEGORY_HOME)
    local inInstanceGroup = isInGroupCategory(PARTY_CATEGORY_INSTANCE)
    local inAnyGroup = inHomeGroup or inInstanceGroup
    local inHomeRaid = isInRaidCategory(PARTY_CATEGORY_HOME)
    local inInstanceRaid = isInRaidCategory(PARTY_CATEGORY_INSTANCE)
    local inAnyRaid = inHomeRaid or inInstanceRaid
    local livePartyMemberCount = getLivePartyUnitCount()
    local spacing = Util:Clamp(tonumber(partyConfig.spacing) or 2, 0, 80)
    local width = Util:Clamp(tonumber(partyConfig.width) or 180, 80, 500)
    local height = Util:Clamp(tonumber(partyConfig.height) or 34, 16, 120)
    local x = tonumber(partyConfig.x) or 0
    local y = tonumber(partyConfig.y) or 0
    local orientation = (partyConfig.orientation == "horizontal") and "horizontal" or "vertical"

    if Style:IsPixelPerfectEnabled() then
        spacing = Style:Snap(spacing)
        width   = Style:Snap(width)
        height  = Style:Snap(height)
        x       = Style:Snap(x)
        y       = Style:Snap(y)
    else
        spacing = math.floor(spacing + 0.5)
        width   = math.floor(width + 0.5)
        height  = math.floor(height + 0.5)
        x       = math.floor(x + 0.5)
        y       = math.floor(y + 0.5)
    end

    -- -----------------------------------------------------------------------
    -- Preview / test mode: header hidden, test frames shown with fake data.
    -- -----------------------------------------------------------------------
    if previewMode then
        self:StopTestTicker()
        self:HideLeaderActionButtons()
        -- Do not transition secure frame visibility/layout in combat.
        -- Defer preview/test presentation until PLAYER_REGEN_ENABLED.
        if inCombat then
            self.pendingLayoutRefresh = true
            return
        end
        self.header:Hide()

        local unitsToShow = self:BuildPreviewUnitsToShow(showPlayer)
        if testMode then
            self:EnsureStaticTestMemberStates(unitsToShow)
            self:EnsureTestTicker()
        else
            self._testMemberStateByUnit = nil
        end

        -- Build the test frame map and lay them out.
        local frameByDisplayedUnit = {}
        local displayedUnitByGUID = {}
        local totalWidth = orientation == "horizontal"
            and (width * #unitsToShow) + (spacing * math.max(0, #unitsToShow - 1))
            or width
        local totalHeight = orientation == "horizontal"
            and height
            or (height * #unitsToShow) + (spacing * math.max(0, #unitsToShow - 1))

        if shouldApplyLayout then
            self.container:SetSize(totalWidth, totalHeight)
            self.container:ClearAllPoints()
            self.container:SetPoint(
                partyConfig.point or "LEFT",
                UIParent,
                partyConfig.relativePoint or "LEFT",
                x, y
            )
        end

        for i = 1, MAX_PARTY_TEST_FRAMES do
            local frame = self.testFrames[i]
            local unitToken = unitsToShow[i]
            if frame and unitToken then
                frame.unit = unitToken
                frame.displayedUnit = unitToken
                frameByDisplayedUnit[unitToken] = frame
                local guid = getUnitGUIDSafe(unitToken)
                if guid then
                    setDisplayedUnitForGUID(displayedUnitByGUID, guid, unitToken)
                end
                if shouldApplyLayout then
                    frame:ClearAllPoints()
                    if i == 1 then
                        frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", 0, 0)
                    elseif orientation == "horizontal" then
                        frame:SetPoint("LEFT", self.testFrames[i - 1], "RIGHT", spacing, 0)
                    else
                        frame:SetPoint("TOP", self.testFrames[i - 1], "BOTTOM", 0, -spacing)
                    end
                end
                self:RefreshMember(frame, unitToken, partyConfig, true, testMode, shouldApplyLayout, MEMBER_REFRESH_FULL)
                if type(frame.EnableMouse) == "function" then
                    frame:EnableMouse(true)
                end
                frame:Show()
            elseif frame then
                frame:Hide()
            end
        end
        -- Hide any header children that might still be visible.
        self.frames = self.testFrames
        self._frameByDisplayedUnit = frameByDisplayedUnit
        self._displayedUnitByGUID = displayedUnitByGUID
        self.container:Show()
        self:RefreshLeaderActionButtons(state, height, inAnyGroup, inAnyRaid)
        if shouldApplyLayout then
            self.layoutInitialized = true
        end
        refreshIncomingCastBoard(self, state)
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    -- Raid mode: the raid module owns group presentation, so the live party
    -- container should disappear entirely instead of leaving an empty shell.
    if inAnyRaid then
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        self.frames = {}
        ns.activeMummuPartyFrames = {}
        self:HideLeaderActionButtons()
        self:StopTestTicker()
        self._testMemberStateByUnit = nil

        if ns.AuraHandle and type(ns.AuraHandle.RebuildSharedUnitFrameMap) == "function" then
            ns.AuraHandle:RebuildSharedUnitFrameMap(inCombat, inCombat and "party_hidden_in_raid_combat" or "party_hidden_in_raid")
        end

        if inCombat then
            self.pendingLayoutRefresh = true
        else
            self.header:Hide()
            for i = 1, #self.testFrames do
                self.testFrames[i]:Hide()
            end
            self.container:Hide()
        end

        refreshIncomingCastBoard(self, state)
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    -- -----------------------------------------------------------------------
    -- Real mode: SecureGroupHeaderTemplate owns unit attribution and
    -- show/hide of children. We configure the header's layout attributes and
    -- call RefreshMember on whatever children it currently has assigned.
    -- -----------------------------------------------------------------------
    self:StopTestTicker()
    self._testMemberStateByUnit = nil

    -- Hide all test frames — only the header's children are active here.
    if not inCombat then
        for i = 1, #self.testFrames do
            self.testFrames[i]:Hide()
        end
    end

    -- Push layout and roster-config into the header's secure attributes.
    -- These updates are safe to call at any time (plain frame attributes on our own frame).
    if shouldApplyLayout and not inCombat then
        self:ApplyHeaderConfiguration(
            orientation,
            spacing,
            width,
            height,
            showPlayer,
            showSelfWithoutGroup
        )

        -- Determine container size from live party count (up to MAX_PARTY_TEST_FRAMES).
        local liveCount = livePartyMemberCount
        if showPlayer then
            if not inAnyRaid and (liveCount > 0 or showSelfWithoutGroup) then
                liveCount = liveCount + 1
            end
        end
        liveCount = math.max(liveCount, 1)
        local totalWidth = orientation == "horizontal"
            and (width * liveCount) + (spacing * math.max(0, liveCount - 1))
            or width
        local totalHeight = orientation == "horizontal"
            and height
            or (height * liveCount) + (spacing * math.max(0, liveCount - 1))

        self.container:SetSize(totalWidth, totalHeight)
        self.container:ClearAllPoints()
        self.container:SetPoint(
            partyConfig.point or "LEFT",
            UIParent,
            partyConfig.relativePoint or "LEFT",
            x, y
        )
    end

    -- Collect header children and refresh their display.
    -- Unit attribution is already done by the header's restricted attribute code;
    -- we read the backup .displayedUnit / .unit fields (plain Lua, safe in combat).
    local children = { self.header:GetChildren() }
    local frameByDisplayedUnit = {}
    local displayedUnitByGUID = {}
    local activeFrames = {}

    for i = 1, #children do
        local child = children[i]
        if child and not child._mummuVisualsBuilt then
            -- Lazily attach visual sub-frames the first time each child is seen.
            -- BuildFrameVisuals is idempotent and also calls RegisterForClicks in
            -- normal Lua (it cannot be called from initialConfigFunction's restricted env).
            -- During combat we defer this work to avoid mutating secure child scripts/clicks.
            if inCombat then
                self.pendingLayoutRefresh = true
            else
                self:BuildFrameVisuals(child)
            end
        end
        if child and child._mummuVisualsBuilt then
            -- Read the unit the header has assigned to this child.
            local unitToken = getCurrentPartyFrameDisplayedUnit(child)

            if unitToken then
                local isShown = type(child.IsShown) == "function" and child:IsShown() or false
                if isShown or inCombat then
                    frameByDisplayedUnit[unitToken] = child
                    local guid = getUnitGUIDSafe(unitToken)
                    if guid then
                        setDisplayedUnitForGUID(displayedUnitByGUID, guid, unitToken)
                    end
                    activeFrames[#activeFrames + 1] = child
                    self:RefreshMember(
                        child, unitToken, partyConfig,
                        false, false, shouldApplyLayout,
                        MEMBER_REFRESH_FULL
                    )
                end
            end
        end
    end

    -- Solo player fallback: SecureGroupHeaderTemplate only iterates actual group members,
    -- so it never creates child buttons when the player is solo (showSolo only controls
    -- header visibility, not child creation). Explicitly show testFrames[MAX_PARTY_TEST_FRAMES]
    -- (unit = "player") with real data when not in any group.
    --
    -- Follower-dungeon edge case:
    -- some instance-category groups can report grouped state while exposing zero
    -- party1-party4 units to the secure header for a short period. In that case,
    -- keep player visible instead of rendering nothing.
    -- Visibility/position updates are deferred if combat is active.
    local shouldUseSoloFallback = false
    if showSelfWithoutGroup and not frameByDisplayedUnit["player"] then
        if not inAnyGroup then
            shouldUseSoloFallback = true
        elseif inInstanceGroup and not inAnyRaid and livePartyMemberCount == 0 then
            shouldUseSoloFallback = true
        end
    end
    if shouldUseSoloFallback then
        local soloFrame = self.testFrames and self.testFrames[MAX_PARTY_TEST_FRAMES]
        if soloFrame then
            soloFrame.unit = "player"
            soloFrame.displayedUnit = "player"
            frameByDisplayedUnit["player"] = soloFrame
            local guid = getUnitGUIDSafe("player")
            if guid then
                setDisplayedUnitForGUID(displayedUnitByGUID, guid, "player")
            end
            activeFrames[#activeFrames + 1] = soloFrame
            if shouldApplyLayout and not inCombat then
                soloFrame:ClearAllPoints()
                soloFrame:SetPoint("TOPLEFT", self.container, "TOPLEFT", 0, 0)
                soloFrame:SetSize(width, height)
            end
            self:RefreshMember(soloFrame, "player", partyConfig, false, false, shouldApplyLayout, MEMBER_REFRESH_FULL)
            if not inCombat and type(soloFrame.EnableMouse) == "function" then
                soloFrame:EnableMouse(true)
            end
            if not inCombat then
                soloFrame:Show()
            else
                self.pendingLayoutRefresh = true
            end
        end
    end

    self.frames = activeFrames
    self._frameByDisplayedUnit = frameByDisplayedUnit
    self._displayedUnitByGUID = displayedUnitByGUID

    -- Publish active frame list so AuraHandle can find all mummu frames,
    -- including the solo player frame. Then rebuild the shared unit map
    -- immediately so UNIT_AURA dispatches hit the fast path from the start.
    ns.activeMummuPartyFrames = activeFrames
    if ns.AuraHandle and type(ns.AuraHandle.RebuildSharedUnitFrameMap) == "function" then
        -- In combat include hidden stand-by frames so UNIT_AURA dispatch can
        -- still resolve units during secure-header roster transitions.
        ns.AuraHandle:RebuildSharedUnitFrameMap(inCombat, inCombat and "party_refresh_combat" or "party_refresh")
    end

    if not inCombat then
        self.header:Show()
        self.container:Show()
        self:RefreshLeaderActionButtons(state, height, inAnyGroup, inAnyRaid)
        if shouldApplyLayout then
            self.layoutInitialized = true
        end
    else
        self:RefreshLeaderActionButtons(state, height, inAnyGroup, inAnyRaid)
        self.pendingLayoutRefresh = true
    end
    refreshIncomingCastBoard(self, state)
    recordPerfCounters(self, "RefreshAll", perfStartedAt)
end

-- Enable or disable lightweight runtime profiling counters for party hot paths.
function PartyFrames:SetPerfCountersEnabled(enabled, resetExisting)
    self._perfCountersEnabled = enabled == true
    if resetExisting ~= false then
        self._perfCounters = {}
    end
end

-- Return a snapshot of the current profiling counters.
function PartyFrames:GetPerfCounters()
    return copyPerfCounters(self._perfCounters)
end

-- Clear recorded profiling counters.
function PartyFrames:ResetPerfCounters()
    self._perfCounters = {}
end

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

-- Register the PartyFrames module with the addon framework.
addon:RegisterModule("partyFrames", PartyFrames:New())
