-- AuraHandle.lua
-- Manages aura/buff caching, player-cast HoT indicators, dispel overlays, and
-- the suppression of Blizzard's compact unit frames when mummuFrames replaces them.
--
-- Architecture overview:
--   * A hook on CompactUnitFrame_UpdateAuras still populates blizzardAuraCacheByUnit
--     for tracked helpful buffs and centre defensive indicators that intentionally
--     mirror Blizzard compact-frame behaviour.
--   * Group debuffs now use a dedicated per-unit cache driven by UNIT_AURA
--     updateInfo and C_UnitAuras slot scans, so party/raid debuff icons and the
--     dispel overlay no longer depend on hidden Blizzard compact frames staying
--     current in combat.
--   * Per-unit UNIT_AURA dispatcher frames drive indicator refreshes directly,
--     bypassing Blizzard's compact frame hook path when rendering debuff state.
--   * A shared unitToken→frame map (sharedUnitFrameMap) lets the dispatcher
--     locate the mummu frame for any group unit without scanning every frame.
--   * HoT/buff indicators query current unit auras directly and prefer
--     player-owned matches for configured whitelist spells.

local _, ns = ...

local Util  = ns.Util
local Style = ns.Style
local AuraSafety = ns.AuraSafety


-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local MAX_AURA_SCAN        = 80
local DEFAULT_AURA_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local DISPEL_OVERLAY_ALPHA = 0.32
local GROUP_AURA_SLOT_BATCH_SIZE = 16
local GROUP_AURA_SLOT_SCAN_GUARD = 8

-- Maximum pool sizes used when enumerating Blizzard's compact unit frames.
local MAX_BLIZZARD_PARTY_FRAMES       = 5
local MAX_BLIZZARD_RAID_FRAMES        = 40
local MAX_BLIZZARD_RAID_GROUPS        = 8
local MAX_BLIZZARD_RAID_GROUP_MEMBERS = 5

-- Minimum time between automatic shared-map rebuilds (seconds).
local SHARED_MAP_SELF_HEAL_THROTTLE = 1.0
-- Minimum time between routine shared-map rebuilds (seconds).
local MAP_REBUILD_THROTTLE          = 0.20

-- Maximum number of player-cast buff icons shown per frame.
local MAX_TRACKER_AURAS    = 4
-- Default tracker icon size in pixels.
local DEFAULT_TRACKER_SIZE = (Util and type(Util.GetTrackedAuraDefaultSize) == "function" and Util:GetTrackedAuraDefaultSize()) or 14
local GROUP_DEBUFF_BUTTON_GAP = 2
local GROUP_DEBUFF_MAX_BUTTONS = 8
local CENTER_DEFENSIVE_MIN_SIZE = 16
local CENTER_DEFENSIVE_MAX_SIZE = 30
local CENTER_DEFENSIVE_BACKDROP_COLOR = { 0.03, 0.04, 0.06, 0.72 }
local CENTER_DEFENSIVE_BORDER_COLOR_PERSONAL = { 0.28, 0.82, 1.00, 0.95 }
local CENTER_DEFENSIVE_BORDER_COLOR_EXTERNAL = { 1.00, 0.76, 0.24, 0.95 }
local CENTER_DEFENSIVE_BORDER_COLOR_UNKNOWN  = { 0.88, 0.90, 0.94, 0.90 }
-- Whitelist lookups prefer the PLAYER filter so same-spell buffs from other
-- players do not satisfy the tracker. A broader HELPFUL scan remains as
-- fallback when ownership metadata is more reliable than the filter path.
local TRACKER_PLAYER_HELPFUL_FILTER = "HELPFUL|PLAYER|RAID_IN_COMBAT"
local TRACKER_HELPFUL_FILTER        = "HELPFUL|RAID_IN_COMBAT"
-- Midnight-era group aura consumers in other addons successfully rely on
-- INCLUDE_NAME_PLATE_ONLY with C_UnitAuras slot enumeration. We keep a plain
-- HARMFUL fallback so the cache still works if Blizzard changes the stricter
-- filter path again.
local GROUP_HARMFUL_FILTER          = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
local GROUP_HARMFUL_FALLBACK_FILTER = "HARMFUL"
local GROUP_DISPELLABLE_FILTER          = "HARMFUL|INCLUDE_NAME_PLATE_ONLY|RAID_PLAYER_DISPELLABLE"
local GROUP_DISPELLABLE_FALLBACK_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
-- This is only a safety net for missed UNIT_AURA events; normal combat updates
-- should keep the cache fresh long before the fallback window elapses.
local DEBUFF_CACHE_STALE_WINDOW     = 15.0
local DISPEL_TYPE_PRIORITY  = { "Magic", "Curse", "Poison", "Disease" }
local DISPEL_INDEX_BY_NAME = {
    None = 0,
    Magic = 1,
    Curse = 2,
    Disease = 3,
    Poison = 4,
}
local TRACKER_SPELL_ID_OVERRIDES_BY_NAME = {
    -- Retail/Midnight can surface tracked healer buffs on units through
    -- alternate aura spellIDs even though spell-name resolution typically
    -- returns only the base cast or passive spell.
    ["Renewing Mist"] = { 119611, 281231 },
    ["Atonement"] = { 194384, 81749, 81751 },
    ["Prayer of Mending"] = { 41635, 33076, 33110, 123259, 319912 },
}
local DEFAULT_GROUP_DEBUFF_CONFIG_BY_OWNER = {
    party = {
        enabled = true,
        anchorPoint = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -4,
        size = 16,
        scale = 1,
        max = 4,
        hidePermanent = false,
        hideLongDuration = false,
        maxDurationSeconds = 60,
    },
    raid = {
        enabled = true,
        anchorPoint = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -3,
        size = 12,
        scale = 1,
        max = 3,
        hidePermanent = false,
        hideLongDuration = false,
        maxDurationSeconds = 60,
    },
}


-- Events that the group-level dispatcher listens for (UNIT_AURA is handled by
-- per-unit dispatcher frames to allow RegisterUnitEvent filtering).
local GROUP_EVENT_NAMES = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE",
    "UNIT_CONNECTION",
    "UNIT_IN_RANGE_UPDATE",
    "UNIT_FLAGS",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_AURA",
    "INCOMING_SUMMON_CHANGED",
}

local UNIT_FILTERED_GROUP_EVENT_NAMES = {
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_POWER_UPDATE = true,
    UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true,
    UNIT_NAME_UPDATE = true,
    UNIT_CONNECTION = true,
    UNIT_IN_RANGE_UPDATE = true,
    UNIT_FLAGS = true,
    UNIT_ABSORB_AMOUNT_CHANGED = true,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
    INCOMING_SUMMON_CHANGED = true,
}

local RAID_IGNORED_VITALS_EVENT_NAMES = {
    UNIT_POWER_UPDATE = true,
    UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true,
    INCOMING_SUMMON_CHANGED = true,
}

-- All group unit tokens: player + party1-4 + raid1-40.
local GROUP_UNIT_TOKENS = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4",
}
for raidIndex = 1, 40 do
    GROUP_UNIT_TOKENS[#GROUP_UNIT_TOKENS + 1] = "raid" .. tostring(raidIndex)
end

-- RegisterUnitEvent only tracks a small number of units per frame reliably,
-- so group members are split into Blizzard-safe chunks instead of one large
-- player/party/raid registration.
local GROUP_EVENT_UNIT_CHUNKS = {
    { "player" },
    { "party1", "party2", "party3", "party4" },
}
for raidIndex = 1, 40, 4 do
    local unitChunk = {}
    for offset = 0, 3 do
        unitChunk[#unitChunk + 1] = "raid" .. tostring(raidIndex + offset)
    end
    GROUP_EVENT_UNIT_CHUNKS[#GROUP_EVENT_UNIT_CHUNKS + 1] = unitChunk
end

local function tryRegisterFilteredGroupEvent(frame, eventName, unitTokens, unpackGroupUnits)
    if
        type(frame) ~= "table"
        or type(eventName) ~= "string"
        or UNIT_FILTERED_GROUP_EVENT_NAMES[eventName] ~= true
        or type(unitTokens) ~= "table"
        or type(frame.RegisterUnitEvent) ~= "function"
        or type(unpackGroupUnits) ~= "function"
    then
        return false
    end

    local okRegistered = pcall(frame.RegisterUnitEvent, frame, eventName, unpackGroupUnits(unitTokens))
    return okRegistered == true
end

local function shouldSkipGroupVitalsRefresh(ownerKey, eventName)
    if eventName == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        return true
    end

    if ownerKey == "raid" and RAID_IGNORED_VITALS_EVENT_NAMES[eventName] == true then
        return true
    end

    return false
end

-- Refresh descriptor passed to frame modules for non-aura unit events: only
-- vitals (health, power, name, …) need updating, not aura indicators.
local VITALS_ONLY_REFRESH = {
    vitals = true,
    auras  = false,
}

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------

local AuraHandle = ns.Object:Extend()

-- Per-unit aura cache populated by the Blizzard compact-frame hook.
-- This remains useful for visuals that intentionally mirror Blizzard compact
-- frames, such as tracked helpful buffs and the centre defensive indicator.
-- Group debuff rows and dispel overlays are authoritative in
-- groupDebuffStateByUnit instead.
-- blizzardAuraCacheByUnit[unitToken] = {
--   buffs            : { [auraInstanceID] = true }
--   debuffs          : { [auraInstanceID] = true }
--   debuffTypeByAuraID           : { [auraInstanceID] = "Magic"|"Curse"|"Poison"|"Disease" }
--   debuffTypeSet                : { Magic=true, Curse=true, Poison=true, Disease=true }
--   playerDispellable: { [auraInstanceID] = true }
--   playerDispellableTypeByAuraID: { [auraInstanceID] = "Magic"|"Curse"|"Poison"|"Disease" }
--   playerDispellableTypeSet      : { Magic=true, Curse=true, Poison=true, Disease=true }
--   defensives       : { [auraInstanceID] = true }
--   updatedAt        : number  (GetTime() at last capture)
-- }
local blizzardAuraCacheByUnit = {}

-- Dedicated group debuff cache populated from live C_UnitAuras reads.
-- groupDebuffStateByUnit[unitToken] = {
--   harmful = {
--     auras          : { [auraInstanceID] = auraData }
--     order          : { auraInstanceID, ... }
--     indexByAuraID  : { [auraInstanceID] = orderIndex }
--     dispelTypeByAuraID : { [auraInstanceID] = "Magic"|"Curse"|"Poison"|"Disease" }
--     dispelTypeCount    : { Magic=number, Curse=number, Poison=number, Disease=number }
--   }
--   dispellable = { same shape as harmful }
--   revision     : number  (incremented on any harmful/dispellable change)
--   updatedAt    : number  (GetTime() at last successful update)
--   lastFullScanAt : number
--   lastDeltaAt    : number
--   lastSource     : string
-- }
local groupDebuffStateByUnit = {}

-- Whether Blizzard's compact party/raid frames are currently suppressed.
local blizzardFramesHiddenByOwner = {
    party = false,
    raid  = false,
}

-- Set of Blizzard compact frames whose event registration has been stripped
-- down to just UNIT_AURA (to reduce Blizzard overhead while we're replacing them).
local strippedCompactFrames = {}

-- Shared unitToken → mummu-frame mapping, rebuilt on roster/world changes.
local sharedUnitFrameMap        = {}  -- [unitToken] = frame
local sharedUnitOwnerMap        = {}  -- [unitToken] = "party" | "raid"
local sharedDisplayedUnitByGUID = {}  -- [guid]      = unitToken
local sharedMapLastBuiltAt      = 0
local sharedMapLastSelfHealAt   = 0

-- Guards against installing Blizzard hooks more than once.
local blizzardHooksInstalled = false
local blizzardHookState = {
    updateAuras      = false,
    updateUnitEvents = false,
}

-- Bootstrap frame token: incremented each time a new bootstrap sequence is
-- started so that stale C_Timer callbacks can detect they are outdated.
local cacheBootstrapToken = 0

-- Persistent WoW frames created at construction time.
local cacheBootstrapFrame      = nil
local groupDispatcherFrames    = {}
local unitAuraDispatcherFrames = {}
local clearGroupDebuffState

-- Pre-resolved icon textures for whitelisted spell names (spellName → texture path).
-- Built by RebuildSpellIconCache outside combat so the hot path never reads
-- tainted auraData.icon fields.
local _spellIconCache = {}
local _trackerSpellInfoCache = {}
local _groupDispelColorCurve = nil

-- ---------------------------------------------------------------------------
-- Pure helper functions
-- ---------------------------------------------------------------------------

-- Safely wipe a table that may not yet be initialised.
local function wipeTable(tbl)
    if type(tbl) == "table" then
        wipe(tbl)
    end
end

-- Returns GetTime() or 0 if the API is unavailable (e.g. during early load).
local function getSafeNowSeconds()
    if type(GetTime) ~= "function" then
        return 0
    end
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then
        return now
    end
    return 0
end

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

-- Coerces a value to a positive integer spell ID.
-- Aura payload spell IDs can be protected in combat, so normalization routes
-- through AuraSafety when available instead of assuming raw numeric values are
-- safe to compare or use as table keys.
local function normalizeSpellID(value)
    local numeric = nil
    if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
        numeric = AuraSafety:SafeNumber(value, nil)
    elseif type(value) == "number" then
        local okString, asString = pcall(tostring, value)
        if okString and type(asString) == "string" then
            numeric = tonumber(asString)
        end
    elseif type(value) == "string" then
        numeric = tonumber(value)
    else
        local okTonumber, coerced = pcall(tonumber, value)
        if okTonumber and type(coerced) == "number" then
            numeric = coerced
        end
    end
    if type(numeric) ~= "number" then
        return nil
    end
    local rounded = math.floor(numeric + 0.5)
    if rounded <= 0 then
        return nil
    end
    return rounded
end

-- Append a spell ID once after normalizing it through AuraSafety rules.
local function addUniqueSpellID(targetList, seen, spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID then
        return
    end
    if seen[normalizedSpellID] == true then
        return
    end
    seen[normalizedSpellID] = true
    targetList[#targetList + 1] = normalizedSpellID
end

-- Resolve spell info by name using modern APIs first, then legacy fallback.
local function getResolvedSpellInfo(query)
    local queryType = type(query)
    if queryType == "string" and query == "" then
        return nil
    end
    if queryType ~= "string" and queryType ~= "number" then
        return nil
    end

    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local okInfo, info = pcall(C_Spell.GetSpellInfo, query)
        if okInfo and type(info) == "table" then
            return info
        end
    end

    if type(GetSpellInfo) == "function" then
        local okLegacy, spellName, _, iconTexture, castTime, minRange, maxRange, spellID, originalIconID =
            pcall(GetSpellInfo, query)
        if okLegacy and type(spellName) == "string" and spellName ~= "" then
            return {
                name = spellName,
                iconID = iconTexture,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID = spellID,
                originalIconID = originalIconID,
            }
        end
    end

    return nil
end

-- Build the dispel-color curve expected by C_UnitAuras.GetAuraDispelTypeColor.
local function getGroupDispelColorCurve()
    if _groupDispelColorCurve ~= nil then
        return _groupDispelColorCurve or nil
    end
    _groupDispelColorCurve = false

    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function") then
        return nil
    end

    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then
        return nil
    end
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and type(curve.SetType) == "function" then
        curve:SetType(Enum.LuaCurveType.Step)
    end

    local debuffColorsByIndex = {
        [DISPEL_INDEX_BY_NAME.None] = _G.DEBUFF_TYPE_NONE_COLOR,
        [DISPEL_INDEX_BY_NAME.Magic] = _G.DEBUFF_TYPE_MAGIC_COLOR,
        [DISPEL_INDEX_BY_NAME.Curse] = _G.DEBUFF_TYPE_CURSE_COLOR,
        [DISPEL_INDEX_BY_NAME.Disease] = _G.DEBUFF_TYPE_DISEASE_COLOR,
        [DISPEL_INDEX_BY_NAME.Poison] = _G.DEBUFF_TYPE_POISON_COLOR,
    }

    for dispelIndex, colorValue in pairs(debuffColorsByIndex) do
        if colorValue and type(curve.AddPoint) == "function" then
            curve:AddPoint(dispelIndex, colorValue)
        end
    end

    _groupDispelColorCurve = curve
    return curve
end

-- Coerce any aura-instance-like input to a positive integer ID.
local function normalizeAuraInstanceID(value)
    local numeric = nil
    if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
        numeric = AuraSafety:SafeNumber(value, nil)
    elseif type(value) == "number" then
        local okString, asString = pcall(tostring, value)
        if okString and type(asString) == "string" then
            numeric = tonumber(asString)
        end
    elseif type(value) == "string" then
        numeric = tonumber(value)
    else
        local okTonumber, coerced = pcall(tonumber, value)
        if okTonumber and type(coerced) == "number" then
            numeric = coerced
        end
    end
    if type(numeric) ~= "number" then
        return nil
    end
    local rounded = math.floor(numeric + 0.5)
    if rounded <= 0 then
        return nil
    end
    return rounded
end

-- Coerce numeric-like aura payload fields without letting secret wrappers leak
-- into render code that performs comparisons or cooldown math.
local function getSafeAuraNumericValue(value, fallback)
    if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
        return AuraSafety:SafeNumber(value, fallback)
    end
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
    local okTonumber, coerced = pcall(tonumber, value)
    if okTonumber and type(coerced) == "number" then
        return coerced
    end
    return fallback
end

-- Resolve the most reliable icon texture for a tracked aura.
-- Prefer cached spell-database icons, then spellID lookups from the live aura,
-- then the raw aura icon payload, and only finally the question-mark fallback.
local function resolveTrackedAuraIcon(spellName, trackedSpellInfo, auraData)
    if type(trackedSpellInfo) == "table" and trackedSpellInfo.icon then
        return trackedSpellInfo.icon
    end

    if type(spellName) == "string" and spellName ~= "" then
        local cachedIcon = _spellIconCache[spellName]
        if cachedIcon then
            return cachedIcon
        end
    end

    if type(auraData) == "table" then
        local auraSpellID = normalizeSpellID(auraData.spellId)
        if auraSpellID then
            local resolvedInfo = getResolvedSpellInfo(auraSpellID)
            local resolvedIcon = resolvedInfo and (resolvedInfo.iconID or resolvedInfo.originalIconID) or nil
            if resolvedIcon then
                return resolvedIcon
            end
        end

        if auraData.icon then
            return auraData.icon
        end
    end

    return DEFAULT_AURA_TEXTURE
end

-- Returns the canonical unit token if it is a valid group token
-- ("player", "partyN", "raidN"), or nil otherwise.
local function normalizeGroupUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if unitToken == "player" then
        return unitToken
    end
    if string.match(unitToken, "^party%d+$") then
        return unitToken
    end
    if string.match(unitToken, "^raid%d+$") then
        return unitToken
    end
    return nil
end

-- Returns true when ownerKey is a recognised group owner ("party" or "raid").
local function isGroupOwner(ownerKey)
    return ownerKey == "party" or ownerKey == "raid"
end

-- Returns the owner key for a group unit token, or nil.
local function inferOwnerForUnit(unitToken)
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

-- Returns the set of debuff types the player can dispel, keyed by type string.
-- Unknown classes receive the full set as a safe fallback.
local function getPlayerDispelTypeSet()
    local _, classToken = UnitClass("player")
    local set = {}

    if classToken == "PRIEST" then
        set.Magic   = true
        set.Disease = true
    elseif classToken == "PALADIN" then
        set.Poison  = true
        set.Disease = true
        set.Magic   = true
    elseif classToken == "SHAMAN" then
        set.Curse = true
        set.Magic = true
    elseif classToken == "DRUID" then
        set.Curse  = true
        set.Poison = true
        set.Magic  = true
    elseif classToken == "MONK" then
        set.Poison  = true
        set.Disease = true
        set.Magic   = true
    elseif classToken == "MAGE" then
        set.Curse = true
    elseif classToken == "EVOKER" then
        set.Poison = true
    else
        -- Unknown class: grant the full set so indicators still display.
        set.Magic   = true
        set.Curse   = true
        set.Poison  = true
        set.Disease = true
    end

    return set
end

-- Returns a canonical dispel type literal ("Magic", "Curse", "Poison", "Disease")
-- or nil. Compares in pcall so secret values never escape as table keys.
local function normalizeDispelType(value)
    local okMagic, isMagic = pcall(function()
        return value == "Magic"
    end)
    if okMagic and isMagic then
        return "Magic"
    end

    local okCurse, isCurse = pcall(function()
        return value == "Curse"
    end)
    if okCurse and isCurse then
        return "Curse"
    end

    local okPoison, isPoison = pcall(function()
        return value == "Poison"
    end)
    if okPoison and isPoison then
        return "Poison"
    end

    local okDisease, isDisease = pcall(function()
        return value == "Disease"
    end)
    if okDisease and isDisease then
        return "Disease"
    end

    return nil
end

-- Evaluate a boolean-like value without propagating secret-value errors.
local function safeTruthy(value)
    if AuraSafety and type(AuraSafety.SafeTruthy) == "function" then
        return AuraSafety:SafeTruthy(value)
    end
    local ok, resolved = pcall(function()
        return value == true
    end)
    return ok and resolved == true
end

-- Compare two values inside pcall so protected payloads never explode.
local function safeValueEquals(leftValue, rightValue)
    local ok, resolved = pcall(function()
        return leftValue == rightValue
    end)
    return ok and resolved == true
end

-- Read a dispel type from a Blizzard compact-frame debuff widget, if present.
local function extractDispelTypeFromCompactDebuffFrame(debuffFrame)
    if type(debuffFrame) ~= "table" then
        return nil
    end

    local directType = normalizeDispelType(debuffFrame.dispelType or debuffFrame.debuffType or debuffFrame.dispelName)
    if directType then
        return directType
    end

    if type(debuffFrame.GetAttribute) == "function" then
        local ok, attrType = pcall(debuffFrame.GetAttribute, debuffFrame, "debuffType")
        if ok then
            return normalizeDispelType(attrType)
        end
    end

    return nil
end

-- Mirror Blizzard's compact-frame dispel flags into a canonical type set.
local function captureDispelTypeFlagsFromCompactFrame(frame, dispelTypeSet)
    if type(frame) ~= "table" or type(dispelTypeSet) ~= "table" then
        return
    end

    if safeTruthy(frame.hasDispelMagic) or safeTruthy(frame.hasMagicDispel) then
        dispelTypeSet.Magic = true
    end
    if safeTruthy(frame.hasDispelCurse) or safeTruthy(frame.hasCurseDispel) then
        dispelTypeSet.Curse = true
    end
    if safeTruthy(frame.hasDispelPoison) or safeTruthy(frame.hasPoisonDispel) then
        dispelTypeSet.Poison = true
    end
    if safeTruthy(frame.hasDispelDisease) or safeTruthy(frame.hasDiseaseDispel) then
        dispelTypeSet.Disease = true
    end
end

-- Ensures blizzardAuraCacheByUnit[unitToken] exists and returns it.
local function ensureUnitCache(unitToken)
    local cache = blizzardAuraCacheByUnit[unitToken]
    if type(cache) ~= "table" then
        cache = {}
        blizzardAuraCacheByUnit[unitToken] = cache
    end

    cache.buffs = cache.buffs or {}
    cache.debuffs = cache.debuffs or {}
    cache.debuffTypeByAuraID = cache.debuffTypeByAuraID or {}
    cache.debuffTypeSet = cache.debuffTypeSet or {}
    cache.playerDispellable = cache.playerDispellable or {}
    cache.playerDispellableTypeByAuraID = cache.playerDispellableTypeByAuraID or {}
    cache.playerDispellableTypeSet = cache.playerDispellableTypeSet or {}
    cache.defensives = cache.defensives or {}
    if type(cache.updatedAt) ~= "number" then
        cache.updatedAt = 0
    end

    return cache
end

-- Return true when Blizzard marks a slot-query payload as secret.
-- Group debuff tracking prefers direct C_UnitAuras reads over fail-closed
-- C_Secrets checks so a single API mismatch cannot blank the whole indicator.
local function isSecretAuraValue(value)
    local secretCheck = _G.issecretvalue
    if type(secretCheck) ~= "function" then
        return false
    end

    local okSecret, isSecret = pcall(secretCheck, value)
    return okSecret and isSecret == true
end

-- Create one ordered aura bucket used by the shared group debuff cache.
local function createGroupDebuffBucket()
    return {
        auras = {},
        order = {},
        indexByAuraID = {},
        dispelTypeByAuraID = {},
        dispelTypeCount = {},
    }
end

-- Ensures groupDebuffStateByUnit[unitToken] exists and returns it.
local function ensureGroupDebuffState(unitToken)
    local state = groupDebuffStateByUnit[unitToken]
    if type(state) ~= "table" then
        state = {}
        groupDebuffStateByUnit[unitToken] = state
    end

    state.harmful = state.harmful or createGroupDebuffBucket()
    state.dispellable = state.dispellable or createGroupDebuffBucket()
    if type(state.revision) ~= "number" then
        state.revision = 0
    end
    if type(state.updatedAt) ~= "number" then
        state.updatedAt = 0
    end
    if type(state.lastFullScanAt) ~= "number" then
        state.lastFullScanAt = 0
    end
    if type(state.lastDeltaAt) ~= "number" then
        state.lastDeltaAt = 0
    end
    if type(state.lastSource) ~= "string" then
        state.lastSource = "unset"
    end

    return state
end

-- Clears one ordered aura bucket in-place without reallocating its tables.
local function resetGroupDebuffBucket(bucket)
    if type(bucket) ~= "table" then
        return
    end

    wipeTable(bucket.auras)
    wipeTable(bucket.indexByAuraID)
    wipeTable(bucket.dispelTypeByAuraID)
    wipeTable(bucket.dispelTypeCount)
    if type(bucket.order) == "table" then
        for index = #bucket.order, 1, -1 do
            bucket.order[index] = nil
        end
    end
    bucket._orderDirty = nil
end

-- Rebuild the dense aura order after removals.
local function compactGroupDebuffBucket(bucket)
    if type(bucket) ~= "table"
        or bucket._orderDirty ~= true
        or type(bucket.order) ~= "table"
        or type(bucket.indexByAuraID) ~= "table"
        or type(bucket.auras) ~= "table"
    then
        return
    end

    wipeTable(bucket.indexByAuraID)

    local writeIndex = 1
    for readIndex = 1, #bucket.order do
        local auraInstanceID = bucket.order[readIndex]
        if auraInstanceID and bucket.auras[auraInstanceID] and not bucket.indexByAuraID[auraInstanceID] then
            bucket.order[writeIndex] = auraInstanceID
            bucket.indexByAuraID[auraInstanceID] = writeIndex
            writeIndex = writeIndex + 1
        end
    end
    for clearIndex = writeIndex, #bucket.order do
        bucket.order[clearIndex] = nil
    end

    bucket._orderDirty = nil
end

-- Apply a typed dispel-name change to a bucket without leaving stale type counts.
local function setBucketDispelType(bucket, auraInstanceID, dispelType)
    if type(bucket) ~= "table" or auraInstanceID == nil then
        return
    end

    local oldType = bucket.dispelTypeByAuraID[auraInstanceID]
    if oldType == dispelType then
        return
    end

    if oldType then
        local remaining = (tonumber(bucket.dispelTypeCount[oldType]) or 0) - 1
        if remaining > 0 then
            bucket.dispelTypeCount[oldType] = remaining
        else
            bucket.dispelTypeCount[oldType] = nil
        end
        bucket.dispelTypeByAuraID[auraInstanceID] = nil
    end

    if dispelType then
        bucket.dispelTypeByAuraID[auraInstanceID] = dispelType
        bucket.dispelTypeCount[dispelType] = (tonumber(bucket.dispelTypeCount[dispelType]) or 0) + 1
    end
end

-- Insert or replace one aura inside an ordered bucket.
local function storeAuraInGroupDebuffBucket(bucket, auraData)
    if type(bucket) ~= "table" or type(auraData) ~= "table" then
        return false
    end

    local auraInstanceID = normalizeAuraInstanceID(auraData.auraInstanceID)
    if not auraInstanceID then
        return false
    end

    local existingAura = bucket.auras[auraInstanceID]
    bucket.auras[auraInstanceID] = auraData
    if not bucket.indexByAuraID[auraInstanceID] then
        bucket.order[#bucket.order + 1] = auraInstanceID
        bucket.indexByAuraID[auraInstanceID] = #bucket.order
    end

    setBucketDispelType(bucket, auraInstanceID, normalizeDispelType(auraData.dispelName))
    return existingAura ~= auraData
end

-- Remove one aura from an ordered bucket and flag the sparse order for compaction.
local function removeAuraFromGroupDebuffBucket(bucket, auraInstanceID)
    if type(bucket) ~= "table" then
        return false
    end

    local normalizedAuraInstanceID = normalizeAuraInstanceID(auraInstanceID)
    if not normalizedAuraInstanceID then
        return false
    end

    local hadAura = bucket.auras[normalizedAuraInstanceID] ~= nil
    if hadAura then
        bucket.auras[normalizedAuraInstanceID] = nil
    end
    if bucket.indexByAuraID[normalizedAuraInstanceID] ~= nil then
        bucket.indexByAuraID[normalizedAuraInstanceID] = nil
        bucket._orderDirty = true
        hadAura = true
    end

    setBucketDispelType(bucket, normalizedAuraInstanceID, nil)
    return hadAura
end

-- Return the highest-priority dispel type still present in a bucket.
local function findPriorityDebuffTypeInBucket(bucket, allowedTypeSet)
    if type(bucket) ~= "table" or type(bucket.dispelTypeCount) ~= "table" then
        return nil
    end

    for index = 1, #DISPEL_TYPE_PRIORITY do
        local debuffType = DISPEL_TYPE_PRIORITY[index]
        if (type(allowedTypeSet) ~= "table" or allowedTypeSet[debuffType] == true)
            and (tonumber(bucket.dispelTypeCount[debuffType]) or 0) > 0
        then
            return debuffType
        end
    end

    return nil
end

-- Return the first live auraData payload still present in an ordered bucket.
local function getFirstAuraDataInBucket(bucket)
    if type(bucket) ~= "table" or type(bucket.order) ~= "table" or type(bucket.auras) ~= "table" then
        return nil
    end

    compactGroupDebuffBucket(bucket)

    for index = 1, #bucket.order do
        local auraInstanceID = bucket.order[index]
        local auraData = auraInstanceID and bucket.auras[auraInstanceID] or nil
        if type(auraData) == "table" then
            return auraData
        end
    end

    return nil
end

local isGroupAuraFilteredIn

-- Return the first dispellable debuff aura for unitToken.
-- Prefer the dedicated dispellable bucket, but fall back to validating the
-- harmful bucket against the dispel filter so the overlay still works when the
-- dispellable filter path omits type metadata.
local function getFirstDispellableAuraData(unitToken, state, allowedTypeSet)
    if type(state) ~= "table" then
        return nil
    end

    local dispellableAura = getFirstAuraDataInBucket(state.dispellable)
    if dispellableAura then
        return dispellableAura
    end

    local harmfulBucket = state.harmful
    if type(harmfulBucket) ~= "table" or type(harmfulBucket.order) ~= "table" or type(harmfulBucket.auras) ~= "table" then
        return nil
    end

    compactGroupDebuffBucket(harmfulBucket)

    for index = 1, #harmfulBucket.order do
        local auraInstanceID = harmfulBucket.order[index]
        local auraData = auraInstanceID and harmfulBucket.auras[auraInstanceID] or nil
        if type(auraData) == "table" then
            if isGroupAuraFilteredIn(unitToken, auraInstanceID, GROUP_DISPELLABLE_FILTER, GROUP_DISPELLABLE_FALLBACK_FILTER, auraData) then
                return auraData
            end

            local dispelType = normalizeDispelType(auraData.dispelName)
            if dispelType and (type(allowedTypeSet) ~= "table" or allowedTypeSet[dispelType] == true) then
                return auraData
            end

            if safeTruthy(auraData.canActivePlayerDispel) then
                return auraData
            end
        end
    end

    return nil
end

-- Resolve RGB components for a dispellable aura using Blizzard's color API when
-- available, then fall back to the dispel type tables used elsewhere.
local function resolveDispellableAuraColor(unitToken, auraData, fallbackDebuffType)
    if type(unitToken) ~= "string" or unitToken == "" or type(auraData) ~= "table" then
        if fallbackDebuffType and DebuffTypeColor and DebuffTypeColor[fallbackDebuffType] then
            local fallbackColor = DebuffTypeColor[fallbackDebuffType]
            return fallbackColor.r, fallbackColor.g, fallbackColor.b
        end
        return nil, nil, nil
    end

    local auraInstanceID = normalizeAuraInstanceID(auraData.auraInstanceID)
    if auraInstanceID and C_UnitAuras and type(C_UnitAuras.GetAuraDispelTypeColor) == "function" then
        local colorCurve = getGroupDispelColorCurve()
        local okColor, colorValue
        if colorCurve then
            okColor, colorValue = pcall(C_UnitAuras.GetAuraDispelTypeColor, unitToken, auraInstanceID, colorCurve)
        else
            okColor, colorValue = pcall(C_UnitAuras.GetAuraDispelTypeColor, unitToken, auraInstanceID)
        end
        if okColor and colorValue then
            if type(colorValue.GetRGBA) == "function" then
                local okRGBA, r, g, b = pcall(colorValue.GetRGBA, colorValue)
                if okRGBA then
                    return r, g, b
                end
            elseif type(colorValue) == "table" and type(colorValue.r) == "number" then
                return colorValue.r, colorValue.g, colorValue.b
            end
        end
    end

    local dispelType = normalizeDispelType(auraData.dispelName) or fallbackDebuffType
    if dispelType and DebuffTypeColor and DebuffTypeColor[dispelType] then
        local color = DebuffTypeColor[dispelType]
        return color.r, color.g, color.b
    end

    return nil, nil, nil
end

-- Read one aura by slot using pcall so the cache degrades per-aura instead of
-- fail-closing the whole unit when Blizzard adjusts secret-value guards.
local function getGroupAuraDataBySlot(unitToken, slot)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataBySlot) == "function") then
        return nil
    end
    if isSecretAuraValue(slot) then
        return nil
    end

    local okAura, auraData = pcall(C_UnitAuras.GetAuraDataBySlot, unitToken, slot)
    if not okAura or type(auraData) ~= "table" or isSecretAuraValue(auraData) then
        return nil
    end

    return auraData
end

-- Read one aura by auraInstanceID for the delta-update path.
local function getGroupAuraDataByInstanceID(unitToken, auraInstanceID)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function") then
        return nil
    end

    local normalizedAuraInstanceID = normalizeAuraInstanceID(auraInstanceID)
    if not normalizedAuraInstanceID then
        return nil
    end

    local okAura, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, normalizedAuraInstanceID)
    if not okAura or type(auraData) ~= "table" or isSecretAuraValue(auraData) then
        return nil
    end

    return auraData
end

-- Query aura slots for one filter, following continuation tokens when needed.
local function collectAuraSlots(unitToken, filter, fallbackFilter, maxCount)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraSlots) == "function") then
        return {}
    end

    local limit = Util:Clamp(tonumber(maxCount) or MAX_AURA_SCAN, 1, MAX_AURA_SCAN)

    local function runQuery(activeFilter)
        local slots = {}
        local continuationToken = nil
        local batchSize = limit

        for _ = 1, GROUP_AURA_SLOT_SCAN_GUARD do
            local okQuery, batch
            if continuationToken ~= nil then
                okQuery, batch = pcall(function()
                    return { C_UnitAuras.GetAuraSlots(unitToken, activeFilter, batchSize, continuationToken) }
                end)
            else
                okQuery, batch = pcall(function()
                    return { C_UnitAuras.GetAuraSlots(unitToken, activeFilter, batchSize) }
                end)
            end
            if not okQuery or type(batch) ~= "table" then
                return nil
            end

            local nextToken = batch[1]
            if isSecretAuraValue(nextToken) then
                nextToken = nil
            end

            local addedThisBatch = 0
            for batchIndex = 2, #batch do
                local slot = batch[batchIndex]
                if not isSecretAuraValue(slot) then
                    slots[#slots + 1] = slot
                    addedThisBatch = addedThisBatch + 1
                    if #slots >= limit then
                        nextToken = nil
                        break
                    end
                end
            end

            if nextToken == nil or addedThisBatch == 0 or #slots >= limit then
                break
            end
            continuationToken = nextToken
        end

        return slots
    end

    local slots = runQuery(filter)
    if type(slots) == "table" and (#slots > 0 or fallbackFilter == nil or fallbackFilter == filter) then
        return slots
    end
    if fallbackFilter and fallbackFilter ~= filter then
        local fallbackSlots = runQuery(fallbackFilter)
        if type(fallbackSlots) == "table" then
            return fallbackSlots
        end
    end

    return slots or {}
end

-- Return true when auraInstanceID currently matches the requested aura filter.
isGroupAuraFilteredIn = function(unitToken, auraInstanceID, primaryFilter, fallbackFilter, auraData)
    local normalizedAuraInstanceID = normalizeAuraInstanceID(auraInstanceID)
    if not normalizedAuraInstanceID then
        return false
    end

    local function matchesFilter(filterValue)
        if not filterValue then
            return nil
        end
        if C_UnitAuras and type(C_UnitAuras.IsAuraFilteredOutByInstanceID) == "function" then
            local okFilter, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unitToken, normalizedAuraInstanceID, filterValue)
            if okFilter and not isSecretAuraValue(filteredOut) then
                return safeTruthy(filteredOut) ~= true
            end
        end
        return nil
    end

    local matched = matchesFilter(primaryFilter)
    if matched == nil and fallbackFilter and fallbackFilter ~= primaryFilter then
        matched = matchesFilter(fallbackFilter)
    end
    if matched ~= nil then
        return matched == true
    end

    if type(auraData) ~= "table" then
        auraData = getGroupAuraDataByInstanceID(unitToken, normalizedAuraInstanceID)
    end
    if type(auraData) ~= "table" then
        return false
    end

    if primaryFilter == GROUP_DISPELLABLE_FILTER or primaryFilter == GROUP_DISPELLABLE_FALLBACK_FILTER then
        return safeTruthy(auraData.canActivePlayerDispel)
    end

    if auraData.isHarmful ~= nil and not isSecretAuraValue(auraData.isHarmful) then
        return safeTruthy(auraData.isHarmful)
    end

    return safeTruthy(auraData.isHelpful) ~= true
end

-- Extracts the normalised group unit token from any frame that exposes a unit
-- via GetAttribute("unit"), .displayedUnit, or .unit.
local function getFrameUnitToken(frame)
    if type(frame) ~= "table" then
        return nil
    end
    local unitToken = nil
    if type(frame.GetAttribute) == "function" then
        local ok, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(attrUnit) == "string" and attrUnit ~= "" then
            unitToken = attrUnit
        end
    end
    if type(unitToken) ~= "string" or unitToken == "" then
        unitToken = frame.displayedUnit or frame.unit
    end
    return normalizeGroupUnitToken(unitToken)
end

-- Collects all mummu party/raid frames into a flat array.
local function getAllMummuGroupFrames()
    local activeFrames = {}
    local activePartyFrames = type(ns.activeMummuPartyFrames) == "table" and ns.activeMummuPartyFrames or nil
    local activeRaidFrames = type(ns.activeMummuRaidFrames) == "table" and ns.activeMummuRaidFrames or nil

    if activePartyFrames and #activePartyFrames > 0 then
        for i = 1, #activePartyFrames do
            activeFrames[#activeFrames + 1] = activePartyFrames[i]
        end
    end
    if activeRaidFrames and #activeRaidFrames > 0 then
        for i = 1, #activeRaidFrames do
            activeFrames[#activeFrames + 1] = activeRaidFrames[i]
        end
    end
    if #activeFrames > 0 then
        return activeFrames
    end

    -- Fallback: scan header children (covers the case before first RefreshAll).
    local frames = {}
    local partyHeader = _G["mummuFramesPartyHeader"]
    if partyHeader and type(partyHeader.GetChildren) == "function" then
        local children = { partyHeader:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child then
                frames[#frames + 1] = child
            end
        end
    end
    for groupIndex = 1, MAX_BLIZZARD_RAID_GROUPS do
        local raidHeader = _G["mummuFramesRaidHeader" .. tostring(groupIndex)]
        if raidHeader and type(raidHeader.GetChildren) == "function" then
            local children = { raidHeader:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child then
                    frames[#frames + 1] = child
                end
            end
        end
    end
    return frames
end

-- Return the owning group module for "party" or "raid".
local function getModuleForOwner(addonRef, ownerKey)
    if not addonRef or type(addonRef.GetModule) ~= "function" then
        return nil
    end
    if ownerKey == "raid" then
        return addonRef:GetModule("raidFrames")
    end
    return addonRef:GetModule("partyFrames")
end

-- Collects all Blizzard compact unit frames into a flat array.
local function getAllBlizzardCompactUnitFrames()
    local frames = {}

    for i = 1, MAX_BLIZZARD_PARTY_FRAMES do
        local frame = _G["CompactPartyFrameMember" .. tostring(i)]
        if frame then
            frames[#frames + 1] = frame
        end
    end

    for i = 1, MAX_BLIZZARD_RAID_FRAMES do
        local frame = _G["CompactRaidFrame" .. tostring(i)]
        if frame then
            frames[#frames + 1] = frame
        end
    end

    for groupIndex = 1, MAX_BLIZZARD_RAID_GROUPS do
        for memberIndex = 1, MAX_BLIZZARD_RAID_GROUP_MEMBERS do
            local frame = _G["CompactRaidGroup" .. tostring(groupIndex) .. "Member" .. tostring(memberIndex)]
            if frame then
                frames[#frames + 1] = frame
            end
        end
    end

    return frames
end

-- ---------------------------------------------------------------------------
-- Frame visibility helpers (module-level to avoid per-call closure allocation)
-- ---------------------------------------------------------------------------

local function getFrameShown(frame)
    if type(frame.IsShown) ~= "function" then
        return true
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

-- Return a frame's effective alpha, falling back to fully visible.
local function getFrameAlpha(frame)
    if type(frame.GetAlpha) ~= "function" then
        return 1
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if ok and type(alpha) == "number" then
        return alpha
    end
    return 1
end

-- Returns true when candidateFrame should replace existingFrame in the shared map.
-- Prefers shown frames over hidden ones, then visible-alpha over transparent.
local function shouldPreferFrame(existingFrame, candidateFrame)
    if type(existingFrame) ~= "table" then
        return true
    end
    if type(candidateFrame) ~= "table" then
        return false
    end

    local existingShown   = getFrameShown(existingFrame)
    local candidateShown  = getFrameShown(candidateFrame)
    if existingShown ~= candidateShown then
        return candidateShown
    end

    local existingVisible  = getFrameAlpha(existingFrame) > 0.05
    local candidateVisible = getFrameAlpha(candidateFrame) > 0.05
    if existingVisible ~= candidateVisible then
        return candidateVisible
    end

    return false
end

-- Safely sets a texture on a texture object; returns true on success.
local function safeSetTexture(textureObject, texturePath)
    if not textureObject or type(textureObject.SetTexture) ~= "function" then
        return false
    end
    local ok = pcall(textureObject.SetTexture, textureObject, texturePath)
    return ok == true
end

-- Returns true when aura indicators should be rendered on frame.
-- mummu group frames always return true: during combat, party/raid remaps can
-- temporarily point to hidden stand-by frames, but we still need aura state
-- so indicators are correct when the frame becomes visible again.
local function shouldFrameRenderAuras(frame)
    if type(frame) ~= "table" then
        return false
    end
    if frame._mummuIsGroupFrame == true or frame._mummuIsPartyFrame == true or frame._mummuIsRaidFrame == true then
        return true
    end
    if type(frame.IsVisible) == "function" then
        local ok, visible = pcall(frame.IsVisible, frame)
        if ok then
            return visible == true
        end
    end
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok then
            return shown == true
        end
    end
    return true
end

-- Returns true when a compact aura widget currently represents a shown aura.
local function isCompactAuraFrameShown(auraFrame)
    if type(auraFrame) ~= "table" or not auraFrame.auraInstanceID then
        return false
    end

    local shown = true
    if type(auraFrame.IsShown) == "function" then
        local ok, shownValue = pcall(auraFrame.IsShown, auraFrame)
        if ok then
            shown = shownValue == true
        end
    end

    return shown
end

-- Collects visible auraInstanceIDs from a Blizzard aura frame list into setTarget.
local function captureFromCompactAuraList(auraList, setTarget)
    if type(auraList) ~= "table" then
        return
    end
    for _, auraFrame in pairs(auraList) do
        if isCompactAuraFrameShown(auraFrame) then
            setTarget[auraFrame.auraInstanceID] = true
        end
    end
end

-- Collects visible debuff types from a Blizzard compact debuff list.
local function captureDebuffTypesFromCompactAuraList(auraList, auraTypeByAuraID, typeSet)
    if type(auraList) ~= "table" or type(auraTypeByAuraID) ~= "table" or type(typeSet) ~= "table" then
        return
    end

    for _, auraFrame in pairs(auraList) do
        if isCompactAuraFrameShown(auraFrame) then
            local debuffType = extractDispelTypeFromCompactDebuffFrame(auraFrame)
            if debuffType then
                auraTypeByAuraID[auraFrame.auraInstanceID] = debuffType
                typeSet[debuffType] = true
            end
        end
    end
end

-- Infers the owner key ("party" or "raid") for a Blizzard compact frame by
-- checking the frame's unit token first, then walking up the parent chain
-- looking for "Party" or "Raid" in frame names.
local function inferCompactOwner(frame)
    local unitToken     = getFrameUnitToken(frame)
    local ownerFromUnit = inferOwnerForUnit(unitToken)
    if ownerFromUnit then
        return ownerFromUnit
    end

    local cursor = frame
    for _ = 1, 3 do
        if type(cursor) ~= "table" then
            break
        end

        local frameName
        if type(cursor.GetName) == "function" then
            local ok, name = pcall(cursor.GetName, cursor)
            if ok and type(name) == "string" then
                frameName = name
            end
        end

        if frameName then
            if string.find(frameName, "Party", 1, true) then
                return "party"
            end
            if string.find(frameName, "Raid", 1, true) then
                return "raid"
            end
        end

        if type(cursor.GetParent) ~= "function" then
            break
        end
        local ok, parent = pcall(cursor.GetParent, cursor)
        if not ok then
            break
        end
        cursor = parent
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Compact frame helpers for alpha/scale/mouse control
-- (module-level to avoid per-call closure allocation)
-- ---------------------------------------------------------------------------

local function safeSetAlpha(frame, alpha)
    if frame and type(frame.SetAlpha) == "function" then
        pcall(frame.SetAlpha, frame, alpha)
    end
end

-- Safely change frame scale outside combat.
local function safeSetScale(frame, scale)
    if not frame or type(frame.SetScale) ~= "function" then
        return
    end
    if InCombatLockdown() then
        return
    end
    pcall(frame.SetScale, frame, scale)
end

-- Safely toggle mouse interaction on a frame outside combat.
local function safeEnableMouse(frame, enabled)
    if not frame or type(frame.EnableMouse) ~= "function" then
        return
    end
    if InCombatLockdown() then
        return
    end
    pcall(frame.EnableMouse, frame, enabled)
end

-- Hide Blizzard edit/selection highlights on suppressed compact frames.
local function hideSelectionHighlights(frame)
    if not frame then
        return
    end
    if frame.selectionHighlight and type(frame.selectionHighlight.SetShown) == "function" then
        frame.selectionHighlight:SetShown(false)
    end
    if frame.selectionIndicator and type(frame.selectionIndicator.SetShown) == "function" then
        frame.selectionIndicator:SetShown(false)
    end
end

-- ---------------------------------------------------------------------------
-- Tracker indicator element helpers
-- ---------------------------------------------------------------------------

-- Builds a string-keyed set from an array of spell names for O(1) lookup.
-- Returns nil when the array is empty or absent (no name filter — show all).

-- Returns (or creates) the tracker indicator element for slotIndex on frame.
-- Elements display a spell icon in a small overlay frame.
local function ensureTrackerElement(frame, slotIndex)
    frame.HealerTrackerElements = frame.HealerTrackerElements or {}
    local key      = tostring(slotIndex)
    local existing = frame.HealerTrackerElements[key]
    if existing then
        return existing
    end

    local element = CreateFrame("Frame", nil, frame)
    element:SetFrameStrata("MEDIUM")
    element:SetFrameLevel(frame:GetFrameLevel() + 40)
    element:Hide()

    element.Icon = element:CreateTexture(nil, "ARTWORK")
    element.Icon:SetAllPoints()
    element.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.HealerTrackerElements[key] = element
    return element
end

-- Hides all tracker elements whose keys are not in usedByKey.
local function hideUnusedTrackerElements(frame, usedByKey)
    if type(frame) ~= "table" or type(frame.HealerTrackerElements) ~= "table" then
        return
    end
    for key, element in pairs(frame.HealerTrackerElements) do
        if not usedByKey[key] and element then
            element:Hide()
        end
    end
end

local function getAuraAnchorGrowth(anchorPoint)
    local resolvedAnchor = type(anchorPoint) == "string" and anchorPoint or "TOPRIGHT"
    if string.find(resolvedAnchor, "RIGHT", 1, true) then
        return string.gsub(resolvedAnchor, "RIGHT", "LEFT"), -GROUP_DEBUFF_BUTTON_GAP
    end
    if string.find(resolvedAnchor, "LEFT", 1, true) then
        return string.gsub(resolvedAnchor, "LEFT", "RIGHT"), GROUP_DEBUFF_BUTTON_GAP
    end
    return resolvedAnchor, GROUP_DEBUFF_BUTTON_GAP
end

local function hideGroupDebuffButton(button)
    if type(button) ~= "table" then
        return
    end
    if button.Cooldown and type(button.Cooldown.SetCooldown) == "function" then
        pcall(button.Cooldown.SetCooldown, button.Cooldown, 0, 0)
        button.Cooldown:Hide()
    end
    if type(button.Hide) == "function" then
        button:Hide()
    end
end

local function hideGroupDebuffButtonPool(buttons)
    if type(buttons) ~= "table" then
        return
    end
    for index = 1, #buttons do
        hideGroupDebuffButton(buttons[index])
    end
end

local function ensureGroupDebuffButton(frame, index)
    if type(frame) ~= "table" then
        return nil
    end

    frame.GroupDebuffButtons = frame.GroupDebuffButtons or {}
    local buttons = frame.GroupDebuffButtons
    if buttons[index] then
        return buttons[index]
    end

    local button = CreateFrame("Frame", nil, frame)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(frame:GetFrameLevel() + 34)

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon:SetTexture(DEFAULT_AURA_TEXTURE)

    button.CountText = button:CreateFontString(nil, "OVERLAY")
    button.CountText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.CountText:SetJustifyH("RIGHT")

    button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.Cooldown:SetAllPoints()
    if type(button.Cooldown.SetDrawBling) == "function" then
        button.Cooldown:SetDrawBling(false)
    end
    if type(button.Cooldown.SetHideCountdownNumbers) == "function" then
        button.Cooldown:SetHideCountdownNumbers(true)
    end
    button.Cooldown:Hide()
    button:Hide()

    buttons[index] = button
    return button
end

local function getGroupDebuffConfig(self, frame, unitToken)
    local ownerKey = inferOwnerForUnit(unitToken)
    if ownerKey ~= "party" and ownerKey ~= "raid" then
        if type(frame) == "table" and frame._mummuIsRaidFrame == true then
            ownerKey = "raid"
        else
            ownerKey = "party"
        end
    end

    local defaults = DEFAULT_GROUP_DEBUFF_CONFIG_BY_OWNER[ownerKey] or DEFAULT_GROUP_DEBUFF_CONFIG_BY_OWNER.party
    local dataHandle = self:GetDataHandle()
    local unitConfig = dataHandle and type(dataHandle.GetUnitConfig) == "function" and dataHandle:GetUnitConfig(ownerKey) or nil
    local auraConfig = unitConfig and type(unitConfig.aura) == "table" and unitConfig.aura or nil
    local debuffsConfig = auraConfig and type(auraConfig.debuffs) == "table" and auraConfig.debuffs or nil
    local maxDurationSeconds = tonumber(debuffsConfig and debuffsConfig.maxDurationSeconds) or defaults.maxDurationSeconds or 60
    maxDurationSeconds = math.floor(maxDurationSeconds + 0.5)
    if maxDurationSeconds < 1 then
        maxDurationSeconds = defaults.maxDurationSeconds or 60
    end

    return {
        enabled = debuffsConfig == nil or debuffsConfig.enabled ~= false,
        anchorPoint = (debuffsConfig and debuffsConfig.anchorPoint) or defaults.anchorPoint,
        relativePoint = (debuffsConfig and debuffsConfig.relativePoint) or defaults.relativePoint,
        x = tonumber(debuffsConfig and debuffsConfig.x) or defaults.x,
        y = tonumber(debuffsConfig and debuffsConfig.y) or defaults.y,
        size = tonumber(debuffsConfig and debuffsConfig.size) or defaults.size,
        scale = tonumber(debuffsConfig and debuffsConfig.scale) or defaults.scale,
        max = tonumber(debuffsConfig and debuffsConfig.max) or defaults.max,
        hidePermanent = debuffsConfig and debuffsConfig.hidePermanent == true or defaults.hidePermanent == true,
        hideLongDuration = debuffsConfig and debuffsConfig.hideLongDuration == true or defaults.hideLongDuration == true,
        maxDurationSeconds = Util:Clamp(maxDurationSeconds, 1, 3600),
    }
end

local getAuraDataByIndex
local isAuraIndexSecret

-- Returns true when a debuff entry should be hidden by the optional
-- party/raid declutter filter. Fail open on unknown/secret timing fields so
-- we never suppress an aura we could not classify safely.
local function shouldHideGroupDebuffEntry(config, entry)
    if type(config) ~= "table" or type(entry) ~= "table" then
        return false
    end
    if config.hidePermanent ~= true and config.hideLongDuration ~= true then
        return false
    end

    local duration = getSafeAuraNumericValue(entry.duration, nil)
    local expirationTime = getSafeAuraNumericValue(entry.expirationTime, nil)

    if config.hidePermanent == true
        and type(duration) == "number"
        and type(expirationTime) == "number"
        and duration <= 0
        and expirationTime <= 0
    then
        return true
    end

    if config.hideLongDuration == true and type(duration) == "number" then
        local threshold = tonumber(config.maxDurationSeconds) or 60
        threshold = math.floor(threshold + 0.5)
        if threshold < 1 then
            threshold = 60
        end
        threshold = Util:Clamp(threshold, 1, 3600)
        if duration > threshold then
            return true
        end
    end

    return false
end

-- Convert the cached harmful aura bucket into render entries for the debuff row.
local function gatherGroupDebuffEntries(unitToken, config)
    local entries = {}
    local limit = Util:Clamp(tonumber(config and config.max) or 0, 0, GROUP_DEBUFF_MAX_BUTTONS)
    if type(unitToken) ~= "string" or unitToken == "" or limit <= 0 then
        return entries
    end

    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    local state = normalizedUnit and groupDebuffStateByUnit[normalizedUnit] or nil
    local bucket = state and state.harmful or nil
    if type(bucket) ~= "table" then
        return entries
    end

    compactGroupDebuffBucket(bucket)

    local order = bucket.order
    local auras = bucket.auras
    if type(order) ~= "table" or type(auras) ~= "table" then
        return entries
    end

    for index = 1, #order do
        local auraInstanceID = order[index]
        local auraData = auraInstanceID and auras[auraInstanceID] or nil
        if type(auraData) == "table" then
            local applications = getSafeAuraNumericValue(auraData.applications, nil)
            if applications == nil then
                applications = getSafeAuraNumericValue(auraData.count, 0) or 0
            end

            entries[#entries + 1] = {
                icon = isSecretAuraValue(auraData.icon) and nil or auraData.icon,
                applications = applications,
                expirationTime = getSafeAuraNumericValue(auraData.expirationTime, nil),
                duration = getSafeAuraNumericValue(auraData.duration, nil),
            }
            if shouldHideGroupDebuffEntry(config, entries[#entries]) then
                entries[#entries] = nil
            elseif #entries >= limit then
                break
            end
        end
    end

    return entries
end

local function getPreviewGroupDebuffEntries(maxIcons)
    local entries = {}
    local limit = Util:Clamp(tonumber(maxIcons) or 0, 0, GROUP_DEBUFF_MAX_BUTTONS)
    if limit <= 0 then
        return entries
    end

    local total = math.min(limit, 3)
    local now = getSafeNowSeconds()
    local previewDurations = {
        45,
        120,
        0,
    }
    for index = 1, total do
        local duration = previewDurations[index] or 0
        entries[#entries + 1] = {
            icon = DEFAULT_AURA_TEXTURE,
            applications = index == 1 and 2 or 0,
            expirationTime = duration > 0 and (now + duration) or 0,
            duration = duration,
        }
    end
    return entries
end

local function setDefensiveIndicatorBorderColor(indicator, color)
    if type(indicator) ~= "table" or type(color) ~= "table" then
        return
    end

    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    local a = color[4] or 1

    local borderTextures = {
        indicator.BorderTop,
        indicator.BorderRight,
        indicator.BorderBottom,
        indicator.BorderLeft,
    }
    for i = 1, #borderTextures do
        local borderTexture = borderTextures[i]
        if borderTexture and type(borderTexture.SetColorTexture) == "function" then
            borderTexture:SetColorTexture(r, g, b, a)
        end
    end
end

local function getSafeFrameHeight(frame)
    if type(frame) ~= "table" or type(frame.GetHeight) ~= "function" then
        return 0
    end

    local okHeight, height = pcall(frame.GetHeight, frame)
    if okHeight and type(height) == "number" then
        return height
    end
    return 0
end

local function ensureCenterDefensiveIndicator(frame)
    if type(frame) ~= "table" then
        return nil
    end

    local existing = frame.MummuCenterDefensiveIndicator
    if existing then
        return existing
    end

    local parent = frame.HealthBar or frame
    local indicator = CreateFrame("Frame", nil, parent)
    indicator:Hide()

    indicator.Background = indicator:CreateTexture(nil, "BACKGROUND")
    indicator.Background:SetAllPoints()
    indicator.Background:SetColorTexture(
        CENTER_DEFENSIVE_BACKDROP_COLOR[1],
        CENTER_DEFENSIVE_BACKDROP_COLOR[2],
        CENTER_DEFENSIVE_BACKDROP_COLOR[3],
        CENTER_DEFENSIVE_BACKDROP_COLOR[4]
    )

    indicator.BorderTop = indicator:CreateTexture(nil, "BORDER")
    indicator.BorderTop:SetPoint("TOPLEFT", indicator, "TOPLEFT", 0, 0)
    indicator.BorderTop:SetPoint("TOPRIGHT", indicator, "TOPRIGHT", 0, 0)
    indicator.BorderTop:SetHeight(1)

    indicator.BorderRight = indicator:CreateTexture(nil, "BORDER")
    indicator.BorderRight:SetPoint("TOPRIGHT", indicator, "TOPRIGHT", 0, 0)
    indicator.BorderRight:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", 0, 0)
    indicator.BorderRight:SetWidth(1)

    indicator.BorderBottom = indicator:CreateTexture(nil, "BORDER")
    indicator.BorderBottom:SetPoint("BOTTOMLEFT", indicator, "BOTTOMLEFT", 0, 0)
    indicator.BorderBottom:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", 0, 0)
    indicator.BorderBottom:SetHeight(1)

    indicator.BorderLeft = indicator:CreateTexture(nil, "BORDER")
    indicator.BorderLeft:SetPoint("TOPLEFT", indicator, "TOPLEFT", 0, 0)
    indicator.BorderLeft:SetPoint("BOTTOMLEFT", indicator, "BOTTOMLEFT", 0, 0)
    indicator.BorderLeft:SetWidth(1)

    indicator.Icon = indicator:CreateTexture(nil, "ARTWORK")
    indicator.Icon:SetPoint("TOPLEFT", indicator, "TOPLEFT", 2, -2)
    indicator.Icon:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", -2, 2)
    indicator.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    indicator.Cooldown = CreateFrame("Cooldown", nil, indicator, "CooldownFrameTemplate")
    indicator.Cooldown:SetAllPoints(indicator.Icon)
    if type(indicator.Cooldown.SetDrawEdge) == "function" then
        indicator.Cooldown:SetDrawEdge(false)
    end
    if type(indicator.Cooldown.SetDrawBling) == "function" then
        indicator.Cooldown:SetDrawBling(false)
    end
    if type(indicator.Cooldown.SetHideCountdownNumbers) == "function" then
        indicator.Cooldown:SetHideCountdownNumbers(true)
    end
    indicator.Cooldown:Hide()

    setDefensiveIndicatorBorderColor(indicator, CENTER_DEFENSIVE_BORDER_COLOR_UNKNOWN)

    frame.MummuCenterDefensiveIndicator = indicator
    return indicator
end

local function layoutCenterDefensiveIndicator(frame, indicator)
    if type(frame) ~= "table" or type(indicator) ~= "table" then
        return
    end

    local parent = frame.HealthBar or frame
    local frameHeight = getSafeFrameHeight(parent)
    if frameHeight <= 0 then
        frameHeight = getSafeFrameHeight(frame)
    end
    if frameHeight <= 0 then
        frameHeight = 24
    end

    local size = Util:Clamp(math.floor((frameHeight * 0.82) + 0.5), CENTER_DEFENSIVE_MIN_SIZE, CENTER_DEFENSIVE_MAX_SIZE)
    indicator:ClearAllPoints()
    indicator:SetPoint("CENTER", parent, "CENTER", 0, 0)
    indicator:SetSize(size, size)

    if type(parent.GetFrameStrata) == "function" then
        local okStrata, strata = pcall(parent.GetFrameStrata, parent)
        if okStrata and type(strata) == "string" and strata ~= "" then
            indicator:SetFrameStrata(strata)
            if indicator.Cooldown then
                indicator.Cooldown:SetFrameStrata(strata)
            end
        end
    end

    if type(parent.GetFrameLevel) == "function" then
        local okLevel, level = pcall(parent.GetFrameLevel, parent)
        if okLevel and type(level) == "number" then
            indicator:SetFrameLevel(level + 24)
            if indicator.Cooldown then
                indicator.Cooldown:SetFrameLevel(level + 25)
            end
        end
    end
end

local function hideCenterDefensiveIndicator(frame)
    if type(frame) ~= "table" then
        return
    end

    local indicator = frame.MummuCenterDefensiveIndicator
    if type(indicator) ~= "table" then
        return
    end

    if indicator.Cooldown and type(indicator.Cooldown.SetCooldown) == "function" then
        pcall(indicator.Cooldown.SetCooldown, indicator.Cooldown, 0, 0)
        indicator.Cooldown:Hide()
    end
    indicator:Hide()
end

-- Fetches aura data by scan index; returns the auraData table or nil.
-- Uses ns.AuraSafety when available so secret indexes are skipped safely.
getAuraDataByIndex = function(unitToken, index, filter)
    if AuraSafety and type(AuraSafety.GetAuraDataByIndexSafe) == "function" then
        return AuraSafety:GetAuraDataByIndexSafe(unitToken, index, filter)
    end
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return nil
    end
    local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
    return type(auraData) == "table" and auraData or nil
end

-- Fetches aura data by instance ID; returns the auraData table or nil.
local function getAuraDataByInstanceID(unitToken, auraInstanceID)
    if AuraSafety and type(AuraSafety.GetAuraDataByInstanceIDSafe) == "function" then
        return AuraSafety:GetAuraDataByInstanceIDSafe(unitToken, auraInstanceID)
    end
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, auraInstanceID)
        if ok and type(auraData) == "table" then
            return auraData
        end
    end
    return nil
end

-- Ask AuraSafety whether the indexed aura is hidden behind secret restrictions.
isAuraIndexSecret = function(unitToken, index, filter)
    if AuraSafety and type(AuraSafety.IsAuraIndexSecret) == "function" then
        return AuraSafety:IsAuraIndexSecret(unitToken, index, filter)
    end
    return false
end

-- Ask AuraSafety whether the aura instance is hidden behind secret restrictions.
local function isAuraInstanceSecret(unitToken, auraInstanceID)
    if AuraSafety and type(AuraSafety.IsAuraInstanceSecret) == "function" then
        return AuraSafety:IsAuraInstanceSecret(unitToken, auraInstanceID)
    end
    return false
end

-- Reset the dedicated group debuff cache for one unit.
clearGroupDebuffState = function(state)
    if type(state) ~= "table" then
        return false
    end

    resetGroupDebuffBucket(state.harmful)
    resetGroupDebuffBucket(state.dispellable)
    state.revision = (tonumber(state.revision) or 0) + 1
    state.updatedAt = 0
    state.lastFullScanAt = 0
    state.lastDeltaAt = 0
    state.lastSource = "cleared"
    return true
end

-- Record metadata after a group debuff cache update.
local function finalizeGroupDebuffStateUpdate(state, changed, sourceTag, wasFullScan)
    if type(state) ~= "table" then
        return
    end

    local now = getSafeNowSeconds()
    state.updatedAt = now
    state.lastSource = type(sourceTag) == "string" and sourceTag ~= "" and sourceTag or "unknown"
    if wasFullScan == true then
        state.lastFullScanAt = now
    else
        state.lastDeltaAt = now
    end
    if changed == true then
        state.revision = (tonumber(state.revision) or 0) + 1
    end
end

-- Update one aura across both harmful and dispellable group debuff buckets.
local function applyAuraToGroupDebuffState(unitToken, state, auraData)
    if type(state) ~= "table" or type(auraData) ~= "table" then
        return false
    end

    local auraInstanceID = normalizeAuraInstanceID(auraData.auraInstanceID)
    if not auraInstanceID then
        return false
    end

    local changed = false
    if isGroupAuraFilteredIn(unitToken, auraInstanceID, GROUP_HARMFUL_FILTER, GROUP_HARMFUL_FALLBACK_FILTER, auraData) then
        changed = storeAuraInGroupDebuffBucket(state.harmful, auraData) or changed
    else
        changed = removeAuraFromGroupDebuffBucket(state.harmful, auraInstanceID) or changed
    end

    if isGroupAuraFilteredIn(unitToken, auraInstanceID, GROUP_DISPELLABLE_FILTER, GROUP_DISPELLABLE_FALLBACK_FILTER, auraData) then
        changed = storeAuraInGroupDebuffBucket(state.dispellable, auraData) or changed
    else
        changed = removeAuraFromGroupDebuffBucket(state.dispellable, auraInstanceID) or changed
    end

    return changed
end

-- Rebuild both group debuff buckets from live slot scans.
local function refreshGroupDebuffStateFromFullScan(unitToken, state, sourceTag)
    if type(state) ~= "table" then
        return false
    end

    resetGroupDebuffBucket(state.harmful)
    resetGroupDebuffBucket(state.dispellable)

    local harmfulSlots = collectAuraSlots(unitToken, GROUP_HARMFUL_FILTER, GROUP_HARMFUL_FALLBACK_FILTER, MAX_AURA_SCAN)
    for index = 1, #harmfulSlots do
        local auraData = getGroupAuraDataBySlot(unitToken, harmfulSlots[index])
        if auraData then
            storeAuraInGroupDebuffBucket(state.harmful, auraData)
        end
    end
    compactGroupDebuffBucket(state.harmful)

    local dispellableSlots = collectAuraSlots(unitToken, GROUP_DISPELLABLE_FILTER, GROUP_DISPELLABLE_FALLBACK_FILTER, MAX_AURA_SCAN)
    for index = 1, #dispellableSlots do
        local auraData = getGroupAuraDataBySlot(unitToken, dispellableSlots[index])
        if auraData then
            storeAuraInGroupDebuffBucket(state.dispellable, auraData)
        end
    end
    compactGroupDebuffBucket(state.dispellable)

    finalizeGroupDebuffStateUpdate(state, true, sourceTag or "full_scan", true)
    return true
end

-- Apply UNIT_AURA delta payloads to the dedicated group debuff cache.
local function refreshGroupDebuffStateFromDelta(unitToken, state, auraUpdateInfo, sourceTag)
    if type(state) ~= "table" or type(auraUpdateInfo) ~= "table" then
        return false
    end

    local changed = false

    if type(auraUpdateInfo.removedAuraInstanceIDs) == "table" then
        for index = 1, #auraUpdateInfo.removedAuraInstanceIDs do
            local auraInstanceID = auraUpdateInfo.removedAuraInstanceIDs[index]
            changed = removeAuraFromGroupDebuffBucket(state.harmful, auraInstanceID) or changed
            changed = removeAuraFromGroupDebuffBucket(state.dispellable, auraInstanceID) or changed
        end
    end

    local function applyAuraList(auraList)
        if type(auraList) ~= "table" then
            return
        end
        for index = 1, #auraList do
            changed = applyAuraToGroupDebuffState(unitToken, state, auraList[index]) or changed
        end
    end

    applyAuraList(auraUpdateInfo.addedAuras)
    applyAuraList(auraUpdateInfo.updatedAuras)

    if type(auraUpdateInfo.updatedAuraInstanceIDs) == "table" then
        for index = 1, #auraUpdateInfo.updatedAuraInstanceIDs do
            local auraInstanceID = auraUpdateInfo.updatedAuraInstanceIDs[index]
            local auraData = getGroupAuraDataByInstanceID(unitToken, auraInstanceID)
            if auraData then
                changed = applyAuraToGroupDebuffState(unitToken, state, auraData) or changed
            else
                changed = removeAuraFromGroupDebuffBucket(state.harmful, auraInstanceID) or changed
                changed = removeAuraFromGroupDebuffBucket(state.dispellable, auraInstanceID) or changed
            end
        end
    end

    compactGroupDebuffBucket(state.harmful)
    compactGroupDebuffBucket(state.dispellable)
    finalizeGroupDebuffStateUpdate(state, changed, sourceTag or "delta", false)
    return true
end

-- Refresh the dedicated group debuff cache from live UNIT_AURA data.
-- This path intentionally bypasses the Blizzard compact-frame hook because the
-- hidden compact frames can miss combat aura transitions in party/raid content.
function AuraHandle:RefreshDebuffCacheFromUnitAuras(unitToken, auraUpdateInfo, forceFullScan, sourceTag)
    local perfStartedAt = startPerfCounters(self)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return finishPerfCounters(self, "RefreshDebuffCacheFromUnitAuras", perfStartedAt, false)
    end

    local state = ensureGroupDebuffState(normalizedUnit)
    if type(UnitExists) == "function" and UnitExists(normalizedUnit) ~= true then
        return finishPerfCounters(self, "RefreshDebuffCacheFromUnitAuras", perfStartedAt, clearGroupDebuffState(state))
    end

    if forceFullScan == true
        or type(auraUpdateInfo) ~= "table"
        or auraUpdateInfo.isFullUpdate == true
        or not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function")
    then
        local refreshed = refreshGroupDebuffStateFromFullScan(normalizedUnit, state, sourceTag or "full_scan")
        if refreshed and self._diagnosticsEnabled then
            print(string.format(
                "[mummuFrames:AuraHandle] debuff full scan unit=%s harmful=%d dispellable=%d source=%s",
                tostring(normalizedUnit),
                #(state.harmful and state.harmful.order or {}),
                #(state.dispellable and state.dispellable.order or {}),
                tostring(sourceTag or "full_scan")
            ))
        end
        return finishPerfCounters(self, "RefreshDebuffCacheFromUnitAuras", perfStartedAt, refreshed)
    end

    local refreshed = refreshGroupDebuffStateFromDelta(normalizedUnit, state, auraUpdateInfo, sourceTag or "delta")
    if refreshed and self._diagnosticsEnabled then
        print(string.format(
            "[mummuFrames:AuraHandle] debuff delta unit=%s harmful=%d dispellable=%d source=%s",
            tostring(normalizedUnit),
            #(state.harmful and state.harmful.order or {}),
            #(state.dispellable and state.dispellable.order or {}),
            tostring(sourceTag or "delta")
        ))
    end
    return finishPerfCounters(self, "RefreshDebuffCacheFromUnitAuras", perfStartedAt, refreshed)
end

-- Ensure the live group debuff cache exists before rendering debuff visuals.
function AuraHandle:EnsureFreshGroupDebuffCache(unitToken, maxAgeSeconds, sourceTag)
    local perfStartedAt = startPerfCounters(self)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return finishPerfCounters(self, "EnsureFreshGroupDebuffCache", perfStartedAt, nil)
    end

    local state = ensureGroupDebuffState(normalizedUnit)
    local maxAge = tonumber(maxAgeSeconds) or DEBUFF_CACHE_STALE_WINDOW
    if maxAge < 0 then
        maxAge = DEBUFF_CACHE_STALE_WINDOW
    end

    if state.updatedAt <= 0 or (getSafeNowSeconds() - state.updatedAt) > maxAge then
        self:RefreshDebuffCacheFromUnitAuras(normalizedUnit, nil, true, sourceTag or "ensure_fresh")
        state = groupDebuffStateByUnit[normalizedUnit]
    end

    return finishPerfCounters(self, "EnsureFreshGroupDebuffCache", perfStartedAt, state)
end

-- Return whether a tracked aura belongs to the player, pet, or vehicle.
local function isTrackerAuraOwnedByPlayer(auraData)
    if type(auraData) ~= "table" then
        return false
    end
    if safeTruthy(auraData.isFromPlayerOrPlayerPet) then
        return true
    end

    local sourceUnit = auraData.sourceUnit
    return safeValueEquals(sourceUnit, "player")
        or safeValueEquals(sourceUnit, "pet")
        or safeValueEquals(sourceUnit, "vehicle")
end

local function isAuraSelfCastOnUnit(unitToken, auraData)
    if type(unitToken) ~= "string" or unitToken == "" or type(auraData) ~= "table" then
        return nil
    end

    local sourceUnit = auraData.sourceUnit
    if type(sourceUnit) ~= "string" or sourceUnit == "" or type(UnitIsUnit) ~= "function" then
        return nil
    end

    local okMatch, isSameUnit = pcall(UnitIsUnit, sourceUnit, unitToken)
    if not okMatch then
        return nil
    end

    return isSameUnit == true
end

local function shouldTrustDirectTrackedSpellMatch(trackedSpellInfo)
    return type(trackedSpellInfo) == "table" and trackedSpellInfo.preferDirectSpellIDMatch == true
end

local function alwaysMatchTrackedAuraRequest()
    return true
end

local function appendTrackedAuraRequestIndex(indexesByKey, key, requestIndex)
    if key == nil then
        return
    end

    local requestIndexes = indexesByKey[key]
    if type(requestIndexes) ~= "table" then
        requestIndexes = {}
        indexesByKey[key] = requestIndexes
    end
    requestIndexes[#requestIndexes + 1] = requestIndex
end

local function buildTrackedAuraRequests(allowedSpells)
    local requests = {}
    local requestIndexesByName = {}
    local requestIndexesBySpellID = {}

    if type(allowedSpells) ~= "table" then
        return requests, requestIndexesByName, requestIndexesBySpellID
    end

    for spellIndex = 1, #allowedSpells do
        local spellName = allowedSpells[spellIndex]
        if type(spellName) == "string" and spellName ~= "" then
            local trackedSpellInfo = _trackerSpellInfoCache[spellName]
            local requestIndex = #requests + 1
            local request = {
                spellName = spellName,
                trackedSpellInfo = trackedSpellInfo,
                resolvedName = trackedSpellInfo and trackedSpellInfo.name or spellName,
                preferDirectSpellIDMatch = shouldTrustDirectTrackedSpellMatch(trackedSpellInfo),
                matchedAura = nil,
            }
            requests[requestIndex] = request

            appendTrackedAuraRequestIndex(requestIndexesByName, spellName, requestIndex)
            if request.resolvedName ~= spellName then
                appendTrackedAuraRequestIndex(requestIndexesByName, request.resolvedName, requestIndex)
            end

            local trackedSpellIDs = trackedSpellInfo and trackedSpellInfo.spellIDs or nil
            if type(trackedSpellIDs) == "table" then
                local seenSpellIDs = {}
                for trackedIndex = 1, #trackedSpellIDs do
                    local trackedSpellID = normalizeSpellID(trackedSpellIDs[trackedIndex])
                    if trackedSpellID and seenSpellIDs[trackedSpellID] ~= true then
                        seenSpellIDs[trackedSpellID] = true
                        appendTrackedAuraRequestIndex(requestIndexesBySpellID, trackedSpellID, requestIndex)
                    end
                end
            end
        end
    end

    return requests, requestIndexesByName, requestIndexesBySpellID
end

local function assignTrackedAuraRequests(requests, requestIndexes, auraData, canMatchRequest)
    if type(requestIndexes) ~= "table" then
        return 0
    end

    local matchedCount = 0
    for index = 1, #requestIndexes do
        local request = requests[requestIndexes[index]]
        if request and not request.matchedAura and canMatchRequest(request) then
            request.matchedAura = auraData
            matchedCount = matchedCount + 1
        end
    end

    return matchedCount
end

local function collectTrackedAuraMatchesForFilter(unitToken, filter, requests, requestIndexesByName, requestIndexesBySpellID, resolveNamePredicate, resolveSpellPredicate)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end

    local totalRequests = #requests
    if totalRequests == 0 then
        return
    end

    local matchedCount = 0
    for requestIndex = 1, totalRequests do
        if requests[requestIndex] and requests[requestIndex].matchedAura then
            matchedCount = matchedCount + 1
        end
    end
    for index = 1, MAX_AURA_SCAN do
        if matchedCount >= totalRequests then
            break
        end

        if not isAuraIndexSecret(unitToken, index, filter) then
            local auraData = getAuraDataByIndex(unitToken, index, filter)
            if not auraData then
                break
            end

            local auraName = type(auraData.name) == "string" and auraData.name or nil
            if auraName then
                matchedCount = matchedCount + assignTrackedAuraRequests(
                    requests,
                    requestIndexesByName[auraName],
                    auraData,
                    resolveNamePredicate(auraData)
                )
            end

            local auraSpellID = normalizeSpellID(auraData.spellId)
            if auraSpellID then
                matchedCount = matchedCount + assignTrackedAuraRequests(
                    requests,
                    requestIndexesBySpellID[auraSpellID],
                    auraData,
                    resolveSpellPredicate(auraData)
                )
            end
        end
    end
end

-- Resolve tracked group-buff matches without relying on direct spell-name or
-- spell-ID aura APIs, which can be restricted while aura access is secret.
local function collectTrackedAuraMatches(unitToken, allowedSpells)
    local requests, requestIndexesByName, requestIndexesBySpellID = buildTrackedAuraRequests(allowedSpells)
    if #requests == 0 then
        return requests
    end

    collectTrackedAuraMatchesForFilter(
        unitToken,
        TRACKER_PLAYER_HELPFUL_FILTER,
        requests,
        requestIndexesByName,
        requestIndexesBySpellID,
        function()
            return alwaysMatchTrackedAuraRequest
        end,
        function()
            return alwaysMatchTrackedAuraRequest
        end
    )

    collectTrackedAuraMatchesForFilter(
        unitToken,
        TRACKER_HELPFUL_FILTER,
        requests,
        requestIndexesByName,
        requestIndexesBySpellID,
        function(auraData)
            local ownedByPlayer = isTrackerAuraOwnedByPlayer(auraData)
            return function()
                return ownedByPlayer
            end
        end,
        function(auraData)
            local ownedByPlayer = isTrackerAuraOwnedByPlayer(auraData)
            local selfCastOnUnit = nil
            return function(request)
                if ownedByPlayer then
                    return true
                end
                if request.preferDirectSpellIDMatch then
                    return true
                end
                if selfCastOnUnit == nil then
                    selfCastOnUnit = isAuraSelfCastOnUnit(unitToken, auraData)
                end
                return selfCastOnUnit == true
            end
        end
    )

    return requests
end

-- ---------------------------------------------------------------------------
-- AuraHandle class
-- ---------------------------------------------------------------------------

function AuraHandle:Constructor()
    self.addon      = nil
    self.dataHandle = nil

    self._diagnosticsEnabled = false
    self._perfCountersEnabled = false
    self._perfCounters = {}

    self:SetupBlizzardHooks()
    self:EnsureBootstrapFrame()
    self:EnsureGroupEventDispatcher()
    self:ScheduleBlizzardCacheBootstrap()
end

-- Lazy accessor: resolves the mummuFrames addon table on first call.
function AuraHandle:GetAddon()
    if self.addon then
        return self.addon
    end
    local addon = _G.mummuFrames
    if addon then
        self.addon = addon
    end
    return addon
end

-- Lazy accessor: resolves the dataHandle module on first call.
function AuraHandle:GetDataHandle()
    if self.dataHandle then
        return self.dataHandle
    end
    local addon = self:GetAddon()
    if addon and type(addon.GetModule) == "function" then
        local module = addon:GetModule("dataHandle")
        if module then
            self.dataHandle = module
            return module
        end
    end
    return nil
end

-- Enable or disable lightweight runtime profiling counters for aura hot paths.
function AuraHandle:SetPerfCountersEnabled(enabled, resetExisting)
    self._perfCountersEnabled = enabled == true
    if resetExisting ~= false then
        self._perfCounters = {}
    end
end

-- Return a snapshot of the current profiling counters.
function AuraHandle:GetPerfCounters()
    return copyPerfCounters(self._perfCounters)
end

-- Clear recorded profiling counters.
function AuraHandle:ResetPerfCounters()
    self._perfCounters = {}
end

-- ---------------------------------------------------------------------------
-- Bootstrap / initialisation
-- ---------------------------------------------------------------------------

-- Creates the persistent bootstrap frame that listens for world-entry, roster,
-- and combat events to trigger cache/map rebuilds.
function AuraHandle:EnsureBootstrapFrame()
    if cacheBootstrapFrame or type(CreateFrame) ~= "function" then
        return
    end

    local selfRef = self
    local frame   = CreateFrame("Frame", "mummuFramesAuraBootstrap")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("ADDON_LOADED")

    frame:SetScript("OnEvent", function(_, eventName, arg1)
        if eventName == "ADDON_LOADED" then
            -- Rebuild when Blizzard's compact frame code is available, or when
            -- this addon itself finishes loading.
            if arg1 == "Blizzard_CompactRaidFrames" or arg1 == "mummuFrames" then
                selfRef:OnWorldOrRosterChanged()
            end
            return
        end
        if eventName == "PLAYER_REGEN_DISABLED" or eventName == "PLAYER_REGEN_ENABLED" then
            selfRef:RebuildSharedUnitFrameMap(InCombatLockdown(), "combat_toggle")
            selfRef:ApplyBlizzardCompactFrameVisibility("combat_toggle")
            selfRef:ScheduleBlizzardVisibilityReapply("combat_toggle")
            selfRef:ScheduleBlizzardCacheBootstrap()
            return
        end
        selfRef:OnWorldOrRosterChanged()
    end)

    cacheBootstrapFrame = frame
end

-- Schedules a cascade of full compact-frame scans to warm the aura cache after
-- world entry or roster changes.  Multiple timer delays compensate for frames
-- that are not yet visible at the moment of the triggering event.
function AuraHandle:ScheduleBlizzardCacheBootstrap()
    cacheBootstrapToken = cacheBootstrapToken + 1
    local token   = cacheBootstrapToken
    local selfRef = self

    -- Run one bootstrap scan only if this schedule is still current.
    local function runScan(delayTag)
        if token ~= cacheBootstrapToken then
            return
        end
        selfRef:ScanAllBlizzardFrames(true, "bootstrap:" .. tostring(delayTag))
        -- Debuff icons and dispel overlays use the live group cache instead of
        -- the compact-frame hook, so warm both caches on the same bootstrap pass.
        for index = 1, #GROUP_UNIT_TOKENS do
            local unitToken = GROUP_UNIT_TOKENS[index]
            if type(UnitExists) ~= "function" or UnitExists(unitToken) == true then
                selfRef:RefreshDebuffCacheFromUnitAuras(unitToken, nil, true, "bootstrap:" .. tostring(delayTag))
            else
                local state = groupDebuffStateByUnit[unitToken]
                if state then
                    clearGroupDebuffState(state)
                end
            end
        end
    end

    runScan("immediate")

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.1, function() runScan(0.1) end)
        C_Timer.After(0.5, function() runScan(0.5) end)
        C_Timer.After(1.5, function() runScan(1.5) end)
    end
end

-- Handles PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE, and ADDON_LOADED events.
function AuraHandle:OnWorldOrRosterChanged()
    self:InitializeAurasDefaults()
    self:RebuildSharedUnitFrameMap(InCombatLockdown(), "world_or_roster")
    self:ScheduleBlizzardCacheBootstrap()
    self:ApplyBlizzardCompactFrameVisibility("world_or_roster")
    self:ScheduleBlizzardVisibilityReapply("world_or_roster")
end

-- Enable or disable verbose diagnostics for map/cache debugging.
function AuraHandle:SetDiagnosticsEnabled(enabled)
    self._diagnosticsEnabled = enabled == true
end

-- Return whether verbose diagnostics are currently enabled.
function AuraHandle:IsDiagnosticsEnabled()
    return self._diagnosticsEnabled == true
end

-- ---------------------------------------------------------------------------
-- Blizzard compact-frame aura capture
-- ---------------------------------------------------------------------------

-- Reads the visible aura frames from a Blizzard compact unit frame and stores
-- their instance IDs in blizzardAuraCacheByUnit.  Fires a refresh notification
-- when triggerUpdate is true.
function AuraHandle:CaptureAurasFromBlizzardFrame(frame, triggerUpdate)
    if type(frame) ~= "table" then
        return false
    end

    local unitToken = getFrameUnitToken(frame)
    if not unitToken then
        return false
    end

    if frame.unitExists == false then
        return false
    end

    local cache = ensureUnitCache(unitToken)
    wipeTable(cache.buffs)
    wipeTable(cache.debuffs)
    wipeTable(cache.debuffTypeByAuraID)
    wipeTable(cache.debuffTypeSet)
    wipeTable(cache.playerDispellable)
    wipeTable(cache.playerDispellableTypeByAuraID)
    wipeTable(cache.playerDispellableTypeSet)
    wipeTable(cache.defensives)

    captureFromCompactAuraList(frame.buffFrames,   cache.buffs)
    captureFromCompactAuraList(frame.debuffFrames, cache.debuffs)
    captureDebuffTypesFromCompactAuraList(frame.debuffFrames, cache.debuffTypeByAuraID, cache.debuffTypeSet)

    -- dispelDebuffFrames: a subset of debuffs that the player can remove.
    if type(frame.dispelDebuffFrames) == "table" then
        for _, debuffFrame in pairs(frame.dispelDebuffFrames) do
            if isCompactAuraFrameShown(debuffFrame) then
                local auraInstanceID = debuffFrame.auraInstanceID
                cache.debuffs[auraInstanceID]           = true
                cache.playerDispellable[auraInstanceID] = true

                local dispelType = extractDispelTypeFromCompactDebuffFrame(debuffFrame)
                if dispelType then
                    cache.debuffTypeByAuraID[auraInstanceID] = dispelType
                    cache.debuffTypeSet[dispelType] = true
                    cache.playerDispellableTypeByAuraID[auraInstanceID] = dispelType
                    cache.playerDispellableTypeSet[dispelType] = true
                end
            end
        end
    end

    captureDispelTypeFlagsFromCompactFrame(frame, cache.playerDispellableTypeSet)

    -- CenterDefensiveBuff: the single prominent defensive buff shown in the
    -- centre of the compact frame (e.g. Blessing of Protection).
    if type(frame.CenterDefensiveBuff) == "table" and frame.CenterDefensiveBuff.auraInstanceID then
        local shown = true
        if type(frame.CenterDefensiveBuff.IsShown) == "function" then
            local ok, shownValue = pcall(frame.CenterDefensiveBuff.IsShown, frame.CenterDefensiveBuff)
            if ok then
                shown = shownValue == true
            end
        end
        if shown then
            cache.defensives[frame.CenterDefensiveBuff.auraInstanceID] = true
        end
    end

    cache.updatedAt = getSafeNowSeconds()

    if triggerUpdate then
        self:NotifyBlizzardBuffCacheChanged(unitToken, "hook")
    end

    return true
end

-- Scans every Blizzard compact unit frame and updates the aura cache.
-- Returns the number of frames captured.
function AuraHandle:ScanAllBlizzardFrames(trigger, source)
    if trigger == false then
        return 0
    end

    local captured = 0
    local frames   = getAllBlizzardCompactUnitFrames()
    for i = 1, #frames do
        if self:CaptureAurasFromBlizzardFrame(frames[i], true) then
            captured = captured + 1
        end
    end

    if self._diagnosticsEnabled then
        print(string.format(
            "[mummuFrames:AuraHandle] full compact scan source=%s captured=%d",
            tostring(source or "scan"),
            captured
        ))
    end

    return captured
end

-- ---------------------------------------------------------------------------
-- Blizzard compact-frame event stripping
-- When a compact frame's display is taken over by mummu we reduce its event
-- registration to the bare minimum needed to keep its internal state valid.
-- ---------------------------------------------------------------------------

-- Strips a Blizzard compact frame down to UNIT_AURA-only event registration.
function AuraHandle:StripCompactUnitFrameEvents(frame)
    local unitToken = getFrameUnitToken(frame)
    if not unitToken or type(frame) ~= "table" then
        return false
    end
    if type(frame.UnregisterAllEvents) ~= "function" then
        return false
    end

    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.RegisterUnitEvent,   frame, "UNIT_AURA", unitToken)
    pcall(frame.RegisterEvent,       frame, "PLAYER_REGEN_ENABLED")
    pcall(frame.RegisterEvent,       frame, "PLAYER_REGEN_DISABLED")
    strippedCompactFrames[frame] = true
    return true
end

-- Restores full event registration for a previously stripped compact frame.
function AuraHandle:RestoreCompactUnitFrameEvents(frame)
    if type(frame) ~= "table" or strippedCompactFrames[frame] ~= true then
        return false
    end
    if type(CompactUnitFrame_UpdateUnitEvents) == "function" then
        pcall(CompactUnitFrame_UpdateUnitEvents, frame)
    end
    strippedCompactFrames[frame] = nil
    return true
end

-- Installs a hook on CompactUnitFrame_UpdateUnitEvents to re-apply event
-- stripping whenever Blizzard resets a frame's event list.
function AuraHandle:EnsureBlizzardUnitEventHook()
    if blizzardHookState.updateUnitEvents or type(hooksecurefunc) ~= "function" then
        return
    end

    local selfRef = self
    if CompactUnitFrame_UpdateUnitEvents then
        hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
            local ownerKey = inferCompactOwner(frame)
            if isGroupOwner(ownerKey) and blizzardFramesHiddenByOwner[ownerKey] == true then
                selfRef:StripCompactUnitFrameEvents(frame)
            else
                selfRef:RestoreCompactUnitFrameEvents(frame)
            end
        end)
        blizzardHookState.updateUnitEvents = true
    end
end

-- Installs all required Blizzard function hooks (idempotent).
function AuraHandle:SetupBlizzardHooks()
    if blizzardHooksInstalled then
        return
    end
    if type(hooksecurefunc) ~= "function" then
        return
    end

    local selfRef = self

    -- Hook CompactUnitFrame_UpdateAuras to populate the aura cache whenever
    -- Blizzard refreshes a compact frame.
    if not blizzardHookState.updateAuras and CompactUnitFrame_UpdateAuras then
        hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
            if not frame or frame.unitExists == false then
                return
            end
            selfRef:CaptureAurasFromBlizzardFrame(frame, true)
        end)
        blizzardHookState.updateAuras = true
    end

    self:EnsureBlizzardUnitEventHook()

    blizzardHooksInstalled = blizzardHookState.updateAuras
        or blizzardHookState.updateUnitEvents
end

-- ---------------------------------------------------------------------------
-- Blizzard compact-frame visibility management
-- ---------------------------------------------------------------------------

-- Reads the current hide-party and hide-raid flags from the saved profile.
function AuraHandle:SyncBlizzardHiddenFlagsFromConfig()
    local dataHandle = self:GetDataHandle()
    if not dataHandle or type(dataHandle.GetProfile) ~= "function" then
        return
    end

    local profile      = dataHandle:GetProfile()
    local addonEnabled = profile and profile.enabled ~= false
    local partyConfig  = type(dataHandle.GetUnitConfig) == "function" and dataHandle:GetUnitConfig("party") or nil
    local raidConfig   = type(dataHandle.GetUnitConfig) == "function" and dataHandle:GetUnitConfig("raid")  or nil

    blizzardFramesHiddenByOwner.party = addonEnabled and partyConfig and partyConfig.hideBlizzardFrame == true or false
    blizzardFramesHiddenByOwner.raid  = addonEnabled and raidConfig  and raidConfig.hideBlizzardFrame  == true or false
end

-- Applies the current hide flags to every Blizzard compact unit frame and
-- their parent containers, and (re-)installs hooks if needed.
function AuraHandle:ApplyBlizzardCompactFrameVisibility(source)
    self:SetupBlizzardHooks()
    self:SyncBlizzardHiddenFlagsFromConfig()

    local hideParty = blizzardFramesHiddenByOwner.party == true
    local hideRaid  = blizzardFramesHiddenByOwner.raid  == true

    -- Suppress the PartyFrame container.
    local partyFrame = _G["PartyFrame"]
    if partyFrame then
        safeSetAlpha(partyFrame, hideParty and 0 or 1)
        safeSetScale(partyFrame, hideParty and 0.001 or 1)
    end

    -- Suppress the raid container and its manager UI.
    local raidContainer = _G["CompactRaidFrameContainer"]
    if raidContainer then
        safeSetAlpha(raidContainer, hideRaid and 0 or 1)
        safeSetScale(raidContainer, hideRaid and 0.001 or 1)
    end

    local manager = _G["CompactRaidFrameManager"]
    if manager then
        safeSetAlpha(manager,              hideRaid and 0 or 1)
        safeSetAlpha(manager.container,    hideRaid and 0 or 1)
        safeSetAlpha(manager.toggleButton, hideRaid and 0 or 1)
        safeSetAlpha(manager.displayFrame, hideRaid and 0 or 1)
    end

    -- Apply per-frame alpha, mouse interaction, and event stripping.
    local compactFrames = getAllBlizzardCompactUnitFrames()
    for i = 1, #compactFrames do
        local frame      = compactFrames[i]
        local owner      = inferCompactOwner(frame)
        local shouldHide = (owner == "party" and hideParty) or (owner == "raid" and hideRaid)

        safeSetAlpha(frame, shouldHide and 0 or 1)
        safeEnableMouse(frame, not shouldHide)

        if shouldHide then
            hideSelectionHighlights(frame)
            self:StripCompactUnitFrameEvents(frame)
        else
            self:RestoreCompactUnitFrameEvents(frame)
        end
    end

    if self._diagnosticsEnabled then
        print(string.format(
            "[mummuFrames:AuraHandle] blizzard visibility apply source=%s party=%s raid=%s",
            tostring(source or "unknown"),
            tostring(hideParty),
            tostring(hideRaid)
        ))
    end
end

-- Schedules two deferred re-applications of the Blizzard visibility state to
-- handle frames that become available after the initial apply.
function AuraHandle:ScheduleBlizzardVisibilityReapply(source)
    local selfRef = self
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.2, function()
            selfRef:ApplyBlizzardCompactFrameVisibility((source or "visibility") .. ":0.2")
        end)
        C_Timer.After(0.5, function()
            selfRef:ApplyBlizzardCompactFrameVisibility((source or "visibility") .. ":0.5")
        end)
    end
end

-- Sets the hide state for an owner ("party" or "raid") and applies it immediately.
function AuraHandle:SetBlizzardFramesHidden(ownerKey, shouldHide, source)
    if not isGroupOwner(ownerKey) then
        return
    end
    local tag = source or ("set_hidden:" .. ownerKey)
    blizzardFramesHiddenByOwner[ownerKey] = shouldHide == true
    self:ApplyBlizzardCompactFrameVisibility(tag)
    self:ScheduleBlizzardVisibilityReapply(tag)
end

-- Returns true when Blizzard's frames for ownerKey are currently suppressed.
function AuraHandle:IsBlizzardFramesHidden(ownerKey)
    if not isGroupOwner(ownerKey) then
        return false
    end
    return blizzardFramesHiddenByOwner[ownerKey] == true
end

-- Returns true when the aura cache for unitToken was populated within maxAgeSeconds.
function AuraHandle:IsHookCacheFresh(unitToken, maxAgeSeconds)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return false
    end

    local cache     = blizzardAuraCacheByUnit[normalizedUnit]
    local updatedAt = cache and tonumber(cache.updatedAt) or 0
    if updatedAt <= 0 then
        return false
    end

    local maxAge = tonumber(maxAgeSeconds) or 0.4
    if maxAge < 0 then
        maxAge = 0.4
    end

    return (getSafeNowSeconds() - updatedAt) <= maxAge
end

-- ---------------------------------------------------------------------------
-- Shared unit-frame map
-- ---------------------------------------------------------------------------

-- Inserts or replaces an entry in the shared map, preferring visible frames.
local function setSharedMapEntry(unitToken, frame, ownerKey)
    if not unitToken or type(frame) ~= "table" or not isGroupOwner(ownerKey) then
        return
    end

    local existingFrame = sharedUnitFrameMap[unitToken]
    if existingFrame and not shouldPreferFrame(existingFrame, frame) then
        return
    end

    sharedUnitFrameMap[unitToken] = frame
    sharedUnitOwnerMap[unitToken] = ownerKey

    local guid = UnitGUID(unitToken)
    if guid then
        sharedDisplayedUnitByGUID[guid] = unitToken
    end
end

-- Rebuilds the shared unitToken→frame map from all currently active mummu
-- group frames.  Returns the number of mapped units.
--
-- allowHidden = true skips the throttle and includes hidden frames; used
-- during combat where party/raid remaps may point to stand-by frames.
function AuraHandle:RebuildSharedUnitFrameMap(allowHidden, source)
    local includeHidden = allowHidden == true
    local now           = getSafeNowSeconds()

    if not includeHidden and (now - sharedMapLastBuiltAt) < MAP_REBUILD_THROTTLE then
        local count = 0
        for _ in pairs(sharedUnitFrameMap) do
            count = count + 1
        end
        return count
    end

    wipeTable(sharedUnitFrameMap)
    wipeTable(sharedUnitOwnerMap)
    wipeTable(sharedDisplayedUnitByGUID)

    local playerGUID = UnitGUID("player")
    local allFrames  = getAllMummuGroupFrames()

    for i = 1, #allFrames do
        local frame = allFrames[i]
        if type(frame) == "table" then
            local shown = true
            if not includeHidden and type(frame.IsShown) == "function" then
                local ok, shownValue = pcall(frame.IsShown, frame)
                shown = ok and shownValue == true
            end

            if includeHidden or shown then
                local unitToken = getFrameUnitToken(frame)
                local ownerKey  = inferOwnerForUnit(unitToken)
                if unitToken and ownerKey then
                    setSharedMapEntry(unitToken, frame, ownerKey)

                    -- Cross-register player↔partyN aliases so that the map works
                    -- regardless of whether the player is shown as "player" or
                    -- as a party slot.
                    if playerGUID then
                        if unitToken == "player" then
                            for partyIndex = 1, 4 do
                                local partyUnit = "party" .. tostring(partyIndex)
                                local partyGUID = UnitGUID(partyUnit)
                                if partyGUID and partyGUID == playerGUID then
                                    setSharedMapEntry(partyUnit, frame, ownerKey)
                                end
                            end
                        elseif string.match(unitToken, "^party%d+$") then
                            local unitGUID = UnitGUID(unitToken)
                            if unitGUID and unitGUID == playerGUID then
                                setSharedMapEntry("player", frame, ownerKey)
                            end
                        end
                    end
                end
            end
        end
    end

    sharedMapLastBuiltAt = now

    if self._diagnosticsEnabled then
        local count = 0
        for _ in pairs(sharedUnitFrameMap) do
            count = count + 1
        end
        print(string.format(
            "[mummuFrames:AuraHandle] shared map rebuilt source=%s count=%d includeHidden=%s",
            tostring(source or "rebuild"),
            count,
            tostring(includeHidden)
        ))
    end

    local mappedCount = 0
    for _ in pairs(sharedUnitFrameMap) do
        mappedCount = mappedCount + 1
    end
    return mappedCount
end

-- Throttled self-heal: rebuilds the shared map when it may have gone stale,
-- but no more than once per SHARED_MAP_SELF_HEAL_THROTTLE seconds.
function AuraHandle:RequestSharedMapSelfHeal(allowHidden, source)
    local now = getSafeNowSeconds()
    if (now - sharedMapLastSelfHealAt) < SHARED_MAP_SELF_HEAL_THROTTLE then
        if self._diagnosticsEnabled then
            print(string.format(
                "[mummuFrames:AuraHandle] shared map self-heal throttled source=%s",
                tostring(source or "self_heal")
            ))
        end
        return false
    end
    sharedMapLastSelfHealAt = now
    self:RebuildSharedUnitFrameMap(allowHidden == true, source or "self_heal")
    return true
end

-- Returns the mummu frame, resolved unit token, and owner key for unitToken
-- from the shared map.  Falls back to a GUID lookup when a direct token miss
-- occurs (handles player↔partyN aliasing).
function AuraHandle:ResolveSharedMappedFrame(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil, nil, nil
    end

    local frame = sharedUnitFrameMap[normalizedUnit]
    if frame then
        return frame, normalizedUnit, sharedUnitOwnerMap[normalizedUnit] or inferOwnerForUnit(normalizedUnit)
    end

    -- GUID fallback: handles cross-token aliases (e.g. "player" ↔ "party1").
    local guid = UnitGUID(normalizedUnit)
    if guid then
        local mappedUnit = sharedDisplayedUnitByGUID[guid]
        if mappedUnit then
            local guidFrame = sharedUnitFrameMap[mappedUnit]
            if guidFrame then
                return guidFrame, mappedUnit, sharedUnitOwnerMap[mappedUnit] or inferOwnerForUnit(mappedUnit)
            end
        end
    end

    return nil, normalizedUnit, inferOwnerForUnit(normalizedUnit)
end

-- Prints the current shared-map state (diagnostics only).
function AuraHandle:DebugPrintMergedFrameMap(source)
    if not self._diagnosticsEnabled then
        return
    end
    local keys = {}
    for unitToken in pairs(sharedUnitFrameMap) do
        keys[#keys + 1] = tostring(unitToken)
    end
    table.sort(keys)
    print(string.format(
        "[mummuFrames:AuraHandle] map state source=%s count=%d units=%s",
        tostring(source or "unknown"),
        #keys,
        (#keys > 0 and table.concat(keys, ",") or "-")
    ))
end

-- ---------------------------------------------------------------------------
-- Aura refresh dispatch
-- ---------------------------------------------------------------------------

-- Called when the Blizzard aura cache for unitToken has been updated.
function AuraHandle:NotifyBlizzardBuffCacheChanged(unitToken, source)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return
    end
    -- Hook path: unitToken originates from frame.unit and may be tainted.
    -- Skip the direct C_UnitAuras tracker scan here; the hook path only drives
    -- cache-backed visuals that intentionally mirror Blizzard state, such as
    -- the centre defensive indicator. Group debuffs use UNIT_AURA instead.
    self:RefreshMappedUnit(normalizedUnit, source or "hook", true)
end

-- Returns the approved aura instance ID set for unitToken and auraType.
-- auraType: "DEBUFF" returns the live group debuff cache; any other value
-- returns helpful auras mirrored from Blizzard's compact-frame state.
function AuraHandle:GetApprovedAuraSet(unitToken, auraType)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end
    if auraType == "DEBUFF" then
        local state = self:EnsureFreshGroupDebuffCache(normalizedUnit, DEBUFF_CACHE_STALE_WINDOW, "approved_debuffs")
        local bucket = state and state.harmful or nil
        if type(bucket) ~= "table" or type(bucket.auras) ~= "table" then
            return nil
        end

        local auraSet = {}
        for auraInstanceID in pairs(bucket.auras) do
            auraSet[auraInstanceID] = true
        end
        return auraSet
    end

    local cache = blizzardAuraCacheByUnit[normalizedUnit]
    if type(cache) ~= "table" then
        return nil
    end
    return cache.buffs
end

-- Returns an auraInstanceID→auraData map of all active non-secret buffs for
-- unitToken that are present in the Blizzard aura cache.
function AuraHandle:GetApprovedBuffDataByAuraInstanceID(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end
    local cache = blizzardAuraCacheByUnit[normalizedUnit]
    if type(cache) ~= "table" then
        return nil
    end

    local buffDataByAuraInstanceID = {}
    for auraInstanceID in pairs(cache.buffs) do
        if not isAuraInstanceSecret(normalizedUnit, auraInstanceID) then
            local auraData = getAuraDataByInstanceID(normalizedUnit, auraInstanceID)
            if auraData then
                buffDataByAuraInstanceID[auraInstanceID] = auraData
            end
        end
    end
    return buffDataByAuraInstanceID
end

-- Returns a spellID→auraData map of all active non-secret buffs for unitToken
-- present in the Blizzard aura cache. Secret auras are intentionally omitted.
function AuraHandle:GetApprovedBuffData(unitToken)
    local buffDataByAuraInstanceID = self:GetApprovedBuffDataByAuraInstanceID(unitToken)
    if type(buffDataByAuraInstanceID) ~= "table" then
        return nil
    end

    local buffDataBySpellID = {}
    for _, auraData in pairs(buffDataByAuraInstanceID) do
        local spellID = normalizeSpellID(auraData and auraData.spellId)
        if spellID then
            buffDataBySpellID[spellID] = auraData
        end
    end
    return buffDataBySpellID
end

-- Returns an auraInstanceID→auraData map for buffs Blizzard classified as the
-- prominent centre defensive buff on a compact group frame.
function AuraHandle:GetApprovedDefensiveBuffDataByAuraInstanceID(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end

    local cache = blizzardAuraCacheByUnit[normalizedUnit]
    if type(cache) ~= "table" or type(cache.defensives) ~= "table" then
        return nil
    end

    local buffDataByAuraInstanceID = {}
    for auraInstanceID in pairs(cache.defensives) do
        if not isAuraInstanceSecret(normalizedUnit, auraInstanceID) then
            local auraData = getAuraDataByInstanceID(normalizedUnit, auraInstanceID)
            if auraData then
                buffDataByAuraInstanceID[auraInstanceID] = auraData
            end
        end
    end

    if next(buffDataByAuraInstanceID) == nil then
        return nil
    end
    return buffDataByAuraInstanceID
end

-- Returns the single best defensive aura data table for unitToken, or nil.
function AuraHandle:GetCenterDefensiveBuffData(unitToken)
    local buffDataByAuraInstanceID = self:GetApprovedDefensiveBuffDataByAuraInstanceID(unitToken)
    if type(buffDataByAuraInstanceID) ~= "table" then
        return nil
    end

    local bestAura = nil
    for _, auraData in pairs(buffDataByAuraInstanceID) do
        if not bestAura then
            bestAura = auraData
        else
            local expirationTime = type(auraData.expirationTime) == "number" and auraData.expirationTime or 0
            local bestExpirationTime = type(bestAura.expirationTime) == "number" and bestAura.expirationTime or 0
            if expirationTime > bestExpirationTime then
                bestAura = auraData
            end
        end
    end

    return bestAura
end

-- ---------------------------------------------------------------------------
-- Aura tracker rendering
-- Displays icons for configured player-owned buffs on group frames.
-- ---------------------------------------------------------------------------

-- Redraws the tracker icon strip on frame for the given unitToken.
function AuraHandle:RefreshFrameTrackedAuras(frame, unitToken)
    if type(frame) ~= "table" then
        return
    end
    if frame._mummuIsPartyFrame ~= true and frame._mummuIsRaidFrame ~= true then
        return
    end

    local config = self:GetAurasConfig()
    if not config or config.enabled == false then
        hideUnusedTrackerElements(frame, {})
        return
    end

    -- Snapshot config values as locals — no writes back to profile in the hot path.
    local size = Util:Clamp(tonumber(config.size) or DEFAULT_TRACKER_SIZE, 6, 48)
    if Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled() then
        size = Style:Snap(size)
    else
        size = math.floor(size + 0.5)
    end

    local allowedSpells = config.allowedSpells
    local hasFilter     = type(allowedSpells) == "table" and #allowedSpells > 0

    local usedByKey = {}
    local count     = 0

    if hasFilter then
        local trackedRequests = collectTrackedAuraMatches(unitToken, allowedSpells)
        for i = 1, #trackedRequests do
            if count >= MAX_TRACKER_AURAS then
                break
            end
            local request = trackedRequests[i]
            local spellName = request and request.spellName or nil
            local cachedInfo = request and request.trackedSpellInfo or nil
            local found = request and request.matchedAura or nil
            if found then
                count = count + 1
                local element = ensureTrackerElement(frame, count)
                element:SetSize(size, size)
                element:ClearAllPoints()
                element:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(count - 1) * (size + 2), 0)
                if not safeSetTexture(element.Icon, resolveTrackedAuraIcon(spellName, cachedInfo, found)) then
                    safeSetTexture(element.Icon, DEFAULT_AURA_TEXTURE)
                end
                element.Icon:Show()
                element:Show()
                usedByKey[tostring(count)] = true
            end
        end
    else
        for index = 1, MAX_AURA_SCAN do
            if count >= MAX_TRACKER_AURAS then
                break
            end
            if not isAuraIndexSecret(unitToken, index, TRACKER_HELPFUL_FILTER) then
                local auraData = getAuraDataByIndex(unitToken, index, TRACKER_HELPFUL_FILTER)
                if not auraData then
                    break
                end

                if isTrackerAuraOwnedByPlayer(auraData) then
                    count = count + 1
                    local element = ensureTrackerElement(frame, count)
                    element:SetSize(size, size)
                    element:ClearAllPoints()
                    element:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(count - 1) * (size + 2), 0)
                    if not safeSetTexture(element.Icon, resolveTrackedAuraIcon(nil, nil, auraData)) then
                        safeSetTexture(element.Icon, DEFAULT_AURA_TEXTURE)
                    end
                    element.Icon:Show()
                    element:Show()
                    usedByKey[tostring(count)] = true
                end
            end
        end
    end

    hideUnusedTrackerElements(frame, usedByKey)
end

-- Redraws the large centre defensive icon on frame for the given unitToken.
function AuraHandle:RefreshFrameCenterDefensiveIndicator(frame, unitToken)
    if type(frame) ~= "table" then
        return
    end
    if frame._mummuIsPartyFrame ~= true and frame._mummuIsRaidFrame ~= true then
        hideCenterDefensiveIndicator(frame)
        return
    end

    local config = self:GetAurasConfig()
    if not config or config.enabled == false then
        hideCenterDefensiveIndicator(frame)
        return
    end

    local auraData = self:GetCenterDefensiveBuffData(unitToken)
    if type(auraData) ~= "table" then
        hideCenterDefensiveIndicator(frame)
        return
    end

    local indicator = ensureCenterDefensiveIndicator(frame)
    if type(indicator) ~= "table" then
        return
    end

    layoutCenterDefensiveIndicator(frame, indicator)

    local iconTexture = auraData.icon or DEFAULT_AURA_TEXTURE
    if not safeSetTexture(indicator.Icon, iconTexture) then
        safeSetTexture(indicator.Icon, DEFAULT_AURA_TEXTURE)
    end
    indicator.Icon:Show()

    local borderColor = CENTER_DEFENSIVE_BORDER_COLOR_UNKNOWN
    local isSelfCast = isAuraSelfCastOnUnit(unitToken, auraData)
    if isSelfCast == true then
        borderColor = CENTER_DEFENSIVE_BORDER_COLOR_PERSONAL
    elseif isSelfCast == false then
        borderColor = CENTER_DEFENSIVE_BORDER_COLOR_EXTERNAL
    end
    setDefensiveIndicatorBorderColor(indicator, borderColor)

    local duration = type(auraData.duration) == "number" and auraData.duration or 0
    local expirationTime = type(auraData.expirationTime) == "number" and auraData.expirationTime or 0
    if indicator.Cooldown then
        if duration > 0 and expirationTime > 0 and type(indicator.Cooldown.SetCooldown) == "function" then
            local startTime = expirationTime - duration
            if startTime < 0 then
                startTime = 0
            end
            indicator.Cooldown:SetCooldown(startTime, duration)
            indicator.Cooldown:Show()
        else
            if type(indicator.Cooldown.SetCooldown) == "function" then
                pcall(indicator.Cooldown.SetCooldown, indicator.Cooldown, 0, 0)
            end
            indicator.Cooldown:Hide()
        end
    end

    indicator:Show()
end

-- ---------------------------------------------------------------------------
-- Dispel overlay
-- ---------------------------------------------------------------------------

-- Returns the debuff type string ("Magic", "Curse", "Poison", "Disease") for
-- the highest-priority typed debuff found on unitToken, or nil.
function AuraHandle:GetUnitDebuffType(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end

    local state = self:EnsureFreshGroupDebuffCache(normalizedUnit, DEBUFF_CACHE_STALE_WINDOW, "get_debuff_type")
    if type(state) ~= "table" then
        return nil
    end

    return findPriorityDebuffTypeInBucket(state.harmful)
end

-- Returns the debuff type string ("Magic", "Curse", "Poison", "Disease") for
-- the first player-dispellable debuff found on unitToken, or nil.
-- The dedicated dispellable bucket is preferred, but Midnight can sometimes
-- omit dispel metadata there; in that case we fall back to typed harmful auras
-- that match the player's dispel set.
function AuraHandle:GetUnitDispellableDebuffType(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end

    local state = self:EnsureFreshGroupDebuffCache(normalizedUnit, DEBUFF_CACHE_STALE_WINDOW, "get_dispellable_type")
    if type(state) ~= "table" then
        return nil
    end

    local playerDispelTypeSet = getPlayerDispelTypeSet()
    local debuffType = findPriorityDebuffTypeInBucket(state.dispellable, playerDispelTypeSet)
    if debuffType then
        return debuffType
    end

    debuffType = findPriorityDebuffTypeInBucket(state.harmful, playerDispelTypeSet)
    if debuffType then
        return debuffType
    end

    local auraData = getFirstDispellableAuraData(normalizedUnit, state, playerDispelTypeSet)
    local auraDispelType = normalizeDispelType(auraData and auraData.dispelName)
    if auraDispelType and playerDispelTypeSet[auraDispelType] == true then
        return auraDispelType
    end

    -- Some Midnight payloads report a dispellable aura without exposing the
    -- dispelName reliably. Preserve a visible overlay in that case even if the
    -- exact type color must be resolved through GetAuraDispelTypeColor later.
    if auraData and safeTruthy(auraData.canActivePlayerDispel) then
        return "Magic"
    end

    return nil
end

-- Shows or hides the healthbar overlay on frame based on debuff state.
-- Group frames only highlight debuffs the current player can dispel.
function AuraHandle:RefreshFrameDispelOverlay(frame, unitToken, rawUnitToken)
    if type(frame) ~= "table" or type(frame.DispelOverlay) ~= "table" then
        return
    end

    local liveUnitToken = normalizeGroupUnitToken(rawUnitToken) or normalizeGroupUnitToken(unitToken)
    local resolvedUnitToken = liveUnitToken or unitToken
    local normalizedUnit = normalizeGroupUnitToken(resolvedUnitToken)
    local state = normalizedUnit and self:EnsureFreshGroupDebuffCache(normalizedUnit, DEBUFF_CACHE_STALE_WINDOW, "render_dispel_overlay") or nil
    local playerDispelTypeSet = getPlayerDispelTypeSet()
    local auraData = normalizedUnit and getFirstDispellableAuraData(normalizedUnit, state, playerDispelTypeSet) or nil
    local debuffType = self:GetUnitDispellableDebuffType(resolvedUnitToken)
    local red, green, blue = resolveDispellableAuraColor(normalizedUnit or resolvedUnitToken, auraData, debuffType)

    if red and green and blue then
        -- Keep opacity centralized here so layout refreshes do not multiply the
        -- tint alpha a second time in frame modules.
        frame.DispelOverlay:SetColorTexture(red, green, blue, DISPEL_OVERLAY_ALPHA)
        frame.DispelOverlay:Show()
    else
        frame.DispelOverlay:Hide()
    end
end

-- Render the configurable debuff icon strip for party/raid frames.
function AuraHandle:RefreshFrameDebuffIcons(frame, unitToken, previewMode)
    if type(frame) ~= "table" then
        return
    end

    local config = getGroupDebuffConfig(self, frame, unitToken)
    frame.GroupDebuffButtons = frame.GroupDebuffButtons or {}
    if config.enabled ~= true then
        hideGroupDebuffButtonPool(frame.GroupDebuffButtons)
        return
    end

    local entries = previewMode == true
        and getPreviewGroupDebuffEntries(config.max)
        or gatherGroupDebuffEntries(unitToken, config)
    if previewMode == true and (config.hidePermanent == true or config.hideLongDuration == true) then
        local filteredEntries = {}
        for index = 1, #entries do
            local entry = entries[index]
            if not shouldHideGroupDebuffEntry(config, entry) then
                filteredEntries[#filteredEntries + 1] = entry
            end
        end
        entries = filteredEntries
    end
    if #entries == 0 then
        hideGroupDebuffButtonPool(frame.GroupDebuffButtons)
        return
    end

    local anchorPoint = config.anchorPoint or "TOPRIGHT"
    local relativePoint = config.relativePoint or "BOTTOMRIGHT"
    local offsetX = tonumber(config.x) or 0
    local offsetY = tonumber(config.y) or 0
    local iconSize = Util:Clamp((tonumber(config.size) or 0) * (tonumber(config.scale) or 1), 8, 48)

    if Style:IsPixelPerfectEnabled() then
        iconSize = Style:Snap(iconSize)
        offsetX = Style:Snap(offsetX)
        offsetY = Style:Snap(offsetY)
    else
        iconSize = math.floor(iconSize + 0.5)
        offsetX = math.floor(offsetX + 0.5)
        offsetY = math.floor(offsetY + 0.5)
    end

    local previousPoint, gap = getAuraAnchorGrowth(anchorPoint)
    local buttons = frame.GroupDebuffButtons
    for index = 1, #entries do
        local entry = entries[index]
        local button = ensureGroupDebuffButton(frame, index)
        local previousButton = buttons[index - 1]

        button:SetSize(iconSize, iconSize)
        button:ClearAllPoints()
        if previousButton then
            button:SetPoint(anchorPoint, previousButton, previousPoint, gap, 0)
        else
            button:SetPoint(anchorPoint, frame, relativePoint, offsetX, offsetY)
        end

        if not safeSetTexture(button.Icon, entry.icon) then
            safeSetTexture(button.Icon, DEFAULT_AURA_TEXTURE)
        end
        Style:ApplyFont(button.CountText, math.max(6, math.floor((iconSize * 0.52) + 0.5)), "OUTLINE")
        local applications = getSafeAuraNumericValue(entry.applications, 0) or 0
        if applications > 1 then
            button.CountText:SetText(tostring(math.floor(applications + 0.5)))
            button.CountText:Show()
        else
            button.CountText:SetText("")
            button.CountText:Hide()
        end

        local duration = getSafeAuraNumericValue(entry.duration, 0) or 0
        local expirationTime = getSafeAuraNumericValue(entry.expirationTime, 0) or 0
        if duration > 0 and expirationTime > 0 and button.Cooldown and type(button.Cooldown.SetCooldown) == "function" then
            local startTime = expirationTime - duration
            if startTime < 0 then
                startTime = 0
            end
            button.Cooldown:SetCooldown(startTime, duration)
            button.Cooldown:Show()
        elseif button.Cooldown then
            if type(button.Cooldown.SetCooldown) == "function" then
                pcall(button.Cooldown.SetCooldown, button.Cooldown, 0, 0)
            end
            button.Cooldown:Hide()
        end

        button:Show()
    end

    for index = #entries + 1, #buttons do
        hideGroupDebuffButton(buttons[index])
    end
end

-- Hides all aura indicators (tracker elements, centre defensive icon, and
-- dispel overlay) on frame.
function AuraHandle:ClearFrameAuraIndicators(frame)
    if type(frame) ~= "table" then
        return
    end
    hideUnusedTrackerElements(frame, {})
    hideGroupDebuffButtonPool(frame.GroupDebuffButtons)
    hideCenterDefensiveIndicator(frame)
    if frame.DispelOverlay and type(frame.DispelOverlay.Hide) == "function" then
        frame.DispelOverlay:Hide()
    end
end

-- Updates aura indicators on a group frame.
-- When skipTrackedScan is true only cache-backed visuals are refreshed (used by
-- the Blizzard-frame hook path whose unitToken may be tainted).
-- rawUnitToken: if provided, passed to RefreshFrameTrackedAuras for untainted
-- C_UnitAuras API calls; falls back to unitToken when absent.
function AuraHandle:RefreshGroupFrameAuras(frame, unitToken, skipTrackedScan, rawUnitToken)
    local perfStartedAt = startPerfCounters(self)
    if not shouldFrameRenderAuras(frame) then
        return finishPerfCounters(self, "RefreshGroupFrameAuras", perfStartedAt)
    end
    local liveUnitToken = normalizeGroupUnitToken(rawUnitToken) or normalizeGroupUnitToken(unitToken)
    if liveUnitToken and (skipTrackedScan ~= true or (type(rawUnitToken) == "string" and rawUnitToken ~= "")) then
        self:EnsureFreshGroupDebuffCache(liveUnitToken, DEBUFF_CACHE_STALE_WINDOW, "render")
    end
    if not skipTrackedScan then
        self:RefreshFrameTrackedAuras(frame, rawUnitToken or unitToken)
    end
    if liveUnitToken then
        self:RefreshFrameDebuffIcons(frame, liveUnitToken, false)
    elseif skipTrackedScan ~= true then
        self:RefreshFrameDebuffIcons(frame, unitToken, false)
    end
    self:RefreshFrameCenterDefensiveIndicator(frame, unitToken)
    self:RefreshFrameDispelOverlay(frame, liveUnitToken or unitToken, rawUnitToken)
    recordPerfCounters(self, "RefreshGroupFrameAuras", perfStartedAt)
end

-- ---------------------------------------------------------------------------
-- Mapped-unit refresh
-- ---------------------------------------------------------------------------

-- Linear scan fallback: finds the mummu frame for unitToken by iterating all
-- group frames when the shared map doesn't have an entry.
local function findMappedFrameFallback(unitToken)
    local directGUID = UnitGUID(unitToken)
    local frames     = getAllMummuGroupFrames()
    for i = 1, #frames do
        local frame     = frames[i]
        local frameUnit = getFrameUnitToken(frame)
        if frameUnit == unitToken then
            return frame, frameUnit, inferOwnerForUnit(frameUnit)
        end
        if directGUID and frameUnit then
            local frameGUID = UnitGUID(frameUnit)
            if frameGUID and frameGUID == directGUID then
                return frame, frameUnit, inferOwnerForUnit(frameUnit)
            end
        end
    end
    return nil, nil, nil
end

-- Refreshes aura indicators on the mummu frame mapped to unitToken.
-- If the shared map has no entry it attempts a self-heal rebuild, then a
-- linear scan fallback before giving up.
-- rawUnitToken: the original, unprocessed event arg (clean, from WoW event system).
-- It is passed to RefreshFrameTrackedAuras so that C_UnitAuras.GetAuraDataByIndex
-- receives an untainted argument and returns untainted aura data.
function AuraHandle:RefreshMappedUnit(unitToken, source, skipTrackedScan, rawUnitToken)
    local perfStartedAt = startPerfCounters(self)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return finishPerfCounters(self, "RefreshMappedUnit", perfStartedAt, false)
    end

    local frame, resolvedUnit = self:ResolveSharedMappedFrame(normalizedUnit)
    if not frame then
        self:RequestSharedMapSelfHeal(InCombatLockdown(), "mapped_miss")
        frame, resolvedUnit = self:ResolveSharedMappedFrame(normalizedUnit)
    end
    if not frame then
        frame, resolvedUnit = findMappedFrameFallback(normalizedUnit)
    end

    if not frame then
        if self._diagnosticsEnabled then
            print(string.format(
                "[mummuFrames:AuraHandle] mapped refresh miss unit=%s source=%s",
                tostring(normalizedUnit),
                tostring(source or "unknown")
            ))
        end
        return finishPerfCounters(self, "RefreshMappedUnit", perfStartedAt, false)
    end

    self:RefreshGroupFrameAuras(frame, resolvedUnit or normalizedUnit, skipTrackedScan, rawUnitToken)

    if self._diagnosticsEnabled then
        print(string.format(
            "[mummuFrames:AuraHandle] mapped refresh unit=%s source=%s",
            tostring(resolvedUnit or normalizedUnit),
            tostring(source or "unknown")
        ))
    end

    return finishPerfCounters(self, "RefreshMappedUnit", perfStartedAt, true)
end

-- ---------------------------------------------------------------------------
-- Group event dispatcher
-- ---------------------------------------------------------------------------

-- Resolve the mapped frame and owning module for a shared group unit event.
function AuraHandle:ResolveGroupDispatchTarget(normalizedUnit, eventName)
    local frame, resolvedUnit, ownerKey = self:ResolveSharedMappedFrame(normalizedUnit)
    if not frame then
        self:RequestSharedMapSelfHeal(InCombatLockdown(), "dispatch_miss")
        frame, resolvedUnit, ownerKey = self:ResolveSharedMappedFrame(normalizedUnit)
    end

    if not frame then
        if self._diagnosticsEnabled then
            print(string.format(
                "[mummuFrames:AuraHandle] dispatcher miss event=%s unit=%s",
                tostring(eventName),
                tostring(normalizedUnit)
            ))
        end
        return nil, nil, nil
    end

    local addon = self:GetAddon()
    if not addon then
        return nil, nil, nil
    end

    local effectiveUnit = resolvedUnit or normalizedUnit
    local effectiveOwnerKey = ownerKey or inferOwnerForUnit(effectiveUnit)
    local module = getModuleForOwner(addon, effectiveOwnerKey)
    if not module then
        return nil, nil, nil, nil
    end

    return frame, effectiveUnit, module, effectiveOwnerKey
end

-- Routes a unit event to the appropriate mummu module for the unit's owner.
-- UNIT_AURA is handled specially: tracker icons are refreshed directly here
-- (the CompactUnitFrame_UpdateAuras hook is unreliable in combat), and
-- the owning module is asked to rebuild its map on a miss.
function AuraHandle:DispatchGroupUnitEvent(eventName, unitToken, eventPayload)
    local perfStartedAt = startPerfCounters(self)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
    end

    if eventName == "UNIT_AURA" then
        -- Prime the dedicated group debuff cache directly from the clean event
        -- payload. This keeps debuff icons and dispel overlays aligned with the
        -- same UNIT_AURA deltas that Midnight exposes to modern addons.
        self:RefreshDebuffCacheFromUnitAuras(unitToken, eventPayload, nil, "unit_aura_dispatch")

        -- Drive the tracker refresh directly from UNIT_AURA.
        -- RefreshFrameTrackedAuras reads C_UnitAuras directly and does not
        -- depend on Blizzard's compact-frame display filter.
        -- Pass unitToken (raw, clean from WoW event system) as rawUnitToken so that
        -- C_UnitAuras.GetAuraDataByIndex receives an untainted argument.
        local refreshed = self:RefreshMappedUnit(normalizedUnit, "unit_aura_dispatch", nil, unitToken)
        if refreshed then
            return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
        end

        -- Combat roster transitions can leave the shared map temporarily stale.
        -- Ask the owning module to rebuild its mapping and retry.
        local addon = self:GetAddon()
        if not addon then
            return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
        end

        local module = getModuleForOwner(addon, inferOwnerForUnit(normalizedUnit))
        if not module then
            return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
        end

        local allowHidden = InCombatLockdown()
        if type(module.RebuildDisplayedUnitMap) == "function" then
            module:RebuildDisplayedUnitMap(allowHidden)
        end

        if type(module.EnsureMappedFrameForUnit) == "function" then
            local ensuredFrame = module:EnsureMappedFrameForUnit(normalizedUnit)
            if type(ensuredFrame) == "table" then
                local mappedUnit = getFrameUnitToken(ensuredFrame) or normalizedUnit
                self:RefreshGroupFrameAuras(ensuredFrame, mappedUnit, nil, unitToken)
                self:RebuildSharedUnitFrameMap(allowHidden, "unit_aura_dispatch_ensure")
            end
        end
        return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
    end

    local frame, resolvedUnit, module, ownerKey = self:ResolveGroupDispatchTarget(normalizedUnit, eventName)
    if not frame or not module then
        return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
    end

    if eventName == "UNIT_IN_RANGE_UPDATE" then
        -- Range churn only affects alpha, so prefer the dedicated light-weight
        -- path instead of re-running a full vitals refresh.
        local normalizedInRange = nil
        if Util and type(Util.NormalizeBooleanLike) == "function" then
            normalizedInRange = Util:NormalizeBooleanLike(eventPayload)
        end
        if type(module.RefreshDisplayedMappedFrameRangeState) == "function" then
            module:RefreshDisplayedMappedFrameRangeState(frame, resolvedUnit, normalizedInRange)
            return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
        end

        if type(module.RefreshDisplayedUnitRangeState) == "function" then
            module:RefreshDisplayedUnitRangeState(resolvedUnit, normalizedInRange)
            return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
        end
    end

    if shouldSkipGroupVitalsRefresh(ownerKey, eventName) then
        return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
    end

    -- Non-UNIT_AURA events: forward a vitals-only refresh to the owning module.
    if type(module.RefreshDisplayedMappedFrame) == "function" then
        module:RefreshDisplayedMappedFrame(frame, resolvedUnit, VITALS_ONLY_REFRESH)
        return finishPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
    end

    if type(module.RefreshDisplayedUnit) == "function" then
        module:RefreshDisplayedUnit(resolvedUnit, VITALS_ONLY_REFRESH)
    end
    recordPerfCounters(self, "DispatchGroupUnitEvent", perfStartedAt)
end

-- Creates the group-level event dispatcher frame for non-UNIT_AURA events.
function AuraHandle:EnsureGroupEventDispatcher()
    if type(CreateFrame) ~= "function" then
        return
    end
    if type(groupDispatcherFrames) == "table" and #groupDispatcherFrames > 0 then
        return
    end

    local selfRef           = self
    local unpackGroupUnits = (table and table.unpack) or unpack
    local fallbackFrame    = nil
    local fallbackEvents   = {}

    local function attachDispatcherScript(frame)
        frame:SetScript("OnEvent", function(_, eventName, unitToken, eventPayload)
            selfRef:DispatchGroupUnitEvent(eventName, unitToken, eventPayload)
        end)
    end

    for chunkIndex = 1, #GROUP_EVENT_UNIT_CHUNKS do
        local unitChunk = GROUP_EVENT_UNIT_CHUNKS[chunkIndex]
        local frame     = CreateFrame("Frame")
        local registeredAnyEvent = false

        for eventIndex = 1, #GROUP_EVENT_NAMES do
            local eventName = GROUP_EVENT_NAMES[eventIndex]
            if eventName ~= "UNIT_AURA" then
                local registeredWithUnitFilter = tryRegisterFilteredGroupEvent(frame, eventName, unitChunk, unpackGroupUnits)
                if registeredWithUnitFilter then
                    registeredAnyEvent = true
                elseif fallbackEvents[eventName] ~= true then
                    if type(fallbackFrame) ~= "table" then
                        fallbackFrame = CreateFrame("Frame", "mummuFramesAuraGroupDispatcher")
                        attachDispatcherScript(fallbackFrame)
                    end
                    fallbackFrame:RegisterEvent(eventName)
                    fallbackEvents[eventName] = true
                end
            end
        end

        if registeredAnyEvent then
            attachDispatcherScript(frame)
            groupDispatcherFrames[#groupDispatcherFrames + 1] = frame
        end
    end

    if type(fallbackFrame) == "table" then
        groupDispatcherFrames[#groupDispatcherFrames + 1] = fallbackFrame
    end

    self:EnsureUnitAuraDispatchers()
end

-- Creates one lightweight frame per group unit token, each registered for
-- UNIT_AURA via RegisterUnitEvent for precise per-unit filtering.
function AuraHandle:EnsureUnitAuraDispatchers()
    if type(CreateFrame) ~= "function" then
        return
    end
    if type(unitAuraDispatcherFrames) == "table" and #unitAuraDispatcherFrames > 0 then
        return
    end

    local selfRef = self
    for i = 1, #GROUP_UNIT_TOKENS do
        local unitToken = GROUP_UNIT_TOKENS[i]
        local frame     = CreateFrame("Frame")

        if type(frame.RegisterUnitEvent) == "function" then
            frame:RegisterUnitEvent("UNIT_AURA", unitToken)
        else
            frame:RegisterEvent("UNIT_AURA")
        end

        frame:SetScript("OnEvent", function(_, eventName, eventUnitToken, auraUpdateInfo)
            -- Prefer the event's own unit token; fall back to the registered one.
            local dispatchUnit = (type(eventUnitToken) == "string" and eventUnitToken ~= "")
                and eventUnitToken
                or unitToken
            selfRef:DispatchGroupUnitEvent(eventName, dispatchUnit, auraUpdateInfo)
        end)

        unitAuraDispatcherFrames[#unitAuraDispatcherFrames + 1] = frame
    end
end

-- ---------------------------------------------------------------------------
-- Aura configuration
-- ---------------------------------------------------------------------------

-- Rebuilds _spellIconCache from the current allowedSpells list.
-- Resolves each spell name to an icon texture using GetSpellInfo (accepts names).
-- Must be called outside combat (on login or when the list changes).
function AuraHandle:RebuildSpellIconCache()
    local config = self:GetAurasConfig()
    local spells = config and type(config.allowedSpells) == "table" and config.allowedSpells or {}
    for k in pairs(_spellIconCache) do
        _spellIconCache[k] = nil
    end
    for k in pairs(_trackerSpellInfoCache) do
        _trackerSpellInfoCache[k] = nil
    end
    for i = 1, #spells do
        local name = spells[i]
        if type(name) == "string" and name ~= "" then
            local info = getResolvedSpellInfo(name)
            local icon = info and (info.iconID or info.originalIconID) or nil
            local spellIDs = {}
            local seenSpellIDs = {}
            local overrideSpellIDs = TRACKER_SPELL_ID_OVERRIDES_BY_NAME[name]
            if type(overrideSpellIDs) == "table" then
                for spellIndex = 1, #overrideSpellIDs do
                    addUniqueSpellID(spellIDs, seenSpellIDs, overrideSpellIDs[spellIndex])
                end
            end
            addUniqueSpellID(spellIDs, seenSpellIDs, info and info.spellID)
            _spellIconCache[name] = icon
            _trackerSpellInfoCache[name] = {
                name = info and info.name or name,
                spellIDs = spellIDs,
                icon = icon,
                preferDirectSpellIDMatch = type(overrideSpellIDs) == "table" and #overrideSpellIDs > 0,
            }
        end
    end
end

-- Writes all missing defaults into profile.auras exactly once (before combat).
-- Safe to call multiple times; re-entrancy guarded by nil checks.
function AuraHandle:InitializeAurasDefaults()
    local dataHandle = self:GetDataHandle()
    if not dataHandle or type(dataHandle.GetProfile) ~= "function" then
        return
    end
    local profile = dataHandle:GetProfile()
    if type(profile) ~= "table" then
        return
    end

    profile.auras = profile.auras or {}
    local config  = profile.auras

    if config.enabled == nil then
        config.enabled = true
    end
    if config.size == nil then
        config.size = DEFAULT_TRACKER_SIZE
    end
    if config.allowedSpells == nil then
        config.allowedSpells = self:GetClassDefaultAuraNames()
    end
    self:RebuildSpellIconCache()
end

-- Returns the raw auras config table (profile.auras) for reading.
-- Does NOT mutate config values — call InitializeAurasDefaults first.
function AuraHandle:GetAurasConfig()
    local dataHandle = self:GetDataHandle()
    if not dataHandle or type(dataHandle.GetProfile) ~= "function" then
        return nil
    end

    local profile = dataHandle:GetProfile()
    if type(profile) ~= "table" then
        return nil
    end

    -- Ensure the sub-table exists (first-boot guard; normally done by InitializeAurasDefaults).
    if type(profile.auras) ~= "table" then
        self:InitializeAurasDefaults()
    end

    return profile.auras
end

-- Returns the default spell-name list for the current player class.
-- Always returns a new copy so callers may mutate it freely.
function AuraHandle:GetClassDefaultAuraNames()
    if Util and type(Util.GetTrackedAuraDefaultNames) == "function" then
        return Util:GetTrackedAuraDefaultNames()
    end
    return {}
end

-- Replaces allowedSpells with the class defaults and rebuilds the icon cache.
function AuraHandle:ResetAurasToClassDefaults()
    local config = self:GetAurasConfig()
    if not config then return end
    config.allowedSpells = self:GetClassDefaultAuraNames()
    self:RebuildSpellIconCache()
end

-- Signals that allowedSpells changed; rebuilds the icon cache.
-- Called by configuration.lua when the user adds or removes a spell.
function AuraHandle:InvalidateAuraNameSetCache()
    self:RebuildSpellIconCache()
end

-- ---------------------------------------------------------------------------
-- Aura query helpers
-- ---------------------------------------------------------------------------

-- Returns an array of aura data tables for every non-secret instance of spellID
-- on unitToken matching filter ("HELPFUL" or "HARMFUL"). Secret indexes are
-- skipped so this may return partial results in restricted combat contexts.
function AuraHandle:GetAurasBySpellID(unitToken, filter, spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID or type(unitToken) ~= "string" then
        return {}
    end

    local matches = {}
    for index = 1, MAX_AURA_SCAN do
        if not isAuraIndexSecret(unitToken, index, filter) then
            local auraData = getAuraDataByIndex(unitToken, index, filter)
            if not auraData then
                break
            end
            local auraSpellID = normalizeSpellID(auraData.spellId)
            if auraSpellID and auraSpellID == normalizedSpellID then
                matches[#matches + 1] = {
                    name           = auraData.name,
                    auraInstanceID = auraData.auraInstanceID,
                    icon           = auraData.icon,
                    count          = auraData.applications,
                    duration       = auraData.duration,
                    expirationTime = auraData.expirationTime,
                    spellId        = auraSpellID,
                }
            end
        end
    end
    return matches
end

-- ---------------------------------------------------------------------------
-- Public group-aura refresh entry point (called by party/raid modules)
-- ---------------------------------------------------------------------------

-- Refreshes aura indicators on frame for unitToken.  Clears all indicators
-- when previewMode is true or the unit does not exist.
-- Returns the dispellable debuff type string, or nil.
function AuraHandle:RefreshGroupAuras(frame, unitToken, exists, previewMode)
    if previewMode then
        self:ClearFrameAuraIndicators(frame)
        self:RefreshFrameDebuffIcons(frame, unitToken, true)
        return nil
    end
    if exists ~= true then
        self:ClearFrameAuraIndicators(frame)
        return nil
    end
    self:RefreshGroupFrameAuras(frame, unitToken)
    return self:GetUnitDispellableDebuffType(unitToken)
end

-- ---------------------------------------------------------------------------
-- Cache management
-- ---------------------------------------------------------------------------

-- Legacy helper name kept for compatibility with older internal call sites.
-- It now reports freshness for the dedicated group debuff cache.
function AuraHandle:WasBlizzardUnitSeenRecently(unitToken, windowSeconds)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return false
    end
    local state = groupDebuffStateByUnit[normalizedUnit]
    local updatedAt = state and tonumber(state.updatedAt) or 0
    if updatedAt <= 0 then
        return false
    end
    local window = tonumber(windowSeconds) or 3
    if window < 0 then
        window = 3
    end
    return (getSafeNowSeconds() - updatedAt) <= window
end

-- Clears the Blizzard compact-frame aura cache and the live group debuff cache
-- for unitToken, or for all units when unitToken is nil/empty.
function AuraHandle:ClearBlizzardBuffCache(unitToken)
    if type(unitToken) == "string" and unitToken ~= "" then
        blizzardAuraCacheByUnit[unitToken] = nil
        groupDebuffStateByUnit[unitToken] = nil
    else
        wipeTable(blizzardAuraCacheByUnit)
        wipeTable(groupDebuffStateByUnit)
    end
end

-- ---------------------------------------------------------------------------
-- Module export
-- ---------------------------------------------------------------------------

ns.AuraHandleClass = AuraHandle
ns.AuraHandle      = AuraHandle:New()
