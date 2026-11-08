-- Squire: to-do list in cities and near trainers you need
local ADDON, ns = ...
local N = {}
ns.Nearby = N

local hiddenZone = {}      -- "Hide in this city" for this session
local nearNotified = {}    -- trainer key -> time last shown
local ROWS = 8

-- All six Vanilla capitals (English zone names)
N.CAPITALS = {
    ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true,
    ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true,
}

local function PlayerWorldPos()
    if not C_Map then return end
    if IsInInstance and IsInInstance() then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local cont, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
    if not world then return end
    return cont, world.x, world.y
end

local function Distance(t, cont, x, y)
    if not t.wx or t.cont ~= cont then return nil end
    local dx, dy = t.wx - x, t.wy - y
    return math.sqrt(dx * dx + dy * dy)
end

-- Find a recorded trainer: same zone first, else nearest on this continent
local function FindTrainer(match)
    local zone = GetRealZoneText()
    local cont, x, y = PlayerWorldPos()
    local best, bestD
    for key, t in pairs(ns.db.trainers) do
        if match(t) then
            local d = cont and Distance(t, cont, x, y) or math.huge
            if t.zone == zone then d = d - 100000 end
            if not bestD or d < bestD then best, bestD = t, d end
        end
    end
    return best
end

-- Everything you could do at a trainer right now
function N.BuildTasks()
    local tasks = {}
    local _, classFile = UnitClass("player")
    local spells, cost = ns.GetAvailable()
    if #spells > 0 then
        local names = {}
        for i, s in ipairs(spells) do names[i] = ns.SpellLabel(s) end
        tasks[#tasks + 1] = {
            title = "Class trainer",
            detail = format("%d spell(s): %s · %s", #spells, table.concat(names, ", "), ns.Money(cost)),
            trainer = FindTrainer(function(t) return t.kind == "class" and t.class == classFile end),
        }
    end
    for _, e in ipairs(ns.Prof.Scan()) do
        if e.state == "train" or e.state == "capped" then
            local detail
            if e.state == "train" then
                detail = format("Learn %s (%d/%d)", e.rule.next, e.rank, e.max)
            else
                detail = format("Capped at %d/%d – %s needs level %d", e.rank, e.max, e.rule.next, e.reqLevel or 0)
            end
            tasks[#tasks + 1] = {
                title = e.name,
                detail = detail,
                trainer = FindTrainer(function(t) return t.kind == "profession" and t.prof == e.name end),
            }
        end
    end
    if ns.db.remindRecipes then
        for _, r in ipairs(ns.Prof.NewRecipes()) do
            tasks[#tasks + 1] = {
                title = r.name .. " recipes",
                recipeProf = r.name,
                detail = format("%d new recipe(s) · %s", r.count, ns.Money(r.cost)),
                trainer = FindTrainer(function(t) return t.kind == "profession" and t.prof == r.name end),
            }
        end
    end
    if ns.db.remindQuests then
        for _, q in ipairs(ns.Quests.Open()) do
            tasks[#tasks + 1] = {
                title = "Class quest",
                detail = format("%s – rewards %s", q.quest, q.reward),
                trainer = FindTrainer(function(t) return t.kind == "class" and t.class == classFile end),
            }
        end
    end
    local talents = ns.db.remindTalents and ns.UnspentTalents()
    if talents and talents > 0 then
        tasks[#tasks + 1] = { title = "Talents", detail = format("%d unspent point(s) – open your talents", talents) }
    end
    return tasks
end

local function SetWaypoint(t)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(t.mapID) then
        ns.Print("Can't place a waypoint on that map.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(t.mapID, t.x, t.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    ns.Print(format("Waypoint set: %s (%.1f, %.1f)", t.name, t.x * 100, t.y * 100))
end

-- To-do section styled like a quest tracker block -------------------------------
local LINE_FONT = _G.ObjectiveTrackerLineFont and "ObjectiveTrackerLineFont" or "GameFontHighlight"
local HEAD_FONT = _G.ObjectiveTrackerHeaderFont and "ObjectiveTrackerHeaderFont" or "GameFontNormalMed2"
local TITLE_FONT = "GameFontNormal"

local function TrackerWidth()
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetWidth then
        local w = ObjectiveTrackerFrame:GetWidth()
        if w and w > 150 then return w end
    end
    return 260
end

local function RowClick(r, button)
    local t = r.task
    if not t then return end
    if t.recipeProf then
        N.ShowRecipes(t.recipeProf)
    elseif t.trainer then
        SetWaypoint(t.trainer)
    end
end

local function RowEnter(r)
    local t = r.task
    if not t then return end
    GameTooltip:SetOwner(r, "ANCHOR_LEFT")
    GameTooltip:AddLine(t.title, 1, 0.82, 0)
    GameTooltip:AddLine(t.detail, 1, 1, 1, true)
    if t.trainer then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(t.trainer.name .. (t.trainer.zone and (", " .. t.trainer.zone) or ""), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    if t.recipeProf then
        GameTooltip:AddLine("Click: show learnable recipes", 0.5, 0.8, 1)
    end
    if t.trainer then
        GameTooltip:AddLine((t.recipeProf and "Shift-click" or "Click") .. ": set waypoint to trainer", 0.5, 0.8, 1)
    end
    GameTooltip:Show()
end

local function CreateList()
    local f = CreateFrame("Frame", "SquireListFrame", UIParent)
    f:SetSize(TrackerWidth(), 30)
    f:SetFrameStrata("LOW")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if N.editing then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if N.editing then
            local right, bottom = self:GetRight(), self:GetBottom()
            local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            ns.db.listPos = { x = right * sc - UIParent:GetWidth(), y = bottom * sc }
            N.PlaceList()
        end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if N.editing and button == "RightButton" then
            ns.db.listPos = nil
            N.PlaceList()
        end
    end)

    -- header like the tracker's "Quests" header: title + collapse button, click to toggle
    local head = CreateFrame("Button", nil, f)
    head:SetHeight(24)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:RegisterForClicks("LeftButtonUp")
    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints()
    head.bg:SetColorTexture(0, 0, 0, 0.35)
    head.line = head:CreateTexture(nil, "ARTWORK")
    head.line:SetHeight(1)
    head.line:SetPoint("BOTTOMLEFT")
    head.line:SetPoint("BOTTOMRIGHT")
    head.line:SetColorTexture(1, 0.82, 0, 0.6)
    head.text = head:CreateFontString(nil, "OVERLAY", HEAD_FONT)
    head.text:SetPoint("LEFT", 8, 0)
    head.text:SetJustifyH("LEFT")
    head.sign = head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head.sign:SetPoint("RIGHT", -8, 0)
    head:SetScript("OnClick", function()
        if N.editing then return end
        ns.db.listCollapsed = not ns.db.listCollapsed
        N.ShowList(true)
    end)
    head:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Squire", 1, 0.82, 0)
        GameTooltip:AddLine("Click to " .. (ns.db.listCollapsed and "expand" or "collapse"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.head = head

    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:RegisterForClicks("LeftButtonUp")
        r.title = r:CreateFontString(nil, "OVERLAY", TITLE_FONT)
        r.title:SetPoint("TOPLEFT", 10, 0)
        r.title:SetPoint("RIGHT", -6, 0)
        r.title:SetJustifyH("LEFT")
        r.title:SetWordWrap(false)
        r.detail = r:CreateFontString(nil, "OVERLAY", LINE_FONT)
        r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 10, -2)
        r.detail:SetPoint("RIGHT", -6, 0)
        r.detail:SetJustifyH("LEFT")
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.82, 0, 0.08)
        r:SetScript("OnClick", function(self)
            if IsShiftKeyDown() and self.task and self.task.trainer then
                SetWaypoint(self.task.trainer)
            else
                RowClick(self)
            end
        end)
        r:SetScript("OnEnter", RowEnter)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.rows[i] = r
    end

    -- Edit Mode highlight
    f.edit = CreateFrame("Frame", nil, f)
    f.edit:SetAllPoints()
    f.edit:SetFrameLevel(f:GetFrameLevel() + 20)
    local hl = f.edit:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(0.25, 0.55, 1, 0.25)
    local lbl = f.edit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("CENTER")
    lbl:SetText("Squire\n|cffaaaaaaDrag to move · right-click to reset|r")
    f.edit:EnableMouse(false)
    f.edit:Hide()

    N.frame = f
    N.PlaceList()
    return f
end

-- Default: directly above the quest tracker, same width. After Edit Mode: where you put it.
function N.PlaceList()
    local f = N.frame
    if not f then return end
    f:ClearAllPoints()
    local pos = ns.db.listPos
    if pos then
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", pos.x, pos.y)
    elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame:GetTop() then
        f:SetPoint("BOTTOMRIGHT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 4)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -260)
    end
end

-- Hook into the game's own Edit Mode
local function EnterEdit()
    N.editing = true
    local f = N.frame or CreateList()
    N.ShowList(true, true)
    f.edit:Show()
end

local function ExitEdit()
    N.editing = false
    if not N.frame then return end
    N.frame.edit:Hide()
    N.ShowList(false)
end

function N.HookEditMode()
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", EnterEdit, N)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", ExitEdit, N)
    end
end

-- Draws the section. Always visible while there is something to do.
-- forced: user asked for it; preview: Edit Mode with an example line
function N.ShowList(forced, preview)
    if not ns.db then return end
    local tasks = N.BuildTasks()
    if #tasks == 0 and (preview or N.editing) then
        tasks = { { title = "Example", detail = "Your to-do list shows here." } }
    end
    local f = N.frame or (#tasks > 0 and CreateList()) or nil
    if not f then
        if forced then ns.Print("Nothing to train right now.") end
        return
    end
    if #tasks == 0 or not ns.db.trackerSection then
        if forced and #tasks == 0 then ns.Print("Nothing to train right now.") end
        f:Hide()
        return
    end
    if InCombatLockdown() and not f:IsShown() then return end

    f:SetWidth(TrackerWidth())
    local collapsed = ns.db.listCollapsed and not N.editing
    f.head.text:SetText(format("Squire – to do (%d)", #tasks))
    f.head.sign:SetText(collapsed and "+" or "–")

    local y = 26
    local shown = collapsed and 0 or math.min(#tasks, ROWS)
    for i = 1, ROWS do
        local r = f.rows[i]
        if i <= shown then
            local t = tasks[i]
            r.task = t
            r.title:SetText(t.title)
            r.detail:SetText(t.detail)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            r:SetWidth(f:GetWidth())
            local h = r.title:GetStringHeight() + 2 + r.detail:GetStringHeight() + 6
            r:SetHeight(h)
            r:Show()
            y = y + h
        else
            r.task = nil
            r:Hide()
        end
    end
    f:SetHeight(y + (shown > 0 and 4 or 0))
    N.PlaceList()
    f:Show()
end

-- "What can I learn?" window: one row per spell/recipe with icon and tooltip.
-- prof = nil shows class spells and every profession.
local ROW_H = 20
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function RowTooltip(row)
    local d = row.data
    if not d then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = false
    if d.link then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
    end
    if not shown then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(d.name .. ((d.rank and d.rank ~= "") and (" (" .. d.rank .. ")") or ""), 1, 0.82, 0)
        if d.desc then GameTooltip:AddLine(d.desc, 1, 1, 1, true) end
    end
    GameTooltip:AddLine(" ")
    if d.skill and d.skill > 0 then GameTooltip:AddLine("Requires skill " .. d.skill, 0.7, 0.7, 0.7) end
    if d.level and d.level > 0 then GameTooltip:AddLine("Requires level " .. d.level, 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Cost: " .. ns.Money(d.cost), 1, 1, 1)
    if not d.link and not d.desc then
        GameTooltip:AddLine("Visit the trainer again to see more details.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function GetRow(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f.content)
    row:SetSize(410, ROW_H)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 0.82, 0, 0.12)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
    return row
end

function N.ShowRecipes(prof)
    local f = N.recipeFrame
    if not f then
        f = ns.MakeWindow("SquireRecipeFrame")
        f:SetSize(450, 200)
        f:SetPoint("CENTER", 0, 60)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "SquireRecipeFrame")
        f.content = CreateFrame("Frame", nil, f)
        f.content:SetPoint("TOPLEFT", 16, -32)
        f.content:SetSize(410, 10)
        f.rows = {}
        f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.footer:SetPoint("BOTTOMLEFT", 16, 14)
        f.footer:SetPoint("RIGHT", -16, 0)
        f.footer:SetJustifyH("LEFT")
        N.recipeFrame = f
    end

    local money = GetMoney()
    local items = {}   -- { header = text } or { data = entry }
    local grand = 0
    if not prof and ns.HasServiceData() then
        local spells, cost = ns.GetAvailable()
        if #spells > 0 then
            grand = grand + cost
            items[#items + 1] = { header = format("|cffffd100Class trainer|r |cffaaaaaa(%s)|r", ns.Money(cost)) }
            for _, sp in ipairs(spells) do items[#items + 1] = { data = sp } end
        end
    end
    for _, entry in ipairs(ns.Prof.RecipeList()) do
        if not prof or entry.name == prof then
            grand = grand + entry.cost
            items[#items + 1] = { header = format("|cffffd100%s|r |cffaaaaaa(%s)|r", entry.name, ns.Money(entry.cost)) }
            for _, r in ipairs(entry.list) do items[#items + 1] = { data = r } end
        end
    end

    local y = 0
    local maxRows = 30
    local used = 0
    for i, it in ipairs(items) do
        if i > maxRows then break end
        used = i
        local row = GetRow(f, i)
        row:ClearAllPoints()
        if it.header then
            if i > 1 then y = y + 6 end
            row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
            row.icon:Hide()
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", 0, 0)
            row.text:SetPoint("RIGHT", -2, 0)
            row.text:SetText(it.header)
            row.data = nil
            row:EnableMouse(false)
        else
            local d = it.data
            row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 8, -y)
            row.icon:SetTexture(d.icon or QUESTION)
            row.icon:Show()
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", -2, 0)
            local label = d.name .. ((d.rank and d.rank ~= "") and (" (" .. d.rank .. ")") or "")
            local prefix = (d.skill and d.skill > 0) and format("|cffaaaaaa[%d]|r ", d.skill) or ""
            if (d.cost or 0) > money then
                row.text:SetText(prefix .. format("|cffff5555%s – %s|r", label, ns.Money(d.cost)))
            else
                row.text:SetText(prefix .. format("%s – %s", label, ns.Money(d.cost)))
            end
            row.data = d
            row:EnableMouse(true)
        end
        row:Show()
        y = y + ROW_H
    end
    for i = used + 1, #f.rows do f.rows[i]:Hide() end

    local foot = {}
    if #items == 0 then
        foot[1] = "Nothing to learn right now.\n|cffaaaaaaTalk to your trainers to update this list.|r"
    else
        if #items > maxRows then foot[#foot + 1] = format("|cffaaaaaa…and %d more|r", #items - maxRows) end
        foot[#foot + 1] = format("|cffffd100Total:|r %s   |cffffd100You have:|r %s", ns.Money(grand), ns.Money(money))
        if grand > money then foot[#foot + 1] = "|cffff5555Red = can't afford yet.|r" end
    end
    f.footer:SetText(table.concat(foot, "\n"))
    f.TitleText:SetText(prof and (prof .. " – learnable recipes") or "What can I learn?")
    f:SetHeight(y + f.footer:GetStringHeight() + 60)
    f:Show()
end

function N.OnZone()
    if not ns.db or not ns.db.remindCity then return end
    local zone = GetRealZoneText()
    if zone and (N.CAPITALS[zone] or ns.db.cities[zone]) then
        N.ShowList(false)
    end
end

-- Every 2 seconds: are you close to a trainer you need?
local function Tick()
    if not ns.db.remindNear or InCombatLockdown() then return end
    local cont, x, y = PlayerWorldPos()
    if not cont then return end
    local tasks = N.BuildTasks()
    local now = GetTime()
    for _, task in ipairs(tasks) do
        local t = task.trainer
        if t then
            local d = Distance(t, cont, x, y)
            local key = t.name .. "@" .. t.mapID
            if d and d <= ns.db.nearYards and (not nearNotified[key] or now - nearNotified[key] > 600) then
                nearNotified[key] = now
                ns.Print(format("%s is close by (%d yd): %s", t.name, math.floor(d), task.detail))
                N.ShowList(false)
                return
            end
        end
    end
end

function N.Init()
    N.HookEditMode()
    C_Timer.NewTicker(2, Tick)
    -- keep the tracker section current
    C_Timer.NewTicker(5, function()
        if not InCombatLockdown() then N.ShowList(false) end
    end)
    C_Timer.After(3, function() N.ShowList(false) end)
end
