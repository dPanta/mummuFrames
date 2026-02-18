local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

-- Create class holding data handle behavior.
local DataHandle = ns.Object:Extend()
local DEFAULT_FONT_PATH = (Style and Style.DEFAULT_FONT) or "Interface\\AddOns\\mummuFrames\\Fonts\\ProductSans-Bold.ttf"
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
        -- Create table holding profiles.
        profiles = {
            -- Create table holding default.
            Default = {
                enabled = true,
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
                                source = "all",
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
