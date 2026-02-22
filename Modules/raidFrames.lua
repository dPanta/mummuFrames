local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util
local L = ns.L

-- Create class holding raid frames behavior.
local RaidFrames = ns.Object:Extend()
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local DISPEL_OVERLAY_ALPHA = 0.2
local MAX_RAID_FRAMES = 40
local MEMBERS_PER_GROUP = 5
local MAX_HELPFUL_AURA_SCAN = 80
local MAX_HARMFUL_AURA_SCAN = 40
local TEST_NAME_PREFIX = "Raid Member "
local DEFAULT_TEST_SIZE = 20
local DEFAULT_DISPEL_TYPES = { "Magic", "Curse", "Poison", "Disease" }
local DUMMY_BUFF_ICONS = {
    "Interface\\Icons\\Spell_Holy_WordFortitude",
    "Interface\\Icons\\Spell_Nature_Regeneration",
    "Interface\\Icons\\Spell_Holy_MagicalSentry",
    "Interface\\Icons\\Ability_Paladin_BlessedMending",
    "Interface\\Icons\\Spell_Holy_SealOfProtection",
}
local DUMMY_DEBUFFS = {
    { icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", debuffType = "Curse" },
    { icon = "Interface\\Icons\\Ability_Creature_Poison_06", debuffType = "Poison" },
    { icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", debuffType = "Disease" },
    { icon = "Interface\\Icons\\Spell_Frost_FrostNova", debuffType = "Magic" },
}
local MEMBER_REFRESH_FULL = {
    vitals = true,
    auras = true,
    healerTrackers = true,
}
local MEMBER_REFRESH_VITALS_ONLY = {
    vitals = true,
}
local MEMBER_REFRESH_AURAS_ONLY = {
    auras = true,
    healerTrackers = true,
}
local MEMBER_REFRESH_AURAS_NO_TRACKERS = {
    auras = true,
}
local GROUP_HEALER_DEFAULTS = {
    hots = { style = "icon", size = 14, color = { r = 0.22, g = 0.87, b = 0.42, a = 0.85 } },
    absorbs = { style = "icon", size = 14, color = { r = 0.32, g = 0.68, b = 1.00, a = 0.85 } },
    externals = { style = "icon", size = 14, color = { r = 1.00, g = 0.76, b = 0.30, a = 0.85 } },
}
local ROLE_SORT_PRIORITY = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
    NONE = 4,
}
local BLIZZARD_RAID_FRAME_NAMES = {
    "CompactRaidFrameContainer",
    "CompactRaidFrameManager",
    "CompactRaidFrameManagerContainer",
    "CompactRaidFrameManagerDisplayFrame",
    "CompactRaidFrameManagerToggleButton",
}

-- Show unit tooltip.
local function showUnitTooltip(frame)
    if not frame then
        return
    end

    local unit = frame.unit or frame.displayedUnit or (frame.GetAttribute and frame:GetAttribute("unit")) or nil
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

-- Return random item from table.
local function getRandomItem(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    local index = math.random(1, #list)
    return list[index]
end

-- Return safe numeric value.
local function addZero(value)
    return value + 0
end
local function computePercent(value, maxValue)
    return (value / maxValue) * 100
end
local function equalsTrue(value)
    return value == true
end
local function iterateAuraUpdateList(list, callback)
    if type(list) ~= "table" or type(callback) ~= "function" then
        return false
    end

    local numericCount = #list
    if numericCount > 0 then
        for i = 1, numericCount do
            if callback(list[i]) then
                return true
            end
        end
        return false
    end

    for _, value in pairs(list) do
        if callback(value) then
            return true
        end
    end
    return false
end

local function getSafeNumericValue(value, fallback)
    local numeric = nil
    if type(value) == "number" then
        local okDirect, direct = pcall(addZero, value)
        if okDirect and type(direct) == "number" then
            numeric = direct
        end
    end

    if numeric == nil then
        local coerced = tonumber(value)
        if type(coerced) == "number" then
            local okCoerced, normalized = pcall(addZero, coerced)
            if okCoerced and type(normalized) == "number" then
                numeric = normalized
            end
        end
    end

    if type(numeric) == "number" then
        return numeric
    end
    return fallback
end

-- Set status bar value safely.
local function setStatusBarValueSafe(statusBar, currentValue, maxValue)
    if not statusBar then
        return
    end

    local okRange = pcall(statusBar.SetMinMaxValues, statusBar, 0, maxValue or 1)
    if not okRange then
        statusBar:SetMinMaxValues(0, 1)
    end

    local okValue = pcall(statusBar.SetValue, statusBar, currentValue or 0)
    if not okValue then
        statusBar:SetValue(0)
    end
end

-- Return debuff types dispellable by current player class.
local function getPlayerDispelTypes()
    local _, classToken = UnitClass("player")
    if classToken == "PRIEST" then
        return { "Magic", "Disease" }
    end
    if classToken == "PALADIN" then
        return { "Poison", "Disease", "Magic" }
    end
    if classToken == "SHAMAN" then
        return { "Curse", "Magic" }
    end
    if classToken == "DRUID" then
        return { "Curse", "Poison", "Magic" }
    end
    if classToken == "MONK" then
        return { "Poison", "Disease", "Magic" }
    end
    if classToken == "MAGE" then
        return { "Curse" }
    end
    if classToken == "EVOKER" then
        return { "Poison" }
    end
    return DEFAULT_DISPEL_TYPES
end

-- Return set of dispellable debuff types.
local function getPlayerDispelTypeSet()
    local types = getPlayerDispelTypes()
    local set = {}
    for i = 1, #types do
        set[types[i]] = true
    end
    return set
end

-- Return aura data by index.
local function getAuraDataByIndex(unitToken, index, filter)
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local okAura, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unitToken, index, filter)
        if okAura and type(aura) == "table" then
            local icon = aura.icon or aura.iconFileID or aura.texture
            if icon then
                return {
                    name = aura.name,
                    icon = icon,
                    count = aura.applications or aura.charges or aura.count,
                    duration = aura.duration,
                    expirationTime = aura.expirationTime,
                    debuffType = aura.dispelName or aura.debuffType,
                    spellId = aura.spellId or aura.spellID,
                    isHelpful = aura.isHelpful,
                    isHarmful = aura.isHarmful,
                }
            end
        end
    end

    if type(UnitAura) == "function" then
        local name, icon, count, debuffType, duration, expirationTime, _, _, _, spellID = UnitAura(unitToken, index, filter)
        if icon then
            return {
                name = name,
                icon = icon,
                count = count,
                duration = duration,
                expirationTime = expirationTime,
                debuffType = debuffType,
                spellId = spellID,
            }
        end
    end

    return nil
end

-- Initialize raid frames state.
function RaidFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    self.unitFrames = nil
    self.partyFrames = nil
    self.container = nil
    self.frames = {}
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self.editModeActive = false
    self.editModeCallbacksRegistered = false
    self._testMemberStateByUnit = nil
    self._helpfulAuraCacheByUnit = {}
end

-- Initialize raid frames module.
function RaidFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Return raid healer config with guaranteed defaults.
function RaidFrames:GetRaidHealerConfig()
    if self.partyFrames and type(self.partyFrames.GetPartyHealerConfig) == "function" then
        local shared = self.partyFrames:GetPartyHealerConfig()
        if shared then
            return shared
        end
    end

    if not self.dataHandle then
        return nil
    end

    local profile = self.dataHandle:GetProfile()
    profile.loveHealers = profile.loveHealers or {}
    local config = profile.loveHealers

    if config.enabled == nil then
        config.enabled = true
    end
    config.groups = config.groups or {}
    config.spells = config.spells or {}

    for groupKey, defaults in pairs(GROUP_HEALER_DEFAULTS) do
        config.groups[groupKey] = config.groups[groupKey] or {}
        local groupConfig = config.groups[groupKey]
        if type(groupConfig.style) ~= "string" or groupConfig.style == "" then
            groupConfig.style = defaults.style
        end
        groupConfig.size = Util:Clamp(tonumber(groupConfig.size) or defaults.size, 6, 48)
        groupConfig.color = groupConfig.color or {}
        groupConfig.color.r = Util:Clamp(tonumber(groupConfig.color.r) or defaults.color.r, 0, 1)
        groupConfig.color.g = Util:Clamp(tonumber(groupConfig.color.g) or defaults.color.g, 0, 1)
        groupConfig.color.b = Util:Clamp(tonumber(groupConfig.color.b) or defaults.color.b, 0, 1)
        groupConfig.color.a = Util:Clamp(tonumber(groupConfig.color.a) or defaults.color.a, 0, 1)
    end

    return config
end

-- Return currently available tracked spells for player spec/talents.
function RaidFrames:GetAvailableHealerSpells()
    if self.partyFrames and type(self.partyFrames.GetAvailableHealerSpells) == "function" then
        local available = self.partyFrames:GetAvailableHealerSpells()
        if type(available) == "table" then
            return available
        end
    end
    return {}
end

-- Return whether spell id is configured as custom healer spell.
function RaidFrames:IsCustomHealerSpell(spellID)
    if self.partyFrames and type(self.partyFrames.IsCustomHealerSpell) == "function" then
        return self.partyFrames:IsCustomHealerSpell(spellID) == true
    end
    return false
end

-- Add custom healer spell by spell id or spell name.
function RaidFrames:AddCustomHealerSpell(rawIdentifier, groupKey)
    if self.partyFrames and type(self.partyFrames.AddCustomHealerSpell) == "function" then
        return self.partyFrames:AddCustomHealerSpell(rawIdentifier, groupKey)
    end
    return nil, "missing_party_module"
end

-- Remove one custom healer spell by spell id.
function RaidFrames:RemoveCustomHealerSpell(spellID)
    if self.partyFrames and type(self.partyFrames.RemoveCustomHealerSpell) == "function" then
        return self.partyFrames:RemoveCustomHealerSpell(spellID)
    end
    return false
end

-- Return whether healer trackers should refresh for this aura update.
function RaidFrames:ShouldRefreshHealerTrackersForAuraUpdate(unitToken, auraUpdateInfo)
    if type(auraUpdateInfo) ~= "table" then
        return true
    end
    if auraUpdateInfo.isFullUpdate == true then
        return true
    end

    local removed = auraUpdateInfo.removedAuraInstanceIDs
    if type(removed) == "table" and next(removed) ~= nil then
        return true
    end

    local function isHelpfulOrUnknown(auraData)
        if type(auraData) ~= "table" then
            return true
        end
        if auraData.isHelpful ~= nil then
            local okHelpful, helpful = pcall(equalsTrue, auraData.isHelpful)
            if okHelpful then
                return helpful
            end
            return true
        end
        if auraData.isHarmful ~= nil then
            local okHarmful, harmful = pcall(equalsTrue, auraData.isHarmful)
            if okHarmful then
                return not harmful
            end
            return true
        end
        return true
    end

    if iterateAuraUpdateList(auraUpdateInfo.addedAuras, isHelpfulOrUnknown) then
        return true
    end

    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
        if iterateAuraUpdateList(auraUpdateInfo.updatedAuraInstanceIDs, function(auraInstanceID)
            local okAura, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, auraInstanceID)
            if not okAura then
                return true
            end
            return isHelpfulOrUnknown(auraData)
        end) then
            return true
        end
    else
        local updated = auraUpdateInfo.updatedAuraInstanceIDs
        if type(updated) == "table" and next(updated) ~= nil then
            return true
        end
    end

    return false
end

-- Invalidate helpful-aura cache for one unit, or all units.
function RaidFrames:InvalidateHelpfulAuraCache(unitToken)
    if type(unitToken) == "string" and unitToken ~= "" then
        if type(self._helpfulAuraCacheByUnit) == "table" then
            self._helpfulAuraCacheByUnit[unitToken] = nil
        end
        return
    end

    self._helpfulAuraCacheByUnit = {}
end

-- Build helpful-aura map by spell id for one unit.
function RaidFrames:BuildHelpfulAuraMapForUnit(unitToken)
    local map = {}
    if type(unitToken) ~= "string" or unitToken == "" then
        return map
    end

    for index = 1, MAX_HELPFUL_AURA_SCAN do
        local auraData = getAuraDataByIndex(unitToken, index, "HELPFUL")
        if type(auraData) ~= "table" then
            break
        end

        local spellID = getSafeNumericValue(auraData.spellId, nil)
        spellID = spellID and math.floor(spellID + 0.5) or nil
        if spellID and spellID > 0 and map[spellID] == nil then
            map[spellID] = {
                spellID = spellID,
                icon = auraData.icon or auraData.iconFileID or auraData.texture,
            }
        end
    end

    return map
end

-- Return cached helpful-aura map for one unit.
function RaidFrames:GetHelpfulAuraMapForUnit(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return {}
    end

    self._helpfulAuraCacheByUnit = self._helpfulAuraCacheByUnit or {}
    local cached = self._helpfulAuraCacheByUnit[unitToken]
    if type(cached) == "table" then
        return cached
    end

    cached = self:BuildHelpfulAuraMapForUnit(unitToken)
    self._helpfulAuraCacheByUnit[unitToken] = cached
    return cached
end

-- Return aura data for a specific spell ID on unit.
function RaidFrames:GetUnitAuraBySpellID(unitToken, spellID)
    if not unitToken or type(spellID) ~= "number" then
        return nil
    end

    local roundedSpellID = math.floor(spellID + 0.5)
    local auraMap = self:GetHelpfulAuraMapForUnit(unitToken)
    local auraInfo = type(auraMap) == "table" and auraMap[roundedSpellID] or nil
    if type(auraInfo) == "table" then
        return auraInfo
    end

    return nil
end

-- Enable raid frames module.
function RaidFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")
    self.unitFrames = self.addon:GetModule("unitFrames")
    self.partyFrames = self.addon:GetModule("partyFrames")
    self:RegisterEvents()
    self:RegisterEditModeCallbacks()
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame.editModeActive == true) and true or false
    if self.editModeActive then
        self:EnsureEditModeSelection()
        if self.container and self.container.EditModeSelection then
            self.container.EditModeSelection:Show()
        end
    end
    self:InvalidateHelpfulAuraCache()
    self:ApplyBlizzardRaidFrameVisibility()
    self:RefreshAll(true)
end

-- Disable raid frames module.
function RaidFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:UnregisterEditModeCallbacks()
    self.editModeActive = false
    self.pendingLayoutRefresh = false
    self.layoutInitialized = false
    self._frameByDisplayedUnit = {}
    self._displayedUnitByGUID = {}
    self._testMemberStateByUnit = nil
    self:InvalidateHelpfulAuraCache()
    self:SetBlizzardRaidFramesHidden(false)
    if self.container then
        self.container:StopMovingOrSizing()
        self.container._editModeMoving = false
        if self.container.EditModeSelection then
            self.container.EditModeSelection:Hide()
        end
        self.container:Hide()
    end
end

-- Create raid frames.
function RaidFrames:CreateRaidFrames()
    if self.container then
        return self.container
    end

    if not self.globalFrames then
        return nil
    end

    local container = CreateFrame("Frame", "mummuFramesRaidContainer", UIParent)
    container:SetFrameStrata("LOW")
    container.unitToken = "raid"
    container:Hide()
    self.container = container

    for i = 1, MAX_RAID_FRAMES do
        local frame = CreateFrame("Button", "mummuFramesRaidFrame" .. i, container, "SecureUnitButtonTemplate")
        frame:SetFrameStrata("LOW")
        frame:SetClampedToScreen(true)
        frame._mummuIsRaidFrame = true
        frame:RegisterForClicks("AnyDown", "AnyUp")
        frame:SetAttribute("unit", "raid1")
        frame:SetAttribute("type1", "target")
        frame:SetAttribute("*type2", "togglemenu")
        frame.unit = "raid1"
        frame.displayedUnit = "raid1"
        if self.globalFrames and type(self.globalFrames.RegisterClickCastFrame) == "function" then
            self.globalFrames:RegisterClickCastFrame(frame)
        end
        frame:SetScript("OnEnter", showUnitTooltip)
        frame:SetScript("OnLeave", hideUnitTooltip)

        frame.Background = Style:CreateBackground(frame, 0.06, 0.06, 0.07, 0.9)
        frame.HealthBar = self.globalFrames:CreateStatusBar(frame)

        frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
        frame.NameText:SetJustifyH("LEFT")
        frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
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
        frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
        frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
        frame.AbsorbOverlayBar:Hide()

        frame.DispelOverlay = frame.HealthBar:CreateTexture(nil, "OVERLAY")
        frame.DispelOverlay:SetAllPoints(frame.HealthBar)
        frame.DispelOverlay:Hide()

        if self.unitFrames and type(self.unitFrames.EnsureAuraContainers) == "function" then
            self.unitFrames:EnsureAuraContainers(frame)
        end

        frame:Hide()
        self.frames[i] = frame
    end

    return self.container
end

-- Return all available Blizzard raid frames.
function RaidFrames:GetBlizzardRaidFrames()
    local frames = {}
    local seen = {}
    for i = 1, #BLIZZARD_RAID_FRAME_NAMES do
        local frame = _G[BLIZZARD_RAID_FRAME_NAMES[i]]
        if frame and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    return frames
end

-- Set Blizzard raid frames hidden or shown.
function RaidFrames:SetBlizzardRaidFramesHidden(shouldHide)
    local frames = self:GetBlizzardRaidFrames()
    for i = 1, #frames do
        local frame = frames[i]
        if not frame._mummuRaidHideInit then
            frame._mummuRaidHideInit = true
            frame._mummuRaidOriginalAlpha = frame:GetAlpha()
            if type(frame.IsMouseEnabled) == "function" then
                frame._mummuRaidOriginalMouseEnabled = frame:IsMouseEnabled()
            end
        end

        if not frame._mummuRaidHideHooked and type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function(shownFrame)
                if shownFrame._mummuRaidHideRequested then
                    shownFrame:SetAlpha(0)
                    if not InCombatLockdown() and type(shownFrame.EnableMouse) == "function" then
                        shownFrame:EnableMouse(false)
                    end
                end
            end)
            frame:HookScript("OnUpdate", function(shownFrame)
                if shownFrame._mummuRaidHideRequested and shownFrame:GetAlpha() > 0 then
                    shownFrame:SetAlpha(0)
                end
            end)
            frame._mummuRaidHideHooked = true
        end

        frame._mummuRaidHideRequested = shouldHide and true or false
        if shouldHide then
            frame:SetAlpha(0)
            if not InCombatLockdown() and type(frame.EnableMouse) == "function" then
                frame:EnableMouse(false)
            end
        else
            frame:SetAlpha(frame._mummuRaidOriginalAlpha or 1)
            if not InCombatLockdown() and type(frame.EnableMouse) == "function" then
                if frame._mummuRaidOriginalMouseEnabled ~= nil then
                    frame:EnableMouse(frame._mummuRaidOriginalMouseEnabled)
                else
                    frame:EnableMouse(true)
                end
            end
        end
    end
end

-- Apply Blizzard raid frame visibility by config.
function RaidFrames:ApplyBlizzardRaidFrameVisibility()
    if not self.dataHandle then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local raidConfig = self.dataHandle:GetUnitConfig("raid")
    local addonEnabled = profile and profile.enabled ~= false
    local shouldHide = addonEnabled and raidConfig and raidConfig.hideBlizzardFrame == true
    self:SetBlizzardRaidFramesHidden(shouldHide)
end

-- Register raid frame events.
function RaidFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_SPECIALIZATION_CHANGED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_TALENT_UPDATE", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_ROLES_ASSIGNED", self.OnWorldEvent)
    ns.EventRouter:Register(self, "UNIT_NAME_UPDATE", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_HEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_MAXHEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_AURA", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_ABSORB_AMOUNT_CHANGED", self.OnUnitEvent)
end

-- Register edit mode callbacks.
function RaidFrames:RegisterEditModeCallbacks()
    if self.editModeCallbacksRegistered then
        return
    end

    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    EventRegistry:RegisterCallback("EditMode.Enter", self.OnEditModeEnter, self)
    EventRegistry:RegisterCallback("EditMode.Exit", self.OnEditModeExit, self)
    self.editModeCallbacksRegistered = true
end

-- Unregister edit mode callbacks.
function RaidFrames:UnregisterEditModeCallbacks()
    if not self.editModeCallbacksRegistered then
        return
    end

    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end

    self.editModeCallbacksRegistered = false
end

-- Ensure edit mode selection for raid container.
function RaidFrames:EnsureEditModeSelection()
    if not self.container or not self.unitFrames then
        return
    end

    if type(self.unitFrames.EnsureEditModeSelection) == "function" then
        self.unitFrames:EnsureEditModeSelection(self.container)
    end

    local selection = self.container.EditModeSelection
    if selection and selection.Label and selection.Label.SetText then
        selection.Label:SetText((L and L.CONFIG_TAB_RAID) or "Raid")
    end
end

-- Handle edit mode enter event.
function RaidFrames:OnEditModeEnter()
    self.editModeActive = true
    self:EnsureEditModeSelection()
    if self.container and self.container.EditModeSelection then
        self.container.EditModeSelection:Show()
    end
    self:RefreshAll(true)
end

-- Handle edit mode exit event.
function RaidFrames:OnEditModeExit()
    self.editModeActive = false
    if self.container then
        self.container:StopMovingOrSizing()
        self.container._editModeMoving = false
        if self.container.EditModeSelection then
            self.container.EditModeSelection:Hide()
        end
    end
    self:RefreshAll(true)
end

-- Handle world/roster/spec events.
function RaidFrames:OnWorldEvent()
    self:InvalidateHelpfulAuraCache()
    self:RefreshAll(true)
end

-- Handle combat ended event.
function RaidFrames:OnCombatEnded()
    if self.pendingLayoutRefresh then
        self.pendingLayoutRefresh = false
        self:RefreshAll(true)
        return
    end

    self:RefreshAll(false)
end

-- Return static dummy aura state for one test member.
function RaidFrames:CreateStaticDummyAuraState()
    local state = {
        buffs = {},
        debuffs = {},
        dispelType = nil,
    }

    local dispelTypes = getPlayerDispelTypes()
    local buffCount = math.random(2, 4)
    for i = 1, buffCount do
        state.buffs[i] = {
            icon = getRandomItem(DUMMY_BUFF_ICONS),
            count = math.random(0, 3),
            duration = 0,
            expirationTime = 0,
            debuffType = nil,
        }
    end

    local debuffCount = math.random(1, 3)
    for i = 1, debuffCount do
        local dispelType = getRandomItem(dispelTypes) or getRandomItem(DEFAULT_DISPEL_TYPES)
        local dummy = getRandomItem(DUMMY_DEBUFFS) or DUMMY_DEBUFFS[1]
        state.debuffs[i] = {
            icon = dummy.icon,
            count = math.random(0, 2),
            duration = 0,
            expirationTime = 0,
            debuffType = dispelType,
        }
        if i == 1 then
            state.dispelType = dispelType
        end
    end

    return state
end

-- Return static test state for one member.
function RaidFrames:CreateStaticTestMemberState(_, index)
    local fallbackName = TEST_NAME_PREFIX .. tostring(index or 1)
    local state = {
        name = fallbackName,
        health = math.random(35, 100),
        maxHealth = 100,
        absorb = math.random(0, 35),
        auras = self:CreateStaticDummyAuraState(),
    }

    return state
end

-- Return static test state for member, creating it if needed.
function RaidFrames:GetOrCreateStaticTestMemberState(unitToken, index)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    self._testMemberStateByUnit = self._testMemberStateByUnit or {}
    local state = self._testMemberStateByUnit[unitToken]
    if state then
        return state
    end

    state = self:CreateStaticTestMemberState(unitToken, index)
    self._testMemberStateByUnit[unitToken] = state
    return state
end

-- Ensure static test states for listed units and drop stale ones.
function RaidFrames:EnsureStaticTestMemberStates(unitsToShow)
    if type(unitsToShow) ~= "table" then
        return
    end

    self._testMemberStateByUnit = self._testMemberStateByUnit or {}
    local seen = {}
    for i = 1, #unitsToShow do
        local entry = unitsToShow[i]
        local unitToken = entry and entry.unitToken
        if type(unitToken) == "string" then
            seen[unitToken] = true
            self:GetOrCreateStaticTestMemberState(unitToken, i)
        end
    end

    for unitToken in pairs(self._testMemberStateByUnit) do
        if not seen[unitToken] then
            self._testMemberStateByUnit[unitToken] = nil
        end
    end
end

-- Return sort key for one role token.
function RaidFrames:GetRoleSortPriority(roleToken)
    local normalized = type(roleToken) == "string" and roleToken or "NONE"
    return ROLE_SORT_PRIORITY[normalized] or ROLE_SORT_PRIORITY.NONE
end

-- Return sorted raid roster entries.
function RaidFrames:BuildSortedRaidEntries(previewMode, raidConfig)
    local entries = {}
    local sortBy = type(raidConfig.sortBy) == "string" and raidConfig.sortBy or "group"
    local sortDirection = (raidConfig.sortDirection == "desc") and "desc" or "asc"

    if previewMode then
        local previewCount = Util:Clamp(tonumber(raidConfig.testSize) or DEFAULT_TEST_SIZE, 1, MAX_RAID_FRAMES)
        for i = 1, previewCount do
            entries[#entries + 1] = {
                unitToken = "raid" .. tostring(i),
                name = TEST_NAME_PREFIX .. tostring(i),
                subgroup = math.floor((i - 1) / MEMBERS_PER_GROUP) + 1,
                role = (i % 5 == 1) and "TANK" or ((i % 3 == 0) and "HEALER" or "DAMAGER"),
                index = i,
            }
        end
    else
        local inRaidHome = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_HOME) or false
        local inRaidInstance = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) or false
        local inRaid = inRaidHome or inRaidInstance
        if not inRaid then
            return entries
        end

        local count = Util:Clamp(tonumber(GetNumGroupMembers and GetNumGroupMembers() or 0) or 0, 0, MAX_RAID_FRAMES)
        for i = 1, count do
            local unitToken = "raid" .. tostring(i)
            if UnitExists(unitToken) then
                local name, _, subgroup, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
                local resolvedName = UnitName(unitToken) or name or (TEST_NAME_PREFIX .. tostring(i))
                local resolvedSubgroup = tonumber(subgroup) or (math.floor((i - 1) / MEMBERS_PER_GROUP) + 1)
                local resolvedRole = UnitGroupRolesAssigned(unitToken)
                if type(resolvedRole) ~= "string" or resolvedRole == "NONE" then
                    resolvedRole = role
                end
                if type(resolvedRole) ~= "string" or resolvedRole == "" then
                    resolvedRole = "NONE"
                end

                entries[#entries + 1] = {
                    unitToken = unitToken,
                    name = resolvedName,
                    subgroup = resolvedSubgroup,
                    role = resolvedRole,
                    index = i,
                }
            end
        end
    end

    local function compareEntries(a, b)
        if sortBy == "name" then
            local aName = string.lower(tostring(a.name or ""))
            local bName = string.lower(tostring(b.name or ""))
            if aName ~= bName then
                return aName < bName
            end
            if a.subgroup ~= b.subgroup then
                return a.subgroup < b.subgroup
            end
            return a.index < b.index
        end

        if sortBy == "role" then
            local aRole = self:GetRoleSortPriority(a.role)
            local bRole = self:GetRoleSortPriority(b.role)
            if aRole ~= bRole then
                return aRole < bRole
            end
            if a.subgroup ~= b.subgroup then
                return a.subgroup < b.subgroup
            end
            return a.index < b.index
        end

        if a.subgroup ~= b.subgroup then
            return a.subgroup < b.subgroup
        end
        return a.index < b.index
    end

    table.sort(entries, function(a, b)
        if sortDirection == "desc" then
            return compareEntries(b, a)
        end
        return compareEntries(a, b)
    end)

    return entries
end

-- Return dispellable debuff type for one unit.
function RaidFrames:GetDispellableDebuffType(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    local dispelTypeSet = getPlayerDispelTypeSet()
    for index = 1, MAX_HARMFUL_AURA_SCAN do
        local auraData = getAuraDataByIndex(unitToken, index, "HARMFUL")
        if type(auraData) ~= "table" then
            break
        end

        local debuffType = auraData.debuffType
        if type(debuffType) == "string" and dispelTypeSet[debuffType] == true then
            return debuffType
        end
    end

    return nil
end

-- Apply style to one raid member frame.
function RaidFrames:ApplyMemberStyle(frame, raidConfig)
    if not frame or not raidConfig then
        return false
    end

    if InCombatLockdown() then
        self.pendingLayoutRefresh = true
        return false
    end

    local width = Util:Clamp(tonumber(raidConfig.width) or 92, 60, 300)
    local height = Util:Clamp(tonumber(raidConfig.height) or 28, 14, 120)
    local fontSize = Util:Clamp(tonumber(raidConfig.fontSize) or 10, 8, 22)
    local pixelPerfect = Style:IsPixelPerfectEnabled()

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
    end

    frame:SetSize(width, height)
    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(4) or 4

    Style:ApplyStatusBarTexture(frame.HealthBar)
    frame.HealthBar:ClearAllPoints()
    frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
    frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
    frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
    frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)

    frame.NameText:ClearAllPoints()
    frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
    frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

    frame.HealthText:ClearAllPoints()
    frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")
    frame.NameText:SetTextColor(1, 1, 1, 1)
    frame.HealthText:SetTextColor(1, 1, 1, 1)
    return true
end

-- Apply dummy aura test state.
function RaidFrames:ApplyDummyAuras(frame, raidConfig, dummyAuraState)
    if not (self.unitFrames and frame and frame.AuraContainers) then
        return nil
    end

    local unitFrames = self.unitFrames
    unitFrames:ApplyAuraLayout(frame, raidConfig)

    local dispelTypes = getPlayerDispelTypes()
    local dispelTypeToShow = nil

    local buffsContainer = frame.AuraContainers.buffs
    if buffsContainer and buffsContainer.enabled ~= false then
        local staticBuffs = dummyAuraState and dummyAuraState.buffs or nil
        local buffCount = 0
        if type(staticBuffs) == "table" then
            buffCount = math.min(buffsContainer.maxIcons or 6, #staticBuffs)
        else
            buffCount = math.min(buffsContainer.maxIcons or 6, math.random(2, 4))
        end
        for i = 1, buffCount do
            local auraData = staticBuffs and staticBuffs[i] or {
                icon = getRandomItem(DUMMY_BUFF_ICONS),
                count = math.random(0, 3),
                duration = 0,
                expirationTime = 0,
                debuffType = nil,
            }
            unitFrames:ApplyAuraToIcon(buffsContainer, "buffs", i, auraData)
        end
        unitFrames:HideUnusedAuraIcons(buffsContainer, buffCount)
        buffsContainer:SetShown(buffCount > 0)
    end

    local debuffsContainer = frame.AuraContainers.debuffs
    if debuffsContainer and debuffsContainer.enabled ~= false then
        local staticDebuffs = dummyAuraState and dummyAuraState.debuffs or nil
        local debuffCount = 0
        if type(staticDebuffs) == "table" then
            debuffCount = math.min(debuffsContainer.maxIcons or 6, #staticDebuffs)
            dispelTypeToShow = dummyAuraState and dummyAuraState.dispelType or nil
        else
            debuffCount = math.min(debuffsContainer.maxIcons or 6, math.random(1, 3))
        end
        for i = 1, debuffCount do
            local auraData = staticDebuffs and staticDebuffs[i] or nil
            if not auraData then
                local dispelType = getRandomItem(dispelTypes) or getRandomItem(DEFAULT_DISPEL_TYPES)
                local dummy = getRandomItem(DUMMY_DEBUFFS) or DUMMY_DEBUFFS[1]
                auraData = {
                    icon = dummy.icon,
                    count = math.random(0, 2),
                    duration = 0,
                    expirationTime = 0,
                    debuffType = dispelType,
                }
            end
            unitFrames:ApplyAuraToIcon(debuffsContainer, "debuffs", i, auraData)
            if i == 1 and not dispelTypeToShow then
                dispelTypeToShow = auraData and auraData.debuffType or nil
            end
        end
        unitFrames:HideUnusedAuraIcons(debuffsContainer, debuffCount)
        debuffsContainer:SetShown(debuffCount > 0)
    end

    return dispelTypeToShow
end

-- Return (and create if needed) healer tracker element for spell.
function RaidFrames:GetHealerTrackerElement(frame, spellID)
    if not frame or type(spellID) ~= "number" then
        return nil
    end

    frame.HealerTrackerElements = frame.HealerTrackerElements or {}
    local key = tostring(spellID)
    if frame.HealerTrackerElements[key] then
        return frame.HealerTrackerElements[key]
    end

    local element = CreateFrame("Frame", nil, frame)
    element:SetFrameStrata("MEDIUM")
    element:SetFrameLevel(frame:GetFrameLevel() + 40)
    element:Hide()

    element.Icon = element:CreateTexture(nil, "ARTWORK")
    element.Icon:SetAllPoints()
    element.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    element.Rect = element:CreateTexture(nil, "ARTWORK")
    element.Rect:SetAllPoints()
    element.Rect:Hide()

    frame.HealerTrackerElements[key] = element
    return element
end

-- Hide all unused healer tracker elements.
function RaidFrames:HideUnusedHealerTrackerElements(frame, usedByKey)
    if not frame or type(frame.HealerTrackerElements) ~= "table" then
        return
    end

    for key, element in pairs(frame.HealerTrackerElements) do
        if not usedByKey[key] and element then
            element:Hide()
        end
    end
end

-- Refresh healer tracked buffs on one raid member frame.
function RaidFrames:RefreshHealerTrackers(frame, unitToken, previewMode, availableSpells)
    if not frame then
        return
    end

    local config = self:GetRaidHealerConfig()
    if not config or config.enabled == false then
        self:HideUnusedHealerTrackerElements(frame, {})
        return
    end

    availableSpells = availableSpells or self:GetAvailableHealerSpells()
    local usedByKey = {}
    local defaultTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
    local auraMap = nil
    if not previewMode then
        auraMap = self:GetHelpfulAuraMapForUnit(unitToken)
    end

    for i = 1, #availableSpells do
        local spellEntry = availableSpells[i]
        local spellID = spellEntry and spellEntry.spellID
        local key = tostring(spellID)
        local spellConfig = config.spells[key] or {}
        if spellConfig.enabled ~= false and type(spellID) == "number" then
            local auraInfo = previewMode and { icon = spellEntry.icon }
                or (auraMap and auraMap[spellID])
                or self:GetUnitAuraBySpellID(unitToken, spellID)
            if auraInfo then
                local groupKey = spellEntry.group or "hots"
                local groupConfig = config.groups[groupKey] or GROUP_HEALER_DEFAULTS[groupKey]
                local size = Util:Clamp(tonumber(spellConfig.size) or tonumber(groupConfig and groupConfig.size) or 14, 6, 48)
                local anchorPoint = (type(spellConfig.anchorPoint) == "string" and spellConfig.anchorPoint) or "CENTER"
                local x = tonumber(spellConfig.x) or 0
                local y = tonumber(spellConfig.y) or 0
                local style = spellConfig.style or "group"
                if style == "group" then
                    style = (groupConfig and groupConfig.style) or "icon"
                end
                if style ~= "rectangle" then
                    style = "icon"
                end

                local colorSource = spellConfig.color or (groupConfig and groupConfig.color) or { r = 1, g = 1, b = 1, a = 1 }
                local colorR = Util:Clamp(tonumber(colorSource.r) or 1, 0, 1)
                local colorG = Util:Clamp(tonumber(colorSource.g) or 1, 0, 1)
                local colorB = Util:Clamp(tonumber(colorSource.b) or 1, 0, 1)
                local colorA = Util:Clamp(tonumber(colorSource.a) or 1, 0, 1)

                if Style:IsPixelPerfectEnabled() then
                    size = Style:Snap(size)
                    x = Style:Snap(x)
                    y = Style:Snap(y)
                else
                    size = math.floor(size + 0.5)
                    x = math.floor(x + 0.5)
                    y = math.floor(y + 0.5)
                end

                local element = self:GetHealerTrackerElement(frame, spellID)
                if element then
                    element:SetSize(size, size)
                    element:ClearAllPoints()
                    element:SetPoint(anchorPoint, frame, anchorPoint, x, y)

                    if style == "rectangle" then
                        element.Icon:Hide()
                        element.Rect:Show()
                        element.Rect:SetColorTexture(colorR, colorG, colorB, colorA)
                    else
                        element.Rect:Hide()
                        element.Icon:Show()
                        element.Icon:SetTexture(auraInfo.icon or spellEntry.icon or defaultTexture)
                    end

                    element:Show()
                    usedByKey[key] = true
                end
            end
        end
    end

    self:HideUnusedHealerTrackerElements(frame, usedByKey)
end

-- Refresh one currently displayed raid unit frame.
function RaidFrames:RefreshDisplayedUnit(unitToken, refreshOptions, auraUpdateInfo)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end
    if not self.dataHandle or not self.container then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local raidConfig = self.dataHandle:GetUnitConfig("raid")
    local testMode = profile and profile.testMode == true
    local previewMode = testMode or self.editModeActive
    if previewMode then
        self:RefreshAll(false)
        return
    end

    local addonEnabled = profile and profile.enabled ~= false
    local inRaidHome = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_HOME) or false
    local inRaidInstance = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) or false
    local inRaid = inRaidHome or inRaidInstance
    if not addonEnabled or raidConfig.enabled == false or not inRaid then
        return
    end

    local displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    if not displayedUnit then
        return
    end

    local frame = self._frameByDisplayedUnit and self._frameByDisplayedUnit[displayedUnit] or nil
    if not frame then
        return
    end

    local availableHealerSpells = self:GetAvailableHealerSpells()
    self:RefreshMember(
        frame,
        frame.displayedUnit or displayedUnit,
        raidConfig,
        false,
        availableHealerSpells,
        false,
        false,
        refreshOptions or MEMBER_REFRESH_FULL,
        auraUpdateInfo
    )
end

-- Resolve a unit token to currently displayed raid unit token.
function RaidFrames:ResolveDisplayedUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end

    if self._frameByDisplayedUnit and self._frameByDisplayedUnit[unitToken] then
        return unitToken
    end

    if type(UnitGUID) == "function" and type(self._displayedUnitByGUID) == "table" then
        local unitGUID = UnitGUID(unitToken)
        if unitGUID and self._displayedUnitByGUID[unitGUID] then
            return self._displayedUnitByGUID[unitGUID]
        end
    end

    return nil
end

-- Handle unit updates.
function RaidFrames:OnUnitEvent(eventName, unitToken, auraUpdateInfo)
    local displayedUnit = self:ResolveDisplayedUnitToken(unitToken)
    if not displayedUnit then
        return
    end

    if eventName == "UNIT_AURA" then
        local refreshHealerTrackers = self:ShouldRefreshHealerTrackersForAuraUpdate(displayedUnit, auraUpdateInfo)
        if refreshHealerTrackers then
            self:InvalidateHelpfulAuraCache(displayedUnit)
            self:RefreshDisplayedUnit(displayedUnit, MEMBER_REFRESH_AURAS_ONLY, auraUpdateInfo)
        else
            self:RefreshDisplayedUnit(displayedUnit, MEMBER_REFRESH_AURAS_NO_TRACKERS, auraUpdateInfo)
        end
        return
    end

    self:RefreshDisplayedUnit(displayedUnit, MEMBER_REFRESH_VITALS_ONLY)
end

-- Update one raid member.
function RaidFrames:RefreshMember(frame, unitToken, raidConfig, previewMode, availableSpells, testMode, forceStyle, refreshOptions, auraUpdateInfo)
    if not frame then
        return
    end

    refreshOptions = refreshOptions or MEMBER_REFRESH_FULL
    local refreshVitals = refreshOptions.vitals == true
    local refreshAuras = refreshOptions.auras == true
    local refreshHealerTrackers = refreshOptions.healerTrackers == true

    local needsStyle = forceStyle == true or frame._mummuStyleApplied ~= true
    if needsStyle then
        local applied = self:ApplyMemberStyle(frame, raidConfig)
        if applied then
            frame._mummuStyleApplied = true
        end
    end

    local exists = UnitExists(unitToken)
    local _, classToken = UnitClass(unitToken)

    if not refreshVitals and not refreshAuras and not refreshHealerTrackers then
        return
    end

    local name = UnitName(unitToken) or unitToken
    local health = 100
    local maxHealth = 100
    local absorb = 0
    local testState = nil

    if refreshVitals and (testMode or previewMode) then
        local index = tonumber(string.match(unitToken, "raid(%d+)")) or 1
        testState = self:GetOrCreateStaticTestMemberState(unitToken, index)
        if testState then
            name = testState.name or name
            health = testState.health or health
            maxHealth = testState.maxHealth or maxHealth
            absorb = testState.absorb or absorb
        end
    elseif refreshVitals and exists then
        name = UnitName(unitToken) or name
        health = UnitHealth(unitToken) or 0
        maxHealth = UnitHealthMax(unitToken) or 1
        absorb = type(UnitGetTotalAbsorbs) == "function" and (UnitGetTotalAbsorbs(unitToken) or 0) or 0
    end

    if refreshVitals then
        maxHealth = getSafeNumericValue(maxHealth, 100) or 100
        if maxHealth <= 0 then
            maxHealth = 100
        end
        health = getSafeNumericValue(health, maxHealth) or maxHealth
        absorb = getSafeNumericValue(absorb, 0) or 0
        health = Util:Clamp(health, 0, maxHealth)

        local healthColor = { r = 0.2, g = 0.78, b = 0.3 }
        if exists and UnitIsPlayer(unitToken) then
            local classColor = classToken and RAID_CLASS_COLORS[classToken]
            if classColor then
                healthColor = { r = classColor.r, g = classColor.g, b = classColor.b }
            end
        end
        frame.HealthBar:SetStatusBarColor(healthColor.r, healthColor.g, healthColor.b, 1)
        setStatusBarValueSafe(frame.HealthBar, health, maxHealth)

        frame.NameText:SetText(name)
        local healthPercent = 0
        local okHealthPercent, computedHealthPercent = pcall(computePercent, health, maxHealth)
        if okHealthPercent and type(computedHealthPercent) == "number" then
            healthPercent = computedHealthPercent
        end
        frame.HealthText:SetText(string.format("%.0f%%", healthPercent))

        if previewMode then
            if absorb > 0 then
                setStatusBarValueSafe(frame.AbsorbOverlayBar, absorb, maxHealth)
                frame.AbsorbOverlayFrame:Show()
                frame.AbsorbOverlayBar:Show()
            else
                frame.AbsorbOverlayBar:Hide()
                frame.AbsorbOverlayFrame:Hide()
            end
        elseif exists then
            setStatusBarValueSafe(frame.AbsorbOverlayBar, absorb, maxHealth)
            frame.AbsorbOverlayFrame:Show()
            frame.AbsorbOverlayBar:Show()
        else
            frame.AbsorbOverlayBar:Hide()
            frame.AbsorbOverlayFrame:Hide()
        end
    end

    local dispelType = nil
    if refreshAuras and self.unitFrames and type(self.unitFrames.EnsureAuraContainers) == "function" then
        self.unitFrames:EnsureAuraContainers(frame)
        if previewMode then
            dispelType = self:ApplyDummyAuras(frame, raidConfig, testState and testState.auras or nil)
        else
            self.unitFrames:RefreshAuras(frame, unitToken, exists, false, raidConfig, auraUpdateInfo)
            dispelType = self:GetDispellableDebuffType(unitToken)
        end
    end

    if refreshAuras and frame.DispelOverlay then
        local color = dispelType and DebuffTypeColor and DebuffTypeColor[dispelType] or nil
        if color then
            frame.DispelOverlay:SetColorTexture(color.r, color.g, color.b, DISPEL_OVERLAY_ALPHA)
            frame.DispelOverlay:Show()
        else
            frame.DispelOverlay:Hide()
        end
    end

    if refreshHealerTrackers then
        self:RefreshHealerTrackers(frame, unitToken, previewMode, availableSpells)
    end
end

-- Refresh raid frames.
function RaidFrames:RefreshAll(forceLayout)
    if not self.dataHandle then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local raidConfig = self.dataHandle:GetUnitConfig("raid")
    local testMode = profile and profile.testMode == true
    local previewMode = testMode or self.editModeActive
    local addonEnabled = profile and profile.enabled ~= false
    local inCombat = InCombatLockdown()
    local shouldApplyLayout = (forceLayout == true) or (self.layoutInitialized ~= true)
    self:ApplyBlizzardRaidFrameVisibility()

    local inRaidHome = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_HOME) or false
    local inRaidInstance = (type(IsInRaid) == "function") and IsInRaid(LE_PARTY_CATEGORY_INSTANCE) or false
    local inRaid = inRaidHome or inRaidInstance
    local shouldShow = previewMode or (addonEnabled and raidConfig.enabled ~= false and inRaid)

    if not shouldShow then
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        self._testMemberStateByUnit = nil
        if self.container then
            if inCombat then
                self.pendingLayoutRefresh = true
            else
                self.container:Hide()
            end
        end
        return
    end

    if not self.container and inCombat then
        self.pendingLayoutRefresh = true
        return
    end

    self:CreateRaidFrames()
    if not self.container then
        return
    end
    if self.editModeActive then
        self:EnsureEditModeSelection()
        if self.container.EditModeSelection then
            self.container.EditModeSelection:Show()
        end
    end

    local entries = self:BuildSortedRaidEntries(previewMode, raidConfig)
    if testMode or previewMode then
        self:EnsureStaticTestMemberStates(entries)
    else
        self._testMemberStateByUnit = nil
    end

    if #entries == 0 then
        self._frameByDisplayedUnit = {}
        self._displayedUnitByGUID = {}
        if inCombat then
            self.pendingLayoutRefresh = true
        else
            self.container:Hide()
        end
        return
    end

    local availableHealerSpells = self:GetAvailableHealerSpells()
    local width = Util:Clamp(tonumber(raidConfig.width) or 92, 60, 300)
    local height = Util:Clamp(tonumber(raidConfig.height) or 28, 14, 120)
    local spacingX = Util:Clamp(tonumber(raidConfig.spacingX) or 5, 0, 80)
    local spacingY = Util:Clamp(tonumber(raidConfig.spacingY) or 6, 0, 80)
    local groupSpacing = Util:Clamp(tonumber(raidConfig.groupSpacing) or 12, 0, 120)
    local x = tonumber(raidConfig.x) or 0
    local y = tonumber(raidConfig.y) or 0
    local groupLayout = (raidConfig.groupLayout == "horizontal") and "horizontal" or "vertical"

    if Style:IsPixelPerfectEnabled() then
        width = Style:Snap(width)
        height = Style:Snap(height)
        spacingX = Style:Snap(spacingX)
        spacingY = Style:Snap(spacingY)
        groupSpacing = Style:Snap(groupSpacing)
        x = Style:Snap(x)
        y = Style:Snap(y)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        spacingX = math.floor(spacingX + 0.5)
        spacingY = math.floor(spacingY + 0.5)
        groupSpacing = math.floor(groupSpacing + 0.5)
        x = math.floor(x + 0.5)
        y = math.floor(y + 0.5)
    end

    local frameCount = #entries
    local groupsCount = math.ceil(frameCount / MEMBERS_PER_GROUP)
    local framesInMainAxis = math.min(MEMBERS_PER_GROUP, frameCount)
    local totalWidth
    local totalHeight

    if groupLayout == "horizontal" then
        totalWidth = (groupsCount * width) + (math.max(0, groupsCount - 1) * groupSpacing)
        totalHeight = (framesInMainAxis * height) + (math.max(0, framesInMainAxis - 1) * spacingY)
    else
        totalWidth = (framesInMainAxis * width) + (math.max(0, framesInMainAxis - 1) * spacingX)
        totalHeight = (groupsCount * height) + (math.max(0, groupsCount - 1) * groupSpacing)
    end

    if shouldApplyLayout and not inCombat then
        self.container:SetSize(totalWidth, totalHeight)
        self.container:ClearAllPoints()
        self.container:SetPoint(
            raidConfig.point or "TOPLEFT",
            UIParent,
            raidConfig.relativePoint or "TOPLEFT",
            x,
            y
        )
    end

    local frameByDisplayedUnit = {}
    local displayedUnitByGUID = {}
    for i = 1, MAX_RAID_FRAMES do
        local frame = self.frames[i]
        local entry = entries[i]
        if frame and entry then
            local unitToken = entry.unitToken
            local displayedUnit = unitToken
            if not inCombat then
                frame:SetAttribute("unit", unitToken)
            else
                displayedUnit = (type(frame.GetAttribute) == "function" and frame:GetAttribute("unit")) or frame.unit or unitToken
            end
            frame.unit = displayedUnit
            frame.displayedUnit = displayedUnit
            frameByDisplayedUnit[displayedUnit] = frame
            if type(UnitGUID) == "function" then
                local displayedUnitGUID = UnitGUID(displayedUnit)
                if displayedUnitGUID then
                    displayedUnitByGUID[displayedUnitGUID] = displayedUnit
                end
            end

            if shouldApplyLayout then
                if not inCombat then
                    local zeroIndex = i - 1
                    local groupIndex = math.floor(zeroIndex / MEMBERS_PER_GROUP)
                    local indexInGroup = zeroIndex % MEMBERS_PER_GROUP
                    local frameX = 0
                    local frameY = 0
                    if groupLayout == "horizontal" then
                        frameX = groupIndex * (width + groupSpacing)
                        frameY = -indexInGroup * (height + spacingY)
                    else
                        frameX = indexInGroup * (width + spacingX)
                        frameY = -groupIndex * (height + groupSpacing)
                    end

                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", self.container, "TOPLEFT", frameX, frameY)
                else
                    self.pendingLayoutRefresh = true
                end
            end

            self:RefreshMember(
                frame,
                displayedUnit,
                raidConfig,
                previewMode,
                availableHealerSpells,
                testMode,
                shouldApplyLayout,
                MEMBER_REFRESH_FULL
            )

            if not inCombat then
                frame:Show()
            else
                self.pendingLayoutRefresh = true
            end
        elseif frame then
            if not inCombat then
                frame:Hide()
            else
                self.pendingLayoutRefresh = true
            end
        end
    end

    self._frameByDisplayedUnit = frameByDisplayedUnit
    self._displayedUnitByGUID = displayedUnitByGUID

    if not inCombat then
        self.container:Show()
        if shouldApplyLayout then
            self.layoutInitialized = true
        end
    else
        self.pendingLayoutRefresh = true
    end
end

addon:RegisterModule("raidFrames", RaidFrames:New())
