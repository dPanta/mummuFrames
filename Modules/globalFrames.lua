local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

local GlobalFrames = ns.Object:Extend()
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local RESTING_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\catzzz.png"
local LEADER_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\crown.png"
local COMBAT_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\swords.png"
local SECONDARY_POWER_MAX_ICONS = 10
-- Cropped UVs to remove large transparent padding from 1024x1024 source PNGs.
local RESTING_ICON_TEXCOORD = { 0.25390625, 0.66796875, 0.138671875, 0.9130859375 } -- 260,684,142,935
local LEADER_ICON_TEXCOORD = { 0.25390625, 0.67578125, 0.138671875, 0.9130859375 } -- 260,692,142,935
local RESTING_ICON_ASPECT = 424 / 793
local LEADER_ICON_ASPECT = 432 / 793

-- Show the default Blizzard unit tooltip for this frame.
local function showUnitTooltip(frame)
    if not frame then
        return
    end

    local unit = frame.unit or frame.displayedUnit or frame.unitToken or (frame.GetAttribute and frame:GetAttribute("unit")) or nil
    if not unit then
        return
    end

    -- Use Blizzard's unit-frame tooltip helper when possible, but fall back safely.
    if type(UnitFrame_OnEnter) == "function" then
        local ok = pcall(UnitFrame_OnEnter, frame)
        if ok then
            return
        end
    end

    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", 0, -2)
    end
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

-- Hide tooltip on mouse leave.
local function hideUnitTooltip(frame)
    if not frame then
        return
    end

    if type(UnitFrame_OnLeave) == "function" then
        UnitFrame_OnLeave(frame)
        return
    end

    GameTooltip:Hide()
end

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
    container:SetFrameStrata("HIGH")
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

-- Create the player-only secondary power icon row.
function GlobalFrames:CreateSecondaryPowerBar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(frame:GetFrameLevel() + 20)
    bar:SetSize(120, 16)
    bar:SetClampedToScreen(true)
    bar:Hide()

    bar.Icons = {}
    for i = 1, SECONDARY_POWER_MAX_ICONS do
        local icon = bar:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()
        bar.Icons[i] = icon
    end

    frame.SecondaryPowerBar = bar
end

-- Create the cast bar widget attached to a unit frame.
function GlobalFrames:CreateCastBar(frame)
    local container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(200, 20)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:Hide()

    -- Class-colored border (1px frame).
    local borderSize = 1
    local borderTop = container:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)
    borderTop:SetColorTexture(1, 1, 1, 1)
    local borderBottom = container:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(borderSize)
    borderBottom:SetColorTexture(1, 1, 1, 1)
    local borderLeft = container:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)
    borderLeft:SetColorTexture(1, 1, 1, 1)
    local borderRight = container:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)
    borderRight:SetColorTexture(1, 1, 1, 1)
    container.BorderTextures = { borderTop, borderBottom, borderLeft, borderRight }

    container.Background = Style:CreateBackground(container, 0.06, 0.06, 0.07, 0.9)

    local inset = borderSize
    local iconSize = 20
    container.Icon = container:CreateTexture(nil, "ARTWORK")
    container.Icon:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -inset)
    container.Icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", inset, inset)
    container.Icon:SetWidth(iconSize)
    container.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local bar = self:CreateStatusBar(container)
    bar:SetPoint("TOPLEFT", container.Icon, "TOPRIGHT", 1, 0)
    bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, inset)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.29, 0.52, 0.90, 1)
    container.Bar = bar

    container.SpellText = bar:CreateFontString(nil, "OVERLAY")
    container.SpellText:SetDrawLayer("OVERLAY", 7)
    container.SpellText:SetJustifyH("LEFT")

    container.TimeText = bar:CreateFontString(nil, "OVERLAY")
    container.TimeText:SetDrawLayer("OVERLAY", 7)
    container.TimeText:SetJustifyH("RIGHT")

    container.parentUnitFrame = frame
    container.unitToken = frame.unitToken
    frame.CastBar = container
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
    frame.unit = unitToken
    frame.displayedUnit = unitToken
    frame:SetScript("OnEnter", showUnitTooltip)
    frame:SetScript("OnLeave", hideUnitTooltip)

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

    if unitToken == "player" or unitToken == "target" then
        self:CreateCastBar(frame)
    end

    if unitToken == "player" then
        self:CreatePlayerStatusIcons(frame)
        self:CreateSecondaryPowerBar(frame)
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
    frame.HealthBar:ClearAllPoints()
    frame.PowerBar:SetHeight(powerHeight)

    if unitConfig.powerOnTop then
        frame.PowerBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.PowerBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)

        frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
        frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
        frame.HealthBar:SetPoint("TOPLEFT", frame.PowerBar, "BOTTOMLEFT", 0, -border)
        frame.HealthBar:SetPoint("TOPRIGHT", frame.PowerBar, "BOTTOMRIGHT", 0, -border)
    else
        frame.PowerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
        frame.PowerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)

        frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
        frame.HealthBar:SetPoint("BOTTOMLEFT", frame.PowerBar, "TOPLEFT", 0, border)
        frame.HealthBar:SetPoint("BOTTOMRIGHT", frame.PowerBar, "TOPRIGHT", 0, border)
    end

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

    if frame.SecondaryPowerBar then
        local secondaryConfig = unitConfig.secondaryPower or {}
        local spEnabled = unitToken == "player" and secondaryConfig.enabled ~= false
        local spDetached = secondaryConfig.detached == true
        local defaultSpSize = math.floor((fontSize * 1.35) + 0.5)
        local spHeight = Util:Clamp(math.floor((tonumber(secondaryConfig.size) or defaultSpSize) + 0.5), 8, 40)
        local spWidth = Util:Clamp(math.max(math.floor((width * 0.75) + 0.5), spHeight * 8), 80, 300)

        frame.SecondaryPowerBar:ClearAllPoints()
        frame.SecondaryPowerBar:SetSize(spWidth, spHeight)

        if spDetached then
            local spX = tonumber(secondaryConfig.x) or 0
            local spY = tonumber(secondaryConfig.y) or 0
            if pixelPerfect then
                spX = Style:Snap(spX)
                spY = Style:Snap(spY)
            else
                spX = math.floor(spX + 0.5)
                spY = math.floor(spY + 0.5)
            end

            if not InCombatLockdown() then
                frame.SecondaryPowerBar:SetPoint("CENTER", UIParent, "CENTER", spX, spY)
            end
        else
            local spOffsetY = pixelPerfect and Style:Snap(8) or 8
            frame.SecondaryPowerBar:SetPoint("BOTTOM", frame, "TOP", 0, spOffsetY)
        end

        frame.SecondaryPowerBar._enabled = spEnabled
        frame.SecondaryPowerBar._detached = spDetached
    end

    -- Cast bar layout for player and target.
    if frame.CastBar then
        local castbarConfig = unitConfig.castbar or {}
        local cbEnabled = castbarConfig.enabled ~= false
        local cbDetached = castbarConfig.detached == true
        local cbWidth = Util:Clamp(tonumber(castbarConfig.width) or width, 50, 600)
        local cbHeight = Util:Clamp(tonumber(castbarConfig.height) or 20, 8, 40)

        if pixelPerfect then
            cbWidth = Style:Snap(cbWidth)
            cbHeight = Style:Snap(cbHeight)
        else
            cbWidth = math.floor(cbWidth + 0.5)
            cbHeight = math.floor(cbHeight + 0.5)
        end

        frame.CastBar:ClearAllPoints()

        if cbDetached then
            local cbX = tonumber(castbarConfig.x) or 0
            local cbY = tonumber(castbarConfig.y) or 0
            if pixelPerfect then
                cbX = Style:Snap(cbX)
                cbY = Style:Snap(cbY)
            else
                cbX = math.floor(cbX + 0.5)
                cbY = math.floor(cbY + 0.5)
            end
            frame.CastBar:SetSize(cbWidth, cbHeight)
            if not InCombatLockdown() then
                frame.CastBar:SetPoint("CENTER", UIParent, "CENTER", cbX, cbY)
            end
        else
            frame.CastBar:SetSize(width, cbHeight)
            frame.CastBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -border)
            frame.CastBar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -border)
        end

        -- Dark gray border.
        local cbBorderInset = 1
        if frame.CastBar.BorderTextures then
            for _, tex in ipairs(frame.CastBar.BorderTextures) do
                tex:SetColorTexture(0.2, 0.2, 0.2, 1)
            end
        end

        -- Icon visibility.
        local cbShowIcon = castbarConfig.showIcon ~= false
        frame.CastBar.Icon:SetShown(cbShowIcon)
        local innerHeight = cbHeight - cbBorderInset * 2
        frame.CastBar.Icon:SetWidth(cbShowIcon and math.max(1, innerHeight) or 0)

        -- Re-anchor bar based on icon visibility.
        frame.CastBar.Bar:ClearAllPoints()
        if cbShowIcon then
            frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar.Icon, "TOPRIGHT", 1, 0)
        else
            frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar, "TOPLEFT", cbBorderInset, -cbBorderInset)
        end
        frame.CastBar.Bar:SetPoint("BOTTOMRIGHT", frame.CastBar, "BOTTOMRIGHT", -cbBorderInset, cbBorderInset)

        -- Update bar texture and fonts.
        Style:ApplyStatusBarTexture(frame.CastBar.Bar)

        local cbTextInset = pixelPerfect and Style:Snap(4) or 4
        local cbFontSize = Util:Clamp(math.floor(cbHeight * 0.55 + 0.5), 8, 20)

        frame.CastBar.SpellText:ClearAllPoints()
        frame.CastBar.SpellText:SetPoint("LEFT", frame.CastBar.Bar, "LEFT", cbTextInset, 0)
        frame.CastBar.SpellText:SetPoint("RIGHT", frame.CastBar.TimeText, "LEFT", -cbTextInset, 0)

        frame.CastBar.TimeText:ClearAllPoints()
        frame.CastBar.TimeText:SetPoint("RIGHT", frame.CastBar.Bar, "RIGHT", -cbTextInset, 0)

        Style:ApplyFont(frame.CastBar.SpellText, cbFontSize, "OUTLINE")
        Style:ApplyFont(frame.CastBar.TimeText, cbFontSize, "OUTLINE")
        frame.CastBar.SpellText:SetTextColor(1, 1, 1, 1)
        frame.CastBar.TimeText:SetTextColor(1, 1, 1, 1)
        frame.CastBar.SpellText:SetShadowColor(0, 0, 0, 0)
        frame.CastBar.TimeText:SetShadowColor(0, 0, 0, 0)
        frame.CastBar.SpellText:SetShadowOffset(0, 0)
        frame.CastBar.TimeText:SetShadowOffset(0, 0)

        frame.CastBar._enabled = cbEnabled
        frame.CastBar._detached = cbDetached
    end
end

addon:RegisterModule("globalFrames", GlobalFrames:New())
