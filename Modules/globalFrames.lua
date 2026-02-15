local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

local GlobalFrames = ns.Object:Extend()
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local RESTING_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\catzzz.png"
local LEADER_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\crown.png"
local COMBAT_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\swords.png"
-- Cropped UVs to remove large transparent padding from 1024x1024 source PNGs.
local RESTING_ICON_TEXCOORD = { 0.25390625, 0.66796875, 0.138671875, 0.9130859375 } -- 260,684,142,935
local LEADER_ICON_TEXCOORD = { 0.25390625, 0.67578125, 0.138671875, 0.9130859375 } -- 260,692,142,935
local RESTING_ICON_ASPECT = 424 / 793
local LEADER_ICON_ASPECT = 432 / 793

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

-- Create small player-only status badges shown above the frame.
function GlobalFrames:CreatePlayerStatusIcons(frame)
    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 2)
    container:SetSize(52, 14)
    container:Hide()

    local resting = CreateFrame("Frame", nil, container)
    resting:SetSize(14, 14)
    resting.Icon = resting:CreateTexture(nil, "ARTWORK")
    resting.Icon:SetAllPoints()
    resting.Icon:SetTexture(RESTING_ICON_TEXTURE)
    resting.Icon:SetTexCoord(
        RESTING_ICON_TEXCOORD[1],
        RESTING_ICON_TEXCOORD[2],
        RESTING_ICON_TEXCOORD[3],
        RESTING_ICON_TEXCOORD[4]
    )
    resting:Hide()

    local leader = CreateFrame("Frame", nil, container)
    leader:SetSize(14, 14)
    leader.Icon = leader:CreateTexture(nil, "ARTWORK")
    leader.Icon:SetAllPoints()
    leader.Icon:SetTexture(LEADER_ICON_TEXTURE)
    leader.Icon:SetTexCoord(
        LEADER_ICON_TEXCOORD[1],
        LEADER_ICON_TEXCOORD[2],
        LEADER_ICON_TEXCOORD[3],
        LEADER_ICON_TEXCOORD[4]
    )
    leader:Hide()

    local combat = CreateFrame("Frame", nil, container)
    combat:SetSize(14, 14)
    combat.Icon = combat:CreateTexture(nil, "ARTWORK")
    combat.Icon:SetAllPoints()
    combat.Icon:SetTexture(COMBAT_ICON_TEXTURE)
    combat:Hide()

    frame.StatusIconContainer = container
    frame.StatusIcons = {
        Resting = resting,
        Leader = leader,
        Combat = combat,
    }
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
    frame:SetAttribute("*type2", "togglemenu")

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

    frame.AbsorbOverlayFrame = CreateFrame("Frame", nil, frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
    frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
    frame.AbsorbOverlayFrame:Hide()

    frame.AbsorbOverlayBar = CreateFrame("StatusBar", nil, frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetAllPoints(frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
    frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(0)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    frame.AbsorbOverlayBar:Hide()

    if unitToken == "player" then
        self:CreatePlayerStatusIcons(frame)
    end

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
    if frame.AbsorbOverlayBar and frame.AbsorbOverlayFrame then
        frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
        frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
        frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
        frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
        frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
        frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    end

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

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")

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
    frame.NameText:SetShadowColor(0, 0, 0, 0)
    frame.HealthText:SetShadowColor(0, 0, 0, 0)
    frame.NameText:SetShadowOffset(0, 0)
    frame.HealthText:SetShadowOffset(0, 0)

    frame.NameText:SetShown(true)
    frame.HealthText:SetShown(unitConfig.showHealthText ~= false)

    if frame.StatusIcons and frame.StatusIconContainer then
        local iconSize = Util:Clamp((fontSize + 1) * 5, 40, 96)
        local combatIconSize = math.max(1, math.floor((iconSize * 0.75) + 0.5))
        local badgeSpacing = pixelPerfect and Style:Snap(4) or 4
        local restingWidth = math.floor((iconSize * RESTING_ICON_ASPECT) + 0.5)
        local leaderHeight = math.max(1, math.floor((iconSize / 3) + 0.5))
        local leaderWidth = math.max(1, math.floor((leaderHeight * LEADER_ICON_ASPECT) + 0.5))

        frame.StatusIconContainer:ClearAllPoints()
        -- Container center matches the unit frame top-left corner.
        frame.StatusIconContainer:SetPoint("CENTER", frame, "TOPLEFT", 0, 0)
        frame.StatusIconContainer:SetSize(restingWidth + leaderWidth + badgeSpacing, iconSize)
        frame.StatusIconSpacing = badgeSpacing

        frame.StatusIcons.Resting:SetSize(restingWidth, iconSize)
        frame.StatusIcons.Resting.Icon:SetAllPoints()
        frame.StatusIcons.Resting.Icon:SetTexture(RESTING_ICON_TEXTURE)
        frame.StatusIcons.Resting.Icon:SetTexCoord(
            RESTING_ICON_TEXCOORD[1],
            RESTING_ICON_TEXCOORD[2],
            RESTING_ICON_TEXCOORD[3],
            RESTING_ICON_TEXCOORD[4]
        )

        frame.StatusIcons.Leader:SetSize(leaderWidth, leaderHeight)
        frame.StatusIcons.Leader.Icon:SetAllPoints()
        frame.StatusIcons.Leader.Icon:SetTexture(LEADER_ICON_TEXTURE)
        frame.StatusIcons.Leader.Icon:SetTexCoord(
            LEADER_ICON_TEXCOORD[1],
            LEADER_ICON_TEXCOORD[2],
            LEADER_ICON_TEXCOORD[3],
            LEADER_ICON_TEXCOORD[4]
        )

        frame.StatusIcons.Combat:SetSize(combatIconSize, combatIconSize)
        frame.StatusIcons.Combat.Icon:SetAllPoints()
        frame.StatusIcons.Combat.Icon:SetTexture(COMBAT_ICON_TEXTURE)
    end
end

addon:RegisterModule("globalFrames", GlobalFrames:New())
