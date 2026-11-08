-- Squire: core, saved settings, messages, events, slash commands
local ADDON, ns = ...

local PREFIX = "|cffffd100[Squire]|r "

local DEFAULTS = {
    remindLevelUp = true,   -- check spells when you level up
    remindLogin   = true,   -- check spells and professions at login
    remindCity    = true,   -- show the to-do list when entering a city below
    remindNear    = true,   -- show the to-do list when close to a trainer you need
    remindProf    = true,   -- profession reminders
    remindCapCraft = false, -- warn on every craft/gather while a profession is capped (off: to-do list only)
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
        if not s.known and s.level <= level and not ns.IsSkipped(s) then
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
        if not s.known and s.level > level and s.level <= level + range and not ns.IsSkipped(s) then
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
function ns.UnspentTalents()
    if UnitCharacterPoints then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and type(n) == "number" then return n end
    end
    if GetUnspentTalentPoints then
        local ok, n = pcall(GetUnspentTalentPoints)
        if ok and type(n) == "number" then return n end
    end
    return nil
end

local lastTalentMsg
function ns.CheckTalents()
    local n = ns.db.remindTalents and ns.UnspentTalents() or 0
    if n and n > 0 and n ~= lastTalentMsg then
        ns.Print(format("You have %d unspent talent point(s). Open your talents to spend them.", n))
    end
    lastTalentMsg = n
    if ns.UI then
        ns.UI.TalentBubble(n or 0)
        ns.UI.Refresh()
    end
end

-- Events
local f = CreateFrame("Frame")
local lastSkill = 0

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SKILL_LINES_CHANGED")
pcall(f.RegisterEvent, f, "CHARACTER_POINTS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:RegisterEvent("TRAINER_CLOSED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        SquireDB = SquireDB or {}
        SquireCharDB = SquireCharDB or {}
        ApplyDefaults(SquireDB, DEFAULTS)
        ApplyDefaults(SquireCharDB, CHAR_DEFAULTS)
        ns.db, ns.char = SquireDB, SquireCharDB
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
        -- one-time move of settings and data from the old TrainerNudge name
        if not ns.db.migratedFromTN and type(TrainerNudgeDB) == "table" then
            for k, v in pairs(TrainerNudgeDB) do ns.db[k] = v end
            ns.db.migratedFromTN = true
            ns.Print("Moved your TrainerNudge settings over to Squire.")
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
            end
        end)

    elseif event == "PLAYER_LEVEL_UP" then
        local level = tonumber(arg1) or UnitLevel("player")
        if ns.db.remindLevelUp then ns.CheckSpells(level) end
        if ns.db.remindProf then
            C_Timer.After(1, function() ns.Prof.Check(level) end)
        end
        C_Timer.After(1.5, function() ns.CheckTalents() end)
        C_Timer.After(2, function() ns.Quests.Check(level) end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.CheckTalents()  -- the bubble waits until combat ends

    elseif event == "CHARACTER_POINTS_CHANGED" then
        C_Timer.After(0.5, function() ns.CheckTalents() end)

    elseif event == "SKILL_LINES_CHANGED" then
        local now = GetTime()
        if ns.db.remindProf and now - lastSkill > 2 then
            lastSkill = now
            C_Timer.After(0.5, function() ns.Prof.Check() end)
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
SLASH_SQUIRE1 = "/squire"
SLASH_SQUIRE2 = "/tn"
SlashCmdList.SQUIRE = function(input)
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
        local list = ns.Prof.RecipeList()
        if #list == 0 then ns.Print("No recipes waiting. Talk to your profession trainers to update the list.") end
        for _, p in ipairs(list) do
            ns.Print(format("%s: %d recipe(s), total %s", p.name, #p.list, ns.Money(p.cost)))
            for _, r in ipairs(p.list) do ns.Print("   " .. r.name .. " – " .. ns.Money(r.cost)) end
        end
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
        ns.Print("/squire (or /tn) – panel · /tn check · /tn list · /tn recipes · /tn alts · /tn forget <name> · /tn options · /tn skip <spell> · /tn unskip <spell> · /tn reset")
    end
end
