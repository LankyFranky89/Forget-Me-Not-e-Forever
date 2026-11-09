-- Forget-Me-Not(e) Forever: core, saved settings, messages, events, slash commands
local ADDON, ns = ...

local PREFIX = "|cffffd100[FMN]|r "

local DEFAULTS = {
    remindLevelUp = true,   -- check spells when you level up
    remindLogin   = true,   -- check spells and professions at login
    remindCity    = true,   -- show the to-do list when entering a city below
    remindNear    = true,   -- show the to-do list when close to a trainer you need
    remindProf    = true,   -- profession reminders
    remindCapCraft = false, -- warn on every craft/gather while a profession is capped (off: to-do list only)
    remindInn     = true,
    remindSupplies = true,  -- food and drink
    supplyLow     = 0,      -- warn when you have this many or fewer
    remindDeparture = true, -- "Before you leave" window at flight masters and on Hearthstone
    remindFlight  = true,   -- undiscovered flight paths in your zone   -- remind to bind your hearthstone at a new inn
    remindQuests  = true,   -- class quests
    remindTalents = true,   -- unspent talent points
    remindRecipes = true,   -- new profession recipes at the trainer
    showAlts      = true,   -- show other characters' to-do lists in the panel
    chat          = true,   -- chat messages
    alert         = true,   -- big on-screen text (raid-warning style)
    sound         = true,
    nearYards     = 40,
    profWarn      = 5,      -- warn when this many points (or fewer) below the cap
    cities        = { ["Stormwind City"] = true, ["Ironforge"] = true },
    minimap       = { angle = 210, hide = false },
    trainers      = {},     -- trainer locations, recorded when you talk to them
    chars         = {},     -- "Name-Realm" -> summary of that character's to-do list
}

local CHAR_DEFAULTS = {
    services = {},          -- class trainer spells, read from the trainer window
    skipped  = {},          -- "Name" or "Name|Rank" the user chose to skip
    recipes  = {},          -- profession -> recipes read from that trainer
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                ApplyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
end

ns.seenProf = {}  -- profession messages already shown this session

function ns.Print(msg)
    if ns.db and ns.db.chat then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    end
end

function ns.Alert(msg)
    if not ns.db then return end
    if ns.db.alert and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    if ns.db.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

function ns.Money(copper)
    copper = copper or 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    elseif GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

-- Weapon skills taught by trainers/weapon masters are ignored everywhere
ns.WEAPON_SKILLS = {
    ["Axes"] = true, ["Two-Handed Axes"] = true, ["One-Handed Axes"] = true,
    ["Maces"] = true, ["Two-Handed Maces"] = true, ["One-Handed Maces"] = true,
    ["Swords"] = true, ["Two-Handed Swords"] = true, ["One-Handed Swords"] = true,
    ["Daggers"] = true, ["Staves"] = true, ["Polearms"] = true, ["Fist Weapons"] = true,
    ["Bows"] = true, ["Guns"] = true, ["Crossbows"] = true, ["Thrown"] = true, ["Wands"] = true,
}
function ns.IsWeaponSkill(name)
    return name and ns.WEAPON_SKILLS[name] or false
end

function ns.IsSkipped(s)
    local sk = ns.char.skipped
    return sk[s.name] or sk[s.name .. "|" .. (s.rank or "")]
end

function ns.SpellLabel(s)
    if s.rank and s.rank ~= "" then
        return s.name .. " (" .. s.rank .. ")"
    end
    return s.name
end

local function SortSpells(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.name ~= b.name then return a.name < b.name end
    return (a.rank or "") < (b.rank or "")
end

-- Spells you can learn now (level met, not known, not skipped)
function ns.GetAvailable(level)
    level = level or UnitLevel("player")
    local list, cost = {}, 0
    for _, s in pairs(ns.char.services) do
        if not s.known and s.level <= level and not ns.IsSkipped(s) and not ns.IsWeaponSkill(s.name) then
            list[#list + 1] = s
            cost = cost + (s.cost or 0)
        end
    end
    table.sort(list, SortSpells)
    return list, cost
end

-- Spells unlocking within the next `range` levels
function ns.GetUpcoming(level, range)
    level = level or UnitLevel("player")
    range = range or 10
    local list = {}
    for _, s in pairs(ns.char.services) do
        if not s.known and s.level > level and s.level <= level + range and not ns.IsSkipped(s) and not ns.IsWeaponSkill(s.name) then
            list[#list + 1] = s
        end
    end
    table.sort(list, SortSpells)
    return list
end

function ns.HasServiceData()
    return next(ns.char.services) ~= nil
end

function ns.CheckSpells(level, quiet)
    level = level or UnitLevel("player")
    if not ns.HasServiceData() then
        ns.Print("Talk to your class trainer once so I can read which spells exist and at which level.")
        return
    end
    local list, cost = ns.GetAvailable(level)
    if #list > 0 then
        local names = {}
        for i, s in ipairs(list) do names[i] = ns.SpellLabel(s) end
        ns.Print(format("%d spell(s) to learn at your trainer: %s. Cost: %s",
            #list, table.concat(names, ", "), ns.Money(cost)))
        if not quiet then
            ns.Alert(format("Level %d: %d new spell(s) to learn", level, #list))
        end
    end
    if ns.UI then ns.UI.Refresh() end
end

-- A window using the game's own frame (ButtonFrameTemplate), so it looks exactly
-- like Forever's windows. Falls back to a gold-bordered frame if the template is missing.
function ns.MakeWindow(name)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate")
    if ok and f then
        if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
        if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
        if f.Inset then f.Inset:Hide() end
        -- callers use f.TitleText:SetText(...)
        if f.SetTitle then
            f.TitleText = { SetText = function(_, text) f:SetTitle(text) end }
        elseif f.TitleContainer and f.TitleContainer.TitleText then
            f.TitleText = f.TitleContainer.TitleText
        end
        if f.TitleText then return f end
        f:Hide()
    end
    return ns.MakePlainWindow(name and (name .. "Plain"))
end

function ns.MakePlainWindow(name)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    f:SetBackdropBorderColor(1, 0.82, 0)  -- WoW gold
    f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.TitleText:SetPoint("TOP", 0, -9)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    f.CloseButton = close
    return f
end

-- "Name-Realm" for the character you're on
function ns.CharKey()
    local name, realm = UnitFullName("player")
    realm = (realm and realm ~= "") and realm or GetNormalizedRealmName() or GetRealmName()
    return (name or "?") .. "-" .. (realm or "?")
end

-- Saves this character's to-do summary so alts can see it (named, never mixed)
function ns.SaveSummary()
    if not ns.db or not UnitName("player") then return end
    local className, classFile = UnitClass("player")
    local spells, cost = {}, 0
    if ns.HasServiceData() then
        local list
        list, cost = ns.GetAvailable()
        for i, s in ipairs(list) do spells[i] = ns.SpellLabel(s) end
    end
    local profs = {}
    for _, e in ipairs(ns.Prof.Scan()) do profs[#profs + 1] = e.text end
    ns.db.chars[ns.CharKey()] = {
        name = UnitName("player"), class = className, classFile = classFile,
        level = UnitLevel("player"), spells = spells, cost = cost,
        hasData = ns.HasServiceData(), profs = profs, updated = time(),
    }
end

-- Unspent talent points, or nil if this client can't tell
-- Each way of reading unspent talent points; the first that works is used.
local TALENT_METHODS = {
    { name = "UnitCharacterPoints", fn = function()
        if UnitCharacterPoints then return UnitCharacterPoints("player") end
    end },
    { name = "GetUnspentTalentPoints", fn = function()
        if GetUnspentTalentPoints then return GetUnspentTalentPoints() end
    end },
    { name = "C_Traits (modern talents)", fn = function()
        if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return end
        local configID = C_ClassTalents.GetActiveConfigID()
        if not configID then return end
        local info = C_Traits.GetConfigInfo(configID)
        local treeID = info and info.treeIDs and info.treeIDs[1]
        if not treeID then return end
        local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
        if type(currencies) ~= "table" then return end
        local total = 0
        for _, c in ipairs(currencies) do
            if type(c.quantity) == "number" then total = total + c.quantity end
        end
        return total
    end },
    { name = "Talent tabs (level - 9 - spent)", fn = function()
        if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
        local level = UnitLevel("player")
        if level < 10 then return 0 end
        local spent = 0
        for tab = 1, GetNumTalentTabs() do
            for i = 1, GetNumTalents(tab) do
                local r = { GetTalentInfo(tab, i) }
                -- current rank is the 5th value in the classic API
                if type(r[5]) == "number" then spent = spent + r[5] end
            end
        end
        return math.max(0, level - 9 - spent)
    end },
}

function ns.UnspentTalents()
    for _, m in ipairs(TALENT_METHODS) do
        local ok, n = pcall(m.fn)
        if ok and type(n) == "number" then return n, m.name end
    end
    return nil
end

-- /fmn talents: shows what each method returns
function ns.DebugTalents()
    for _, m in ipairs(TALENT_METHODS) do
        local ok, n = pcall(m.fn)
        ns.Print(format("%s: %s", m.name, ok and tostring(n) or ("error: " .. tostring(n))))
    end
    local b = ns.UI and ns.UI.TalentButton and ns.UI.TalentButton()
    ns.Print("Talent button found: " .. (b and (b:GetName() or "yes") or "no"))
end

local lastTalentMsg
function ns.CheckTalents()
    local n = (ns.db.remindTalents and ns.UnspentTalents()) or 0
    lastTalentMsg = n
    if ns.UI then
        ns.UI.TalentBubble(n)
        ns.UI.Refresh()
    end
end
-- Inn reminder: when you start resting somewhere that isn't your hearthstone spot
local innSeen = {}   -- places already reminded about this session
function ns.CheckInn()
    if not ns.db.remindInn or not IsResting() then return end
    local bind = GetBindLocation and GetBindLocation() or ""
    local sub, zone = GetSubZoneText() or "", GetRealZoneText() or ""
    if bind == "" or bind == sub or bind == zone then return end
    -- the place where you last bound (saved when you bind), in case its name differs from the bind name
    local spot = ns.char.bindSpot
    if spot and spot.bind == bind and spot.zone == zone and (spot.sub == sub or spot.sub == "" or sub == "") then return end
    local key = zone .. "/" .. sub
    if innSeen[key] then return end
    innSeen[key] = true
    local here = (sub ~= "" and sub) or zone
    local msg = format("You're at an inn in %s. Your hearthstone is set to %s – talk to the innkeeper to bind it here.", here, bind)
    ns.Print(msg)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("Bind your hearthstone here? (now: " .. bind .. ")", 1, 0.82, 0) end
end

-- Events
local f = CreateFrame("Frame")
local lastSkill = 0

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SKILL_LINES_CHANGED")
pcall(f.RegisterEvent, f, "CHAT_MSG_SKILL")          -- "Your skill in X has increased to N."
pcall(f.RegisterEvent, f, "TRADE_SKILL_LIST_UPDATE")
pcall(f.RegisterEvent, f, "CHARACTER_POINTS_CHANGED")
pcall(f.RegisterEvent, f, "PLAYER_TALENT_UPDATE")
pcall(f.RegisterEvent, f, "TRAIT_CONFIG_UPDATED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
pcall(f.RegisterEvent, f, "HEARTHSTONE_BOUND")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:RegisterEvent("TRAINER_CLOSED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForgetMeNotDB = ForgetMeNotDB or {}
        ForgetMeNotCharDB = ForgetMeNotCharDB or {}
        ApplyDefaults(ForgetMeNotDB, DEFAULTS)
        ApplyDefaults(ForgetMeNotCharDB, CHAR_DEFAULTS)
        ns.db, ns.char = ForgetMeNotDB, ForgetMeNotCharDB
        -- 0.8.4: per-craft cap warning is now off by default
        if not ns.db.capCraftDefaultOff then
            ns.db.remindCapCraft = false
            ns.db.capCraftDefaultOff = true
        end
        -- 0.1.0 could store other classes' spells: clear them once
        if (ns.char.dataVersion or 1) < 3 then
            wipe(ns.char.services)
            for k, t in pairs(ns.db.trainers) do
                if t.kind == "class" then ns.db.trainers[k] = nil end
            end
            if ns.char.recipes then wipe(ns.char.recipes) end
            ns.char.dataVersion = 3
        end
        f:UnregisterEvent("ADDON_LOADED")

    elseif not ns.db then
        return

    elseif event == "PLAYER_LOGIN" then
        -- one-time move of settings and data from the old Squire name
        if not ns.db.migratedFromSquire and type(SquireDB) == "table" then
            for k, v in pairs(SquireDB) do ns.db[k] = v end
            ns.db.migratedFromSquire = true
            ns.Print("Moved your Squire settings over to Forget-Me-Not(e) Forever.")
        end
        if not ns.char.migratedFromSquire and type(SquireCharDB) == "table" then
            for k, v in pairs(SquireCharDB) do ns.char[k] = v end
            ns.char.migratedFromSquire = true
        end
        -- one-time move of settings and data from the old TrainerNudge name
        if not ns.db.migratedFromTN and type(TrainerNudgeDB) == "table" then
            for k, v in pairs(TrainerNudgeDB) do ns.db[k] = v end
            ns.db.migratedFromTN = true
            ns.Print("Moved your TrainerNudge settings over to Forget-Me-Not(e) Forever.")
        end
        if not ns.char.migratedFromTN and type(TrainerNudgeCharDB) == "table" then
            for k, v in pairs(TrainerNudgeCharDB) do ns.char[k] = v end
            ns.char.migratedFromTN = true
        end
        ns.UI.Init()
        ns.Nearby.Init()
        C_Timer.After(8, function()
            if ns.db.remindLogin then
                ns.CheckSpells(nil, true)
                if ns.db.remindProf then ns.Prof.Check() end
                ns.CheckTalents()
                ns.Quests.Check()
                -- re-show the talent bubble 15 minutes after it was closed
                C_Timer.NewTicker(60, function()
                    if not InCombatLockdown() then ns.CheckTalents() end
                end)
            end
        end)

    elseif event == "PLAYER_LEVEL_UP" then
        local level = tonumber(arg1) or UnitLevel("player")
        if ns.db.remindLevelUp then ns.CheckSpells(level) end
        if ns.db.remindProf then
            C_Timer.After(1, function() ns.Prof.Check(level) end)
        end
        if ns.UI then ns.UI.talentDismissedAt = nil end  -- a new level shows it right away
        C_Timer.After(1.5, function() ns.CheckTalents() end)
        C_Timer.After(2, function() ns.Quests.Check(level) end)

    elseif event == "HEARTHSTONE_BOUND" then
        C_Timer.After(0.5, function()
            ns.char.bindSpot = { bind = GetBindLocation and GetBindLocation() or "",
                sub = GetSubZoneText() or "", zone = GetRealZoneText() or "" }
        end)

    elseif event == "PLAYER_UPDATE_RESTING" then
        C_Timer.After(1, ns.CheckInn)

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.CheckTalents()  -- the bubble waits until combat ends

    elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        C_Timer.After(0.5, function() ns.CheckTalents() end)

    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "TRADE_SKILL_LIST_UPDATE" then
        -- wait a moment so several skill-ups in a row are checked once, after the last one
        if ns.db.remindProf and not ns.profCheckPending then
            ns.profCheckPending = true
            C_Timer.After(1.5, function()
                ns.profCheckPending = false
                ns.Prof.Check()
            end)
        end

    elseif event == "TRAINER_SHOW" then
        ns.Trainer.OnShow()
    elseif event == "TRAINER_UPDATE" then
        ns.Trainer.OnUpdate()
    elseif event == "TRAINER_CLOSED" then
        ns.Trainer.OnClosed()

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, ns.Nearby.OnZone)
    end
end)

-- Slash commands
SLASH_FORGETMENOT1 = "/fmn"
SLASH_FORGETMENOT2 = "/forgetmenot"
SLASH_FORGETMENOT3 = "/squire"
SLASH_FORGETMENOT4 = "/tn"
SlashCmdList.FORGETMENOT = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI.TogglePanel()
    elseif cmd == "check" then
        ns.seenProf = {}
        ns.CheckSpells(nil, true)
        ns.Prof.Check()
    elseif cmd == "list" then
        ns.Nearby.ShowList(true)
    elseif cmd == "options" or cmd == "config" then
        ns.UI.OpenOptions()
    elseif cmd == "skip" and rest ~= "" then
        ns.char.skipped[rest] = true
        ns.Print("Skipping all ranks of: " .. rest)
        ns.UI.Refresh()
    elseif cmd == "unskip" and rest ~= "" then
        ns.char.skipped[rest] = nil
        ns.Print("No longer skipping: " .. rest)
        ns.UI.Refresh()
    elseif cmd == "recipes" then
        ns.Nearby.ShowRecipes(nil)
    elseif cmd == "talents" then
        ns.DebugTalents()
        ns.CheckTalents()
    elseif cmd == "flights" then
        ns.Nearby.DebugFlights()
    elseif cmd == "notes" then
        ns.UI.ToggleNotes()
    elseif cmd == "dump" then
        ns.Trainer.Dump()
    elseif cmd == "alts" then
        ns.SaveSummary()
        for key, c in pairs(ns.db.chars) do
            ns.Print(format("%s (%s %d): %s", key, c.class or "?", c.level or 0,
                #c.spells > 0 and (#c.spells .. " spell(s) to learn") or "no spells to learn"))
            for _, p in ipairs(c.profs or {}) do ns.Print("   " .. p) end
        end
    elseif cmd == "forget" and rest ~= "" then
        local gone = false
        for key in pairs(ns.db.chars) do
            if key:lower() == rest:lower() or key:lower():match("^" .. rest:lower():gsub("%W", "%%%0") .. "%-") then
                ns.db.chars[key] = nil
                gone = true
                ns.Print("Forgot " .. key)
            end
        end
        if not gone then ns.Print("No character called " .. rest) end
    elseif cmd == "reset" then
        wipe(ns.char.services)
        ns.Print("Spell data cleared. Talk to your class trainer to read it again.")
        ns.UI.Refresh()
    else
        ns.Print("/fmn (or /tn) – panel · /tn check · /tn list · /tn recipes · /tn alts · /tn forget <name> · /tn options · /tn skip <spell> · /tn unskip <spell> · /tn reset")
    end
end

-- Supplies: food and drink in your bags --------------------------------------------
-- Drinks only matter for characters that use mana.
local supplyType = {}   -- itemID -> "food" | "drink" | "both" | false

local function ClassifyItem(itemID)
    if supplyType[itemID] ~= nil then return supplyType[itemID] end
    local kind = false
    local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok and classID == 0 and subClassID == 5 then          -- Consumable > Food & Drink
        local ok2, spellName = pcall(C_Item.GetItemSpell, itemID)
        if ok2 and type(spellName) == "string" then
            if spellName:find("Refreshment") then kind = "both"
            elseif spellName:find("Drink") then kind = "drink"
            elseif spellName:find("Food") then kind = "food" end
        end
    end
    -- item data may not be loaded yet: don't remember "nothing" for good
    if kind or (ok and classID) then supplyType[itemID] = kind end
    return kind
end

function ns.UsesMana()
    return UnitPowerType("player") == 0 or (UnitPowerMax("player", 0) or 0) > 0
end

function ns.CountSupplies()
    local food, drink = 0, 0
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local k = ClassifyItem(info.itemID)
                local n = info.stackCount or 1
                if k == "food" or k == "both" then food = food + n end
                if k == "drink" or k == "both" then drink = drink + n end
            end
        end
    end
    return food, drink
end

-- What you're out of: list of "food" / "drinks"
function ns.MissingSupplies()
    if not ns.db.remindSupplies then return {} end
    local food, drink = ns.CountSupplies()
    if not food then return {} end
    local out = {}
    if food <= ns.db.supplyLow then out[#out + 1] = "food" end
    if ns.UsesMana() and drink <= ns.db.supplyLow then out[#out + 1] = "drinks" end
    return out, food, drink
end

do
    local last = {}
    local pending = false
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    pcall(ev.RegisterEvent, ev, "MERCHANT_SHOW")
    ev:SetScript("OnEvent", function(_, event)
        if not ns.db or not ns.db.remindSupplies then return end
        if event == "BAG_UPDATE_DELAYED" then
            if pending then return end
            pending = true
            C_Timer.After(1, function()
                pending = false
                local missing = ns.MissingSupplies()
                local now = {}
                for _, m in ipairs(missing) do
                    now[m] = true
                    if not last[m] then
                        ns.Print(format("You're out of %s! Buy some at the next vendor.", m))
                        if UIErrorsFrame then UIErrorsFrame:AddMessage("Out of " .. m .. "!", 1, 0.6, 0.2) end
                    end
                end
                last = now
            end)
        elseif event == "MERCHANT_SHOW" then
            C_Timer.After(0.3, function()
                local missing = ns.MissingSupplies()
                if #missing == 0 or not (GetMerchantNumItems and GetMerchantItemID) then return end
                local want = {}
                for _, m in ipairs(missing) do want[m] = true end
                local found = {}
                for i = 1, GetMerchantNumItems() do
                    local id = GetMerchantItemID(i)
                    local k = id and ClassifyItem(id)
                    if k and ((want.food and (k == "food" or k == "both")) or (want.drinks and (k == "drink" or k == "both"))) then
                        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("item " .. id)
                        found[#found + 1] = name
                    end
                end
                if #found > 0 then
                    ns.Print(format("You're out of %s – this vendor sells: %s", table.concat(missing, " and "), table.concat(found, ", ")))
                end
            end)
        end
    end)
end
