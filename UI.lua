-- Squire: minimap button, overview panel, options
local ADDON, ns = ...
local UI = {}
ns.UI = UI

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- Minimap button -----------------------------------------------------------
local function PlaceButton(b)
    local a = math.rad(ns.db.minimap.angle)
    local r = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "SquireMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.badge:SetPoint("BOTTOMRIGHT", -2, 2)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.Nearby.ShowList(true) else UI.TogglePanel() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Squire", 1, 0.82, 0)
        local spells = ns.GetAvailable()
        if not ns.HasServiceData() then
            GameTooltip:AddLine("Talk to your class trainer once to read spells.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(#spells .. " spell(s) to train", 1, 1, 1)
        end
        for _, e in ipairs(ns.Prof.Scan()) do
            GameTooltip:AddLine(e.text, 1, 0.6, 0.4, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open panel", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: to-do list", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton(b)
    UI.minimap = b
end

-- Overview panel -------------------------------------------------------------
local function CreatePanel()
    local f = ns.MakeWindow("SquirePanel")
    f:SetSize(440, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("Squire")
    tinsert(UISpecialFrames, "SquirePanel")

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32)
    sf:SetPoint("BOTTOMRIGHT", -32, 44)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(390, 10)
    sf:SetScrollChild(child)
    f.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT")
    f.text:SetWidth(390)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(3)
    f.child = child

    local opt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    opt:SetSize(110, 22)
    opt:SetPoint("BOTTOMRIGHT", -12, 12)
    opt:SetText("Options")
    opt:SetScript("OnClick", function() UI.OpenOptions() end)

    local list = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    list:SetSize(110, 22)
    list:SetPoint("RIGHT", opt, "LEFT", -6, 0)
    list:SetText("To-do list")
    list:SetScript("OnClick", function() ns.Nearby.ShowList(true) end)

    f:SetScript("OnShow", UI.Refresh)
    f:Hide()
    UI.panel = f
end

local GOLD, GREY, WHITE = "|cffffd100", "|cffaaaaaa", "|cffffffff"

local function BuildText()
    local level = UnitLevel("player")
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local className = UnitClass("player")
    add(format("%s%s|r  %s(%s %d)|r", WHITE, UnitName("player"), GREY, className, level))
    add(" ")
    add(GOLD .. "Learn now|r")
    if not ns.HasServiceData() then
        add(GREY .. "Talk to your class trainer once so I can read the spell list.|r")
    else
        local list, cost = ns.GetAvailable(level)
        if #list == 0 then add(GREY .. "Nothing new.|r") end
        for _, s in ipairs(list) do
            add(format("%s  %s(lvl %d · %s)|r", ns.SpellLabel(s), GREY, s.level, ns.Money(s.cost)))
        end
        if #list > 0 then add(WHITE .. "Total: " .. ns.Money(cost) .. "|r") end

        add(" ")
        add(GOLD .. "Coming up (next 10 levels)|r")
        local up = ns.GetUpcoming(level, 10)
        if #up == 0 then add(GREY .. "Nothing in the next 10 levels.|r") end
        for _, s in ipairs(up) do
            add(format("%sLevel %d|r  %s", GREY, s.level, ns.SpellLabel(s)))
        end
    end

    add(" ")
    add(GOLD .. "Professions|r")
    local any = false
    if GetProfessions then
        local idx = { GetProfessions() }
        for i = 1, 6 do
            if idx[i] then
                local name, _, rank, maxRank = GetProfessionInfo(idx[i])
                if name then
                    any = true
                    add(format("%s  %d / %d", name, rank, maxRank))
                end
            end
        end
    end
    if not any then add(GREY .. "No professions found.|r") end
    for _, e in ipairs(ns.Prof.Scan(level)) do
        add("|cffff9966" .. e.text .. "|r")
    end
    for _, r in ipairs(ns.Prof.NewRecipes(level)) do
        add(format("|cffff9966%d new %s recipe(s) at the trainer (%s)|r", r.count, r.name, ns.Money(r.cost)))
    end

    local quests = ns.Quests.Open(level)
    if #quests > 0 then
        add(" ")
        add(GOLD .. "Class quests|r")
        for _, q in ipairs(quests) do
            add(format("%s  %s(level %d · %s)|r", q.quest, GREY, q.level, q.reward))
        end
    end

    local talents = ns.UnspentTalents()
    if talents and talents > 0 then
        add(" ")
        add(GOLD .. "Talents|r")
        add(format("|cffff9966%d unspent point(s) – open your talents|r", talents))
    end

    local me, alts = ns.CharKey(), {}
    for key, c in pairs(ns.db.chars) do
        if key ~= me then alts[#alts + 1] = { key = key, c = c } end
    end
    if #alts > 0 and ns.db.showAlts then
        table.sort(alts, function(a, b) return a.key < b.key end)
        add(" ")
        add(GOLD .. "Your other characters|r " .. GREY .. "(as of their last login)|r")
        for _, a in ipairs(alts) do
            local c = a.c
            local what
            if not c.hasData then what = "hasn't visited a class trainer yet"
            elseif #c.spells > 0 then what = #c.spells .. " spell(s) to learn (" .. ns.Money(c.cost) .. ")"
            else what = "no spells to learn" end
            add(format("%s%s|r %s(%s %d)|r: %s", WHITE, c.name or a.key, GREY, c.class or "?", c.level or 0, what))
            for _, p in ipairs(c.profs or {}) do add("   |cffff9966" .. p .. "|r") end
        end
    end

    local skipped = {}
    for k in pairs(ns.char.skipped) do skipped[#skipped + 1] = k:gsub("|", " ") end
    if #skipped > 0 then
        table.sort(skipped)
        add(" ")
        add(GOLD .. "Skipped|r " .. GREY .. "(/tn unskip <spell>)|r")
        for _, k in ipairs(skipped) do add(GREY .. k .. "|r") end
    end
    return table.concat(lines, "\n")
end

function UI.Refresh()
    if not ns.db then return end
    ns.SaveSummary()
    if UI.minimap then
        local n = ns.HasServiceData() and #ns.GetAvailable() or 0
        UI.minimap.badge:SetText(n > 0 and n or "")
    end
    local f = UI.panel
    if f and f:IsShown() then
        f.text:SetText(BuildText())
        f.child:SetHeight(f.text:GetStringHeight() + 10)
    end
end

function UI.TogglePanel()
    if UI.panel:IsShown() then UI.panel:Hide() else UI.panel:Show() end
end

-- Options -------------------------------------------------------------------
local CHECKS = {
    { "remindLevelUp", "Remind me when I level up" },
    { "remindLogin",   "Remind me at login" },
    { "remindCity",    "Show the to-do list in capital cities" },
    { "remindNear",    "Show the to-do list when I'm near a trainer I need" },
    { "remindProf",    "Profession reminders" },
    { "remindQuests",  "Remind me about class quests" },
    { "remindTalents", "Remind me about unspent talent points" },
    { "remindRecipes", "Remind me about new profession recipes at the trainer" },
    { "showAlts",      "Show my other characters' to-do lists in the panel" },
    { "chat",          "Chat messages" },
    { "alert",         "On-screen alert" },
    { "sound",         "Sound" },
}

local function Stepper(parent, label, key, step, min, max, anchor, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    local function update() t:SetText(format(label, ns.db[key])) end
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(26, 22)
    minus:SetPoint("LEFT", t, "RIGHT", 10, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ns.db[key] = math.max(min, ns.db[key] - step); update() end)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(26, 22)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ns.db[key] = math.min(max, ns.db[key] + step); update() end)
    t.update = update
    return t
end

local function CreateOptions()
    local p = CreateFrame("Frame")
    p.name = "Squire"
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Squire")

    local last = title
    local boxes = {}
    for i, c in ipairs(CHECKS) do
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -12 or -2)
        local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(c[2])
        cb:SetScript("OnClick", function(self) ns.db[c[1]] = self:GetChecked() and true or false; UI.Refresh() end)
        cb.key = c[1]
        boxes[#boxes + 1] = cb
        last = cb
    end
    local yards = Stepper(p, "Trainer distance: %d yards", "nearYards", 10, 10, 100, last, -16)
    local warn = Stepper(p, "Warn %d points before a profession cap", "profWarn", 1, 0, 25, yards, -16)

    p:SetScript("OnShow", function()
        for _, cb in ipairs(boxes) do cb:SetChecked(ns.db[cb.key]) end
        yards.update()
        warn.update()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(p, "Squire")
        Settings.RegisterAddOnCategory(cat)
        UI.category = cat
    end
    UI.options = p
end

function UI.OpenOptions()
    if UI.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(UI.category:GetID())
    else
        ns.Print("Options: open Esc > Options > AddOns > Squire.")
    end
end

-- Talent bubble over the talent button --------------------------------------------
local function TalentButton()
    for _, n in ipairs({ "PlayerSpellsMicroButton", "TalentMicroButton" }) do
        local b = _G[n]
        if b and b.IsVisible and b:IsVisible() then return b end
    end
end

local function OpenTalents()
    local b = TalentButton()
    if b then
        b:Click()
    elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then
        PlayerSpellsUtil.ToggleClassTalentOrSpecFrame()
    elseif ToggleTalentFrame then
        ToggleTalentFrame()
    else
        ns.Print("Couldn't open the talents window – press your talents key.")
    end
end

local function CreateBubble()
    local f = CreateFrame("Button", "SquireTalentBubble", UIParent, "BackdropTemplate")
    f:SetSize(260, 52)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(1, 0.82, 0)

    -- the tail: a gold diamond under a dark one, half hidden behind the bubble
    local tail = CreateFrame("Frame", nil, f)
    tail:SetSize(20, 20)
    tail:SetPoint("CENTER", f, "BOTTOM", 0, 1)
    tail:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    local outer = tail:CreateTexture(nil, "BACKGROUND")
    outer:SetTexture("Interface\\Buttons\\WHITE8X8")
    outer:SetVertexColor(1, 0.82, 0)
    outer:SetSize(16, 16)
    outer:SetPoint("CENTER")
    outer:SetRotation(math.rad(45))
    local inner = tail:CreateTexture(nil, "ARTWORK")
    inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    inner:SetVertexColor(0.05, 0.05, 0.05)
    inner:SetSize(12, 12)
    inner:SetPoint("CENTER", 0, 1)
    inner:SetRotation(math.rad(45))

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.sub:SetText("Click here to open your talents.")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        ns.char.talentDismissedLevel = UnitLevel("player")
        UI.TalentBubble(0)
    end)

    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", function()
        OpenTalents()
    end)

    -- glow over the talent button (our own frame; the game's button is untouched)
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("DIALOG")
    glow:EnableMouse(false)
    local tex = glow:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0.82, 0)
    tex:SetAllPoints()
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.3)
    a:SetDuration(0.8)
    glow.anim = ag
    glow:Hide()
    f.glow = glow

    f:Hide()
    UI.bubble = f
    return f
end

function UI.TalentBubble(n)
    if InCombatLockdown() then return end
    local f = UI.bubble
    if not n or n <= 0 or ns.char.talentDismissedLevel == UnitLevel("player") then
        if f then f:Hide(); f.glow.anim:Stop(); f.glow:Hide() end
        return
    end
    f = f or CreateBubble()
    f.title:SetText(format("%d talent point%s to spend", n, n == 1 and "" or "s"))
    f:SetWidth(math.max(f.title:GetStringWidth(), f.sub:GetStringWidth()) + 50)
    f:ClearAllPoints()
    local b = TalentButton()
    if b then
        f:SetPoint("BOTTOM", b, "TOP", 0, 14)
        f:SetClampedToScreen(true)
        f.glow:ClearAllPoints()
        f.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
        f.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
        f.glow:Show()
        f.glow.anim:Play()
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
        f.glow:Hide()
    end
    f:Show()
end

function UI.Init()
    CreatePanel()
    CreateOptions()
    if not ns.db.minimap.hide then CreateMinimapButton() end
    UI.Refresh()
end
