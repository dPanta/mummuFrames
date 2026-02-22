local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

-- Create class holding global frames behavior.
local GlobalFrames = ns.Object:Extend()
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local RESTING_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\catzzz.png"
local LEADER_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\crown.png"
local COMBAT_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\swords.png"
local SECONDARY_POWER_MAX_ICONS = 10
local TERTIARY_POWER_MAX_STACK_OVERLAYS = 10
local TERTIARY_POWER_HEIGHT_BONUS = 5
local RESTING_ICON_TEXCOORD = { 0.25390625, 0.66796875, 0.138671875, 0.9130859375 } -- 260,684,142,935
local LEADER_ICON_TEXCOORD = { 0.25390625, 0.67578125, 0.138671875, 0.9130859375 } -- 260,692,142,935
local RESTING_ICON_ASPECT = 424 / 793
local LEADER_ICON_ASPECT = 432 / 793

-- Show unit tooltip.
local function showUnitTooltip(frame)
    if not frame then
        return
    end

    local unit = frame.unit or frame.displayedUnit or frame.unitToken or (frame.GetAttribute and frame:GetAttribute("unit")) or nil
    if not unit then
        return
    end

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

-- Hide unit tooltip.
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

-- Initialize global frames state.
function GlobalFrames:Constructor()
    self.addon = nil
end

-- Initialize global frames module.
function GlobalFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Create status bar. Coffee remains optional.
function GlobalFrames:CreateStatusBar(parent)
    -- Create statusbar for bar.
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    Style:ApplyStatusBarTexture(bar)

    -- Create texture for bg.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    bar.Background = bg

    return bar
end

-- Create player status icons.
function GlobalFrames:CreatePlayerStatusIcons(frame)
    -- Create frame for container.
    local container = CreateFrame("Frame", nil, frame)
    container:SetFrameStrata("HIGH")
    container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 2)
    container:SetSize(52, 14)
    container:Hide()

    -- Create frame for resting.
    local resting = CreateFrame("Frame", nil, container)
    resting:SetSize(14, 14)
    -- Create texture layer.
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

    -- Create frame for leader.
    local leader = CreateFrame("Frame", nil, container)
    leader:SetSize(14, 14)
    -- Create texture layer.
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

    -- Create frame for combat.
    local combat = CreateFrame("Frame", nil, container)
    combat:SetSize(14, 14)
    -- Create texture layer.
    combat.Icon = combat:CreateTexture(nil, "ARTWORK")
    combat.Icon:SetAllPoints()
    combat.Icon:SetTexture(COMBAT_ICON_TEXTURE)
    combat:Hide()

    frame.StatusIconContainer = container
    -- Create table holding status icons.
    frame.StatusIcons = {
        Resting = resting,
        Leader = leader,
        Combat = combat,
    }
end

-- Create secondary power bar.
function GlobalFrames:CreateSecondaryPowerBar(frame)
    -- Create frame for bar.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(frame:GetFrameLevel() + 20)
    bar:SetSize(120, 16)
    bar:SetClampedToScreen(true)
    bar:Hide()

    -- Create table holding icons.
    bar.Icons = {}
    for i = 1, SECONDARY_POWER_MAX_ICONS do
        -- Create texture for icon.
        local icon = bar:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()
        bar.Icons[i] = icon
    end

    frame.SecondaryPowerBar = bar
end

-- Create tertiary power bar.
function GlobalFrames:CreateTertiaryPowerBar(frame)
    -- Create frame for container.
    local container = CreateFrame("Frame", nil, frame)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(frame:GetFrameLevel() + 19)
    container:SetSize(120, 13)
    container:SetClampedToScreen(true)
    container:Hide()

    local borderSize = 1
    -- Create texture for border top.
    local borderTop = container:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)
    borderTop:SetColorTexture(0.2, 0.2, 0.2, 1)
    -- Create texture for border bottom.
    local borderBottom = container:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(borderSize)
    borderBottom:SetColorTexture(0.2, 0.2, 0.2, 1)
    -- Create texture for border left. Bug parade continues.
    local borderLeft = container:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)
    borderLeft:SetColorTexture(0.2, 0.2, 0.2, 1)
    -- Create texture for border right.
    local borderRight = container:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)
    borderRight:SetColorTexture(0.2, 0.2, 0.2, 1)

    local bar = self:CreateStatusBar(container)
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -borderSize, borderSize)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.32, 0.68, 0.29, 0.95)

    -- Create statusbar for overlay bar.
    local overlayBar = CreateFrame("StatusBar", nil, container)
    overlayBar:SetAllPoints(bar)
    overlayBar:SetFrameStrata(container:GetFrameStrata())
    overlayBar:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlayBar:SetMinMaxValues(0, 1)
    overlayBar:SetValue(0)
    overlayBar:SetStatusBarColor(0.95, 0.85, 0.36, 0.55)
    Style:ApplyStatusBarTexture(overlayBar)

    -- Create font string for value text.
    local valueText = bar:CreateFontString(nil, "OVERLAY", nil, 7)
    valueText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    valueText:SetJustifyH("RIGHT")
    valueText:SetDrawLayer("OVERLAY", 7)

    -- Create texture for right glow.
    local rightGlow = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    rightGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    rightGlow:SetBlendMode("ADD")
    rightGlow:SetVertexColor(0.70, 0.88, 1.00, 0.45)
    rightGlow:SetPoint("CENTER", bar, "RIGHT", 0, 0)
    rightGlow:SetSize(24, 28)
    rightGlow:Hide()

    container.Bar = bar
    container.OverlayBar = overlayBar
    container.ValueText = valueText
    container.RightGlow = rightGlow
    -- Create table holding stack overlays.
    container.StackOverlays = {}
    container.StackRightGlows = {}
    for i = 1, TERTIARY_POWER_MAX_STACK_OVERLAYS do
        local overlaySubLevel = -9 + i -- Keeps stack overlays inside valid sublevel range [-8, 7].
        -- Create texture for overlay.
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, overlaySubLevel)
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        overlay:SetWidth(0)
        overlay:Hide()
        container.StackOverlays[i] = overlay

        -- Create texture for stack right-edge glow.
        local glowSubLevel = overlaySubLevel + 1
        local stackGlow = bar:CreateTexture(nil, "OVERLAY", nil, glowSubLevel)
        stackGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        stackGlow:SetBlendMode("ADD")
        stackGlow:SetVertexColor(0.74, 0.91, 1.00, 0.42)
        stackGlow:SetPoint("CENTER", bar, "RIGHT", 0, 0)
        stackGlow:SetSize(24, 30)
        stackGlow:Hide()
        container.StackRightGlows[i] = stackGlow
    end

    frame.TertiaryPowerBar = container
end

-- Create cast bar.
function GlobalFrames:CreateCastBar(frame)
    -- Create frame for container.
    local container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(200, 20)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:Hide()

    local borderSize = 1
    -- Create texture for border top.
    local borderTop = container:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)
    borderTop:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border bottom.
    local borderBottom = container:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(borderSize)
    borderBottom:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border left.
    local borderLeft = container:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)
    borderLeft:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border right.
    local borderRight = container:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)
    borderRight:SetColorTexture(1, 1, 1, 1)
    container.BorderTextures = { borderTop, borderBottom, borderLeft, borderRight }

    container.Background = Style:CreateBackground(container, 0.06, 0.06, 0.07, 0.9)

    local inset = borderSize
    local iconSize = 20
    -- Create texture layer.
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

    -- Create text font string.
    container.SpellText = bar:CreateFontString(nil, "OVERLAY")
    container.SpellText:SetDrawLayer("OVERLAY", 7)
    container.SpellText:SetJustifyH("LEFT")

    -- Create text font string.
    container.TimeText = bar:CreateFontString(nil, "OVERLAY")
    container.TimeText:SetDrawLayer("OVERLAY", 7)
    container.TimeText:SetJustifyH("RIGHT")

    container.parentUnitFrame = frame
    container.unitToken = frame.unitToken
    frame.CastBar = container
end

-- Create unit frame base.
function GlobalFrames:CreateUnitFrameBase(name, parent, unitToken, width, height)
    -- Create button for frame.
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

    -- Create text font string.
    frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.NameText:SetDrawLayer("OVERLAY", 7)
    frame.NameText:SetJustifyH("LEFT")

    -- Create text font string.
    frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.HealthText:SetDrawLayer("OVERLAY", 7)
    frame.HealthText:SetJustifyH("RIGHT")

    -- Create frame widget. Nothing exploded yet.
    frame.AbsorbOverlayFrame = CreateFrame("Frame", nil, frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
    frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
    frame.AbsorbOverlayFrame:Hide()

    -- Create frame widget.
    frame.AbsorbOverlayBar = CreateFrame("StatusBar", nil, frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetAllPoints(frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
    frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(0)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    frame.AbsorbOverlayBar:Hide()

    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        self:CreateCastBar(frame)
    end

    if unitToken == "player" then
        self:CreatePlayerStatusIcons(frame)
        self:CreateSecondaryPowerBar(frame)
        self:CreateTertiaryPowerBar(frame)
    end

    self:ApplyStyle(frame, unitToken)
    return frame
end

-- Apply style settings to unit frame.
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
    local primaryPowerConfig = unitConfig.primaryPower or {}
    local primaryPowerDetached = unitToken == "player" and primaryPowerConfig.detached == true
    local defaultPrimaryWidth = math.floor((width - (border * 2)) + 0.5)
    local primaryWidth = Util:Clamp(tonumber(primaryPowerConfig.width) or defaultPrimaryWidth, 80, 600)

    if pixelPerfect then
        primaryWidth = Style:Snap(primaryWidth)
    else
        primaryWidth = math.floor(primaryWidth + 0.5)
    end

    frame.PowerBar:ClearAllPoints()
    frame.HealthBar:ClearAllPoints()
    if primaryPowerDetached then
        local ppX = tonumber(primaryPowerConfig.x) or 0
        local ppY = tonumber(primaryPowerConfig.y) or 0
        if pixelPerfect then
            ppX = Style:Snap(ppX)
            ppY = Style:Snap(ppY)
        else
            ppX = math.floor(ppX + 0.5)
            ppY = math.floor(ppY + 0.5)
        end

        frame.PowerBar:SetSize(primaryWidth, powerHeight)
        frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
        frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
        frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)

        if not InCombatLockdown() then
            frame.PowerBar:SetPoint("CENTER", UIParent, "CENTER", ppX, ppY)
        end
    else
        local healthOffset = powerHeight + (border * 2)
        frame.PowerBar:SetSize(primaryWidth, powerHeight)

        if unitConfig.powerOnTop then
            frame.PowerBar:SetPoint("TOP", frame, "TOP", 0, -border)

            frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -healthOffset)
            frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -healthOffset)
            frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
            frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
        else
            frame.PowerBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, border)

            frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
            frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
            frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, healthOffset)
            frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, healthOffset)
        end
    end
    frame.PowerBar._detached = primaryPowerDetached
    frame.PowerBar._enabled = unitToken == "player"

    frame.NameText:ClearAllPoints()
    frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
    frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

    frame.HealthText:ClearAllPoints()
    frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")

    if not frame.NameText:GetFont() and GameFontHighlightSmall then
        frame.NameText:SetFontObject(GameFontHighlightSmall)
    end
    if not frame.HealthText:GetFont() and GameFontHighlightSmall then
        frame.HealthText:SetFontObject(GameFontHighlightSmall)
    end

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
        local defaultSpWidth = Util:Clamp(math.max(math.floor((width * 0.75) + 0.5), spHeight * 8), 80, 300)
        local spWidth = Util:Clamp(tonumber(secondaryConfig.width) or defaultSpWidth, 80, 600)

        if pixelPerfect then
            spHeight = Style:Snap(spHeight)
            spWidth = Style:Snap(spWidth)
        else
            spHeight = math.floor(spHeight + 0.5)
            spWidth = math.floor(spWidth + 0.5)
        end

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

    if frame.TertiaryPowerBar then
        local tertiaryConfig = unitConfig.tertiaryPower or {}
        local tpEnabled = unitToken == "player" and tertiaryConfig.enabled ~= false
        local tpDetached = tertiaryConfig.detached == true
        local defaultTpHeight = math.floor((fontSize * 0.68) + 0.5)
        local configuredTpHeight = tonumber(tertiaryConfig.height) or defaultTpHeight
        local tpHeight = Util:Clamp(math.floor(configuredTpHeight + TERTIARY_POWER_HEIGHT_BONUS + 0.5), 6, 32)
        local defaultTpWidth = Util:Clamp(math.floor((width - (border * 2)) + 0.5), 80, 520)
        local tpWidth = Util:Clamp(tonumber(tertiaryConfig.width) or defaultTpWidth, 80, 600)

        if pixelPerfect then
            tpHeight = Style:Snap(tpHeight)
            tpWidth = Style:Snap(tpWidth)
        else
            tpHeight = math.floor(tpHeight + 0.5)
            tpWidth = math.floor(tpWidth + 0.5)
        end

        Style:ApplyStatusBarTexture(frame.TertiaryPowerBar.Bar)
        Style:ApplyStatusBarTexture(frame.TertiaryPowerBar.OverlayBar)
        Style:ApplyFont(frame.TertiaryPowerBar.ValueText, 24, "OUTLINE")
        frame.TertiaryPowerBar.ValueText:SetTextColor(1, 1, 1, 1)
        frame.TertiaryPowerBar.ValueText:SetShadowColor(0, 0, 0, 0)
        frame.TertiaryPowerBar.ValueText:SetShadowOffset(0, 0)

        frame.TertiaryPowerBar:ClearAllPoints()
        if tpDetached then
            local tpX = tonumber(tertiaryConfig.x) or 0
            local tpY = tonumber(tertiaryConfig.y) or 0
            if pixelPerfect then
                tpX = Style:Snap(tpX)
                tpY = Style:Snap(tpY)
            else
                tpX = math.floor(tpX + 0.5)
                tpY = math.floor(tpY + 0.5)
            end

            frame.TertiaryPowerBar:SetSize(tpWidth, tpHeight)
            if not InCombatLockdown() then
                frame.TertiaryPowerBar:SetPoint("CENTER", UIParent, "CENTER", tpX, tpY)
            end
        else
            frame.TertiaryPowerBar:SetSize(tpWidth, tpHeight)
            frame.TertiaryPowerBar:SetPoint("TOP", frame, "TOP", 0, -border)
        end

        frame.TertiaryPowerBar._enabled = tpEnabled
        frame.TertiaryPowerBar._detached = tpDetached
    end

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

        local cbBorderInset = 1
        if frame.CastBar.BorderTextures then
            for _, tex in ipairs(frame.CastBar.BorderTextures) do
                tex:SetColorTexture(0.2, 0.2, 0.2, 1)
            end
        end

        local cbShowIcon = castbarConfig.showIcon ~= false
        frame.CastBar.Icon:SetShown(cbShowIcon)
        local innerHeight = cbHeight - cbBorderInset * 2
        frame.CastBar.Icon:SetWidth(cbShowIcon and math.max(1, innerHeight) or 0)

        frame.CastBar.Bar:ClearAllPoints()
        if cbShowIcon then
            frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar.Icon, "TOPRIGHT", 1, 0)
        else
            frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar, "TOPLEFT", cbBorderInset, -cbBorderInset)
        end
        frame.CastBar.Bar:SetPoint("BOTTOMRIGHT", frame.CastBar, "BOTTOMRIGHT", -cbBorderInset, cbBorderInset)

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
