-- ============================================================================
-- MUMMUFRAMES GROUP RANGE MODULE
-- ============================================================================
-- Owns party/raid out-of-range state for group frames.
--
-- Design goals:
--   * Keep range state in one place instead of spreading logic across frames.
--   * Prefer friendly spell checks when the player has a meaningful spell.
--   * Fall back safely to UnitInRange and interact distance.
--   * Persist the last useful result so frame refreshes do not fail open.
--   * Combine UNIT_IN_RANGE_UPDATE with a lightweight polling safety net.

local _, ns = ...

local addon = _G.mummuFrames
local Util = ns.Util

local RangeHandle = ns.Object:Extend()

local RANGE_POLL_INTERVAL = 0.35
local RANGE_EVENT_HINT_TTL = 1.0
local GROUP_OUT_OF_RANGE_ALPHA = 0.55
local GROUP_OFFLINE_ALPHA = 0.70
local GROUP_UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }

for raidIndex = 1, 40 do
    GROUP_UNIT_TOKENS[#GROUP_UNIT_TOKENS + 1] = "raid" .. tostring(raidIndex)
end

local FRIENDLY_RANGE_CANDIDATES_BY_CLASS = {
    DRUID = { 774, 8936, 5185 },
    EVOKER = { 355913, 361469 },
    MONK = { 116670 },
    PALADIN = { 19750, 635 },
    PRIEST = { 17, 2061, 2050 },
    SHAMAN = { 8004, 331 },
    WARLOCK = { 5697, 20707 },
    WARRIOR = { 3411 },
}

local FRIENDLY_RANGE_CANDIDATES_BY_SPEC = {
    [105] = { 774, 8936 },
    [256] = { 17, 2061 },
    [257] = { 2061, 17 },
    [258] = { 17, 2061 },
    [264] = { 8004, 331 },
    [270] = { 116670 },
    [1467] = { 355913, 361469 },
    [1468] = { 355913, 361469 },
    [1473] = { 355913, 361469 },
}

local DEAD_RANGE_CANDIDATES_BY_CLASS = {
    DEATHKNIGHT = { 61999 },
    DRUID = { 20484 },
    EVOKER = { 361227 },
    MONK = { 115178 },
    PALADIN = { 7328 },
    PRIEST = { 2006 },
    SHAMAN = { 2008 },
    WARLOCK = { 20707 },
}

local function isGroupUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end
    return unitToken == "player"
        or string.match(unitToken, "^party%d+$") ~= nil
        or string.match(unitToken, "^raid%d+$") ~= nil
end

local function getOwnerKeyForUnit(unitToken)
    if type(unitToken) ~= "string" then
        return nil
    end
    if unitToken == "player" or string.match(unitToken, "^party%d+$") then
        return "party"
    end
    if string.match(unitToken, "^raid%d+$") then
        return "raid"
    end
    return nil
end

local function isSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function normalizeComparableBoolean(value)
    if isSecretValue(value) then
        return nil
    end
    if Util and type(Util.NormalizeBooleanLike) == "function" then
        return Util:NormalizeBooleanLike(value)
    end
    if value == nil then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        local normalized = string.lower(value)
        if normalized == "true" or normalized == "1" then
            return true
        end
        if normalized == "false" or normalized == "0" or normalized == "" then
            return false
        end
    end
    return nil
end

local function makeStateRecord(rawValue, comparableValue, sourceTag, eventHintComparable)
    local signature = "nil"
    if comparableValue == true then
        signature = "true"
    elseif comparableValue == false then
        signature = "false"
    elseif isSecretValue(rawValue) then
        signature = "secret"
    end

    return {
        rawValue = rawValue,
        comparableValue = comparableValue,
        source = sourceTag,
        eventHintComparable = eventHintComparable,
        signature = signature,
        updatedAt = GetTime(),
    }
end

local function makeEventHintRecord(rawValue)
    return {
        rawValue = rawValue,
        comparableValue = normalizeComparableBoolean(rawValue),
        updatedAt = GetTime(),
    }
end

local function getPlayerClassToken()
    local _, classToken = UnitClass("player")
    if type(classToken) == "string" and classToken ~= "" then
        return classToken
    end
    return nil
end

local function getPlayerSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if type(specIndex) ~= "number" then
        return nil
    end

    local specID = GetSpecializationInfo(specIndex)
    if type(specID) == "number" then
        return specID
    end
    return nil
end

local function isSpellKnownSafe(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then
        return false
    end

    if type(IsPlayerSpell) == "function" then
        local okPlayerSpell, isPlayerSpell = pcall(IsPlayerSpell, spellID)
        if okPlayerSpell and isPlayerSpell == true then
            return true
        end
    end

    if type(IsSpellKnownOrOverridesKnown) == "function" then
        local okKnown, isKnown = pcall(IsSpellKnownOrOverridesKnown, spellID)
        if okKnown and isKnown == true then
            return true
        end
    end

    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local okBook, isKnownInBook = pcall(C_SpellBook.IsSpellKnown, spellID)
        if okBook and isKnownInBook == true then
            return true
        end
    end

    return false
end

local function pickKnownSpellID(candidateList)
    if type(candidateList) ~= "table" then
        return nil
    end

    for index = 1, #candidateList do
        local spellID = candidateList[index]
        if isSpellKnownSafe(spellID) then
            return spellID
        end
    end

    return nil
end

local function probeSpellRange(spellID, unitToken)
    if type(spellID) ~= "number" or spellID <= 0 then
        return nil, nil
    end
    if not (C_Spell and type(C_Spell.IsSpellInRange) == "function") then
        return nil, nil
    end

    local okRange, rawValue = pcall(C_Spell.IsSpellInRange, spellID, unitToken)
    if not okRange then
        return nil, nil
    end

    local comparableValue = normalizeComparableBoolean(rawValue)
    if comparableValue ~= nil then
        return rawValue, comparableValue
    end

    return nil, nil
end

local function probeUnitInRange(unitToken)
    if type(UnitInRange) ~= "function" then
        return nil
    end

    local okRange, rawInRange, rawCheckedRange = pcall(UnitInRange, unitToken)
    if not okRange then
        return nil
    end

    return {
        rawValue = rawInRange,
        comparableValue = normalizeComparableBoolean(rawInRange),
        rawCheckedRange = rawCheckedRange,
        checkedComparable = normalizeComparableBoolean(rawCheckedRange),
        hasSecretValue = isSecretValue(rawInRange) or isSecretValue(rawCheckedRange),
    }
end

local function probeInteractRange(unitToken)
    if type(CheckInteractDistance) ~= "function" then
        return nil
    end

    local okRange, rawValue = pcall(CheckInteractDistance, unitToken, 4)
    if not okRange then
        return nil
    end

    return normalizeComparableBoolean(rawValue)
end

function RangeHandle:Constructor()
    self.addon = nil
    self.partyFrames = nil
    self.raidFrames = nil
    self._pollTicker = nil
    self._unitStateByToken = {}
    self._eventHintByUnit = {}
    self._playerClassToken = nil
    self._playerSpecID = nil
    self._friendlyRangeSpellID = nil
    self._deadRangeSpellID = nil
end

function RangeHandle:OnInitialize(addonRef)
    self.addon = addonRef
end

function RangeHandle:OnEnable()
    self.partyFrames = self.addon:GetModule("partyFrames")
    self.raidFrames = self.addon:GetModule("raidFrames")
    self._playerClassToken = getPlayerClassToken()
    self:RefreshKnownRangeSpells()
    self:ResetRangeState()
    self:RegisterEvents()
    self:StartPollTicker()
    self:RefreshAllTrackedUnits("enable", true)
end

function RangeHandle:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:StopPollTicker()
    self.partyFrames = nil
    self.raidFrames = nil
    self:ResetRangeState()
end

function RangeHandle:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldChanged)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnWorldChanged)
    ns.EventRouter:Register(self, "PLAYER_REGEN_DISABLED", self.OnCombatStateChanged)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatStateChanged)
    ns.EventRouter:Register(self, "SPELLS_CHANGED", self.OnSpellbookChanged)
    ns.EventRouter:Register(self, "PLAYER_SPECIALIZATION_CHANGED", self.OnSpecChanged)
    ns.EventRouter:Register(self, "PLAYER_TALENT_UPDATE", self.OnSpellbookChanged)
    ns.EventRouter:Register(self, "UNIT_CONNECTION", self.OnRangeRelatedUnitEvent)
    ns.EventRouter:Register(self, "UNIT_FLAGS", self.OnRangeRelatedUnitEvent)
    ns.EventRouter:Register(self, "UNIT_PHASE", self.OnRangeRelatedUnitEvent)
    ns.EventRouter:Register(self, "UNIT_IN_RANGE_UPDATE", self.OnUnitInRangeUpdate)
end

function RangeHandle:StartPollTicker()
    self:StopPollTicker()
    if not (C_Timer and type(C_Timer.NewTicker) == "function") then
        return
    end

    self._pollTicker = C_Timer.NewTicker(RANGE_POLL_INTERVAL, function()
        self:OnPollTick()
    end)
end

function RangeHandle:StopPollTicker()
    local ticker = self._pollTicker
    if ticker and type(ticker.Cancel) == "function" then
        ticker:Cancel()
    end
    self._pollTicker = nil
end

function RangeHandle:ResetRangeState()
    wipe(self._unitStateByToken)
    wipe(self._eventHintByUnit)
end

function RangeHandle:SetEventHint(unitToken, rawValue)
    if not isGroupUnitToken(unitToken) or rawValue == nil then
        return
    end

    self._eventHintByUnit[unitToken] = makeEventHintRecord(rawValue)
end

function RangeHandle:GetRecentEventHint(unitToken)
    if not isGroupUnitToken(unitToken) then
        return nil, nil
    end

    local hintRecord = self._eventHintByUnit[unitToken]
    if type(hintRecord) ~= "table" then
        return nil, nil
    end

    local updatedAt = tonumber(hintRecord.updatedAt) or 0
    if updatedAt <= 0 or (GetTime() - updatedAt) > RANGE_EVENT_HINT_TTL then
        self._eventHintByUnit[unitToken] = nil
        return nil, nil
    end

    return hintRecord.rawValue, hintRecord.comparableValue
end

function RangeHandle:RefreshKnownRangeSpells()
    self._playerClassToken = self._playerClassToken or getPlayerClassToken()
    self._playerSpecID = getPlayerSpecID()

    local friendlySpellID = nil
    if self._playerSpecID and FRIENDLY_RANGE_CANDIDATES_BY_SPEC[self._playerSpecID] then
        friendlySpellID = pickKnownSpellID(FRIENDLY_RANGE_CANDIDATES_BY_SPEC[self._playerSpecID])
    end
    if not friendlySpellID and self._playerClassToken and FRIENDLY_RANGE_CANDIDATES_BY_CLASS[self._playerClassToken] then
        friendlySpellID = pickKnownSpellID(FRIENDLY_RANGE_CANDIDATES_BY_CLASS[self._playerClassToken])
    end

    local deadSpellID = nil
    if self._playerClassToken and DEAD_RANGE_CANDIDATES_BY_CLASS[self._playerClassToken] then
        deadSpellID = pickKnownSpellID(DEAD_RANGE_CANDIDATES_BY_CLASS[self._playerClassToken])
    end

    self._friendlyRangeSpellID = friendlySpellID
    self._deadRangeSpellID = deadSpellID
end

function RangeHandle:GetOwnerModule(ownerKey)
    if ownerKey == "raid" then
        return self.raidFrames
    end
    if ownerKey == "party" then
        return self.partyFrames
    end
    return nil
end

function RangeHandle:GetCachedUnitState(unitToken)
    if not isGroupUnitToken(unitToken) then
        return nil
    end
    return self._unitStateByToken[unitToken]
end

function RangeHandle:GetUnitRangeValue(unitToken, forceRefresh)
    if not isGroupUnitToken(unitToken) then
        return nil
    end
    if forceRefresh == true then
        self:RefreshUnitState(unitToken, nil, "forced_lookup")
    elseif not self._unitStateByToken[unitToken] then
        self:RefreshUnitState(unitToken, nil, "lazy_lookup")
    end

    local state = self._unitStateByToken[unitToken]
    return state and state.rawValue or nil
end

function RangeHandle:ApplyGroupFrameAlpha(frame, unitToken, options)
    if type(frame) ~= "table" then
        return false
    end

    options = options or {}
    local previewMode = options.previewMode == true
    local testMode = options.testMode == true
    local exists = options.exists == true
    local isConnected = options.isConnected ~= false

    if previewMode or testMode or not exists then
        frame:SetAlpha(1)
        return true
    end

    if not isConnected then
        frame:SetAlpha(GROUP_OFFLINE_ALPHA)
        return true
    end

    local rangeValue = options.rangeValue
    if rangeValue == nil then
        rangeValue = self:GetUnitRangeValue(unitToken)
    end

    if rangeValue == nil then
        frame:SetAlpha(1)
        return true
    end

    if type(frame.SetAlphaFromBoolean) == "function" then
        frame:SetAlphaFromBoolean(rangeValue, 1, GROUP_OUT_OF_RANGE_ALPHA)
        return true
    end

    local comparableValue = normalizeComparableBoolean(rangeValue)
    if comparableValue == nil then
        frame:SetAlpha(1)
        return true
    end

    frame:SetAlpha(comparableValue and 1 or GROUP_OUT_OF_RANGE_ALPHA)
    return true
end

function RangeHandle:NotifyOwnerUnitRefresh(ownerKey, unitToken, refreshAll)
    local module = self:GetOwnerModule(ownerKey)
    if not module then
        return false
    end

    if refreshAll == true and type(module.RefreshAllDisplayedRangeStates) == "function" then
        module:RefreshAllDisplayedRangeStates()
        return true
    end

    if type(unitToken) == "string" and unitToken ~= "" and type(module.RefreshDisplayedUnitRangeState) == "function" then
        local refreshed = module:RefreshDisplayedUnitRangeState(unitToken, self:GetUnitRangeValue(unitToken))
        if refreshed then
            return true
        end
    end

    if type(module.RefreshAllDisplayedRangeStates) == "function" then
        module:RefreshAllDisplayedRangeStates()
        return true
    end

    return false
end

function RangeHandle:ResolveRangeState(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return makeStateRecord(nil, nil, "invalid")
    end

    if unitToken == "player" then
        return makeStateRecord(true, true, "player")
    end

    if type(UnitExists) == "function" and UnitExists(unitToken) ~= true then
        return makeStateRecord(nil, nil, "missing")
    end

    local previousState = self._unitStateByToken[unitToken]
    local eventHintRaw, eventHintComparable = self:GetRecentEventHint(unitToken)

    if type(UnitIsConnected) == "function" then
        local okConnected, rawConnected = pcall(UnitIsConnected, unitToken)
        if okConnected and normalizeComparableBoolean(rawConnected) == false then
            return makeStateRecord(nil, nil, "offline", eventHintComparable)
        end
    end

    if type(UnitPhaseReason) == "function" then
        local okPhase, phaseReason = pcall(UnitPhaseReason, unitToken)
        if okPhase and phaseReason ~= nil and not isSecretValue(phaseReason) then
            return makeStateRecord(false, false, "phase", eventHintComparable)
        end
    end

    if type(UnitIsVisible) == "function" then
        local okVisible, rawVisible = pcall(UnitIsVisible, unitToken)
        if okVisible and normalizeComparableBoolean(rawVisible) == false then
            return makeStateRecord(false, false, "visibility", eventHintComparable)
        end
    end

    if self._deadRangeSpellID and type(UnitIsDeadOrGhost) == "function" then
        local okDead, isDeadOrGhost = pcall(UnitIsDeadOrGhost, unitToken)
        if okDead and normalizeComparableBoolean(isDeadOrGhost) == true then
            local rawDeadRange, comparableDeadRange = probeSpellRange(self._deadRangeSpellID, unitToken)
            if comparableDeadRange ~= nil then
                return makeStateRecord(rawDeadRange, comparableDeadRange, "dead_spell", eventHintComparable)
            end
        end
    end

    if self._friendlyRangeSpellID then
        local rawSpellRange, comparableSpellRange = probeSpellRange(self._friendlyRangeSpellID, unitToken)
        if comparableSpellRange ~= nil then
            return makeStateRecord(rawSpellRange, comparableSpellRange, "friendly_spell", eventHintComparable)
        end
    end

    local directRange = probeUnitInRange(unitToken)
    if directRange then
        if directRange.checkedComparable ~= false and directRange.rawValue ~= nil then
            if directRange.comparableValue ~= nil then
                return makeStateRecord(directRange.comparableValue, directRange.comparableValue, "unit_in_range", eventHintComparable)
            end

            if eventHintComparable ~= nil then
                return makeStateRecord(eventHintRaw, eventHintComparable, "range_event_hint", eventHintComparable)
            end

            return makeStateRecord(directRange.rawValue, nil, "unit_in_range_secret", eventHintComparable)
        end
    end

    local interactRange = probeInteractRange(unitToken)
    if interactRange ~= nil then
        return makeStateRecord(interactRange, interactRange, "interact", eventHintComparable)
    end

    if eventHintComparable ~= nil then
        return makeStateRecord(eventHintRaw, eventHintComparable, "event_hint", eventHintComparable)
    end

    if previousState and previousState.signature ~= "nil" then
        return makeStateRecord(
            previousState.rawValue,
            previousState.comparableValue,
            "cached_" .. tostring(previousState.source or "range"),
            previousState.eventHintComparable
        )
    end

    return makeStateRecord(nil, nil, "unknown", eventHintComparable)
end

function RangeHandle:RefreshUnitState(unitToken, eventHintRaw, sourceTag)
    if not isGroupUnitToken(unitToken) then
        return false, nil
    end

    if eventHintRaw ~= nil then
        self:SetEventHint(unitToken, eventHintRaw)
    end

    local previousState = self._unitStateByToken[unitToken]
    local nextState = self:ResolveRangeState(unitToken)
    nextState.trigger = sourceTag
    self._unitStateByToken[unitToken] = nextState

    if nextState.source ~= "event_hint"
        and nextState.source ~= "range_event_hint"
        and nextState.source ~= "unit_in_range_secret"
    then
        self._eventHintByUnit[unitToken] = nil
    end

    local previousSignature = previousState and previousState.signature or "nil"
    local changed = previousSignature ~= nextState.signature

    if not changed and previousState and nextState.signature ~= "secret" then
        changed = previousState.comparableValue ~= nextState.comparableValue
    end

    return changed, nextState
end

function RangeHandle:RefreshAllTrackedUnits(sourceTag, refreshOwnersWhenUnchanged)
    local ownerNeedsRefresh = {
        party = refreshOwnersWhenUnchanged == true,
        raid = refreshOwnersWhenUnchanged == true,
    }

    for index = 1, #GROUP_UNIT_TOKENS do
        local unitToken = GROUP_UNIT_TOKENS[index]
        local changed, state = self:RefreshUnitState(unitToken, nil, sourceTag)
        local ownerKey = getOwnerKeyForUnit(unitToken)
        if ownerKey and (changed or (state and state.signature == "secret")) then
            ownerNeedsRefresh[ownerKey] = true
        end
    end

    if ownerNeedsRefresh.party then
        self:NotifyOwnerUnitRefresh("party", nil, true)
    end
    if ownerNeedsRefresh.raid then
        self:NotifyOwnerUnitRefresh("raid", nil, true)
    end
end

function RangeHandle:OnPollTick()
    self:RefreshAllTrackedUnits("poll")
end

function RangeHandle:OnWorldChanged()
    self:RefreshKnownRangeSpells()
    self:ResetRangeState()
    self:RefreshAllTrackedUnits("world", true)
end

function RangeHandle:OnCombatStateChanged()
    self:ResetRangeState()
    self:RefreshAllTrackedUnits("combat", true)
end

function RangeHandle:OnSpellbookChanged(eventName, unitToken)
    if eventName == "PLAYER_SPECIALIZATION_CHANGED" and unitToken ~= "player" then
        return
    end

    self:RefreshKnownRangeSpells()
    self:ResetRangeState()
    self:RefreshAllTrackedUnits("spellbook", true)
end

function RangeHandle:OnSpecChanged(eventName, unitToken)
    self:OnSpellbookChanged(eventName, unitToken)
end

function RangeHandle:OnRangeRelatedUnitEvent(_, unitToken)
    if not isGroupUnitToken(unitToken) then
        return
    end

    local changed, state = self:RefreshUnitState(unitToken, nil, "unit_context")
    local ownerKey = getOwnerKeyForUnit(unitToken)
    if ownerKey and (changed or (state and state.signature == "secret")) then
        self:NotifyOwnerUnitRefresh(ownerKey, unitToken, false)
    end
end

function RangeHandle:OnUnitInRangeUpdate(_, unitToken, eventPayload)
    if not isGroupUnitToken(unitToken) then
        self:RefreshAllTrackedUnits("unit_in_range_broadcast", true)
        return
    end

    local changed, state = self:RefreshUnitState(unitToken, eventPayload, "unit_in_range")
    local ownerKey = getOwnerKeyForUnit(unitToken)
    if not ownerKey then
        return
    end

    if changed or (state and state.signature == "secret") then
        self:NotifyOwnerUnitRefresh(ownerKey, unitToken, false)
    end
end

addon:RegisterModule("rangeHandle", RangeHandle:New())
