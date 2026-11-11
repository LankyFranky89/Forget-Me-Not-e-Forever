-- Forget-Me-Not(e) Forever: minimap button, overview panel, options
local ADDON, ns = ...
local UI = {}
ns.UI = UI

local ICON = "Interface\\AddOns\\ForgetMeNot\\ForgetMeNot"

-- Minimap button -----------------------------------------------------------
local function PlaceButton(b)
    local a = math.rad(ns.db.minimap.angle)
    local r = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "ForgetMeNotMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
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
        if button == "MiddleButton" then
            UI.ToggleNotes()
        elseif button == "RightButton" then
            ns.Nearby.ShowList(true)
        elseif IsShiftKeyDown() then
            ns.Nearby.ShowRecipes(nil)
        else
            UI.TogglePanel()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forget-Me-Not(e) Forever", 1, 0.82, 0)
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
        GameTooltip:AddLine("Shift-click: what can I learn?", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Middle-click: my notes", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton(b)
    UI.minimap = b
end

-- Overview panel -------------------------------------------------------------
local function CreatePanel()
    local f = ns.MakeWindow("ForgetMeNotPanel")
    f:SetSize(520, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("Forget-Me-Not(e) Forever")
    tinsert(UISpecialFrames, "ForgetMeNotPanel")

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32)
    sf:SetPoint("BOTTOMRIGHT", -32, 44)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(466, 10)
    sf:SetScrollChild(child)
    f.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT")
    f.text:SetWidth(466)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(3)
    f.child = child

    local opt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    opt:SetSize(110, 22)
    opt:SetPoint("BOTTOMRIGHT", -12, 12)
    opt:SetText("Options")
    opt:SetScript("OnClick", function() UI.OpenOptions() end)

    local rec = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rec:SetSize(110, 22)
    rec:SetPoint("BOTTOMLEFT", 12, 12)
    rec:SetSize(140, 22)
    rec:SetText("What can I learn?")
    rec:SetScript("OnClick", function() ns.Nearby.ShowRecipes(nil) end)

    local notes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    notes:SetSize(100, 22)
    notes:SetPoint("LEFT", rec, "RIGHT", 6, 0)
    notes:SetText("My notes")
    notes:SetScript("OnClick", function() UI.ToggleNotes() end)

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

-- The game's profession book uses a themed fill for each profession's bar.
-- Borrow it from the book's own bars (once the book has been opened); otherwise use a colour.
local barLook = {}
local FALLBACK = {
    ["Leatherworking"] = { 0.62, 0.42, 0.24 }, ["Skinning"] = { 0.45, 0.75, 0.72 },
    ["First Aid"] = { 0.2, 0.75, 0.2 }, ["Cooking"] = { 0.85, 0.85, 0.9 },
    ["Fishing"] = { 0.3, 0.55, 0.9 }, ["Mining"] = { 0.6, 0.6, 0.65 },
    ["Herbalism"] = { 0.4, 0.75, 0.3 }, ["Blacksmithing"] = { 0.55, 0.55, 0.6 },
    ["Tailoring"] = { 0.75, 0.5, 0.8 }, ["Alchemy"] = { 0.4, 0.8, 0.5 },
    ["Enchanting"] = { 0.6, 0.45, 0.9 }, ["Engineering"] = { 0.85, 0.65, 0.25 },
}
local function LearnBarLooks()
    for _, n in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
        "SecondaryProfession2", "SecondaryProfession3", "SecondaryProfession4" }) do
        local fr = _G[n]
        local sb = fr and (fr.statusBar or fr.StatusBar)
        local label = sb and (sb.rankText or sb.RankText)
        local pname = fr and (fr.professionName or fr.ProfessionName)
        local key = pname and pname.GetText and pname:GetText()
        if (not key or key == "") and label and label.GetText then key = (label:GetText() or ""):match("^(.-)%s+%d") end
        local tex = sb and sb.GetStatusBarTexture and sb:GetStatusBarTexture()
        if key and key ~= "" and tex then
            local look = {}
            local ok, atlas = pcall(tex.GetAtlas, tex)
            if ok and atlas and atlas ~= "" then look.atlas = atlas else
                local ok2, file = pcall(tex.GetTexture, tex)
                if ok2 and file then look.file = file end
            end
            look.color = { tex:GetVertexColor() }
            if look.atlas or look.file then barLook[key] = look end
        end
    end
end

local function BuildText()
    local level = UnitLevel("player")
    local lines = {}
    local datas = {}
    local function add(s, data)
        lines[#lines + 1] = s
        datas[#lines] = data
    end

    local className = UnitClass("player")
    add(format("%s%s|r  %s(%s %d)|r", WHITE, UnitName("player"), GREY, className, level))
    add(" ")
    local col = ns.db.collapsed or {}
    ns.db.collapsed = col
    local function header(key, text, n)
        local arrow = col[key] and "|cffaaaaaa[+]|r " or "|cffaaaaaa[-]|r "
        add(arrow .. GOLD .. text .. "|r" .. (n and (" " .. GREY .. "(" .. n .. ")|r") or ""), { toggle = key })
    end
    if not ns.HasServiceData() then
        add(GOLD .. "Learn now|r")
        add(GREY .. "Talk to your class trainer once so I can read the spell list.|r")
    else
        local list, cost = ns.GetAvailable(level)
        header("learn", "Learn now", #list)
        if col.learn then list = {} cost = 0 elseif #list == 0 then add(GREY .. "Nothing new.|r") end
        for _, s in ipairs(list) do
            s.isSpell = true
            local icon = s.icon and format("|T%s:14:14|t ", tostring(s.icon)) or ""
            add(format("%s%s  %s(lvl %d · %s)|r", icon, ns.SpellLabel(s), GREY, s.level, ns.Money(s.cost)), s)
        end
        if #list > 0 then add(WHITE .. "Total: " .. ns.Money(cost) .. "|r") end

        add(" ")
        local up = ns.GetUpcoming(level, 10)
        header("upcoming", "Coming up (next 10 levels)", #up)
        if col.upcoming then up = {} elseif #up == 0 then add(GREY .. "Nothing in the next 10 levels.|r") end
        for _, s in ipairs(up) do
            s.isSpell = true
            local icon = s.icon and format("|T%s:14:14|t ", tostring(s.icon)) or ""
            add(format("%sLevel %d|r  %s%s", GREY, s.level, icon, ns.SpellLabel(s)), s)
        end
    end

    add(" ")
    add(GOLD .. "Professions|r")
    -- recipes per profession, not counting training tiers (Journeyman etc.)
    local recipeSum = {}
    for _, p in ipairs(ns.Prof.RecipeList(level)) do
        local count, cost = 0, 0
        for _, r in ipairs(p.list) do
            local isTier = false
            for _, t in pairs(ns.Prof.TIERS) do
                if (r.name or ""):find(t.next, 1, true) then isTier = true end
            end
            if not isTier then
                count = count + 1
                cost = cost + (r.cost or 0)
            end
        end
        recipeSum[p.name] = { count = count, cost = cost }
    end
    local any = false
    if GetProfessions then
        local idx = { GetProfessions() }
        for i = 1, 6 do
            if idx[i] then
                local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx[i])
                if name then
                    any = true
                    local r = recipeSum[name]
                    local extra
                    if r and r.count > 0 then
                        extra = format("%s%d recipe%s can be learned (%s)|r", GREY, r.count,
                            r.count == 1 and "" or "s", ns.Money(r.cost))
                    end
                    local ic = icon and format("|T%s:14:14|t ", tostring(icon)) or ""
                    add(format("%s%s%s|r  %s%d/%d|r", ic, WHITE, name, GREY, rank, maxRank) .. (extra and ("  " .. extra) or ""),
                        { prof = { name = name, skillLine = skillLine } })
                end
            end
        end
    end
    if not any then add(GREY .. "No professions found.|r") end
    for _, e in ipairs(ns.Prof.Scan(level)) do
        add("|cffff9966" .. e.text .. "|r")
    end

    local quests = ns.Quests.Open(level)
    if #quests > 0 then
        add(" ")
        add(GOLD .. "Class quests|r")
        for _, q in ipairs(quests) do
            add(format("%s  %s(level %d · %s)|r%s", q.quest, GREY, q.level, q.reward,
                q.inLog and " |cff66ff66in quest log|r" or ""))
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
    for k in pairs(ns.char.skipped) do skipped[#skipped + 1] = k end
    if #skipped > 0 then
        table.sort(skipped)
        add(" ")
        add(GOLD .. "Ignored|r " .. GREY .. "(not counted until you un-ignore)|r")
        for _, k in ipairs(skipped) do add(GREY .. k:gsub("|L%d+$", ""):gsub("|", " ") .. "|r", { unskip = k }) end
    end
    return lines, datas
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
        pcall(LearnBarLooks)
        local lines, datas = BuildText()
        f.text:Hide()
        f.rows = f.rows or {}
        local y = 0
        for i, line in ipairs(lines) do
            local r = f.rows[i]
            if not r then
                r = CreateFrame("Button", nil, f.child)
                r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                r.fs:SetPoint("TOPLEFT")
                r.fs:SetWidth(370)
                r.fs:SetJustifyH("LEFT")
                r.hl = r:CreateTexture(nil, "HIGHLIGHT")
                r.hl:SetAllPoints()
                r.hl:SetColorTexture(1, 0.82, 0, 0.10)
                r:SetScript("OnEnter", function(self)
                    if self.barData then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(self.barData.name, 1, 0.82, 0)
                        GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    elseif self.data and ns.Nearby.EntryTooltip then
                        ns.Nearby.EntryTooltip(self)
                    end
                end)
                r:SetScript("OnLeave", function() GameTooltip:Hide() end)
                r:RegisterForClicks("LeftButtonUp")
                r:SetScript("OnClick", function(self)
                    if self.toggle then
                        ns.db.collapsed[self.toggle] = not ns.db.collapsed[self.toggle] or nil
                        UI.Refresh()
                        return
                    end
                    local b = self.barData
                    if b then UI.OpenProfession(b) end
                end)
                f.rows[i] = r
            end
            local d = datas[i]
            local h
            if d and d.bar then
                -- skill bar like the game's profession bars
                if not r.bar then
                    local b = CreateFrame("StatusBar", nil, r)
                    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                    b:SetStatusBarColor(0.25, 0.4, 0.95)
                    b:SetHeight(18)
                    b:SetPoint("TOPLEFT", 0, -2)
                    b:SetPoint("TOPRIGHT", -10, -2)
                    b.bg = b:CreateTexture(nil, "BACKGROUND")
                    b.bg:SetAllPoints()
                    b.bg:SetColorTexture(0, 0, 0, 0.5)
                    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
                    b.border:SetPoint("TOPLEFT", -2, 2)
                    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
                    b.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
                    b.border:SetBackdropBorderColor(0.6, 0.6, 0.6)
                    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    b.label:SetPoint("CENTER")
                    b.icon = r:CreateTexture(nil, "ARTWORK")
                    b.icon:SetSize(20, 20)
                    b.icon:SetPoint("TOPLEFT", 0, -1)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 26, -2)
                    b:SetPoint("TOPRIGHT", -10, -2)
                    r.bar = b
                end
                local b = r.bar
                local look = barLook[d.bar.name]
                if look and look.atlas then
                    b:SetStatusBarTexture(look.atlas)
                    b:GetStatusBarTexture():SetVertexColor(unpack(look.color))
                elseif look and look.file then
                    b:SetStatusBarTexture(look.file)
                    b:GetStatusBarTexture():SetVertexColor(unpack(look.color))
                else
                    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                    local c = FALLBACK[d.bar.name] or { 0.25, 0.4, 0.95 }
                    b:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3])
                end
                b.bg:SetColorTexture(0, 0, 0, 0.85)
                b:SetMinMaxValues(0, math.max(1, d.bar.max))
                b:SetValue(d.bar.rank)
                b.label:SetText(format("%s %d/%d", d.bar.name, d.bar.rank, d.bar.max))
                b.icon:SetTexture(d.bar.icon)
                b.icon:Show()
                b:Show()
                r.fs:ClearAllPoints()
                r.fs:SetPoint("TOPLEFT", 30, -24)
                r.fs:SetText(d.bar.extra or "")
                h = 24 + (d.bar.extra and (r.fs:GetStringHeight() + 4) or 2)
            else
                if r.bar then r.bar:Hide(); r.bar.icon:Hide() end
                r.fs:ClearAllPoints()
                r.fs:SetPoint("TOPLEFT")
                r.fs:SetText(line == " " and "" or line)
                h = math.max(r.fs:GetStringHeight(), 8) + 3
            end
            -- Ignore / Un-ignore button on spell rows
            local skipKey = d and d.isSpell and (d.name .. "|" .. (d.rank ~= "" and d.rank or ("L" .. (d.level or 0))))
            local unskipKey = d and d.unskip
            if skipKey or unskipKey then
                if not r.ign then
                    r.ign = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
                    r.ign:SetSize(70, 16)
                    r.ign:SetPoint("TOPRIGHT", -12, 0)
                    r.ign:SetNormalFontObject("GameFontHighlightSmall")
                    r.ign:SetScript("OnClick", function(self)
                        if self.unskip then
                            ns.char.skipped[self.unskip] = nil
                        elseif self.skip then
                            ns.char.skipped[self.skip] = true
                        end
                        UI.Refresh()
                    end)
                end
                r.ign.skip, r.ign.unskip = skipKey, unskipKey
                r.ign:SetText(unskipKey and "Un-ignore" or "Ignore")
                r.ign:Show()
                h = math.max(h, 18)
            elseif r.ign then
                r.ign:Hide()
            end
            r:SetSize(466, h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -y)
            r.toggle = d and d.toggle or nil
            r.data = (d and not d.bar and not d.unskip and not d.toggle and not d.prof) and d or nil
            r.barData = d and (d.bar or d.prof) or nil
            r:EnableMouse(r.data ~= nil or r.barData ~= nil or r.toggle ~= nil)
            r:Show()
            y = y + h
        end
        for i = #lines + 1, #f.rows do f.rows[i]:Hide() end
        f.child:SetHeight(y + 10)
    end
end

-- My notes: a free-text notepad, saved per character -----------------------------
local function CreateNotes()
    local f = ns.MakeWindow("ForgetMeNotNotesFrame")
    f:SetSize(380, 340)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.TitleText:SetText("My notes – " .. (UnitName("player") or ""))
    tinsert(UISpecialFrames, "ForgetMeNotNotesFrame")

    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 12, -32)
    bg:SetPoint("BOTTOMRIGHT", -12, 34)
    bg:SetColorTexture(0, 0, 0, 0.35)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -36)
    sf:SetPoint("BOTTOMRIGHT", -34, 38)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(320)
    eb:SetMaxLetters(5000)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then ns.char.notes = self:GetText() end
        sf:UpdateScrollChildRect()
    end)
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        -- keep the cursor in view while typing
        local top, height = sf:GetVerticalScroll(), sf:GetHeight()
        y = -y
        if y < top then sf:SetVerticalScroll(y)
        elseif y + h > top + height then sf:SetVerticalScroll(y + h - height) end
    end)
    sf:SetScrollChild(eb)
    -- clicking anywhere in the box starts typing
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.edit = eb

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 14)
    hint:SetText("Saved automatically for this character.")

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(80, 22)
    clear:SetPoint("BOTTOMRIGHT", -12, 8)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() StaticPopup_Show("FORGETMENOT_CLEARNOTES") end)

    StaticPopupDialogs["FORGETMENOT_CLEARNOTES"] = {
        text = "Delete all your notes for this character?",
        button1 = YES, button2 = NO, timeout = 0, hideOnEscape = true,
        OnAccept = function() ns.char.notes = ""; eb:SetText("") end,
    }
    UI.notes = f
    return f
end

function UI.ToggleNotes()
    local f = UI.notes or CreateNotes()
    if f:IsShown() then f:Hide() return end
    f.edit:SetText(ns.char.notes or "")
    f:ClearAllPoints()
    local panel = UI.panel
    if panel and panel:IsShown() then
        if (panel:GetLeft() or 0) > 400 then
            f:SetPoint("TOPRIGHT", panel, "TOPLEFT", -8, 0)
        else
            f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
        end
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    f.edit:SetFocus()
    f.edit:SetCursorPosition(#(ns.char.notes or ""))
end

-- Open a profession's window (or the profession book for gathering skills)
function UI.OpenProfession(b)
    if InCombatLockdown() then
        ns.Print("Can't open professions in combat.")
        return
    end
    if b.skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
        local ok, res = pcall(C_TradeSkillUI.OpenTradeSkill, b.skillLine)
        if ok and res ~= false then return end
    end
    -- no crafting window (e.g. Skinning): open the profession book instead
    if ToggleProfessionsBook then
        pcall(ToggleProfessionsBook)
    elseif ToggleSpellBook then
        pcall(ToggleSpellBook, BOOKTYPE_PROFESSION)
    end
end

function UI.TogglePanel()
    if UI.panel:IsShown() then UI.panel:Hide() else UI.panel:Show() end
end

-- Options -------------------------------------------------------------------
-- Two columns of small groups. "-" entries are group headings.
local COLUMNS = {
    {
        { "-", "Show my to-do list" },
        { "remindLevelUp", "When I level up" },
        { "remindLogin",   "At login" },
        { "remindCity",    "In capital cities" },
        { "remindNear",    "Near a trainer I need" },
        { "-", "Class" },
        { "remindQuests",  "Class quests" },
        { "remindTalents", "Unspent talent points" },
        { "-", "Professions" },
        { "remindProf",    "Next rank / skill cap" },
        { "remindRecipes", "New recipes at the trainer" },
        { "remindBagRecipes", "Recipes in my bags or bank" },
        { "remindCapCraft", "Warn on every craft while capped" },
    },
    {
        { "-", "Travel" },
        { "remindInn",     "Bind hearthstone at a new inn" },
        { "remindFlight",  "Undiscovered flight paths" },
        { "remindDeparture", "'Before you leave' window" },
        { "-", "Supplies" },
        { "remindSupplies", "Food & drink (20 or fewer)" },
        { "remindAmmo",    "Arrows & bullets (400 or fewer)" },
        { "-", "How I'm told" },
        { "chat",          "Chat message" },
        { "alert",         "On-screen alert" },
        { "sound",         "Sound" },
        { "-", "Panel" },
        { "showAlts",      "Show my other characters" },
    },
}

local function Stepper(parent, label, key, step, min, max, anchor, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, y)
    local function update() t:SetText(format(label, ns.db[key])) end
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(22, 18)
    minus:SetPoint("LEFT", t, "RIGHT", 10, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ns.db[key] = math.max(min, ns.db[key] - step); update() end)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(22, 18)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ns.db[key] = math.min(max, ns.db[key] + step); update() end)
    t.update = update
    return t
end

local function CreateOptions()
    local p = CreateFrame("Frame")
    p.name = "Forget-Me-Not(e) Forever"
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forget-Me-Not(e) Forever")

    local boxes = {}
    local bottom
    for col, list in ipairs(COLUMNS) do
        local y = -48
        local x = col == 1 and 16 or 330
        for _, c in ipairs(list) do
            if c[1] == "-" then
                if y < -48 then y = y - 8 end
                local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                h:SetPoint("TOPLEFT", x, y)
                h:SetText(c[2])
                y = y - 18
            else
                local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("TOPLEFT", x + 4, y)
                local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                label:SetText(c[2])
                cb:SetScript("OnClick", function(self) ns.db[c[1]] = self:GetChecked() and true or false; UI.Refresh() end)
                cb.key = c[1]
                boxes[#boxes + 1] = cb
                y = y - 20
            end
        end
        if not bottom or y < bottom then bottom = y end
    end
    local anchor = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchor:SetPoint("TOPLEFT", 16, bottom - 8)
    anchor:SetText("Settings")
    local yards = Stepper(p, "Trainer distance: %d yards", "nearYards", 10, 10, 100, anchor, -6)
    local warn = Stepper(p, "Warn %d points before a profession cap", "profWarn", 1, 0, 25, yards, -10)

    p:SetScript("OnShow", function()
        for _, cb in ipairs(boxes) do cb:SetChecked(ns.db[cb.key]) end
        yards.update()
        warn.update()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(p, "Forget-Me-Not(e) Forever")
        Settings.RegisterAddOnCategory(cat)
        UI.category = cat
    end
    UI.options = p
end

function UI.OpenOptions()
    if UI.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(UI.category:GetID())
    else
        ns.Print("Options: open Esc > Options > AddOns > Forget-Me-Not(e) Forever.")
    end
end

-- Talent bubble over the talent button --------------------------------------------
local function TalentButton()
    for _, n in ipairs({ "TalentMicroButton", "PlayerSpellsMicroButton", "TalentsMicroButton", "ClassTalentMicroButton" }) do
        local b = _G[n]
        if b and b.IsVisible and b:IsVisible() then return b end
    end
end
UI.TalentButton = TalentButton

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
    local f = CreateFrame("Button", "ForgetMeNotTalentBubble", UIParent, "BackdropTemplate")
    f:SetSize(320, 70)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(1, 0.82, 0)

    -- the tail: a gold diamond under a dark one, half hidden behind the bubble
    local tail = CreateFrame("Frame", nil, f)
    tail:SetSize(24, 24)
    tail:SetPoint("CENTER", f, "BOTTOM", 0, 1)
    tail:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    local outer = tail:CreateTexture(nil, "BACKGROUND")
    outer:SetTexture("Interface\\Buttons\\WHITE8X8")
    outer:SetVertexColor(1, 0.82, 0)
    outer:SetSize(20, 20)
    outer:SetPoint("CENTER")
    outer:SetRotation(math.rad(45))
    local inner = tail:CreateTexture(nil, "ARTWORK")
    inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    inner:SetVertexColor(0.05, 0.05, 0.05)
    inner:SetSize(15, 15)
    inner:SetPoint("CENTER", 0, 1)
    inner:SetRotation(math.rad(45))

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sub:SetText("Click here to open your talents.")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        UI.talentDismissedAt = GetTime()  -- comes back after 15 minutes
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
    local snoozed = UI.talentDismissedAt and (GetTime() - UI.talentDismissedAt) < 900
    if not n or n <= 0 or snoozed then
        if f then f:Hide(); f.glow.anim:Stop(); f.glow:Hide() end
        return
    end
    f = f or CreateBubble()
    f.title:SetText(format("%d talent point%s to spend", n, n == 1 and "" or "s"))
    f:SetWidth(math.max(f.title:GetStringWidth(), f.sub:GetStringWidth()) + 70)
    f:ClearAllPoints()
    local b = TalentButton()
    if b then
        f:SetPoint("BOTTOM", b, "TOP", 0, 16)
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
