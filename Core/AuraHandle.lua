-- AuraHandle.lua
-- Manages aura/buff caching, player-cast HoT indicators, dispel overlays, and
-- the suppression of Blizzard's compact unit frames when mummuFrames replaces them.
--
-- Architecture overview:
--   * A hook on CompactUnitFrame_UpdateAuras populates blizzardAuraCacheByUnit,
--     a per-unit set of active auraInstanceIDs keyed by category (buffs, debuffs,
--     playerDispellable, defensives).
--   * Per-unit UNIT_AURA dispatcher frames drive indicator refreshes directly,
--     bypassing Blizzard's compact frame filter which is unreliable in combat.
--   * A shared unitToken→frame map (sharedUnitFrameMap) lets the dispatcher
--     locate the mummu frame for any group unit without scanning every frame.
--   * HoT/buff indicators use the "HELPFUL|PLAYER" aura filter to show only
--     spells the player personally cast on each target — no whitelist needed.

local _, ns = ...

local Util  = ns.Util
local Style = ns.Style
local AuraSafety = ns.AuraSafety


-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local MAX_AURA_SCAN        = 80
local DEFAULT_AURA_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local DISPEL_OVERLAY_ALPHA = 0.24

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
local DEFAULT_TRACKER_SIZE = 14
-- Shared tracker filter: player-cast helpful auras, reliable in combat.
local TRACKER_PLAYER_HELPFUL_FILTER = "HELPFUL|PLAYER|RAID_IN_COMBAT"
local DISPEL_TYPE_PRIORITY  = { "Magic", "Curse", "Poison", "Disease" }

-- Per-class default spell-name whitelists. Empty table = no name filter (show all player-cast buffs).
local CLASS_DEFAULT_AURA_NAMES = {
    DEATHKNIGHT = {},
    DEMONHUNTER = {},
    DRUID    = { "Rejuvenation", "Germination", "Wild Growth", "Regrowth", "Lifebloom", "Cenarion Ward" },
    EVOKER   = { "Reversion", "Echo", "Temporal Anomaly", "Dream Breath" },
    HUNTER   = {},
    MAGE     = {},
    MONK     = { "Renewing Mist", "Enveloping Mist", "Life Cocoon" },
    PALADIN  = { "Beacon of Light", "Beacon of Faith", "Sacred Shield", "Aura Mastery" },
    PRIEST   = { "Renew", "Atonement", "Power Word: Shield", "Prayer of Mending" },
    ROGUE    = {},
    SHAMAN   = { "Riptide", "Unleash Life", "Earthen Wall Totem" },
    WARLOCK  = {},
    WARRIOR  = {},
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
    "UNIT_FLAGS",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_AURA",
    "INCOMING_SUMMON_CHANGED",
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
-- blizzardAuraCacheByUnit[unitToken] = {
--   buffs            : { [auraInstanceID] = true }
--   debuffs          : { [auraInstanceID] = true }
--   playerDispellable: { [auraInstanceID] = true }
--   playerDispellableTypeByAuraID: { [auraInstanceID] = "Magic"|"Curse"|"Poison"|"Disease" }
--   playerDispellableTypeSet      : { Magic=true, Curse=true, Poison=true, Disease=true }
--   defensives       : { [auraInstanceID] = true }
--   updatedAt        : number  (GetTime() at last capture)
-- }
local blizzardAuraCacheByUnit = {}

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
    updateBuffs      = false,
    updateDebuffs    = false,
    updateUnitEvents = false,
}

-- Bootstrap frame token: incremented each time a new bootstrap sequence is
-- started so that stale C_Timer callbacks can detect they are outdated.
local cacheBootstrapToken = 0

-- Persistent WoW frames created at construction time.
local cacheBootstrapFrame      = nil
local groupDispatcherFrame     = nil
local unitAuraDispatcherFrames = {}

-- Pre-resolved icon textures for whitelisted spell names (spellName → texture path).
-- Built by RebuildSpellIconCache outside combat so the hot path never reads
-- tainted auraData.icon fields.
local _spellIconCache = {}

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

-- Coerces a value to a positive integer spell ID.
-- WoW Lua marks spell IDs from C_UnitAuras as "secret tainted numbers" in
-- combat: arithmetic, comparison, AND table-indexing on them is forbidden.
-- Passing an already-clean number skips all coercion so the tainted value is
-- never touched.  Non-number values are converted via tonumber().
local function normalizeSpellID(value)
    if type(value) == "number" then
        return value
    end
    local numeric = tonumber(value)
    if type(numeric) ~= "number" then
        return nil
    end
    local rounded = math.floor(numeric + 0.5)
    if rounded <= 0 then
        return nil
    end
    return rounded
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

-- Returns true when ownerKey is a recognised group owner ("party").
local function isGroupOwner(ownerKey)
    return ownerKey == "party"
end

-- Returns the owner key for a group unit token, or nil.
local function inferOwnerForUnit(unitToken)
    if type(unitToken) ~= "string" then
        return nil
    end
    if unitToken == "player" or string.match(unitToken, "^party%d+$") then
        return "party"
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

local function safeTruthy(value)
    if AuraSafety and type(AuraSafety.SafeTruthy) == "function" then
        return AuraSafety:SafeTruthy(value)
    end
    local ok, resolved = pcall(function()
        return value == true
    end)
    return ok and resolved == true
end

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
    cache.playerDispellable = cache.playerDispellable or {}
    cache.playerDispellableTypeByAuraID = cache.playerDispellableTypeByAuraID or {}
    cache.playerDispellableTypeSet = cache.playerDispellableTypeSet or {}
    cache.defensives = cache.defensives or {}
    if type(cache.updatedAt) ~= "number" then
        cache.updatedAt = 0
    end

    return cache
end

-- Extracts the normalised group unit token from any frame that exposes a unit
-- via .displayedUnit, .unit, or GetAttribute("unit").
local function getFrameUnitToken(frame)
    if type(frame) ~= "table" then
        return nil
    end
    local unitToken = frame.displayedUnit or frame.unit
    if (type(unitToken) ~= "string" or unitToken == "") and type(frame.GetAttribute) == "function" then
        local ok, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(attrUnit) == "string" and attrUnit ~= "" then
            unitToken = attrUnit
        end
    end
    return normalizeGroupUnitToken(unitToken)
end

-- Collects all mummu group frames (party header children) into a flat array.
local function getAllMummuGroupFrames()
    -- Prefer the authoritative list published by partyFrames after each RefreshAll.
    -- This includes the solo player frame (testFrames[5]) when not in a group.
    if type(ns.activeMummuGroupFrames) == "table" and #ns.activeMummuGroupFrames > 0 then
        return ns.activeMummuGroupFrames
    end
    -- Fallback: scan header children (covers the case before first RefreshAll).
    local frames = {}
    local header = _G["mummuFramesPartyHeader"]
    if header and type(header.GetChildren) == "function" then
        local children = { header:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child then
                frames[#frames + 1] = child
            end
        end
    end
    return frames
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
    if frame._mummuIsPartyFrame == true then
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

-- Collects visible auraInstanceIDs from a Blizzard aura frame list into setTarget.
local function captureFromCompactAuraList(auraList, setTarget)
    if type(auraList) ~= "table" then
        return
    end
    for _, auraFrame in pairs(auraList) do
        if type(auraFrame) == "table" and auraFrame.auraInstanceID then
            local shown = true
            if type(auraFrame.IsShown) == "function" then
                local ok, shownValue = pcall(auraFrame.IsShown, auraFrame)
                if ok then
                    shown = shownValue == true
                end
            end
            if shown then
                setTarget[auraFrame.auraInstanceID] = true
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

local function safeSetScale(frame, scale)
    if not frame or type(frame.SetScale) ~= "function" then
        return
    end
    if InCombatLockdown() then
        return
    end
    pcall(frame.SetScale, frame, scale)
end

local function safeEnableMouse(frame, enabled)
    if not frame or type(frame.EnableMouse) ~= "function" then
        return
    end
    if InCombatLockdown() then
        return
    end
    pcall(frame.EnableMouse, frame, enabled)
end

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

-- Fetches aura data by scan index; returns the auraData table or nil.
-- Uses ns.AuraSafety when available so secret indexes are skipped safely.
local function getAuraDataByIndex(unitToken, index, filter)
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

local function isAuraIndexSecret(unitToken, index, filter)
    if AuraSafety and type(AuraSafety.IsAuraIndexSecret) == "function" then
        return AuraSafety:IsAuraIndexSecret(unitToken, index, filter)
    end
    return false
end

local function isAuraInstanceSecret(unitToken, auraInstanceID)
    if AuraSafety and type(AuraSafety.IsAuraInstanceSecret) == "function" then
        return AuraSafety:IsAuraInstanceSecret(unitToken, auraInstanceID)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- AuraHandle class
-- ---------------------------------------------------------------------------

function AuraHandle:Constructor()
    self.addon      = nil
    self.dataHandle = nil

    self._diagnosticsEnabled = false

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

    local function runScan(delayTag)
        if token ~= cacheBootstrapToken then
            return
        end
        selfRef:ScanAllBlizzardFrames(true, "bootstrap:" .. tostring(delayTag))
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

function AuraHandle:SetDiagnosticsEnabled(enabled)
    self._diagnosticsEnabled = enabled == true
end

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
    wipeTable(cache.playerDispellable)
    wipeTable(cache.playerDispellableTypeByAuraID)
    wipeTable(cache.playerDispellableTypeSet)
    wipeTable(cache.defensives)

    captureFromCompactAuraList(frame.buffFrames,   cache.buffs)
    captureFromCompactAuraList(frame.debuffFrames, cache.debuffs)

    -- dispelDebuffFrames: a subset of debuffs that the player can remove.
    if type(frame.dispelDebuffFrames) == "table" then
        for _, debuffFrame in pairs(frame.dispelDebuffFrames) do
            if type(debuffFrame) == "table" and debuffFrame.auraInstanceID then
                local shown = true
                if type(debuffFrame.IsShown) == "function" then
                    local ok, shownValue = pcall(debuffFrame.IsShown, debuffFrame)
                    if ok then
                        shown = shownValue == true
                    end
                end
                if shown then
                    local auraInstanceID = debuffFrame.auraInstanceID
                    cache.debuffs[auraInstanceID]           = true
                    cache.playerDispellable[auraInstanceID] = true

                    local dispelType = extractDispelTypeFromCompactDebuffFrame(debuffFrame)
                    if dispelType then
                        cache.playerDispellableTypeByAuraID[auraInstanceID] = dispelType
                        cache.playerDispellableTypeSet[dispelType] = true
                    end
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
    -- Pass dispelOnly=true so RefreshFrameTrackedAuras is never called here.
    self:RefreshMappedUnit(normalizedUnit, source or "hook", true)
end

-- Returns the approved aura instance ID set for unitToken and auraType.
-- auraType: "DEBUFF" → debuffs, anything else → buffs.
function AuraHandle:GetApprovedAuraSet(unitToken, auraType)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end
    local cache = blizzardAuraCacheByUnit[normalizedUnit]
    if type(cache) ~= "table" then
        return nil
    end
    return auraType == "DEBUFF" and cache.debuffs or cache.buffs
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

-- ---------------------------------------------------------------------------
-- Aura tracker rendering
-- Displays icons for buffs the player personally cast on the target unit.
-- Uses the "HELPFUL|PLAYER" filter — no spell whitelist needed.
-- ---------------------------------------------------------------------------

-- Redraws the tracker icon strip on frame for the given unitToken.
function AuraHandle:RefreshFrameTrackedAuras(frame, unitToken)
    if type(frame) ~= "table" then
        return
    end
    if frame._mummuIsPartyFrame ~= true then
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
        -- Whitelist path: iterate OUR clean spell names and ask WoW whether each
        -- is active.  AuraUtil.FindAuraByName calls C_UnitAuras.GetAuraDataBySpellName
        -- (a C-level lookup) — no Lua comparison of secret/tainted aura fields.
        -- Whitelist mode is strict player-cast only: use HELPFUL|PLAYER with
        -- RAID_IN_COMBAT to keep lookups reliable during combat updates.
        local findAura = AuraUtil and AuraUtil.FindAuraByName
        local canFindAuraByName = type(findAura) == "function"
        for i = 1, #allowedSpells do
            if count >= MAX_TRACKER_AURAS then
                break
            end
            local spellName = allowedSpells[i]
            local ok, found = false, nil
            if canFindAuraByName then
                ok, found = pcall(findAura, spellName, unitToken, TRACKER_PLAYER_HELPFUL_FILTER)
            end
            if ok and found then
                count = count + 1
                local element = ensureTrackerElement(frame, count)
                element:SetSize(size, size)
                element:ClearAllPoints()
                element:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(count - 1) * (size + 2), 0)
                safeSetTexture(element.Icon, _spellIconCache[spellName] or DEFAULT_AURA_TEXTURE)
                element.Icon:Show()
                element:Show()
                usedByKey[tostring(count)] = true
            end
        end
    else
        -- No-whitelist path: show all player-cast buffs by index scan.
        -- No name comparison needed — no taint risk.
        for index = 1, MAX_AURA_SCAN do
            if count >= MAX_TRACKER_AURAS then
                break
            end
            if not isAuraIndexSecret(unitToken, index, TRACKER_PLAYER_HELPFUL_FILTER) then
                local auraData = getAuraDataByIndex(unitToken, index, TRACKER_PLAYER_HELPFUL_FILTER)
                if not auraData then
                    break
                end
                count = count + 1
                local element = ensureTrackerElement(frame, count)
                element:SetSize(size, size)
                element:ClearAllPoints()
                element:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(count - 1) * (size + 2), 0)
                if not safeSetTexture(element.Icon, auraData.icon) then
                    safeSetTexture(element.Icon, DEFAULT_AURA_TEXTURE)
                end
                element.Icon:Show()
                element:Show()
                usedByKey[tostring(count)] = true
            end
        end
    end

    hideUnusedTrackerElements(frame, usedByKey)
end

-- ---------------------------------------------------------------------------
-- Dispel overlay
-- ---------------------------------------------------------------------------

-- Returns the debuff type string ("Magic", "Curse", "Poison", "Disease") for
-- the first player-dispellable debuff found on unitToken, or nil.
function AuraHandle:GetUnitDispellableDebuffType(unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return nil
    end

    local cache = blizzardAuraCacheByUnit[normalizedUnit]
    if type(cache) ~= "table" then
        return nil
    end

    local playerDispelTypeSet = getPlayerDispelTypeSet()

    -- Per-aura type map is the most specific source and avoids aura payload reads.
    if type(cache.playerDispellableTypeByAuraID) == "table" and type(cache.playerDispellable) == "table" then
        for auraInstanceID in pairs(cache.playerDispellable) do
            local debuffType = cache.playerDispellableTypeByAuraID[auraInstanceID]
            if debuffType and playerDispelTypeSet[debuffType] == true then
                return debuffType
            end
        end
    end

    -- Fall back to compact-frame type flags when per-aura mapping is unavailable.
    if type(cache.playerDispellableTypeSet) == "table" then
        for i = 1, #DISPEL_TYPE_PRIORITY do
            local debuffType = DISPEL_TYPE_PRIORITY[i]
            if cache.playerDispellableTypeSet[debuffType] == true and playerDispelTypeSet[debuffType] == true then
                return debuffType
            end
        end
    end

    return nil
end

-- Shows or hides the dispel colour overlay on frame based on whether the unit
-- has a dispellable debuff.
function AuraHandle:RefreshFrameDispelOverlay(frame, unitToken)
    if type(frame) ~= "table" or type(frame.DispelOverlay) ~= "table" then
        return
    end
    local dispelType = self:GetUnitDispellableDebuffType(unitToken)
    local color      = dispelType and DebuffTypeColor and DebuffTypeColor[dispelType] or nil
    if color then
        frame.DispelOverlay:SetColorTexture(color.r, color.g, color.b, DISPEL_OVERLAY_ALPHA)
        frame.DispelOverlay:Show()
    else
        frame.DispelOverlay:Hide()
    end
end

-- Hides all aura indicators (tracker elements + dispel overlay) on frame.
function AuraHandle:ClearFrameAuraIndicators(frame)
    if type(frame) ~= "table" then
        return
    end
    hideUnusedTrackerElements(frame, {})
    if frame.DispelOverlay and type(frame.DispelOverlay.Hide) == "function" then
        frame.DispelOverlay:Hide()
    end
end

-- Updates aura indicators on a group frame.
-- When dispelOnly is true only the dispel overlay is refreshed (used by the
-- Blizzard-frame hook path whose unitToken may be tainted).
-- rawUnitToken: if provided, passed to RefreshFrameTrackedAuras for untainted
-- C_UnitAuras API calls; falls back to unitToken when absent.
function AuraHandle:RefreshGroupFrameAuras(frame, unitToken, dispelOnly, rawUnitToken)
    if not shouldFrameRenderAuras(frame) then
        return
    end
    if not dispelOnly then
        self:RefreshFrameTrackedAuras(frame, rawUnitToken or unitToken)
    end
    self:RefreshFrameDispelOverlay(frame, unitToken)
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
function AuraHandle:RefreshMappedUnit(unitToken, source, dispelOnly, rawUnitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return false
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
        return false
    end

    self:RefreshGroupFrameAuras(frame, resolvedUnit or normalizedUnit, dispelOnly, rawUnitToken)

    if self._diagnosticsEnabled then
        print(string.format(
            "[mummuFrames:AuraHandle] mapped refresh unit=%s source=%s",
            tostring(resolvedUnit or normalizedUnit),
            tostring(source or "unknown")
        ))
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Group event dispatcher
-- ---------------------------------------------------------------------------

-- Routes a unit event to the appropriate mummu module for the unit's owner.
-- UNIT_AURA is handled specially: tracker icons are refreshed directly here
-- (the CompactUnitFrame_UpdateAuras hook is unreliable in combat), and
-- the owning module is asked to rebuild its map on a miss.
function AuraHandle:DispatchGroupUnitEvent(eventName, unitToken)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return
    end

    if eventName == "UNIT_AURA" then
        -- Drive the tracker refresh directly from UNIT_AURA.
        -- "HELPFUL|PLAYER" scanning in RefreshFrameTrackedAuras reads
        -- C_UnitAuras directly and does not depend on Blizzard's compact-frame
        -- display filter.
        -- Pass unitToken (raw, clean from WoW event system) as rawUnitToken so that
        -- C_UnitAuras.GetAuraDataByIndex receives an untainted argument.
        local refreshed = self:RefreshMappedUnit(normalizedUnit, "unit_aura_dispatch", nil, unitToken)
        if refreshed then
            return
        end

        -- Combat roster transitions can leave the shared map temporarily stale.
        -- Ask the owning module to rebuild its mapping and retry.
        local addon = self:GetAddon()
        if not addon or type(addon.GetModule) ~= "function" then
            return
        end

        local module     = addon:GetModule("partyFrames")
        if not module then
            return
        end

        local allowHidden = InCombatLockdown()
        if type(module.RebuildDisplayedUnitMap) == "function" then
            module:RebuildDisplayedUnitMap(allowHidden)
        end

        if type(module.EnsureMappedFrameForUnit) == "function" then
            local ensuredFrame = module:EnsureMappedFrameForUnit(normalizedUnit)
            if type(ensuredFrame) == "table" then
                local mappedUnit = (type(ensuredFrame.displayedUnit) == "string" and ensuredFrame.displayedUnit ~= "")
                    and ensuredFrame.displayedUnit
                    or normalizedUnit
                self:RefreshGroupFrameAuras(ensuredFrame, mappedUnit, nil, unitToken)
                self:RebuildSharedUnitFrameMap(allowHidden, "unit_aura_dispatch_ensure")
            end
        end
        return
    end

    -- Non-UNIT_AURA events: forward a vitals-only refresh to the owning module.
    local frame, resolvedUnit = self:ResolveSharedMappedFrame(normalizedUnit)
    if not frame then
        self:RequestSharedMapSelfHeal(InCombatLockdown(), "dispatch_miss")
        frame, resolvedUnit = self:ResolveSharedMappedFrame(normalizedUnit)
    end

    if not frame then
        if self._diagnosticsEnabled then
            print(string.format(
                "[mummuFrames:AuraHandle] dispatcher miss event=%s unit=%s",
                tostring(eventName),
                tostring(normalizedUnit)
            ))
        end
        return
    end

    local addon = self:GetAddon()
    if not addon or type(addon.GetModule) ~= "function" then
        return
    end

    local module     = addon:GetModule("partyFrames")
    if not module then
        return
    end

    if type(module.RefreshDisplayedMappedFrame) == "function" then
        module:RefreshDisplayedMappedFrame(frame, resolvedUnit or normalizedUnit, VITALS_ONLY_REFRESH)
        return
    end

    if type(module.RefreshDisplayedUnit) == "function" then
        module:RefreshDisplayedUnit(resolvedUnit or normalizedUnit, VITALS_ONLY_REFRESH)
    end
end

-- Creates the group-level event dispatcher frame for non-UNIT_AURA events.
function AuraHandle:EnsureGroupEventDispatcher()
    if groupDispatcherFrame or type(CreateFrame) ~= "function" then
        return
    end

    local selfRef = self
    local frame   = CreateFrame("Frame", "mummuFramesAuraGroupDispatcher")

    for i = 1, #GROUP_EVENT_NAMES do
        local eventName = GROUP_EVENT_NAMES[i]
        if eventName ~= "UNIT_AURA" then
            frame:RegisterEvent(eventName)
        end
    end

    frame:SetScript("OnEvent", function(_, eventName, unitToken)
        selfRef:DispatchGroupUnitEvent(eventName, unitToken)
    end)

    groupDispatcherFrame = frame
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

        frame:SetScript("OnEvent", function(_, eventName, eventUnitToken)
            -- Prefer the event's own unit token; fall back to the registered one.
            local dispatchUnit = (type(eventUnitToken) == "string" and eventUnitToken ~= "")
                and eventUnitToken
                or unitToken
            selfRef:DispatchGroupUnitEvent(eventName, dispatchUnit)
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
    for i = 1, #spells do
        local name = spells[i]
        if type(name) == "string" and name ~= "" then
            -- C_Spell.GetSpellInfo accepts spell names and returns {iconID = fileDataID}.
            -- SetTexture accepts fileDataIDs (integers) directly.
            local icon
            if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
                local info = C_Spell.GetSpellInfo(name)
                icon = info and info.iconID
            end
            _spellIconCache[name] = icon or DEFAULT_AURA_TEXTURE
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
    local _, classToken = UnitClass("player")
    local defaults = classToken and CLASS_DEFAULT_AURA_NAMES[classToken]
    if not defaults then return {} end
    local copy = {}
    for i, v in ipairs(defaults) do copy[i] = v end
    return copy
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

-- Public alias kept for external callers (partyFrames, raidFrames, configuration).
function AuraHandle:GetHealerConfig()
    return self:GetAurasConfig()
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
    if previewMode or exists ~= true then
        self:ClearFrameAuraIndicators(frame)
        return nil
    end
    self:RefreshGroupFrameAuras(frame, unitToken)
    return self:GetUnitDispellableDebuffType(unitToken)
end

-- ---------------------------------------------------------------------------
-- Cache management
-- ---------------------------------------------------------------------------

-- Returns true when the Blizzard frame for unitToken was captured within
-- the given time window (default 3 seconds).
function AuraHandle:WasBlizzardUnitSeenRecently(unitToken, windowSeconds)
    local normalizedUnit = normalizeGroupUnitToken(unitToken)
    if not normalizedUnit then
        return false
    end
    local cache     = blizzardAuraCacheByUnit[normalizedUnit]
    local updatedAt = cache and tonumber(cache.updatedAt) or 0
    if updatedAt <= 0 then
        return false
    end
    local window = tonumber(windowSeconds) or 3
    if window < 0 then
        window = 3
    end
    return (getSafeNowSeconds() - updatedAt) <= window
end

-- Clears the Blizzard aura cache for unitToken, or for all units when
-- unitToken is nil/empty.
function AuraHandle:ClearBlizzardBuffCache(unitToken)
    if type(unitToken) == "string" and unitToken ~= "" then
        blizzardAuraCacheByUnit[unitToken] = nil
    else
        wipeTable(blizzardAuraCacheByUnit)
    end
end

-- ---------------------------------------------------------------------------
-- Module export
-- ---------------------------------------------------------------------------

ns.AuraHandleClass = AuraHandle
ns.AuraHandle      = AuraHandle:New()
