-------------------------------------------------------------------------------
--  EllesmereUIBasics_EncounterTimer.lua
--  Encounter timer module for EllesmereUIBasics.
--
--  Tracks boss pull duration using ENCOUNTER_START / ENCOUNTER_END events.
--  An optional "combat" trigger mode uses PLAYER_REGEN_DISABLED / ENABLED
--  for any combat, including trash.
--
--  Performance contract:
--    • No OnUpdate.  A C_Timer.NewTicker(0.1) runs ONLY during an active
--      encounter and is cancelled immediately on pull end.
--    • Between pulls the frame is fully Hide()'d — zero render cost.
--    • Event handlers are always registered but guard with early returns;
--      ENCOUNTER_START/END and PLAYER_REGEN_* fire infrequently.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Local state
-------------------------------------------------------------------------------
local _etFrame, _etBg, _etNameFS, _etTimerFS
local _framesCreated = false

local _ticker        = nil    -- C_Timer.NewTicker handle; nil when not active
local _startTime     = nil    -- GetTime() snapshot at pull start
local _inEncounter   = false  -- true only while timer is running
local _encounterName = nil    -- boss name from ENCOUNTER_START (nil in combat mode)

-------------------------------------------------------------------------------
--  DB helpers
-------------------------------------------------------------------------------
local function DB()
    local ace = _G._EBS_AceDB
    return ace and ace.profile and ace.profile.encounterTimer
end

local function Cfg(k)
    local d = DB()
    return d and d[k]
end

-------------------------------------------------------------------------------
--  Font helpers  (exact pattern from EllesmereUIBasics_QuestTracker.lua)
-------------------------------------------------------------------------------
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"

-- Validates a font path; rejects OTF (WoW only supports TTF/TGA)
local function SafeFont(p)
    if not p or p == "" then return FALLBACK_FONT end
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return FALLBACK_FONT end
    return p
end

-- Returns the resolved EllesmereUI global font path (safe, never OTF)
local function GlobalFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return SafeFont(EllesmereUI.GetFontPath("unitFrames"))
    end
    return FALLBACK_FONT
end

-- Sets font on a FontString with the full fallback chain
local function SetFontSafe(fs, path, size, flags)
    if not fs then return end
    local safePath = SafeFont(path)
    size  = size  or 14
    flags = flags or "NONE"
    local curPath, curSize, curFlags = fs:GetFont()
    if curPath == safePath and curSize == size and (curFlags or "NONE") == flags then return end
    fs:SetFont(safePath, size, flags)
    if not fs:GetFont() then fs:SetFont("Fonts/FRIZQT__.TTF",  size, flags) end
    if not fs:GetFont() then fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags) end
    if not fs:GetFont() then
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fs:SetFont(gf, size, flags) end
    end
end

-- Applies shadow setting independently of the font call
local function ApplyShadow(fs, shadow)
    if not fs then return end
    if shadow then
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

-------------------------------------------------------------------------------
--  Ticker  (the only recurring work this module does)
-------------------------------------------------------------------------------
local function FormatTime(elapsed)
    local m = math.floor(elapsed / 60)
    local s = math.floor(elapsed % 60)
    return string.format("%d:%02d", m, s)
end

local function StartTicker()
    if _ticker then _ticker:Cancel() end
    _ticker = C_Timer.NewTicker(0.1, function()
        if not _startTime or not _etTimerFS then return end
        _etTimerFS:SetText(FormatTime(GetTime() - _startTime))
    end)
end

local function StopTicker()
    if _ticker then _ticker:Cancel(); _ticker = nil end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function UpdateEncounterTimerVisibility()
    if not _etFrame then return end
    local d = DB()
    if not d or not d.enabled then
        _etFrame:Hide()
        return
    end
    -- If showWhenIdle is off, hide entirely when no encounter is active
    if not _inEncounter and not d.showWhenIdle then
        _etFrame:Hide()
        return
    end
    -- Delegate to the shared EvalVisibility function exposed by EllesmereUIBasics.lua
    local evalFn = _G._EBS_EvalVisibility
    if evalFn then
        local vis = evalFn(d)
        if vis then
            _etFrame:Show()
        else
            _etFrame:Hide()
        end
    else
        _etFrame:Show()
    end
end
_G._EBS_UpdateETVisibility = UpdateEncounterTimerVisibility

-------------------------------------------------------------------------------
--  Frame auto-sizing  (fits the frame snugly around the text content)
-------------------------------------------------------------------------------
local function ResizeFrame()
    if not _etFrame or not _etTimerFS then return end

    -- Measure timer width using the widest realistic string at current font size.
    -- Save and restore the live text so the display isn't disturbed.
    local prevText = _etTimerFS:GetText() or ""
    _etTimerFS:SetText("00:00")
    local timerW = math.ceil(_etTimerFS:GetStringWidth())
    local timerH = math.ceil(_etTimerFS:GetStringHeight())
    _etTimerFS:SetText(prevText)

    -- Ensure sane minimums even if the font failed to load
    timerW = math.max(timerW, 40)
    timerH = math.max(timerH, 16)

    local padX, padY = 14, 10
    local frameW = timerW + padX * 2
    local frameH = timerH + padY * 2

    -- If the name string is currently visible, account for its height
    if _etNameFS and _etNameFS:IsShown() then
        local nameW = math.ceil(_etNameFS:GetStringWidth())
        local nameH = math.ceil(_etNameFS:GetStringHeight())
        frameW = math.max(frameW, nameW + padX * 2)
        frameH = frameH + nameH + 6
    end

    _etFrame:SetSize(math.max(frameW, 60), math.max(frameH, 30))
end

-------------------------------------------------------------------------------
--  Timer display update  (repositions font strings, sets idle text, resizes)
-------------------------------------------------------------------------------
local function UpdateTimerDisplay()
    if not _etTimerFS then return end
    local showName = Cfg("showEncounterName") and _encounterName
    -- Name font string
    if _etNameFS then
        if showName then
            _etNameFS:SetText(_encounterName)
            _etNameFS:Show()
        else
            _etNameFS:SetText("")
            _etNameFS:Hide()
        end
    end
    -- Reposition timer font string
    _etTimerFS:ClearAllPoints()
    if showName then
        _etTimerFS:SetPoint("BOTTOM", _etFrame, "BOTTOM", 0, 6)
    else
        _etTimerFS:SetPoint("CENTER", _etFrame, "CENTER", 0, 0)
    end
    -- Idle text when not in an encounter
    if not _inEncounter then
        _etTimerFS:SetText(Cfg("showWhenIdle") and "0:00" or "")
    end
    -- Fit frame to content
    ResizeFrame()
end

-------------------------------------------------------------------------------
--  Apply  (create + refresh; called at login and whenever options change)
-------------------------------------------------------------------------------
local function ApplyEncounterTimer()
    local d = DB()
    if not d then return end

    ---------------------------------------------------------------------------
    --  One-time frame creation (lazy)
    ---------------------------------------------------------------------------
    if not _framesCreated then
        _framesCreated = true

        -- Container frame (size is driven by ResizeFrame(), not hardcoded)
        _etFrame = CreateFrame("Frame", "EBS_EncounterTimerFrame", UIParent)
        _etFrame:SetSize(80, 40)   -- placeholder; overwritten by ResizeFrame()
        _etFrame:SetFrameStrata("HIGH")
        _etFrame:SetClampedToScreen(true)

        -- Semi-transparent background  (extends 4 px outside the frame)
        _etBg = _etFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        _etBg:SetColorTexture(0, 0, 0)
        _etBg:SetPoint("TOPLEFT",     _etFrame, "TOPLEFT",      -4,  4)
        _etBg:SetPoint("BOTTOMRIGHT", _etFrame, "BOTTOMRIGHT",   4, -4)

        -- Encounter name  (shown above the timer when enabled)
        _etNameFS = _etFrame:CreateFontString(nil, "OVERLAY")
        _etNameFS:SetPoint("TOP", _etFrame, "TOP", 0, -6)
        _etNameFS:SetJustifyH("CENTER")
        _etNameFS:Hide()

        -- Timer display (no SetText here — font must be applied first)
        _etTimerFS = _etFrame:CreateFontString(nil, "OVERLAY")
        _etTimerFS:SetPoint("CENTER", _etFrame, "CENTER", 0, 0)
        _etTimerFS:SetJustifyH("CENTER")

        -- Default anchor (center of screen, slightly above middle)
        _etFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    ---------------------------------------------------------------------------
    --  Position
    ---------------------------------------------------------------------------
    local pos = d.position
    _etFrame:ClearAllPoints()
    if pos and pos.point then
        _etFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        _etFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    ---------------------------------------------------------------------------
    --  Font  (face from EllesmereUI global, size/outline/shadow per-module)
    ---------------------------------------------------------------------------
    local fontSize = d.fontSize    or 28
    local outline  = (d.fontOutline and d.fontOutline ~= "") and d.fontOutline or "NONE"
    local shadow   = d.fontShadow  ~= false
    local fontPath = GlobalFont()

    SetFontSafe(_etTimerFS, fontPath, fontSize, outline)
    SetFontSafe(_etNameFS,  fontPath, math.max(fontSize - 6, 12), outline)
    ApplyShadow(_etTimerFS, shadow)
    ApplyShadow(_etNameFS,  shadow)

    ---------------------------------------------------------------------------
    --  Text color
    ---------------------------------------------------------------------------
    local r, g, b = d.r or 1, d.g or 1, d.b or 1
    if d.useClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then r, g, b = cc.r, cc.g, cc.b end
    end
    if _etTimerFS then _etTimerFS:SetTextColor(r, g, b, 1) end
    if _etNameFS  then _etNameFS:SetTextColor(r, g, b, 1)  end

    ---------------------------------------------------------------------------
    --  Background alpha
    ---------------------------------------------------------------------------
    if _etBg then
        _etBg:SetAlpha((d.showBg ~= false) and (d.bgAlpha or 0.5) or 0)
    end

    UpdateTimerDisplay()
    UpdateEncounterTimerVisibility()
end
_G._EBS_ApplyEncounterTimer = ApplyEncounterTimer

-------------------------------------------------------------------------------
--  Event handler frame
-------------------------------------------------------------------------------
local etEventFrame = CreateFrame("Frame")

etEventFrame:RegisterEvent("PLAYER_LOGIN")
etEventFrame:RegisterEvent("ENCOUNTER_START")
etEventFrame:RegisterEvent("ENCOUNTER_END")
etEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
etEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

etEventFrame:SetScript("OnEvent", function(self, event, ...)
    ---------------------------------------------------------------------------
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Initialize frame once the DB is ready (EBS:OnInitialize runs first)
        C_Timer.After(0, ApplyEncounterTimer)
        -- Register with Unlock Mode after everything has loaded
        C_Timer.After(1.5, function()
            if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
            local MK = EllesmereUI.MakeUnlockElement
            EllesmereUI:RegisterUnlockElements({
                MK({
                    key      = "EBS_EncounterTimer",
                    label    = "Encounter Timer",
                    group    = "Basics",
                    order    = 520,
                    noResize = true,
                    isHidden = function() return not Cfg("enabled") end,
                    getFrame = function() return _etFrame end,
                    savePos  = function(_, point, relPoint, x, y)
                        local d = DB(); if not d then return end
                        d.position = { point = point, relPoint = relPoint, x = x, y = y }
                    end,
                    loadPos  = function()
                        local d = DB(); return d and d.position
                    end,
                    clearPos = function()
                        local d = DB(); if not d then return end
                        d.position = nil
                    end,
                    applyPos = function() ApplyEncounterTimer() end,
                })
            })
        end)

    ---------------------------------------------------------------------------
    elseif event == "ENCOUNTER_START" then
        -- Both trigger modes respond: ENCOUNTER_START is always more precise
        if not Cfg("enabled") then return end
        local encounterID, encounterName, difficultyID, groupSize = ...
        _encounterName = encounterName
        _startTime     = GetTime()
        _inEncounter   = true
        UpdateTimerDisplay()
        StartTicker()
        UpdateEncounterTimerVisibility()

    ---------------------------------------------------------------------------
    elseif event == "ENCOUNTER_END" then
        -- Only "encounter" mode stops on ENCOUNTER_END
        if Cfg("triggerMode") == "combat" then return end
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        _inEncounter   = false
        _encounterName = nil
        StopTicker()
        -- Keep the final time on screen for 2 seconds before resetting
        C_Timer.After(2, function()
            _startTime = nil
            UpdateTimerDisplay()
            UpdateEncounterTimerVisibility()
        end)

    ---------------------------------------------------------------------------
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- "combat" mode only; also skips if ENCOUNTER_START already owns the timer
        if not Cfg("enabled") then return end
        if Cfg("triggerMode") ~= "combat" then return end
        if _inEncounter then return end
        _encounterName = nil
        _startTime     = GetTime()
        _inEncounter   = true
        UpdateTimerDisplay()
        StartTicker()
        UpdateEncounterTimerVisibility()

    ---------------------------------------------------------------------------
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Cfg("triggerMode") ~= "combat" then return end
        _inEncounter = false
        StopTicker()
        C_Timer.After(2, function()
            _startTime = nil
            UpdateTimerDisplay()
            UpdateEncounterTimerVisibility()
        end)
    end
end)
