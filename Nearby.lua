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
        if e.state == "train" then
            tasks[#tasks + 1] = {
                title = e.name,
                detail = format("Learn %s (%d/%d)", e.rule.next, e.rank, e.max),
                trainer = FindTrainer(function(t) return t.kind == "profession" and t.prof == e.name end),
            }
        end
    end
    if ns.db.remindRecipes then
        for _, r in ipairs(ns.Prof.NewRecipes()) do
            tasks[#tasks + 1] = {
                title = r.name .. " recipes",
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

local function CreateList()
    local f = ns.MakeWindow("SquireListFrame")
    f:SetSize(380, 90)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SquireListFrame")  -- Esc closes it
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(350, 40)
        r:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 44)
        r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.title:SetPoint("TOPLEFT")
        r.title:SetPoint("RIGHT", -90, 0)
        r.title:SetJustifyH("LEFT")
        r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
        r.detail:SetPoint("RIGHT", -90, 0)
        r.detail:SetJustifyH("LEFT")
        r.detail:SetMaxLines(2)
        r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.btn:SetSize(84, 22)
        r.btn:SetPoint("RIGHT")
        r.btn:SetText("Waypoint")
        r.btn:SetScript("OnClick", function(b) if b.trainer then SetWaypoint(b.trainer) end end)
        f.rows[i] = r
    end
    f.hide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.hide:SetSize(140, 22)
    f.hide:SetPoint("BOTTOM", 0, 10)
    f.hide:SetText("Hide in this zone")
    f.hide:SetScript("OnClick", function()
        hiddenZone[GetRealZoneText()] = true
        f:Hide()
    end)
    N.frame = f
    return f
end

-- forced = opened by the user (/tn list or minimap right-click)
function N.ShowList(forced)
    local tasks = N.BuildTasks()
    if #tasks == 0 then
        if forced then ns.Print("Nothing to train right now.") end
        if N.frame then N.frame:Hide() end
        return
    end
    local f = N.frame or CreateList()
    local zone = GetRealZoneText()
    f.TitleText:SetText(UnitName("player") .. " – to do" .. (zone and zone ~= "" and (" in " .. zone) or ""))
    local shown = math.min(#tasks, ROWS)
    for i = 1, ROWS do
        local r, t = f.rows[i], tasks[i]
        if i <= shown then
            local tr = t.trainer
            r.title:SetText(t.title .. (tr and ("  |cffbbbbbb– " .. tr.name .. (tr.zone and (", " .. tr.zone) or "") .. "|r") or ""))
            r.detail:SetText(t.detail)
            r.btn.trainer = tr
            if tr then r.btn:Show() else r.btn:Hide() end
            r:Show()
        else
            r:Hide()
        end
    end
    f:SetHeight(30 + shown * 44 + 40)
    f:Show()
end

function N.OnZone()
    if not ns.db or not ns.db.remindCity then return end
    local zone = GetRealZoneText()
    if zone and (N.CAPITALS[zone] or ns.db.cities[zone]) and not hiddenZone[zone] then
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
                if not hiddenZone[GetRealZoneText()] then N.ShowList(false) end
                return
            end
        end
    end
end

function N.Init()
    C_Timer.NewTicker(2, Tick)
end
