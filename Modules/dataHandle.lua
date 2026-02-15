local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

local DataHandle = ns.Object:Extend()
local DEFAULT_FONT_PATH = (Style and Style.DEFAULT_FONT) or "Interface\\AddOns\\mummuFrames\\Fonts\\ProductSans-Bold.ttf"
local NAME_TEXT_UNITS = {
    player = true,
    pet = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
}

-- Build default config values for a single unit frame.
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
        fontSize = 12,
        showNameText = true,
        showHealthText = true,
        aura = {
            enabled = true,
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

-- Store global and per-character defaults for the saved database.
local DEFAULTS = {
    global = {
        version = 1,
        profiles = {
            Default = {
                enabled = true,
                testMode = false,
                minimap = {
                    hide = false,
                    angle = 220,
                },
                style = {
                    fontPath = DEFAULT_FONT_PATH,
                    fontSize = 12,
                    fontFlags = "OUTLINE",
                    pixelPerfect = true,
                    barTexturePath = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga",
                },
                units = {
                    player = newUnitDefaults("CENTER", "CENTER", -260, -220, 240, 46),
                    pet = newUnitDefaults("CENTER", "CENTER", -260, -275, 170, 32),
                    target = newUnitDefaults("CENTER", "CENTER", 260, -220, 240, 46),
                    targettarget = newUnitDefaults("CENTER", "CENTER", 260, -275, 170, 32),
                    focus = newUnitDefaults("CENTER", "CENTER", 0, -275, 200, 38),
                    focustarget = newUnitDefaults("CENTER", "CENTER", 0, -320, 160, 30),
                    party = {
                        enabled = true,
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
                            buffs = {
                                enabled = true,
                                source = "all",
                                anchorPoint = "TOPLEFT",
                                relativePoint = "BOTTOMLEFT",
                                x = 0,
                                y = -3,
                                size = 14,
                                scale = 1,
                                max = 6,
                            },
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
                        aura = {
                            enabled = true,
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
            },
        },
    },
    char = {},
}

-- Fill missing values in a table from a defaults table recursively.
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

-- Split a dot path like "a.b.c" into a list of keys.
local function splitPath(path)
    local parts = {}
    for token in string.gmatch(path, "[^%.]+") do
        table.insert(parts, token)
    end
    return parts
end

-- Set up module state.
function DataHandle:Constructor()
    self.addon = nil
    self.db = nil
end

-- Initialize and merge saved variables with defaults.
function DataHandle:OnInitialize(addonRef)
    self.addon = addonRef
    mummuFramesDB = mummuFramesDB or {}
    mergeDefaults(mummuFramesDB, DEFAULTS)

    local defaultFontPath = DEFAULT_FONT_PATH
    if Style and type(Style.GetDefaultFontPath) == "function" then
        defaultFontPath = Style:GetDefaultFontPath()
    end

    -- Migrate missing/invalid style settings to safe defaults.
    local profiles = mummuFramesDB.global and mummuFramesDB.global.profiles
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
                            -- Keep names visible by default; there is currently no name-visibility toggle in the UI.
                            unitConfig.showNameText = true
                        end
                    end
                end
            end
        end
    end

    self.db = mummuFramesDB
end

-- Return the raw addon database table.
function DataHandle:GetDB()
    return self.db
end

-- Return per-character settings, creating them when needed.
function DataHandle:GetCharacterSettings()
    local charKey = Util:GetCharacterKey()
    self.db.char[charKey] = self.db.char[charKey] or {
        activeProfile = "Default",
    }
    return self.db.char[charKey]
end

-- Return the active profile and ensure it has defaults.
function DataHandle:GetProfile()
    local charSettings = self:GetCharacterSettings()
    local profileName = charSettings.activeProfile or "Default"
    local profiles = self.db.global.profiles

    if type(profiles[profileName]) ~= "table" then
        profiles[profileName] = {}
    end
    mergeDefaults(profiles[profileName], DEFAULTS.global.profiles.Default)
    return profiles[profileName]
end

-- Return one unit config and ensure unit-level defaults exist.
function DataHandle:GetUnitConfig(unitToken)
    local profile = self:GetProfile()
    if type(profile.units[unitToken]) ~= "table" then
        profile.units[unitToken] = {}
    end

    local defaultUnit = DEFAULTS.global.profiles.Default.units[unitToken]
    if type(defaultUnit) == "table" then
        mergeDefaults(profile.units[unitToken], defaultUnit)
    else
        mergeDefaults(profile.units[unitToken], DEFAULTS.global.profiles.Default.units.player)
    end

    return profile.units[unitToken]
end

-- Set a unit config value, including nested keys using dot paths.
function DataHandle:SetUnitConfig(unitToken, key, value)
    local unitConfig = self:GetUnitConfig(unitToken)
    if type(key) ~= "string" or key == "" then
        return
    end

    -- Walk nested tables when the key uses dot notation.
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
        return
    end

    unitConfig[key] = value
end

addon:RegisterModule("dataHandle", DataHandle:New())
