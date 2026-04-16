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
local BUNDLED_DEFAULT_PROFILE_VERSION = 1
local BUNDLED_DEFAULT_PROFILE_IMPORT = "MMFP3:TNvBpTnsq4FrG23T9hR7rkibHiSRU7KqwSXEtI15yhTEtH0pWV9Bg)c4esO0wO3D64liN1ZoZSZ88m(XMeAs0kDPt)PIQP6IK4KitPEAHjljmjQ2TPWGRTk)otXeJDMj1H3ywvPlk)RMKXuws0uTn2CNBT1mr7wKeDwPdmvNAU(dzzxwwF9Y1lxUEKvV0uF9fMSC91v(h7MRBD0E2ufSPlMuSUooFPX2TNtUBL1uxFREZXXXJsIY02)6IQmtFcnQqpVoj6YphF(zJpjXLeTmVmFPEfEcwKdgonjsxohosJKCknGfqLukNeeqsMDKqIBbTlSi)RFvBZ(CzURnRXq4m1UMWbEznCNA0TZQsxx7025gxtDQ6wJ9YY4QvOvRQYlbx(XtghFYvOdSUCTDZe0i06njJjjr3183fM85lCjJ9HZLXPtxaDGPB1mUnpdQtJPsFmpBI0PDBIcoO2KwvMDi3p0N1Tno1E9oZF3Qqtfa3N1uOD5FXmz7J1q8YIQBp1OlClq8aUsQU2bWJDth0WZG8fnzyQnmUFe2AiS1TRc91jg5XCwrWCEWVGyn6iFpbLs9uCfnWxqKylw0Kakc9yPIjPCHqg41MoJHtzFw3heozxO(klaOEb14(mE6U9n9AREhw201ZMvpCnShvT2MAaZlkayS(UgGbeSJe9rBNUr4LXXxEX5Nmc8tDQUaZxeTNUOY2zs8Lt6UF7XPjFYmpe(Dn(QZ(0PX9HBq(U3i3z8JHUlz7Z9bX01GF1w3MDkedk10NWEWEuKPy2VN7wuT29jB16v9yURQkm9Wj83tk0BG(d(Rv608Y5nhHDaispQNqrKbmgNiiceF4Jhxa6Weko3JhWuccHO6GopLveU3g6GA6GvH6aRREi(rAFdnztJVARPmsBfTh0IhVkBUbgQ7YHAs0xW5oGpXQHPOiUzA1PGXfnByRS0DiAoCv7yUFTd7uVpSBNHDEBnSZRByNNNKkbeTiG4da8hh2nYlawvgi8cKsgPfMlFMrESxXrEQ3h5nyKxJwHFveNG3uIJK8FoIdG9hqCWF1Psiqrc4mQpYB2I4qG19vE(CpH4X7CqIJ)RiXj4DIZaIZV0h5W4VPmh)dWCc)hJ5e(nzoITyoIV1JC6tG9XseQxpwsxN6DwsllXQZZWG2j59pbLGpveD79(JKXYVVX31vw3VLBHx)VrsPUoDRdWCun(56nGW8H6nXxzoQxKAFBlG9ytE0rkpHptY8ukoTxfoVZHr9I3rCYdat)2SjCtNvBbOiFFcYjDLt(lThCGok2A4p0syp8soVlu(F5cL5DYHBGIucJ5hO8isjV7wI3sLYH)ikLd))WhhO9933M6e(sOoqxKZy0aqFh0nbzBp2GpeFk8LQciy)0jqdPqPy8apgNIZWAEsO6jn(W(ZjNSVikElvgGGBPhtjzso1JYANZQEwIx4RICbUSN4fqvcFoWVc4GE6T7l)mYfGZgWKHQptiK(SU6VCF1)Nw15TVjZ7Ai6PEyLy35nWXfk3zr4xpcVh6OqJgam3Ft1S7V58omW2RosN3uHtII0Pwt293a4jtrwZN)6dqyU)MlamLXUPrnYhCvLMLMsxJULjwCcqRJUWuMHYaCDpWVTSmfebmT5Y0QIQgSGgQjh7d(YIxGZNXp83XWS1OPys76)pAeLJG9(tVOH3v5EoNX6DMVxJZihlypR)aGSXwQloStPDE0t15r(Z5qx3xVd9hCn(FDOAz0Gv2Y2K)o"
local maintainProfile = nil
local bundledDefaultProfile = nil
local bundledDefaultProfileFontPath = nil
local bundledDefaultProfileResolved = false
local legacyDefaultProfileSnapshot = nil
local legacyDefaultProfileSnapshotFontPath = nil

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
-- Units whose frames display a name label by default.
local NAME_TEXT_UNITS = {
    player = true,
    pet = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
    boss = true,
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
            displayMode = "icons",
            detached = false,
            size = 16,
            height = 8,
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
                hidePermanent = false,
                hideLongDuration = false,
                maxDurationSeconds = 60,
            },
        },
    }
end

-- Shared defaults for the stacked boss-frame group.
local function newBossDefaults()
    local defaults = newUnitDefaults("RIGHT", "RIGHT", -220, 120, 180, 32)
    defaults.powerHeight = 8
    defaults.fontSize = 11
    defaults.spacing = 8
    defaults.aura.buffs.enabled = false
    defaults.aura.debuffs.enabled = false
    return defaults
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
        boss = newBossDefaults(),
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
            incomingCastBoard = {
                enabled = true,
                anchorToPartyFrames = true,
                anchorX = 0,
                anchorY = 0,
                detachedX = 0,
                detachedY = -140,
                width = 248,
                height = 24,
                spacing = 4,
                maxBars = 6,
                fontSize = 13,
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
                    hidePermanent = false,
                    hideLongDuration = false,
                    maxDurationSeconds = 60,
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
                    hidePermanent = false,
                    hideLongDuration = false,
                    maxDurationSeconds = 60,
                },
            },
        },
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

-- Return whether two values match recursively.
local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
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

-- Return copied structured tracked aura defaults for the current class.
local function getDefaultTrackedAuraEntries()
    if Util and type(Util.GetTrackedAuraDefaultEntries) == "function" then
        return Util:GetTrackedAuraDefaultEntries()
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

local TRACKED_AURA_SQUARE_SLOT_SET = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

local TRACKED_AURA_ICON_SLOT_SET = {
    ICON1 = true,
    ICON2 = true,
    ICON3 = true,
    ICON4 = true,
}
local TRACKED_AURA_ENTRY_OFFSET_MIN = -80
local TRACKED_AURA_ENTRY_OFFSET_MAX = 80

local function sanitizeTrackedAuraColor(value)
    if type(value) ~= "table" then
        return nil
    end

    local red = tonumber(value.r ~= nil and value.r or value[1])
    local green = tonumber(value.g ~= nil and value.g or value[2])
    local blue = tonumber(value.b ~= nil and value.b or value[3])
    local alpha = tonumber(value.a ~= nil and value.a or value[4])
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
        return nil
    end

    return {
        r = Util:Clamp(red, 0, 1),
        g = Util:Clamp(green, 0, 1),
        b = Util:Clamp(blue, 0, 1),
        a = Util:Clamp(type(alpha) == "number" and alpha or 0.95, 0, 1),
    }
end

local function normalizeTrackedAuraDisplay(value)
    if value == "square" or value == "corner" or value == "rectangle" then
        return "square"
    end
    return "icon"
end

local function normalizeTrackedAuraSlot(display, value)
    if display == "square" then
        if TRACKED_AURA_SQUARE_SLOT_SET[value] == true then
            return value
        end
        return "TOPLEFT"
    end

    if TRACKED_AURA_ICON_SLOT_SET[value] == true then
        return value
    end
    return nil
end

local function normalizeTrackedAuraOffset(value)
    local numeric = tonumber(value)
    if type(numeric) ~= "number" then
        return nil
    end

    if numeric >= 0 then
        numeric = math.floor(numeric + 0.5)
    else
        numeric = math.ceil(numeric - 0.5)
    end

    return Util:Clamp(numeric, TRACKED_AURA_ENTRY_OFFSET_MIN, TRACKED_AURA_ENTRY_OFFSET_MAX)
end

local function sanitizeTrackedAuraEntry(value)
    if type(value) ~= "table" then
        return nil
    end

    local spellName = value.spell or value.spellName or value.name
    if type(spellName) ~= "string" then
        return nil
    end

    spellName = string.match(spellName, "^%s*(.-)%s*$")
    if not spellName or spellName == "" then
        return nil
    end

    local display = normalizeTrackedAuraDisplay(value.display)
    local entry = {
        spell = spellName,
        display = display,
        slot = normalizeTrackedAuraSlot(display, value.slot),
        ownOnly = value.ownOnly ~= false,
    }

    local size = tonumber(value.size)
    if type(size) == "number" then
        entry.size = Util:Clamp(math.floor(size + 0.5), 4, 48)
    end

    local offsetX = normalizeTrackedAuraOffset(value.x)
    if type(offsetX) == "number" and offsetX ~= 0 then
        entry.x = offsetX
    end

    local offsetY = normalizeTrackedAuraOffset(value.y)
    if type(offsetY) == "number" and offsetY ~= 0 then
        entry.y = offsetY
    end

    local color = sanitizeTrackedAuraColor(value.color)
    if display == "square" then
        entry.color = color or {
            r = 0.25,
            g = 0.95,
            b = 0.35,
            a = 0.95,
        }
    elseif color ~= nil then
        entry.color = color
    end

    return entry
end

local function sanitizeTrackedAuraEntries(value)
    if type(value) ~= "table" then
        return nil
    end

    local sanitized = {}
    for index = 1, #value do
        local entry = sanitizeTrackedAuraEntry(value[index])
        if entry then
            sanitized[#sanitized + 1] = entry
        end
    end

    return sanitized
end

local function buildLegacyTrackedAuraEntries(allowedSpells)
    local entries = {}
    if type(allowedSpells) ~= "table" then
        return entries
    end

    for index = 1, #allowedSpells do
        local spellName = allowedSpells[index]
        if type(spellName) == "string" and spellName ~= "" then
            entries[#entries + 1] = {
                spell = spellName,
                display = "icon",
                ownOnly = true,
            }
        end
    end

    return entries
end

local function buildTrackedAuraSpellListFromEntries(entries)
    local spellNames = {}
    local seen = {}
    if type(entries) ~= "table" then
        return spellNames
    end

    for index = 1, #entries do
        local entry = entries[index]
        local spellName = type(entry) == "table" and entry.spell or nil
        if type(spellName) == "string" and spellName ~= "" and seen[spellName] ~= true then
            seen[spellName] = true
            spellNames[#spellNames + 1] = spellName
        end
    end

    return spellNames
end

local function maintainTrackedAurasConfig(config)
    if type(config) ~= "table" then
        config = {}
    end

    if config.enabled == nil then
        config.enabled = true
    end
    config.size = Util:Clamp(tonumber(config.size) or getDefaultTrackedAuraSize(), 6, 48)

    local entries = sanitizeTrackedAuraEntries(config.entries)
    local allowedSpells = sanitizeAuraSpellList(config.allowedSpells)
    if entries == nil or #entries == 0 then
        if allowedSpells ~= nil and #allowedSpells > 0 then
            entries = buildLegacyTrackedAuraEntries(allowedSpells)
        else
            entries = getDefaultTrackedAuraEntries()
        end
    end

    if allowedSpells == nil or #allowedSpells == 0 then
        allowedSpells = buildTrackedAuraSpellListFromEntries(entries)
        if #allowedSpells == 0 then
            allowedSpells = getDefaultTrackedAuraNames()
        end
    end

    config.entries = entries
    config.allowedSpells = allowedSpells
    return config
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

        local entries = sanitizeTrackedAuraEntries(value.entries)
        if entries ~= nil then
            sanitized.entries = entries
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
    snapshot.auras = nil
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

-- Decode and sanitize one exported profile string.
local function decodeProfileTransferCode(code)
    local serializer, deflate = getTransferLibraries()
    if not serializer or not deflate then
        return nil, nil, "missing_dependency"
    end

    if type(code) ~= "string" then
        return nil, nil, "invalid_code"
    end

    local trimmedCode = string.match(code, "^%s*(.-)%s*$")
    if not trimmedCode or trimmedCode == "" then
        return nil, nil, "invalid_code"
    end

    local encodedPayload = string.match(trimmedCode, "^" .. PROFILE_EXPORT_PREFIX .. "(.+)$")
    if not encodedPayload then
        return nil, nil, "unsupported_format"
    end

    local decodedPayload = deflate:DecodeForPrint(encodedPayload)
    if type(decodedPayload) ~= "string" or decodedPayload == "" then
        return nil, nil, "decode_failed"
    end

    local payload = deflate:DecompressDeflate(decodedPayload)
    if type(payload) ~= "string" or payload == "" then
        return nil, nil, "decompress_failed"
    end

    local deserializeResults = { serializer:Deserialize(payload) }
    if deserializeResults[1] ~= true then
        return nil, nil, "deserialize_failed"
    end
    if #deserializeResults ~= 3 then
        return nil, nil, "invalid_payload"
    end

    local sourceProfileName = deserializeResults[2]
    local importedPayload = deserializeResults[3]
    if type(sourceProfileName) ~= "string" or type(importedPayload) ~= "table" then
        return nil, nil, "invalid_payload"
    end

    local importedProfile = sanitizeImportedProfile(importedPayload, DEFAULT_PROFILE, "")
    if not hasTableEntries(importedProfile) then
        return nil, nil, "invalid_payload"
    end

    return normalizeProfileName(sourceProfileName), importedProfile, nil
end

-- Return a normalized snapshot of the legacy in-file defaults for comparison.
local function getLegacyDefaultProfileSnapshot(defaultFontPath)
    local resolvedFontPath = defaultFontPath or DEFAULT_FONT_PATH
    if legacyDefaultProfileSnapshotFontPath ~= resolvedFontPath then
        legacyDefaultProfileSnapshot = buildProfileSnapshot(DEFAULT_PROFILE, resolvedFontPath)
        legacyDefaultProfileSnapshotFontPath = resolvedFontPath
    end
    return legacyDefaultProfileSnapshot
end

-- Return the addon's bundled default profile template for default/reset state.
local function getDefaultProfileTemplate(defaultFontPath)
    local resolvedFontPath = defaultFontPath or DEFAULT_FONT_PATH
    if bundledDefaultProfileResolved and bundledDefaultProfileFontPath == resolvedFontPath then
        return bundledDefaultProfile or DEFAULT_PROFILE
    end

    bundledDefaultProfileResolved = true
    bundledDefaultProfileFontPath = resolvedFontPath
    bundledDefaultProfile = nil

    local _, importedProfile = decodeProfileTransferCode(BUNDLED_DEFAULT_PROFILE_IMPORT)
    if type(importedProfile) == "table" then
        bundledDefaultProfile = buildProfileSnapshot(importedProfile, resolvedFontPath)
    end

    return bundledDefaultProfile or DEFAULT_PROFILE
end

-- Return the bundled default unit configuration for one unit token.
local function getDefaultUnitTemplate(unitToken, defaultFontPath)
    local defaults = getDefaultProfileTemplate(defaultFontPath)
    local units = type(defaults.units) == "table" and defaults.units or DEFAULT_PROFILE.units
    local defaultUnit = units[unitToken]
    if type(defaultUnit) ~= "table" then
        defaultUnit = DEFAULT_PROFILE.units[unitToken] or units.player or DEFAULT_PROFILE.units.player
    end
    return defaultUnit
end

-- Upgrade untouched stored Default profiles to the bundled seed.
local function shouldReplaceStoredDefaultProfile(profile, defaultFontPath)
    local seededDefaults = getDefaultProfileTemplate(defaultFontPath)
    if seededDefaults == DEFAULT_PROFILE or type(profile) ~= "table" then
        return false
    end

    local currentSnapshot = buildProfileSnapshot(profile, defaultFontPath)
    local legacySnapshot = getLegacyDefaultProfileSnapshot(defaultFontPath)
    if type(currentSnapshot) ~= "table" or type(legacySnapshot) ~= "table" then
        return false
    end

    return deepEqual(currentSnapshot, legacySnapshot)
end

-- Return default profile collection for a character.
local function newDefaultProfiles(defaultFontPath)
    return {
        Default = deepCopy(getDefaultProfileTemplate(defaultFontPath)),
    }
end

local function getLegacyTrackedAurasSource(db, charSettings)
    if type(charSettings) ~= "table" then
        return nil
    end

    local profiles = type(charSettings.profiles) == "table" and charSettings.profiles or nil
    local activeProfileName = normalizeProfileName(charSettings.activeProfile) or "Default"
    if type(profiles) == "table" then
        local activeProfile = profiles[activeProfileName]
        if type(activeProfile) == "table" and type(activeProfile.auras) == "table" then
            return activeProfile.auras
        end

        local defaultProfile = profiles.Default
        if activeProfileName ~= "Default" and type(defaultProfile) == "table" and type(defaultProfile.auras) == "table" then
            return defaultProfile.auras
        end

        for _, profileName in ipairs(getSortedKeys(profiles)) do
            local profile = profiles[profileName]
            if type(profile) == "table" and type(profile.auras) == "table" then
                return profile.auras
            end
        end
    end

    if type(db) ~= "table" then
        return nil
    end

    if type(db.auras) == "table" then
        return db.auras
    end

    local globalSettings = db.global
    if type(globalSettings) == "table" and type(globalSettings.auras) == "table" then
        return globalSettings.auras
    end

    return nil
end

local function ensureCharacterTrackedAurasConfig(db, charSettings)
    if type(charSettings) ~= "table" then
        return charSettings
    end

    if type(charSettings.auras) ~= "table" then
        local legacySource = getLegacyTrackedAurasSource(db, charSettings)
        charSettings.auras = type(legacySource) == "table" and deepCopy(legacySource) or {}
    end

    charSettings.auras = maintainTrackedAurasConfig(charSettings.auras)
    return charSettings
end

-- Return a cache key scoped to one character/profile pair.
local function getProfileCacheKey(charKey, profileName)
    return string.format("%s::%s", tostring(charKey or "UnknownCharacter"), tostring(profileName or "Default"))
end

local function sanitizeGroupDebuffFilterConfig(unitConfig)
    if type(unitConfig) ~= "table" then
        return
    end

    unitConfig.aura = type(unitConfig.aura) == "table" and unitConfig.aura or {}
    unitConfig.aura.debuffs = type(unitConfig.aura.debuffs) == "table" and unitConfig.aura.debuffs or {}

    local debuffsConfig = unitConfig.aura.debuffs
    debuffsConfig.hidePermanent = debuffsConfig.hidePermanent == true
    debuffsConfig.hideLongDuration = debuffsConfig.hideLongDuration == true

    local threshold = tonumber(debuffsConfig.maxDurationSeconds)
    if type(threshold) ~= "number" then
        threshold = 60
    end
    threshold = math.floor(threshold + 0.5)
    if threshold < 1 then
        threshold = 60
    end
    debuffsConfig.maxDurationSeconds = Util:Clamp(threshold, 1, 3600)
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

    if type(profile.units) == "table" then
        sanitizeGroupDebuffFilterConfig(profile.units.party)
        sanitizeGroupDebuffFilterConfig(profile.units.raid)

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
local function ensureCharacterSettings(charSettings, sourceProfiles, defaultFontPath)
    if type(charSettings) ~= "table" then
        charSettings = {}
    end

    if type(charSettings.profiles) ~= "table" then
        if type(sourceProfiles) == "table" then
            charSettings.profiles = deepCopy(sourceProfiles)
        else
            charSettings.profiles = newDefaultProfiles(defaultFontPath)
        end
    end

    if type(charSettings.profiles.Default) ~= "table" then
        charSettings.profiles.Default = deepCopy(getDefaultProfileTemplate(defaultFontPath))
    end

    local activeProfile = normalizeProfileName(charSettings.activeProfile) or "Default"
    if type(charSettings.profiles[activeProfile]) ~= "table" then
        activeProfile = "Default"
    end
    charSettings.activeProfile = activeProfile

    return charSettings
end

-- Upgrade one character's untouched Default profile to the bundled seed once.
local function ensureBundledDefaultProfileSeedApplied(charSettings, defaultFontPath)
    if type(charSettings) ~= "table" then
        return charSettings
    end

    local appliedVersion = tonumber(charSettings.bundledDefaultProfileVersion) or 0
    if appliedVersion >= BUNDLED_DEFAULT_PROFILE_VERSION then
        return charSettings
    end

    charSettings.profiles = type(charSettings.profiles) == "table" and charSettings.profiles or newDefaultProfiles(defaultFontPath)
    if type(charSettings.profiles.Default) ~= "table" then
        charSettings.profiles.Default = deepCopy(getDefaultProfileTemplate(defaultFontPath))
    elseif shouldReplaceStoredDefaultProfile(charSettings.profiles.Default, defaultFontPath) then
        charSettings.profiles.Default = deepCopy(getDefaultProfileTemplate(defaultFontPath))
    end

    charSettings.bundledDefaultProfileVersion = BUNDLED_DEFAULT_PROFILE_VERSION
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
    self._perfCountersEnabled = false
    self._perfCounters = {}
end

-- Resolve one character's settings and apply any one-time migrations once.
local function resolveCharacterSettings(self, sourceProfiles)
    if not self or not self.db then
        return nil, nil
    end

    local charKey = Util:GetCharacterKey()
    self.db.char = self.db.char or {}

    local defaultFontPath = self._defaultFontPath or DEFAULT_FONT_PATH
    local charSettings = ensureCharacterSettings(self.db.char[charKey], sourceProfiles, defaultFontPath)
    if (tonumber(charSettings.bundledDefaultProfileVersion) or 0) < BUNDLED_DEFAULT_PROFILE_VERSION then
        charSettings = ensureBundledDefaultProfileSeedApplied(charSettings, defaultFontPath)
    end
    charSettings = ensureCharacterTrackedAurasConfig(self.db, charSettings)

    self.db.char[charKey] = charSettings
    return charSettings, charKey
end

-- Resolve the active profile and cache bookkeeping used by hot config readers.
local function resolveActiveProfileContext(self)
    local charSettings, charKey = resolveCharacterSettings(self)
    if not charSettings then
        return nil
    end

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
    return {
        charKey = charKey,
        charSettings = charSettings,
        profileName = profileName,
        profiles = profiles,
        profile = profile,
        cacheKey = cacheKey,
    }
end

-- Resolve one unit config from the active profile without re-entering profile lookup.
local function resolveUnitConfigContext(self, unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil, nil
    end

    local context = resolveActiveProfileContext(self)
    if not context then
        return nil, nil
    end

    local profile = context.profile
    profile.units = profile.units or {}

    local unitDefaultsApplied = self._unitDefaultsAppliedByProfile[context.cacheKey]
    if type(unitDefaultsApplied) ~= "table" then
        unitDefaultsApplied = {}
        self._unitDefaultsAppliedByProfile[context.cacheKey] = unitDefaultsApplied
    end

    if type(profile.units[unitToken]) ~= "table" then
        profile.units[unitToken] = {}
        unitDefaultsApplied[unitToken] = nil
    end

    if not unitDefaultsApplied[unitToken] then
        mergeDefaults(profile.units[unitToken], getDefaultUnitTemplate(unitToken, self._defaultFontPath or DEFAULT_FONT_PATH))
        unitDefaultsApplied[unitToken] = true
    end

    return profile.units[unitToken], context
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
            local preparedSettings = ensureCharacterSettings(charSettings, legacyProfiles, self._defaultFontPath or DEFAULT_FONT_PATH)
            charStorage[charKey] = ensureBundledDefaultProfileSeedApplied(preparedSettings, self._defaultFontPath or DEFAULT_FONT_PATH)
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
    local perfStartedAt = startPerfCounters(self)
    local charSettings = resolveCharacterSettings(self)
    return finishPerfCounters(self, "GetCharacterSettings", perfStartedAt, charSettings)
end

-- Return the character-scoped tracked aura configuration table.
function DataHandle:GetTrackedAurasConfig()
    local perfStartedAt = startPerfCounters(self)
    local charSettings = resolveCharacterSettings(self)
    local auras = charSettings and charSettings.auras or nil
    return finishPerfCounters(self, "GetTrackedAurasConfig", perfStartedAt, auras)
end

-- Return current profile table.
function DataHandle:GetProfile()
    local perfStartedAt = startPerfCounters(self)
    local context = resolveActiveProfileContext(self)
    return finishPerfCounters(self, "GetProfile", perfStartedAt, context and context.profile or nil)
end

-- Return active profile name.
function DataHandle:GetActiveProfileName()
    local charSettings = resolveCharacterSettings(self)
    if not charSettings then
        return "Default"
    end
    return normalizeProfileName(charSettings.activeProfile) or "Default"
end

-- Return sorted profile names.
function DataHandle:GetProfileNames()
    local charSettings = resolveCharacterSettings(self)
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

    local charSettings = resolveCharacterSettings(self)
    local profiles = charSettings and charSettings.profiles or {}
    return type(profiles[normalized]) == "table"
end

-- Create profile, optionally copying from source profile.
function DataHandle:CreateProfile(name, sourceProfileName)
    local normalizedName = normalizeProfileName(name)
    if not normalizedName then
        return false, "invalid_name"
    end

    local charSettings = resolveCharacterSettings(self)
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
        sourceProfile = getDefaultProfileTemplate(self._defaultFontPath or DEFAULT_FONT_PATH)
    end

    profiles[normalizedName] = buildProfileSnapshot(sourceProfile, self._defaultFontPath or DEFAULT_FONT_PATH) or deepCopy(getDefaultProfileTemplate(self._defaultFontPath or DEFAULT_FONT_PATH))
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

    local charSettings = resolveCharacterSettings(self)
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

    local charSettings = resolveCharacterSettings(self)
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

    local charSettings = resolveCharacterSettings(self)
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
    local charSettings = resolveCharacterSettings(self)
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
    local normalizedSourceName, importedProfile, decodeError = decodeProfileTransferCode(code)
    if type(importedProfile) ~= "table" then
        return nil, decodeError or "invalid_payload"
    end

    local targetName = normalizeProfileName(targetProfileName) or normalizedSourceName or "Imported"
    local charSettings = resolveCharacterSettings(self)
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
    local perfStartedAt = startPerfCounters(self)
    local unitConfig = resolveUnitConfigContext(self, unitToken)
    return finishPerfCounters(self, "GetUnitConfig", perfStartedAt, unitConfig)
end

-- Set unit config.
function DataHandle:SetUnitConfig(unitToken, key, value)
    local unitConfig, context = resolveUnitConfigContext(self, unitToken)
    if not unitConfig or not context then
        return
    end
    local cacheKey = context.cacheKey
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

    local context = resolveActiveProfileContext(self)
    if not context then
        return nil
    end

    local profile = context.profile
    profile.units = profile.units or {}
    profile.units[unitToken] = deepCopy(getDefaultUnitTemplate(unitToken, self._defaultFontPath or DEFAULT_FONT_PATH))

    self._unitDefaultsAppliedByProfile[context.cacheKey] = self._unitDefaultsAppliedByProfile[context.cacheKey] or {}
    self._unitDefaultsAppliedByProfile[context.cacheKey][unitToken] = true

    return profile.units[unitToken]
end

-- Enable or disable lightweight runtime profiling counters for hot getters.
function DataHandle:SetPerfCountersEnabled(enabled, resetExisting)
    self._perfCountersEnabled = enabled == true
    if resetExisting ~= false then
        self._perfCounters = {}
    end
end

-- Return a snapshot of the current profiling counters.
function DataHandle:GetPerfCounters()
    return copyPerfCounters(self._perfCounters)
end

-- Clear recorded profiling counters.
function DataHandle:ResetPerfCounters()
    self._perfCounters = {}
end

addon:RegisterModule("dataHandle", DataHandle:New())
