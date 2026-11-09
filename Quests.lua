-- Forget-Me-Not: class quest reminders
--
-- Data from WoW Forever class quest guides (Icy Veins, Warcraft Tavern, wow4ever.quest).
-- Each entry:
--   level    = when the quest becomes available
--   quest    = the quest to look for (first step)
--   reward   = what you get
--   spell(s) = a spell the quest teaches; known = done (works even for quests done before Forget-Me-Not)
--   final    = last quest title(s) of the chain; turned in = done (only seen while Forget-Me-Not runs)
--   faction / races = who gets it (raceFile names: Human, Dwarf, NightElf, Gnome, Orc, Scourge, Troll, Tauren)
-- Quests that are only remembered by turn-in can be hidden with /fmn skip <quest name>.
local ADDON, ns = ...
local Q = {}
ns.Quests = Q

Q.LIST = {
    WARRIOR = {
        { level = 10, quest = "Bartleby the Drunk / Veteran Uzzek (ask your class trainer)", reward = "Defensive Stance", spell = "Defensive Stance" },
        { level = 10, quest = "The Skybreaker Bulwark", reward = "Stormforged Protector (shield)", final = { "The Skybreaker Bulwark" } },
        { level = 30, quest = "Berserker Stance quest (ask your class trainer)", reward = "Berserker Stance", spell = "Berserker Stance" },
        { level = 30, quest = "Cyclonian", reward = "Whirlwind weapon", final = { "Whirlwind Weapon" } },
    },
    PALADIN = {
        { level = 12, faction = "Alliance", quest = "The Tome of Divinity", reward = "Redemption", spell = "Redemption" },
        { level = 12, faction = "Horde", quest = "A Lesson in Divinity", reward = "Redemption", spell = "Redemption" },
        { level = 20, faction = "Alliance", quest = "The Tome of Valor", reward = "Verigan's Fist", final = { "The Test of Righteousness" } },
        { level = 20, faction = "Horde", quest = "A Moon-Kissed Blade", reward = "Moonsilver Blade / Wolfsbane", final = { "The Moonsilver Blade", "Old Fire-Eye" } },
        { level = 40, faction = "Alliance", quest = "The Tome of Nobility", reward = "Summon Warhorse", spell = "Summon Warhorse" },
    },
    HUNTER = {
        { level = 10, quest = "Taming the Beast", reward = "Tame Beast (your first pet)", spell = "Tame Beast" },
    },
    ROGUE = {
        { level = 20, quest = "Poisons quest (ask your class trainer)", reward = "Poisons", spell = "Poisons" },
        { level = 24, quest = "The Manor, Ravenholdt", reward = "Ravenholdt access", final = { "Syndicate Emblems" } },
    },
    PRIEST = {
        { level = 10, races = { Human = true, Dwarf = true }, quest = "Desperate Prayer", reward = "Desperate Prayer", spell = "Desperate Prayer" },
        { level = 10, races = { NightElf = true }, quest = "Stars of Elune", reward = "Starshards", spell = "Starshards" },
        { level = 10, races = { Troll = true }, quest = "Hex of Weakness", reward = "Hex of Weakness", spell = "Hex of Weakness" },
        { level = 10, races = { Scourge = true }, quest = "Touch of Weakness", reward = "Touch of Weakness", spell = "Touch of Weakness" },
        { level = 20, races = { Human = true }, quest = "Arcane Feedback", reward = "Feedback", spell = "Feedback" },
        { level = 20, races = { Dwarf = true }, quest = "A Lack of Fear", reward = "Fear Ward", spell = "Fear Ward" },
        { level = 20, races = { NightElf = true }, quest = "Elune's Grace", reward = "Elune's Grace", spell = "Elune's Grace" },
        { level = 20, races = { Troll = true }, quest = "Shadowguard", reward = "Shadowguard", spell = "Shadowguard" },
        { level = 20, races = { Scourge = true }, quest = "Devouring Plague", reward = "Devouring Plague", spell = "Devouring Plague" },
    },
    SHAMAN = {
        { level = 4,  quest = "Call of Earth", reward = "Earth Totem", item = "Earth Totem" },
        { level = 10, quest = "Call of Fire",  reward = "Fire Totem",  item = "Fire Totem" },
        { level = 20, quest = "Call of Water", reward = "Water Totem", item = "Water Totem" },
        { level = 30, quest = "Call of Air",   reward = "Air Totem",   item = "Air Totem" },
    },
    MAGE = {
        { level = 30, quest = "Journey to the Marsh", reward = "Mage's wand", final = { "Mage's Wand" } },
        { level = 35, quest = "Return to the Marsh", reward = "Celestial Power", final = { "Celestial Power" } },
    },
    WARLOCK = {
        { level = 10, quest = "Voidwalker quest (ask your class trainer)", reward = "Summon Voidwalker", spell = "Summon Voidwalker" },
        { level = 20, quest = "Succubus / Incubus quest (ask your class trainer)", reward = "Summon Succubus or Incubus", spells = { "Summon Succubus", "Summon Incubus" } },
        { level = 30, quest = "Felhunter quest (ask your class trainer)", reward = "Summon Felhunter", spell = "Summon Felhunter" },
        { level = 40, quest = "Felsteed quest (ask your class trainer)", reward = "Summon Felsteed", spell = "Summon Felsteed" },
    },
    DRUID = {
        { level = 10, quest = "Bear Form quest (ask your class trainer)", reward = "Bear Form", spell = "Bear Form" },
        { level = 14, quest = "Lessons Anew", reward = "Cure Poison", spell = "Cure Poison" },
        { level = 16, quest = "Aquatic Form quest (ask your class trainer)", reward = "Aquatic Form", spell = "Aquatic Form" },
        { level = 20, quest = "The Great Cat Spirit", reward = "Cat Form", spell = "Cat Form" },
    },
}

local function KnowsSpell(name)
    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        local ok, slot = pcall(C_SpellBook.FindSpellBookSlotForSpell, name)
        if ok and slot then return true end
    end
    for _, s in pairs(ns.char.services) do
        if s.known and s.name == name then return true end
    end
    return false
end

local function HasItem(name)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, name, true)  -- true = include bank
        if ok and type(n) == "number" and n > 0 then return true end
    end
    return false
end

local function Done()
    ns.char.questsDone = ns.char.questsDone or {}
    return ns.char.questsDone
end

local function IsDone(q)
    local done = Done()
    if done[q.quest] then return true end
    local ok = false
    if q.spell and KnowsSpell(q.spell) then ok = true end
    if q.spells then
        for _, s in ipairs(q.spells) do if KnowsSpell(s) then ok = true end end
    end
    if q.item and HasItem(q.item) then ok = true end
    if q.final then
        for _, t in ipairs(q.final) do if done[t] then ok = true end end
    end
    if ok then done[q.quest] = true end  -- remember, e.g. if a totem is banked later
    return ok
end

-- Quest titles in your quest log right now
local function LogTitles()
    local titles = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(n) == "number" then
            for i = 1, n do
                local ok2, info = pcall(C_QuestLog.GetInfo, i)
                if ok2 and info and info.title and not info.isHeader then titles[info.title] = true end
            end
        end
    end
    return titles
end

-- Class quests available now and not done. Each gets .inLog if it's in your quest log.
function Q.Open(level)
    level = level or UnitLevel("player")
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local inLog = LogTitles()
    local out = {}
    for _, q in ipairs(Q.LIST[classFile] or {}) do
        if level >= q.level
            and (not q.faction or q.faction == faction)
            and (not q.races or q.races[raceFile])
            and not ns.IsSkipped({ name = q.quest, rank = "" })
            and not IsDone(q) then
            q.inLog = inLog[q.quest] or false
            if q.final then
                for _, t in ipairs(q.final) do if inLog[t] then q.inLog = true end end
            end
            out[#out + 1] = q
        end
    end
    return out
end

local seen = {}
function Q.Check(level)
    if not ns.db.remindQuests then return end
    for _, q in ipairs(Q.Open(level)) do
        if not seen[q.quest] and not q.inLog then
            seen[q.quest] = true
            ns.Print(format("Class quest available: %s (level %d) – rewards %s.", q.quest, q.level, q.reward))
        end
    end
    if ns.UI then ns.UI.Refresh() end
end

-- Remember turned-in quest titles, so item-reward chains count as done
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(_, _, questID)
    if not ns.char or type(questID) ~= "number" then return end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" then
            Done()[title] = true
            if ns.UI then ns.UI.Refresh() end
        end
    end
end)
