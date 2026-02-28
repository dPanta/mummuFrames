-- Centralized style/media resolver.
-- Handles font/texture discovery, profile overrides, and pixel-perfect snapping.

local _, ns = ...

-- Create table holding style.
local Style = {}
-- Create table holding font validation cache.
local fontValidationCache = {}
local availableFontsCache = nil
local availableBarTexturesCache = nil
local fontProbe = nil
local lsm = nil
local lsmCallbacksRegistered = false

Style.DEFAULT_FONT = "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf"
Style.DEFAULT_BAR_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga"

-- Normalize media path. Bug parade continues.
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
        -- Invalidate media caches.
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

-- Return profile style.
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

-- Check pixel perfect enabled.
function Style:IsPixelPerfectEnabled()
    local style = getProfileStyle()
    return not (style and style.pixelPerfect == false)
end

-- Return pixel size.
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

-- Ensure font probe.
local function ensureFontProbe()
    if fontProbe then
        return fontProbe
    end

    local holder = UIParent
    if not holder then
        -- Create frame widget.
        holder = CreateFrame("Frame")
        holder:Hide()
    end

    if holder and type(holder.CreateFontString) == "function" then
        -- Create text font string.
        fontProbe = holder:CreateFontString(nil, "OVERLAY")
    end

    return fontProbe
end

-- Check font path usable.
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

    -- Try assigning font path with flags.
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

    -- Create table holding available.
    local available = {}
    -- Create table holding seen paths.
    local seenPaths = {}
    local catalog = ns.FontCatalog and ns.FontCatalog.list or {}

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

    for i = 1, #catalog do
        local entry = catalog[i]
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
                -- Create table holding names.
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

    -- Create table holding available.
    local available = {}
    -- Create table holding seen paths.
    local seenPaths = {}

    -- Add texture option. Nothing exploded yet.
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
                -- Create table holding names.
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

    if not trySetFontWithFallbackFlags(self:GetFontPath()) then
        if not trySetFontWithFallbackFlags(STANDARD_TEXT_FONT) then
            trySetFontWithFallbackFlags("Fonts\\FRIZQT__.TTF")
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

-- Create background texture layer.
function Style:CreateBackground(frame, r, g, b, a)
    -- Create texture for bg.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0.06, g or 0.06, b or 0.07, a or 0.88)
    return bg
end

ns.Style = Style
