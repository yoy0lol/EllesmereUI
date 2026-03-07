-------------------------------------------------------------------------------
--  EllesmereUIRaidFrames.lua
--  Core addon: party/raid unit frames with secure group headers
--  Handles frame creation, event dispatch, health/power/aura updates
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ERF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERF = ERF

-- Expose globally for options and cross-file access
EllesmereUIRaidFrames = ERF

local _G = _G
local pairs, ipairs, type, wipe = pairs, ipairs, type, wipe
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local format = string.format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists, UnitIsUnit = UnitExists, UnitIsUnit
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitName, UnitGUID = UnitName, UnitGUID
local UnitClass, UnitClassBase = UnitClass, UnitClassBase
local UnitIsDeadOrGhost, UnitIsConnected = UnitIsDeadOrGhost, UnitIsConnected
local UnitIsAFK = UnitIsAFK
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation = UnitThreatSituation
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitIsPlayer = UnitIsPlayer
local UnitInRange = UnitInRange
local GetTime = GetTime
local GetRaidTargetIndex = GetRaidTargetIndex
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetReadyCheckStatus = GetReadyCheckStatus
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PixelUtil = PixelUtil
local PP = EllesmereUI.PP

-------------------------------------------------------------------------------
--  Media paths
-------------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
local FONT_DIR = MEDIA .. "fonts\\"
local DEFAULT_FONT = FONT_DIR .. "Expressway.TTF"
local DEFAULT_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-------------------------------------------------------------------------------
--  Default settings
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        -- Frame dimensions
        frameWidth       = 90,
        frameHeight      = 46,
        frameSpacing     = 2,
        framePadding     = 1,
        groupSpacing     = 8,

        -- Layout
        growthDirection  = "DOWN",     -- DOWN, UP, LEFT, RIGHT
        groupBy          = "GROUP",    -- GROUP, ROLE, CLASS, NONE
        sortBy           = "INDEX",    -- INDEX, NAME, ROLE, CLASS
        showPlayer       = true,
        showSolo         = false,
        showPets         = false,
        raidLayout       = "BY_GROUP", -- BY_GROUP, COMBINED
        maxColumns       = 8,
        unitsPerColumn   = 5,
        columnSpacing    = 8,
        columnGrowth     = "RIGHT",    -- LEFT, RIGHT

        -- Health bar
        healthTexture    = DEFAULT_TEXTURE,
        healthColorMode  = "CLASS",    -- CLASS, HEALTH_GRADIENT, CUSTOM
        healthCustomColor = { r = 0.2, g = 0.9, b = 0.2 },
        healthBgAlpha    = 0.35,

        -- Missing health (deficit bar behind health)
        missingHealthColor = { r = 0.15, g = 0.15, b = 0.15 },

        -- Power bar
        powerBarEnabled  = true,
        powerBarHeight   = 4,
        powerBarTexture  = DEFAULT_TEXTURE,
        powerBarDetached = false,

        -- Absorb shield
        absorbEnabled    = true,
        absorbColor      = { r = 0.1, g = 0.75, b = 0.95, a = 0.55 },
        absorbOverflow   = true,

        -- Heal prediction
        healPrediction   = true,
        healPredColor    = { r = 0.3, g = 0.85, b = 0.3, a = 0.45 },

        -- Name text
        nameFont         = DEFAULT_FONT,
        nameFontSize     = 10,
        nameOutline      = "OUTLINE",
        namePosition     = "TOP",      -- TOP, CENTER, BOTTOM
        nameYOffset      = -2,
        nameColorMode    = "CLASS",    -- CLASS, WHITE, CUSTOM
        nameCustomColor  = { r = 1, g = 1, b = 1 },
        nameLength       = 8,

        -- Health text
        healthTextEnabled = true,
        healthFont       = DEFAULT_FONT,
        healthFontSize   = 10,
        healthOutline    = "OUTLINE",
        healthFormat     = "DEFICIT",  -- PERCENT, CURRENT, DEFICIT, NONE
        healthPosition   = "CENTER",
        healthYOffset    = 0,

        -- Status text (Dead, Offline, AFK)
        statusFont       = DEFAULT_FONT,
        statusFontSize   = 10,
        statusOutline    = "OUTLINE",
        statusColor      = { r = 0.8, g = 0.2, b = 0.2 },

        -- Border
        borderEnabled    = true,
        borderSize       = 1,
        borderColor      = { r = 0, g = 0, b = 0, a = 1 },

        -- Background
        bgColor          = { r = 0.06, g = 0.06, b = 0.06, a = 0.85 },

        -- Role icon
        roleIconEnabled  = true,
        roleIconSize     = 12,
        roleIconPosition = "TOPLEFT",
        roleIconXOffset  = 1,
        roleIconYOffset  = -1,

        -- Raid target icon
        raidTargetEnabled = true,
        raidTargetSize   = 14,
        raidTargetPosition = "CENTER",

        -- Ready check icon
        readyCheckEnabled = true,
        readyCheckSize   = 20,

        -- Dispel highlight (unique: colored border flash by debuff type)
        dispelHighlight  = true,
        dispelGlowAlpha  = 0.7,

        -- Aggro highlight
        aggroHighlight   = true,
        aggroColor       = { r = 1, g = 0, b = 0, a = 0.6 },

        -- Range fading (unique: smooth fade, not binary)
        rangeFadeEnabled = true,
        rangeFadeAlpha   = 0.40,

        -- Role tint (unique: subtle background tint by role)
        roleTintEnabled  = false,
        roleTintAlpha    = 0.08,
        roleTintTank     = { r = 0.3, g = 0.5, b = 1.0 },
        roleTintHealer   = { r = 0.3, g = 1.0, b = 0.5 },
        roleTintDamager  = { r = 1.0, g = 0.3, b = 0.3 },

        -- Buffs/Debuffs
        showBuffs        = false,
        buffSize         = 16,
        buffMax          = 3,
        buffPosition     = "BOTTOMRIGHT",
        showDebuffs      = true,
        debuffSize       = 18,
        debuffMax        = 3,
        debuffPosition   = "BOTTOMLEFT",
        debuffTypeColor  = true,

        -- Center icon (defensive/important aura)
        centerIconEnabled = true,
        centerIconSize   = 22,
    },
}
ns.defaults = defaults

-------------------------------------------------------------------------------
--  Power color table
-------------------------------------------------------------------------------
local POWER_COLORS = {
    [0]  = { r = 0.00, g = 0.00, b = 1.00 },  -- Mana
    [1]  = { r = 1.00, g = 0.00, b = 0.00 },  -- Rage
    [2]  = { r = 1.00, g = 0.50, b = 0.25 },  -- Focus
    [3]  = { r = 1.00, g = 1.00, b = 0.00 },  -- Energy
    [4]  = { r = 0.00, g = 1.00, b = 1.00 },  -- Combo Points
    [5]  = { r = 0.50, g = 0.50, b = 0.50 },  -- Runes
    [6]  = { r = 0.00, g = 0.82, b = 1.00 },  -- Runic Power
    [7]  = { r = 0.60, g = 0.35, b = 0.95 },  -- Soul Shards
    [8]  = { r = 0.95, g = 0.90, b = 0.60 },  -- Lunar Power
    [9]  = { r = 0.00, g = 1.00, b = 0.60 },  -- Holy Power
    [11] = { r = 0.64, g = 0.23, b = 0.91 },  -- Maelstrom
    [12] = { r = 0.60, g = 0.09, b = 0.18 },  -- Chi
    [13] = { r = 0.77, g = 0.12, b = 0.23 },  -- Insanity
    [17] = { r = 0.00, g = 0.59, b = 0.60 },  -- Fury
    [18] = { r = 0.30, g = 0.52, b = 0.90 },  -- Pain
    [19] = { r = 0.54, g = 0.26, b = 0.15 },  -- Essence
}

local DISPEL_COLORS = {
    Magic   = { r = 0.2, g = 0.6, b = 1.0 },
    Curse   = { r = 0.6, g = 0.0, b = 1.0 },
    Disease = { r = 0.6, g = 0.4, b = 0.0 },
    Poison  = { r = 0.0, g = 0.6, b = 0.0 },
}

ns.POWER_COLORS = POWER_COLORS
ns.DISPEL_COLORS = DISPEL_COLORS

-------------------------------------------------------------------------------
--  DB helpers
-------------------------------------------------------------------------------
function ERF:DB()
    return self.db.profile
end

function ERF:GetFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("raidFrames")
    end
    return self:DB().nameFont or DEFAULT_FONT
end

local function SetFSFont(fs, font, size, flags)
    if not (fs and fs.SetFont) then return end
    local resolvedFont = font or DEFAULT_FONT
    if EllesmereUI and EllesmereUI.GetFontPath then
        resolvedFont = EllesmereUI.GetFontPath("raidFrames")
    end
    local resolvedFlags = flags
    if resolvedFlags == nil then
        resolvedFlags = (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or "OUTLINE"
    end
    fs:SetFont(resolvedFont, size or 10, resolvedFlags)
    if resolvedFlags == "" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end
ns.SetFSFont = SetFSFont

-------------------------------------------------------------------------------
--  Frame tracking
-------------------------------------------------------------------------------
local unitFrameMap = {}   -- "party1" => frame, "raid5" => frame
ERF.unitFrameMap = unitFrameMap
ERF.partyHeader = nil
ERF.raidHeaders = {}      -- group index => header
ERF.anchorFrame = nil     -- movable anchor for positioning

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function ERF:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIRaidFramesDB", defaults, true)

    -- Create the anchor frame for positioning (movable via unlock mode)
    local anchor = CreateFrame("Frame", "EllesmereUIRaidFramesAnchor", UIParent)
    anchor:SetSize(2, 2)
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    self.anchorFrame = anchor

    -- Register with EllesmereUI unlock mode if available
    if EllesmereUI and EllesmereUI.RegisterMover then
        EllesmereUI:RegisterMover(anchor, "Raid Frames")
    end
end

function ERF:OnEnable()
    -- Minimap button (shared across all Ellesmere addons â€” first to load wins)
    -- Minimap button (handled by parent addon)
    if not _EllesmereUI_MinimapRegistered and EllesmereUI and EllesmereUI.CreateMinimapButton then
        EllesmereUI.CreateMinimapButton()
    end

    -- Register events
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnGroupChanged")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    -- Unit events handled by centralized dispatcher
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_NAME_UPDATE")
    self:RegisterEvent("UNIT_CONNECTION")
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self:RegisterEvent("READY_CHECK")
    self:RegisterEvent("READY_CHECK_CONFIRM")
    self:RegisterEvent("READY_CHECK_FINISHED")
    self:RegisterEvent("RAID_TARGET_UPDATE")
    self:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    self:RegisterEvent("INCOMING_SUMMON_CHANGED")

    -- Range check ticker
    self.rangeTimer = C_Timer.NewTicker(0.2, function() self:UpdateAllRange() end)

    -- Initial setup
    C_Timer.After(0.1, function() self:OnGroupChanged() end)
end

-------------------------------------------------------------------------------
--  Pending operations for after combat
-------------------------------------------------------------------------------
local pendingGroupUpdate = false

function ERF:OnCombatEnd()
    if pendingGroupUpdate then
        pendingGroupUpdate = false
        self:OnGroupChanged()
    end
end

-------------------------------------------------------------------------------
--  Group change handler â€” creates/destroys headers as needed
-------------------------------------------------------------------------------
function ERF:OnGroupChanged()
    if InCombatLockdown() then
        pendingGroupUpdate = true
        return
    end

    local db = self:DB()
    local inRaid = IsInRaid()
    local inGroup = IsInGroup()

    -- Hide everything first
    self:HideAllFrames()

    if inRaid then
        self:SetupRaidFrames()
    elseif inGroup or db.showSolo then
        self:SetupPartyFrames()
    end
end

function ERF:HideAllFrames()
    if InCombatLockdown() then return end
    if self.partyHeader then
        self.partyHeader:Hide()
    end
    for _, header in pairs(self.raidHeaders) do
        header:Hide()
    end
    if self.combinedRaidHeader then
        self.combinedRaidHeader:Hide()
    end
    wipe(unitFrameMap)
end

-------------------------------------------------------------------------------
--  Party header setup
-------------------------------------------------------------------------------
function ERF:SetupPartyFrames()
    if InCombatLockdown() then return end
    local db = self:DB()

    if not self.partyHeader then
        local header = CreateFrame("Frame", "ERFPartyHeader", UIParent, "SecureGroupHeaderTemplate")
        header:SetAttribute("template", "SecureUnitButtonTemplate")
        header:SetAttribute("templateType", "Button")
        -- Secure snippet: runs in restricted environment when header creates children
        header:SetAttribute("initialConfigFunction", [[
            local header = self:GetParent()
            self:SetWidth(]] .. db.frameWidth .. [[)
            self:SetHeight(]] .. db.frameHeight .. [[)
            self:SetAttribute("type1", "target")
            self:SetAttribute("type2", "togglemenu")
        ]])
        self.partyHeader = header
    end

    local header = self.partyHeader
    header:SetAttribute("showPlayer", db.showPlayer)
    header:SetAttribute("showSolo", db.showSolo)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", false)

    -- Growth direction
    local point, xDir, yDir = self:GetGrowthAttributes(db.growthDirection)
    header:SetAttribute("point", point)
    header:SetAttribute("xOffset", xDir * (db.frameWidth + db.frameSpacing))
    header:SetAttribute("yOffset", yDir * (db.frameHeight + db.frameSpacing))

    -- Sort
    header:SetAttribute("groupBy", nil)
    header:SetAttribute("groupingOrder", nil)
    header:SetAttribute("sortMethod", db.sortBy == "NAME" and "NAME" or "INDEX")

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.anchorFrame, "TOPLEFT", 0, 0)
    header:Show()

    -- Initialize any children that already exist
    C_Timer.After(0, function() self:InitializeHeaderChildren(header) end)
end

-------------------------------------------------------------------------------
--  Raid header setup
-------------------------------------------------------------------------------
function ERF:SetupRaidFrames()
    if InCombatLockdown() then return end
    local db = self:DB()

    if db.raidLayout == "BY_GROUP" then
        self:SetupRaidByGroup()
    else
        self:SetupRaidCombined()
    end
end

function ERF:SetupRaidByGroup()
    if InCombatLockdown() then return end
    local db = self:DB()

    -- Hide combined header if it exists
    if self.combinedRaidHeader then
        self.combinedRaidHeader:Hide()
    end

    local point, xDir, yDir = self:GetGrowthAttributes(db.growthDirection)
    local colGrowthX = (db.columnGrowth == "RIGHT") and 1 or -1

    for group = 1, 8 do
        if not self.raidHeaders[group] then
            local name = "ERFRaidGroup" .. group .. "Header"
            local header = CreateFrame("Frame", name, UIParent, "SecureGroupHeaderTemplate")
            header:SetAttribute("template", "SecureUnitButtonTemplate")
            header:SetAttribute("templateType", "Button")
            header:SetAttribute("initialConfigFunction", [[
                local header = self:GetParent()
                self:SetWidth(]] .. db.frameWidth .. [[)
                self:SetHeight(]] .. db.frameHeight .. [[)
                self:SetAttribute("type1", "target")
                self:SetAttribute("type2", "togglemenu")
            ]])
            self.raidHeaders[group] = header
        end

        local header = self.raidHeaders[group]
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showParty", false)
        header:SetAttribute("showPlayer", true)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("groupFilter", tostring(group))
        header:SetAttribute("point", point)
        header:SetAttribute("xOffset", xDir * (db.frameWidth + db.frameSpacing))
        header:SetAttribute("yOffset", yDir * (db.frameHeight + db.frameSpacing))
        header:SetAttribute("sortMethod", db.sortBy == "NAME" and "NAME" or "INDEX")

        -- Position each group column
        local colOffset = (group - 1) * (db.frameWidth + db.columnSpacing) * colGrowthX
        local rowOffset = 0
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", self.anchorFrame, "TOPLEFT", colOffset, rowOffset)
        header:Show()

        C_Timer.After(0, function() self:InitializeHeaderChildren(header) end)
    end
end

function ERF:SetupRaidCombined()
    if InCombatLockdown() then return end
    local db = self:DB()

    -- Hide group headers
    for _, header in pairs(self.raidHeaders) do
        header:Hide()
    end

    if not self.combinedRaidHeader then
        local header = CreateFrame("Frame", "ERFRaidCombinedHeader", UIParent, "SecureGroupHeaderTemplate")
        header:SetAttribute("template", "SecureUnitButtonTemplate")
        header:SetAttribute("templateType", "Button")
        header:SetAttribute("initialConfigFunction", [[
            local header = self:GetParent()
            self:SetWidth(]] .. db.frameWidth .. [[)
            self:SetHeight(]] .. db.frameHeight .. [[)
            self:SetAttribute("type1", "target")
            self:SetAttribute("type2", "togglemenu")
        ]])
        self.combinedRaidHeader = header
    end

    local header = self.combinedRaidHeader
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showSolo", false)

    local point, xDir, yDir = self:GetGrowthAttributes(db.growthDirection)
    header:SetAttribute("point", point)
    header:SetAttribute("xOffset", xDir * (db.frameWidth + db.frameSpacing))
    header:SetAttribute("yOffset", yDir * (db.frameHeight + db.frameSpacing))
    header:SetAttribute("maxColumns", db.maxColumns)
    header:SetAttribute("unitsPerColumn", db.unitsPerColumn)
    header:SetAttribute("columnSpacing", db.columnSpacing)

    local colAnchor = (db.columnGrowth == "RIGHT") and "LEFT" or "RIGHT"
    header:SetAttribute("columnAnchorPoint", colAnchor)

    header:SetAttribute("sortMethod", db.sortBy == "NAME" and "NAME" or "INDEX")

    if db.groupBy == "ROLE" then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    elseif db.groupBy == "CLASS" then
        header:SetAttribute("groupBy", "CLASS")
        header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,DEATHKNIGHT,DEMONHUNTER,DRUID,HUNTER,MAGE,MONK,PRIEST,ROGUE,SHAMAN,WARLOCK,EVOKER")
    else
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
    end

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.anchorFrame, "TOPLEFT", 0, 0)
    header:Show()

    C_Timer.After(0, function() self:InitializeHeaderChildren(header) end)
end

-------------------------------------------------------------------------------
--  Growth direction helpers
-------------------------------------------------------------------------------
function ERF:GetGrowthAttributes(direction)
    -- Returns: anchorPoint, xMultiplier, yMultiplier
    if direction == "UP" then
        return "BOTTOM", 0, 1
    elseif direction == "LEFT" then
        return "RIGHT", -1, 0
    elseif direction == "RIGHT" then
        return "LEFT", 1, 0
    else -- DOWN (default)
        return "TOP", 0, -1
    end
end

-------------------------------------------------------------------------------
--  Initialize header children (called after header:Show())
-------------------------------------------------------------------------------
function ERF:InitializeHeaderChildren(header)
    if not header then return end
    for i = 1, 40 do
        local child = header:GetAttribute("child" .. i)
        if child then
            self:InitializeUnitFrame(child)
        end
    end
end

-------------------------------------------------------------------------------
--  Frame element creation
-------------------------------------------------------------------------------
function ERF:InitializeUnitFrame(frame)
    if not frame or frame.erfInitialized then return end
    local db = self:DB()

    frame:SetSize(db.frameWidth, db.frameHeight)
    frame:RegisterForClicks("AnyUp")

    -- Background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    local bgc = db.bgColor
    frame.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a)

    -- Role tint overlay (unique feature)
    frame.roleTint = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.roleTint:SetAllPoints()
    frame.roleTint:SetColorTexture(1, 1, 1, 0)

    -- Missing health bar (shows deficit behind health bar)
    local pad = db.framePadding
    frame.missingHealthBar = CreateFrame("StatusBar", nil, frame)
    frame.missingHealthBar:SetPoint("TOPLEFT", pad, -pad)
    frame.missingHealthBar:SetPoint("BOTTOMRIGHT", -pad, pad + (db.powerBarEnabled and db.powerBarHeight or 0))
    frame.missingHealthBar:SetStatusBarTexture(db.healthTexture)
    frame.missingHealthBar:SetMinMaxValues(0, 1)
    frame.missingHealthBar:SetValue(1)
    local mhc = db.missingHealthColor
    frame.missingHealthBar:SetStatusBarColor(mhc.r, mhc.g, mhc.b, 1)
    frame.missingHealthBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetPoint("TOPLEFT", pad, -pad)
    frame.healthBar:SetPoint("BOTTOMRIGHT", -pad, pad + (db.powerBarEnabled and db.powerBarHeight or 0))
    frame.healthBar:SetStatusBarTexture(db.healthTexture)
    frame.healthBar:SetMinMaxValues(0, 1)
    frame.healthBar:SetValue(1)
    frame.healthBar:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Heal prediction overlay (unique: smooth animated)
    frame.healPredBar = frame.healthBar:CreateTexture(nil, "OVERLAY")
    frame.healPredBar:SetTexture(db.healthTexture)
    local hpc = db.healPredColor
    frame.healPredBar:SetVertexColor(hpc.r, hpc.g, hpc.b, hpc.a)
    frame.healPredBar:SetBlendMode("ADD")
    frame.healPredBar:Hide()

    -- Absorb overlay (unique: gradient shield visualization)
    frame.absorbBar = frame.healthBar:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.absorbBar:SetTexture(FLAT_TEXTURE)
    local abc = db.absorbColor
    frame.absorbBar:SetVertexColor(abc.r, abc.g, abc.b, abc.a)
    frame.absorbBar:SetBlendMode("ADD")
    frame.absorbBar:Hide()

    -- Power bar
    if db.powerBarEnabled then
        frame.powerBar = CreateFrame("StatusBar", nil, frame)
        frame.powerBar:SetPoint("BOTTOMLEFT", pad, pad)
        frame.powerBar:SetPoint("BOTTOMRIGHT", -pad, pad)
        frame.powerBar:SetHeight(db.powerBarHeight)
        frame.powerBar:SetStatusBarTexture(db.powerBarTexture)
        frame.powerBar:SetMinMaxValues(0, 1)
        frame.powerBar:SetValue(1)
        frame.powerBar:SetFrameLevel(frame:GetFrameLevel() + 3)
        -- Power bar background
        frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
        frame.powerBar.bg:SetAllPoints()
        frame.powerBar.bg:SetColorTexture(0, 0, 0, 0.5)
    end

    -- Content overlay (for text and icons above bars)
    frame.overlay = CreateFrame("Frame", nil, frame)
    frame.overlay:SetAllPoints()
    frame.overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.overlay:EnableMouse(false)

    -- Name text
    frame.nameText = frame.overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(frame.nameText, db.nameFont, db.nameFontSize, db.nameOutline)
    frame.nameText:SetPoint(db.namePosition, frame, db.namePosition, 0, db.nameYOffset)
    frame.nameText:SetTextColor(1, 1, 1, 1)
    frame.nameText:SetJustifyH("CENTER")
    frame.nameText:SetWordWrap(false)

    -- Health text
    frame.healthText = frame.overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(frame.healthText, db.healthFont, db.healthFontSize, db.healthOutline)
    frame.healthText:SetPoint(db.healthPosition, frame, db.healthPosition, 0, db.healthYOffset)
    frame.healthText:SetTextColor(1, 1, 1, 1)
    frame.healthText:SetJustifyH("CENTER")

    -- Status text (Dead, Offline, AFK)
    frame.statusText = frame.overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(frame.statusText, db.statusFont, db.statusFontSize, db.statusOutline)
    frame.statusText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local sc = db.statusColor
    frame.statusText:SetTextColor(sc.r, sc.g, sc.b, 1)
    frame.statusText:Hide()

    -- Border
    self:CreateBorder(frame)

    -- Role icon
    frame.roleIcon = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.roleIcon:SetSize(db.roleIconSize, db.roleIconSize)
    frame.roleIcon:SetPoint(db.roleIconPosition, frame, db.roleIconPosition, db.roleIconXOffset, db.roleIconYOffset)
    frame.roleIcon:Hide()

    -- Raid target icon
    frame.raidTargetIcon = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.raidTargetIcon:SetSize(db.raidTargetSize, db.raidTargetSize)
    frame.raidTargetIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.raidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    frame.raidTargetIcon:Hide()

    -- Ready check icon
    frame.readyCheckIcon = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.readyCheckIcon:SetSize(db.readyCheckSize, db.readyCheckSize)
    frame.readyCheckIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.readyCheckIcon:Hide()

    -- Dispel highlight border (unique: colored by debuff type)
    frame.dispelBorder = CreateFrame("Frame", nil, frame)
    frame.dispelBorder:SetAllPoints()
    frame.dispelBorder:SetFrameLevel(frame:GetFrameLevel() + 15)
    self:CreateDispelBorder(frame)
    frame.dispelBorder:Hide()

    -- Aggro highlight
    frame.aggroBorder = CreateFrame("Frame", nil, frame)
    frame.aggroBorder:SetAllPoints()
    frame.aggroBorder:SetFrameLevel(frame:GetFrameLevel() + 14)
    self:CreateAggroBorder(frame)
    frame.aggroBorder:Hide()

    -- Buff/Debuff icons
    frame.buffIcons = {}
    frame.debuffIcons = {}
    self:CreateAuraIcons(frame, "buff", db.buffMax, db.buffSize, db.buffPosition)
    self:CreateAuraIcons(frame, "debuff", db.debuffMax, db.debuffSize, db.debuffPosition)

    -- Center icon (for important auras like defensives)
    frame.centerIcon = CreateFrame("Frame", nil, frame.overlay)
    frame.centerIcon:SetSize(db.centerIconSize, db.centerIconSize)
    frame.centerIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.centerIcon:SetFrameLevel(frame.overlay:GetFrameLevel() + 5)
    frame.centerIcon.tex = frame.centerIcon:CreateTexture(nil, "OVERLAY")
    frame.centerIcon.tex:SetAllPoints()
    frame.centerIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.centerIcon.cd = CreateFrame("Cooldown", nil, frame.centerIcon, "CooldownFrameTemplate")
    frame.centerIcon.cd:SetAllPoints()
    frame.centerIcon:Hide()

    -- Resurrection icon
    frame.resIcon = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.resIcon:SetSize(16, 16)
    frame.resIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    frame.resIcon:Hide()

    -- Summon icon
    frame.summonIcon = frame.overlay:CreateTexture(nil, "OVERLAY")
    frame.summonIcon:SetSize(16, 16)
    frame.summonIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.summonIcon:SetAtlas("Raid-Icon-SummonPending")
    frame.summonIcon:Hide()

    -- Hover highlight
    frame.hoverHighlight = frame:CreateTexture(nil, "HIGHLIGHT")
    frame.hoverHighlight:SetAllPoints()
    frame.hoverHighlight:SetColorTexture(1, 1, 1, 0.05)

    -- Hook OnAttributeChanged for unit assignment
    frame:HookScript("OnAttributeChanged", function(self, name, value)
        if name == "unit" then
            local unit = value and SecureButton_GetModifiedUnit(self) or nil
            local oldUnit = self.unit
            if oldUnit and unitFrameMap[oldUnit] == self then
                unitFrameMap[oldUnit] = nil
            end
            self.unit = unit
            if unit then
                unitFrameMap[unit] = self
                ERF:FullFrameUpdate(self)
            end
        end
    end)

    -- Register for ping system
    if C_Ping and C_Ping.RegisterFrame then
        pcall(C_Ping.RegisterFrame, frame)
    end

    frame.erfInitialized = true

    -- If unit already assigned, do initial update
    local unit = frame:GetAttribute("unit")
    if unit then
        frame.unit = unit
        unitFrameMap[unit] = frame
        C_Timer.After(0, function()
            if frame:IsVisible() and frame.unit then
                ERF:FullFrameUpdate(frame)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Border creation helpers
-------------------------------------------------------------------------------
function ERF:CreateBorder(frame)
    local db = self:DB()
    if not db.borderEnabled then return end
    if not PP then PP = EllesmereUI and EllesmereUI.PP end
    local s = db.borderSize
    local c = db.borderColor
    frame.borderTextures = {}

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(c.r, c.g, c.b, c.a)
    if PP then PP.DisablePixelSnap(top) end
    top:SetHeight(PP and PP.Scale(s) or s)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.borderTextures.top = top

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(c.r, c.g, c.b, c.a)
    if PP then PP.DisablePixelSnap(bottom) end
    bottom:SetHeight(PP and PP.Scale(s) or s)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borderTextures.bottom = bottom

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(c.r, c.g, c.b, c.a)
    if PP then PP.DisablePixelSnap(left) end
    left:SetWidth(PP and PP.Scale(s) or s)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.borderTextures.left = left

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(c.r, c.g, c.b, c.a)
    if PP then PP.DisablePixelSnap(right) end
    right:SetWidth(PP and PP.Scale(s) or s)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borderTextures.right = right
end

function ERF:CreateDispelBorder(frame)
    if not PP then PP = EllesmereUI and EllesmereUI.PP end
    local s = 2
    local parent = frame.dispelBorder
    parent.textures = {}
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0.2, 0.6, 1.0, 0.7)
        if PP then PP.DisablePixelSnap(tex) end
        if side == "top" then
            tex:SetHeight(s); tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT")
        elseif side == "bottom" then
            tex:SetHeight(s); tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT")
        elseif side == "left" then
            tex:SetWidth(s); tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT")
        else
            tex:SetWidth(s); tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT")
        end
        parent.textures[side] = tex
    end
end

function ERF:CreateAggroBorder(frame)
    local db = self:DB()
    if not PP then PP = EllesmereUI and EllesmereUI.PP end
    local s = 2
    local parent = frame.aggroBorder
    local c = db.aggroColor
    parent.textures = {}
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(c.r, c.g, c.b, c.a)
        if PP then PP.DisablePixelSnap(tex) end
        if side == "top" then
            tex:SetHeight(s); tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT")
        elseif side == "bottom" then
            tex:SetHeight(s); tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT")
        elseif side == "left" then
            tex:SetWidth(s); tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT")
        else
            tex:SetWidth(s); tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT")
        end
        parent.textures[side] = tex
    end
end

-------------------------------------------------------------------------------
--  Aura icon creation
-------------------------------------------------------------------------------
function ERF:CreateAuraIcons(frame, auraType, maxIcons, iconSize, position)
    local icons = (auraType == "buff") and frame.buffIcons or frame.debuffIcons
    local growDir = (position == "BOTTOMLEFT" or position == "TOPLEFT") and 1 or -1

    for i = 1, maxIcons do
        local icon = CreateFrame("Frame", nil, frame.overlay)
        icon:SetSize(iconSize, iconSize)
        icon:SetFrameLevel(frame.overlay:GetFrameLevel() + 3)

        if i == 1 then
            icon:SetPoint(position, frame, position, 1 * growDir, (position:find("BOTTOM") and 1 or -1))
        else
            if growDir > 0 then
                icon:SetPoint("LEFT", icons[i - 1], "RIGHT", 1, 0)
            else
                icon:SetPoint("RIGHT", icons[i - 1], "LEFT", -1, 0)
            end
        end

        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.cd:SetAllPoints()
        icon.cd:SetDrawSwipe(true)
        icon.cd:SetDrawEdge(false)

        icon.count = icon:CreateFontString(nil, "OVERLAY")
        SetFSFont(icon.count, DEFAULT_FONT, 9, "OUTLINE")
        icon.count:SetPoint("BOTTOMRIGHT", 1, -1)
        icon.count:SetTextColor(1, 1, 1, 1)

        -- Debuff type colored border
        if auraType == "debuff" then
            icon.typeBorder = {}
            for _, side in ipairs({"top", "bottom", "left", "right"}) do
                local bt = icon:CreateTexture(nil, "OVERLAY")
                bt:SetColorTexture(1, 0, 0, 0.8)
                if PP then PP.DisablePixelSnap(bt) end
                if side == "top" then
                    bt:SetHeight(PP and PP.Scale(1) or 1); bt:SetPoint("TOPLEFT"); bt:SetPoint("TOPRIGHT")
                elseif side == "bottom" then
                    bt:SetHeight(PP and PP.Scale(1) or 1); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT")
                elseif side == "left" then
                    bt:SetWidth(PP and PP.Scale(1) or 1); bt:SetPoint("TOPLEFT"); bt:SetPoint("BOTTOMLEFT")
                else
                    bt:SetWidth(PP and PP.Scale(1) or 1); bt:SetPoint("TOPRIGHT"); bt:SetPoint("BOTTOMRIGHT")
                end
                icon.typeBorder[side] = bt
            end
        end

        icon:Hide()
        icons[i] = icon
    end
end

-------------------------------------------------------------------------------
--  Full frame update (called on unit change, settings change, etc.)
-------------------------------------------------------------------------------
function ERF:FullFrameUpdate(frame)
    if not frame or not frame.unit then return end
    self:UpdateHealth(frame)
    self:UpdatePower(frame)
    self:UpdateName(frame)
    self:UpdateRoleIcon(frame)
    self:UpdateRaidTarget(frame)
    self:UpdateAuras(frame)
    self:UpdateStatus(frame)
    self:UpdateThreat(frame)
    self:UpdateRange(frame)
    self:UpdateRoleTint(frame)
    self:UpdateResIcon(frame)
    self:UpdateSummonIcon(frame)
end

-------------------------------------------------------------------------------
--  Health update
-------------------------------------------------------------------------------
function ERF:UpdateHealth(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    local db = self:DB()
    local hp = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    local pct = (hpMax > 0) and (hp / hpMax) or 1

    -- Health bar value
    frame.healthBar:SetValue(pct)
    frame.missingHealthBar:SetValue(1 - pct)

    -- Health bar color
    if db.healthColorMode == "CLASS" and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            frame.healthBar:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        end
    elseif db.healthColorMode == "HEALTH_GRADIENT" then
        local r = min(2 * (1 - pct), 1)
        local g = min(2 * pct, 1)
        frame.healthBar:SetStatusBarColor(r, g, 0, 1)
    else
        local c = db.healthCustomColor
        frame.healthBar:SetStatusBarColor(c.r, c.g, c.b, 1)
    end

    -- Heal prediction
    if db.healPrediction then
        local incoming = (UnitGetIncomingHeals(unit) or 0)
        if incoming > 0 and hpMax > 0 then
            local predPct = min((hp + incoming) / hpMax, 1)
            local barW = frame.healthBar:GetWidth()
            local startX = pct * barW
            local predW = (predPct - pct) * barW
            if predW > 1 then
                frame.healPredBar:ClearAllPoints()
                frame.healPredBar:SetPoint("LEFT", frame.healthBar, "LEFT", startX, 0)
                frame.healPredBar:SetSize(predW, frame.healthBar:GetHeight())
                frame.healPredBar:Show()
            else
                frame.healPredBar:Hide()
            end
        else
            frame.healPredBar:Hide()
        end
    end

    -- Absorb shield
    if db.absorbEnabled then
        local absorb = UnitGetTotalAbsorbs(unit) or 0
        if absorb > 0 and hpMax > 0 then
            local absorbPct = min(absorb / hpMax, 1)
            local barW = frame.healthBar:GetWidth()
            local absorbW = absorbPct * barW
            if absorbW > 1 then
                frame.absorbBar:ClearAllPoints()
                frame.absorbBar:SetPoint("LEFT", frame.healthBar, "LEFT", pct * barW, 0)
                frame.absorbBar:SetSize(min(absorbW, barW - pct * barW + (db.absorbOverflow and absorbW * 0.3 or 0)), frame.healthBar:GetHeight())
                frame.absorbBar:Show()
            else
                frame.absorbBar:Hide()
            end
        else
            frame.absorbBar:Hide()
        end
    end

    -- Health text
    if db.healthTextEnabled and db.healthFormat ~= "NONE" then
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            frame.healthText:SetText("")
        elseif db.healthFormat == "PERCENT" then
            frame.healthText:SetText(floor(pct * 100) .. "%")
        elseif db.healthFormat == "CURRENT" then
            frame.healthText:SetText(self:FormatNumber(hp))
        elseif db.healthFormat == "DEFICIT" then
            local deficit = hpMax - hp
            if deficit > 0 then
                frame.healthText:SetText("-" .. self:FormatNumber(deficit))
            else
                frame.healthText:SetText("")
            end
        end
    else
        frame.healthText:SetText("")
    end
end

function ERF:FormatNumber(n)
    if n >= 1e6 then
        return format("%.1fM", n / 1e6)
    elseif n >= 1e3 then
        return format("%.0fK", n / 1e3)
    end
    return tostring(n)
end

-------------------------------------------------------------------------------
--  Power update
-------------------------------------------------------------------------------
function ERF:UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    local powerType = UnitPowerType(unit)
    local power = UnitPower(unit)
    local powerMax = UnitPowerMax(unit)
    local pct = (powerMax > 0) and (power / powerMax) or 0

    frame.powerBar:SetValue(pct)

    local pc = POWER_COLORS[powerType] or POWER_COLORS[0]
    frame.powerBar:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
end

-------------------------------------------------------------------------------
--  Name update
-------------------------------------------------------------------------------
function ERF:UpdateName(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    local db = self:DB()
    local name = UnitName(unit) or ""

    -- Truncate name
    if db.nameLength and db.nameLength > 0 and #name > db.nameLength then
        name = name:sub(1, db.nameLength)
    end

    frame.nameText:SetText(name)

    -- Name color
    if db.nameColorMode == "CLASS" and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            frame.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
        else
            frame.nameText:SetTextColor(1, 1, 1, 1)
        end
    elseif db.nameColorMode == "CUSTOM" then
        local c = db.nameCustomColor
        frame.nameText:SetTextColor(c.r, c.g, c.b, 1)
    else
        frame.nameText:SetTextColor(1, 1, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  Status update (Dead, Offline, AFK)
-------------------------------------------------------------------------------
function ERF:UpdateStatus(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    if UnitIsDeadOrGhost(unit) then
        frame.statusText:SetText("DEAD")
        frame.statusText:Show()
        frame.healthText:SetText("")
    elseif not UnitIsConnected(unit) then
        frame.statusText:SetText("OFFLINE")
        frame.statusText:Show()
        frame.healthText:SetText("")
    elseif UnitIsAFK(unit) then
        frame.statusText:SetText("AFK")
        frame.statusText:Show()
    else
        frame.statusText:Hide()
    end
end

-------------------------------------------------------------------------------
--  Role icon update
-------------------------------------------------------------------------------
function ERF:UpdateRoleIcon(frame)
    if not frame or not frame.unit then return end
    local db = self:DB()
    if not db.roleIconEnabled then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(frame.unit)
    if role == "TANK" then
        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        frame.roleIcon:SetTexCoord(0, 19/64, 22/64, 41/64)
        frame.roleIcon:Show()
    elseif role == "HEALER" then
        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        frame.roleIcon:SetTexCoord(20/64, 39/64, 1/64, 20/64)
        frame.roleIcon:Show()
    elseif role == "DAMAGER" then
        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        frame.roleIcon:SetTexCoord(20/64, 39/64, 22/64, 41/64)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Role tint (unique feature: subtle background tint by role)
-------------------------------------------------------------------------------
function ERF:UpdateRoleTint(frame)
    if not frame or not frame.unit or not frame.roleTint then return end
    local db = self:DB()
    if not db.roleTintEnabled then
        frame.roleTint:SetColorTexture(1, 1, 1, 0)
        return
    end

    local role = UnitGroupRolesAssigned(frame.unit)
    local c
    if role == "TANK" then
        c = db.roleTintTank
    elseif role == "HEALER" then
        c = db.roleTintHealer
    elseif role == "DAMAGER" then
        c = db.roleTintDamager
    end

    if c then
        frame.roleTint:SetColorTexture(c.r, c.g, c.b, db.roleTintAlpha)
    else
        frame.roleTint:SetColorTexture(1, 1, 1, 0)
    end
end

-------------------------------------------------------------------------------
--  Raid target icon
-------------------------------------------------------------------------------
function ERF:UpdateRaidTarget(frame)
    if not frame or not frame.unit then return end
    local db = self:DB()
    if not db.raidTargetEnabled then
        frame.raidTargetIcon:Hide()
        return
    end

    local idx = GetRaidTargetIndex(frame.unit)
    if idx then
        SetRaidTargetIconTexture(frame.raidTargetIcon, idx)
        frame.raidTargetIcon:Show()
    else
        frame.raidTargetIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Threat update
-------------------------------------------------------------------------------
function ERF:UpdateThreat(frame)
    if not frame or not frame.unit then return end
    local db = self:DB()
    if not db.aggroHighlight then
        frame.aggroBorder:Hide()
        return
    end

    local status = UnitThreatSituation(frame.unit)
    if status and status >= 2 then
        local c = db.aggroColor
        for _, tex in pairs(frame.aggroBorder.textures) do
            tex:SetColorTexture(c.r, c.g, c.b, c.a)
        end
        frame.aggroBorder:Show()
    else
        frame.aggroBorder:Hide()
    end
end

-------------------------------------------------------------------------------
--  Range update (unique: smooth fade)
-------------------------------------------------------------------------------
function ERF:UpdateRange(frame)
    if not frame or not frame.unit then return end
    local db = self:DB()
    if not db.rangeFadeEnabled then
        frame:SetAlpha(1)
        return
    end

    local unit = frame.unit
    if UnitIsUnit(unit, "player") then
        frame:SetAlpha(1)
        return
    end

    local inRange, checkedRange = UnitInRange(unit)
    if checkedRange and not inRange then
        frame:SetAlpha(db.rangeFadeAlpha)
    else
        frame:SetAlpha(1)
    end
end

function ERF:UpdateAllRange()
    for unit, frame in pairs(unitFrameMap) do
        if frame and frame:IsVisible() then
            self:UpdateRange(frame)
        end
    end
end

-------------------------------------------------------------------------------
--  Resurrection / Summon icons
-------------------------------------------------------------------------------
function ERF:UpdateResIcon(frame)
    if not frame or not frame.unit then return end
    local hasRes = UnitHasIncomingResurrection and UnitHasIncomingResurrection(frame.unit)
    if hasRes then
        frame.resIcon:Show()
    else
        frame.resIcon:Hide()
    end
end

function ERF:UpdateSummonIcon(frame)
    if not frame or not frame.unit then return end
    local status = C_IncomingSummon and C_IncomingSummon.HasIncomingSummon and C_IncomingSummon.HasIncomingSummon(frame.unit)
    if status then
        frame.summonIcon:Show()
    else
        frame.summonIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Aura update
-------------------------------------------------------------------------------
function ERF:UpdateAuras(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end
    local db = self:DB()

    -- Reset dispel border
    local dispelType = nil

    -- Debuffs
    if db.showDebuffs then
        local debuffIdx = 0
        local function ProcessDebuff(aura)
            if not aura or not aura.name then return end
            debuffIdx = debuffIdx + 1
            if debuffIdx > db.debuffMax then return end
            local icon = frame.debuffIcons[debuffIdx]
            if not icon then return end
            icon.tex:SetTexture(aura.icon)
            if aura.applications and aura.applications > 1 then
                icon.count:SetText(aura.applications)
                icon.count:Show()
            else
                icon.count:SetText("")
            end
            -- Cooldown
            if aura.expirationTime and aura.expirationTime > 0 and aura.duration and aura.duration > 0 then
                local dur = aura.duration
                if type(dur) == "table" then dur = 0 end
                if dur > 0 then
                    icon.cd:SetCooldown(aura.expirationTime - dur, dur)
                else
                    icon.cd:Clear()
                end
            else
                icon.cd:Clear()
            end
            -- Debuff type border color
            if db.debuffTypeColor and icon.typeBorder and aura.dispelName then
                local dc = DISPEL_COLORS[aura.dispelName]
                if dc then
                    for _, bt in pairs(icon.typeBorder) do
                        bt:SetColorTexture(dc.r, dc.g, dc.b, 0.8)
                    end
                end
            end
            icon:Show()

            -- Track dispellable debuff type for frame border
            if aura.isRaid or aura.dispelName then
                dispelType = dispelType or aura.dispelName
            end
        end

        -- Use C_UnitAuras.GetAuraDataByIndex for debuffs
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
            if not aura then break end
            ProcessDebuff(aura)
            i = i + 1
        end

        -- Hide unused icons
        for j = debuffIdx + 1, db.debuffMax do
            if frame.debuffIcons[j] then
                frame.debuffIcons[j]:Hide()
            end
        end
    else
        for _, icon in ipairs(frame.debuffIcons) do icon:Hide() end
    end

    -- Buffs
    if db.showBuffs then
        local buffIdx = 0
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            if aura.isFromPlayerOrPlayerPet then
                buffIdx = buffIdx + 1
                if buffIdx <= db.buffMax then
                    local icon = frame.buffIcons[buffIdx]
                    if icon then
                        icon.tex:SetTexture(aura.icon)
                        if aura.applications and aura.applications > 1 then
                            icon.count:SetText(aura.applications)
                        else
                            icon.count:SetText("")
                        end
                        if aura.expirationTime and aura.expirationTime > 0 and aura.duration and aura.duration > 0 then
                            local dur = aura.duration
                            if type(dur) == "table" then dur = 0 end
                            if dur > 0 then
                                icon.cd:SetCooldown(aura.expirationTime - dur, dur)
                            else
                                icon.cd:Clear()
                            end
                        else
                            icon.cd:Clear()
                        end
                        icon:Show()
                    end
                end
            end
            i = i + 1
        end
        for j = buffIdx + 1, db.buffMax do
            if frame.buffIcons[j] then frame.buffIcons[j]:Hide() end
        end
    else
        for _, icon in ipairs(frame.buffIcons) do icon:Hide() end
    end

    -- Dispel highlight (unique feature)
    if db.dispelHighlight and dispelType then
        local dc = DISPEL_COLORS[dispelType]
        if dc and frame.dispelBorder then
            for _, tex in pairs(frame.dispelBorder.textures) do
                tex:SetColorTexture(dc.r, dc.g, dc.b, db.dispelGlowAlpha)
            end
            frame.dispelBorder:Show()
        end
    else
        if frame.dispelBorder then frame.dispelBorder:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Event dispatchers
-------------------------------------------------------------------------------
function ERF:UNIT_HEALTH(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateHealth(frame)
    end
end

function ERF:UNIT_AURA(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateAuras(frame)
    end
end

function ERF:UNIT_POWER_UPDATE(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdatePower(frame)
    end
end

function ERF:UNIT_NAME_UPDATE(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateName(frame)
    end
end

function ERF:UNIT_CONNECTION(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateStatus(frame)
        self:UpdateHealth(frame)
    end
end

function ERF:UNIT_THREAT_SITUATION_UPDATE(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateThreat(frame)
    end
end

function ERF:READY_CHECK()
    for unit, frame in pairs(unitFrameMap) do
        if frame and frame:IsVisible() then
            self:UpdateReadyCheck(frame)
        end
    end
end

function ERF:READY_CHECK_CONFIRM(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateReadyCheck(frame)
    end
end

function ERF:READY_CHECK_FINISHED()
    C_Timer.After(6, function()
        for _, frame in pairs(unitFrameMap) do
            if frame and frame.readyCheckIcon then
                frame.readyCheckIcon:Hide()
            end
        end
    end)
end

function ERF:RAID_TARGET_UPDATE()
    for _, frame in pairs(unitFrameMap) do
        if frame and frame:IsVisible() then
            self:UpdateRaidTarget(frame)
        end
    end
end

function ERF:INCOMING_RESURRECT_CHANGED(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateResIcon(frame)
    end
end

function ERF:INCOMING_SUMMON_CHANGED(_, unit)
    local frame = unitFrameMap[unit]
    if frame and frame:IsVisible() then
        self:UpdateSummonIcon(frame)
    end
end

-------------------------------------------------------------------------------
--  Ready check
-------------------------------------------------------------------------------
function ERF:UpdateReadyCheck(frame)
    if not frame or not frame.unit then return end
    local db = self:DB()
    if not db.readyCheckEnabled then
        frame.readyCheckIcon:Hide()
        return
    end

    local status = GetReadyCheckStatus(frame.unit)
    if status == "ready" then
        frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        frame.readyCheckIcon:Show()
    elseif status == "notready" then
        frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        frame.readyCheckIcon:Show()
    elseif status == "waiting" then
        frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        frame.readyCheckIcon:Show()
    else
        frame.readyCheckIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Update all visible frames (for settings changes)
-------------------------------------------------------------------------------
function ERF:UpdateAllFrames()
    for _, frame in pairs(unitFrameMap) do
        if frame and frame:IsVisible() and frame.unit then
            self:FullFrameUpdate(frame)
        end
    end
end

-------------------------------------------------------------------------------
--  Apply layout changes to all frames (resize, reposition elements)
-------------------------------------------------------------------------------
function ERF:ApplyLayoutToAll()
    if InCombatLockdown() then
        pendingGroupUpdate = true
        return
    end
    local db = self:DB()
    for _, frame in pairs(unitFrameMap) do
        if frame and frame.erfInitialized then
            frame:SetSize(db.frameWidth, db.frameHeight)
            local pad = db.framePadding
            local powerH = (db.powerBarEnabled and frame.powerBar) and db.powerBarHeight or 0
            frame.healthBar:ClearAllPoints()
            frame.healthBar:SetPoint("TOPLEFT", pad, -pad)
            frame.healthBar:SetPoint("BOTTOMRIGHT", -pad, pad + powerH)
            frame.missingHealthBar:ClearAllPoints()
            frame.missingHealthBar:SetPoint("TOPLEFT", pad, -pad)
            frame.missingHealthBar:SetPoint("BOTTOMRIGHT", -pad, pad + powerH)
            if frame.powerBar then
                frame.powerBar:ClearAllPoints()
                frame.powerBar:SetPoint("BOTTOMLEFT", pad, pad)
                frame.powerBar:SetPoint("BOTTOMRIGHT", -pad, pad)
                frame.powerBar:SetHeight(db.powerBarHeight)
            end
            self:FullFrameUpdate(frame)
        end
    end
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------
SLASH_ELLESMERERAIDFRAMES1 = "/erf"
SlashCmdList["ELLESMERERAIDFRAMES"] = function(msg)
    if msg == "test" then
        -- Toggle test mode (show frames even when solo)
        local db = ERF:DB()
        db.showSolo = not db.showSolo
        ERF:OnGroupChanged()
        print("|cff0cd29fEllesmere Raid Frames:|r Solo mode " .. (db.showSolo and "enabled" or "disabled"))
    elseif msg == "reset" then
        ERF.anchorFrame:ClearAllPoints()
        ERF.anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
        ERF:OnGroupChanged()
        print("|cff0cd29fEllesmere Raid Frames:|r Position reset.")
    else
        if EllesmereUI and EllesmereUI.Toggle then
            EllesmereUI:Toggle()
        else
            print("|cff0cd29fEllesmere Raid Frames:|r /erf test - toggle solo test mode | /erf reset - reset position")
        end
    end
end
