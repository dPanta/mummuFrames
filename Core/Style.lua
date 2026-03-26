-- Centralized style/media resolver.
-- Handles font/texture discovery, profile overrides, and pixel-perfect snapping.

local _, ns = ...

-- Shared style/media helpers exposed to the rest of the addon.
local Style = {}
-- Cache of font-path usability checks.
local fontValidationCache = {}
local availableFontsCache = nil
local availableBarTexturesCache = nil
local fontProbe = nil
local lsm = nil
local lsmCallbacksRegistered = false
local BUNDLED_FONTS = {
    {
        key = "expressway",
        label = "Expressway",
        path = "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf",
    },
    {
        key = "Fredoka_SemiBold",
        label = "Fredoka Semi Bold",
        path = "Interface\\AddOns\\mummuFrames\\Fonts\\Fredoka-SemiBold.ttf",
    },
}

Style.DEFAULT_FONT = "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf"
Style.DEFAULT_BAR_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga"
Style.DARK_MODE_GRANITE_COLOR = { 0.19, 0.20, 0.22, 0.95 }
Style.DARK_MODE_HEALTH_BAR_BACKGROUND_COLOR = { 0.90, 0.72, 0.73, 0.78 }
Style.DARK_MODE_PRIMARY_POWER_BAR_BACKGROUND_COLOR = { 0.72, 0.50, 0.51, 0.55 }
local DEFAULT_STATUS_BAR_BACKGROUND_COLOR = { 0.00, 0.00, 0.00, 0.55 }

-- Normalize media paths so cache lookups ignore slash and case differences.
local function normalizeMediaPath(path)
    if type(path) ~= "string" then
        return nil
    end
    return string.lower(string.gsub(path, "/", "\\"))
end

-- Return cached LibSharedMedia handle.
local function getLSM()
    if lsm then
        return lsm
    end

    local libStub = _G.LibStub or LibStub
    if type(libStub) == "table" and type(libStub.GetLibrary) == "function" then
        lsm = libStub:GetLibrary("LibSharedMedia-3.0", true)
    elseif type(libStub) == "function" then
        local ok, found = pcall(libStub, "LibSharedMedia-3.0", true)
        if ok then
            lsm = found
        end
    end

    if lsm and not lsmCallbacksRegistered and type(lsm.RegisterCallback) == "function" then
        -- Clear cached lists when LibSharedMedia content changes at runtime.
        local function invalidateMediaCaches()
            availableFontsCache = nil
            availableBarTexturesCache = nil
        end

        lsm:RegisterCallback("LibSharedMedia_Registered", invalidateMediaCaches)
        lsm:RegisterCallback("LibSharedMedia_SetGlobal", invalidateMediaCaches)
        lsmCallbacksRegistered = true
    end

    return lsm
end

-- Return the current profile's style table, if available.
local function getProfileStyle()
    local addon = _G.mummuFrames
    if not addon or type(addon.GetModule) ~= "function" then
        return nil
    end

    local dataHandle = addon:GetModule("dataHandle")
    if not dataHandle or type(dataHandle.GetProfile) ~= "function" then
        return nil
    end

    local profile = dataHandle:GetProfile()
    return profile and profile.style or nil
end

-- Return whether pixel-perfect snapping is enabled in the active profile.
function Style:IsPixelPerfectEnabled()
    local style = getProfileStyle()
    return not (style and style.pixelPerfect == false)
end

-- Return whether Dark Mode is enabled in the active profile.
function Style:IsDarkModeEnabled()
    local style = getProfileStyle()
    return style and style.darkMode == true or false
end

-- Return one physical screen pixel in UI coordinates.
function Style:GetPixelSize()
    local scale = 1
    if UIParent and type(UIParent.GetEffectiveScale) == "function" then
        scale = UIParent:GetEffectiveScale() or 1
    end
    if type(scale) ~= "number" or scale <= 0 then
        scale = 1
    end
    return 1 / scale
end

-- Snap value to pixel grid.
function Style:Snap(value)
    local n = tonumber(value) or 0
    local pixel = self:GetPixelSize()
    return math.floor((n / pixel) + 0.5) * pixel
end

-- Lazily create the hidden FontString used to validate font paths.
local function ensureFontProbe()
    if fontProbe then
        return fontProbe
    end

    local holder = UIParent
    if not holder then
        holder = CreateFrame("Frame")
        holder:Hide()
    end

    if holder and type(holder.CreateFontString) == "function" then
        fontProbe = holder:CreateFontString(nil, "OVERLAY")
    end

    return fontProbe
end

-- Return whether the supplied font path can actually be applied.
function Style:IsFontPathUsable(fontPath)
    if type(fontPath) ~= "string" or fontPath == "" then
        return false
    end

    if fontValidationCache[fontPath] ~= nil then
        return fontValidationCache[fontPath]
    end

    local probe = ensureFontProbe()
    if not probe then
        fontValidationCache[fontPath] = false
        return false
    end

    -- Some fonts only accept specific flags; try both common paths.
    local function tryAssign(flags)
        local ok, setResult = pcall(probe.SetFont, probe, fontPath, 12, flags)
        if not ok or setResult == false then
            return false
        end
        local assigned = probe:GetFont()
        return type(assigned) == "string" and assigned ~= ""
    end

    local usable = tryAssign("OUTLINE") or tryAssign("")
    fontValidationCache[fontPath] = usable
    return usable
end

-- Return available fonts.
function Style:GetAvailableFonts(forceRefresh)
    if forceRefresh then
        availableFontsCache = nil
    end

    if availableFontsCache then
        return availableFontsCache
    end

    local available = {}
    local seenPaths = {}
    -- Add font option.
    local function addFontOption(key, label, path)
        if type(path) ~= "string" or path == "" then
            return
        end

        local normalized = normalizeMediaPath(path)
        if normalized and seenPaths[normalized] then
            return
        end

        available[#available + 1] = {
            key = key or path,
            label = label or path,
            path = path,
        }

        if normalized then
            seenPaths[normalized] = true
        end
    end

    for i = 1, #BUNDLED_FONTS do
        local entry = BUNDLED_FONTS[i]
        local path = type(entry) == "table" and entry.path or nil
        if type(path) == "string" and path ~= "" then
            addFontOption(entry.key or path, entry.label or path, path)
        end
    end

    local lsmRef = getLSM()
    if lsmRef and type(lsmRef.Fetch) == "function" then
        local names = nil
        if type(lsmRef.List) == "function" then
            names = lsmRef:List("font")
        end
        if type(names) ~= "table" and type(lsmRef.HashTable) == "function" then
            local fontTable = lsmRef:HashTable("font")
            if type(fontTable) == "table" then
                names = {}
                for name in pairs(fontTable) do
                    names[#names + 1] = name
                end
                table.sort(names)
            end
        end

        if type(names) == "table" then
            for i = 1, #names do
                local mediaName = names[i]
                local mediaPath = lsmRef:Fetch("font", mediaName, true)
                if self:IsFontPathUsable(mediaPath) then
                    addFontOption("lsm_font_" .. mediaName, mediaName, mediaPath)
                end
            end
        end
    end

    addFontOption("default", "Default", self.DEFAULT_FONT)

    if #available == 0 then
        addFontOption("standard", "Blizzard Default", STANDARD_TEXT_FONT)
    end

    availableFontsCache = available
    return availableFontsCache
end

-- Return available bar textures.
function Style:GetAvailableBarTextures(forceRefresh)
    if forceRefresh then
        availableBarTexturesCache = nil
    end

    if availableBarTexturesCache then
        return availableBarTexturesCache
    end

    local available = {}
    local seenPaths = {}

    -- Add one unique texture option to the dropdown list.
    local function addTextureOption(key, label, path)
        if type(path) ~= "string" or path == "" then
            return
        end

        local normalized = normalizeMediaPath(path)
        if normalized and seenPaths[normalized] then
            return
        end

        available[#available + 1] = {
            key = key or path,
            label = label or path,
            path = path,
        }

        if normalized then
            seenPaths[normalized] = true
        end
    end

    addTextureOption("default", "Default", self.DEFAULT_BAR_TEXTURE)

    local lsmRef = getLSM()
    if lsmRef and type(lsmRef.Fetch) == "function" then
        local names = nil
        if type(lsmRef.List) == "function" then
            names = lsmRef:List("statusbar")
        end
        if type(names) ~= "table" and type(lsmRef.HashTable) == "function" then
            local textureTable = lsmRef:HashTable("statusbar")
            if type(textureTable) == "table" then
                names = {}
                for name in pairs(textureTable) do
                    names[#names + 1] = name
                end
                table.sort(names)
            end
        end

        if type(names) == "table" then
            for i = 1, #names do
                local mediaName = names[i]
                local mediaPath = lsmRef:Fetch("statusbar", mediaName, true)
                addTextureOption("lsm_statusbar_" .. mediaName, mediaName, mediaPath)
            end
        end
    end

    availableBarTexturesCache = available
    return availableBarTexturesCache
end

-- Return default font path.
function Style:GetDefaultFontPath()
    local available = self:GetAvailableFonts()
    for i = 1, #available do
        if available[i].path == self.DEFAULT_FONT then
            return self.DEFAULT_FONT
        end
    end

    if available[1] and available[1].path then
        return available[1].path
    end

    return self.DEFAULT_FONT
end

-- Return default bar texture path.
function Style:GetDefaultBarTexturePath()
    local available = self:GetAvailableBarTextures()
    for i = 1, #available do
        if available[i].path == self.DEFAULT_BAR_TEXTURE then
            return self.DEFAULT_BAR_TEXTURE
        end
    end

    if available[1] and available[1].path then
        return available[1].path
    end

    return self.DEFAULT_BAR_TEXTURE
end

-- Return font path.
function Style:GetFontPath()
    local style = getProfileStyle()
    local configuredPath = style and style.fontPath or nil
    if type(configuredPath) == "string" and configuredPath ~= "" then
        return configuredPath
    end

    return self:GetDefaultFontPath()
end

-- Return bar texture path.
function Style:GetBarTexturePath()
    local style = getProfileStyle()
    local configuredPath = style and style.barTexturePath or nil
    if type(configuredPath) == "string" and configuredPath ~= "" then
        return configuredPath
    end

    return self:GetDefaultBarTexturePath()
end

-- Return the class text color for a class token, or nil when unavailable.
function Style:GetClassTextColor(classToken)
    if type(classToken) ~= "string" or classToken == "" then
        return nil
    end

    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil
    if type(classColor) ~= "table" then
        return nil
    end

    local r = tonumber(classColor.r)
    local g = tonumber(classColor.g)
    local b = tonumber(classColor.b)
    if not r or not g or not b then
        return nil
    end

    return r, g, b, 1
end

-- Return the class text color for a player unit token, or nil when unavailable.
function Style:GetPlayerClassTextColor(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if type(UnitIsPlayer) ~= "function" or not UnitIsPlayer(unitToken) then
        return nil
    end

    local _, classToken = UnitClass(unitToken)
    return self:GetClassTextColor(classToken)
end

-- Apply font with fallback paths.
function Style:ApplyFont(fontString, size, flags)
    if not fontString then
        return
    end

    local resolvedSize = math.floor((tonumber(size) or 11) + 0.5)
    if resolvedSize < 6 then
        resolvedSize = 6
    end

    local style = getProfileStyle()
    local defaultFlags = "OUTLINE"
    if style and type(style.fontFlags) == "string" and style.fontFlags ~= "" then
        defaultFlags = style.fontFlags
    end
    local resolvedFlags = (flags == nil) and defaultFlags or flags

    -- Normalize font path slashes and case.
    local function normalizePath(path)
        if type(path) ~= "string" then
            return nil
        end
        return string.lower(string.gsub(path, "/", "\\"))
    end

    -- Check font assigned.
    local function hasFontAssigned()
        local fontPath = fontString:GetFont()
        return type(fontPath) == "string" and fontPath ~= ""
    end

    -- Try set font.
    local function trySetFont(path, flagsOverride)
        if type(path) ~= "string" or path == "" then
            return false
        end
        local flagsToUse = flagsOverride
        if flagsToUse == nil then
            flagsToUse = resolvedFlags
        end
        local beforePath = normalizePath(fontString:GetFont())
        local ok, setResult = pcall(fontString.SetFont, fontString, path, resolvedSize, flagsToUse)
        if not ok or setResult == false then
            return false
        end

        local assignedPath = normalizePath(fontString:GetFont())
        if not assignedPath or assignedPath == "" then
            return false
        end

        local targetPath = normalizePath(path)
        if assignedPath == targetPath then
            return true
        end

        return assignedPath ~= beforePath
    end

    -- Try set font with fallback flags.
    local function trySetFontWithFallbackFlags(path)
        if trySetFont(path, resolvedFlags) then
            return true
        end
        if resolvedFlags ~= "" and trySetFont(path, "") then
            return true
        end
        return false
    end

    local function trySetFontFromObject(fontObject)
        if type(fontObject) ~= "table" or type(fontObject.GetFont) ~= "function" then
            return false
        end

        local okFontInfo, objectPath, _, objectFlags = pcall(fontObject.GetFont, fontObject)
        if not okFontInfo or type(objectPath) ~= "string" or objectPath == "" then
            return false
        end

        if trySetFontWithFallbackFlags(objectPath) then
            return true
        end

        if type(objectFlags) == "string" and objectFlags ~= "" and objectFlags ~= resolvedFlags then
            if trySetFont(objectPath, objectFlags) then
                return true
            end
            if trySetFont(objectPath, "") then
                return true
            end
        end

        return false
    end

    if not trySetFontWithFallbackFlags(self:GetFontPath()) then
        if not trySetFontWithFallbackFlags(STANDARD_TEXT_FONT) then
            trySetFontWithFallbackFlags("Fonts\\FRIZQT__.TTF")
        end
    end

    if not hasFontAssigned() then
        local fallbackFontObjects = {
            GameFontNormal,
            GameFontNormalSmall,
            GameFontHighlightSmall,
            SystemFont_Shadow_Med1,
            SystemFont_Med1,
        }

        for index = 1, #fallbackFontObjects do
            if trySetFontFromObject(fallbackFontObjects[index]) then
                break
            end
        end
    end

    if not hasFontAssigned() then
        local fallbackObject = GameFontNormal or SystemFont_Shadow_Med1
        if fallbackObject then
            pcall(fontString.SetFontObject, fontString, fallbackObject)
        end
    end

    if hasFontAssigned() then
        fontString:SetShadowColor(0, 0, 0, 0)
        fontString:SetShadowOffset(0, 0)
    end
end

-- Apply status bar texture.
function Style:ApplyStatusBarTexture(statusBar)
    if not statusBar then
        return
    end

    statusBar:SetStatusBarTexture(self:GetBarTexturePath())
    local tex = statusBar:GetStatusBarTexture()
    if tex then
        tex:SetHorizTile(false)
        tex:SetVertTile(false)
    end
end

-- Return the background tint for a status bar role.
local function getStatusBarBackingColor(isDarkModeEnabled, role)
    if isDarkModeEnabled and role == "health" then
        return Style.DARK_MODE_HEALTH_BAR_BACKGROUND_COLOR[1],
            Style.DARK_MODE_HEALTH_BAR_BACKGROUND_COLOR[2],
            Style.DARK_MODE_HEALTH_BAR_BACKGROUND_COLOR[3],
            Style.DARK_MODE_HEALTH_BAR_BACKGROUND_COLOR[4]
    end

    if isDarkModeEnabled and role == "primaryPower" then
        return Style.DARK_MODE_PRIMARY_POWER_BAR_BACKGROUND_COLOR[1],
            Style.DARK_MODE_PRIMARY_POWER_BAR_BACKGROUND_COLOR[2],
            Style.DARK_MODE_PRIMARY_POWER_BAR_BACKGROUND_COLOR[3],
            Style.DARK_MODE_PRIMARY_POWER_BAR_BACKGROUND_COLOR[4]
    end

    return DEFAULT_STATUS_BAR_BACKGROUND_COLOR[1],
        DEFAULT_STATUS_BAR_BACKGROUND_COLOR[2],
        DEFAULT_STATUS_BAR_BACKGROUND_COLOR[3],
        DEFAULT_STATUS_BAR_BACKGROUND_COLOR[4]
end

-- Apply the background tint for a status bar based on its semantic role.
function Style:ApplyStatusBarBacking(statusBar, role)
    if not statusBar or not statusBar.Background then
        return
    end

    local resolvedRole = role or statusBar._mummuStatusBarRole or "generic"
    if type(role) == "string" and role ~= "" then
        statusBar._mummuStatusBarRole = role
    end

    local r, g, b, a = getStatusBarBackingColor(self:IsDarkModeEnabled(), resolvedRole)
    statusBar.Background:SetColorTexture(r, g, b, a)
end

-- Create background texture layer.
function Style:CreateBackground(frame, r, g, b, a)
    -- Create texture for bg.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0.06, g or 0.06, b or 0.07, a or 0.88)
    return bg
end

ns.Style = Style
