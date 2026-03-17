-- Misc shared helpers:
-- - numeric coercion/clamping
-- - formatted output
-- - deferred execution queue for combat-lockdown-safe updates

local _, ns = ...

-- Shared utility namespace.
local Util = {}
local GROUP_UNIT_FRIENDLY_RANGE_ITEM_ID = 1713
local GROUP_UNIT_INTERACT_RANGE_INDEX = 4
local TRACKED_AURA_DEFAULT_SIZE = 14
local TRACKED_AURA_DEFAULT_NAMES_BY_CLASS = {
    DEATHKNIGHT = {},
    DEMONHUNTER = {},
    DRUID = { "Rejuvenation", "Germination", "Wild Growth", "Regrowth", "Lifebloom", "Cenarion Ward" },
    EVOKER = { "Reversion", "Echo", "Temporal Anomaly", "Dream Breath" },
    HUNTER = {},
    MAGE = {},
    MONK = { "Renewing Mist", "Enveloping Mist", "Life Cocoon" },
    PALADIN = { "Beacon of Light", "Beacon of Faith", "Sacred Shield", "Aura Mastery" },
    PRIEST = { "Renew", "Atonement", "Power Word: Shield", "Prayer of Mending" },
    ROGUE = {},
    SHAMAN = { "Riptide", "Unleash Life", "Earthen Wall Totem" },
    WARLOCK = {},
    WARRIOR = {},
}

-- Coerce numeric-like input to a number or return fallback.
local function toNumberSafe(input, fallback)
    if type(input) == "number" then
        local okString, asString = pcall(tostring, input)
        if okString and type(asString) == "string" then
            local parsed = tonumber(asString)
            if type(parsed) == "number" then
                return parsed
            end
        end
        return fallback
    end

    if type(input) == "string" then
        local parsed = tonumber(input)
        if type(parsed) == "number" then
            return parsed
        end
        return fallback
    end

    local okTonumber, coerced = pcall(tonumber, input)
    if okTonumber and type(coerced) == "number" then
        return coerced
    end

    return fallback
end

-- Compare against literal true inside pcall to tolerate wrapped booleans.
local function equalsTrueSafe(value)
    local ok, resolved = pcall(function()
        return value == true
    end)
    if ok then
        return resolved == true
    end
    return false
end

-- Normalize WoW boolean-like returns (true/false, 1/0, "1"/"0") without
-- letting wrapped or secret values escape.
local function normalizeBooleanLike(value)
    if value == nil then
        return nil
    end

    if type(value) == "number" then
        return value ~= 0
    end

    if type(value) == "string" then
        local normalizedString = string.lower(value)
        if normalizedString == "true" or normalizedString == "1" then
            return true
        end
        if normalizedString == "false" or normalizedString == "0" or normalizedString == "" then
            return false
        end
    end

    local auraSafety = ns.AuraSafety
    if auraSafety and type(auraSafety.SafeTruthy) == "function" then
        local okSafeTruthy, resolved = pcall(auraSafety.SafeTruthy, auraSafety, value)
        if okSafeTruthy then
            return resolved == true
        end
        return nil
    end

    local okTruthy, resolvedTruthy = pcall(function()
        if value then
            return true
        end
        return false
    end)
    if okTruthy then
        return resolvedTruthy == true
    end

    return nil
end

-- Return true when Blizzard marks a value as secret/tainted on Retail.
local function isSecretValue(value)
    local secretCheck = _G.issecretvalue
    if type(secretCheck) ~= "function" then
        return false
    end

    local okSecret, isSecret = pcall(secretCheck, value)
    return okSecret and isSecret == true
end

-- Format large values using compact k/m suffixes.
local function formatAbbrevNumber(value)
    local n = tonumber(value) or 0
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(math.floor(n + 0.5))
end

-- Deferred callbacks that must wait until combat ends.
local deferredQueue = {}
-- Optional key index for de-duplicating deferred callbacks.
local deferredQueueByKey = {}
-- Flush deferred callbacks when combat lockdown ends.
local deferredFrame = CreateFrame("Frame")
deferredFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
deferredFrame:SetScript("OnEvent", function()
    for i = 1, #deferredQueue do
        local item = deferredQueue[i]
        if item and type(item.fn) == "function" then
            local ok, err = pcall(item.fn)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
    wipe(deferredQueue)
    wipe(deferredQueueByKey)
end)

-- Print addon message to chat.
function Util:Print(message)
    print("|cff77b9ffmummuFrames|r: " .. tostring(message))
end

-- Clamp a value into the inclusive min/max range.
function Util:Clamp(value, minValue, maxValue)
    local resolvedMin = toNumberSafe(minValue, 0)
    local resolvedMax = toNumberSafe(maxValue, resolvedMin)
    if resolvedMin > resolvedMax then
        resolvedMin, resolvedMax = resolvedMax, resolvedMin
    end

    local resolvedValue = toNumberSafe(value, resolvedMin)
    if resolvedValue < resolvedMin then
        return resolvedMin
    end
    if resolvedValue > resolvedMax then
        return resolvedMax
    end
    return resolvedValue
end

-- Resolve a boolean-like value without letting wrapped or secret values escape.
function Util:NormalizeBooleanLike(value)
    return normalizeBooleanLike(value)
end

-- Resolve a boolean-like value without letting wrapped or secret values escape.
function Util:SafeBoolean(value, fallback)
    local normalizedValue = normalizeBooleanLike(value)
    if normalizedValue ~= nil then
        return normalizedValue
    end

    local normalizedFallback = normalizeBooleanLike(fallback)
    if normalizedFallback ~= nil then
        return normalizedFallback
    end

    return equalsTrueSafe(fallback)
end

-- Read a unit GUID without letting secret-value wrappers or comparison faults
-- escape into callers that only need stable, non-secret GUID strings.
function Util:GetUnitGUIDSafe(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" or type(UnitGUID) ~= "function" then
        return nil
    end

    local okGUID, guid = pcall(UnitGUID, unitToken)
    if not okGUID or guid == nil or isSecretValue(guid) or type(guid) ~= "string" then
        return nil
    end

    local okNonEmpty, isNonEmpty = pcall(function()
        return guid ~= ""
    end)
    if okNonEmpty and isNonEmpty then
        return guid
    end

    return nil
end

-- Return whether a party or raid unit should be considered out of range.
-- Prefer confirmed positive probes over dimming on ambiguous API returns.
-- Some clients surface noisy UNIT_IN_RANGE_UPDATE payloads or transient
-- UnitInRange false negatives for valid party members, so only explicit direct
-- or 40-yard item misses should fade the frame.
function Util:GetGroupUnitInRangeState(unitToken, providedInRange)
    if type(unitToken) ~= "string" or unitToken == "" or unitToken == "player" then
        return true
    end

    if type(UnitExists) == "function" and not UnitExists(unitToken) then
        return nil
    end

    local normalizedProvidedInRange = normalizeBooleanLike(providedInRange)
    if normalizedProvidedInRange == true then
        return true
    end

    local normalizedDirectInRange = nil
    local normalizedCanCheckRange = nil
    if type(UnitInRange) == "function" then
        local okInRange, inRange, checkedRange = pcall(UnitInRange, unitToken)
        if okInRange then
            normalizedDirectInRange = normalizeBooleanLike(inRange)
            normalizedCanCheckRange = normalizeBooleanLike(checkedRange)

            if normalizedDirectInRange == true then
                return true
            end
        end
    end

    if C_Item and type(C_Item.IsItemInRange) == "function" then
        local okItemRange, inItemRange = pcall(C_Item.IsItemInRange, GROUP_UNIT_FRIENDLY_RANGE_ITEM_ID, unitToken)
        if okItemRange then
            local normalizedItemRange = normalizeBooleanLike(inItemRange)
            if normalizedItemRange ~= nil then
                return normalizedItemRange
            end
        end
    end

    if type(CheckInteractDistance) == "function" then
        local okInteractRange, inInteractRange = pcall(CheckInteractDistance, unitToken, GROUP_UNIT_INTERACT_RANGE_INDEX)
        if okInteractRange then
            local normalizedInteractRange = normalizeBooleanLike(inInteractRange)
            if normalizedInteractRange == true then
                return true
            end
        end
    end

    if normalizedCanCheckRange ~= false and normalizedDirectInRange ~= nil then
        return normalizedDirectInRange
    end

    return nil
end

-- Return whether a party or raid unit should be considered out of range.
-- Unknown range states are treated as in range to avoid false dimming.
function Util:IsGroupUnitOutOfRange(unitToken, providedInRange)
    return self:GetGroupUnitInRangeState(unitToken, providedInRange) == false
end

-- Format a number using Blizzard formatting, then fall back to compact suffixes.
function Util:FormatNumber(value)
    if BreakUpLargeNumbers then
        local okBuiltin, builtInFormatted = pcall(BreakUpLargeNumbers, value)
        if okBuiltin and builtInFormatted then
            return builtInFormatted
        end
    end

    -- Protected call keeps formatting errors from breaking UI updates.
    local okFormat, formatted = pcall(formatAbbrevNumber, value)

    if okFormat and formatted then
        return formatted
    end

    local okString, asString = pcall(tostring, value)
    if okString and asString then
        return asString
    end

    return "?"
end

-- Build the current character's stable name-realm key.
function Util:GetCharacterKey()
    local name, realm = UnitFullName("player")
    if not name then
        name = UnitName("player") or "Unknown"
    end
    realm = realm or GetRealmName() or "UnknownRealm"
    return string.format("%s-%s", name, realm)
end

-- Return the tracked aura icon size default shared across modules.
function Util:GetTrackedAuraDefaultSize()
    return TRACKED_AURA_DEFAULT_SIZE
end

-- Return a copied tracked aura whitelist for the current or provided class.
function Util:GetTrackedAuraDefaultNames(classToken)
    local resolvedClassToken = classToken
    if type(resolvedClassToken) ~= "string" or resolvedClassToken == "" then
        local _, liveClassToken = UnitClass("player")
        resolvedClassToken = liveClassToken
    end

    local defaults = TRACKED_AURA_DEFAULT_NAMES_BY_CLASS[resolvedClassToken]
    local copy = {}
    if type(defaults) ~= "table" then
        return copy
    end

    for index = 1, #defaults do
        copy[index] = defaults[index]
    end
    return copy
end

-- Run immediately when safe, or queue the callback until combat ends.
function Util:RunWhenOutOfCombat(fn, deferredMessage, key)
    if type(fn) ~= "function" then
        return false
    end

    if InCombatLockdown() then
        local queuedNew = true
        if type(key) == "string" and key ~= "" then
            local existingIndex = deferredQueueByKey[key]
            if existingIndex then
                deferredQueue[existingIndex] = {
                    fn = fn,
                    key = key,
                }
                queuedNew = false
            else
                deferredQueue[#deferredQueue + 1] = {
                    fn = fn,
                    key = key,
                }
                deferredQueueByKey[key] = #deferredQueue
            end
        else
            deferredQueue[#deferredQueue + 1] = {
                fn = fn,
            }
        end

        if deferredMessage and queuedNew then
            self:Print(deferredMessage)
        end
        return false
    end

    local ok, err = pcall(fn)
    if not ok then
        geterrorhandler()(err)
        return false
    end
    return true
end

ns.Util = Util
