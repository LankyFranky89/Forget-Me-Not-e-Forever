-- Forget-Me-Not: reads the trainer window, records trainer locations, "Learn all" helper
local ADDON, ns = ...
local T = {}
ns.Trainer = T

local scanning = false
local FILTERS = { "available", "unavailable", "used" }

local TYPES = { available = true, unavailable = true, used = true, header = true }

-- Reads one trainer entry. Forever returns the type ("used", "available"...) in a
-- different position than older clients, so find it by value instead of position.
local function ServiceInfo(i)
    local r = { GetTrainerServiceInfo(i) }
    local name = r[1]
    local stype, rank, icon
    for k = 2, 6 do
        local v = r[k]
        if type(v) == "number" and v > 100000 and not icon then
            icon = v  -- texture file ID (small numbers are levels or costs)
        elseif type(v) == "string" then
            if v:find("[\\/]") then
                icon = icon or v  -- texture path
            elseif TYPES[v] and not stype then
                stype = v
            elseif not rank and v ~= "" and not TYPES[v] then
                rank = v
            end
        end
    end
    return name, rank or "", stype, icon
end

-- Extra details kept for tooltips: icon, item link (what a recipe makes), description
local function Details(i, icon)
    local link, desc
    if GetTrainerServiceItemLink then
        local ok, l = pcall(GetTrainerServiceItemLink, i)
        if ok and type(l) == "string" then link = l end
    end
    if GetTrainerServiceDescription then
        local ok, d = pcall(GetTrainerServiceDescription, i)
        if ok and type(d) == "string" and d ~= "" then desc = d end
    end
    if not icon and GetTrainerServiceIcon then
        local ok, ic = pcall(GetTrainerServiceIcon, i)
        if ok and ic then icon = ic end
    end
    return icon, link, desc
end
T.ServiceInfo = ServiceInfo

-- Unique key per entry. Without a rank text, the level keeps ranks apart.
local function ServiceKey(i, name, rank)
    if rank ~= "" then return name .. "|" .. rank end
    return name .. "|L" .. (GetTrainerServiceLevelReq(i) or 0)
end

-- /tn dump: prints exactly what the open trainer window gives addons
function T.Dump()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then
        ns.Print("Trainer functions are missing on this client.")
        return
    end
    local n = GetNumTrainerServices() or 0
    if n == 0 then
        ns.Print("Open a trainer window first, then type /tn dump.")
        return
    end
    ns.Print("IsTradeskillTrainer: " .. tostring(IsTradeskillTrainer and IsTradeskillTrainer()))
    local recipeCount = 0
    for _, store in pairs(ns.char.recipes or {}) do for _ in pairs(store) do recipeCount = recipeCount + 1 end end
    ns.Print("Saved recipes for this character: " .. recipeCount)
    for i = 1, n do
        local r = { GetTrainerServiceInfo(i) }
        local parts = {}
        for k = 1, 8 do parts[k] = tostring(r[k]) end
        local lvl = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
        local sk = { GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i) }
        ns.Print(format("%d: %s | lvl %s | skill %s, %s, %s", i, table.concat(parts, ", "), tostring(lvl),
            tostring(sk[1]), tostring(sk[2]), tostring(sk[3])))
    end
end

local function ApiOK()
    return GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceLevelReq
end

local function FilterOn(f)
    return GetTrainerServiceTypeFilter(f) and true or false
end

-- Works whether the client expects a boolean or 1/0
local function SetFilter(f, on)
    SetTrainerServiceTypeFilter(f, on)
    if FilterOn(f) ~= on then
        SetTrainerServiceTypeFilter(f, on and 1 or 0)
    end
end

local function TrainerKind()
    if IsTradeskillTrainer and IsTradeskillTrainer() then
        if GetTrainerServiceSkillReq then
            for i = 1, GetNumTrainerServices() do
                local skill = GetTrainerServiceSkillReq(i)
                if skill and skill ~= "" then return "profession", skill end
            end
        end
        return "profession", nil
    end
    return "class", nil
end

local function RecordTrainer(kind, prof)
    local npc = UnitName("npc")
    if not npc or not C_Map then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local cont, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
    local _, classFile = UnitClass("player")
    ns.db.trainers[npc .. "@" .. mapID] = {
        name = npc, kind = kind, prof = prof,
        class = (kind == "class") and classFile or nil,
        mapID = mapID, x = x, y = y,
        cont = cont, wx = world and world.x, wy = world and world.y,
        zone = GetRealZoneText(),
    }
end

-- Is this trainer for MY class? Checks the NPC's title line (e.g. "Paladin Trainer").
-- If the title can't be read, it only trusts trainers that list a spell you already know.
local function IsMyClassTrainer()
    local myClass = UnitClass("player")  -- localized, e.g. "Paladin"
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local info = C_TooltipInfo.GetUnit("npc")
        if info and info.lines then
            for i = 2, #info.lines do
                local text = info.lines[i].leftText
                if text and text:find(TRAINER or "Trainer", 1, true) then
                    return text:find(myClass, 1, true) ~= nil
                end
            end
        end
    end
    for i = 1, GetNumTrainerServices() do
        local _, _, stype = ServiceInfo(i)
        if stype == "used" then return true end
    end
    return false
end

local function Scan()
    local kind, prof = TrainerKind()
    if kind == "class" and not IsMyClassTrainer() then
        T.notMine = true
        return
    end
    T.notMine = false
    RecordTrainer(kind, prof)
    if kind ~= "class" then
        -- profession trainer: remember its recipes and their skill requirements
        if prof then
            ns.char.recipes[prof] = ns.char.recipes[prof] or {}
            local store = ns.char.recipes[prof]
            for i = 1, GetNumTrainerServices() do
                local name, sub, stype, icon = ServiceInfo(i)
                if name and stype and stype ~= "header" then
                    local _, skill = GetTrainerServiceSkillReq(i)
                    local ic, link, desc = Details(i, icon)
                    store[ServiceKey(i, name, sub or "")] = {
                        name = name, rank = sub or "",
                        skill = tonumber(skill) or 0,
                        level = GetTrainerServiceLevelReq(i) or 0,
                        cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
                        known = (stype == "used"),
                        icon = ic, link = link, desc = desc,
                    }
                end
            end
        end
        return
    end
    for i = 1, GetNumTrainerServices() do
        local name, sub, stype, icon = ServiceInfo(i)
        if name and stype and stype ~= "header" then
            local ic, link, desc = Details(i, icon)
            local rank = sub or ""
            local key = ServiceKey(i, name, rank)
            ns.char.services[key] = {
                name = name, rank = rank,
                level = GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
                known = (stype == "used"),
                icon = ic, link = link, desc = desc,
            }
        end
    end
end

function T.OnShow()
    if not ApiOK() then
        ns.Print("This client's trainer window can't be read by addons, so spell reminders are off.")
        return
    end
    -- Show every kind of entry for the scan, then put the user's filters back
    local saved
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        scanning = true
        saved = {}
        for _, flt in ipairs(FILTERS) do
            saved[flt] = FilterOn(flt)
            if not saved[flt] then SetFilter(flt, true) end
        end
    end
    if ExpandTrainerSkillLine then ExpandTrainerSkillLine(0) end
    C_Timer.After(0.3, function()
        Scan()
        if saved then
            for flt, was in pairs(saved) do
                if not was then SetFilter(flt, false) end
            end
        end
        C_Timer.After(0.3, function()
            scanning = false
            T.ShowHelper()
            ns.UI.Refresh()
        end)
    end)
end

function T.OnUpdate()
    if scanning then return end
    if T.buying then
        C_Timer.After(0.3, T.BuyNext)
    end
    if T.helper and T.helper:IsShown() then T.Refresh() end
end

function T.OnClosed()
    T.buying = false
    if T.helper then T.helper:Hide() end
    ns.UI.Refresh()
end

-- Mark a spell known as soon as it's bought (from our button or Blizzard's)
if BuyTrainerService then
    hooksecurefunc("BuyTrainerService", function(i)
        local name, sub = ServiceInfo(i)
        if name then
            if not ns.char then return end
            local key = ServiceKey(i, name, sub or "")
            local s = ns.char.services[key]
            if s then s.known = true end
            for _, store in pairs(ns.char.recipes) do
                if store[key] then store[key].known = true end
            end
        end
    end)
end

-- "Learn all" helper next to the trainer window
local function CreateHelper()
    local f = ns.MakeWindow("ForgetMeNotTrainerHelper")
    f:SetSize(260, 130)
    f:SetFrameStrata("HIGH")
    f.TitleText:SetText("Forget-Me-Not")
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.info:SetPoint("TOPLEFT", 14, -34)
    f.info:SetPoint("RIGHT", -14, 0)
    f.info:SetJustifyH("LEFT")
    f.btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btn:SetSize(220, 26)
    f.btn:SetPoint("BOTTOM", 0, 14)
    f.btn:SetScript("OnClick", function()
        local list, cost = T.CurrentAvailable()
        if #list == 0 then return end
        StaticPopup_Show("FORGETMENOT_LEARNALL", #list, ns.Money(cost))
    end)
    T.helper = f
    return f
end

-- What the open trainer offers right now (not skipped)
function T.CurrentAvailable()
    local list, cost = {}, 0
    for i = 1, GetNumTrainerServices() do
        local name, sub, stype = ServiceInfo(i)
        if stype == "available" then
            local s = { name = name, rank = sub or "" }
            if not ns.IsSkipped(s) then
                list[#list + 1] = s
                cost = cost + (GetTrainerServiceCost(i) or 0)
            end
        end
    end
    return list, cost
end

function T.Refresh()
    local f = T.helper
    if not f then return end
    local list, cost = T.CurrentAvailable()
    if #list == 0 then
        f.info:SetText("Nothing new to learn here.")
        f.btn:Disable()
        f.btn:SetText("Learn all")
    else
        f.info:SetText(format("%d spell(s) available\nTotal: %s\nYour gold: %s", #list, ns.Money(cost), ns.Money(GetMoney())))
        f.btn:SetText("Learn all (" .. #list .. ")")
        if cost <= GetMoney() then f.btn:Enable() else f.btn:Disable() end
    end
end

function T.ShowHelper()
    local kind = TrainerKind()
    if kind ~= "class" or T.notMine then return end
    local f = T.helper or CreateHelper()
    f:ClearAllPoints()
    if ClassTrainerFrame and ClassTrainerFrame:IsShown() then
        f:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
    end
    T.Refresh()
    f:Show()
end

-- Buys one spell at a time, the next after the trainer list updates
function T.StartBuying()
    T.buying = true
    T.tried = {}
    T.bought = 0
    T.BuyNext()
end

function T.BuyNext()
    if not T.buying then return end
    for i = 1, GetNumTrainerServices() do
        local name, sub, stype = ServiceInfo(i)
        if stype == "available" then
            local key = ServiceKey(i, name, sub or "")
            if not ns.IsSkipped({ name = name, rank = sub or "" }) and not T.tried[key] then
                if (GetTrainerServiceCost(i) or 0) > GetMoney() then
                    ns.Print("Not enough gold for " .. name .. ". Stopped.")
                    T.buying = false
                    return
                end
                T.tried[key] = true
                T.bought = T.bought + 1
                BuyTrainerService(i)
                -- if the list doesn't update, carry on anyway
                C_Timer.After(1.5, function() if T.buying then T.BuyNext() end end)
                return
            end
        end
    end
    T.buying = false
    ns.Print(format("Done: tried to learn %d spell(s).", T.bought))
    ns.UI.Refresh()
end

StaticPopupDialogs["FORGETMENOT_LEARNALL"] = {
    text = "Learn %d spell(s) for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() T.StartBuying() end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
}
