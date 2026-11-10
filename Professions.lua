-- Forget-Me-Not(e) Forever: profession milestones (Vanilla rules)
local ADDON, ns = ...
local P = {}
ns.Prof = P

-- Keyed by your current cap. Edit here if Forever's rules differ.
P.TIERS = {
    [75]  = { next = "Journeyman", cap = 150, skill = 50 },
    [150] = { next = "Expert",     cap = 225, skill = 125 },
    [225] = { next = "Artisan",    cap = 300, skill = 200 },
}

-- Secondary professions don't always train at a trainer in Vanilla
P.SECONDARY = {
    ["Cooking"]   = { [150] = "a book from a vendor", [225] = "a quest" },
    ["First Aid"] = { [150] = "a book from a vendor", [225] = "a quest" },
    ["Fishing"]   = { [150] = "a book from a vendor", [225] = "a quest" },
}

-- Level and skill needed for the next tier. Read from that profession's trainer
-- (talk to it once); until then: no level requirement, Vanilla skill requirement.
function P.Req(name, rule)
    local store = ns.char.recipes and ns.char.recipes[name]
    if store then
        for _, r in pairs(store) do
            local label = (r.name or "") .. " " .. (r.rank or "")
            if label:find(rule.next, 1, true) then
                return r.level or 0, (r.skill and r.skill > 0) and r.skill or rule.skill
            end
        end
    end
    return 0, rule.skill
end

-- Returns one entry per profession that needs attention
function P.Scan(level)
    level = level or UnitLevel("player")
    local out = {}
    if not GetProfessions or not GetProfessionInfo then return out end
    local idx = { GetProfessions() }
    for i = 1, 6 do
        if idx[i] then
            local name, _, rank, maxRank = GetProfessionInfo(idx[i])
            local rule = name and P.TIERS[maxRank]
            if rule then
                local where = (P.SECONDARY[name] and P.SECONDARY[name][maxRank]) or ("a " .. name .. " trainer")
                local e = { name = name, rank = rank, max = maxRank, rule = rule, where = where }
                local reqLevel, reqSkill = P.Req(name, rule)
                e.reqLevel = reqLevel
                if rank >= reqSkill and level >= reqLevel then
                    e.state = "train"
                    e.text = format("%s %d/%d: you can learn %s %s now, from %s.", name, rank, maxRank, rule.next, name, where)
                elseif rank >= maxRank then
                    e.state = "capped"
                    e.text = format("%s is capped at %d. %s needs level %d.", name, maxRank, rule.next, reqLevel)
                elseif maxRank - rank <= ns.db.profWarn then
                    e.state = "near"
                    e.text = format("%s %d/%d: %d point(s) to the cap.", name, rank, maxRank, maxRank - rank)
                end
                if e.state then out[#out + 1] = e end
            end
        end
    end
    return out
end

-- Gathering spells -> profession name
local GATHER = { ["Mining"] = "Mining", ["Skinning"] = "Skinning", ["Herb Gathering"] = "Herbalism",
    ["Fishing"] = "Fishing" }

-- Which profession a spell belongs to (crafting recipe or gathering), or nil
local function ProfessionForSpell(spellID)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe then
        local ok, _, lineName, parentID = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, spellID)
        if ok and type(lineName) == "string" and lineName ~= "" then
            if parentID and C_TradeSkillUI.GetTradeSkillDisplayName then
                local ok2, parentName = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, parentID)
                if ok2 and type(parentName) == "string" and parentName ~= "" then return parentName end
            end
            return lineName
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and type(info.name) == "string" then return GATHER[info.name] end
    end
end

-- After each craft or gather: warn if that profession is capped (can't skill up)
local lastWarn = 0
local function OnCast(spellID)
    if not ns.db.remindCapCraft then return end
    local prof = ProfessionForSpell(spellID)
    if not prof or not (GetProfessions and GetProfessionInfo) then return end
    local idx = { GetProfessions() }
    for i = 1, 6 do
        if idx[i] then
            local name, _, rank, maxRank = GetProfessionInfo(idx[i])
            if name and (name == prof or prof:find(name, 1, true)) then
                local rule = P.TIERS[maxRank]
                if rule and rank >= maxRank and GetTime() - lastWarn > 3 then
                    lastWarn = GetTime()
                    local where = (P.SECONDARY[name] and P.SECONDARY[name][maxRank]) or ("a " .. name .. " trainer")
                    local msg
                    local reqLevel = P.Req(name, rule)
                    if UnitLevel("player") >= reqLevel then
                        msg = format("%s is capped at %d/%d – no skill-ups! Learn %s from %s.", name, rank, maxRank, rule.next, where)
                    else
                        msg = format("%s is capped at %d/%d – no skill-ups! %s needs level %d.", name, rank, maxRank, rule.next, reqLevel)
                    end
                    ns.Print(msg)
                    if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.5, 0.2) end
                end
                return
            end
        end
    end
end


-- Every recipe you have the skill for but haven't learned, per profession,
-- cheapest first: { name = prof, list = { {name, rank, cost}... }, cost = total }
function P.RecipeList(level)
    level = level or UnitLevel("player")
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local idx = { GetProfessions() }
    for i = 1, 6 do
        if idx[i] then
            local name, _, rank = GetProfessionInfo(idx[i])
            local store = name and ns.char.recipes[name]
            if store then
                local list, total = {}, 0
                for _, r in pairs(store) do
                    if not r.known and r.skill <= rank and r.level <= level then
                        list[#list + 1] = r
                        total = total + (r.cost or 0)
                    end
                end
                table.sort(list, function(a, b)
                    if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
                    return a.name < b.name
                end)
                if #list > 0 then out[#out + 1] = { name = name, list = list, cost = total } end
            end
        end
    end
    return out
end

-- Recipes you can learn now, per profession: { name, count, cost }
function P.NewRecipes(level)
    level = level or UnitLevel("player")
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local idx = { GetProfessions() }
    for i = 1, 6 do
        if idx[i] then
            local name, _, rank = GetProfessionInfo(idx[i])
            local store = name and ns.char.recipes[name]
            if store then
                local count, cost = 0, 0
                for _, r in pairs(store) do
                    if not r.known and r.skill <= rank and r.level <= level then
                        count = count + 1
                        cost = cost + (r.cost or 0)
                    end
                end
                if count > 0 then out[#out + 1] = { name = name, count = count, cost = cost } end
            end
        end
    end
    return out
end

-- Prints each message once per session (per profession, cap and state)
function P.Check(level)
    if not ns.db.remindProf then return end
    for _, e in ipairs(P.Scan(level)) do
        local key = e.name .. e.max .. e.state
        if not ns.seenProf[key] then
            ns.seenProf[key] = true
            ns.Print(e.text)
            if e.state == "train" or e.state == "capped" then
                ns.Alert(e.text)
            end
        end
    end
    if ns.db.remindRecipes then
        for _, r in ipairs(P.NewRecipes(level)) do
            local key = r.name .. "recipes" .. r.count
            if not ns.seenProf[key] then
                ns.seenProf[key] = true
                ns.Print(format("%d new %s recipe(s) at your trainer (%s).", r.count, r.name, ns.Money(r.cost)))
            end
        end
    end
    P.CheckBagRecipes()
    if ns.UI then ns.UI.Refresh() end
end

-- Recipes in your bags and bank ------------------------------------------------------
-- Bank contents are remembered (per character) from the last time the bank was open.
local function RecipeInfo(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return end
    local ok, info = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or not info or not info.lines then return end
    local prof, skill, known
    for _, line in ipairs(info.lines) do
        local text = line.leftText or ""
        if text == (ITEM_SPELL_KNOWN or "Already known") then known = true end
        if not prof then
            local p, n = text:match("^Requires ([%a ]+) %((%d+)%)$")
            if p and n then prof, skill = p, tonumber(n) end
        end
    end
    return prof, skill, known
end

local function IsRecipe(itemID)
    local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
    return ok and classID == 9      -- Recipe
end

local function BankBags()
    local out = {}
    if Enum and Enum.BagIndex then
        if Enum.BagIndex.Bank then out[#out + 1] = Enum.BagIndex.Bank end
        for i = 1, 7 do
            local b = Enum.BagIndex["BankBag_" .. i] or Enum.BagIndex["CharacterBankTab_" .. i]
            if b then out[#out + 1] = b end
        end
    end
    if #out == 0 then
        out[1] = -1
        for b = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 6) do out[#out + 1] = b end
    end
    return out
end

local function ScanBags(bags, into)
    for _, bag in ipairs(bags) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and n) or 0 do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID and item.hyperlink and IsRecipe(item.itemID) then
                into[item.itemID] = item.hyperlink
            end
        end
    end
end

function P.SaveBank()
    if not (ns.char and C_Container) then return end
    local found = {}
    ScanBags(BankBags(), found)
    ns.char.bankRecipes = found
end

-- Syndicator (Baganator's data addon) keeps a saved copy of your bank: use it if installed
local function SyndicatorBank()
    local out = {}
    if not (Syndicator and Syndicator.API and Syndicator.API.GetCurrentCharacter
        and Syndicator.API.GetByCharacterFullName) then return out end
    local ok, data = pcall(function()
        return Syndicator.API.GetByCharacterFullName(Syndicator.API.GetCurrentCharacter())
    end)
    if not ok or type(data) ~= "table" then return out end
    local function scan(containers)
        if type(containers) ~= "table" then return end
        for _, c in pairs(containers) do
            local slots = type(c) == "table" and (c.slots or c) or nil
            if type(slots) == "table" then
                for _, item in pairs(slots) do
                    if type(item) == "table" and item.itemID and item.itemLink and IsRecipe(item.itemID) then
                        out[item.itemID] = item.itemLink
                    end
                end
            end
        end
    end
    scan(data.bank)
    scan(data.bankTabs)
    return out
end

-- Every recipe you carry or bank that you don't know yet:
-- { link, prof, skill, where = "bags"/"bank", ready = true if your skill is high enough }
function P.BagRecipes()
    local out = {}
    if not (C_Container and GetProfessions and GetProfessionInfo) then return out end
    local rank = {}
    for _, i in pairs({ GetProfessions() }) do
        local name, _, r = GetProfessionInfo(i)
        if name then rank[name] = r end
    end
    local bags = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = b end
    local inBags = {}
    ScanBags(bags, inBags)
    local function add(list, where)
        for id, link in pairs(list or {}) do
            local prof, skill, known = RecipeInfo(link)
            if prof and not known and rank[prof] then
                out[#out + 1] = { id = id, link = link, prof = prof, skill = skill, where = where,
                    ready = rank[prof] >= skill }
            end
        end
    end
    add(inBags, "bags")
    local bank = {}
    for id, link in pairs(ns.char.bankRecipes or {}) do if not inBags[id] then bank[id] = link end end
    for id, link in pairs(SyndicatorBank()) do if not inBags[id] then bank[id] = link end end
    add(bank, "bank")
    table.sort(out, function(a, b) return a.skill < b.skill end)
    return out
end

-- Tell once (per session) when a carried/banked recipe becomes learnable
local toldRecipe = {}
function P.CheckBagRecipes()
    if not ns.db.remindBagRecipes then return end
    for _, r in ipairs(P.BagRecipes()) do
        if r.ready and not toldRecipe[r.id] then
            toldRecipe[r.id] = true
            ns.Print(format("You can learn %s now (in your %s).", r.link, r.where))
        end
    end
end

do
    local bev = CreateFrame("Frame")
    pcall(bev.RegisterEvent, bev, "BANKFRAME_OPENED")
    pcall(bev.RegisterEvent, bev, "PLAYERBANKSLOTS_CHANGED")
    pcall(bev.RegisterEvent, bev, "BANKFRAME_CLOSED")
    bev:RegisterEvent("BAG_UPDATE_DELAYED")
    local bankOpen, pending = false, false
    bev:SetScript("OnEvent", function(_, event)
        if not ns.db then return end
        if event == "BANKFRAME_OPENED" then bankOpen = true
        elseif event == "BANKFRAME_CLOSED" then bankOpen = false; return end
        if pending then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            if bankOpen then pcall(P.SaveBank) end
            pcall(P.CheckBagRecipes)
        end)
    end)
end

-- Listen for crafts/gathers last, and safely: if the client refuses this event,
-- everything above still works.
local ev = CreateFrame("Frame")
local ok = pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
if not ok then pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED") end
ev:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or not ns.db or type(spellID) ~= "number" then return end
    C_Timer.After(0.3, function() pcall(OnCast, spellID) end)
end)
