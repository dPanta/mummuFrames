-- ============================================================================
-- MUMMUFRAMES RAID FRAMES MODULE
-- ============================================================================
-- Owns custom raid member frames for live raids and preview/test layouts.
-- Live mode uses one fixed SecureUnitButtonTemplate per raid token (raid1-raid40)
-- so unit assignment is deterministic and does not depend on secure-header child
-- creation timing. Preview mode keeps a separate synthetic frame pool.

local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util
local L = ns.L

local RaidFrames = ns.Object:Extend()

local MAX_RAID_GROUPS = 8
local MAX_RAID_GROUP_SIZE = 5
local MAX_RAID_TEST_FRAMES = 40
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local OUT_OF_RANGE_ALPHA = 0.55
local OFFLINE_FRAME_ALPHA = 0.7
local OFFLINE_HEALTH_COLOR = { r = 0.38, g = 0.38, b = 0.38 }
local GROUP_LEADER_ICON_ATLAS = "UI-HUD-UnitFrame-Player-Group-LeaderIcon"
local RAID_FRAME_STRATA = "MEDIUM"
local ROLE_GROUPING_ORDER_ASC = "TANK,HEALER,DAMAGER,NONE"
local ROLE_GROUPING_ORDER_DESC = "NONE,DAMAGER,HEALER,TANK"
local TEST_ROLE_BY_SLOT = {
    "TANK",
    "HEALER",
    "DAMAGER",
    "DAMAGER",
    "DAMAGER",
}
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
local PARTY_CATEGORY_HOME = (_G.Enum and _G.Enum.PartyCategory and _G.Enum.PartyCategory.Home) or 1
local PARTY_CATEGORY_INSTANCE = (_G.Enum and _G.Enum.PartyCategory and _G.Enum.PartyCategory.Instance) or 2

-- Show a tooltip for the unit currently assigned to the raid frame.
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

-- Hide the tooltip opened by showUnitTooltip.
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

-- Coerce a numeric-like value without letting protected payloads escape.
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

-- Convert a value/max pair into a percentage.
local function computePercent(value, maxValue)
    if type(maxValue) ~= "number" or maxValue <= 0 then
        return 0
    end
    return (value / maxValue) * 100
end

-- Return whether a value is one of WoW's protected secret-number payloads.
local function isSecretNumericValue(value)
    if type(value) ~= "number" or type(issecretvalue) ~= "function" then
        return false
    end

    local okSecret, isSecret = pcall(issecretvalue, value)
    return okSecret and isSecret == true
end

-- Apply a clamped value/range pair to a status bar safely.
local function setStatusBarValueSafe(statusBar, currentValue, maxValue)
    if not statusBar then
        return
    end

    local maxIsSecret = isSecretNumericValue(maxValue)
    local currentIsSecret = isSecretNumericValue(currentValue)

    local resolvedMax = maxValue
    if not maxIsSecret then
        resolvedMax = getSafeNumericValue(maxValue, 1) or 1
        if resolvedMax <= 0 then
            resolvedMax = 1
        end
    end

    local resolvedCurrent = currentValue
    if not currentIsSecret then
        resolvedCurrent = getSafeNumericValue(currentValue, 0) or 0
        if resolvedCurrent < 0 then
            resolvedCurrent = 0
        elseif not maxIsSecret and resolvedCurrent > resolvedMax then
            resolvedCurrent = resolvedMax
        end
    end

    local okRange = pcall(statusBar.SetMinMaxValues, statusBar, 0, resolvedMax)
    if not okRange then
        statusBar:SetMinMaxValues(0, 1)
    end

    local okValue = pcall(statusBar.SetValue, statusBar, resolvedCurrent)
    if not okValue then
        statusBar:SetValue(0)
    end
end

local function hideRaidAbsorbOverlay(frame)
    if not frame then
        return
    end
    if frame.AbsorbOverlayBar then
        frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
        frame.AbsorbOverlayBar:SetValue(0)
        frame.AbsorbOverlayBar:Hide()
    end
    if frame.AbsorbOverlayFrame then
        frame.AbsorbOverlayFrame:Hide()
    end
end

local function refreshRaidAbsorbOverlay(frame, healthValue, maxHealthValue, absorbValue)
    if not frame or not frame.HealthBar or not frame.AbsorbOverlayFrame or not frame.AbsorbOverlayBar then
        return hideRaidAbsorbOverlay(frame)
    end

    local maxHealth = getSafeNumericValue(maxHealthValue, 0) or 0
    if maxHealth <= 0 then
        return hideRaidAbsorbOverlay(frame)
    end

    local health = Util:Clamp(getSafeNumericValue(healthValue, 0) or 0, 0, maxHealth)
    local absorb = math.max(0, getSafeNumericValue(absorbValue, 0) or 0)
    local missingHealth = math.max(0, maxHealth - health)
    local visibleAbsorb = math.min(absorb, missingHealth)
    if visibleAbsorb <= 0 then
        return hideRaidAbsorbOverlay(frame)
    end

    local healthBarWidth = tonumber(frame.HealthBar:GetWidth()) or 0
    if healthBarWidth <= 0 then
        return hideRaidAbsorbOverlay(frame)
    end

    local healthOffset = healthBarWidth * (health / maxHealth)
    local absorbWidth = healthBarWidth * (visibleAbsorb / maxHealth)
    if Style:IsPixelPerfectEnabled() then
        local pixelSize = Style:GetPixelSize() or 1
        healthOffset = Style:Snap(healthOffset)
        absorbWidth = math.max(pixelSize, Style:Snap(absorbWidth))
    else
        healthOffset = math.floor(healthOffset + 0.5)
        absorbWidth = math.max(1, math.floor(absorbWidth + 0.5))
    end
    absorbWidth = math.min(absorbWidth, math.max(0, healthBarWidth - healthOffset))
    if absorbWidth <= 0 then
        return hideRaidAbsorbOverlay(frame)
    end

    frame.AbsorbOverlayFrame:ClearAllPoints()
    frame.AbsorbOverlayFrame:SetPoint("TOPLEFT", frame.HealthBar, "TOPLEFT", healthOffset, 0)
    frame.AbsorbOverlayFrame:SetPoint("BOTTOMLEFT", frame.HealthBar, "BOTTOMLEFT", healthOffset, 0)
    frame.AbsorbOverlayFrame:SetWidth(absorbWidth)

    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(1)
    frame.AbsorbOverlayFrame:Show()
    frame.AbsorbOverlayBar:Show()
end

-- Return a unit GUID without propagating UnitGUID failures.
local function getUnitGUIDSafe(unitToken)
    if Util and type(Util.GetUnitGUIDSafe) == "function" then
        return Util:GetUnitGUIDSafe(unitToken)
    end

    return nil
end

-- Accept only raid unit tokens this module can display.
local function normalizeRaidDisplayedUnit(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if string.match(unitToken, "^raid%d+$") then
        return unitToken
    end
    return nil
end

-- Read the secure unit currently assigned to a raid frame.
-- Prefer the live secure attribute because header children may be recycled or
-- reordered while their plain Lua backup fields still hold an older unit token.
local function getCurrentRaidFrameDisplayedUnit(frame)
    if type(frame) ~= "table" then
        return nil
    end

    if type(frame.GetAttribute) == "function" then
        local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if okAttr then
            local normalizedAttrUnit = normalizeRaidDisplayedUnit(attrUnit)
            if normalizedAttrUnit then
                frame.unit = normalizedAttrUnit
                frame.displayedUnit = normalizedAttrUnit
                return normalizedAttrUnit
            end
            return nil
        end
    end

    local cachedUnit = normalizeRaidDisplayedUnit(frame.displayedUnit or frame.unit)
    if cachedUnit then
        frame.unit = cachedUnit
        frame.displayedUnit = cachedUnit
        return cachedUnit
    end

    return nil
end

local function shouldShowLeaderIcon(unitToken, previewMode)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end

    if previewMode then
        return unitToken == "raid1"
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

-- Return the displayed raid unit mapped to a GUID.
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

-- Record which raid unit token a GUID is currently displayed as.
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

-- Return whether the player is in a raid for the requested category.
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

local function resolveRaidMemberFrameAlpha(unitToken, exists, isConnected, previewMode, inRangeState)
    if previewMode or not exists then
        return 1
    end

    if not isConnected then
        return OFFLINE_FRAME_ALPHA
    end

    if Util:IsGroupUnitOutOfRange(unitToken, inRangeState) then
        return OUT_OF_RANGE_ALPHA
    end

    return 1
end

local function refreshRaidMemberRangeState(frame, unitToken, previewMode, inRangeState)
    if not frame then
        return false
    end

    local exists = not previewMode and UnitExists(unitToken)
    local isConnected = true
    if exists and type(UnitIsConnected) == "function" then
        isConnected = Util:SafeBoolean(UnitIsConnected(unitToken), true)
    end

    frame:SetAlpha(resolveRaidMemberFrameAlpha(unitToken, exists, isConnected, previewMode, inRangeState))
    return true
end

-- Count members per raid subgroup and return the active subgroup order.
local function getRaidGroupCounts()
    local counts = {}
    local activeGroups = {}

    for index = 1, MAX_RAID_TEST_FRAMES do
        local unitToken = "raid" .. tostring(index)
        if UnitExists(unitToken) then
            local subgroup = nil
            if type(GetRaidRosterInfo) == "function" then
                local _, _, groupValue = GetRaidRosterInfo(index)
                subgroup = getSafeNumericValue(groupValue, nil)
            end
            subgroup = Util:Clamp(subgroup or math.ceil(index / MAX_RAID_GROUP_SIZE), 1, MAX_RAID_GROUPS)
            counts[subgroup] = (counts[subgroup] or 0) + 1
            activeGroups[subgroup] = true
        end
    end

    local orderedGroups = {}
    for groupIndex = 1, MAX_RAID_GROUPS do
        if activeGroups[groupIndex] then
            orderedGroups[#orderedGroups + 1] = groupIndex
        end
    end

    return counts, orderedGroups
end

-- Build preview entries for test/edit mode raid layouts.
local function getPreviewEntries(count)
    local entries = {}
    local total = Util:Clamp(math.floor((tonumber(count) or 20) + 0.5), 1, MAX_RAID_TEST_FRAMES)

    for index = 1, total do
        local groupIndex = math.ceil(index / MAX_RAID_GROUP_SIZE)
        local slotIndex = ((index - 1) % MAX_RAID_GROUP_SIZE) + 1
        entries[#entries + 1] = {
            unitToken = "raid" .. tostring(index),
            groupIndex = groupIndex,
            slotIndex = slotIndex,
            role = TEST_ROLE_BY_SLOT[slotIndex] or "DAMAGER",
            name = string.format("Raid %02d", index),
            originalIndex = index,
        }
    end

    return entries
end

-- Sort preview entries within each raid group using the current config.
local function sortEntriesWithinGroups(entries, sortBy, sortDirection)
    local sortMode = (sortBy == "name" or sortBy == "role") and sortBy or "group"
    local descending = sortDirection == "desc"
    local rolePriority = {
        TANK = 1,
        HEALER = 2,
        DAMAGER = 3,
        NONE = 4,
    }

    local grouped = {}
    local orderedGroups = {}
    for i = 1, #entries do
        local entry = entries[i]
        local groupIndex = entry.groupIndex
        if not grouped[groupIndex] then
            grouped[groupIndex] = {}
            orderedGroups[#orderedGroups + 1] = groupIndex
        end
        grouped[groupIndex][#grouped[groupIndex] + 1] = entry
    end

    if sortMode == "group" and descending then
        table.sort(orderedGroups, function(left, right)
            return left > right
        end)
    end

    local sorted = {}
    for groupOrder = 1, #orderedGroups do
        local groupIndex = orderedGroups[groupOrder]
        local groupEntries = grouped[groupIndex]
        if sortMode == "name" then
            table.sort(groupEntries, function(left, right)
                if descending then
                    return string.lower(left.name) > string.lower(right.name)
                end
                return string.lower(left.name) < string.lower(right.name)
            end)
        elseif sortMode == "role" then
            table.sort(groupEntries, function(left, right)
                local leftPriority = rolePriority[left.role] or rolePriority.NONE
                local rightPriority = rolePriority[right.role] or rolePriority.NONE
                if leftPriority ~= rightPriority then
                    if descending then
                        return leftPriority > rightPriority
                    end
                    return leftPriority < rightPriority
                end
                if descending then
                    return left.originalIndex > right.originalIndex
                end
                return left.originalIndex < right.originalIndex
            end)
        end

        for slotIndex = 1, #groupEntries do
            groupEntries[slotIndex].slotIndex = slotIndex
            sorted[#sorted + 1] = groupEntries[slotIndex]
        end
    end

    return sorted, orderedGroups
end

-- Reverse group order when the live layout sorts groups descending.
local function getLiveGroupOrder(groupIndices, sortBy, sortDirection)
    if sortBy ~= "group" or sortDirection ~= "desc" then
        return groupIndices
    end

    local reversed = {}
    for index = #groupIndices, 1, -1 do
        reversed[#reversed + 1] = groupIndices[index]
    end
    return reversed
end

-- Compute the size needed for one subgroup container.
local function getGroupContainerSize(memberCount, width, height, spacingX, spacingY, groupLayout)
    local count = math.max(1, memberCount or 1)
    if groupLayout == "horizontal" then
        return (width * count) + (spacingX * math.max(0, count - 1)), height
    end
    return width, (height * count) + (spacingY * math.max(0, count - 1))
end

-- Prefer the unit's live name, falling back to its token.
local function getLiveDisplayName(unitToken)
    local name = UnitName(unitToken)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return unitToken
end

local function getRaidFrameIndexFromUnitToken(unitToken)
    local numericIndex = tonumber(string.match(unitToken or "", "^raid(%d+)$"))
    if type(numericIndex) ~= "number" then
        return nil
    end
    numericIndex = math.floor(numericIndex + 0.5)
    if numericIndex < 1 or numericIndex > MAX_RAID_TEST_FRAMES then
        return nil
    end
    return numericIndex
end

local function getRaidSubgroupForUnit(unitToken, fallbackIndex)
    local subgroup = nil

    if type(GetRaidRosterInfo) == "function" and type(fallbackIndex) == "number" then
        local _, _, groupValue = GetRaidRosterInfo(fallbackIndex)
        subgroup = getSafeNumericValue(groupValue, nil)
    end

    if type(subgroup) ~= "number" and type(UnitInRaid) == "function" and type(GetRaidRosterInfo) == "function" then
        local okRosterIndex, rosterIndex = pcall(UnitInRaid, unitToken)
        if okRosterIndex and type(rosterIndex) == "number" then
            local _, _, groupValue = GetRaidRosterInfo(rosterIndex)
            subgroup = getSafeNumericValue(groupValue, nil)
        end
    end

    return Util:Clamp(subgroup or math.ceil((fallbackIndex or 1) / MAX_RAID_GROUP_SIZE), 1, MAX_RAID_GROUPS)
end

local function buildLiveRaidEntries(sortBy, sortDirection)
    local entries = {}

    for index = 1, MAX_RAID_TEST_FRAMES do
        local unitToken = "raid" .. tostring(index)
        if UnitExists(unitToken) then
            entries[#entries + 1] = {
                unitToken = unitToken,
                groupIndex = getRaidSubgroupForUnit(unitToken, index),
                slotIndex = 0,
                role = type(UnitGroupRolesAssigned) == "function" and UnitGroupRolesAssigned(unitToken) or "NONE",
                name = getLiveDisplayName(unitToken),
                originalIndex = index,
            }
        end
    end

    if #entries == 0 then
        return {}, {}, {}
    end

    local sortedEntries, orderedGroups = sortEntriesWithinGroups(entries, sortBy, sortDirection)
    local groupCounts = {}
    for entryIndex = 1, #sortedEntries do
        local entry = sortedEntries[entryIndex]
        groupCounts[entry.groupIndex] = math.max(groupCounts[entry.groupIndex] or 0, entry.slotIndex or 0)
    end

    return sortedEntries, orderedGroups, groupCounts
end

local function hasLiveRaidUnits()
    for index = 1, MAX_RAID_TEST_FRAMES do
        if UnitExists("raid" .. tostring(index)) then
            return true
        end
    end
    return false
end

-- Initialize raid-frame module state and cached maps.
function RaidFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    self.unitFrames = nil
    self.container = nil
    self.liveFrames = {}
    self.groupContainers = {}
    self.headers = {}
    self.testFrames = {}
    self.frames = {}
    self._rangeTicker = nil
    self.editModeActive = false
    self.editModeCallbacksRegistered = false
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    self._perfCountersEnabled = false
    self._perfCounters = {}
end

-- Store addon references needed by the module.
function RaidFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Create UI, register events, and perform the first full refresh.
function RaidFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")
    self.unitFrames = self.addon:GetModule("unitFrames")
    self:CreateRaidFrames()
    self:RegisterEvents()
    self:RegisterEditModeCallbacks()
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame.editModeActive == true) and true or false
    if self.editModeActive then
        self:EnsureEditModeSelection()
        if self.container and self.container.EditModeSelection then
            self.container.EditModeSelection:Show()
        end
    end
    self:ApplyBlizzardRaidFrameVisibility()
    self:RefreshAll(true)
end

-- Tear down runtime state and restore Blizzard visibility.
function RaidFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:UnregisterEditModeCallbacks()
    self.editModeActive = false
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self:StopRangeTicker()
    self.frames = {}
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    ns.activeMummuRaidFrames = {}
    self:SetBlizzardRaidFramesHidden(false)
    self:HideAll()
end

-- Register world, roster, and combat events that affect raid frames.
function RaidFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_DISABLED", self.OnCombatStarted)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PARTY_LEADER_CHANGED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_SPECIALIZATION_CHANGED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_TALENT_UPDATE", self.OnWorldEvent)
end

-- Subscribe to Edit Mode enter/exit callbacks once.
function RaidFrames:RegisterEditModeCallbacks()
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

-- Remove Edit Mode callbacks when the module disables.
function RaidFrames:UnregisterEditModeCallbacks()
    if not self.editModeCallbacksRegistered then
        return
    end
    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end
    self.editModeCallbacksRegistered = false
end

-- Ensure the raid container has an Edit Mode selection overlay.
function RaidFrames:EnsureEditModeSelection()
    if not self.container or not self.unitFrames then
        return
    end

    if type(self.unitFrames.EnsureEditModeSelection) == "function" then
        self.unitFrames:EnsureEditModeSelection(self.container)
    end

    local selection = self.container.EditModeSelection
    if selection and selection.Label and selection.Label.SetText then
        selection.Label:SetText((L and L.CONFIG_TAB_RAID) or "Raid")
    end
end

-- Show edit-mode affordances and switch to preview presentation.
function RaidFrames:OnEditModeEnter()
    self.editModeActive = true
    self:EnsureEditModeSelection()
    if self.container and self.container.EditModeSelection then
        self.container.EditModeSelection:Show()
    end
    self:RefreshAll(true)
end

-- Hide edit-mode affordances and return to live presentation.
function RaidFrames:OnEditModeExit()
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

-- Refresh layout or defer it when roster/world changes occur in combat.
function RaidFrames:OnWorldEvent()
    if InCombatLockdown() then
        self.pendingLayoutRefresh = true
        self:RebuildDisplayedUnitMap(true)
        return
    end
    self:RefreshAll(true)
    self:RebuildDisplayedUnitMap(false)
end

-- Freeze layout churn while combat lockdown is active.
function RaidFrames:OnCombatStarted()
    self:RefreshAll(false)
    self:RebuildDisplayedUnitMap(true)
    self.pendingLayoutRefresh = true
end

-- Apply any deferred raid layout work after combat ends.
function RaidFrames:OnCombatEnded()
    if self.pendingLayoutRefresh then
        self.pendingLayoutRefresh = false
        self:RefreshAll(true)
        return
    end
    self:RefreshAll(false)
end

-- Delegate Blizzard raid-frame suppression to AuraHandle.
function RaidFrames:SetBlizzardRaidFramesHidden(shouldHide)
    if ns.AuraHandle then
        ns.AuraHandle:SetBlizzardFramesHidden("raid", shouldHide, "raidFrames")
    end
end

-- Apply the current config setting for Blizzard raid-frame visibility.
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

local function buildRaidRuntimeState(self, profileOverride, raidConfigOverride)
    if not self or not self.dataHandle then
        return nil
    end

    local profile = profileOverride or self.dataHandle:GetProfile()
    local raidConfig = raidConfigOverride or self.dataHandle:GetUnitConfig("raid") or {}
    local testMode = profile and profile.testMode == true
    local previewMode = testMode or self.editModeActive

    return {
        profile = profile,
        raidConfig = raidConfig,
        testMode = testMode,
        previewMode = previewMode,
        addonEnabled = profile and profile.enabled ~= false,
    }
end

function RaidFrames:ApplyBlizzardRaidFrameVisibility(runtimeState)
    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return
    end
    local shouldHide = state.addonEnabled and state.raidConfig and state.raidConfig.hideBlizzardFrame == true
    self:SetBlizzardRaidFramesHidden(shouldHide)
end

-- Return the shared healer-aura config used by raid indicators.
-- Create the raid container, fixed live raid frames, and preview frames.
function RaidFrames:CreateRaidFrames()
    if self.container then
        return self.container
    end
    if not self.globalFrames then
        return nil
    end

    local container = CreateFrame("Frame", "mummuFramesRaidContainer", UIParent)
    container:SetFrameStrata(RAID_FRAME_STRATA)
    container.unitToken = "raid"
    container:Hide()
    self.container = container

    for groupIndex = 1, MAX_RAID_GROUPS do
        local groupContainer = CreateFrame("Frame", "mummuFramesRaidGroupContainer" .. tostring(groupIndex), container)
        groupContainer:SetFrameStrata("LOW")
        groupContainer:Hide()
        self.groupContainers[groupIndex] = groupContainer

        local header = CreateFrame(
            "Frame",
            "mummuFramesRaidHeader" .. tostring(groupIndex),
            groupContainer,
            "SecureGroupHeaderTemplate"
        )
        header:SetFrameStrata("LOW")
        header:SetAllPoints(groupContainer)
        header:SetAttribute("showParty", false)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showPlayer", false)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("groupFilter", tostring(groupIndex))
        header:SetAttribute("template", "SecureUnitButtonTemplate")
        header:SetAttribute("maxDisplayed", MAX_RAID_GROUP_SIZE)
        header:SetAttribute("initialConfigFunction", [[
            self:SetAttribute("type1", "target")
            self:SetAttribute("*type2", "togglemenu")
        ]])
        self.headers[groupIndex] = header
    end

    for index = 1, MAX_RAID_TEST_FRAMES do
        local unitToken = "raid" .. tostring(index)
        local liveFrame = CreateFrame(
            "Button",
            "mummuFramesRaidFrame" .. tostring(index),
            container,
            "SecureUnitButtonTemplate"
        )
        liveFrame:SetAttribute("unit", unitToken)
        liveFrame:SetAttribute("type1", "target")
        liveFrame:SetAttribute("*type2", "togglemenu")
        liveFrame:RegisterForClicks("AnyDown", "AnyUp")
        liveFrame.unit = unitToken
        liveFrame.displayedUnit = unitToken
        self:BuildFrameVisuals(liveFrame)
        liveFrame:Hide()
        self.liveFrames[index] = liveFrame
    end

    for index = 1, MAX_RAID_TEST_FRAMES do
        local unitToken = "raid" .. tostring(index)
        local testFrame = CreateFrame(
            "Button",
            "mummuFramesRaidTestFrame" .. tostring(index),
            container,
            "SecureUnitButtonTemplate"
        )
        testFrame:SetAttribute("unit", unitToken)
        testFrame:SetAttribute("type1", "target")
        testFrame:SetAttribute("*type2", "togglemenu")
        testFrame:RegisterForClicks("AnyDown", "AnyUp")
        testFrame.unit = unitToken
        testFrame.displayedUnit = unitToken
        self:BuildFrameVisuals(testFrame)
        testFrame:Hide()
        self.testFrames[index] = testFrame
    end

    return container
end

-- Attach health text, absorb overlays, and tooltip behavior to a raid frame.
function RaidFrames:BuildFrameVisuals(frame)
    if not frame or frame._mummuVisualsBuilt then
        return
    end

    frame:SetFrameStrata((self.container and self.container:GetFrameStrata()) or RAID_FRAME_STRATA)
    frame:SetClampedToScreen(true)
    frame._mummuIsGroupFrame = true
    frame._mummuIsRaidFrame = true

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

    frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.NameText:SetJustifyH("LEFT")
    frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.HealthText:SetJustifyH("RIGHT")
    frame.StatusIconOverlay = CreateFrame("Frame", nil, frame)
    frame.StatusIconOverlay:SetAllPoints(frame)
    frame.StatusIconOverlay:SetFrameStrata("DIALOG")
    frame.StatusIconOverlay:SetFrameLevel(frame:GetFrameLevel() + 40)
    frame.LeaderIcon = frame.StatusIconOverlay:CreateTexture(nil, "OVERLAY")
    frame.LeaderIcon:SetAlpha(0.95)
    frame.LeaderIcon:Hide()

    frame.AbsorbOverlayFrame = CreateFrame("Frame", nil, frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
    frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
    frame.AbsorbOverlayFrame:Hide()

    frame.AbsorbOverlayBar = CreateFrame("StatusBar", nil, frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetAllPoints(frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
    frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(0)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    frame.AbsorbOverlayBar:Hide()

    frame.DispelOverlay = frame.HealthBar:CreateTexture(nil, "OVERLAY")
    frame.DispelOverlay:SetAllPoints(frame.HealthBar)
    frame.DispelOverlay:Hide()

    if ns.AuraHandle and type(ns.AuraHandle.PrimeTrackedAuraIndicators) == "function" then
        ns.AuraHandle:PrimeTrackedAuraIndicators(frame)
    end

    frame._mummuVisualsBuilt = true
end

-- Apply sizing, fonts, and overlay layout to one raid frame.
function RaidFrames:ApplyMemberStyle(frame, raidConfig, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not frame or not raidConfig then
        return finishPerfCounters(self, "ApplyMemberStyle", perfStartedAt, false)
    end
    if InCombatLockdown() then
        self.pendingLayoutRefresh = true
        return finishPerfCounters(self, "ApplyMemberStyle", perfStartedAt, false)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    local profile = state and state.profile or nil
    local styleConfig = profile and profile.style or nil
    local width = Util:Clamp(tonumber(raidConfig.width) or 92, 40, 240)
    local height = Util:Clamp(tonumber(raidConfig.height) or 28, 14, 80)
    local fontSize = Util:Clamp(tonumber(raidConfig.fontSize) or (styleConfig and tonumber(styleConfig.fontSize)) or 10, 6, 26)
    local pixelPerfect = Style:IsPixelPerfectEnabled()

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
    end
    fontSize = math.floor(fontSize + 0.5)

    frame:SetSize(width, height)

    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(4) or 4
    local leaderIconSize = math.max(8, math.floor((height * 0.285) + 0.5))
    if pixelPerfect then
        leaderIconSize = Style:Snap(leaderIconSize)
    end

    Style:ApplyStatusBarTexture(frame.HealthBar)
    Style:ApplyStatusBarBacking(frame.HealthBar, "health")
    frame.HealthBar:ClearAllPoints()
    frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
    frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)

    frame.NameText:ClearAllPoints()
    frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
    frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

    frame.HealthText:ClearAllPoints()
    frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")
    frame.NameText:SetTextColor(1, 1, 1, 1)
    frame.HealthText:SetTextColor(1, 1, 1, 1)
    frame.NameText:SetShadowColor(0, 0, 0, 0)
    frame.HealthText:SetShadowColor(0, 0, 0, 0)
    frame.NameText:SetShadowOffset(0, 0)
    frame.HealthText:SetShadowOffset(0, 0)

    if frame.LeaderIcon then
        frame.LeaderIcon:ClearAllPoints()
        frame.LeaderIcon:SetPoint("CENTER", frame, "LEFT", border, 0)
        frame.LeaderIcon:SetSize(leaderIconSize, leaderIconSize)
    end

    frame.DispelOverlay:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(0)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    return finishPerfCounters(self, "ApplyMemberStyle", perfStartedAt, true)
end

-- Return the spacing between subgroup containers for the chosen layout.
local function getGroupContainerGap(groupLayout, spacingX, spacingY, groupSpacing)
    if groupLayout == "horizontal" then
        return spacingY + groupSpacing
    end
    return spacingX + groupSpacing
end

-- Push layout and sorting attributes into one secure raid header.
function RaidFrames:ApplyHeaderConfiguration(header, groupIndex, width, height, spacingX, spacingY, sortBy, sortDirection, groupLayout)
    if not header then
        return
    end

    local point = (groupLayout == "horizontal") and "LEFT" or "TOP"
    local xOffset = (groupLayout == "horizontal") and spacingX or 0
    local yOffset = (groupLayout == "horizontal") and 0 or -spacingY
    local sortDir = (sortDirection == "desc") and "DESC" or "ASC"

    header:SetAttribute("showParty", false)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showPlayer", false)
    header:SetAttribute("showSolo", false)
    header:SetAttribute("groupFilter", tostring(groupIndex))
    header:SetAttribute("point", point)
    header:SetAttribute("xOffset", xOffset)
    header:SetAttribute("yOffset", yOffset)
    header:SetAttribute("frameWidth", width)
    header:SetAttribute("frameHeight", height)
    header:SetAttribute("maxDisplayed", MAX_RAID_GROUP_SIZE)

    if sortBy == "name" then
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
        header:SetAttribute("sortMethod", "NAME")
        header:SetAttribute("sortDir", sortDir)
    elseif sortBy == "role" then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", (sortDirection == "desc") and ROLE_GROUPING_ORDER_DESC or ROLE_GROUPING_ORDER_ASC)
        header:SetAttribute("sortMethod", "INDEX")
        header:SetAttribute("sortDir", "ASC")
    else
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
        header:SetAttribute("sortMethod", "INDEX")
        header:SetAttribute("sortDir", sortDir)
    end
end

-- Hide the raid container, subgroup containers, and preview frames.
function RaidFrames:HideAll()
    if self.container then
        self.container:Hide()
    end
    for index = 1, #self.liveFrames do
        local frame = self.liveFrames[index]
        if frame then
            frame:Hide()
        end
    end
    for groupIndex = 1, MAX_RAID_GROUPS do
        local groupContainer = self.groupContainers[groupIndex]
        if groupContainer then
            groupContainer:Hide()
        end
    end
    for index = 1, #self.testFrames do
        local frame = self.testFrames[index]
        if frame then
            frame:Hide()
        end
    end
end

-- Refresh one raid frame's vitals, alpha state, and aura overlays.
function RaidFrames:RefreshMember(frame, unitToken, raidConfig, previewMode, forceStyle, refreshOptions, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not frame then
        return finishPerfCounters(self, "RefreshMember", perfStartedAt)
    end

    refreshOptions = refreshOptions or MEMBER_REFRESH_FULL
    local refreshVitals = refreshOptions.vitals == true
    local refreshAuras = refreshOptions.auras == true
    local needsStyle = forceStyle == true or frame._mummuStyleApplied ~= true
    if needsStyle then
        local applied = self:ApplyMemberStyle(frame, raidConfig, runtimeState)
        if applied then
            frame._mummuStyleApplied = true
        elseif frame._mummuStyleApplied ~= true then
            return finishPerfCounters(self, "RefreshMember", perfStartedAt)
        end
    end

    local exists = not previewMode and UnitExists(unitToken)
    local isConnected = true
    local _, classToken = UnitClass(unitToken)
    local name = getLiveDisplayName(unitToken)
    local health = 100
    local maxHealth = 100
    local absorb = 0

    if previewMode then
        local numericIndex = tonumber(string.match(unitToken or "", "^raid(%d+)$")) or 1
        local previewHealth = 100 - ((numericIndex * 7) % 65)
        health = Util:Clamp(previewHealth, 25, 100)
        maxHealth = 100
        absorb = numericIndex % 3 == 0 and 18 or 0
        name = string.format("Raid %02d", numericIndex)
    elseif exists then
        if type(UnitIsConnected) == "function" then
            isConnected = Util:SafeBoolean(UnitIsConnected(unitToken), true)
        end
        health = UnitHealth(unitToken) or 0
        maxHealth = UnitHealthMax(unitToken) or 1
        if type(UnitGetTotalAbsorbs) == "function" then
            absorb = getSafeNumericValue(UnitGetTotalAbsorbs(unitToken), 0) or 0
        end
    end

    if refreshVitals then
        local showLeaderIcon = shouldShowLeaderIcon(unitToken, previewMode)
        local darkModeEnabled = Style:IsDarkModeEnabled()
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
        if not isConnected then
            health = 0
            maxHealth = 1
            absorb = 0
        end
        setStatusBarValueSafe(frame.HealthBar, health, maxHealth)

        local absorbForBar = getSafeNumericValue(absorb, 0) or 0
        local shouldShowAbsorb = (previewMode or (exists and isConnected)) and absorbForBar > 0
        if shouldShowAbsorb then
            refreshRaidAbsorbOverlay(frame, health, maxHealth, absorbForBar)
        else
            hideRaidAbsorbOverlay(frame)
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

        frame.NameText:SetText(name)
        local healthPercent = 0
        if exists and type(UnitHealthPercent) == "function" then
            local curve = (_G.CurveConstants and _G.CurveConstants.ScaleTo100) or nil
            local okPercent, rawPercent = pcall(UnitHealthPercent, unitToken, true, curve)
            if okPercent and type(rawPercent) == "number" then
                healthPercent = rawPercent
            end
        else
            healthPercent = computePercent(health, maxHealth)
        end
        if not isConnected then
            frame.HealthText:SetText("OFFLINE")
            frame.NameText:SetTextColor(0.72, 0.72, 0.72, 1)
            frame.HealthText:SetTextColor(0.72, 0.72, 0.72, 1)
        else
            frame.HealthText:SetText(string.format("%.0f%%", healthPercent))
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

        frame:SetAlpha(resolveRaidMemberFrameAlpha(unitToken, exists, isConnected, previewMode))
    end

    if refreshAuras and ns.AuraHandle and type(ns.AuraHandle.RefreshGroupAuras) == "function" then
        ns.AuraHandle:RefreshGroupAuras(frame, unitToken, exists == true, previewMode)
    end
    recordPerfCounters(self, "RefreshMember", perfStartedAt)
end

-- Rebuild displayedUnit and GUID maps from active raid frames.
function RaidFrames:RebuildDisplayedUnitMap(allowHidden, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    local frameByDisplayedUnit = {}
    local displayedUnitByGUID = {}
    local includeHidden = allowHidden == true
    local previousFrameByDisplayedUnit =
        type(self._frameByDisplayedUnit) == "table" and self._frameByDisplayedUnit or {}

    local state = runtimeState or buildRaidRuntimeState(self)
    local isPreview = state and state.previewMode == true
    local candidateFrames = isPreview and self.testFrames or self.liveFrames

    for frameIndex = 1, #candidateFrames do
        local frame = candidateFrames[frameIndex]
        if frame then
            local isShown = type(frame.IsShown) == "function" and frame:IsShown() or true
            if includeHidden or isShown then
                local displayedUnit = getCurrentRaidFrameDisplayedUnit(frame)

                local shouldMapUnit = false
                if displayedUnit and UnitExists(displayedUnit) then
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

    if includeHidden and InCombatLockdown() then
        for unitToken, previousFrame in pairs(previousFrameByDisplayedUnit) do
            if type(unitToken) == "string" and string.match(unitToken, "^raid%d+$") and previousFrame and not frameByDisplayedUnit[unitToken] then
                if UnitExists(unitToken) then
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

-- Find the secure child that already owns the requested raid unit token.
function RaidFrames:EnsureMappedFrameForUnit(unitToken)
    if type(unitToken) ~= "string" or not string.match(unitToken, "^raid%d+$") then
        return nil
    end

    self._frameByDisplayedUnit = self._frameByDisplayedUnit or {}
    local existing = self._frameByDisplayedUnit[unitToken]
    if existing then
        return existing
    end

    local frameIndex = getRaidFrameIndexFromUnitToken(unitToken)
    local frame = frameIndex and self.liveFrames[frameIndex] or nil
    if frame then
        self._frameByDisplayedUnit[unitToken] = frame
        frame.unit = unitToken
        frame.displayedUnit = unitToken
        local guid = getUnitGUIDSafe(unitToken)
        if guid then
            self._displayedUnitByGUID = self._displayedUnitByGUID or {}
            setDisplayedUnitForGUID(self._displayedUnitByGUID, guid, unitToken)
        end
        return frame
    end

    return nil
end

-- Resolve an incoming unit token to the currently displayed raid token.
function RaidFrames:ResolveDisplayedUnitToken(unitToken)
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
        for displayedUnit in pairs(frameByDisplayedUnit) do
            local displayedGUID = getUnitGUIDSafe(displayedUnit)
            if displayedGUID and displayedGUID == guid then
                return displayedUnit
            end
        end
    end

    return nil
end

-- Refresh the currently displayed raid frame for the given unit token.
function RaidFrames:RefreshDisplayedUnit(unitToken, refreshOptions, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, true)
    end

    local inAnyRaid = hasLiveRaidUnits()
    if not state.addonEnabled or state.raidConfig.enabled == false or not inAnyRaid then
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
        frame.displayedUnit or displayedUnit,
        state.raidConfig,
        false,
        false,
        refreshOptions or MEMBER_REFRESH_FULL,
        state
    )
    return finishPerfCounters(self, "RefreshDisplayedUnit", perfStartedAt, true)
end

-- Refresh a known mapped frame directly without re-resolving it.
function RaidFrames:RefreshDisplayedMappedFrame(frame, unitToken, refreshOptions, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(frame) ~= "table" or type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, true)
    end

    local displayedUnit = getCurrentRaidFrameDisplayedUnit(frame) or unitToken
    self:RefreshMember(
        frame,
        displayedUnit,
        state.raidConfig,
        false,
        false,
        refreshOptions or MEMBER_REFRESH_AURAS_ONLY,
        state
    )
    return finishPerfCounters(self, "RefreshDisplayedMappedFrame", perfStartedAt, true)
end

-- Refresh only the connection/range alpha for the currently displayed raid frame.
function RaidFrames:RefreshDisplayedUnitRangeState(unitToken, inRangeState, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedUnitRangeState", perfStartedAt, true)
    end

    local inAnyRaid = hasLiveRaidUnits()
    if not state.addonEnabled or state.raidConfig.enabled == false or not inAnyRaid then
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

-- Refresh only the connection/range alpha for a known mapped raid frame.
function RaidFrames:RefreshDisplayedMappedFrameRangeState(frame, unitToken, inRangeState, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if type(frame) ~= "table" or type(unitToken) ~= "string" or unitToken == "" then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end
    if state.previewMode then
        self:RefreshAll(false, state)
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, true)
    end

    local inAnyRaid = hasLiveRaidUnits()
    if not state.addonEnabled or state.raidConfig.enabled == false or not inAnyRaid then
        return finishPerfCounters(self, "RefreshDisplayedMappedFrameRangeState", perfStartedAt, false)
    end

    local displayedUnit = getCurrentRaidFrameDisplayedUnit(frame) or unitToken
    return finishPerfCounters(
        self,
        "RefreshDisplayedMappedFrameRangeState",
        perfStartedAt,
        refreshRaidMemberRangeState(frame, displayedUnit, false, inRangeState)
    )
end

-- Refresh alpha-only range state for every currently displayed live raid frame.
-- Kept as an explicit sync helper; live updates normally arrive from
-- UNIT_IN_RANGE_UPDATE through AuraHandle's group dispatcher.
function RaidFrames:RefreshAllDisplayedRangeStates(runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not self.dataHandle or not self.container then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end
    if state.previewMode or not state.addonEnabled or state.raidConfig.enabled == false or not hasLiveRaidUnits() then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    local frameByDisplayedUnit = self._frameByDisplayedUnit
    if type(frameByDisplayedUnit) ~= "table" then
        return finishPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
    end

    for displayedUnit, frame in pairs(frameByDisplayedUnit) do
        if frame and (type(frame.IsShown) ~= "function" or frame:IsShown()) then
            refreshRaidMemberRangeState(frame, getCurrentRaidFrameDisplayedUnit(frame) or displayedUnit, false)
        end
    end
    recordPerfCounters(self, "RefreshAllDisplayedRangeStates", perfStartedAt)
end

-- Stop any legacy live range ticker if one exists.
function RaidFrames:StopRangeTicker()
    local ticker = self._rangeTicker
    if ticker and type(ticker.Cancel) == "function" then
        ticker:Cancel()
    end
    self._rangeTicker = nil
end

-- Group range is event-driven in Midnight retail; keep this as a no-op so
-- callers do not reintroduce protected range polling during combat.
function RaidFrames:EnsureRangeTicker()
    self:StopRangeTicker()
end

-- Refresh every raid frame in live mode or preview mode.
function RaidFrames:RefreshAll(forceLayout, runtimeState)
    local perfStartedAt = startPerfCounters(self)
    if not self.dataHandle then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    self:CreateRaidFrames()
    if not self.container then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    local state = runtimeState or buildRaidRuntimeState(self)
    if not state then
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end
    local profile = state.profile
    local raidConfig = state.raidConfig
    local testMode = state.testMode
    local previewMode = state.previewMode
    local addonEnabled = state.addonEnabled
    local inCombat = InCombatLockdown()
    local shouldApplyLayout = (forceLayout == true) or (self.layoutInitialized ~= true)

    self:ApplyBlizzardRaidFrameVisibility(state)

    if not previewMode and (not addonEnabled or raidConfig.enabled == false) then
        self.frames = {}
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        ns.activeMummuRaidFrames = {}
        if inCombat then
            self.pendingLayoutRefresh = true
        else
            self:HideAll()
        end
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    local width = Util:Clamp(tonumber(raidConfig.width) or 92, 40, 240)
    local height = Util:Clamp(tonumber(raidConfig.height) or 28, 14, 80)
    local spacingX = Util:Clamp(tonumber(raidConfig.spacingX) or 5, 0, 80)
    local spacingY = Util:Clamp(tonumber(raidConfig.spacingY) or 6, 0, 80)
    local groupSpacing = Util:Clamp(tonumber(raidConfig.groupSpacing) or 12, 0, 120)
    local x = tonumber(raidConfig.x) or 0
    local y = tonumber(raidConfig.y) or 0
    local groupLayout = (raidConfig.groupLayout == "horizontal") and "horizontal" or "vertical"
    local sortBy = (raidConfig.sortBy == "name" or raidConfig.sortBy == "role") and raidConfig.sortBy or "group"
    local sortDirection = (raidConfig.sortDirection == "desc") and "desc" or "asc"
    local pixelPerfect = Style:IsPixelPerfectEnabled()

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
        spacingX = Style:Snap(spacingX)
        spacingY = Style:Snap(spacingY)
        groupSpacing = Style:Snap(groupSpacing)
        x = Style:Snap(x)
        y = Style:Snap(y)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        spacingX = math.floor(spacingX + 0.5)
        spacingY = math.floor(spacingY + 0.5)
        groupSpacing = math.floor(groupSpacing + 0.5)
        x = math.floor(x + 0.5)
        y = math.floor(y + 0.5)
    end

    if previewMode then
        if inCombat then
            self.pendingLayoutRefresh = true
            return finishPerfCounters(self, "RefreshAll", perfStartedAt)
        end

        for index = 1, #self.liveFrames do
            if self.liveFrames[index] then
                self.liveFrames[index]:Hide()
            end
        end
        for groupIndex = 1, MAX_RAID_GROUPS do
            if self.groupContainers[groupIndex] then
                self.groupContainers[groupIndex]:Hide()
            end
        end

        local entries, orderedGroups = sortEntriesWithinGroups(
            getPreviewEntries(raidConfig.testSize or 20),
            sortBy,
            sortDirection
        )
        local groupCounts = {}
        for entryIndex = 1, #entries do
            local entry = entries[entryIndex]
            groupCounts[entry.groupIndex] = math.max(groupCounts[entry.groupIndex] or 0, entry.slotIndex)
        end

        local groupGap = getGroupContainerGap(groupLayout, spacingX, spacingY, groupSpacing)
        local containerWidth = 0
        local containerHeight = 0
        for groupOrder = 1, #orderedGroups do
            local groupIndex = orderedGroups[groupOrder]
            local groupWidth, groupHeight = getGroupContainerSize(groupCounts[groupIndex], width, height, spacingX, spacingY, groupLayout)
            if groupLayout == "horizontal" then
                if groupWidth > containerWidth then
                    containerWidth = groupWidth
                end
                containerHeight = containerHeight + groupHeight
                if groupOrder < #orderedGroups then
                    containerHeight = containerHeight + groupGap
                end
            else
                containerWidth = containerWidth + groupWidth
                if groupOrder < #orderedGroups then
                    containerWidth = containerWidth + groupGap
                end
                if groupHeight > containerHeight then
                    containerHeight = groupHeight
                end
            end
        end
        containerWidth = math.max(containerWidth, width)
        containerHeight = math.max(containerHeight, height)

        if shouldApplyLayout then
            self.container:SetSize(containerWidth, containerHeight)
            self.container:ClearAllPoints()
            self.container:SetPoint(
                raidConfig.point or "TOPLEFT",
                UIParent,
                raidConfig.relativePoint or "TOPLEFT",
                x,
                y
            )
        end

        local groupSlotByIndex = {}
        for groupOrder = 1, #orderedGroups do
            groupSlotByIndex[orderedGroups[groupOrder]] = groupOrder
        end

        local activeFrames = {}
        local frameByDisplayedUnit = {}
        local displayedUnitByGUID = {}

        for groupIndex = 1, MAX_RAID_GROUPS do
            if self.groupContainers[groupIndex] then
                self.groupContainers[groupIndex]:Hide()
            end
        end

        for entryIndex = 1, MAX_RAID_TEST_FRAMES do
            local frame = self.testFrames[entryIndex]
            local entry = entries[entryIndex]
            if frame and entry then
                local groupSlot = groupSlotByIndex[entry.groupIndex] or entry.groupIndex
                local memberSlot = entry.slotIndex
                local groupOffset = 0
                for previousGroup = 1, groupSlot - 1 do
                    local previousGroupIndex = orderedGroups[previousGroup]
                    local previousWidth, previousHeight = getGroupContainerSize(
                        groupCounts[previousGroupIndex],
                        width,
                        height,
                        spacingX,
                        spacingY,
                        groupLayout
                    )
                    groupOffset = groupOffset + ((groupLayout == "horizontal") and previousHeight or previousWidth) + groupGap
                end

                frame.unit = entry.unitToken
                frame.displayedUnit = entry.unitToken
                frameByDisplayedUnit[entry.unitToken] = frame
                if shouldApplyLayout then
                    frame:ClearAllPoints()
                    if groupLayout == "horizontal" then
                        local memberX = (memberSlot - 1) * (width + spacingX)
                        frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", memberX, -groupOffset)
                    else
                        local memberY = (memberSlot - 1) * (height + spacingY)
                        frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", groupOffset, -memberY)
                    end
                    frame:SetSize(width, height)
                end
                self:RefreshMember(frame, entry.unitToken, raidConfig, true, shouldApplyLayout, MEMBER_REFRESH_FULL, state)
                if type(frame.EnableMouse) == "function" then
                    frame:EnableMouse(true)
                end
                frame:Show()
                activeFrames[#activeFrames + 1] = frame
            elseif frame then
                frame:Hide()
            end
        end

        self.frames = activeFrames
        self._frameByDisplayedUnit = frameByDisplayedUnit
        self._displayedUnitByGUID = displayedUnitByGUID
        ns.activeMummuRaidFrames = activeFrames
        self.container:Show()
        if shouldApplyLayout then
            self.layoutInitialized = true
        end
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    local entries, orderedGroups, groupCounts = buildLiveRaidEntries(sortBy, sortDirection)
    if #entries == 0 then
        self.frames = {}
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        ns.activeMummuRaidFrames = {}
        if inCombat then
            self.pendingLayoutRefresh = true
        else
            self:HideAll()
        end
        return finishPerfCounters(self, "RefreshAll", perfStartedAt)
    end

    local groupGap = getGroupContainerGap(groupLayout, spacingX, spacingY, groupSpacing)

    if shouldApplyLayout and not inCombat then
        local containerWidth = 0
        local containerHeight = 0
        for groupOrder = 1, #orderedGroups do
            local groupIndex = orderedGroups[groupOrder]
            local groupWidth, groupHeight = getGroupContainerSize(
                groupCounts[groupIndex],
                width,
                height,
                spacingX,
                spacingY,
                groupLayout
            )
            if groupLayout == "horizontal" then
                if groupWidth > containerWidth then
                    containerWidth = groupWidth
                end
                containerHeight = containerHeight + groupHeight
                if groupOrder < #orderedGroups then
                    containerHeight = containerHeight + groupGap
                end
            else
                containerWidth = containerWidth + groupWidth
                if groupOrder < #orderedGroups then
                    containerWidth = containerWidth + groupGap
                end
                if groupHeight > containerHeight then
                    containerHeight = groupHeight
                end
            end
        end
        containerWidth = math.max(containerWidth, width)
        containerHeight = math.max(containerHeight, height)

        self.container:SetSize(containerWidth, containerHeight)
        self.container:ClearAllPoints()
        self.container:SetPoint(
            raidConfig.point or "TOPLEFT",
            UIParent,
            raidConfig.relativePoint or "TOPLEFT",
            x,
            y
        )
    end

    if not inCombat then
        for index = 1, #self.testFrames do
            if self.testFrames[index] then
                self.testFrames[index]:Hide()
            end
        end
        for groupIndex = 1, MAX_RAID_GROUPS do
            if self.groupContainers[groupIndex] then
                self.groupContainers[groupIndex]:Hide()
            end
        end
    end

    local groupSlotByIndex = {}
    for groupOrder = 1, #orderedGroups do
        groupSlotByIndex[orderedGroups[groupOrder]] = groupOrder
    end

    local activeFrames = {}
    local frameByDisplayedUnit = {}
    local displayedUnitByGUID = {}
    local usedFrameByIndex = {}

    for entryIndex = 1, #entries do
        local entry = entries[entryIndex]
        local frameIndex = getRaidFrameIndexFromUnitToken(entry.unitToken)
        local frame = frameIndex and self.liveFrames[frameIndex] or nil
        if frame then
            frame.unit = entry.unitToken
            frame.displayedUnit = entry.unitToken
            frameByDisplayedUnit[entry.unitToken] = frame
            usedFrameByIndex[frameIndex] = true

            local guid = getUnitGUIDSafe(entry.unitToken)
            if guid then
                setDisplayedUnitForGUID(displayedUnitByGUID, guid, entry.unitToken)
            end

            if shouldApplyLayout and not inCombat then
                local groupSlot = groupSlotByIndex[entry.groupIndex] or entry.groupIndex
                local memberSlot = entry.slotIndex
                local groupOffset = 0
                for previousGroup = 1, groupSlot - 1 do
                    local previousGroupIndex = orderedGroups[previousGroup]
                    local previousWidth, previousHeight = getGroupContainerSize(
                        groupCounts[previousGroupIndex],
                        width,
                        height,
                        spacingX,
                        spacingY,
                        groupLayout
                    )
                    groupOffset = groupOffset + ((groupLayout == "horizontal") and previousHeight or previousWidth) + groupGap
                end

                frame:ClearAllPoints()
                if groupLayout == "horizontal" then
                    local memberX = (memberSlot - 1) * (width + spacingX)
                    frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", memberX, -groupOffset)
                else
                    local memberY = (memberSlot - 1) * (height + spacingY)
                    frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", groupOffset, -memberY)
                end
                frame:SetSize(width, height)
            end

            self:RefreshMember(frame, entry.unitToken, raidConfig, false, shouldApplyLayout, MEMBER_REFRESH_FULL, state)
            activeFrames[#activeFrames + 1] = frame
            if not inCombat then
                if type(frame.EnableMouse) == "function" then
                    frame:EnableMouse(true)
                end
                frame:Show()
            end
        end
    end

    if not inCombat then
        for index = 1, #self.liveFrames do
            local frame = self.liveFrames[index]
            if frame and not usedFrameByIndex[index] then
                frame:Hide()
            end
        end
    end

    self.frames = activeFrames
    self._frameByDisplayedUnit = frameByDisplayedUnit
    self._displayedUnitByGUID = displayedUnitByGUID
    ns.activeMummuRaidFrames = activeFrames

    if ns.AuraHandle and type(ns.AuraHandle.RebuildSharedUnitFrameMap) == "function" then
        ns.AuraHandle:RebuildSharedUnitFrameMap(inCombat, inCombat and "raid_refresh_combat" or "raid_refresh")
    end

    if not inCombat then
        self.container:Show()
        if shouldApplyLayout then
            self.layoutInitialized = true
        end
    else
        self.pendingLayoutRefresh = true
    end
    recordPerfCounters(self, "RefreshAll", perfStartedAt)
end

-- Enable or disable lightweight runtime profiling counters for raid hot paths.
function RaidFrames:SetPerfCountersEnabled(enabled, resetExisting)
    self._perfCountersEnabled = enabled == true
    if resetExisting ~= false then
        self._perfCounters = {}
    end
end

-- Return a snapshot of the current profiling counters.
function RaidFrames:GetPerfCounters()
    return copyPerfCounters(self._perfCounters)
end

-- Clear recorded profiling counters.
function RaidFrames:ResetPerfCounters()
    self._perfCounters = {}
end

addon:RegisterModule("raidFrames", RaidFrames:New())
