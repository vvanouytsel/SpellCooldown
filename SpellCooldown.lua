local addonName, addon = ...

-- ==========================================================================
-- Client flavor detection and API compatibility
--
-- Retail (Midnight, 12.0+) hides the player's own cooldown numbers behind
-- "secret values" whenever cooldown access is restricted. Tainted code may
-- hold such a value but may not do arithmetic or comparisons on it, which is
-- what used to break this addon in combat. The countdown is therefore driven
-- through one of two modes:
--
--   * duration - preferred wherever available (Retail 12.0.7+). A DurationObject
--                is bound to the countdown FontString and the client keeps the
--                text updated itself, so no secret value is ever read or
--                formatted here. Used in and out of combat alike, so the display
--                behaves identically either way.
--   * numeric  - the fallback for clients without those APIs (Classic). The
--                remaining time is computed here, as it always was.
--
-- The gating decision ("is this actually on cooldown?") uses only fields
-- Blizzard flags as NeverSecret, so it stays legal in both modes.
--
-- Classic flavors such as TBC Anniversary (2.5.5) lack most of the modern C_*
-- namespaces, hence the feature-detected wrappers below.
--
-- WoW Forever (interface 16001, project "Camelot") runs on the Mainline API and
-- has the same secret values, so it takes the Retail path. It reports its own
-- WOW_PROJECT_ID rather than WOW_PROJECT_MAINLINE, which is why the Retail
-- check below looks for the restriction API instead of the project ID.
-- ==========================================================================
local hasCombatRestrictions = issecretvalue ~= nil

-- Anything at or below this is the global cooldown rather than a real cooldown
local GCD_THRESHOLD = 1.5

local IsSecretValue = issecretvalue or function() return false end
local IsSecretTable = issecrettable or function() return false end

-- True when the value is present and tainted code may safely do math on it
local function IsPlainNumber(value)
    if IsSecretValue(value) then return false end
    return value ~= nil
end

-- Returns the raw cooldown info table for a spell, or nil if it is unreadable.
-- Individual fields may still be secret; guard them with IsPlainNumber.
local GetSpellCooldownInfo
if C_Spell and C_Spell.GetSpellCooldown then
    GetSpellCooldownInfo = function(spellID)
        local info = C_Spell.GetSpellCooldown(spellID)
        -- Indexing a secret table throws, so refuse it outright
        if not info or IsSecretTable(info) then return nil end
        return info
    end
else
    GetSpellCooldownInfo = function(spellID)
        local startTime, duration, enabled = GetSpellCooldown(spellID)
        if not startTime then return nil end
        return { startTime = startTime, duration = duration, isEnabled = enabled }
    end
end

-- Returns name, icon for a spell
local GetSpellDisplayInfo
if C_Spell and C_Spell.GetSpellInfo then
    GetSpellDisplayInfo = function(spellID)
        local info = C_Spell.GetSpellInfo(spellID)
        if not info then return nil end
        return info.name, info.iconID
    end
else
    GetSpellDisplayInfo = function(spellID)
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
end

-- Resolves a spell name (e.g. from a macro) to a spell ID
local function GetSpellIDFromIdentifier(identifier)
    if not identifier then return nil end
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        return C_Spell.GetSpellIDForSpellIdentifier(identifier)
    end
    if GetSpellInfo then
        -- Classic: the 7th return of GetSpellInfo is the spell ID
        return select(7, GetSpellInfo(identifier))
    end
    return nil
end

local GetItemCooldownCompat = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ==========================================================================
-- Duration objects (Retail 12.0+)
--
-- A DurationObject is an opaque, self-updating time span. Only the client may
-- turn one into text, which is what makes it the only way to render a cooldown
-- whose numbers are secret.
-- ==========================================================================
local hasSpellCooldownDuration = (C_Spell and C_Spell.GetSpellCooldownDuration) ~= nil

-- The ignoreGCD argument was added in 12.0.5; drop it if the client rejects it
local passIgnoreGCD = true
local function GetSpellCooldownDurationObject(spellID)
    if not hasSpellCooldownDuration then return nil end

    if passIgnoreGCD then
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        if ok then return duration end
        passIgnoreGCD = false
    end

    local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if ok then return duration end
    return nil
end

-- Wraps a readable start/end pair (items) in a duration object, so everything
-- can go through the same renderer
local function CreateSpanDuration(startTime, endTime)
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end

    local ok, duration = pcall(C_DurationUtil.CreateDuration)
    if not ok or not duration then return nil end
    if not pcall(duration.SetTimeSpan, duration, startTime, endTime) then return nil end
    return duration
end

-- Whether the spell is on a real cooldown rather than just the global cooldown.
-- Returns nil when the answer cannot be determined at all.
local function IsOnRealCooldown(info)
    if not info then return false end

    -- When the numbers are readable, filter exactly as this addon always has,
    -- so a bare global cooldown never triggers the display
    local startTime, duration = info.startTime, info.duration
    if IsPlainNumber(startTime) and IsPlainNumber(duration) then
        return startTime > 0 and duration > GCD_THRESHOLD
    end

    -- Restricted: fall back to the fields Blizzard flags as NeverSecret
    if info.isOnGCD then return false end
    if info.isActive ~= nil and not IsSecretValue(info.isActive) then
        return info.isActive and true or false
    end
    return nil
end

-- Color picker: the table-based API only exists on newer clients
local function ShowColorPicker(r, g, b, onChanged, onCancel)
    local info = {
        r = r,
        g = g,
        b = b,
        opacity = 1,
        hasOpacity = false,
        swatchFunc = function()
            onChanged(ColorPickerFrame:GetColorRGB())
        end,
        -- Close over the original values instead of relying on previousValues,
        -- whose shape differs between clients
        cancelFunc = function()
            onCancel(r, g, b)
        end,
    }

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    elseif OpenColorPicker then
        OpenColorPicker(info)
    else
        ColorPickerFrame.func = info.swatchFunc
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

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

-- ==========================================================================
-- Countdown rendering (Retail 12.0+)
--
-- A Cooldown widget is fed the opaque DurationObject and renders the countdown
-- itself. Nothing else can: every Lua-side route to text needs a client-made
-- formatter object, and none of those produce the plain rounded seconds this
-- addon has always shown. A SecondsFormatter always appends a unit ("55Sec",
-- "55s", "55 seconds") and a number formatter emits the raw float ("32.456").
-- Blizzard's own cooldown text is already exactly the wanted format.
--
-- Caveat: those numbers are gated behind the countdownForCooldowns CVar.
-- SetHideCountdownNumbers(false) un-suppresses them but cannot override that
-- master switch, so the addon checks it and falls back where it can.
-- ==========================================================================

-- The widget takes a Font object by name, so size and colour are carried there
-- rather than being applied to a FontString directly
local countdownFont = CreateFont("SpellCooldownCountdownFont")

local function ApplyCountdownFont()
    countdownFont:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
    countdownFont:SetTextColor(GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"))
end

ApplyCountdownFont()

local cooldownWidget
do
    local widget = CreateFrame("Cooldown", "SpellCooldownCountdown", cooldownFrame, "CooldownFrameTemplate")
    if widget.SetCooldownFromDurationObject then
        widget:SetAllPoints(cooldownFrame)
        -- Used purely as a countdown; the addon draws its own icon and border
        widget:SetDrawSwipe(false)
        widget:SetDrawEdge(false)
        widget:SetDrawBling(false)
        widget:SetHideCountdownNumbers(false)
        pcall(widget.SetCountdownFont, widget, countdownFont:GetName())
        -- Switch to minutes above a minute, matching the old local formatting
        pcall(widget.SetCountdownAbbrevThreshold, widget, 60)
        pcall(widget.SetMinimumCountdownDuration, widget, 0)
        -- SetHideCountdownNumbers is known to stop applying after a resize
        widget:HookScript("OnSizeChanged", function(self)
            self:SetHideCountdownNumbers(false)
        end)
        cooldownWidget = widget
    else
        widget:Hide()
    end
end

-- Sub-second precision is the widget's decision, so it has to be reapplied
-- whenever the decimals setting changes
local function ConfigureCountdown()
    if not cooldownWidget then return end
    -- Show decimals below this many milliseconds remaining; 0 disables them
    pcall(cooldownWidget.SetCountdownMillisecondsThreshold, cooldownWidget,
        GetSetting("showDecimals") and 10000 or 0)
end

ConfigureCountdown()

-- The widget draws nothing without the CVar, so there is no point preferring it
-- over locally formatted numbers in that case
local function CanDrawCountdown()
    if not cooldownWidget then return false end
    if GetCVarBool and not GetCVarBool("countdownForCooldowns") then return false end
    return true
end

local function ClearCountdown()
    if cooldownWidget then
        pcall(cooldownWidget.Clear, cooldownWidget)
    end
end

-- Hands a duration object to the widget. Returns false if that is not possible,
-- in which case the caller falls back to formatting readable numbers itself.
local function ShowDurationObject(durationObject)
    if not durationObject or not CanDrawCountdown() then return false end
    local ok = pcall(cooldownWidget.SetCooldownFromDurationObject, cooldownWidget, durationObject, true)
    if not ok then
        ClearCountdown()
        return false
    end
    -- The widget owns the number now
    cooldownText:SetText("")
    return true
end

-- Variables
local activeSpellID = nil
local displayMode = nil         -- "numeric" | "duration"
local cooldownEndTime = 0       -- 0 when the remaining time is not readable
local hideTime = 0
local activeSince = 0
local nextStateCheck = 0
local canPollActive = false
local debugMode = false
local isLocked = true
local cachedTextColorR, cachedTextColorG, cachedTextColorB

-- Cache text colors to avoid GetSetting calls in OnUpdate
local function UpdateCachedColors()
    cachedTextColorR = GetSetting("textColorR")
    cachedTextColorG = GetSetting("textColorG")
    cachedTextColorB = GetSetting("textColorB")
    cooldownText:SetTextColor(cachedTextColorR, cachedTextColorG, cachedTextColorB)
    ApplyCountdownFont()
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

local function HideDisplay()
    cooldownFrame:Hide()
    ClearCountdown()
    -- Never leave text behind that a later activation could show as its own
    cooldownText:SetText("")
    activeSpellID = nil
    displayMode = nil
    cooldownEndTime = 0
    hideTime = 0
    canPollActive = false
end

-- Update cooldown display
local function UpdateCooldown()
    local currentTime = GetTime()

    -- Check if we should hide based on display duration
    if hideTime > 0 and currentTime >= hideTime then
        HideDisplay()
        return
    end

    -- Known end time, whichever mode is drawing the text
    if cooldownEndTime > 0 and currentTime >= cooldownEndTime then
        HideDisplay()
        return
    end

    if displayMode == "numeric" then
        cooldownText:SetText(FormatCooldownTime(cooldownEndTime - currentTime))
        return
    end

    -- "duration" mode: the binding keeps the text current on its own, so all
    -- that is left is deciding when to stop. The remaining time is secret here,
    -- so poll the NeverSecret isActive flag instead. GetSpellCooldown lags a
    -- moment behind a cast, hence the grace period before the first check.
    if canPollActive and currentTime >= nextStateCheck and (currentTime - activeSince) > 0.3 then
        nextStateCheck = currentTime + 0.1
        local info = GetSpellCooldownInfo(activeSpellID)
        if not info or not info.isActive then
            HideDisplay()
        end
    end
end

-- OnUpdate handler
local function OnUpdateHandler(self, elapsed)
    if activeSpellID then
        UpdateCooldown()
    end
end

cooldownFrame:SetScript("OnUpdate", OnUpdateHandler)

-- Common setup for a freshly triggered display
local function Activate(iconTexture)
    icon:SetTexture(iconTexture)

    -- Set hide time based on display duration setting
    local displayDuration = GetSetting("displayDuration")
    if displayDuration > 0 then
        hideTime = GetTime() + displayDuration
    else
        hideTime = 0  -- Never auto-hide
    end

    activeSince = GetTime()
    nextStateCheck = 0

    if isLocked then
        cooldownFrame:EnableMouse(false)
    end
    cooldownFrame:Show()
    UpdateCooldown()
end

-- Check if spell is on cooldown and display it
local function CheckAndDisplayCooldown(spellID)
    if not spellID then
        if debugMode then print("SpellCD: No spell ID") end
        return
    end

    local info = GetSpellCooldownInfo(spellID)
    local onCooldown = IsOnRealCooldown(info)

    if debugMode then
        print("SpellCD: Checking spell ID:", spellID)
        print("SpellCD: In combat:", InCombatLockdown() and "YES" or "NO")
        print("SpellCD: On cooldown:", tostring(onCooldown))
        print("SpellCD: Values readable:", (info and IsPlainNumber(info.duration)) and "YES" or "NO")
    end

    if not info or not onCooldown then return end

    local spellName, spellIcon = GetSpellDisplayInfo(spellID)
    if not spellIcon then return end

    local readable = IsPlainNumber(info.startTime) and IsPlainNumber(info.duration)

    -- Prefer the widget even when the numbers are readable, so the countdown
    -- looks and ticks the same in and out of combat
    if ShowDurationObject(GetSpellCooldownDurationObject(spellID)) then
        displayMode = "duration"
        activeSpellID = spellID
        -- With a readable end time we can hide precisely; otherwise fall back to
        -- polling isActive, which is the only non-secret signal available
        cooldownEndTime = readable and (info.startTime + info.duration) or 0
        canPollActive = not readable and info.isActive ~= nil
        if cooldownEndTime == 0 and not canPollActive then
            -- Nothing would ever tell us to stop showing it
            if debugMode then print("SpellCD: No way to detect the end of the cooldown for:", spellName) end
            HideDisplay()
            return
        end
    elseif readable then
        ClearCountdown()
        displayMode = "numeric"
        activeSpellID = spellID
        cooldownEndTime = info.startTime + info.duration
        canPollActive = false
    else
        if debugMode then print("SpellCD: Cooldown is secret and cannot be displayed for:", spellName) end
        return
    end

    if debugMode then print("SpellCD: Displaying cooldown for:", spellName, "mode:", displayMode) end
    Activate(spellIcon)
end

-- Items are not part of the automation surface Blizzard restricts, so their
-- cooldowns are normally readable. Skip rather than error if that ever changes.
local function CheckAndDisplayItemCooldown(itemID)
    if not (GetItemCooldownCompat and GetItemInfoCompat) then return end

    local startTime, duration = GetItemCooldownCompat(itemID)
    if not (IsPlainNumber(startTime) and IsPlainNumber(duration)) then
        if debugMode then print("SpellCD: Item cooldown unreadable for ID:", itemID) end
        return
    end
    if startTime <= 0 or duration <= GCD_THRESHOLD then return end

    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoCompat(itemID)
    if not itemIcon then return end

    if debugMode then print("SpellCD: Item on cooldown:", itemName) end

    -- Wrap the readable numbers in a duration object so items render through the
    -- same path as spells; fall back to formatting them here if that fails
    local endTime = startTime + duration
    if ShowDurationObject(CreateSpanDuration(startTime, endTime)) then
        displayMode = "duration"
    else
        ClearCountdown()
        displayMode = "numeric"
    end
    activeSpellID = itemID
    cooldownEndTime = endTime
    canPollActive = false
    Activate(itemIcon)
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
        -- Clearing the active state first stops OnUpdate overwriting the placeholder
        HideDisplay()
        cooldownFrame:EnableMouse(true)
        cooldownFrame:Show()
        icon:SetTexture(136235)
        cooldownText:SetText("SpellCD")
        cooldownText:SetTextColor(0.5, 0.5, 0.5)
        self:SetText("Lock Frame")
        print("|cFF00FF00SpellCooldown:|r Frame unlocked for positioning. Drag to move.")
    else
        isLocked = true
        cooldownFrame:EnableMouse(false)
        HideDisplay()
        -- Undo the greyed-out placeholder colour
        cooldownText:SetTextColor(cachedTextColorR, cachedTextColorG, cachedTextColorB)
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
    ApplyCountdownFont()
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

local function ApplyTextColor(r, g, b)
    SetSetting("textColorR", r)
    SetSetting("textColorG", g)
    SetSetting("textColorB", b)
    UpdateCachedColors()
    previewText:SetTextColor(r, g, b)
    colorTexture:SetColorTexture(r, g, b)
    colorInner:SetColorTexture(r, g, b)
end

colorButton:SetScript("OnClick", function()
    ShowColorPicker(
        GetSetting("textColorR"), GetSetting("textColorG"), GetSetting("textColorB"),
        ApplyTextColor,
        ApplyTextColor
    )
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

local function ApplyBorderColor(r, g, b)
    SetSetting("borderColorR", r)
    SetSetting("borderColorG", g)
    SetSetting("borderColorB", b)
    borderColorTexture:SetColorTexture(r, g, b)
    borderColorInner:SetColorTexture(r, g, b)
    UpdateBorder()
    UpdatePreviewBorder()
end

borderColorButton:SetScript("OnClick", function()
    ShowColorPicker(
        GetSetting("borderColorR"), GetSetting("borderColorG"), GetSetting("borderColorB"),
        ApplyBorderColor,
        ApplyBorderColor
    )
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
    ConfigureCountdown()
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
local settingsCategory
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, "SpellCooldown")
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(configFrame)
end

-- Slash command: AddOn options live in different places per client build
SLASH_SPELLCOOLDOWN1 = "/spellcooldown"
SLASH_SPELLCOOLDOWN2 = "/spellcd"
SlashCmdList["SPELLCOOLDOWN"] = function()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice to work around a long-standing Blizzard bug
        InterfaceOptionsFrame_OpenToCategory(configFrame)
        InterfaceOptionsFrame_OpenToCategory(configFrame)
    else
        print("|cFF00FF00SpellCooldown:|r Could not open the options panel on this client.")
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- The player's own spellcasts are not secret, even in combat
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
        if hasCombatRestrictions and not cooldownWidget then
            print("|cFF00FF00SpellCooldown:|r This client cannot render restricted cooldowns, so the display is unavailable while Blizzard's combat restrictions are active.")
        elseif hasCombatRestrictions and not CanDrawCountdown() then
            print("|cFF00FF00SpellCooldown:|r Turn on \"Show Numbers for Cooldowns\" in Options > ActionBars. Blizzard gates all cooldown countdown text behind it, so without it the timer cannot be drawn in combat.")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Restore size and font on zone change
        cooldownFrame:SetSize(GetSetting("width"), GetSetting("height"))
        cooldownText:SetFont("Fonts\\FRIZQT__.TTF", GetSetting("fontSize"), "OUTLINE")
        UpdateCachedColors()
        UpdateBorder()
    end
end)

-- Hook into spell casts. This is the trigger that matters: a spell that is
-- already on cooldown never casts, so UNIT_SPELLCAST_SUCCEEDED will not fire.
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
            local spellID = GetSpellIDFromIdentifier(macroSpell)
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
        CheckAndDisplayItemCooldown(id)
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
