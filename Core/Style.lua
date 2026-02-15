local _, ns = ...

local Style = {}
local fontValidationCache = {}
local availableFontsCache = nil
local fontProbe = nil

Style.DEFAULT_FONT = "Interface\\AddOns\\mummuFrames\\Fonts\\ProductSans-Bold.ttf"
Style.DEFAULT_BAR_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o8.tga"

-- Read style settings from the active profile when available.
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

-- Return whether pixel-perfect layout is enabled in profile style.
function Style:IsPixelPerfectEnabled()
    local style = getProfileStyle()
    return not (style and style.pixelPerfect == false)
end

-- Return the UI pixel size at the current effective scale.
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

-- Snap a numeric value to the current UI pixel grid.
function Style:Snap(value)
    local n = tonumber(value) or 0
    local pixel = self:GetPixelSize()
    return math.floor((n / pixel) + 0.5) * pixel
end

-- Build one hidden font string used to probe whether font files are usable.
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

-- Return whether a font path can be loaded by WoW's SetFont API.
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

    local function tryAssign(flags)
        local ok, setResult = pcall(probe.SetFont, probe, fontPath, 12, flags)
        if not ok or setResult == false then
            return false
        end
        local assigned = probe:GetFont()
        return type(assigned) == "string" and assigned ~= ""
    end

    -- Some custom fonts fail with outline flags but work with plain rendering.
    local usable = tryAssign("OUTLINE") or tryAssign("")
    fontValidationCache[fontPath] = usable
    return usable
end

-- Return discovered addon fonts from the generated catalog.
function Style:GetAvailableFonts(forceRefresh)
    if forceRefresh then
        availableFontsCache = nil
    end

    if availableFontsCache then
        return availableFontsCache
    end

    local available = {}
    local seenPaths = {}
    local catalog = ns.FontCatalog and ns.FontCatalog.list or {}

    for i = 1, #catalog do
        local entry = catalog[i]
        local path = type(entry) == "table" and entry.path or nil
        if type(path) == "string" and path ~= "" and not seenPaths[path] then
            available[#available + 1] = {
                key = entry.key or path,
                label = entry.label or path,
                path = path,
            }
            seenPaths[path] = true
        end
    end

    if not seenPaths[self.DEFAULT_FONT] and type(self.DEFAULT_FONT) == "string" and self.DEFAULT_FONT ~= "" then
        available[#available + 1] = {
            key = "default",
            label = "Default",
            path = self.DEFAULT_FONT,
        }
        seenPaths[self.DEFAULT_FONT] = true
    end

    if #available == 0 and type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT ~= "" then
        available[#available + 1] = {
            key = "standard",
            label = "Blizzard Default",
            path = STANDARD_TEXT_FONT,
        }
    end

    availableFontsCache = available
    return availableFontsCache
end

-- Return the preferred fallback font path for this addon.
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

-- Return the configured font path, or the addon default.
function Style:GetFontPath()
    local style = getProfileStyle()
    local configuredPath = style and style.fontPath or nil
    if type(configuredPath) == "string" and configuredPath ~= "" then
        return configuredPath
    end

    return self:GetDefaultFontPath()
end

-- Return the configured bar texture path, or the addon default.
function Style:GetBarTexturePath()
    local style = getProfileStyle()
    return (style and style.barTexturePath) or self.DEFAULT_BAR_TEXTURE
end

-- Apply font settings with safe fallbacks if a font fails to load.
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

    local function normalizePath(path)
        if type(path) ~= "string" then
            return nil
        end
        return string.lower(string.gsub(path, "/", "\\"))
    end

    local function hasFontAssigned()
        local fontPath = fontString:GetFont()
        return type(fontPath) == "string" and fontPath ~= ""
    end

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
        -- Some clients return nil on success; only explicit false means failure.
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

        -- Some clients normalize/redirect path internally; accept only if it actually changed.
        return assignedPath ~= beforePath
    end

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
        -- Fall back to Blizzard's standard font first.
        if not trySetFontWithFallbackFlags(STANDARD_TEXT_FONT) then
            -- Final fallback uses a known built-in font path.
            trySetFontWithFallbackFlags("Fonts\\FRIZQT__.TTF")
        end
    end

    -- If file-based font paths failed, force a built-in font object.
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

-- Apply the status bar texture and force non-tiled rendering.
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

-- Create a subtle background texture for a frame.
function Style:CreateBackground(frame, r, g, b, a)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0.06, g or 0.06, b or 0.07, a or 0.88)
    return bg
end

ns.Style = Style
