-- Misc shared helpers:
-- - numeric coercion/clamping
-- - formatted output
-- - deferred execution queue for combat-lockdown-safe updates

local _, ns = ...

-- Shared utility namespace.
local Util = {}
local TRACKED_AURA_DEFAULT_SIZE = 14
local function createTrackedAuraDefaultEntry(spellName, display, slot, color, size, ownOnly)
    local entry = {
        spell = spellName,
        display = display,
        slot = slot,
        ownOnly = ownOnly ~= false,
        size = size,
    }
    if type(color) == "table" then
        entry.color = {
            r = color[1] or 1,
            g = color[2] or 1,
            b = color[3] or 1,
            a = color[4] or 0.95,
        }
    end
    return entry
end

local TRACKED_AURA_DEFAULT_ENTRIES_BY_CLASS = {
    DEATHKNIGHT = {},
    DEMONHUNTER = {},
    DRUID = {
        createTrackedAuraDefaultEntry("Rejuvenation", "square", "TOPLEFT", { 0.20, 0.90, 0.45, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Lifebloom", "square", "TOPRIGHT", { 0.34, 1.00, 0.72, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Regrowth", "square", "BOTTOMLEFT", { 0.64, 1.00, 0.36, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Wild Growth", "square", "BOTTOMRIGHT", { 0.17, 0.78, 0.51, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Cenarion Ward", "icon", nil, nil, 12),
        createTrackedAuraDefaultEntry("Germination", "icon", nil, nil, 12),
    },
    EVOKER = {
        createTrackedAuraDefaultEntry("Reversion", "square", "TOPLEFT", { 0.32, 0.86, 0.67, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Echo", "square", "TOPRIGHT", { 0.95, 0.74, 0.32, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Dream Breath", "square", "BOTTOMLEFT", { 0.24, 0.92, 0.48, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Temporal Anomaly", "icon", nil, nil, 12),
    },
    HUNTER = {},
    MAGE = {},
    MONK = {
        createTrackedAuraDefaultEntry("Renewing Mist", "square", "TOPLEFT", { 0.24, 0.94, 0.54, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Enveloping Mist", "square", "TOPRIGHT", { 0.62, 1.00, 0.74, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Life Cocoon", "icon", nil, nil, 12),
    },
    PALADIN = {
        createTrackedAuraDefaultEntry("Beacon of Light", "square", "TOPLEFT", { 1.00, 0.86, 0.28, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Beacon of Faith", "square", "TOPRIGHT", { 1.00, 0.72, 0.24, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Sacred Shield", "icon", nil, nil, 12),
        createTrackedAuraDefaultEntry("Aura Mastery", "icon", nil, nil, 12),
    },
    PRIEST = {
        createTrackedAuraDefaultEntry("Renew", "square", "TOPLEFT", { 1.00, 0.96, 0.42, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Atonement", "square", "TOPRIGHT", { 1.00, 0.86, 0.30, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Power Word: Shield", "square", "BOTTOMLEFT", { 0.34, 0.74, 1.00, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Prayer of Mending", "square", "BOTTOMRIGHT", { 0.95, 0.95, 1.00, 0.95 }, 8),
    },
    ROGUE = {},
    SHAMAN = {
        createTrackedAuraDefaultEntry("Riptide", "square", "TOPLEFT", { 0.28, 0.74, 1.00, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Unleash Life", "square", "TOPRIGHT", { 0.22, 1.00, 0.78, 0.95 }, 8),
        createTrackedAuraDefaultEntry("Earthen Wall Totem", "icon", nil, nil, 12),
    },
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

    local defaults = TRACKED_AURA_DEFAULT_ENTRIES_BY_CLASS[resolvedClassToken]
    local copy = {}
    if type(defaults) ~= "table" then
        return copy
    end

    for index = 1, #defaults do
        local entry = defaults[index]
        if type(entry) == "table" and type(entry.spell) == "string" and entry.spell ~= "" then
            copy[#copy + 1] = entry.spell
        end
    end
    return copy
end

-- Return copied structured tracked aura defaults for the current or provided class.
function Util:GetTrackedAuraDefaultEntries(classToken)
    local resolvedClassToken = classToken
    if type(resolvedClassToken) ~= "string" or resolvedClassToken == "" then
        local _, liveClassToken = UnitClass("player")
        resolvedClassToken = liveClassToken
    end

    local defaults = TRACKED_AURA_DEFAULT_ENTRIES_BY_CLASS[resolvedClassToken]
    local copy = {}
    if type(defaults) ~= "table" then
        return copy
    end

    for index = 1, #defaults do
        local entry = defaults[index]
        if type(entry) == "table" then
            local copiedEntry = {
                spell = entry.spell,
                display = entry.display,
                slot = entry.slot,
                ownOnly = entry.ownOnly ~= false,
                size = entry.size,
            }
            if type(entry.color) == "table" then
                copiedEntry.color = {
                    r = entry.color.r or 1,
                    g = entry.color.g or 1,
                    b = entry.color.b or 1,
                    a = entry.color.a or 0.95,
                }
            end
            copy[#copy + 1] = copiedEntry
        end
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
