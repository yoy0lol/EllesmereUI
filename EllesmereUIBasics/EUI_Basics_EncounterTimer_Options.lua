-------------------------------------------------------------------------------
--  EUI_Basics_EncounterTimer_Options.lua
--  Options page builder for the Encounter Timer module.
--  Registered as a page under the EllesmereUIBasics module.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local PP = EllesmereUI.PP

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local function DB()
        local ace = _G._EBS_AceDB
        return ace and ace.profile and ace.profile.encounterTimer
    end
    local function Cfg(k)    local d = DB(); return d and d[k] end
    local function Set(k, v) local d = DB(); if d then d[k] = v end end
    local function Refresh()
        if _G._EBS_ApplyEncounterTimer then _G._EBS_ApplyEncounterTimer() end
    end

    ---------------------------------------------------------------------------
    --  Text color multi-swatch  (mirrors MakeBorderSwatch in EUI_Basics_Options.lua)
    ---------------------------------------------------------------------------
    local function MakeTextColorSwatch()
        return {
            {
                tooltip  = "Custom Color",
                hasAlpha = false,
                getValue = function()
                    local d = DB()
                    if not d then return 1, 1, 1 end
                    return d.r or 1, d.g or 1, d.b or 1
                end,
                setValue = function(r, g, b)
                    Set("r", r); Set("g", g); Set("b", b)
                    Refresh()
                end,
                onClick = function(self)
                    local d = DB(); if not d then return end
                    if d.useClassColor then
                        d.useClassColor = false
                        Refresh(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function()
                    local d = DB()
                    if not d or d.enabled == false then return 0.15 end
                    return d.useClassColor and 0.3 or 1
                end,
            },
            {
                tooltip  = "Class Colored",
                hasAlpha = false,
                getValue = function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                setValue = function() end,
                onClick  = function()
                    Set("useClassColor", true)
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local d = DB()
                    if not d or d.enabled == false then return 0.15 end
                    return d.useClassColor and 1 or 0.3
                end,
            },
        }
    end

    ---------------------------------------------------------------------------
    --  Page builder
    ---------------------------------------------------------------------------
    local function BuildPage(_, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- ── ENCOUNTER TIMER ──────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "ENCOUNTER TIMER", y); y = y - h

        -- Row 1: Enable Module | Trigger Mode
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Module",
              getValue = function() return Cfg("enabled") ~= false end,
              setValue = function(v)
                  Set("enabled", v)
                  Refresh()
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Trigger Mode",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              values = { encounter = "Boss Pulls Only", combat = "Any Combat" },
              order  = { "encounter", "combat" },
              getValue = function() return Cfg("triggerMode") or "encounter" end,
              setValue = function(v) Set("triggerMode", v); Refresh() end }
        ); y = y - h

        -- Row 2: Font Size | Font Outline
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Font Size", min = 16, max = 48, step = 1,
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              getValue = function() return Cfg("fontSize") or 28 end,
              setValue = function(v) Set("fontSize", v); Refresh() end },
            { type = "dropdown", text = "Font Outline",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              values = { [""] = "None", OUTLINE = "Thin", THICKOUTLINE = "Thick" },
              order  = { "", "OUTLINE", "THICKOUTLINE" },
              getValue = function() return Cfg("fontOutline") or "" end,
              setValue = function(v) Set("fontOutline", v); Refresh() end }
        ); y = y - h

        -- Row 3: Font Shadow | Text Color
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Font Shadow",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              getValue = function() return Cfg("fontShadow") ~= false end,
              setValue = function(v) Set("fontShadow", v); Refresh() end },
            { type = "multiSwatch", text = "Text Color",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              swatches = MakeTextColorSwatch() }
        ); y = y - h

        -- Row 4: Show Background | Background Opacity
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Background",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              getValue = function() return Cfg("showBg") ~= false end,
              setValue = function(v)
                  Set("showBg", v); Refresh(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Background Opacity", min = 0, max = 1, step = 0.05,
              disabled        = function()
                  return Cfg("enabled") == false or Cfg("showBg") == false
              end,
              disabledTooltip = "Enable background first",
              getValue = function() return Cfg("bgAlpha") or 0.5 end,
              setValue = function(v) Set("bgAlpha", v); Refresh() end }
        ); y = y - h

        -- Row 5: Visibility + Visibility Options  (inline CB-dropdown pattern)
        do
            row, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Visibility",
                  disabled        = function() return Cfg("enabled") == false end,
                  disabledTooltip = "Module is disabled",
                  values = EllesmereUI.VIS_VALUES,
                  order  = EllesmereUI.VIS_ORDER,
                  getValue = function() return Cfg("visibility") or "always" end,
                  setValue = function(v)
                      Set("visibility", v)
                      Refresh()
                      if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                      EllesmereUI:RefreshPage()
                  end },
                { type = "dropdown", text = "Visibility Options",
                  values = { __placeholder = "..." }, order = { "__placeholder" },
                  getValue = function() return "__placeholder" end,
                  setValue = function() end })
            do
                local rightRgn = row._rightRegion
                if rightRgn._control then rightRgn._control:Hide() end
                local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                    EllesmereUI.VIS_OPT_ITEMS,
                    function(k) return Cfg(k) or false end,
                    function(k, v)
                        Set(k, v)
                        if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                        EllesmereUI:RefreshPage()
                    end)
                PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                rightRgn._control = cbDD
                rightRgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            y = y - h
        end

        -- Row 6: Show Encounter Name | Show When Idle
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Encounter Name",
              disabled = function()
                  return Cfg("enabled") == false or Cfg("triggerMode") == "combat"
              end,
              disabledTooltip = Cfg("triggerMode") == "combat"
                  and "Not available in Any Combat mode — boss names only come from Encounter Events"
                  or "Module is disabled",
              getValue = function() return Cfg("showEncounterName") or false end,
              setValue = function(v) Set("showEncounterName", v); Refresh() end },
            { type = "toggle", text = "Show When Idle",
              disabled        = function() return Cfg("enabled") == false end,
              disabledTooltip = "Module is disabled",
              getValue = function() return Cfg("showWhenIdle") or false end,
              setValue = function(v)
                  Set("showWhenIdle", v); Refresh(); EllesmereUI:RefreshPage()
              end }
        ); y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Global bridge
    ---------------------------------------------------------------------------
    _G._EBS_BuildEncounterTimerPage = BuildPage
end)
