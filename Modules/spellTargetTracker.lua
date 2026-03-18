-- ============================================================================
-- MUMMUFRAMES SPELL TARGET TRACKER MODULE
-- ============================================================================
-- Tracks a curated set of Midnight Season 1 dungeon mechanics by watching
-- hostile NPC unit spellcast events, resolving the caster unit, and then scanning the
-- caster's current target until the assigned party member can be determined.
--
-- Midnight-specific implementation notes:
--   * Uses unit spellcast and unit-target APIs only.
--   * Avoids secret-target helpers such as UnitIsSpellTarget.
--   * Limits v1 to curated dungeon spells whose Midnight LittleWigs modules
--     expose concrete cast spell IDs.
-- ============================================================================

local _, ns = ...

local addon = _G.mummuFrames
local Object = ns.Object
local AuraSafety = ns.AuraSafety
local Util = ns.Util

local SpellTargetTracker = Object:Extend()

local PARTY_UNIT_TOKENS = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4",
}

local SOURCE_SCAN_UNITS = {
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5",
    "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10",
    "nameplate11", "nameplate12", "nameplate13", "nameplate14", "nameplate15",
    "nameplate16", "nameplate17", "nameplate18", "nameplate19", "nameplate20",
    "nameplate21", "nameplate22", "nameplate23", "nameplate24", "nameplate25",
    "nameplate26", "nameplate27", "nameplate28", "nameplate29", "nameplate30",
    "nameplate31", "nameplate32", "nameplate33", "nameplate34", "nameplate35",
    "nameplate36", "nameplate37", "nameplate38", "nameplate39", "nameplate40",
    "target",
    "focus",
    "mouseover",
    "softenemy",
}

local DEFAULT_SCAN_WINDOW = 0.8
local DEFAULT_RETRY_DELAY = 0.05
local DEFAULT_LIFETIME = 5.0
local DEBUG_PREFIX = "[SpellTarget]"
local START_CAST_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}

local STOP_CAST_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local TRACKED_SPELLS = {
    [1214032] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 5.0 }, -- Magisters Terrace / Arcanotron Custos / Ethereal Shackles
    [1215087] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 5.0 }, -- Magisters Terrace / Degentrius / Unstable Void Essence
    [1284954] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Magisters Terrace / Gemellus / Cosmic Sting
    [1253709] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 5.0 }, -- Magisters Terrace / Gemellus / Neural Link
    [1225787] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Magisters Terrace / Seranel Sunlash / Runic Mark

    [1266480] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, tankGrace = 0.1, lifetime = 4.0 }, -- Maisara Caverns / Muro'jin and Nekraxx / Flanking Spear
    [1246666] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Muro'jin and Nekraxx / Infected Pinions
    [1260731] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Muro'jin and Nekraxx / Freezing Trap
    [1260643] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Muro'jin and Nekraxx / Barrage
    [1249479] = { trigger = "SPELL_CAST_SUCCESS", scanWindow = 0.6, retryDelay = 0.05, tankGrace = 0.15, lifetime = 1.5 }, -- Maisara Caverns / Muro'jin and Nekraxx / Carrion Swoop
    [1251023] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Raktul / Spiritbreaker
    [1252676] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Raktul / Crush Souls
    [1251554] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Vordaza / Drain Soul
    [1252054] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Maisara Caverns / Vordaza / Unmake

    [1253950] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Nexus Point Xenas / Lothraxion / Searing Rend
    [1253855] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Nexus Point Xenas / Lothraxion / Brilliant Dispersion
    [1247937] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Nexus Point Xenas / Corewarden Nysarra / Umbral Lash
    [1249014] = { trigger = "SPELL_CAST_SUCCESS", scanWindow = 0.6, retryDelay = 0.05, tankGrace = 0.15, lifetime = 1.5 }, -- Nexus Point Xenas / Corewarden Nysarra / Eclipsing Step
    [1264439] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Nexus Point Xenas / Corewarden Nysarra / Lightscar Flare

    [472081] = { trigger = "SPELL_CAST_SUCCESS", scanWindow = 0.6, retryDelay = 0.05, tankGrace = 0.2, lifetime = 1.5 }, -- Windrunner Spire / Commander Kroluk / Reckless Leap
    [1253272] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Commander Kroluk / Intimidating Shout
    [474105] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Derelict Duo / Curse of Darkness
    [466064] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Emberdawn / Searing Beak
    [472662] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Restless Heart / Tempest Slash
    [1253986] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Restless Heart / Gust Shot
    [468429] = { trigger = "SPELL_CAST_START", scanWindow = 0.8, retryDelay = 0.05, lifetime = 4.0 }, -- Windrunner Spire / Restless Heart / Bullseye Windblast
}

local function safeBoolean(value, fallback)
    if Util and type(Util.SafeBoolean) == "function" then
        return Util:SafeBoolean(value, fallback)
    end

    local okEval, evaluated = pcall(function()
        if value then
            return true
        end
        return false
    end)
    if okEval then
        return evaluated == true
    end
    return fallback == true
end

local function safeCallBoolean(apiFn, fallback, ...)
    if type(apiFn) ~= "function" then
        return fallback == true
    end

    local okCall, value = pcall(apiFn, ...)
    if not okCall then
        return fallback == true
    end

    return safeBoolean(value, fallback)
end

local function safeToString(value)
    if value == nil then
        return "nil"
    end

    local okString, asString = pcall(tostring, value)
    if okString and type(asString) == "string" then
        return asString
    end

    return "<?>"
end

local function getUnitGUIDSafe(unitToken)
    if Util and type(Util.GetUnitGUIDSafe) == "function" then
        return Util:GetUnitGUIDSafe(unitToken)
    end

    return nil
end

local function safeUnitExists(unit)
    return safeCallBoolean(UnitExists, false, unit)
end

local function safeUnitCanAttack(attackerUnit, unit)
    return safeCallBoolean(UnitCanAttack, false, attackerUnit, unit)
end

local function safeUnitPlayerControlled(unit)
    return safeCallBoolean(UnitPlayerControlled, false, unit)
end

local function safeUnitIsPlayer(unit)
    return safeCallBoolean(UnitIsPlayer, false, unit)
end

local function safeUnitIsUnit(unitA, unitB)
    return safeCallBoolean(UnitIsUnit, false, unitA, unitB)
end

local function unitsMatch(unitA, unitB)
    if type(unitA) ~= "string" or unitA == "" or type(unitB) ~= "string" or unitB == "" then
        return false
    end
    if unitA == unitB then
        return true
    end

    return safeUnitIsUnit(unitA, unitB)
end

local function isStableSourceUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end

    return string.match(unit, "^boss%d+$") ~= nil
        or string.match(unit, "^nameplate%d+$") ~= nil
end

local function normalizePartyUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    for i = 1, #PARTY_UNIT_TOKENS do
        local partyUnit = PARTY_UNIT_TOKENS[i]
        if unitsMatch(unitToken, partyUnit) then
            return partyUnit
        end
    end

    return nil
end

local function isHostileNpcUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end
    if not safeUnitExists(unit) then
        return false
    end
    if not safeUnitCanAttack("player", unit) then
        return false
    end
    if safeUnitPlayerControlled(unit) then
        return false
    end
    if safeUnitIsPlayer(unit) then
        return false
    end

    return true
end

local function getSpellConfig(spellId)
    local normalizedSpellId = nil
    if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
        normalizedSpellId = AuraSafety:SafeNumber(spellId, nil)
    elseif type(spellId) == "number" then
        local okString, asString = pcall(tostring, spellId)
        if okString and type(asString) == "string" then
            normalizedSpellId = tonumber(asString)
        end
    elseif type(spellId) == "string" then
        normalizedSpellId = tonumber(spellId)
    else
        local okTonumber, coerced = pcall(tonumber, spellId)
        if okTonumber and type(coerced) == "number" then
            normalizedSpellId = coerced
        end
    end

    if type(normalizedSpellId) ~= "number" then
        return nil, nil
    end

    normalizedSpellId = math.floor(normalizedSpellId + 0.5)
    if normalizedSpellId <= 0 then
        return nil, nil
    end

    local config = TRACKED_SPELLS[normalizedSpellId]
    if not config then
        return nil, nil
    end

    config.scanWindow = config.scanWindow or DEFAULT_SCAN_WINDOW
    config.retryDelay = config.retryDelay or DEFAULT_RETRY_DELAY
    config.lifetime = config.lifetime or DEFAULT_LIFETIME
    config.tankGrace = config.tankGrace or 0
    return config, normalizedSpellId
end

local function normalizeSpellId(spellId)
    local _, normalizedSpellId = getSpellConfig(spellId)
    if normalizedSpellId then
        return normalizedSpellId
    end

    if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
        normalizedSpellId = AuraSafety:SafeNumber(spellId, nil)
    else
        local okTonumber, coerced = pcall(tonumber, spellId)
        if okTonumber and type(coerced) == "number" then
            normalizedSpellId = coerced
        end
    end

    if type(normalizedSpellId) ~= "number" then
        return nil
    end

    normalizedSpellId = math.floor(normalizedSpellId + 0.5)
    if normalizedSpellId <= 0 then
        return nil
    end

    return normalizedSpellId
end

local function unitEventMatchesTrigger(eventName, spellInfo)
    if type(eventName) ~= "string" or not spellInfo then
        return false
    end

    if spellInfo.trigger == "SPELL_CAST_SUCCESS" then
        return eventName == "UNIT_SPELLCAST_SUCCEEDED"
    end

    return START_CAST_EVENTS[eventName] == true
end

function SpellTargetTracker:Constructor()
    self.addon = nil
    self.activeCasts = {}
    self.activeCastKeyBySourceSpell = {}
    self.sourceUnitsByGUID = {}
    self.highlightCountsByUnit = {}
    self.scanTicker = nil
end

function SpellTargetTracker:OnInitialize(addonRef)
    self.addon = addonRef
end

function SpellTargetTracker:OnEnable()
    self.activeCasts = {}
    self.activeCastKeyBySourceSpell = {}
    self.sourceUnitsByGUID = {}
    self.highlightCountsByUnit = {}
    self:RegisterEvents()
end

function SpellTargetTracker:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:StopScanTicker()
    self:ClearAllState()
end

function SpellTargetTracker:RegisterEvents()
    -- Midnight-safe path: piggyback on the shared router events that unitFrames,
    -- partyFrames, and raidFrames already keep registered on their persistent
    -- frames. Avoid introducing fresh combat-log/nameplate registrations here.
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnResetEvent)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnResetEvent)
    ns.EventRouter:Register(self, "PLAYER_TARGET_CHANGED", self.OnTargetUnitChanged)
    ns.EventRouter:Register(self, "PLAYER_FOCUS_CHANGED", self.OnFocusUnitChanged)
    ns.EventRouter:Register(self, "UNIT_TARGET", self.OnUnitTarget)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_START", self.OnUnitSpellcastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_START", self.OnUnitSpellcastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_EMPOWER_START", self.OnUnitSpellcastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_SUCCEEDED", self.OnUnitSpellcastSucceeded)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_STOP", self.OnUnitSpellcastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_FAILED", self.OnUnitSpellcastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_INTERRUPTED", self.OnUnitSpellcastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_STOP", self.OnUnitSpellcastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_EMPOWER_STOP", self.OnUnitSpellcastStop)
end

function SpellTargetTracker:EnsureScanTicker()
    if self.scanTicker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end

    self.scanTicker = C_Timer.NewTicker(0.2, function()
        self:OnScanTick()
    end)
end

function SpellTargetTracker:StopScanTicker()
    if not self.scanTicker then
        return
    end

    self.scanTicker:Cancel()
    self.scanTicker = nil
end

-- Enable temporary chat diagnostics with:
-- /run mummuFrames.debugSpellTargetTracker = true
function SpellTargetTracker:IsDebugEnabled()
    return self.addon and self.addon.debugSpellTargetTracker == true
end

function SpellTargetTracker:DebugLog(...)
    if not self:IsDebugEnabled() then
        return
    end

    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = safeToString(select(i, ...))
    end

    local message = DEBUG_PREFIX .. " " .. table.concat(parts, " ")
    if Util and type(Util.Print) == "function" then
        Util:Print(message)
        return
    end

    print(message)
end

function SpellTargetTracker:RefreshAllHighlights()
    local partyFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    if not partyFrames or type(partyFrames.RefreshDisplayedUnitSpellTargetState) ~= "function" then
        return
    end

    for i = 1, #PARTY_UNIT_TOKENS do
        partyFrames:RefreshDisplayedUnitSpellTargetState(PARTY_UNIT_TOKENS[i])
    end
end

function SpellTargetTracker:NotifyHighlightForUnit(unitToken)
    local normalizedUnit = normalizePartyUnitToken(unitToken)
    if not normalizedUnit then
        return
    end

    local partyFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    if not partyFrames or type(partyFrames.RefreshDisplayedUnitSpellTargetState) ~= "function" then
        return
    end

    partyFrames:RefreshDisplayedUnitSpellTargetState(normalizedUnit)
end

function SpellTargetTracker:IncrementHighlight(unitToken)
    local normalizedUnit = normalizePartyUnitToken(unitToken)
    if not normalizedUnit then
        return
    end

    local previous = self.highlightCountsByUnit[normalizedUnit] or 0
    self.highlightCountsByUnit[normalizedUnit] = previous + 1
    if previous == 0 then
        self:NotifyHighlightForUnit(normalizedUnit)
    end
end

function SpellTargetTracker:DecrementHighlight(unitToken)
    local normalizedUnit = normalizePartyUnitToken(unitToken)
    if not normalizedUnit then
        return
    end

    local previous = self.highlightCountsByUnit[normalizedUnit] or 0
    if previous <= 1 then
        self.highlightCountsByUnit[normalizedUnit] = nil
        if previous > 0 then
            self:NotifyHighlightForUnit(normalizedUnit)
        end
        return
    end

    self.highlightCountsByUnit[normalizedUnit] = previous - 1
end

function SpellTargetTracker:ClearAllState()
    local hadHighlights = next(self.highlightCountsByUnit) ~= nil

    self.activeCasts = {}
    self.activeCastKeyBySourceSpell = {}
    self.sourceUnitsByGUID = {}
    self.highlightCountsByUnit = {}

    if hadHighlights then
        self:RefreshAllHighlights()
    end
end

function SpellTargetTracker:RememberSourceUnit(unit)
    local resolvedUnit = self:ResolveBestSourceUnit(unit)
    if not resolvedUnit then
        return nil, nil
    end

    local sourceGUID = getUnitGUIDSafe(resolvedUnit)
    if type(sourceGUID) ~= "string" or sourceGUID == "" then
        return nil, resolvedUnit
    end

    self.sourceUnitsByGUID[sourceGUID] = resolvedUnit
    return sourceGUID, resolvedUnit
end

function SpellTargetTracker:ResolveBestSourceUnit(unit)
    if not isHostileNpcUnit(unit) then
        return nil
    end

    if isStableSourceUnit(unit) then
        return unit
    end

    for i = 1, #SOURCE_SCAN_UNITS do
        local candidate = SOURCE_SCAN_UNITS[i]
        if candidate ~= unit and isStableSourceUnit(candidate) and isHostileNpcUnit(candidate) and unitsMatch(candidate, unit) then
            return candidate
        end
    end

    return unit
end

function SpellTargetTracker:GetSourceUnit(sourceUnit)
    if type(sourceUnit) ~= "string" or sourceUnit == "" then
        return nil
    end

    local rememberedUnit = self.sourceUnitsByGUID[sourceUnit]
    if type(rememberedUnit) == "string" and rememberedUnit ~= "" then
        local rememberedGUID = getUnitGUIDSafe(rememberedUnit)
        if rememberedGUID == sourceUnit and isHostileNpcUnit(rememberedUnit) then
            return self:ResolveBestSourceUnit(rememberedUnit) or rememberedUnit
        end
        self.sourceUnitsByGUID[sourceUnit] = nil
    end

    if type(UnitTokenFromGUID) == "function" then
        local okResolved, resolvedUnit = pcall(UnitTokenFromGUID, sourceUnit)
        if okResolved and type(resolvedUnit) == "string" and resolvedUnit ~= "" then
            local bestUnit = self:ResolveBestSourceUnit(resolvedUnit)
            if bestUnit then
                self.sourceUnitsByGUID[sourceUnit] = bestUnit
                return bestUnit
            end
        end
    end

    for i = 1, #SOURCE_SCAN_UNITS do
        local candidate = SOURCE_SCAN_UNITS[i]
        if getUnitGUIDSafe(candidate) == sourceUnit and isHostileNpcUnit(candidate) then
            local bestUnit = self:ResolveBestSourceUnit(candidate)
            if bestUnit then
                self.sourceUnitsByGUID[sourceUnit] = bestUnit
                return bestUnit
            end
        end
    end

    return nil
end

function SpellTargetTracker:ResolvePartyTargetUnit(sourceUnit)
    if type(sourceUnit) ~= "string" or sourceUnit == "" then
        return nil
    end

    local targetUnit = sourceUnit .. "target"
    if not safeUnitExists(targetUnit) then
        return nil
    end
    if safeUnitCanAttack("player", targetUnit) then
        return nil
    end

    for i = 1, #PARTY_UNIT_TOKENS do
        local partyUnit = PARTY_UNIT_TOKENS[i]
        if safeUnitExists(partyUnit) and safeUnitIsUnit(targetUnit, partyUnit) then
            return partyUnit
        end
    end

    return nil
end

function SpellTargetTracker:IsTankUnit(unitToken)
    return type(unitToken) == "string" and unitToken ~= "" and UnitGroupRolesAssigned(unitToken) == "TANK"
end

function SpellTargetTracker:SetAssignedTarget(castState, unitToken)
    if not castState or type(unitToken) ~= "string" or unitToken == "" then
        return
    end

    local normalizedTargetUnit = normalizePartyUnitToken(unitToken)
    if not normalizedTargetUnit then
        return
    end

    if castState.assignedUnit == normalizedTargetUnit then
        return
    end

    if castState.assignedUnit then
        self:DecrementHighlight(castState.assignedUnit)
    end

    castState.assignedUnit = normalizedTargetUnit
    self:IncrementHighlight(normalizedTargetUnit)
    self:DebugLog(
        "assigned",
        "spell=" .. tostring(castState.spellId),
        "sourceGUID=" .. safeToString(castState.sourceGUID),
        "sourceUnit=" .. safeToString(castState.sourceUnit),
        "target=" .. normalizedTargetUnit
    )
end

function SpellTargetTracker:AttemptResolveCastTarget(castState, now)
    if not castState then
        return
    end

    local sourceUnit = self:GetSourceUnit(castState.sourceGUID)
    if not sourceUnit then
        if castState._debugMissingSource ~= true then
            castState._debugMissingSource = true
            self:DebugLog(
                "waiting_for_source",
                "spell=" .. tostring(castState.spellId),
                "sourceGUID=" .. safeToString(castState.sourceGUID)
            )
        end
        castState.nextScanAt = now + (castState.spellInfo.retryDelay or DEFAULT_RETRY_DELAY)
        return
    end

    if castState._debugMissingSource == true then
        castState._debugMissingSource = false
        self:DebugLog(
            "source_reacquired",
            "spell=" .. tostring(castState.spellId),
            "sourceGUID=" .. safeToString(castState.sourceGUID),
            "sourceUnit=" .. sourceUnit
        )
    end
    if castState.sourceUnit ~= sourceUnit then
        self:DebugLog(
            "source_unit",
            "spell=" .. tostring(castState.spellId),
            "sourceGUID=" .. safeToString(castState.sourceGUID),
            "unit=" .. sourceUnit
        )
    end

    castState.sourceUnit = sourceUnit

    local unitToken = self:ResolvePartyTargetUnit(sourceUnit)
    if unitToken then
        local elapsed = now - castState.startedAt
        if castState.spellInfo.tankGrace > 0 and self:IsTankUnit(unitToken) and elapsed < castState.spellInfo.tankGrace then
            castState.nextScanAt = now + (castState.spellInfo.retryDelay or DEFAULT_RETRY_DELAY)
            return
        end

        self:SetAssignedTarget(castState, unitToken)
    end

    castState.nextScanAt = now + (castState.spellInfo.retryDelay or DEFAULT_RETRY_DELAY)
end

function SpellTargetTracker:ClearCast(castKey, reason)
    local castState = self.activeCasts[castKey]
    if not castState then
        return false
    end

    self.activeCasts[castKey] = nil

    local bySpell = self.activeCastKeyBySourceSpell[castState.sourceGUID]
    if bySpell and bySpell[castState.spellId] == castKey then
        bySpell[castState.spellId] = nil
        if not next(bySpell) then
            self.activeCastKeyBySourceSpell[castState.sourceGUID] = nil
        end
    end

    if castState.assignedUnit then
        self:DecrementHighlight(castState.assignedUnit)
    end

    self:DebugLog(
        "clear",
        "reason=" .. safeToString(reason or "unknown"),
        "spell=" .. tostring(castState.spellId),
        "sourceGUID=" .. safeToString(castState.sourceGUID),
        "sourceUnit=" .. safeToString(castState.sourceUnit),
        "target=" .. safeToString(castState.assignedUnit)
    )

    return true
end

function SpellTargetTracker:ClearCastBySourceSpell(sourceGUID, spellId, reason)
    local normalizedSpellId = normalizeSpellId(spellId)
    if type(sourceGUID) ~= "string" or sourceGUID == "" or type(normalizedSpellId) ~= "number" or normalizedSpellId <= 0 then
        return false
    end

    local bySpell = self.activeCastKeyBySourceSpell[sourceGUID]
    local castKey = bySpell and bySpell[normalizedSpellId] or nil
    if not castKey then
        return false
    end

    return self:ClearCast(castKey, reason)
end

function SpellTargetTracker:ClearCastsForSource(sourceGUID, reason)
    if type(sourceGUID) ~= "string" or sourceGUID == "" then
        return
    end

    local bySpell = self.activeCastKeyBySourceSpell[sourceGUID]
    if not bySpell then
        return
    end

    local keys = {}
    for _, castKey in pairs(bySpell) do
        keys[#keys + 1] = castKey
    end
    for i = 1, #keys do
        self:ClearCast(keys[i], reason)
    end
end

function SpellTargetTracker:GetTrackedSpellForUnitEvent(eventName, unitToken, spellId)
    local _, resolvedSpellId = getSpellConfig(spellId)

    if not resolvedSpellId and START_CAST_EVENTS[eventName] then
        if type(UnitCastingInfo) == "function" then
            local _, normalizedSpellId = getSpellConfig(select(9, UnitCastingInfo(unitToken)))
            resolvedSpellId = normalizedSpellId
        end
        if type(resolvedSpellId) ~= "number" and type(UnitChannelInfo) == "function" then
            local _, normalizedSpellId = getSpellConfig(select(8, UnitChannelInfo(unitToken)))
            resolvedSpellId = normalizedSpellId
        end
    end

    if type(resolvedSpellId) ~= "number" then
        return nil, nil
    end

    local spellInfo = nil
    spellInfo, resolvedSpellId = getSpellConfig(resolvedSpellId)
    if not spellInfo or not unitEventMatchesTrigger(eventName, spellInfo) then
        return nil, nil
    end

    return resolvedSpellId, spellInfo
end

function SpellTargetTracker:BeginTrackingFromUnitEvent(eventName, unitToken, spellId)
    local sourceGUID, sourceUnit = self:RememberSourceUnit(unitToken)
    if not sourceGUID then
        return
    end

    local resolvedSpellId, spellInfo = self:GetTrackedSpellForUnitEvent(eventName, unitToken, spellId)
    if not resolvedSpellId or not spellInfo then
        return
    end

    self:BeginCastTracking(sourceGUID, resolvedSpellId, spellInfo, sourceUnit)
end

function SpellTargetTracker:BeginCastTracking(sourceGUID, spellId, spellInfo, sourceUnit)
    local resolvedSpellInfo = spellInfo
    local normalizedSpellId = spellId
    if not resolvedSpellInfo or type(normalizedSpellId) ~= "number" then
        resolvedSpellInfo, normalizedSpellId = getSpellConfig(spellId)
    end

    if type(sourceGUID) ~= "string" or sourceGUID == "" or type(normalizedSpellId) ~= "number" or not resolvedSpellInfo then
        return
    end

    self:ClearCastBySourceSpell(sourceGUID, normalizedSpellId, "restart")

    local now = GetTime()
    local castKey = sourceGUID .. ":" .. tostring(normalizedSpellId)
    local castState = {
        castKey = castKey,
        sourceGUID = sourceGUID,
        spellId = normalizedSpellId,
        spellInfo = resolvedSpellInfo,
        startedAt = now,
        expiresAt = now + (resolvedSpellInfo.scanWindow or DEFAULT_SCAN_WINDOW),
        hardExpireAt = now + (resolvedSpellInfo.lifetime or DEFAULT_LIFETIME),
        nextScanAt = now,
        assignedUnit = nil,
        sourceUnit = type(sourceUnit) == "string" and sourceUnit ~= "" and sourceUnit or nil,
        _debugMissingSource = false,
    }

    self.activeCasts[castKey] = castState
    self.activeCastKeyBySourceSpell[sourceGUID] = self.activeCastKeyBySourceSpell[sourceGUID] or {}
    self.activeCastKeyBySourceSpell[sourceGUID][normalizedSpellId] = castKey

    self:DebugLog(
        "begin",
        "event_spell=" .. tostring(normalizedSpellId),
        "sourceGUID=" .. safeToString(sourceGUID),
        "sourceUnit=" .. safeToString(sourceUnit)
    )

    self:AttemptResolveCastTarget(castState, now)
    self:EnsureScanTicker()
end

function SpellTargetTracker:OnScanTick()
    local now = GetTime()
    local hasActiveCasts = false
    local keysToClear = nil

    for castKey, castState in pairs(self.activeCasts) do
        hasActiveCasts = true

        if castState.assignedUnit then
            if now >= castState.hardExpireAt then
                keysToClear = keysToClear or {}
                keysToClear[#keysToClear + 1] = {
                    castKey = castKey,
                    reason = "hard_expire",
                }
            elseif now >= (castState.nextScanAt or 0) then
                self:AttemptResolveCastTarget(castState, now)
            end
        else
            if now >= castState.expiresAt then
                keysToClear = keysToClear or {}
                keysToClear[#keysToClear + 1] = {
                    castKey = castKey,
                    reason = "unresolved_expire",
                }
            elseif now >= (castState.nextScanAt or 0) then
                self:AttemptResolveCastTarget(castState, now)
            end
        end
    end

    if keysToClear then
        for i = 1, #keysToClear do
            local clearInfo = keysToClear[i]
            self:ClearCast(clearInfo.castKey, clearInfo.reason)
        end
    end

    if not hasActiveCasts or not next(self.activeCasts) then
        self:StopScanTicker()
    end
end

function SpellTargetTracker:IsUnitSpellTarget(unitToken)
    local normalizedUnit = normalizePartyUnitToken(unitToken)
    if not normalizedUnit then
        return false
    end

    return (self.highlightCountsByUnit[normalizedUnit] or 0) > 0
end

function SpellTargetTracker:RefreshSourceScansForUnit(unit)
    local sourceGUID = self:RememberSourceUnit(unit)
    if not sourceGUID then
        return
    end

    local bySpell = self.activeCastKeyBySourceSpell[sourceGUID]
    if not bySpell then
        return
    end

    local now = GetTime()
    for _, castKey in pairs(bySpell) do
        local castState = self.activeCasts[castKey]
        if castState then
            castState.nextScanAt = now
            self:AttemptResolveCastTarget(castState, now)
        end
    end
end

function SpellTargetTracker:OnResetEvent()
    self:DebugLog("reset")
    self:StopScanTicker()
    self:ClearAllState()
end

function SpellTargetTracker:OnUnitTarget(_, unit)
    self:RefreshSourceScansForUnit(unit)
end

function SpellTargetTracker:OnTargetUnitChanged()
    self:RefreshSourceScansForUnit("target")
end

function SpellTargetTracker:OnFocusUnitChanged()
    self:RefreshSourceScansForUnit("focus")
end

function SpellTargetTracker:OnUnitSpellcastStart(eventName, unitToken, _, spellId)
    self:BeginTrackingFromUnitEvent(eventName, unitToken, spellId)
end

function SpellTargetTracker:OnUnitSpellcastSucceeded(eventName, unitToken, _, spellId)
    local sourceGUID, sourceUnit = self:RememberSourceUnit(unitToken)
    local spellInfo, normalizedSpellId = getSpellConfig(spellId)
    if not sourceGUID or type(normalizedSpellId) ~= "number" then
        return
    end

    if spellInfo and unitEventMatchesTrigger(eventName, spellInfo) then
        self:BeginCastTracking(sourceGUID, normalizedSpellId, spellInfo, sourceUnit)
        return
    end

    self:ClearCastBySourceSpell(sourceGUID, normalizedSpellId, "succeeded_cleanup")
end

function SpellTargetTracker:OnUnitSpellcastStop(eventName, unitToken, _, spellId)
    if not STOP_CAST_EVENTS[eventName] then
        return
    end

    local sourceGUID = self:RememberSourceUnit(unitToken)
    if not sourceGUID then
        return
    end

    local normalizedSpellId = normalizeSpellId(spellId)
    if type(normalizedSpellId) == "number" and normalizedSpellId > 0 and self:ClearCastBySourceSpell(sourceGUID, normalizedSpellId, eventName) then
        return
    end

    self:ClearCastsForSource(sourceGUID, eventName)
end

addon:RegisterModule("spellTargetTracker", SpellTargetTracker:New())
