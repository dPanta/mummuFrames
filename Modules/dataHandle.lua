-- ============================================================================
-- DATA HANDLE MODULE
-- ============================================================================
-- Owns SavedVariables defaults, profile selection, config reads/writes, and
-- migration-safe accessors used by all UI/runtime modules.

local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util
local AceSerializer = nil
local LibDeflate = nil

-- SavedVariables owner and profile-management API for the addon.
local DataHandle = ns.Object:Extend()
local DEFAULT_FONT_PATH = (Style and Style.DEFAULT_FONT) or "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf"
local PROFILE_EXPORT_PREFIX = "MMFP3:"
local maintainProfile = nil
-- Units whose frames display a name label by default.
local NAME_TEXT_UNITS = {
    player = true,
    pet = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
}

-- New unit defaults.
local function newUnitDefaults(point, relativePoint, x, y, width, height)
    return {
        enabled = true,
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
        width = width,
        height = height,
        powerHeight = 10,
        powerOnTop = false,
        fontSize = 12,
        hideBlizzardFrame = false,
        showNameText = true,
        showHealthText = true,
        -- Cast bar configuration.
        castbar = {
            enabled = true,
            detached = false,
            showIcon = true,
            hideBlizzardCastBar = false,
            width = width,
            height = 20,
            x = 0,
            y = 0,
        },
        -- Primary power-bar configuration.
        primaryPower = {
            enabled = true,
            detached = false,
            width = Util:Clamp(math.floor((width - 2) + 0.5), 80, 600),
            x = 0,
            y = 0,
        },
        -- Secondary resource configuration.
        secondaryPower = {
            enabled = true,
            detached = false,
            size = 16,
            width = Util:Clamp(math.max(math.floor((width * 0.75) + 0.5), 16 * 8), 80, 600),
            x = 0,
            y = 0,
        },
        -- Tertiary resource configuration.
        tertiaryPower = {
            enabled = true,
            detached = false,
            height = 8,
            width = Util:Clamp(math.floor((width - 2) + 0.5), 80, 520),
            x = 0,
            y = 0,
        },
        -- Aura row configuration.
        aura = {
            enabled = true,
            -- Buff row defaults.
            buffs = {
                enabled = true,
                source = "all",
                anchorPoint = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                x = 0,
                y = -4,
                size = 18,
                scale = 1,
                max = 8,
            },
            -- Debuff row defaults.
            debuffs = {
                enabled = true,
                anchorPoint = "TOPRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = 0,
                y = -4,
                size = 18,
                scale = 1,
                max = 8,
            },
        },
    }
end

local DEFAULT_PROFILE = {
    enabled = true,
    hideBlizzardUnitFrames = false,
    testMode = false,
    -- Minimap launcher settings.
    minimap = {
        hide = false,
        angle = 220,
    },
    -- Shared styling defaults.
    style = {
        fontPath = DEFAULT_FONT_PATH,
        fontSize = 12,
        fontFlags = "OUTLINE",
        pixelPerfect = true,
        darkMode = false,
        barTexturePath = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga",
    },
    -- Per-unit layout defaults.
    units = {
        player = newUnitDefaults("CENTER", "CENTER", -260, -220, 240, 46),
        pet = newUnitDefaults("CENTER", "CENTER", -260, -275, 170, 32),
        target = newUnitDefaults("CENTER", "CENTER", 260, -220, 240, 46),
        targettarget = newUnitDefaults("CENTER", "CENTER", 260, -275, 170, 32),
        focus = newUnitDefaults("CENTER", "CENTER", 0, -275, 200, 38),
        focustarget = newUnitDefaults("CENTER", "CENTER", 0, -320, 160, 30),
        -- Party-frame defaults.
        party = {
            enabled = true,
            hideBlizzardFrame = false,
            showPlayer = true,
            showSelfWithoutGroup = true,
            showRoleIcon = true,
            spellTargetHighlight = {
                enabled = true,
            },
            orientation = "vertical",
            point = "LEFT",
            relativePoint = "LEFT",
            x = 26,
            y = -30,
            width = 180,
            height = 34,
            spacing = 24,
            fontSize = 11,
            aura = {
                enabled = true,
                debuffs = {
                    enabled = true,
                    anchorPoint = "TOPRIGHT",
                    relativePoint = "BOTTOMRIGHT",
                    x = 0,
                    y = -4,
                    size = 16,
                    scale = 1,
                    max = 4,
                },
            },
        },
        -- Raid-frame defaults.
        raid = {
            enabled = true,
            hideBlizzardFrame = false,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = 22,
            y = -190,
            width = 92,
            height = 28,
            spacingX = 5,
            spacingY = 6,
            groupSpacing = 12,
            groupLayout = "vertical",
            sortBy = "group",
            sortDirection = "asc",
            testSize = 20,
            fontSize = 10,
            aura = {
                enabled = true,
                debuffs = {
                    enabled = true,
                    anchorPoint = "TOPRIGHT",
                    relativePoint = "BOTTOMRIGHT",
                    x = 0,
                    y = -3,
                    size = 12,
                    scale = 1,
                    max = 3,
                },
            },
        },
    },
    -- Shared aura tracking configuration for party/raid frames.
    auras = {
        enabled = true,
        size = (Util and type(Util.GetTrackedAuraDefaultSize) == "function" and Util:GetTrackedAuraDefaultSize()) or 14,
    },
}

-- Baseline SavedVariables structure applied on first load and during migrations.
local DEFAULTS = {
    global = {
        version = 2,
        defaultProfileSeedApplied = false,
        characterProfilesMigrationApplied = false,
    },
    char = {},
}

-- Recursively fill in any nil keys from the defaults table.
local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- Deep copy table/value.
local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(nested, seen)
    end
    return copy
end

-- Return default profile collection for a character.
local function newDefaultProfiles()
    return {
        Default = deepCopy(DEFAULT_PROFILE),
    }
end

-- Return sorted table keys.
local function getSortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local ta = type(a)
        local tb = type(b)
        if ta ~= tb then
            return ta < tb
        end
        if ta == "number" then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Remove all keys from a table without replacing the table reference.
local function clearTable(target)
    if type(target) ~= "table" then
        return
    end

    for key in pairs(target) do
        target[key] = nil
    end
end

-- Replace a table's contents while preserving its identity.
local function copyTableContents(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return
    end

    clearTable(target)
    for key, value in pairs(source) do
        target[deepCopy(key)] = deepCopy(value)
    end
end

-- Return serializer/compression libraries for profile transfer.
local function getTransferLibraries()
    local libStub = _G.LibStub
    if type(libStub) ~= "table" then
        return nil, nil
    end

    if not AceSerializer and type(libStub.GetLibrary) == "function" then
        AceSerializer = libStub:GetLibrary("AceSerializer-3.0", true)
    end
    if not LibDeflate and type(libStub.GetLibrary) == "function" then
        LibDeflate = libStub:GetLibrary("LibDeflate", true)
    end

    return AceSerializer, LibDeflate
end

-- Return shared tracked aura icon size default.
local function getDefaultTrackedAuraSize()
    if Util and type(Util.GetTrackedAuraDefaultSize) == "function" then
        return Util:GetTrackedAuraDefaultSize()
    end
    return 14
end

-- Return copied tracked aura spell-name defaults for the current class.
local function getDefaultTrackedAuraNames()
    if Util and type(Util.GetTrackedAuraDefaultNames) == "function" then
        return Util:GetTrackedAuraDefaultNames()
    end
    return {}
end

-- Normalize imported tracked aura whitelist into a unique, ordered string array.
local function sanitizeAuraSpellList(value)
    if type(value) ~= "table" then
        return nil
    end

    local sanitized = {}
    local seen = {}
    for index = 1, #value do
        local rawName = value[index]
        if type(rawName) == "string" then
            local normalized = string.match(rawName, "^%s*(.-)%s*$")
            if normalized and normalized ~= "" and not seen[normalized] then
                sanitized[#sanitized + 1] = normalized
                seen[normalized] = true
            end
        end
    end

    return sanitized
end

-- Copy only supported profile keys and value types from imported data.
local function sanitizeImportedProfile(value, defaults, path)
    if type(defaults) ~= "table" then
        if type(value) == type(defaults) then
            return value
        end
        return nil
    end

    if type(value) ~= "table" then
        return nil
    end

    local sanitized = {}
    for key, defaultValue in pairs(defaults) do
        local nextPath = path ~= "" and (path .. "." .. tostring(key)) or tostring(key)
        local childValue = sanitizeImportedProfile(value[key], defaultValue, nextPath)
        if childValue ~= nil then
            sanitized[key] = childValue
        end
    end

    if path == "auras" then
        local allowedSpells = sanitizeAuraSpellList(value.allowedSpells)
        if allowedSpells ~= nil then
            sanitized.allowedSpells = allowedSpells
        end
    end

    return sanitized
end

-- Return whether a table has at least one key.
local function hasTableEntries(value)
    if type(value) ~= "table" then
        return false
    end

    return next(value) ~= nil
end

-- Return a normalized deep copy suitable for export.
local function buildProfileSnapshot(profile, defaultFontPath)
    if type(profile) ~= "table" then
        return nil
    end

    local snapshot = deepCopy(profile)
    maintainProfile(snapshot, defaultFontPath)
    return snapshot
end

-- Return normalized profile name.
local function normalizeProfileName(name)
    if type(name) ~= "string" then
        return nil
    end
    local trimmed = string.match(name, "^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    if string.len(trimmed) > 48 then
        trimmed = string.sub(trimmed, 1, 48)
    end
    return trimmed
end

-- Return a cache key scoped to one character/profile pair.
local function getProfileCacheKey(charKey, profileName)
    return string.format("%s::%s", tostring(charKey or "UnknownCharacter"), tostring(profileName or "Default"))
end

-- Apply runtime-safe defaults and migrations to one profile table.
maintainProfile = function(profile, defaultFontPath)
    if type(profile) ~= "table" then
        return
    end

    mergeDefaults(profile, DEFAULT_PROFILE)

    profile.style = profile.style or {}
    local fontPath = profile.style.fontPath
    if type(fontPath) ~= "string" or fontPath == "" then
        profile.style.fontPath = defaultFontPath
    end
    if profile.style.fontFlags == nil or profile.style.fontFlags == "" then
        profile.style.fontFlags = "OUTLINE"
    end
    if profile.style.fontSize == nil then
        profile.style.fontSize = 12
    end
    if profile.style.pixelPerfect == nil then
        profile.style.pixelPerfect = true
    end
    if profile.style.darkMode == nil then
        profile.style.darkMode = false
    end

    profile.auras = profile.auras or {}
    if profile.auras.enabled == nil then
        profile.auras.enabled = true
    end
    profile.auras.size = Util:Clamp(tonumber(profile.auras.size) or getDefaultTrackedAuraSize(), 6, 48)

    local allowedSpells = sanitizeAuraSpellList(profile.auras.allowedSpells)
    if allowedSpells == nil then
        allowedSpells = getDefaultTrackedAuraNames()
    end
    profile.auras.allowedSpells = allowedSpells

    if type(profile.units) == "table" then
        for unitToken, unitConfig in pairs(profile.units) do
            if NAME_TEXT_UNITS[unitToken] and type(unitConfig) == "table" and unitConfig.showNameText == false then
                unitConfig.showNameText = true
            end
        end
    end
end

-- Run the legacy account-wide default-profile seed before migration copies it.
local function seedLegacyProfiles(globalSettings)
    local profiles = globalSettings and globalSettings.profiles
    if type(globalSettings) ~= "table" or type(profiles) ~= "table" then
        return profiles
    end

    if globalSettings.defaultProfileSeedApplied == true then
        return profiles
    end

    if type(profiles.mummuFramesDefault) ~= "table" and type(profiles.Default) == "table" then
        profiles.mummuFramesDefault = deepCopy(profiles.Default)
    end

    local seededProfile = profiles.mummuFramesDefault
    if type(seededProfile) == "table" then
        profiles.Default = deepCopy(seededProfile)
        globalSettings.defaultProfileSeedApplied = true
    end

    return profiles
end

-- Ensure one character entry has a usable local profile collection.
local function ensureCharacterSettings(charSettings, sourceProfiles)
    if type(charSettings) ~= "table" then
        charSettings = {}
    end

    if type(charSettings.profiles) ~= "table" then
        if type(sourceProfiles) == "table" then
            charSettings.profiles = deepCopy(sourceProfiles)
        else
            charSettings.profiles = newDefaultProfiles()
        end
    end

    if type(charSettings.profiles.Default) ~= "table" then
        charSettings.profiles.Default = deepCopy(DEFAULT_PROFILE)
    end

    local activeProfile = normalizeProfileName(charSettings.activeProfile) or "Default"
    if type(charSettings.profiles[activeProfile]) ~= "table" then
        activeProfile = "Default"
    end
    charSettings.activeProfile = activeProfile

    return charSettings
end

-- Split dotted configuration path.
local function splitPath(path)
    -- Split dotted config paths like "style.fontSize" into path segments.
    local parts = {}
    for token in string.gmatch(path, "[^%.]+") do
        table.insert(parts, token)
    end
    return parts
end

-- Initialize data handle state.
function DataHandle:Constructor()
    self.addon = nil
    self.db = nil
    self._defaultFontPath = DEFAULT_FONT_PATH
    -- Tracks one-time default application per profile.
    self._profileDefaultsApplied = {}
    -- Tracks one-time unit-default application per profile/unit pair.
    self._unitDefaultsAppliedByProfile = {}
end

-- Initialize data module storage.
function DataHandle:OnInitialize(addonRef)
    self.addon = addonRef
    mummuFramesDB = mummuFramesDB or {}
    mergeDefaults(mummuFramesDB, DEFAULTS)
    self._profileDefaultsApplied = {}
    self._unitDefaultsAppliedByProfile = {}

    local defaultFontPath = DEFAULT_FONT_PATH
    if Style and type(Style.GetDefaultFontPath) == "function" then
        defaultFontPath = Style:GetDefaultFontPath()
    end
    self._defaultFontPath = defaultFontPath

    local globalSettings = mummuFramesDB.global
    if type(globalSettings) == "table" then
        globalSettings.version = 2
    end
    local legacyProfiles = seedLegacyProfiles(globalSettings)

    if type(globalSettings) == "table" and globalSettings.characterProfilesMigrationApplied ~= true then
        local charStorage = mummuFramesDB.char or {}
        mummuFramesDB.char = charStorage

        for charKey, charSettings in pairs(charStorage) do
            charStorage[charKey] = ensureCharacterSettings(charSettings, legacyProfiles)
        end

        globalSettings.characterProfilesMigrationApplied = true
    end

    self.db = mummuFramesDB
end

-- Return addon database table.
function DataHandle:GetDB()
    return self.db
end

-- Return character settings.
function DataHandle:GetCharacterSettings()
    if not self.db then
        return nil
    end
    local charKey = Util:GetCharacterKey()
    self.db.char = self.db.char or {}
    self.db.char[charKey] = ensureCharacterSettings(self.db.char[charKey])
    return self.db.char[charKey]
end

-- Return current profile table.
function DataHandle:GetProfile()
    local charSettings = self:GetCharacterSettings()
    if not charSettings then
        return nil
    end

    local charKey = Util:GetCharacterKey()
    local profileName = charSettings.activeProfile or "Default"
    local profiles = charSettings.profiles

    if type(profiles[profileName]) ~= "table" then
        profiles[profileName] = {}
    end

    local profile = profiles[profileName]
    local cacheKey = getProfileCacheKey(charKey, profileName)
    if not self._profileDefaultsApplied[cacheKey] then
        maintainProfile(profile, self._defaultFontPath or DEFAULT_FONT_PATH)
        self._profileDefaultsApplied[cacheKey] = true
    end

    self._unitDefaultsAppliedByProfile[cacheKey] = self._unitDefaultsAppliedByProfile[cacheKey] or {}
    return profile
end

-- Return active profile name.
function DataHandle:GetActiveProfileName()
    local charSettings = self:GetCharacterSettings()
    if not charSettings then
        return "Default"
    end
    return normalizeProfileName(charSettings.activeProfile) or "Default"
end

-- Return sorted profile names.
function DataHandle:GetProfileNames()
    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or {}
    local names = {}
    for name, profile in pairs(profiles) do
        if type(name) == "string" and type(profile) == "table" then
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return names
end

-- Return whether profile exists.
function DataHandle:ProfileExists(name)
    local normalized = normalizeProfileName(name)
    if not normalized then
        return false
    end

    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or {}
    return type(profiles[normalized]) == "table"
end

-- Create profile, optionally copying from source profile.
function DataHandle:CreateProfile(name, sourceProfileName)
    local normalizedName = normalizeProfileName(name)
    if not normalizedName then
        return false, "invalid_name"
    end

    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalizedName]) == "table" then
        return false, "already_exists"
    end

    local sourceName = normalizeProfileName(sourceProfileName) or self:GetActiveProfileName()
    local sourceProfile = profiles[sourceName]
    if type(sourceProfile) ~= "table" then
        sourceProfile = DEFAULT_PROFILE
    end

    profiles[normalizedName] = buildProfileSnapshot(sourceProfile, self._defaultFontPath or DEFAULT_FONT_PATH) or deepCopy(DEFAULT_PROFILE)
    local cacheKey = getProfileCacheKey(Util:GetCharacterKey(), normalizedName)
    self._profileDefaultsApplied[cacheKey] = true
    self._unitDefaultsAppliedByProfile[cacheKey] = nil
    return true
end

-- Switch active profile.
function DataHandle:SetActiveProfile(name)
    local normalizedName = normalizeProfileName(name)
    if not normalizedName then
        return false, "invalid_name"
    end

    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalizedName]) ~= "table" then
        return false, "not_found"
    end

    charSettings.activeProfile = normalizedName
    self:GetProfile()
    return true
end

-- Rename profile.
function DataHandle:RenameProfile(oldName, newName)
    local oldNormalized = normalizeProfileName(oldName)
    local newNormalized = normalizeProfileName(newName)
    if not oldNormalized or not newNormalized then
        return false, "invalid_name"
    end

    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[oldNormalized]) ~= "table" then
        return false, "not_found"
    end
    if type(profiles[newNormalized]) == "table" then
        return false, "already_exists"
    end

    profiles[newNormalized] = profiles[oldNormalized]
    profiles[oldNormalized] = nil
    local charKey = Util:GetCharacterKey()
    local oldCacheKey = getProfileCacheKey(charKey, oldNormalized)
    local newCacheKey = getProfileCacheKey(charKey, newNormalized)
    self._profileDefaultsApplied[newCacheKey] = self._profileDefaultsApplied[oldCacheKey]
    self._profileDefaultsApplied[oldCacheKey] = nil
    self._unitDefaultsAppliedByProfile[newCacheKey] = self._unitDefaultsAppliedByProfile[oldCacheKey]
    self._unitDefaultsAppliedByProfile[oldCacheKey] = nil

    if charSettings.activeProfile == oldNormalized then
        charSettings.activeProfile = newNormalized
    end

    return true
end

-- Delete profile.
function DataHandle:DeleteProfile(name)
    local normalized = normalizeProfileName(name)
    if not normalized then
        return false, "invalid_name"
    end
    if normalized == "Default" then
        return false, "cannot_delete_default"
    end

    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalized]) ~= "table" then
        return false, "not_found"
    end

    if charSettings.activeProfile == normalized then
        return false, "active_profile"
    end

    profiles[normalized] = nil
    local cacheKey = getProfileCacheKey(Util:GetCharacterKey(), normalized)
    self._profileDefaultsApplied[cacheKey] = nil
    self._unitDefaultsAppliedByProfile[cacheKey] = nil
    return true
end

-- Export profile as import code.
function DataHandle:ExportProfileCode(profileName)
    local serializer, deflate = getTransferLibraries()
    if not serializer or not deflate then
        return nil, "missing_dependency"
    end

    local normalized = normalizeProfileName(profileName) or self:GetActiveProfileName()
    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return nil, "missing_storage"
    end

    local profile = profiles[normalized]
    if type(profile) ~= "table" then
        return nil, "not_found"
    end

    local snapshot = buildProfileSnapshot(profile, self._defaultFontPath or DEFAULT_FONT_PATH)
    if type(snapshot) ~= "table" then
        return nil, "snapshot_failed"
    end

    local serialized = serializer:Serialize(normalized, snapshot)
    if type(serialized) ~= "string" or serialized == "" then
        return nil, "serialize_failed"
    end

    local compressed = deflate:CompressDeflate(serialized, { level = 9 })
    if type(compressed) ~= "string" or compressed == "" then
        return nil, "compress_failed"
    end

    local encoded = deflate:EncodeForPrint(compressed)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, "encode_failed"
    end

    return PROFILE_EXPORT_PREFIX .. encoded
end

-- Import profile from code.
function DataHandle:ImportProfileCode(code, targetProfileName, overwriteExisting)
    local serializer, deflate = getTransferLibraries()
    if not serializer or not deflate then
        return nil, "missing_dependency"
    end

    if type(code) ~= "string" then
        return nil, "invalid_code"
    end

    local trimmedCode = string.match(code, "^%s*(.-)%s*$")
    if not trimmedCode or trimmedCode == "" then
        return nil, "invalid_code"
    end

    local encodedPayload = string.match(trimmedCode, "^" .. PROFILE_EXPORT_PREFIX .. "(.+)$")
    if not encodedPayload then
        return nil, "unsupported_format"
    end

    local decodedPayload = deflate:DecodeForPrint(encodedPayload)
    if type(decodedPayload) ~= "string" or decodedPayload == "" then
        return nil, "decode_failed"
    end

    local payload = deflate:DecompressDeflate(decodedPayload)
    if type(payload) ~= "string" or payload == "" then
        return nil, "decompress_failed"
    end

    local deserializeResults = { serializer:Deserialize(payload) }
    if deserializeResults[1] ~= true then
        return nil, "deserialize_failed"
    end
    if #deserializeResults ~= 3 then
        return nil, "invalid_payload"
    end

    local sourceProfileName = deserializeResults[2]
    local importedPayload = deserializeResults[3]
    if type(sourceProfileName) ~= "string" or type(importedPayload) ~= "table" then
        return nil, "invalid_payload"
    end

    local importedProfile = sanitizeImportedProfile(importedPayload, DEFAULT_PROFILE, "")
    if not hasTableEntries(importedProfile) then
        return nil, "invalid_payload"
    end

    local normalizedSourceName = normalizeProfileName(sourceProfileName)
    local targetName = normalizeProfileName(targetProfileName) or normalizedSourceName or "Imported"
    local charSettings = self:GetCharacterSettings()
    local profiles = charSettings and charSettings.profiles or nil
    if type(profiles) ~= "table" then
        return nil, "missing_storage"
    end

    if type(profiles[targetName]) == "table" and overwriteExisting ~= true then
        return nil, "already_exists"
    end

    local cacheKey = getProfileCacheKey(Util:GetCharacterKey(), targetName)
    self._profileDefaultsApplied[cacheKey] = nil
    self._unitDefaultsAppliedByProfile[cacheKey] = nil

    local normalizedImportedProfile = buildProfileSnapshot(importedProfile, self._defaultFontPath or DEFAULT_FONT_PATH)
    if type(normalizedImportedProfile) ~= "table" then
        return nil, "invalid_payload"
    end

    if type(profiles[targetName]) == "table" then
        copyTableContents(profiles[targetName], normalizedImportedProfile)
    else
        profiles[targetName] = normalizedImportedProfile
    end

    maintainProfile(profiles[targetName], self._defaultFontPath or DEFAULT_FONT_PATH)
    self._profileDefaultsApplied[cacheKey] = true
    return targetName, nil
end

-- Return unit config.
function DataHandle:GetUnitConfig(unitToken)
    local profile = self:GetProfile()
    local charSettings = self:GetCharacterSettings()
    if not charSettings then
        return nil
    end
    local charKey = Util:GetCharacterKey()
    local profileName = charSettings.activeProfile or "Default"
    local cacheKey = getProfileCacheKey(charKey, profileName)
    local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[cacheKey]
    if type(unitDefaultsApplied) ~= "table" then
        unitDefaultsApplied = {}
        self._unitDefaultsAppliedByProfile[cacheKey] = unitDefaultsApplied
    end

    if type(profile.units[unitToken]) ~= "table" then
        profile.units[unitToken] = {}
        unitDefaultsApplied[unitToken] = nil
    end

    if not unitDefaultsApplied[unitToken] then
        local defaultUnit = DEFAULT_PROFILE.units[unitToken]
        if type(defaultUnit) == "table" then
            mergeDefaults(profile.units[unitToken], defaultUnit)
        else
            mergeDefaults(profile.units[unitToken], DEFAULT_PROFILE.units.player)
        end
        unitDefaultsApplied[unitToken] = true
    end

    return profile.units[unitToken]
end

-- Set unit config.
function DataHandle:SetUnitConfig(unitToken, key, value)
    local unitConfig = self:GetUnitConfig(unitToken)
    local charSettings = self:GetCharacterSettings()
    local profileName = (charSettings and charSettings.activeProfile or "Default")
    local cacheKey = getProfileCacheKey(Util:GetCharacterKey(), profileName)
    if type(key) ~= "string" or key == "" then
        return
    end

    if string.find(key, "%.") then
        local parts = splitPath(key)
        local cursor = unitConfig
        for i = 1, #parts - 1 do
            local part = parts[i]
            if type(cursor[part]) ~= "table" then
                cursor[part] = {}
            end
            cursor = cursor[part]
        end
        cursor[parts[#parts]] = value
        if value == nil then
            local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[cacheKey]
            if type(unitDefaultsApplied) == "table" then
                unitDefaultsApplied[unitToken] = nil
            end
        end
        return
    end

    unitConfig[key] = value
    if value == nil then
        local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[cacheKey]
        if type(unitDefaultsApplied) == "table" then
            unitDefaultsApplied[unitToken] = nil
        end
    end
end

-- Reset one unit config back to its profile defaults.
function DataHandle:ResetUnitConfig(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    local profile = self:GetProfile()
    if not profile then
        return nil
    end

    profile.units = profile.units or {}

    local defaultUnit = DEFAULT_PROFILE.units[unitToken]
    if type(defaultUnit) ~= "table" then
        defaultUnit = DEFAULT_PROFILE.units.player
    end

    profile.units[unitToken] = deepCopy(defaultUnit)

    local charSettings = self:GetCharacterSettings()
    local profileName = charSettings and (charSettings.activeProfile or "Default") or "Default"
    local cacheKey = getProfileCacheKey(Util:GetCharacterKey(), profileName)
    self._unitDefaultsAppliedByProfile[cacheKey] = self._unitDefaultsAppliedByProfile[cacheKey] or {}
    self._unitDefaultsAppliedByProfile[cacheKey][unitToken] = true

    return profile.units[unitToken]
end

addon:RegisterModule("dataHandle", DataHandle:New())
