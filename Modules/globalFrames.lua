local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

local GlobalFrames = ns.Object:Extend()

-- Set up module state.
function GlobalFrames:Constructor()
    self.addon = nil
end

-- Store a reference to the addon during initialization.
function GlobalFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Build a styled status bar with a dark background.
function GlobalFrames:CreateStatusBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    Style:ApplyStatusBarTexture(bar)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    bar.Background = bg

    return bar
end

-- Create the base secure unit frame container and core widgets.
function GlobalFrames:CreateUnitFrameBase(name, parent, unitToken, width, height)
    -- Secure unit button template is required for click-target behavior.
    local frame = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate")
    frame.unitToken = unitToken

    frame:SetSize(width, height)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("unit", unitToken)
    frame:SetAttribute("type1", "target")

    frame.Background = Style:CreateBackground(frame, 0.06, 0.06, 0.07, 0.9)
    frame.HealthBar = self:CreateStatusBar(frame)
    frame.PowerBar = self:CreateStatusBar(frame)

    -- Create text on the health bar so it always renders above bar textures.
    frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.NameText:SetDrawLayer("OVERLAY", 7)
    frame.NameText:SetJustifyH("LEFT")

    frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.HealthText:SetDrawLayer("OVERLAY", 7)
    frame.HealthText:SetJustifyH("RIGHT")

    self:ApplyStyle(frame, unitToken)
    return frame
end

-- Apply profile-driven layout, fonts, and visibility options.
function GlobalFrames:ApplyStyle(frame, unitToken)
    local dataHandle = self.addon:GetModule("dataHandle")
    if not dataHandle or not frame then
        return
    end

    local profile = dataHandle:GetProfile()
    local styleConfig = profile and profile.style or nil
    local unitConfig = dataHandle:GetUnitConfig(unitToken)
    local pixelPerfect = Style:IsPixelPerfectEnabled()
    local width = Util:Clamp(tonumber(unitConfig.width) or 220, 100, 600)
    local height = Util:Clamp(tonumber(unitConfig.height) or 44, 18, 160)
    local powerHeight = Util:Clamp(tonumber(unitConfig.powerHeight) or 10, 4, height - 6)
    local configuredFontSize = styleConfig and tonumber(styleConfig.fontSize) or tonumber(unitConfig.fontSize) or 12
    local fontSize = Util:Clamp(configuredFontSize, 8, 26)
    local x = tonumber(unitConfig.x) or 0
    local y = tonumber(unitConfig.y) or 0

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
        powerHeight = Style:Snap(powerHeight)
        x = Style:Snap(x)
        y = Style:Snap(y)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        powerHeight = math.floor(powerHeight + 0.5)
        x = math.floor(x + 0.5)
        y = math.floor(y + 0.5)
    end
    fontSize = math.floor(fontSize + 0.5)

    -- Position and size changes are skipped during combat lockdown.
    if not InCombatLockdown() then
        frame:SetSize(width, height)
        frame:ClearAllPoints()
        frame:SetPoint(
            unitConfig.point or "CENTER",
            UIParent,
            unitConfig.relativePoint or "CENTER",
            x,
            y
        )
    end

    Style:ApplyStatusBarTexture(frame.HealthBar)
    Style:ApplyStatusBarTexture(frame.PowerBar)

    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(6) or 6

    frame.PowerBar:ClearAllPoints()
    frame.PowerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
    frame.PowerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
    frame.PowerBar:SetHeight(powerHeight)

    frame.HealthBar:ClearAllPoints()
    frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
    frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
    frame.HealthBar:SetPoint("BOTTOMLEFT", frame.PowerBar, "TOPLEFT", 0, border)
    frame.HealthBar:SetPoint("BOTTOMRIGHT", frame.PowerBar, "TOPRIGHT", 0, border)

    frame.NameText:ClearAllPoints()
    frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
    frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

    frame.HealthText:ClearAllPoints()
    frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)

    Style:ApplyFont(frame.NameText, fontSize)
    Style:ApplyFont(frame.HealthText, fontSize)

    -- Force fallback font objects if a skin removes per-string fonts.
    if not frame.NameText:GetFont() and GameFontHighlightSmall then
        frame.NameText:SetFontObject(GameFontHighlightSmall)
    end
    if not frame.HealthText:GetFont() and GameFontHighlightSmall then
        frame.HealthText:SetFontObject(GameFontHighlightSmall)
    end

    -- Keep text readable on top of colored bars.
    frame.NameText:SetTextColor(1, 1, 1, 1)
    frame.HealthText:SetTextColor(1, 1, 1, 1)
    frame.NameText:SetShadowColor(0, 0, 0, 1)
    frame.HealthText:SetShadowColor(0, 0, 0, 1)
    frame.NameText:SetShadowOffset(1, -1)
    frame.HealthText:SetShadowOffset(1, -1)

    frame.NameText:SetShown(unitConfig.showNameText ~= false)
    frame.HealthText:SetShown(unitConfig.showHealthText ~= false)
end

addon:RegisterModule("globalFrames", GlobalFrames:New())
