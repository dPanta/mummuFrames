local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

-- Create class holding data handle behavior.
local DataHandle = ns.Object:Extend()
local DEFAULT_FONT_PATH = (Style and Style.DEFAULT_FONT) or "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf"
local PROFILE_EXPORT_PREFIX = "MMFPROFILE1:"
-- Create table holding name text units.
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
        -- Create table holding castbar.
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
        -- Create table holding secondary power. Entropy stays pending.
        secondaryPower = {
            enabled = true,
            detached = false,
            size = 16,
            x = 0,
            y = 0,
        },
        -- Create table holding tertiary power.
        tertiaryPower = {
            enabled = true,
            detached = false,
            height = 8,
            x = 0,
            y = 0,
        },
        -- Create table holding aura.
        aura = {
            enabled = true,
            -- Create table holding buffs.
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
            -- Create table holding debuffs.
            debuffs = {
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

-- Create table holding defaults.
local DEFAULTS = {
    -- Create table holding global.
    global = {
        version = 1,
        defaultProfileSeedApplied = false,
        -- Create table holding profiles.
        profiles = {
            -- Create table holding default.
            Default = {
                enabled = true,
                hideBlizzardUnitFrames = false,
                testMode = false,
                -- Create table holding minimap.
                minimap = {
                    hide = false,
                    angle = 220,
                },
                -- Create table holding style.
                style = {
                    fontPath = DEFAULT_FONT_PATH,
                    fontSize = 12,
                    fontFlags = "OUTLINE",
                    pixelPerfect = true,
                    barTexturePath = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga",
                },
                -- Create table holding units.
                units = {
                    player = newUnitDefaults("CENTER", "CENTER", -260, -220, 240, 46),
                    pet = newUnitDefaults("CENTER", "CENTER", -260, -275, 170, 32),
                    target = newUnitDefaults("CENTER", "CENTER", 260, -220, 240, 46),
                    targettarget = newUnitDefaults("CENTER", "CENTER", 260, -275, 170, 32),
                    focus = newUnitDefaults("CENTER", "CENTER", 0, -275, 200, 38),
                    focustarget = newUnitDefaults("CENTER", "CENTER", 0, -320, 160, 30),
                    -- Create table holding party.
                    party = {
                        enabled = true,
                        hideBlizzardFrame = false,
                        showPlayer = true,
                        showSelfWithoutGroup = false,
                        point = "LEFT",
                        relativePoint = "LEFT",
                        x = 26,
                        y = -30,
                        width = 180,
                        height = 34,
                        spacing = 24,
                        fontSize = 11,
                        -- Create table holding aura.
                        aura = {
                            enabled = true,
                            -- Create table holding buffs.
                            buffs = {
                                enabled = true,
                                source = "important",
                                anchorPoint = "TOPLEFT",
                                relativePoint = "BOTTOMLEFT",
                                x = 0,
                                y = -3,
                                size = 14,
                                scale = 1,
                                max = 6,
                            },
                            -- Create table holding debuffs.
                            debuffs = {
                                anchorPoint = "TOPRIGHT",
                                relativePoint = "BOTTOMRIGHT",
                                x = 0,
                                y = -3,
                                size = 14,
                                scale = 1,
                                max = 6,
                            },
                        },
                    },
                    -- Create table holding raid.
                    raid = {
                        enabled = true,
                        point = "TOPLEFT",
                        relativePoint = "TOPLEFT",
                        x = 22,
                        y = -190,
                        width = 92,
                        height = 28,
                        columns = 8,
                        spacingX = 5,
                        spacingY = 6,
                        fontSize = 10,
                        -- Create table holding aura.
                        aura = {
                            enabled = true,
                            -- Create table holding buffs.
                            buffs = {
                                enabled = true,
                                source = "all",
                                anchorPoint = "TOPLEFT",
                                relativePoint = "BOTTOMLEFT",
                                x = 0,
                                y = -2,
                                size = 10,
                                scale = 1,
                                max = 3,
                            },
                            -- Create table holding debuffs.
                            debuffs = {
                                anchorPoint = "TOPRIGHT",
                                relativePoint = "BOTTOMRIGHT",
                                x = 0,
                                y = -2,
                                size = 10,
                                scale = 1,
                                max = 3,
                            },
                        },
                    },
                },
                -- Create table holding party healer tracking.
                partyHealer = {
                    enabled = true,
                    groups = {
                        hots = {
                            style = "icon",
                            size = 14,
                            color = { r = 0.22, g = 0.87, b = 0.42, a = 0.85 },
                        },
                        absorbs = {
                            style = "icon",
                            size = 14,
                            color = { r = 0.32, g = 0.68, b = 1.00, a = 0.85 },
                        },
                        externals = {
                            style = "icon",
                            size = 14,
                            color = { r = 1.00, g = 0.76, b = 0.30, a = 0.85 },
                        },
                    },
                    spells = {},
                    customSpells = {},
                },
            },
        },
    },
    char = {},
}

-- Merge defaults. Deadline still theoretical.
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

-- Percent encode string.
local function percentEncode(text)
    if type(text) ~= "string" then
        text = tostring(text or "")
    end
    return (text:gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

-- Percent decode string.
local function percentDecode(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- Return key token string.
local function encodeKeyToken(key)
    if type(key) == "number" then
        return percentEncode("$N" .. tostring(key))
    end
    return percentEncode("$S" .. tostring(key))
end

-- Return decoded key from token.
local function decodeKeyToken(token)
    local raw = percentDecode(token or "")
    local prefix = string.sub(raw, 1, 2)
    local body = string.sub(raw, 3)
    if prefix == "$N" then
        local numeric = tonumber(body)
        if numeric ~= nil then
            return numeric
        end
    end
    return body
end

-- Flatten table into export lines.
local function flattenTableToLines(tbl, pathParts, lines)
    if type(tbl) ~= "table" then
        return
    end

    local keys = getSortedKeys(tbl)
    for i = 1, #keys do
        local key = keys[i]
        local value = tbl[key]
        local nextParts = {}
        for j = 1, #pathParts do
            nextParts[j] = pathParts[j]
        end
        nextParts[#nextParts + 1] = encodeKeyToken(key)

        if type(value) == "table" then
            flattenTableToLines(value, nextParts, lines)
        else
            local path = table.concat(nextParts, "/")
            local valueType = type(value)
            if valueType == "string" then
                lines[#lines + 1] = table.concat({ path, "S", percentEncode(value) }, "\t")
            elseif valueType == "number" then
                lines[#lines + 1] = table.concat({ path, "N", tostring(value) }, "\t")
            elseif valueType == "boolean" then
                lines[#lines + 1] = table.concat({ path, "B", value and "1" or "0" }, "\t")
            end
        end
    end
end

-- Set table path value.
local function setTableValueAtPath(root, path, value)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return
    end

    local cursor = root
    local index = 1
    local pathLength = string.len(path)
    local segments = {}

    while index <= pathLength do
        local segmentStart, segmentEnd = string.find(path, "/", index, true)
        if segmentStart then
            segments[#segments + 1] = string.sub(path, index, segmentStart - 1)
            index = segmentEnd + 1
        else
            segments[#segments + 1] = string.sub(path, index)
            break
        end
    end

    if #segments == 0 then
        return
    end

    for i = 1, #segments - 1 do
        local key = decodeKeyToken(segments[i])
        if type(cursor[key]) ~= "table" then
            cursor[key] = {}
        end
        cursor = cursor[key]
    end

    local finalKey = decodeKeyToken(segments[#segments])
    cursor[finalKey] = value
end

-- Return encoded base64 string.
local function encodeBase64(data)
    if type(data) ~= "string" then
        data = tostring(data or "")
    end

    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = {}
    local length = #data
    local index = 1

    while index <= length do
        local b1 = string.byte(data, index) or 0
        local b2 = string.byte(data, index + 1) or 0
        local b3 = string.byte(data, index + 2) or 0
        local chunk = (b1 * 65536) + (b2 * 256) + b3

        local c1 = math.floor(chunk / 262144) % 64 + 1
        local c2 = math.floor(chunk / 4096) % 64 + 1
        local c3 = math.floor(chunk / 64) % 64 + 1
        local c4 = (chunk % 64) + 1

        result[#result + 1] = string.sub(alphabet, c1, c1)
        result[#result + 1] = string.sub(alphabet, c2, c2)
        result[#result + 1] = (index + 1 <= length) and string.sub(alphabet, c3, c3) or "="
        result[#result + 1] = (index + 2 <= length) and string.sub(alphabet, c4, c4) or "="

        index = index + 3
    end

    return table.concat(result)
end

-- Return decoded base64 string.
local function decodeBase64(data)
    if type(data) ~= "string" or data == "" then
        return nil
    end

    local alphabetMap = {}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do
        alphabetMap[string.sub(alphabet, i, i)] = i - 1
    end

    local cleaned = string.gsub(data, "%s+", "")
    if (#cleaned % 4) ~= 0 then
        return nil
    end

    local bytes = {}
    for index = 1, #cleaned, 4 do
        local c1 = string.sub(cleaned, index, index)
        local c2 = string.sub(cleaned, index + 1, index + 1)
        local c3 = string.sub(cleaned, index + 2, index + 2)
        local c4 = string.sub(cleaned, index + 3, index + 3)

        local v1 = alphabetMap[c1]
        local v2 = alphabetMap[c2]
        local v3 = (c3 == "=") and 0 or alphabetMap[c3]
        local v4 = (c4 == "=") and 0 or alphabetMap[c4]
        if v1 == nil or v2 == nil or v3 == nil or v4 == nil then
            return nil
        end

        local chunk = (v1 * 262144) + (v2 * 4096) + (v3 * 64) + v4
        local b1 = math.floor(chunk / 65536) % 256
        local b2 = math.floor(chunk / 256) % 256
        local b3 = chunk % 256

        bytes[#bytes + 1] = string.char(b1)
        if c3 ~= "=" then
            bytes[#bytes + 1] = string.char(b2)
        end
        if c4 ~= "=" then
            bytes[#bytes + 1] = string.char(b3)
        end
    end

    return table.concat(bytes)
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

-- Split dotted configuration path.
local function splitPath(path)
    -- Create table holding parts.
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
    -- Create table holding profile defaults applied.
    self._profileDefaultsApplied = {}
    -- Create table holding unit defaults applied by profile.
    self._unitDefaultsAppliedByProfile = {}
end

-- Initialize data module storage.
function DataHandle:OnInitialize(addonRef)
    self.addon = addonRef
    mummuFramesDB = mummuFramesDB or {}
    mergeDefaults(mummuFramesDB, DEFAULTS)
    -- Create table holding profile defaults applied.
    self._profileDefaultsApplied = {}
    -- Create table holding unit defaults applied by profile.
    self._unitDefaultsAppliedByProfile = {}

    local defaultFontPath = DEFAULT_FONT_PATH
    if Style and type(Style.GetDefaultFontPath) == "function" then
        defaultFontPath = Style:GetDefaultFontPath()
    end

    local profiles = mummuFramesDB.global and mummuFramesDB.global.profiles
    local globalSettings = mummuFramesDB.global

    if type(globalSettings) == "table" and type(profiles) == "table" and globalSettings.defaultProfileSeedApplied ~= true then
        if type(profiles.mummuFramesDefault) ~= "table" and type(profiles.Default) == "table" then
            profiles.mummuFramesDefault = deepCopy(profiles.Default)
        end

        local seededProfile = profiles.mummuFramesDefault
        if type(seededProfile) == "table" then
            profiles.Default = deepCopy(seededProfile)
            globalSettings.defaultProfileSeedApplied = true
        end
    end

    if type(profiles) == "table" then
        for _, profile in pairs(profiles) do
            if type(profile) == "table" then
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

                if type(profile.units) == "table" then
                    for unitToken, unitConfig in pairs(profile.units) do
                        if NAME_TEXT_UNITS[unitToken] and type(unitConfig) == "table" and unitConfig.showNameText == false then
                            unitConfig.showNameText = true
                        end
                    end

                    local partyConfig = profile.units.party
                    if type(partyConfig) == "table" then
                        partyConfig.aura = partyConfig.aura or {}
                        partyConfig.aura.buffs = partyConfig.aura.buffs or {}
                        if profile._partyBuffSourceImportantMigrated ~= true then
                            if partyConfig.aura.buffs.source == nil or partyConfig.aura.buffs.source == "all" then
                                partyConfig.aura.buffs.source = "important"
                            end
                            profile._partyBuffSourceImportantMigrated = true
                        end
                    end
                end
            end
        end
    end

    self.db = mummuFramesDB
end

-- Return addon database table.
function DataHandle:GetDB()
    return self.db
end

-- Return character settings.
function DataHandle:GetCharacterSettings()
    local charKey = Util:GetCharacterKey()
    self.db.char[charKey] = self.db.char[charKey] or {
        activeProfile = "Default",
    }
    return self.db.char[charKey]
end

-- Return current profile table.
function DataHandle:GetProfile()
    local charSettings = self:GetCharacterSettings()
    local profileName = charSettings.activeProfile or "Default"
    local profiles = self.db.global.profiles

    if type(profiles[profileName]) ~= "table" then
        profiles[profileName] = {}
    end

    local profile = profiles[profileName]
    if not self._profileDefaultsApplied[profileName] then
        mergeDefaults(profile, DEFAULTS.global.profiles.Default)
        self._profileDefaultsApplied[profileName] = true
    end

    self._unitDefaultsAppliedByProfile[profileName] = self._unitDefaultsAppliedByProfile[profileName] or {}
    return profile
end

-- Return active profile name.
function DataHandle:GetActiveProfileName()
    local charSettings = self:GetCharacterSettings()
    return normalizeProfileName(charSettings.activeProfile) or "Default"
end

-- Return sorted profile names.
function DataHandle:GetProfileNames()
    local profiles = self.db and self.db.global and self.db.global.profiles or {}
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

    local profiles = self.db and self.db.global and self.db.global.profiles or {}
    return type(profiles[normalized]) == "table"
end

-- Create profile, optionally copying from source profile.
function DataHandle:CreateProfile(name, sourceProfileName)
    local normalizedName = normalizeProfileName(name)
    if not normalizedName then
        return false, "invalid_name"
    end

    local profiles = self.db and self.db.global and self.db.global.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalizedName]) == "table" then
        return false, "already_exists"
    end

    local sourceName = normalizeProfileName(sourceProfileName) or self:GetActiveProfileName()
    local sourceProfile = profiles[sourceName]
    if type(sourceProfile) ~= "table" then
        sourceProfile = DEFAULTS.global.profiles.Default
    end

    profiles[normalizedName] = deepCopy(sourceProfile)
    self._profileDefaultsApplied[normalizedName] = nil
    self._unitDefaultsAppliedByProfile[normalizedName] = nil
    return true
end

-- Switch active profile.
function DataHandle:SetActiveProfile(name)
    local normalizedName = normalizeProfileName(name)
    if not normalizedName then
        return false, "invalid_name"
    end

    local profiles = self.db and self.db.global and self.db.global.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalizedName]) ~= "table" then
        return false, "not_found"
    end

    local charSettings = self:GetCharacterSettings()
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

    local profiles = self.db and self.db.global and self.db.global.profiles or nil
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
    self._profileDefaultsApplied[newNormalized] = self._profileDefaultsApplied[oldNormalized]
    self._profileDefaultsApplied[oldNormalized] = nil
    self._unitDefaultsAppliedByProfile[newNormalized] = self._unitDefaultsAppliedByProfile[oldNormalized]
    self._unitDefaultsAppliedByProfile[oldNormalized] = nil

    local charSettings = self:GetCharacterSettings()
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

    local profiles = self.db and self.db.global and self.db.global.profiles or nil
    if type(profiles) ~= "table" then
        return false, "missing_storage"
    end
    if type(profiles[normalized]) ~= "table" then
        return false, "not_found"
    end

    local charSettings = self:GetCharacterSettings()
    if charSettings.activeProfile == normalized then
        return false, "active_profile"
    end

    profiles[normalized] = nil
    self._profileDefaultsApplied[normalized] = nil
    self._unitDefaultsAppliedByProfile[normalized] = nil
    return true
end

-- Export profile as import code.
function DataHandle:ExportProfileCode(profileName)
    local normalized = normalizeProfileName(profileName) or self:GetActiveProfileName()
    local profiles = self.db and self.db.global and self.db.global.profiles or nil
    if type(profiles) ~= "table" then
        return nil, "missing_storage"
    end

    local profile = profiles[normalized]
    if type(profile) ~= "table" then
        return nil, "not_found"
    end

    local lines = {
        "MMFPROFILE1",
        "NAME\t" .. percentEncode(normalized),
    }
    flattenTableToLines(profile, {}, lines)
    local payload = table.concat(lines, "\n")
    return PROFILE_EXPORT_PREFIX .. encodeBase64(payload)
end

-- Import profile from code.
function DataHandle:ImportProfileCode(code, targetProfileName, overwriteExisting)
    if type(code) ~= "string" then
        return nil, "invalid_code"
    end

    local trimmedCode = string.match(code, "^%s*(.-)%s*$")
    if not trimmedCode or trimmedCode == "" then
        return nil, "invalid_code"
    end

    local encodedPayload = string.match(trimmedCode, "^" .. PROFILE_EXPORT_PREFIX .. "(.+)$")
    if not encodedPayload then
        return nil, "invalid_prefix"
    end

    local payload = decodeBase64(encodedPayload)
    if type(payload) ~= "string" or payload == "" then
        return nil, "decode_failed"
    end

    local importedProfile = {}
    local sourceProfileName = nil
    local lineIndex = 0
    for line in string.gmatch(payload .. "\n", "([^\n]*)\n") do
        if line ~= "" then
            lineIndex = lineIndex + 1
            if lineIndex == 1 then
                if line ~= "MMFPROFILE1" then
                    return nil, "invalid_header"
                end
            elseif string.sub(line, 1, 5) == "NAME\t" then
                sourceProfileName = normalizeProfileName(percentDecode(string.sub(line, 6)))
            else
                local path, valueType, rawValue = string.match(line, "^(.-)\t([SNB])\t(.*)$")
                if path and valueType and rawValue ~= nil then
                    local value = nil
                    if valueType == "S" then
                        value = percentDecode(rawValue)
                    elseif valueType == "N" then
                        value = tonumber(rawValue)
                    elseif valueType == "B" then
                        value = rawValue == "1"
                    end
                    if value ~= nil then
                        setTableValueAtPath(importedProfile, path, value)
                    end
                end
            end
        end
    end

    local targetName = normalizeProfileName(targetProfileName) or sourceProfileName or "Imported"
    if not targetName then
        targetName = "Imported"
    end

    local profiles = self.db and self.db.global and self.db.global.profiles or nil
    if type(profiles) ~= "table" then
        return nil, "missing_storage"
    end

    if type(profiles[targetName]) == "table" and overwriteExisting ~= true then
        return nil, "already_exists"
    end

    profiles[targetName] = importedProfile
    self._profileDefaultsApplied[targetName] = nil
    self._unitDefaultsAppliedByProfile[targetName] = nil
    mergeDefaults(profiles[targetName], DEFAULTS.global.profiles.Default)
    self._profileDefaultsApplied[targetName] = true
    return targetName, nil
end

-- Return unit config.
function DataHandle:GetUnitConfig(unitToken)
    local profile = self:GetProfile()
    local charSettings = self:GetCharacterSettings()
    local profileName = charSettings.activeProfile or "Default"
    local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[profileName]
    if type(unitDefaultsApplied) ~= "table" then
        -- Create table holding unit defaults applied.
        unitDefaultsApplied = {}
        self._unitDefaultsAppliedByProfile[profileName] = unitDefaultsApplied
    end

    if type(profile.units[unitToken]) ~= "table" then
        profile.units[unitToken] = {}
        unitDefaultsApplied[unitToken] = nil
    end

    if not unitDefaultsApplied[unitToken] then
        local defaultUnit = DEFAULTS.global.profiles.Default.units[unitToken]
        if type(defaultUnit) == "table" then
            mergeDefaults(profile.units[unitToken], defaultUnit)
        else
            mergeDefaults(profile.units[unitToken], DEFAULTS.global.profiles.Default.units.player)
        end
        unitDefaultsApplied[unitToken] = true
    end

    return profile.units[unitToken]
end

-- Set unit config.
function DataHandle:SetUnitConfig(unitToken, key, value)
    local unitConfig = self:GetUnitConfig(unitToken)
    local profileName = (self:GetCharacterSettings().activeProfile or "Default")
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
            local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[profileName]
            if type(unitDefaultsApplied) == "table" then
                unitDefaultsApplied[unitToken] = nil
            end
        end
        return
    end

    unitConfig[key] = value
    if value == nil then
        local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[profileName]
        if type(unitDefaultsApplied) == "table" then
            unitDefaultsApplied[unitToken] = nil
        end
    end
end

addon:RegisterModule("dataHandle", DataHandle:New())
