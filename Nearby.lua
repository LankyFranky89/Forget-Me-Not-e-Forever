-- Forget-Me-Not(e) Forever: to-do list in cities and near trainers you need
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

-- Built-in trainer list (TrainerDB.lua), turned into the same shape as recorded trainers
local builtin
local function Builtin()
    if builtin then return builtin end
    builtin = {}
    local fac = (UnitFactionGroup("player") == "Horde") and "H" or "A"
    -- check the axis order once against trainers you've actually visited
    local swap = false
    local seen = {}
    for _, t in pairs(ns.db.trainers or {}) do if t.wx then seen[t.name] = t end end
    for _, r in ipairs(ns.TRAINER_DB or {}) do
        local v = seen[r[1]]
        if v and v.cont == r[6] then
            local straight = math.abs(v.wx - r[7]) + math.abs(v.wy - r[8])
            local swapped = math.abs(v.wx - r[8]) + math.abs(v.wy - r[7])
            swap = swapped < straight
            break
        end
    end
    for _, r in ipairs(ns.TRAINER_DB or {}) do
        if r[5] == "N" or r[5] == fac then
            builtin[#builtin + 1] = {
                name = r[1], builtin = true,
                kind = r[2] == "c" and "class" or "profession",
                class = r[2] == "c" and r[3] or nil,
                prof = r[2] == "p" and r[3] or nil,
                max = r[4], cont = r[6],
                wx = swap and r[8] or r[7], wy = swap and r[7] or r[8],
            }
        end
    end
    return builtin
end

-- Find the closest trainer: ones you've visited plus the built-in list.
-- need = skill cap you're training towards (skips Journeyman trainers when you need Expert, etc.)
local function FindTrainer(match, need)
    local cont, x, y = PlayerWorldPos()
    local best, bestD
    local function try(t)
        if not match(t) then return end
        if need and t.max and t.max < need then return end
        local d = cont and Distance(t, cont, x, y) or nil
        if not d then d = (t.zone == GetRealZoneText()) and 1e8 or 1e9 end
        if not bestD or d < bestD then best, bestD = t, d end
    end
    for _, t in pairs(ns.db.trainers) do try(t) end
    for _, t in ipairs(Builtin()) do try(t) end
    return best
end

-- Undiscovered flight paths in the zone you're in --------------------------------
local function PlayerFaction()
    local f = UnitFactionGroup("player")
    if not Enum or not Enum.FlightPathFaction then return nil end
    return f == "Horde" and Enum.FlightPathFaction.Horde or Enum.FlightPathFaction.Alliance
end

-- Returns { name, mapID, x, y } for flight paths on this zone's map you haven't learned
function N.UnknownFlightPaths()
    local out = {}
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map and Enum and Enum.FlightPathState) then return out end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return out end
    -- climb to the zone map, so a city district still finds the zone's flight master
    local info = C_Map.GetMapInfo(mapID)
    while info and info.mapType and Enum.UIMapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 do
        mapID = info.parentMapID
        info = C_Map.GetMapInfo(mapID)
    end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not ok or type(nodes) ~= "table" then return out end
    local mine = PlayerFaction()
    for _, n in ipairs(nodes) do
        local factionOK = (n.faction == nil) or (n.faction == Enum.FlightPathFaction.Neutral) or (mine and n.faction == mine)
        if n.state == Enum.FlightPathState.Unreachable and factionOK and n.position then
            local x, y = n.position.x, n.position.y
            if n.position.GetXY then x, y = n.position:GetXY() end
            out[#out + 1] = { name = n.name, mapID = mapID, x = x, y = y, zone = GetRealZoneText() }
        end
    end
    return out
end

local fpSeen = {}
function N.CheckFlightPaths()
    if not ns.db or not ns.db.remindFlight then return end
    for _, fp in ipairs(N.UnknownFlightPaths()) do
        if not fpSeen[fp.name] then
            fpSeen[fp.name] = true
            ns.Print(format("New flight path nearby: %s – talk to the flight master to learn it. (Waypoint in the to-do list)", fp.name))
            if UIErrorsFrame then UIErrorsFrame:AddMessage("Undiscovered flight path: " .. fp.name, 0.4, 0.8, 1) end
        end
    end
end

-- /fmn flights: what the game reports for this zone
function N.DebugFlights()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
        ns.Print("This client has no flight path map data for addons.")
        return
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    ns.Print(format("Map %s: %s", tostring(mapID), ok and (type(nodes) == "table" and (#nodes .. " flight path(s)") or "none") or "error"))
    if ok and type(nodes) == "table" then
        for _, n in ipairs(nodes) do
            ns.Print(format("  %s · state %s · faction %s", tostring(n.name), tostring(n.state), tostring(n.faction)))
        end
    end
    local unknown = N.UnknownFlightPaths()
    ns.Print(#unknown .. " undiscovered for you in this zone.")
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
                trainer = FindTrainer(function(t) return t.kind == "profession" and t.prof == e.name end,
                    e.state == "train" and (e.max or 0) + 1 or nil),
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
    if ns.db.remindBagRecipes and ns.Prof.BagRecipes then
        for _, r in ipairs(ns.Prof.BagRecipes()) do
            if r.ready then
                tasks[#tasks + 1] = { title = "Recipe in your " .. r.where, detail = format("%s – learn it (%s %d)", r.link, r.prof, r.skill) }
            end
        end
    end
    local miss, mtext = ns.MissingSupplies()
    if #miss > 0 then
        tasks[#tasks + 1] = { title = "Supplies", detail = "You have " .. table.concat(mtext, " and ") .. " – visit a food & drink vendor" .. ns.SupplyTip(miss) }
    end
    if ns.db.remindFlight then
        for _, fp in ipairs(N.UnknownFlightPaths()) do
            tasks[#tasks + 1] = { title = "Flight path", detail = fp.name .. " – not learned yet", trainer = fp }
        end
    end
    if ns.db.remindQuests then
        for _, q in ipairs(ns.Quests.Open()) do
            tasks[#tasks + 1] = {
                title = "Class quest",
                detail = format("%s – rewards %s%s", q.quest, q.reward, q.inLog and " (in quest log)" or ""),
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

local CONT_MAP = { [0] = 1415, [1] = 1414 }   -- Eastern Kingdoms, Kalimdor

local function ResolveMap(t)
    if t.mapID then return true end
    if not (C_Map.GetMapPosFromWorldPos and CreateVector2D and t.wx) then return false end
    local world = CreateVector2D(t.wx, t.wy)
    local contMap = CONT_MAP[t.cont]
    local mapID, pos = C_Map.GetMapPosFromWorldPos(t.cont, world, contMap)
    if not pos then return false end
    -- zoom in: continent -> zone -> city
    for _ = 1, 3 do
        local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, pos:GetXY())
        if not info or info.mapID == mapID then break end
        local m2, p2 = C_Map.GetMapPosFromWorldPos(t.cont, world, info.mapID)
        if not p2 then break end
        mapID, pos = info.mapID, p2
    end
    t.mapID, t.x, t.y = mapID, pos:GetXY()
    return true
end

-- Remove the pin we placed (only if it's still ours)
function N.ClearOurWaypoint()
    if not N.wp or not (C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then N.wp = nil return end
    local p = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if p and p.uiMapID == N.wp.mapID and math.abs(p.position.x - N.wp.x) < 0.001 and math.abs(p.position.y - N.wp.y) < 0.001 then
        C_Map.ClearUserWaypoint()
    end
    N.wp = nil
end

local function SetWaypoint(t)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
    if not ResolveMap(t) then ns.Print("Couldn't place a waypoint for " .. t.name .. ".") return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(t.mapID) then
        ns.Print("Can't place a waypoint on that map.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(t.mapID, t.x, t.y))
    N.wp = t
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    ns.Print(format("Waypoint set: %s (%.1f, %.1f)", t.name, t.x * 100, t.y * 100))
end

local function CreateList()
    local f = ns.MakeWindow("ForgetMeNotListFrame")
    f:SetSize(480, 90)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ForgetMeNotListFrame")  -- Esc closes it
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(450, 40)
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
        r.rbtn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.rbtn:SetSize(150, 22)
        r.rbtn:SetText("Learnable recipes")
        r.rbtn:SetScript("OnClick", function(b) if b.prof then N.ShowRecipes(b.prof) end end)
        r.rbtn:Hide()
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
            r.rbtn.prof = t.recipeProf
            r.rbtn:ClearAllPoints()
            if t.recipeProf then
                if tr then r.rbtn:SetPoint("RIGHT", r.btn, "LEFT", -4, 0) else r.rbtn:SetPoint("RIGHT") end
                r.rbtn:Show()
                r.title:SetPoint("RIGHT", tr and -244 or -156, 0)
                r.detail:SetPoint("RIGHT", tr and -244 or -156, 0)
            else
                r.rbtn:Hide()
                r.title:SetPoint("RIGHT", -90, 0)
                r.detail:SetPoint("RIGHT", -90, 0)
            end
            r:Show()
        else
            r:Hide()
        end
    end
    f:SetHeight(30 + shown * 44 + 40)
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
    -- class spells: try the game's own spell tooltip
    if not shown and d.isSpell and C_Spell and C_Spell.GetSpellInfo and GameTooltip.SetSpellByID then
        local ok, info = pcall(C_Spell.GetSpellInfo, d.name)
        if ok and info and info.spellID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, info.spellID)
            if shown and d.rank and d.rank ~= "" then GameTooltip:AddLine(d.rank .. " (from trainer)", 1, 0.82, 0) end
        end
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

N.EntryTooltip = RowTooltip

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
        f = ns.MakeWindow("ForgetMeNotRecipeFrame")
        f:SetSize(450, 200)
        f:SetClampedToScreen(true)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "ForgetMeNotRecipeFrame")
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
    -- sit next to the Forget-Me-Not(e) Forever panel instead of on top of it
    f:ClearAllPoints()
    local panel = ns.UI and ns.UI.panel
    if panel and panel:IsShown() then
        if (panel:GetRight() or 0) + 460 < UIParent:GetRight() then
            f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
        else
            f:SetPoint("TOPRIGHT", panel, "TOPLEFT", -8, 0)
        end
    else
        f:SetPoint("CENTER", 0, 60)
    end
    f:SetHeight(y + f.footer:GetStringHeight() + 60)
    f:Show()
end

function N.OnZone()
    C_Timer.After(1, N.CheckFlightPaths)
    if not ns.db or not ns.db.remindCity then return end
    local zone = GetRealZoneText()
    if zone and (N.CAPITALS[zone] or ns.db.cities[zone]) and not hiddenZone[zone] then
        N.ShowList(false)
    end
end

-- Every 2 seconds: are you close to a trainer you need?
local function Tick()
    local cont, x, y = PlayerWorldPos()
    if not cont then return end
    -- arrived: remove our pin
    if N.wp then
        local d = Distance(N.wp, cont, x, y)
        if d and d < 8 then N.ClearOurWaypoint() end
    end
    if not ns.db.remindNear or InCombatLockdown() then return end
    local tasks = N.BuildTasks()
    local now = GetTime()
    for _, task in ipairs(tasks) do
        local t = task.trainer
        if t then
            local d = Distance(t, cont, x, y)
            local key = t.name
            -- once per trainer every 30 min, and at most one "close by" popup every 5 min
            if d and d <= ns.db.nearYards and (not nearNotified[key] or now - nearNotified[key] > 1800)
                and now - (nearNotified._any or -1e9) > 300 then
                nearNotified[key] = now
                nearNotified._any = now
                ns.Print(format("%s is close by (%d yd): %s", t.name, math.floor(d), task.detail))
                if not hiddenZone[GetRealZoneText()] then N.ShowList(false) end
                return
            end
        end
    end
end

-- "Before you leave" check: flight map opened or Hearthstone cast started --------
local function TrainersHere(match)
    local zone = GetRealZoneText()
    for _, t in pairs(ns.db.trainers) do
        if t.zone == zone and match(t) then return t end
    end
end

local function IsTier(name)
    for _, t in pairs(ns.Prof.TIERS) do
        if (name or ""):find(t.next, 1, true) then return true end
    end
    return false
end

-- Things you can still do in this city/zone, at trainers you've visited here
function N.DepartureItems(forHearth)
    local items = {}
    local _, classFile = UnitClass("player")
    local spells, cost = ns.GetAvailable()
    local ct = #spells > 0 and TrainersHere(function(t) return t.kind == "class" and t.class == classFile end)
    if ct then
        local names = {}
        for i, s in ipairs(spells) do names[i] = ns.SpellLabel(s) end
        items[#items + 1] = { title = format("%d spell(s) at your class trainer", #spells),
            detail = table.concat(names, ", ") .. " · " .. ns.Money(cost) }
    end
    for _, p in ipairs(ns.Prof.RecipeList()) do
        local pt = TrainersHere(function(t) return t.kind == "profession" and t.prof == p.name end)
        if pt then
            local n, c = 0, 0
            for _, r in ipairs(p.list) do
                if not IsTier(r.name) then n = n + 1; c = c + (r.cost or 0) end
            end
            if n > 0 then
                items[#items + 1] = { title = format("%s: %d recipe(s) can be learned", p.name, n),
                    detail = pt.name .. " · " .. ns.Money(c) }
            end
        end
    end
    for _, e in ipairs(ns.Prof.Scan()) do
        if e.state == "train" and TrainersHere(function(t) return t.kind == "profession" and t.prof == e.name end) then
            items[#items + 1] = { title = format("%s %d/%d", e.name, e.rank, e.max),
                detail = format("Learn %s %s before you go", e.rule.next, e.name) }
        end
    end
    local missing, stext = ns.MissingSupplies()
    if #missing > 0 then
        items[#items + 1] = { title = "Supplies", detail = "You have " .. table.concat(stext, " and ") .. " – buy more before you go" .. ns.SupplyTip(missing) }
    end
    if not forHearth and ns.db.remindInn and IsResting() and GetBindLocation then
        local bind = GetBindLocation() or ""
        local zone, sub = GetRealZoneText() or "", GetSubZoneText() or ""
        local spot = ns.char.bindSpot
        local boundHere = bind == zone or bind == sub or (spot and spot.bind == bind and spot.zone == zone)
        if bind ~= "" and not boundHere then
            items[#items + 1] = { title = "Hearthstone", detail = "Still bound to " .. bind .. " – bind here?" }
        end
    end
    return items
end

local function CreateDeparture()
    local f = ns.MakeWindow("ForgetMeNotDepartureFrame")
    f:SetSize(380, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "ForgetMeNotDepartureFrame")
    f.lines = {}
    f.notes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.notes:SetSize(100, 22)
    f.notes:SetText("My notes")
    f.notes:SetScript("OnClick", function() ns.UI.ToggleNotes() end)
    f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.go:SetSize(110, 22)
    f.go:SetPoint("BOTTOMRIGHT", -12, 10)
    f.go:SetScript("OnClick", function() f:Hide() end)
    f.notes:SetPoint("RIGHT", f.go, "LEFT", -6, 0)
    N.departure = f
    return f
end

function N.ShowDeparture(forHearth, always)
    if not ns.db or not ns.db.remindDeparture then return end
    local items = N.DepartureItems(forHearth)
    if #items == 0 and always then
        items[1] = { title = "|cff33ff33All done here|r", detail = "Nothing missed in this area. Check My notes?" }
    end
    if #items == 0 then
        if N.departure then N.departure:Hide() end
        return
    end
    local f = N.departure or CreateDeparture()
    f.TitleText:SetText("Before you leave " .. (GetRealZoneText() or "") .. "…")
    f.go:SetText(forHearth and "Got it" or "Fly anyway")
    local y = 34
    for i, it in ipairs(items) do
        local l = f.lines[i]
        if not l then
            l = {}
            l.t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l.t:SetJustifyH("LEFT")
            l.d = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l.d:SetJustifyH("LEFT")
            f.lines[i] = l
        end
        l.t:ClearAllPoints(); l.t:SetPoint("TOPLEFT", 16, -y); l.t:SetWidth(348)
        l.t:SetText(it.title)
        y = y + l.t:GetStringHeight() + 2
        l.d:ClearAllPoints(); l.d:SetPoint("TOPLEFT", 16, -y); l.d:SetWidth(348)
        l.d:SetText(it.detail)
        y = y + l.d:GetStringHeight() + 10
        l.t:Show(); l.d:Show()
    end
    for i = #items + 1, #f.lines do f.lines[i].t:Hide(); f.lines[i].d:Hide() end
    f:SetHeight(y + 40)
    f:ClearAllPoints()
    local map = (FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame) or (TaxiFrame and TaxiFrame:IsShown() and TaxiFrame)
    if map then
        f:SetPoint("TOPLEFT", map, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER", 0, 80)
    end
    f:Show()
end

do
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "TAXIMAP_OPENED")
    pcall(ev.RegisterEvent, ev, "TAXIMAP_CLOSED")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_START", "player")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Hearthstone, and a mage's own Teleport/Portal spells
    local function IsHearth(spellID)
        if type(spellID) ~= "number" then return false end
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if type(name) ~= "string" then return false end
        return name == "Hearthstone" or name:find("^Teleport:") ~= nil or name:find("^Portal:") ~= nil
    end
    -- Boats, zeppelins and portal rooms: show when you walk onto a dock or into a portal area
    local DOCK_WORDS = { "Dock", "Harbor", "Harbour", "Pier", "Wharf", "Zeppelin", "Portal" }
    local seenSub = {}
    local zev = CreateFrame("Frame")
    zev:RegisterEvent("ZONE_CHANGED")
    zev:RegisterEvent("ZONE_CHANGED_INDOORS")
    zev:SetScript("OnEvent", function()
        if not ns.db then return end
        local sub = GetSubZoneText() or ""
        if sub == "" or seenSub[sub] then return end
        for _, w in ipairs(DOCK_WORDS) do
            if sub:find(w, 1, true) then
                seenSub[sub] = true
                N.ShowDeparture(true)
                return
            end
        end
    end)
    ev:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if not ns.db then return end
        if event == "TAXIMAP_OPENED" then
            C_Timer.After(0.2, function() N.ShowDeparture(false, true) end)
        elseif event == "TAXIMAP_CLOSED" then
            if N.departure then N.departure:Hide() end
        elseif event == "UNIT_SPELLCAST_START" and unit == "player" then
            local ok, hs = pcall(IsHearth, spellID)
            if ok and hs then N.ShowDeparture(true) end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            local ok, hs = pcall(IsHearth, spellID)
            if ok and hs and N.departure then N.departure:Hide() end
        end
    end)
end

function N.Init()
    C_Timer.NewTicker(2, Tick)
end
