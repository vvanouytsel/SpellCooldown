local addonName, addon = ...

-- Default settings
local defaultSettings = {
    width = 40,
    height = 40,
    displayDuration = 2,
    fontSize = 16,
    textColorR = 1,
    textColorG = 1,
    textColorB = 1,
    borderEnabled = true,
    borderSize = 2,
    borderColorR = 0,
    borderColorG = 0,
    borderColorB = 0,
    showDecimals = false,
}

-- Initialize saved variables
SpellCooldownDB = SpellCooldownDB or {}

local function GetSetting(key)
    if SpellCooldownDB[key] ~= nil then
        return SpellCooldownDB[key]
    end
    return defaultSettings[key]
end

local function SetSetting(key, value)
    SpellCooldownDB[key] = value
end

-- Create main frame
local cooldownFrame = CreateFrame("Frame", "SpellCooldownFrame", UIParent)
cooldownFrame:SetSize(GetSetting("width"), GetSetting("height"))
cooldownFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
cooldownFrame:SetFrameStrata("HIGH")
cooldownFrame:Hide()

-- Create border frame (slightly larger)
local borderFrame = CreateFrame("Frame", nil, cooldownFrame)
borderFrame:SetFrameLevel(cooldownFrame:GetFrameLevel() - 1)

local borderTexture = borderFrame:CreateTexture(nil, "BACKGROUND")
borderTexture:SetColorTexture(GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB"), 1)

-- Create icon texture
local icon = cooldownFrame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints(cooldownFrame)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local function UpdateBorder()
    if GetSetting("borderEnabled") then
        local size = GetSetting("borderSize")
        borderFrame:ClearAllPoints()
        borderFrame:SetAllPoints(cooldownFrame)
        borderTexture:ClearAllPoints()
        borderTexture:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", -size, size)
        borderTexture:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", size, -size)
        local r, g, b = GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB")
        borderTexture:SetColorTexture(r, g, b, 1)
        borderFrame:Show()
    else
        borderFrame:Hide()
    end
end

UpdateBorder()

-- Create cooldown text
local cooldownText = cooldownFrame:CreateFontString(nil, "OVERLAY")
cooldownText:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
cooldownText:SetPoint("CENTER", cooldownFrame, "CENTER", 0, 0)
cooldownText:SetTextColor(GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"))

-- Variables
local activeSpellID = nil
local cooldownEndTime = 0
local hideTime = 0
local debugMode = false
local isLocked = true
local cachedTextColorR, cachedTextColorG, cachedTextColorB

-- Cache text colors to avoid GetSetting calls in OnUpdate
local function UpdateCachedColors()
    cachedTextColorR = GetSetting("textColorR")
    cachedTextColorG = GetSetting("textColorG")
    cachedTextColorB = GetSetting("textColorB")
    cooldownText:SetTextColor(cachedTextColorR, cachedTextColorG, cachedTextColorB)
end

UpdateCachedColors()

-- Format cooldown time
local function FormatCooldownTime(seconds)
    local showDecimals = GetSetting("showDecimals")
    
    if seconds >= 60 then
        return string.format("%.1fm", seconds / 60)
    elseif seconds >= 10 then
        return string.format("%.0f", seconds)
    elseif seconds >= 1 then
        if showDecimals then
            return string.format("%.1f", seconds)
        else
            return string.format("%.0f", seconds)
        end
    else
        if showDecimals then
            return string.format("%.1f", seconds)
        else
            return string.format("%.0f", seconds)
        end
    end
end

-- Update cooldown display
local function UpdateCooldown()
    local currentTime = GetTime()
    
    -- Check if we should hide based on display duration
    if hideTime > 0 and currentTime >= hideTime then
        cooldownFrame:Hide()
        activeSpellID = nil
        cooldownEndTime = 0
        hideTime = 0
        return
    end
    
    local remaining = cooldownEndTime - currentTime
    
    if remaining <= 0 then
        -- Cooldown finished, hide immediately
        cooldownFrame:Hide()
        activeSpellID = nil
        cooldownEndTime = 0
        hideTime = 0
        return
    end
    
    cooldownText:SetText(FormatCooldownTime(remaining))
end

-- OnUpdate handler
cooldownFrame:SetScript("OnUpdate", function(self, elapsed)
    if activeSpellID then
        UpdateCooldown()
    end
end)

-- Check if spell is on cooldown and display it
local function CheckAndDisplayCooldown(spellID)
    if not spellID then 
        if debugMode then print("SpellCD: No spell ID") end
        return 
    end
    
    if debugMode then print("SpellCD: Checking spell ID:", spellID) end
    
    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    
    if debugMode then
        if cooldownInfo then
            print("SpellCD: Cooldown duration:", cooldownInfo.duration)
        else
            print("SpellCD: No cooldown info")
        end
    end
    
    if cooldownInfo and cooldownInfo.duration and cooldownInfo.duration > 1.5 then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        
        if spellInfo and spellInfo.iconID then
            if debugMode then print("SpellCD: Displaying cooldown for:", spellInfo.name) end
            icon:SetTexture(spellInfo.iconID)
            activeSpellID = spellID
            cooldownEndTime = cooldownInfo.startTime + cooldownInfo.duration
            
            -- Set hide time based on display duration setting
            local displayDuration = GetSetting("displayDuration")
            if displayDuration > 0 then
                hideTime = GetTime() + displayDuration
            else
                hideTime = 0  -- Never auto-hide
            end
            
            if isLocked then
                cooldownFrame:EnableMouse(false)
            end
            cooldownFrame:Show()
            UpdateCooldown()
        end
    end
end

-- Config panel
local configFrame = CreateFrame("Frame", "SpellCooldownConfig", UIParent)
configFrame.name = "SpellCooldown"

-- Create scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 3, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

-- Create scroll child
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(600, 800)
scrollFrame:SetScrollChild(scrollChild)

local title = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("SpellCooldown Settings")

-- Lock/Unlock button
local lockButton = CreateFrame("Button", "SpellCooldownLockButton", scrollChild, "UIPanelButtonTemplate")
lockButton:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
lockButton:SetSize(120, 25)
lockButton:SetText(isLocked and "Unlock Frame" or "Lock Frame")
lockButton:SetScript("OnClick", function(self)
    if isLocked then
        isLocked = false
        cooldownFrame:EnableMouse(true)
        cooldownFrame:Show()
        icon:SetTexture(136235)
        cooldownText:SetText("SpellCD")
        cooldownText:SetTextColor(0.5, 0.5, 0.5)
        activeSpellID = nil
        self:SetText("Lock Frame")
        print("|cFF00FF00SpellCooldown:|r Frame unlocked for positioning. Drag to move.")
    else
        isLocked = true
        cooldownFrame:EnableMouse(false)
        cooldownFrame:Hide()
        activeSpellID = nil
        self:SetText("Unlock Frame")
        print("|cFF00FF00SpellCooldown:|r Frame locked and hidden.")
    end
end)

-- Preview section
local previewLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
previewLabel:SetPoint("TOPLEFT", 320, -16)
previewLabel:SetText("Preview")

local previewFrame = CreateFrame("Frame", nil, scrollChild)
previewFrame:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -20)
previewFrame:SetSize(GetSetting("width"), GetSetting("height"))

-- Create preview border
local previewBorderFrame = CreateFrame("Frame", nil, previewFrame)
previewBorderFrame:SetFrameLevel(previewFrame:GetFrameLevel() - 1)

local previewBorderTexture = previewBorderFrame:CreateTexture(nil, "BACKGROUND")
previewBorderTexture:SetColorTexture(GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB"), 1)

local previewIcon = previewFrame:CreateTexture(nil, "ARTWORK")
previewIcon:SetAllPoints(previewFrame)
previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
previewIcon:SetTexture(136235) -- Fireball icon

local previewText = previewFrame:CreateFontString(nil, "OVERLAY")
previewText:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
previewText:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
previewText:SetText(GetSetting("showDecimals") and "8.5" or "8")
previewText:SetTextColor(GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"))

local function UpdatePreviewBorder()
    if GetSetting("borderEnabled") then
        local size = GetSetting("borderSize")
        previewBorderFrame:ClearAllPoints()
        previewBorderFrame:SetAllPoints(previewFrame)
        previewBorderTexture:ClearAllPoints()
        previewBorderTexture:SetPoint("TOPLEFT", previewBorderFrame, "TOPLEFT", -size, size)
        previewBorderTexture:SetPoint("BOTTOMRIGHT", previewBorderFrame, "BOTTOMRIGHT", size, -size)
        local r, g, b = GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB")
        previewBorderTexture:SetColorTexture(r, g, b, 1)
        previewBorderFrame:Show()
    else
        previewBorderFrame:Hide()
    end
end

UpdatePreviewBorder()

-- Width slider
local widthLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
widthLabel:SetPoint("TOPLEFT", lockButton, "BOTTOMLEFT", 0, -20)
widthLabel:SetText("Icon Width: " .. GetSetting("width") .. " px")

local widthSlider = CreateFrame("Slider", "SpellCooldownWidthSlider", scrollChild, "OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT", widthLabel, "BOTTOMLEFT", 0, -10)
widthSlider:SetMinMaxValues(32, 256)
widthSlider:SetValue(GetSetting("width"))
widthSlider:SetValueStep(8)
widthSlider:SetObeyStepOnDrag(true)
widthSlider:SetWidth(200)
_G[widthSlider:GetName().."Low"]:SetText("32")
_G[widthSlider:GetName().."High"]:SetText("256")
widthSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    SetSetting("width", value)
    cooldownFrame:SetWidth(value)
    previewFrame:SetWidth(value)
    widthLabel:SetText("Icon Width: " .. value .. " px")
    UpdatePreviewBorder()
end)

-- Height slider
local heightLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
heightLabel:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -30)
heightLabel:SetText("Icon Height: " .. GetSetting("height") .. " px")

local heightSlider = CreateFrame("Slider", "SpellCooldownHeightSlider", scrollChild, "OptionsSliderTemplate")
heightSlider:SetPoint("TOPLEFT", heightLabel, "BOTTOMLEFT", 0, -10)
heightSlider:SetMinMaxValues(32, 256)
heightSlider:SetValue(GetSetting("height"))
heightSlider:SetValueStep(8)
heightSlider:SetObeyStepOnDrag(true)
heightSlider:SetWidth(200)
_G[heightSlider:GetName().."Low"]:SetText("32")
_G[heightSlider:GetName().."High"]:SetText("256")
heightSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    SetSetting("height", value)
    cooldownFrame:SetHeight(value)
    previewFrame:SetHeight(value)
    heightLabel:SetText("Icon Height: " .. value .. " px")
    UpdatePreviewBorder()
end)

-- Font size slider
local fontSizeLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fontSizeLabel:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, -30)
fontSizeLabel:SetText("Font Size: " .. GetSetting("fontSize") .. " pt")

local fontSizeSlider = CreateFrame("Slider", "SpellCooldownFontSizeSlider", scrollChild, "OptionsSliderTemplate")
fontSizeSlider:SetPoint("TOPLEFT", fontSizeLabel, "BOTTOMLEFT", 0, -10)
fontSizeSlider:SetMinMaxValues(10, 48)
fontSizeSlider:SetValue(GetSetting("fontSize"))
fontSizeSlider:SetValueStep(2)
fontSizeSlider:SetObeyStepOnDrag(true)
fontSizeSlider:SetWidth(200)
_G[fontSizeSlider:GetName().."Low"]:SetText("10")
_G[fontSizeSlider:GetName().."High"]:SetText("48")
fontSizeSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    SetSetting("fontSize", value)
    cooldownText:SetFont("Fonts\\FRIZQT__.TTF", value, "OUTLINE")
    previewText:SetFont("Fonts\\FRIZQT__.TTF", value, "OUTLINE")
    fontSizeLabel:SetText("Font Size: " .. value .. " pt")
end)

-- Display duration slider
local durationLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
durationLabel:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -30)
local durText = GetSetting("displayDuration") == 0 and "Until cooldown ends" or (GetSetting("displayDuration") .. " sec")
durationLabel:SetText("Display Duration: " .. durText)

local durationSlider = CreateFrame("Slider", "SpellCooldownDurationSlider", scrollChild, "OptionsSliderTemplate")
durationSlider:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", 0, -10)
durationSlider:SetMinMaxValues(0, 30)
durationSlider:SetValue(GetSetting("displayDuration"))
durationSlider:SetValueStep(1)
durationSlider:SetObeyStepOnDrag(true)
durationSlider:SetWidth(200)
_G[durationSlider:GetName().."Low"]:SetText("0")
_G[durationSlider:GetName().."High"]:SetText("30")
durationSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    SetSetting("displayDuration", value)
    local text = value == 0 and "Until cooldown ends" or (value .. " sec")
    durationLabel:SetText("Display Duration: " .. text)
end)

local durationDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
durationDesc:SetPoint("TOPLEFT", durationSlider, "BOTTOMLEFT", 0, -5)
durationDesc:SetText("How long to show the icon after it appears.\nSet to 0 to show until cooldown ends.")

-- Text color picker
local colorLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
colorLabel:SetPoint("TOPLEFT", durationDesc, "BOTTOMLEFT", 0, -20)
colorLabel:SetText("Text Color:")

local colorButton = CreateFrame("Button", "SpellCooldownColorButton", scrollChild)
colorButton:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
colorButton:SetSize(32, 32)

local colorTexture = colorButton:CreateTexture(nil, "BACKGROUND")
colorTexture:SetAllPoints()
colorTexture:SetColorTexture(GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"))

local colorBorder = colorButton:CreateTexture(nil, "BORDER")
colorBorder:SetAllPoints()
colorBorder:SetColorTexture(1, 1, 1)

local colorInner = colorButton:CreateTexture(nil, "ARTWORK")
colorInner:SetPoint("TOPLEFT", 1, -1)
colorInner:SetPoint("BOTTOMRIGHT", -1, 1)
colorInner:SetColorTexture(GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"))

colorButton:SetScript("OnClick", function()
    local r, g, b = GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB")
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r,
        g = g,
        b = b,
        opacity = 1,
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            SetSetting("textColorR", newR)
            SetSetting("textColorG", newG)
            SetSetting("textColorB", newB)
            UpdateCachedColors()
            previewText:SetTextColor(newR, newG, newB)
            colorTexture:SetColorTexture(newR, newG, newB)
            colorInner:SetColorTexture(newR, newG, newB)
        end,
        cancelFunc = function()
            SetSetting("textColorR", r)
            SetSetting("textColorG", g)
            SetSetting("textColorB", b)
            UpdateCachedColors()
            previewText:SetTextColor(r, g, b)
            colorTexture:SetColorTexture(r, g, b)
            colorInner:SetColorTexture(r, g, b)
        end,
    })
end)

-- Border enabled checkbox
local borderCheckbox = CreateFrame("CheckButton", "SpellCooldownBorderCheckbox", scrollChild, "UICheckButtonTemplate")
borderCheckbox:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -40)
borderCheckbox:SetChecked(GetSetting("borderEnabled"))
_G[borderCheckbox:GetName().."Text"]:SetText("Show Border")
borderCheckbox:SetScript("OnClick", function(self)
    SetSetting("borderEnabled", self:GetChecked())
    UpdateBorder()
    UpdatePreviewBorder()
end)

-- Border color picker
local borderColorLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
borderColorLabel:SetPoint("TOPLEFT", borderCheckbox, "BOTTOMLEFT", 0, -20)
borderColorLabel:SetText("Border Color:")

local borderColorButton = CreateFrame("Button", "SpellCooldownBorderColorButton", scrollChild)
borderColorButton:SetPoint("LEFT", borderColorLabel, "RIGHT", 10, 0)
borderColorButton:SetSize(32, 32)

local borderColorTexture = borderColorButton:CreateTexture(nil, "BACKGROUND")
borderColorTexture:SetAllPoints()
borderColorTexture:SetColorTexture(GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB"))

local borderColorBorder = borderColorButton:CreateTexture(nil, "BORDER")
borderColorBorder:SetAllPoints()
borderColorBorder:SetColorTexture(1, 1, 1)

local borderColorInner = borderColorButton:CreateTexture(nil, "ARTWORK")
borderColorInner:SetPoint("TOPLEFT", 1, -1)
borderColorInner:SetPoint("BOTTOMRIGHT", -1, 1)
borderColorInner:SetColorTexture(GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB"))

borderColorButton:SetScript("OnClick", function()
    local r, g, b = GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB")
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r,
        g = g,
        b = b,
        opacity = 1,
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            SetSetting("borderColorR", newR)
            SetSetting("borderColorG", newG)
            SetSetting("borderColorB", newB)
            borderColorTexture:SetColorTexture(newR, newG, newB)
            borderColorInner:SetColorTexture(newR, newG, newB)
            UpdateBorder()
            UpdatePreviewBorder()
        end,
        cancelFunc = function()
            SetSetting("borderColorR", r)
            SetSetting("borderColorG", g)
            SetSetting("borderColorB", b)
            borderColorTexture:SetColorTexture(r, g, b)
            borderColorInner:SetColorTexture(r, g, b)
            UpdateBorder()
            UpdatePreviewBorder()
        end,
    })
end)

-- Border size slider
local borderSizeLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
borderSizeLabel:SetPoint("TOPLEFT", borderColorLabel, "BOTTOMLEFT", 0, -40)
borderSizeLabel:SetText("Border Size: " .. GetSetting("borderSize") .. " px")

local borderSizeSlider = CreateFrame("Slider", "SpellCooldownBorderSizeSlider", scrollChild, "OptionsSliderTemplate")
borderSizeSlider:SetPoint("TOPLEFT", borderSizeLabel, "BOTTOMLEFT", 0, -10)
borderSizeSlider:SetMinMaxValues(1, 10)
borderSizeSlider:SetValue(GetSetting("borderSize"))
borderSizeSlider:SetValueStep(1)
borderSizeSlider:SetObeyStepOnDrag(true)
borderSizeSlider:SetWidth(200)
_G[borderSizeSlider:GetName().."Low"]:SetText("1")
_G[borderSizeSlider:GetName().."High"]:SetText("10")
borderSizeSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    SetSetting("borderSize", value)
    borderSizeLabel:SetText("Border Size: " .. value .. " px")
    UpdateBorder()
    UpdatePreviewBorder()
end)

-- Show decimals checkbox
local decimalsCheckbox = CreateFrame("CheckButton", "SpellCooldownDecimalsCheckbox", scrollChild, "UICheckButtonTemplate")
decimalsCheckbox:SetPoint("TOPLEFT", borderSizeSlider, "BOTTOMLEFT", 0, -30)
decimalsCheckbox:SetChecked(GetSetting("showDecimals"))
_G[decimalsCheckbox:GetName().."Text"]:SetText("Show Decimal Seconds")
decimalsCheckbox:SetScript("OnClick", function(self)
    SetSetting("showDecimals", self:GetChecked())
    if self:GetChecked() then
        previewText:SetText("8.5")
    else
        previewText:SetText("8")
    end
end)

local decimalsDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
decimalsDesc:SetPoint("TOPLEFT", decimalsCheckbox, "BOTTOMLEFT", 20, -5)
decimalsDesc:SetText("Show decimals for seconds (e.g., 1.4) or whole numbers (e.g., 1).")

-- Debug mode checkbox
local debugCheckbox = CreateFrame("CheckButton", "SpellCooldownDebugCheckbox", scrollChild, "UICheckButtonTemplate")
debugCheckbox:SetPoint("TOPLEFT", decimalsDesc, "BOTTOMLEFT", -20, -10)
debugCheckbox:SetChecked(debugMode)
_G[debugCheckbox:GetName().."Text"]:SetText("Debug Mode")
debugCheckbox:SetScript("OnClick", function(self)
    debugMode = self:GetChecked()
    print("|cFF00FF00SpellCooldown:|r Debug mode " .. (debugMode and "enabled" or "disabled"))
end)

local debugDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugDesc:SetPoint("TOPLEFT", debugCheckbox, "BOTTOMLEFT", 20, -5)
debugDesc:SetText("Prints detailed spell detection info to chat.")

-- Register config
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, "SpellCooldown")
    Settings.RegisterAddOnCategory(category)
else
    InterfaceOptions_AddCategory(configFrame)
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if unit == "player" and spellID then
            if debugMode then print("SpellCD: UNIT_SPELLCAST_SUCCEEDED - Spell ID:", spellID) end
            CheckAndDisplayCooldown(spellID)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Restore saved position
        if SpellCooldownDB.position then
            cooldownFrame:ClearAllPoints()
            cooldownFrame:SetPoint(
                SpellCooldownDB.position.point,
                UIParent,
                SpellCooldownDB.position.relativePoint,
                SpellCooldownDB.position.x,
                SpellCooldownDB.position.y
            )
        end
        
        -- Restore size and font
        cooldownFrame:SetSize(GetSetting("width"), GetSetting("height"))
        cooldownText:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
        UpdateCachedColors()
        UpdateBorder()
        
        print("|cFF00FF00SpellCooldown|r addon loaded! Configure in Game Menu > Options > AddOns > SpellCooldown")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Restore size and font on zone change
        cooldownFrame:SetSize(GetSetting("width"), GetSetting("height"))
        cooldownText:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
        UpdateCachedColors()
        UpdateBorder()
    end
end)

-- Hook into spell casts
hooksecurefunc("UseAction", function(slot, target, button)
    if debugMode then print("SpellCD: UseAction called, slot:", slot) end
    
    local actionType, id, subType = GetActionInfo(slot)
    
    if debugMode then print("SpellCD: Action type:", actionType, "ID:", id) end
    
    if actionType == "spell" then
        CheckAndDisplayCooldown(id)
    elseif actionType == "macro" then
        -- First try to get the spell from the macro
        local macroSpell = GetMacroSpell(id)
        if macroSpell then
            local spellID = C_Spell.GetSpellIDForSpellIdentifier(macroSpell)
            if spellID then
                if debugMode then print("SpellCD: Macro contains spell ID:", spellID) end
                CheckAndDisplayCooldown(spellID)
            end
        else
            -- Sometimes the id is the spell ID itself when a spell is in a macro slot
            -- Try to use the id directly as a spell ID
            if debugMode then print("SpellCD: Trying id as spell ID:", id) end
            CheckAndDisplayCooldown(id)
        end
    elseif actionType == "item" then
        local start, duration = C_Container.GetItemCooldown(id)
        if duration and duration > 1.5 then
            local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(id)
            if itemIcon then
                if debugMode then print("SpellCD: Item on cooldown:", itemName) end
                icon:SetTexture(itemIcon)
                activeSpellID = id
                cooldownEndTime = start + duration
                
                local displayDuration = GetSetting("displayDuration")
                if displayDuration > 0 then
                    hideTime = GetTime() + displayDuration
                else
                    hideTime = 0
                end
                
                if isLocked then
                    cooldownFrame:EnableMouse(false)
                end
                cooldownFrame:Show()
                UpdateCooldown()
            end
        end
    end
end)

-- Make frame draggable
cooldownFrame:SetMovable(true)
cooldownFrame:EnableMouse(false)
cooldownFrame:RegisterForDrag("LeftButton")
cooldownFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
cooldownFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    SpellCooldownDB.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end)
