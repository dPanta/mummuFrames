local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Style = ns.Style
local Util = ns.Util

local Configuration = ns.Object:Extend()

local UNIT_TAB_ORDER = {
    "player",
    "pet",
    "target",
    "targettarget",
    "focus",
    "focustarget",
}

local UNIT_TAB_LABELS = {
    player = L.CONFIG_TAB_PLAYER or "Player",
    pet = L.CONFIG_TAB_PET or "Pet",
    target = L.CONFIG_TAB_TARGET or "Target",
    targettarget = L.CONFIG_TAB_TARGETTARGET or "TargetTarget",
    focus = L.CONFIG_TAB_FOCUS or "Focus",
    focustarget = L.CONFIG_TAB_FOCUSTARGET or "FocusTarget",
}

local function getFontOptions()
    if Style and type(Style.GetAvailableFonts) == "function" then
        return Style:GetAvailableFonts()
    end
    return {}
end

local function getFontLabelByPath(fontPath)
    local options = getFontOptions()
    for i = 1, #options do
        if options[i].path == fontPath then
            return options[i].label
        end
    end
    return fontPath or "Unknown"
end

local function roundToStep(value, step)
    local numeric = tonumber(value) or 0
    local numericStep = tonumber(step) or 1
    if numericStep <= 0 then
        return numeric
    end
    return math.floor((numeric / numericStep) + 0.5) * numericStep
end

local function normalizeNumericValue(value, minValue, maxValue, step)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = Util:Clamp(numeric, minValue, maxValue)
    numeric = roundToStep(numeric, step)
    numeric = Util:Clamp(numeric, minValue, maxValue)
    return numeric
end

local function formatNumericForDisplay(value)
    local numeric = tonumber(value) or 0
    if math.abs(numeric - math.floor(numeric)) < 0.00001 then
        return tostring(math.floor(numeric + 0.5))
    end
    return string.format("%.2f", numeric)
end

-- Ensure a FontString has a usable font before writing text.
local function ensureFontStringFont(fontString, size, flags, fallbackObject)
    if not fontString then
        return false
    end

    local fontPath = fontString:GetFont()
    if not fontPath then
        Style:ApplyFont(fontString, size, flags)
        fontPath = fontString:GetFont()
    end

    if not fontPath then
        local fallback = fallbackObject or GameFontNormal or SystemFont_Shadow_Med1
        if fallback then
            pcall(fontString.SetFontObject, fontString, fallback)
            fontPath = fontString:GetFont()
        end
    end

    return fontPath ~= nil
end

-- Set FontString text safely, even when skinning clears font state.
local function setFontStringTextSafe(fontString, text, size, flags, fallbackObject)
    if not fontString then
        return
    end

    ensureFontStringFont(fontString, size, flags, fallbackObject)
    pcall(fontString.SetText, fontString, text)
end

-- Create a styled options slider with a shared setup.
local function createSlider(name, parent, label, minValue, maxValue, step)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(260)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    Style:ApplyFont(low, 10)
    Style:ApplyFont(high, 10)
    Style:ApplyFont(text, 12)

    setFontStringTextSafe(low, tostring(minValue), 10)
    setFontStringTextSafe(high, tostring(maxValue), 10)
    setFontStringTextSafe(text, label, 12)

    slider._baseLabel = label

    return slider
end

-- Create a small numeric entry box used beside sliders.
local function createNumericEditBox(name, parent)
    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(64, 22)
    editBox:SetMaxLetters(8)
    editBox:SetNumeric(false)
    editBox:SetJustifyH("CENTER")
    Style:ApplyFont(editBox, 12)
    return editBox
end

-- Set up module state and widget references.
function Configuration:Constructor()
    self.addon = nil
    self.panel = nil
    self.category = nil
    self.widgets = {
        unitPages = {},
        tabs = {},
    }
    self.tabPages = {}
    self.currentTab = nil
    self.minimapButton = nil
end

-- Store a reference to the addon during initialization.
function Configuration:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Register config UI and create the minimap launcher.
function Configuration:OnEnable()
    self:RegisterSettingsCategory()
    self:CreateMinimapLauncher()
end

-- Return the active profile from the data module.
function Configuration:GetProfile()
    local dataHandle = self.addon:GetModule("dataHandle")
    return dataHandle and dataHandle:GetProfile() or nil
end

-- Build dropdown items and bind selection handlers for font choices.
function Configuration:InitializeFontDropdown(dropdown)
    if not dropdown or type(UIDropDownMenu_Initialize) ~= "function" then
        return
    end

    UIDropDownMenu_SetWidth(dropdown, 260)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")

    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local profile = self:GetProfile()
        if not profile then
            return
        end
        profile.style = profile.style or {}
        local selectedPath = profile.style.fontPath
        if not (Style and type(Style.IsFontPathUsable) == "function" and Style:IsFontPathUsable(selectedPath)) then
            selectedPath = (Style and type(Style.GetDefaultFontPath) == "function" and Style:GetDefaultFontPath()) or Style.DEFAULT_FONT
            profile.style.fontPath = selectedPath
        end

        local options = getFontOptions()
        if #options == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = L.CONFIG_NO_FONTS or "No loadable fonts found"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        for i = 1, #options do
            local option = options[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.value = option.path
            info.checked = selectedPath == option.path
            info.func = function()
                local liveProfile = self:GetProfile()
                if not liveProfile then
                    return
                end

                liveProfile.style = liveProfile.style or {}
                liveProfile.style.fontPath = option.path
                UIDropDownMenu_SetText(dropdown, option.label)
                self:RequestUnitFrameRefresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

-- Refresh unit frames now, or defer until combat ends.
function Configuration:RequestUnitFrameRefresh()
    local unitFrames = self.addon:GetModule("unitFrames")
    if not unitFrames then
        return
    end

    -- Defer protected frame updates automatically while in combat.
    Util:RunWhenOutOfCombat(function()
        unitFrames:RefreshAll(true)
    end, L.CONFIG_DEFERRED_APPLY)
end

-- Apply the current value to a slider + editbox control without triggering writes.
function Configuration:SetNumericControlValue(control, value)
    if not control or not control.slider then
        return
    end

    local slider = control.slider
    local input = control.input
    local minValue, maxValue = slider:GetMinMaxValues()
    local step = slider:GetValueStep() or 1
    local normalized = normalizeNumericValue(value, minValue, maxValue, step)
    if not normalized then
        normalized = minValue
    end

    slider._refreshing = true
    slider:SetValue(normalized)
    slider._refreshing = false

    if input then
        input:SetText(formatNumericForDisplay(normalized))
    end
end

-- Update label text for a slider with value suffix.
function Configuration:SetSliderLabel(slider, value)
    if not slider then
        return
    end

    local label = _G[slider:GetName() .. "Text"]
    local baseLabel = slider._baseLabel or ""
    setFontStringTextSafe(label, baseLabel .. ": " .. formatNumericForDisplay(value), 12)
end

-- Create one slider + numeric entry pair and wire update handlers.
function Configuration:CreateNumericControl(parent, keyPrefix, label, minValue, maxValue, step, anchor)
    local sliderName = "mummuFramesConfig" .. keyPrefix .. "Slider"
    local inputName = "mummuFramesConfig" .. keyPrefix .. "Input"

    local slider = createSlider(sliderName, parent, label, minValue, maxValue, step)
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -32)

    local input = createNumericEditBox(inputName, parent)
    input:SetPoint("LEFT", slider, "RIGHT", 18, 0)

    local control = {
        slider = slider,
        input = input,
    }

    return control
end

-- Link a slider/input control to value writes.
function Configuration:BindNumericControl(control, onValueCommitted)
    if not control or not control.slider then
        return
    end

    local slider = control.slider
    local input = control.input

    local function commitRawValue(rawValue)
        local minValue, maxValue = slider:GetMinMaxValues()
        local step = slider:GetValueStep() or 1
        local normalized = normalizeNumericValue(rawValue, minValue, maxValue, step)
        if not normalized then
            self:SetNumericControlValue(control, slider:GetValue())
            return
        end
        slider:SetValue(normalized)
    end

    local function onSliderValueChanged(_, value)
        local minValue, maxValue = slider:GetMinMaxValues()
        local step = slider:GetValueStep() or 1
        local normalized = normalizeNumericValue(value, minValue, maxValue, step)
        if not normalized then
            normalized = minValue
        end

        self:SetSliderLabel(slider, normalized)
        if input then
            input:SetText(formatNumericForDisplay(normalized))
        end

        if slider._refreshing then
            return
        end

        if onValueCommitted then
            onValueCommitted(normalized)
        end
    end

    slider:SetScript("OnValueChanged", onSliderValueChanged)

    if input then
        input:SetScript("OnEnterPressed", function(editBox)
            commitRawValue(editBox:GetText())
            editBox:ClearFocus()
        end)

        input:SetScript("OnEditFocusLost", function(editBox)
            commitRawValue(editBox:GetText())
        end)

        input:SetScript("OnEscapePressed", function(editBox)
            self:SetNumericControlValue(control, slider:GetValue())
            editBox:ClearFocus()
        end)
    end
end

-- Create one labeled checkbox with shared styling.
function Configuration:CreateCheckbox(name, parent, label, anchor, xOffset, yOffset, relativePoint)
    local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, relativePoint or "BOTTOMLEFT", xOffset or 0, yOffset or -8)

    local text = _G[check:GetName() .. "Text"]
    Style:ApplyFont(text, 12)
    setFontStringTextSafe(text, label, 12)

    return check
end

-- Build all controls for the global tab.
function Configuration:BuildGlobalPage(page)
    local enableAddon = self:CreateCheckbox(
        "mummuFramesConfigEnableAddon",
        page,
        L.CONFIG_ENABLE,
        page,
        0,
        -6,
        "TOPLEFT"
    )
    enableAddon:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.enabled = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local testMode = self:CreateCheckbox(
        "mummuFramesConfigTestMode",
        page,
        L.CONFIG_TEST_MODE,
        enableAddon,
        0,
        -8
    )
    testMode:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.testMode = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local pixelPerfect = self:CreateCheckbox(
        "mummuFramesConfigPixelPerfect",
        page,
        L.CONFIG_PIXEL_PERFECT,
        testMode,
        0,
        -8
    )
    pixelPerfect:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.style = profile.style or {}
        profile.style.pixelPerfect = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local globalFontSize = self:CreateNumericControl(
        page,
        "GlobalFontSize",
        L.CONFIG_FONT_SIZE,
        8,
        24,
        1,
        pixelPerfect
    )
    self:BindNumericControl(globalFontSize, function(value)
        local profile = self:GetProfile()
        profile.style = profile.style or {}
        profile.style.fontSize = math.floor((value or 12) + 0.5)
        self:RequestUnitFrameRefresh()
    end)

    local fontLabel = page:CreateFontString(nil, "ARTWORK")
    fontLabel:SetPoint("TOPLEFT", globalFontSize.slider, "BOTTOMLEFT", 0, -28)
    setFontStringTextSafe(fontLabel, L.CONFIG_FONT_FACE, 12)

    local fontDropdown = nil
    if type(UIDropDownMenu_Initialize) == "function" then
        fontDropdown = CreateFrame("Frame", "mummuFramesConfigFontDropdown", page, "UIDropDownMenuTemplate")
        fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -4)

        local dropdownText = _G[fontDropdown:GetName() .. "Text"]
        Style:ApplyFont(dropdownText, 12)
        self:InitializeFontDropdown(fontDropdown)
    end

    self.widgets.enableAddon = enableAddon
    self.widgets.testMode = testMode
    self.widgets.pixelPerfect = pixelPerfect
    self.widgets.globalFontSize = globalFontSize
    self.widgets.fontDropdown = fontDropdown
end

-- Build all controls for a unit-specific tab page.
function Configuration:BuildUnitPage(page, unitToken)
    local dataHandle = self.addon:GetModule("dataHandle")

    local enabled = self:CreateCheckbox(
        "mummuFramesConfig" .. unitToken .. "Enabled",
        page,
        L.CONFIG_UNIT_ENABLE or "Enable frame",
        page,
        0,
        -6,
        "TOPLEFT"
    )
    enabled:SetScript("OnClick", function(button)
        dataHandle:SetUnitConfig(unitToken, "enabled", button:GetChecked() and true or false)
        self:RequestUnitFrameRefresh()
    end)

    local width = self:CreateNumericControl(
        page,
        unitToken .. "Width",
        L.CONFIG_UNIT_WIDTH or "Width",
        100,
        600,
        1,
        enabled
    )
    self:BindNumericControl(width, function(value)
        dataHandle:SetUnitConfig(unitToken, "width", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local height = self:CreateNumericControl(
        page,
        unitToken .. "Height",
        L.CONFIG_UNIT_HEIGHT or "Height",
        18,
        160,
        1,
        width.slider
    )
    self:BindNumericControl(height, function(value)
        dataHandle:SetUnitConfig(unitToken, "height", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local powerHeight = self:CreateNumericControl(
        page,
        unitToken .. "PowerHeight",
        L.CONFIG_UNIT_POWER_HEIGHT or "Power bar height",
        4,
        60,
        1,
        height.slider
    )
    self:BindNumericControl(powerHeight, function(value)
        dataHandle:SetUnitConfig(unitToken, "powerHeight", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local fontSize = self:CreateNumericControl(
        page,
        unitToken .. "FontSize",
        L.CONFIG_UNIT_FONT_SIZE or "Unit font size",
        8,
        26,
        1,
        powerHeight.slider
    )
    self:BindNumericControl(fontSize, function(value)
        dataHandle:SetUnitConfig(unitToken, "fontSize", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local xOffset = self:CreateNumericControl(
        page,
        unitToken .. "XOffset",
        L.CONFIG_UNIT_X or "X offset",
        -1600,
        1600,
        1,
        fontSize.slider
    )
    self:BindNumericControl(xOffset, function(value)
        dataHandle:SetUnitConfig(unitToken, "x", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local yOffset = self:CreateNumericControl(
        page,
        unitToken .. "YOffset",
        L.CONFIG_UNIT_Y or "Y offset",
        -1600,
        1600,
        1,
        xOffset.slider
    )
    self:BindNumericControl(yOffset, function(value)
        dataHandle:SetUnitConfig(unitToken, "y", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local widgets = {
        enabled = enabled,
        width = width,
        height = height,
        powerHeight = powerHeight,
        fontSize = fontSize,
        x = xOffset,
        y = yOffset,
    }

    self.widgets.unitPages[unitToken] = widgets
end

-- Select which tab page is shown.
function Configuration:SelectTab(tabKey)
    if not self.tabPages then
        return
    end

    for key, page in pairs(self.tabPages) do
        if page then
            page:SetShown(key == tabKey)
        end
    end

    for key, button in pairs(self.widgets.tabs) do
        if button then
            button:SetEnabled(key ~= tabKey)
            local fontString = button:GetFontString()
            if fontString then
                if key == tabKey then
                    fontString:SetAlpha(1)
                else
                    fontString:SetAlpha(0.75)
                end
            end
        end
    end

    self.currentTab = tabKey
end

-- Sync UI widget values from the current profile.
function Configuration:RefreshConfigWidgets()
    if not self.panel then
        return
    end

    local profile = self:GetProfile()
    if not profile then
        return
    end

    local style = profile.style or {}

    if self.widgets.enableAddon then
        self.widgets.enableAddon:SetChecked(profile.enabled ~= false)
    end
    if self.widgets.testMode then
        self.widgets.testMode:SetChecked(profile.testMode == true)
    end
    if self.widgets.pixelPerfect then
        self.widgets.pixelPerfect:SetChecked(style.pixelPerfect ~= false)
    end

    if self.widgets.globalFontSize then
        self:SetNumericControlValue(self.widgets.globalFontSize, style.fontSize or 12)
    end

    if self.widgets.fontDropdown and type(UIDropDownMenu_SetText) == "function" then
        UIDropDownMenu_SetText(self.widgets.fontDropdown, getFontLabelByPath(Style:GetFontPath()))
    end

    local dataHandle = self.addon:GetModule("dataHandle")
    for i = 1, #UNIT_TAB_ORDER do
        local unitToken = UNIT_TAB_ORDER[i]
        local unitWidgets = self.widgets.unitPages[unitToken]
        if unitWidgets then
            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            unitWidgets.enabled:SetChecked(unitConfig.enabled ~= false)
            self:SetNumericControlValue(unitWidgets.width, unitConfig.width or 220)
            self:SetNumericControlValue(unitWidgets.height, unitConfig.height or 44)
            self:SetNumericControlValue(unitWidgets.powerHeight, unitConfig.powerHeight or 10)
            self:SetNumericControlValue(unitWidgets.fontSize, unitConfig.fontSize or 12)
            self:SetNumericControlValue(unitWidgets.x, unitConfig.x or 0)
            self:SetNumericControlValue(unitWidgets.y, unitConfig.y or 0)
        end
    end
end

-- Build top-row tab buttons and all tab page frames.
function Configuration:BuildTabs(subtitle)
    local panel = self.panel
    local tabWidth = 94
    local tabHeight = 22
    local tabSpacingX = 6
    local tabSpacingY = 6
    local tabsPerRow = 4

    local tabs = {
        { key = "global", label = L.CONFIG_TAB_GLOBAL or "Global" },
    }

    for i = 1, #UNIT_TAB_ORDER do
        local token = UNIT_TAB_ORDER[i]
        tabs[#tabs + 1] = {
            key = token,
            label = UNIT_TAB_LABELS[token] or token,
        }
    end

    local firstButton = nil
    local previousButton = nil
    local rowStartButton = nil
    local lastRowStartButton = nil

    for i = 1, #tabs do
        local tab = tabs[i]
        local button = CreateFrame("Button", "mummuFramesConfigTab" .. tab.key, panel, "UIPanelButtonTemplate")
        button:SetSize(tabWidth, tabHeight)
        button:SetText(tab.label)
        Style:ApplyFont(button:GetFontString(), 11)

        local indexInRow = (i - 1) % tabsPerRow
        if not firstButton then
            button:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
            firstButton = button
            rowStartButton = button
            lastRowStartButton = button
        elseif indexInRow == 0 then
            button:SetPoint("TOPLEFT", rowStartButton, "BOTTOMLEFT", 0, -tabSpacingY)
            rowStartButton = button
            lastRowStartButton = button
            previousButton = button
        else
            button:SetPoint("LEFT", previousButton, "RIGHT", tabSpacingX, 0)
        end

        button:SetScript("OnClick", function()
            self:SelectTab(tab.key)
        end)

        self.widgets.tabs[tab.key] = button
        previousButton = button

        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", firstButton, "BOTTOMLEFT", 0, -14)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        page:Hide()
        self.tabPages[tab.key] = page

        if tab.key == "global" then
            self:BuildGlobalPage(page)
        else
            self:BuildUnitPage(page, tab.key)
        end
    end

    local pagesTopAnchor = lastRowStartButton or firstButton
    for _, page in pairs(self.tabPages) do
        if page then
            page:ClearAllPoints()
            page:SetPoint("TOPLEFT", pagesTopAnchor, "BOTTOMLEFT", 0, -14)
            page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        end
    end

    self:SelectTab("global")
end

-- Build the settings panel controls once.
function Configuration:BuildSettingsPanel()
    if self.panel._built then
        return
    end

    local panel = self.panel

    -- Header and subtitle for the settings page.
    local title = panel:CreateFontString(nil, "ARTWORK")
    title:SetPoint("TOPLEFT", 16, -16)
    setFontStringTextSafe(title, L.CONFIG_TITLE, 24, nil, GameFontHighlightLarge)

    local subtitle = panel:CreateFontString(nil, "ARTWORK")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    setFontStringTextSafe(subtitle, L.CONFIG_SUBTITLE, 12, nil, GameFontHighlightSmall)
    subtitle:SetTextColor(0.86, 0.86, 0.86, 1)

    self:BuildTabs(subtitle)

    -- Mark panel build complete so this setup runs only once.
    panel._built = true
end

-- Register the settings category in modern or legacy UI.
function Configuration:RegisterSettingsCategory()
    if self.panel then
        return
    end

    self.panel = CreateFrame("Frame", "mummuFramesSettingsPanel", UIParent)
    self.panel.name = L.CONFIG_TITLE

    self:BuildSettingsPanel()
    -- Sync widget state each time the panel is opened.
    self.panel:SetScript("OnShow", function()
        self:RefreshConfigWidgets()
    end)

    -- Prefer the modern Settings API, then fall back to InterfaceOptions.
    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" then
        local category, layout = Settings.RegisterCanvasLayoutCategory(self.panel, L.CONFIG_TITLE, L.CONFIG_TITLE)
        Settings.RegisterAddOnCategory(category)
        self.category = category
        self.layout = layout
    elseif type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(self.panel)
        self.category = self.panel
    end
end

-- Open this addon's config page in the active settings system.
function Configuration:OpenConfig()
    -- Use category ID when the modern Settings API is available.
    if self.category and Settings and type(Settings.OpenToCategory) == "function" then
        local categoryID = self.category.GetID and self.category:GetID() or self.category.ID
        if categoryID then
            Settings.OpenToCategory(categoryID)
            return
        end
    end

    -- Legacy InterfaceOptions may require opening the category twice.
    if self.panel and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end

-- Place or hide the minimap button using the saved angle.
function Configuration:UpdateMinimapButtonPosition()
    if not self.minimapButton then
        return
    end

    local profile = self:GetProfile()
    if not profile then
        return
    end

    if profile.minimap and profile.minimap.hide then
        self.minimapButton:Hide()
        return
    end

    self.minimapButton:Show()

    local angle = tonumber(profile.minimap.angle) or 220
    local radius = (Minimap:GetWidth() * 0.5) + 6
    local radians = math.rad(angle)
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius

    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Create the minimap launcher button and attach its handlers.
function Configuration:CreateMinimapLauncher()
    if self.minimapButton then
        self:UpdateMinimapButtonPosition()
        return
    end

    local button = CreateFrame("Button", "mummuFramesMinimapLauncher", Minimap)
    button:SetSize(26, 26)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(Style:GetBarTexturePath())
    icon:SetVertexColor(0.18, 0.66, 1.0, 0.95)
    button.icon = icon

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    setFontStringTextSafe(label, "M", 12, "OUTLINE")
    button.label = label

    -- Open addon settings on left click.
    button:SetScript("OnClick", function()
        self:OpenConfig()
    end)

    -- Show a short tooltip with usage hints.
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:SetText(L.MINIMAP_TOOLTIP_TITLE, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LINE, 0.85, 0.85, 0.85)
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)

    -- Hide tooltip when the cursor leaves the button.
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Shift+drag updates the stored angle continuously while dragging.
    button:SetScript("OnDragStart", function(selfButton)
        if not IsShiftKeyDown() then
            return
        end

        -- Track cursor movement and convert it to a minimap angle.
        selfButton:SetScript("OnUpdate", function()
            local profile = self:GetProfile()
            if not profile then
                return
            end

            local scale = Minimap:GetEffectiveScale()
            local centerX, centerY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            cursorX = cursorX / scale
            cursorY = cursorY / scale

            local deltaX = cursorX - centerX
            local deltaY = cursorY - centerY

            local angle = math.deg(math.atan(deltaY, deltaX))
            if angle < 0 then
                angle = angle + 360
            end

            profile.minimap.angle = angle
            self:UpdateMinimapButtonPosition()
        end)
    end)

    -- Stop live angle updates when dragging ends.
    button:SetScript("OnDragStop", function(selfButton)
        -- Stop polling cursor movement when dragging ends.
        selfButton:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

addon:RegisterModule("configuration", Configuration:New())
