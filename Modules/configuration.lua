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
local BUFF_POSITION_PRESETS = {
    {
        key = "BOTTOM_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_BOTTOM_LEFT or "Below left",
        anchorPoint = "TOPLEFT",
        relativePoint = "BOTTOMLEFT",
    },
    {
        key = "BOTTOM_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_BOTTOM_RIGHT or "Below right",
        anchorPoint = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
    },
    {
        key = "TOP_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_TOP_LEFT or "Above left",
        anchorPoint = "BOTTOMLEFT",
        relativePoint = "TOPLEFT",
    },
    {
        key = "TOP_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_TOP_RIGHT or "Above right",
        anchorPoint = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
    },
}
local BUFF_SOURCE_OPTIONS = {
    { key = "all", label = L.CONFIG_UNIT_BUFFS_SOURCE_ALL or "All" },
    { key = "self", label = L.CONFIG_UNIT_BUFFS_SOURCE_SELF or "Self only" },
}
local CONFIG_WINDOW_WIDTH = 860
local CONFIG_WINDOW_HEIGHT = 700
local CONFIG_PAGE_CONTENT_HEIGHT = 1500
local CONFIG_PAGE_LEFT_INSET = 34
local CONFIG_PAGE_RIGHT_INSET = 8
local REFRESH_DEBOUNCE_SECONDS = 0.05
local CONFIG_SCROLLBAR_WIDTH = 10
local CONFIG_SCROLLBAR_GUTTER = 8
local CONFIG_SELECT_WIDTH = 260
local CONFIG_SELECT_HEIGHT = 26
local CONFIG_SELECT_ROW_HEIGHT = 22
local CONFIG_SELECT_POPUP_PADDING = 4
local CONFIG_SELECT_POPUP_MIN_ROWS = 4
local CONFIG_SELECT_POPUP_MAX_ROWS = 40
local CONFIG_SELECT_POPUP_TEXTURE_WIDTH = 360
local CONFIG_SELECT_POPUP_DEFAULT_WIDTH = 300
local FONT_DROPDOWN_PREVIEW_SIZE = 12
local TEXTURE_DROPDOWN_PREVIEW_WIDTH = 100
local TEXTURE_DROPDOWN_PREVIEW_HEIGHT = 14
local fontDropdownObjectByPath = {}
local fontDropdownObjectCount = 0
local DROPDOWN_MAX_HEIGHT_SCREEN_RATIO = 0.6

local function getBuffPositionPresetByAnchors(anchorPoint, relativePoint)
    for i = 1, #BUFF_POSITION_PRESETS do
        local preset = BUFF_POSITION_PRESETS[i]
        if preset.anchorPoint == anchorPoint and preset.relativePoint == relativePoint then
            return preset
        end
    end
    return BUFF_POSITION_PRESETS[1]
end

local function getBuffSourceLabel(sourceKey)
    local normalized = sourceKey == "self" and "self" or "all"
    for i = 1, #BUFF_SOURCE_OPTIONS do
        if BUFF_SOURCE_OPTIONS[i].key == normalized then
            return BUFF_SOURCE_OPTIONS[i].label
        end
    end
    return BUFF_SOURCE_OPTIONS[1].label
end

local function getFontOptions(forceRefresh)
    if Style and type(Style.GetAvailableFonts) == "function" then
        return Style:GetAvailableFonts(forceRefresh)
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

local function getBarTextureOptions(forceRefresh)
    if Style and type(Style.GetAvailableBarTextures) == "function" then
        return Style:GetAvailableBarTextures(forceRefresh)
    end
    return {}
end

local function getBarTextureLabelByPath(texturePath)
    local options = getBarTextureOptions()
    for i = 1, #options do
        if options[i].path == texturePath then
            return options[i].label
        end
    end
    return texturePath or "Unknown"
end

local function getNormalizedPath(path)
    if type(path) ~= "string" then
        return nil
    end
    return string.lower(string.gsub(path, "/", "\\"))
end

local function getFontDropdownObject(fontPath)
    if type(fontPath) ~= "string" or fontPath == "" then
        return nil
    end

    local normalized = getNormalizedPath(fontPath) or fontPath
    if fontDropdownObjectByPath[normalized] then
        return fontDropdownObjectByPath[normalized]
    end

    fontDropdownObjectCount = fontDropdownObjectCount + 1
    local object = CreateFont("mummuFramesConfigDropdownFontObject" .. tostring(fontDropdownObjectCount))
    object:CopyFontObject(GameFontHighlightSmall or GameFontNormal or SystemFont_Shadow_Med1)

    local okSet = pcall(object.SetFont, object, fontPath, FONT_DROPDOWN_PREVIEW_SIZE, "")
    if not okSet then
        local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        pcall(object.SetFont, object, fallback, FONT_DROPDOWN_PREVIEW_SIZE, "")
    end

    fontDropdownObjectByPath[normalized] = object
    return object
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

-- Create a labeled dropdown control with addon font styling.
local function createLabeledDropdown(name, parent, labelText, anchor)
    local label = parent:CreateFontString(nil, "ARTWORK")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    setFontStringTextSafe(label, labelText, 12)

    local dropdown = CreateFrame("Button", name, parent)
    dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    dropdown:SetSize(CONFIG_SELECT_WIDTH, CONFIG_SELECT_HEIGHT)
    dropdown:SetNormalTexture("Interface\\Buttons\\WHITE8x8")
    dropdown:GetNormalTexture():SetVertexColor(0.08, 0.08, 0.1, 0.92)
    dropdown:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
    dropdown:GetHighlightTexture():SetVertexColor(0.24, 0.46, 0.72, 0.2)
    dropdown:SetPushedTexture("Interface\\Buttons\\WHITE8x8", "ARTWORK")
    dropdown:GetPushedTexture():SetVertexColor(0.12, 0.2, 0.3, 0.36)

    local borderTop = dropdown:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1, 1, 1, 0.12)

    local borderBottom = dropdown:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1, 1, 1, 0.12)

    local borderLeft = dropdown:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(1, 1, 1, 0.12)

    local borderRight = dropdown:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(1, 1, 1, 0.12)

    local text = dropdown:CreateFontString(nil, "ARTWORK")
    text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    text:SetPoint("RIGHT", dropdown, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    Style:ApplyFont(text, 12)
    dropdown.Text = text

    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    arrow:SetSize(12, 12)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    if type(arrow.SetVertexColor) == "function" then
        arrow:SetVertexColor(0.86, 0.9, 1, 0.95)
    end
    dropdown.Arrow = arrow

    return {
        label = label,
        dropdown = dropdown,
    }
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
    self._refreshScheduled = false
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

local function getSelectPopupMaxRows()
    local screenHeight = (UIParent and UIParent:GetHeight()) or 1080
    if type(screenHeight) ~= "number" or screenHeight <= 0 then
        screenHeight = 1080
    end

    local maxHeight = screenHeight * DROPDOWN_MAX_HEIGHT_SCREEN_RATIO
    local rows = math.floor((maxHeight - (CONFIG_SELECT_POPUP_PADDING * 2)) / CONFIG_SELECT_ROW_HEIGHT)
    return Util:Clamp(rows, CONFIG_SELECT_POPUP_MIN_ROWS, CONFIG_SELECT_POPUP_MAX_ROWS)
end

local function styleMinimalScrollBar(scrollBar)
    if not scrollBar then
        return
    end

    if scrollBar.Back then
        scrollBar.Back:Hide()
    end
    if scrollBar.Track and type(scrollBar.Track.SetAlpha) == "function" then
        scrollBar.Track:SetAlpha(0.8)
    end
end

function Configuration:SetSelectControlText(control, text, fontObject)
    if not control or not control.Text then
        return
    end

    if fontObject then
        pcall(control.Text.SetFontObject, control.Text, fontObject)
    else
        Style:ApplyFont(control.Text, 12)
    end
    setFontStringTextSafe(control.Text, text or "", 12, nil, fontObject or GameFontHighlightSmall)
end

function Configuration:EnsureSelectPopup()
    if self._selectPopup then
        return self._selectPopup
    end

    local popup = CreateFrame("Frame", "mummuFramesConfigSelectPopup", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(250)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    local background = popup:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.06, 0.98)

    local borderTop = popup:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1, 1, 1, 0.12)

    local borderBottom = popup:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1, 1, 1, 0.12)

    local borderLeft = popup:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(1, 1, 1, 0.12)

    local borderRight = popup:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(1, 1, 1, 0.12)

    local clickCatcher = CreateFrame("Button", nil, UIParent)
    clickCatcher:SetFrameStrata("TOOLTIP")
    clickCatcher:SetFrameLevel(249)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:EnableMouse(true)
    clickCatcher:SetScript("OnMouseDown", function()
        self:CloseSelectPopup()
    end)
    clickCatcher:Hide()
    popup.ClickCatcher = clickCatcher

    local scrollBar = CreateFrame("EventFrame", nil, popup, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4, 4)
    scrollBar:SetWidth(12)
    styleMinimalScrollBar(scrollBar)

    local scrollBox = CreateFrame("Frame", nil, popup, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", popup, "TOPLEFT", CONFIG_SELECT_POPUP_PADDING, -CONFIG_SELECT_POPUP_PADDING)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(CONFIG_SELECT_ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, elementData)
        if not row._mummuInit then
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
            row:GetHighlightTexture():SetVertexColor(0.2, 0.46, 0.72, 0.22)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(1, 1, 1, 0)
            row.Background = rowBg

            local preview = row:CreateTexture(nil, "ARTWORK")
            preview:SetPoint("LEFT", row, "LEFT", 8, 0)
            preview:SetSize(TEXTURE_DROPDOWN_PREVIEW_WIDTH, TEXTURE_DROPDOWN_PREVIEW_HEIGHT)
            row.Preview = preview

            local label = row:CreateFontString(nil, "ARTWORK")
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            Style:ApplyFont(label, 12)
            row.Label = label

            local check = row:CreateTexture(nil, "ARTWORK")
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            check:SetSize(14, 14)
            check:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.Check = check

            row:SetScript("OnClick", function(selfRow)
                local data = selfRow:GetElementData()
                if not data or data.disabled then
                    return
                end

                local activePopup = self._selectPopup
                local owner = activePopup and activePopup.Owner
                if not owner then
                    return
                end

                if owner._selectOnChoose then
                    owner._selectOnChoose(data)
                end
                self:CloseSelectPopup()
            end)

            row._mummuInit = true
        end

        local isSelected = (popup.SelectedValue ~= nil and elementData.value == popup.SelectedValue)
        row.Background:SetColorTexture(0.18, 0.66, 1, isSelected and 0.18 or 0)
        row.Check:SetShown(isSelected and not elementData.disabled)

        if elementData.texturePath then
            row.Preview:Show()
            row.Preview:SetTexture(elementData.texturePath)
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row.Preview, "RIGHT", 8, 0)
            row.Label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        else
            row.Preview:Hide()
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.Label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        end

        if elementData.fontPath then
            local okSetFont = pcall(row.Label.SetFont, row.Label, elementData.fontPath, FONT_DROPDOWN_PREVIEW_SIZE, "")
            if not okSetFont and elementData.fontObject then
                pcall(row.Label.SetFontObject, row.Label, elementData.fontObject)
            elseif not okSetFont then
                Style:ApplyFont(row.Label, 12)
            end
        elseif elementData.fontObject then
            pcall(row.Label.SetFontObject, row.Label, elementData.fontObject)
        else
            Style:ApplyFont(row.Label, 12)
        end

        setFontStringTextSafe(row.Label, elementData.label or "", 12, nil, elementData.fontObject or GameFontHighlightSmall)

        if elementData.disabled then
            row:Disable()
            row.Label:SetTextColor(0.7, 0.7, 0.7, 0.9)
        else
            row:Enable()
            row.Label:SetTextColor(1, 1, 1, 1)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    popup.ScrollBox = scrollBox
    popup.ScrollBar = scrollBar
    popup.View = view

    self._selectPopup = popup
    return popup
end

function Configuration:CloseSelectPopup()
    local popup = self._selectPopup
    if not popup then
        return
    end

    if popup.ClickCatcher then
        popup.ClickCatcher:Hide()
    end
    popup.Owner = nil
    popup.SelectedValue = nil
    popup:Hide()
end

function Configuration:ToggleSelectPopup(control)
    if not control then
        return
    end

    local popup = self:EnsureSelectPopup()
    if popup and popup:IsShown() and popup.Owner == control then
        self:CloseSelectPopup()
        return
    end

    self:OpenSelectPopup(control)
end

function Configuration:OpenSelectPopup(control)
    if not control then
        return
    end

    local popup = self:EnsureSelectPopup()
    if not popup or not control._selectGetOptions then
        return
    end

    local options = control._selectGetOptions(true) or {}
    local entries = {}
    for i = 1, #options do
        local option = options[i]
        entries[#entries + 1] = {
            value = option.value,
            label = option.label,
            texturePath = option.texturePath,
            fontPath = option.fontPath,
            fontObject = option.fontObject,
            selectedFontObject = option.selectedFontObject,
            disabled = option.disabled == true,
        }
    end

    if #entries == 0 then
        entries[1] = {
            value = nil,
            label = control._selectEmptyLabel or "No options",
            disabled = true,
        }
    end

    local selectedValue = control._selectGetValue and control._selectGetValue() or nil
    popup.SelectedValue = selectedValue
    popup.Owner = control

    local popupWidth = control._selectPopupWidth or CONFIG_SELECT_POPUP_DEFAULT_WIDTH
    popupWidth = math.max(popupWidth, control:GetWidth() or CONFIG_SELECT_WIDTH)

    local maxVisibleRows = getSelectPopupMaxRows()
    local visibleRows = Util:Clamp(#entries, 1, maxVisibleRows)
    local popupHeight = (visibleRows * CONFIG_SELECT_ROW_HEIGHT) + (CONFIG_SELECT_POPUP_PADDING * 2)

    popup:SetSize(popupWidth, popupHeight)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -4)
    popup:Show()

    if popup:GetBottom() and popup:GetBottom() < 8 then
        popup:ClearAllPoints()
        popup:SetPoint("BOTTOMLEFT", control, "TOPLEFT", 0, 4)
    end
    if popup:GetRight() and UIParent and popup:GetRight() > ((UIParent:GetRight() or 0) - 8) then
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", control, "BOTTOMRIGHT", 0, -4)
        if popup:GetBottom() and popup:GetBottom() < 8 then
            popup:ClearAllPoints()
            popup:SetPoint("BOTTOMRIGHT", control, "TOPRIGHT", 0, 4)
        end
    end

    if popup.ClickCatcher then
        popup.ClickCatcher:Show()
    end

    popup.ScrollBox:SetDataProvider(CreateDataProvider(entries), true)

    local selectedIndex = nil
    if selectedValue ~= nil then
        for i = 1, #entries do
            if entries[i].value == selectedValue then
                selectedIndex = i
                break
            end
        end
    end

    local function scrollToSelectedIndex(index)
        if type(popup.ScrollBox.ScrollToElementDataIndex) ~= "function" then
            return false
        end

        local ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, 0, true)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, true)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, 0)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index)
        return ok and true or false
    end

    local function scrollToStart()
        if type(popup.ScrollBox.ScrollToBegin) ~= "function" then
            return
        end

        local ok = pcall(popup.ScrollBox.ScrollToBegin, popup.ScrollBox, true)
        if not ok then
            pcall(popup.ScrollBox.ScrollToBegin, popup.ScrollBox)
        end
    end

    if selectedIndex and type(popup.ScrollBox.ScrollToElementDataIndex) == "function" then
        local didScroll = scrollToSelectedIndex(selectedIndex)
        if not didScroll then
            scrollToStart()
        end
    else
        scrollToStart()
    end
end

function Configuration:ConfigureSelectControl(control, getOptions, getSelectedValue, onChoose, popupWidth, emptyLabel, fallbackLabel)
    if not control then
        return
    end

    control._selectGetOptions = getOptions
    control._selectGetValue = getSelectedValue
    control._selectOnChoose = onChoose
    control._selectPopupWidth = popupWidth
    control._selectEmptyLabel = emptyLabel
    control._selectFallbackLabel = fallbackLabel

    control:SetScript("OnClick", function(button)
        self:ToggleSelectPopup(button)
    end)
end

function Configuration:RefreshSelectControlText(control, forceRefreshOptions)
    if not control then
        return
    end

    local selectedValue = control._selectGetValue and control._selectGetValue() or nil
    local options = control._selectGetOptions and control._selectGetOptions(forceRefreshOptions == true) or {}
    local selectedLabel = nil
    local selectedFontObject = nil

    for i = 1, #options do
        local option = options[i]
        if option.value == selectedValue then
            selectedLabel = option.label
            selectedFontObject = option.selectedFontObject
            break
        end
    end

    if not selectedLabel then
        if control._selectFallbackLabel then
            selectedLabel = control._selectFallbackLabel(selectedValue)
        else
            selectedLabel = tostring(selectedValue or "")
        end
    end

    self:SetSelectControlText(control, selectedLabel, selectedFontObject)
end

-- Build dropdown items and bind selection handlers for font choices.
function Configuration:InitializeFontDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function(forceRefresh)
            local options = getFontOptions(forceRefresh == true)
            local entries = {}
            for i = 1, #options do
                local option = options[i]
                local fontObject = getFontDropdownObject(option.path)
                entries[#entries + 1] = {
                    value = option.path,
                    label = option.label,
                    fontPath = option.path,
                    fontObject = fontObject,
                    selectedFontObject = fontObject,
                }
            end
            return entries
        end,
        function()
            local profile = self:GetProfile()
            if not profile then
                return nil
            end
            profile.style = profile.style or {}
            if type(profile.style.fontPath) ~= "string" or profile.style.fontPath == "" then
                profile.style.fontPath = (Style and type(Style.GetDefaultFontPath) == "function" and Style:GetDefaultFontPath())
                    or Style.DEFAULT_FONT
            end
            return profile.style.fontPath
        end,
        function(option)
            local profile = self:GetProfile()
            if not profile then
                return
            end

            profile.style = profile.style or {}
            profile.style.fontPath = option.value
            self:SetSelectControlText(dropdown, option.label, option.selectedFontObject)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        L.CONFIG_NO_FONTS or "No loadable fonts found",
        function(value)
            return getFontLabelByPath(value)
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Build dropdown items and bind selection handlers for status bar textures.
function Configuration:InitializeBarTextureDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function(forceRefresh)
            local options = getBarTextureOptions(forceRefresh == true)
            local entries = {}
            for i = 1, #options do
                local option = options[i]
                entries[#entries + 1] = {
                    value = option.path,
                    label = option.label,
                    texturePath = option.path,
                }
            end
            return entries
        end,
        function()
            local profile = self:GetProfile()
            if not profile then
                return nil
            end
            profile.style = profile.style or {}
            if type(profile.style.barTexturePath) ~= "string" or profile.style.barTexturePath == "" then
                profile.style.barTexturePath = (Style and type(Style.GetDefaultBarTexturePath) == "function" and Style:GetDefaultBarTexturePath())
                    or Style.DEFAULT_BAR_TEXTURE
            end
            return profile.style.barTexturePath
        end,
        function(option)
            local profile = self:GetProfile()
            if not profile then
                return
            end

            profile.style = profile.style or {}
            profile.style.barTexturePath = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            if self.minimapButton and self.minimapButton.icon then
                self.minimapButton.icon:SetTexture(option.value)
            end
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_TEXTURE_WIDTH,
        L.CONFIG_NO_TEXTURES or "No status bar textures found",
        function(value)
            return getBarTextureLabelByPath(value)
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Build dropdown items and bind selection handlers for buff position presets.
function Configuration:InitializeBuffPositionDropdown(dropdown, unitToken)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #BUFF_POSITION_PRESETS do
                local preset = BUFF_POSITION_PRESETS[i]
                entries[#entries + 1] = {
                    value = preset.key,
                    label = preset.label,
                    preset = preset,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return BUFF_POSITION_PRESETS[1].key
            end

            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            local selectedPreset = getBuffPositionPresetByAnchors(
                buffsConfig.anchorPoint or "TOPLEFT",
                buffsConfig.relativePoint or "BOTTOMLEFT"
            )
            return selectedPreset.key
        end,
        function(option)
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle or not option.preset then
                return
            end

            dataHandle:SetUnitConfig(unitToken, "aura.buffs.anchorPoint", option.preset.anchorPoint)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.relativePoint", option.preset.relativePoint)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function()
            return BUFF_POSITION_PRESETS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Build dropdown items and bind selection handlers for buff source filtering.
function Configuration:InitializeBuffSourceDropdown(dropdown, unitToken)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #BUFF_SOURCE_OPTIONS do
                local option = BUFF_SOURCE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return "all"
            end

            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            return buffsConfig.source == "self" and "self" or "all"
        end,
        function(option)
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return
            end

            dataHandle:SetUnitConfig(unitToken, "aura.buffs.source", option.value)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getBuffSourceLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Refresh unit frames now, or defer until combat ends.
-- Calls are coalesced for a short time to reduce slider-drag churn.
function Configuration:RequestUnitFrameRefresh(immediate)
    local unitFrames = self.addon:GetModule("unitFrames")
    if not unitFrames then
        return
    end

    local function runRefresh()
        self._refreshScheduled = false
        Util:RunWhenOutOfCombat(function()
            unitFrames:RefreshAll(true)
        end, L.CONFIG_DEFERRED_APPLY, "config_refresh_all")
    end

    local delay = (immediate and 0) or REFRESH_DEBOUNCE_SECONDS
    if delay <= 0 then
        runRefresh()
        return
    end

    if self._refreshScheduled then
        return
    end
    self._refreshScheduled = true

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, runRefresh)
    else
        runRefresh()
    end
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
function Configuration:CreateNumericControl(parent, keyPrefix, label, minValue, maxValue, step, anchor, anchorXOffset)
    local sliderName = "mummuFramesConfig" .. keyPrefix .. "Slider"
    local inputName = "mummuFramesConfig" .. keyPrefix .. "Input"

    local slider = createSlider(sliderName, parent, label, minValue, maxValue, step)
    local resolvedXOffset = anchorXOffset or 0
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", resolvedXOffset, -32)

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
        pixelPerfect,
        20
    )
    self:BindNumericControl(globalFontSize, function(value)
        local profile = self:GetProfile()
        profile.style = profile.style or {}
        profile.style.fontSize = math.floor((value or 12) + 0.5)
        self:RequestUnitFrameRefresh()
    end)

    local fontControl = createLabeledDropdown(
        "mummuFramesConfigFontDropdown",
        page,
        L.CONFIG_FONT_FACE,
        globalFontSize.slider
    )
    local fontDropdown = fontControl and fontControl.dropdown or nil
    if fontDropdown then
        self:InitializeFontDropdown(fontDropdown)
    end

    local textureAnchor = fontDropdown or globalFontSize.slider
    local barTextureControl = createLabeledDropdown(
        "mummuFramesConfigBarTextureDropdown",
        page,
        L.CONFIG_BAR_TEXTURE or "Bar texture",
        textureAnchor
    )
    local barTextureDropdown = barTextureControl and barTextureControl.dropdown or nil
    if barTextureDropdown then
        self:InitializeBarTextureDropdown(barTextureDropdown)
    end

    self.widgets.enableAddon = enableAddon
    self.widgets.testMode = testMode
    self.widgets.pixelPerfect = pixelPerfect
    self.widgets.globalFontSize = globalFontSize
    self.widgets.fontDropdown = fontDropdown
    self.widgets.barTextureDropdown = barTextureDropdown
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

    local hideBlizzard = self:CreateCheckbox(
        "mummuFramesConfig" .. unitToken .. "HideBlizzard",
        page,
        L.CONFIG_UNIT_HIDE_BLIZZARD or "Hide Blizzard frame",
        enabled,
        0,
        -8
    )
    hideBlizzard:SetScript("OnClick", function(button)
        dataHandle:SetUnitConfig(unitToken, "hideBlizzardFrame", button:GetChecked() and true or false)
        self:RequestUnitFrameRefresh()
    end)

    local buffsEnabled = self:CreateCheckbox(
        "mummuFramesConfig" .. unitToken .. "BuffsEnabled",
        page,
        L.CONFIG_UNIT_BUFFS_ENABLE or "Show buffs",
        hideBlizzard,
        0,
        -8
    )
    buffsEnabled:SetScript("OnClick", function(button)
        dataHandle:SetUnitConfig(unitToken, "aura.buffs.enabled", button:GetChecked() and true or false)
        self:RequestUnitFrameRefresh()
    end)

    local buffsMax = self:CreateNumericControl(
        page,
        unitToken .. "BuffsMax",
        L.CONFIG_UNIT_BUFFS_MAX or "Buff count",
        1,
        16,
        1,
        buffsEnabled,
        20
    )
    self:BindNumericControl(buffsMax, function(value)
        dataHandle:SetUnitConfig(unitToken, "aura.buffs.max", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local buffsSize = self:CreateNumericControl(
        page,
        unitToken .. "BuffsSize",
        L.CONFIG_UNIT_BUFFS_SIZE or "Buff size",
        10,
        48,
        1,
        buffsMax.slider
    )
    self:BindNumericControl(buffsSize, function(value)
        dataHandle:SetUnitConfig(unitToken, "aura.buffs.size", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local layoutAnchor = buffsSize.slider
    local layoutAnchorXOffset = 20

    local buffsPositionControl = createLabeledDropdown(
        "mummuFramesConfig" .. unitToken .. "BuffPositionDropdown",
        page,
        L.CONFIG_UNIT_BUFFS_POSITION or "Buff position",
        layoutAnchor
    )
    if buffsPositionControl and buffsPositionControl.dropdown then
        self:InitializeBuffPositionDropdown(buffsPositionControl.dropdown, unitToken)
        layoutAnchor = buffsPositionControl.dropdown
        layoutAnchorXOffset = 20
    end

    local buffsSourceControl = createLabeledDropdown(
        "mummuFramesConfig" .. unitToken .. "BuffSourceDropdown",
        page,
        L.CONFIG_UNIT_BUFFS_SOURCE or "Buff source",
        layoutAnchor
    )
    if buffsSourceControl and buffsSourceControl.dropdown then
        self:InitializeBuffSourceDropdown(buffsSourceControl.dropdown, unitToken)
        layoutAnchor = buffsSourceControl.dropdown
        layoutAnchorXOffset = 20
    end

    local width = self:CreateNumericControl(
        page,
        unitToken .. "Width",
        L.CONFIG_UNIT_WIDTH or "Width",
        100,
        600,
        1,
        layoutAnchor,
        layoutAnchorXOffset
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

    local powerOnTop = self:CreateCheckbox(
        "mummuFramesConfig" .. unitToken .. "PowerOnTop",
        page,
        L.CONFIG_UNIT_POWER_ON_TOP or "Power bar on top",
        powerHeight.slider,
        0,
        -8
    )
    powerOnTop:SetScript("OnClick", function(button)
        dataHandle:SetUnitConfig(unitToken, "powerOnTop", button:GetChecked() and true or false)
        self:RequestUnitFrameRefresh()
    end)

    local fontSize = self:CreateNumericControl(
        page,
        unitToken .. "FontSize",
        L.CONFIG_UNIT_FONT_SIZE or "Unit font size",
        8,
        26,
        1,
        powerOnTop
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

    -- Cast bar options (player, target, and focus).
    local castbarEnabled, castbarDetach, castbarWidth, castbarHeight, castbarShowIcon, castbarHideBlizzard
    local secondaryPowerEnabled, secondaryPowerDetach, secondaryPowerSize
    local tertiaryPowerEnabled, tertiaryPowerDetach, tertiaryPowerHeight
    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        castbarEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarEnabled",
            page,
            L.CONFIG_UNIT_CASTBAR_ENABLE or "Show cast bar",
            yOffset.slider,
            0,
            -16
        )
        castbarEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarDetach",
            page,
            L.CONFIG_UNIT_CASTBAR_DETACH or "Detach cast bar",
            castbarEnabled,
            0,
            -8
        )
        castbarDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarWidth = self:CreateNumericControl(
            page,
            unitToken .. "CastbarWidth",
            L.CONFIG_UNIT_CASTBAR_WIDTH or "Cast bar width",
            50,
            600,
            1,
            castbarDetach
        )
        self:BindNumericControl(castbarWidth, function(value)
            dataHandle:SetUnitConfig(unitToken, "castbar.width", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        castbarHeight = self:CreateNumericControl(
            page,
            unitToken .. "CastbarHeight",
            L.CONFIG_UNIT_CASTBAR_HEIGHT or "Cast bar height",
            8,
            40,
            1,
            castbarWidth.slider
        )
        self:BindNumericControl(castbarHeight, function(value)
            dataHandle:SetUnitConfig(unitToken, "castbar.height", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        castbarShowIcon = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarShowIcon",
            page,
            L.CONFIG_UNIT_CASTBAR_SHOW_ICON or "Show spell icon",
            castbarHeight.slider,
            0,
            -8
        )
        castbarShowIcon:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.showIcon", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarHideBlizzard = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarHideBlizzard",
            page,
            L.CONFIG_UNIT_CASTBAR_HIDE_BLIZZARD or "Hide Blizzard cast bar",
            castbarShowIcon,
            0,
            -8
        )
        castbarHideBlizzard:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.hideBlizzardCastBar", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
    end

    if unitToken == "player" then
        local secondaryAnchor = castbarHideBlizzard or yOffset.slider
        local secondaryYOffset = castbarHideBlizzard and -10 or -16

        secondaryPowerEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "SecondaryPowerEnabled",
            page,
            L.CONFIG_UNIT_SECONDARY_POWER_ENABLE or "Show secondary power bar",
            secondaryAnchor,
            0,
            secondaryYOffset
        )
        secondaryPowerEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        secondaryPowerDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "SecondaryPowerDetach",
            page,
            L.CONFIG_UNIT_SECONDARY_POWER_DETACH or "Detach secondary power bar",
            secondaryPowerEnabled,
            0,
            -8
        )
        secondaryPowerDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        secondaryPowerSize = self:CreateNumericControl(
            page,
            unitToken .. "SecondaryPowerSize",
            L.CONFIG_UNIT_SECONDARY_POWER_SIZE or "Secondary power size",
            8,
            40,
            1,
            secondaryPowerDetach
        )
        self:BindNumericControl(secondaryPowerSize, function(value)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.size", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "TertiaryPowerEnabled",
            page,
            L.CONFIG_UNIT_TERTIARY_POWER_ENABLE or "Show tertiary power bar",
            secondaryPowerSize.slider,
            0,
            -12
        )
        tertiaryPowerEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "TertiaryPowerDetach",
            page,
            L.CONFIG_UNIT_TERTIARY_POWER_DETACH or "Detach tertiary power bar",
            tertiaryPowerEnabled,
            0,
            -8
        )
        tertiaryPowerDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerHeight = self:CreateNumericControl(
            page,
            unitToken .. "TertiaryPowerHeight",
            L.CONFIG_UNIT_TERTIARY_POWER_HEIGHT or "Tertiary power bar height",
            4,
            24,
            1,
            tertiaryPowerDetach
        )
        self:BindNumericControl(tertiaryPowerHeight, function(value)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.height", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)
    end

    local widgets = {
        enabled = enabled,
        hideBlizzard = hideBlizzard,
        buffsEnabled = buffsEnabled,
        buffsMax = buffsMax,
        buffsSize = buffsSize,
        buffsPositionDropdown = buffsPositionControl and buffsPositionControl.dropdown or nil,
        buffsSourceDropdown = buffsSourceControl and buffsSourceControl.dropdown or nil,
        width = width,
        height = height,
        powerHeight = powerHeight,
        powerOnTop = powerOnTop,
        fontSize = fontSize,
        x = xOffset,
        y = yOffset,
        castbarEnabled = castbarEnabled,
        castbarDetach = castbarDetach,
        castbarWidth = castbarWidth,
        castbarHeight = castbarHeight,
        castbarShowIcon = castbarShowIcon,
        castbarHideBlizzard = castbarHideBlizzard,
        secondaryPowerEnabled = secondaryPowerEnabled,
        secondaryPowerDetach = secondaryPowerDetach,
        secondaryPowerSize = secondaryPowerSize,
        tertiaryPowerEnabled = tertiaryPowerEnabled,
        tertiaryPowerDetach = tertiaryPowerDetach,
        tertiaryPowerHeight = tertiaryPowerHeight,
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
            local selected = key == tabKey
            page:SetShown(selected)
            if selected and page.ScrollFrame then
                page.ScrollFrame:SetVerticalScroll(0)
                page.ScrollFrame:SetHorizontalScroll(0)
                if page.ScrollBar then
                    if type(page.ScrollBar.SetValue) == "function" then
                        page.ScrollBar:SetValue(0)
                    elseif type(page.ScrollBar.SetScrollPercentage) == "function" then
                        page.ScrollBar:SetScrollPercentage(0, true)
                    end
                end
            end
        end
    end

    for key, button in pairs(self.widgets.tabs) do
        if button then
            local selected = key == tabKey
            if button._background then
                if selected then
                    button._background:SetColorTexture(1, 1, 1, 0.2)
                else
                    button._background:SetColorTexture(1, 1, 1, 0.08)
                end
            end
            if button._label then
                button._label:SetAlpha(selected and 1 or 0.78)
            end
        end
    end

    self.currentTab = tabKey
end

-- Build one scrollable tab page so long option lists stay inside the window.
function Configuration:CreateScrollableTabPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetClipsChildren(true)

    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -2, 4)
    scrollBar:SetWidth(CONFIG_SCROLLBAR_WIDTH)
    styleMinimalScrollBar(scrollBar)

    local scrollFrame = CreateFrame("ScrollFrame", nil, page)
    scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -CONFIG_SCROLLBAR_GUTTER, 2)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetHorizontalScroll(0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", CONFIG_PAGE_LEFT_INSET, 0)
    content:SetWidth(1)
    content:SetHeight(CONFIG_PAGE_CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(content)

    local function updateContentWidth(selfFrame, width)
        local resolvedWidth = width or selfFrame:GetWidth() or 1
        local contentWidth = math.max(1, resolvedWidth - CONFIG_PAGE_LEFT_INSET - CONFIG_PAGE_RIGHT_INSET)
        content:SetWidth(contentWidth)
    end
    updateContentWidth(scrollFrame, scrollFrame:GetWidth())

    local function getScrollRange(selfFrame)
        local maxRange = selfFrame:GetVerticalScrollRange() or 0
        if maxRange < 0 then
            maxRange = 0
        end
        return maxRange
    end

    local baseSetScrollPercentage = type(scrollBar.SetScrollPercentage) == "function" and scrollBar.SetScrollPercentage or nil
    function scrollBar:SetScrollPercentage(scrollPercentage, fromMouseWheel)
        local clamped = Util:Clamp(tonumber(scrollPercentage) or 0, 0, 1)

        if baseSetScrollPercentage then
            baseSetScrollPercentage(self, clamped, fromMouseWheel)
        elseif ScrollControllerMixin and type(ScrollControllerMixin.SetScrollPercentage) == "function" then
            ScrollControllerMixin.SetScrollPercentage(self, clamped)
        end

        if type(self.Update) == "function" then
            self:Update()
        end

        if fromMouseWheel then
            return
        end

        local maxRange = getScrollRange(scrollFrame)
        local offset = maxRange * clamped
        scrollFrame:SetVerticalScroll(offset)
        scrollFrame:SetHorizontalScroll(0)
    end

    local function syncScrollBarValue(selfFrame, fromMouseWheel)
        local maxRange = getScrollRange(selfFrame)
        local current = selfFrame:GetVerticalScroll() or 0
        if current > maxRange then
            current = maxRange
            selfFrame:SetVerticalScroll(current)
        end

        local frameHeight = math.max(1, selfFrame:GetHeight() or 1)
        local contentHeight = math.max(frameHeight, content:GetHeight() or frameHeight)
        local visibleRatio = Util:Clamp(frameHeight / contentHeight, 0, 1)
        if type(scrollBar.SetVisibleExtentPercentage) == "function" then
            scrollBar:SetVisibleExtentPercentage(visibleRatio)
        end

        if maxRange <= 0 then
            scrollBar:Hide()
        else
            scrollBar:Show()
        end

        local percentage = (maxRange > 0) and (current / maxRange) or 0
        if type(scrollBar.SetScrollPercentage) == "function" then
            scrollBar:SetScrollPercentage(percentage, fromMouseWheel and true or false)
        end
    end

    scrollFrame:SetScript("OnMouseWheel", function(selfFrame, delta)
        local step = 52
        local current = selfFrame:GetVerticalScroll() or 0
        local target = current - (delta * step)
        local maxRange = getScrollRange(selfFrame)
        if target < 0 then
            target = 0
        elseif target > maxRange then
            target = maxRange
        end
        selfFrame:SetVerticalScroll(target)
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)
    scrollFrame:SetScript("OnSizeChanged", function(selfFrame, width)
        updateContentWidth(selfFrame, width)
        syncScrollBarValue(selfFrame, true)
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(selfFrame, offset)
        local target = offset or 0
        local maxRange = getScrollRange(selfFrame)
        if target < 0 then
            target = 0
        elseif target > maxRange then
            target = maxRange
        end
        if target ~= (selfFrame:GetVerticalScroll() or 0) then
            selfFrame:SetVerticalScroll(target)
        end
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(selfFrame)
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)

    syncScrollBarValue(scrollFrame, true)

    page.ScrollFrame = scrollFrame
    page.ScrollBar = scrollBar
    page.Content = content
    return page, content
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

    if self.widgets.fontDropdown then
        self:RefreshSelectControlText(self.widgets.fontDropdown, true)
    end
    if self.widgets.barTextureDropdown then
        self:RefreshSelectControlText(self.widgets.barTextureDropdown, true)
    end
    if self.minimapButton and self.minimapButton.icon then
        self.minimapButton.icon:SetTexture(Style:GetBarTexturePath())
    end

    local dataHandle = self.addon:GetModule("dataHandle")
    for i = 1, #UNIT_TAB_ORDER do
        local unitToken = UNIT_TAB_ORDER[i]
        local unitWidgets = self.widgets.unitPages[unitToken]
        if unitWidgets then
            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            unitWidgets.enabled:SetChecked(unitConfig.enabled ~= false)
            if unitWidgets.hideBlizzard then
                unitWidgets.hideBlizzard:SetChecked(unitConfig.hideBlizzardFrame == true)
            end
            if unitWidgets.buffsEnabled then
                unitWidgets.buffsEnabled:SetChecked(buffsConfig.enabled ~= false)
            end
            if unitWidgets.buffsMax then
                self:SetNumericControlValue(unitWidgets.buffsMax, buffsConfig.max or 8)
            end
            if unitWidgets.buffsSize then
                self:SetNumericControlValue(unitWidgets.buffsSize, buffsConfig.size or 18)
            end
            if unitWidgets.buffsPositionDropdown then
                self:RefreshSelectControlText(unitWidgets.buffsPositionDropdown, false)
            end
            if unitWidgets.buffsSourceDropdown then
                self:RefreshSelectControlText(unitWidgets.buffsSourceDropdown, false)
            end
            self:SetNumericControlValue(unitWidgets.width, unitConfig.width or 220)
            self:SetNumericControlValue(unitWidgets.height, unitConfig.height or 44)
            self:SetNumericControlValue(unitWidgets.powerHeight, unitConfig.powerHeight or 10)
            if unitWidgets.powerOnTop then
                unitWidgets.powerOnTop:SetChecked(unitConfig.powerOnTop == true)
            end
            self:SetNumericControlValue(unitWidgets.fontSize, unitConfig.fontSize or 12)
            self:SetNumericControlValue(unitWidgets.x, unitConfig.x or 0)
            self:SetNumericControlValue(unitWidgets.y, unitConfig.y or 0)
            local castbarConfig = unitConfig.castbar or {}
            if unitWidgets.castbarEnabled then
                unitWidgets.castbarEnabled:SetChecked(castbarConfig.enabled ~= false)
            end
            if unitWidgets.castbarDetach then
                unitWidgets.castbarDetach:SetChecked(castbarConfig.detached == true)
            end
            if unitWidgets.castbarWidth then
                self:SetNumericControlValue(unitWidgets.castbarWidth, castbarConfig.width or unitConfig.width or 220)
            end
            if unitWidgets.castbarHeight then
                self:SetNumericControlValue(unitWidgets.castbarHeight, castbarConfig.height or 20)
            end
            if unitWidgets.castbarShowIcon then
                unitWidgets.castbarShowIcon:SetChecked(castbarConfig.showIcon ~= false)
            end
            if unitWidgets.castbarHideBlizzard then
                unitWidgets.castbarHideBlizzard:SetChecked(castbarConfig.hideBlizzardCastBar == true)
            end
            local secondaryPowerConfig = unitConfig.secondaryPower or {}
            if unitWidgets.secondaryPowerEnabled then
                unitWidgets.secondaryPowerEnabled:SetChecked(secondaryPowerConfig.enabled ~= false)
            end
            if unitWidgets.secondaryPowerDetach then
                unitWidgets.secondaryPowerDetach:SetChecked(secondaryPowerConfig.detached == true)
            end
            if unitWidgets.secondaryPowerSize then
                self:SetNumericControlValue(unitWidgets.secondaryPowerSize, secondaryPowerConfig.size or 16)
            end
            local tertiaryPowerConfig = unitConfig.tertiaryPower or {}
            if unitWidgets.tertiaryPowerEnabled then
                unitWidgets.tertiaryPowerEnabled:SetChecked(tertiaryPowerConfig.enabled ~= false)
            end
            if unitWidgets.tertiaryPowerDetach then
                unitWidgets.tertiaryPowerDetach:SetChecked(tertiaryPowerConfig.detached == true)
            end
            if unitWidgets.tertiaryPowerHeight then
                self:SetNumericControlValue(unitWidgets.tertiaryPowerHeight, tertiaryPowerConfig.height or 8)
            end
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
        local button = CreateFrame("Button", "mummuFramesConfigTab" .. tab.key, panel)
        button:SetSize(tabWidth, tabHeight)

        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(1, 1, 1, 0.08)
        button._background = background

        local label = button:CreateFontString(nil, "ARTWORK")
        label:SetPoint("CENTER", 0, 0)
        setFontStringTextSafe(label, tab.label, 11)
        button._label = label

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
        button:SetScript("OnEnter", function()
            if self.currentTab ~= tab.key and button._background then
                button._background:SetColorTexture(1, 1, 1, 0.14)
            end
        end)
        button:SetScript("OnLeave", function()
            if self.currentTab ~= tab.key and button._background then
                button._background:SetColorTexture(1, 1, 1, 0.08)
            end
        end)

        self.widgets.tabs[tab.key] = button
        previousButton = button

        local page, content = self:CreateScrollableTabPage(panel)
        page:SetPoint("TOPLEFT", firstButton, "BOTTOMLEFT", 0, -14)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        page:Hide()
        self.tabPages[tab.key] = page

        if tab.key == "global" then
            self:BuildGlobalPage(content)
        else
            self:BuildUnitPage(content, tab.key)
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
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)

    -- Keep visuals minimal with simple flat fills and no Blizzard window frame.
    panel.Background = Style:CreateBackground(panel, 0.05, 0.05, 0.06, 0.95)

    local headerFill = panel:CreateTexture(nil, "ARTWORK")
    headerFill:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    headerFill:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    headerFill:SetHeight(34)
    headerFill:SetColorTexture(1, 1, 1, 0.04)
    panel.HeaderFill = headerFill

    local headerLine = panel:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT", headerFill, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerFill, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(1, 1, 1, 0.08)
    panel.HeaderLine = headerLine

    local dragHandle = CreateFrame("Frame", nil, panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -6)
    dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -42, -6)
    dragHandle:SetHeight(24)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        panel:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    panel.DragHandle = dragHandle

    local closeButton = CreateFrame("Button", nil, panel)
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)

    local closeNormal = closeButton:CreateTexture(nil, "BACKGROUND")
    closeNormal:SetAllPoints()
    closeNormal:SetColorTexture(1, 1, 1, 0.06)
    closeButton.Normal = closeNormal

    local closeHover = closeButton:CreateTexture(nil, "ARTWORK")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(1, 1, 1, 0.14)
    closeHover:Hide()
    closeButton.Hover = closeHover

    local closeLabel = closeButton:CreateFontString(nil, "OVERLAY")
    closeLabel:SetPoint("CENTER", 0, 0)
    setFontStringTextSafe(closeLabel, "x", 12, "OUTLINE")
    closeButton.Label = closeLabel

    closeButton:SetScript("OnEnter", function()
        closeHover:Show()
    end)
    closeButton:SetScript("OnLeave", function()
        closeHover:Hide()
    end)
    closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)
    panel.CloseButton = closeButton

    -- Header and subtitle for the settings page.
    local title = panel:CreateFontString(nil, "ARTWORK")
    title:SetPoint("TOPLEFT", 16, -10)
    setFontStringTextSafe(title, L.CONFIG_TITLE, 24, nil, GameFontHighlightLarge)

    local subtitle = panel:CreateFontString(nil, "ARTWORK")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    setFontStringTextSafe(subtitle, L.CONFIG_SUBTITLE, 12, nil, GameFontHighlightSmall)
    subtitle:SetTextColor(0.86, 0.86, 0.86, 1)

    self:BuildTabs(subtitle)

    -- Mark panel build complete so this setup runs only once.
    panel._built = true
end

-- Build the standalone configuration window once.
function Configuration:RegisterSettingsCategory()
    if self.panel then
        return
    end

    self.panel = CreateFrame("Frame", "mummuFramesConfigWindow", UIParent)
    self.panel:SetSize(CONFIG_WINDOW_WIDTH, CONFIG_WINDOW_HEIGHT)
    self.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.panel:SetFrameStrata("DIALOG")
    self.panel:SetFrameLevel(50)
    self.panel:Hide()
    if type(UISpecialFrames) == "table" then
        local frameName = self.panel:GetName()
        local known = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == frameName then
                known = true
                break
            end
        end
        if not known then
            table.insert(UISpecialFrames, frameName)
        end
    end

    self:BuildSettingsPanel()
    -- Sync widget state each time the panel is opened.
    self.panel:SetScript("OnShow", function()
        self:RefreshConfigWidgets()
    end)
    self.panel:HookScript("OnHide", function()
        self:CloseSelectPopup()
    end)
end

-- Open this addon's standalone configuration window.
function Configuration:OpenConfig()
    if not self.panel then
        self:RegisterSettingsCategory()
    end

    if self.panel then
        self.panel:Show()
        self.panel:Raise()
        self:RefreshConfigWidgets()
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
        if InCombatLockdown() then
            return
        end
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
