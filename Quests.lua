-- Squire: class quest reminders
local ADDON, ns = ...
local Q = {}
ns.Quests = Q

-- level, quest to ask for, what it gives, and how the addon sees it's done:
--   spell = a spell the quest teaches, item = an item it gives (checked in your bags)
-- faction: only for that faction (nil = both)
Q.LIST = {
    PALADIN = {
        { level = 12, faction = "Alliance", quest = "The Tome of Divinity", reward = "Redemption", spell = "Redemption" },
        { level = 20, faction = "Alliance", quest = "The Tome of Valor", reward = "Sense Undead and Verigan's Fist", spell = "Sense Undead" },
        { level = 40, faction = "Alliance", quest = "Paladin mount quest (ask your class trainer)", reward = "Warhorse", spell = "Summon Warhorse" },
    },
    SHAMAN = {
        { level = 4,  quest = "Call of Earth", reward = "Earth Totem", item = "Earth Totem" },
        { level = 10, quest = "Call of Fire",  reward = "Fire Totem",  item = "Fire Totem" },
        { level = 20, quest = "Call of Water", reward = "Water Totem", item = "Water Totem" },
        { level = 30, quest = "Call of Air",   reward = "Air Totem",   item = "Air Totem" },
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
    local count = 0
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, name, true)  -- true = include bank
        if ok and type(n) == "number" then count = n end
    end
    return count > 0
end

local function IsDone(q)
    ns.char.questsDone = ns.char.questsDone or {}
    if ns.char.questsDone[q.quest] then return true end
    local done = (q.spell and KnowsSpell(q.spell)) or (q.item and HasItem(q.item))
    if done then ns.char.questsDone[q.quest] = true end  -- remember, e.g. if the totem is banked later
    return done
end

-- Class quests available now and not done
function Q.Open(level)
    level = level or UnitLevel("player")
    local _, classFile = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local out = {}
    for _, q in ipairs(Q.LIST[classFile] or {}) do
        if level >= q.level and (not q.faction or q.faction == faction)
            and not ns.IsSkipped({ name = q.quest, rank = "" }) and not IsDone(q) then
            out[#out + 1] = q
        end
    end
    return out
end

local seen = {}
function Q.Check(level)
    if not ns.db.remindQuests then return end
    for _, q in ipairs(Q.Open(level)) do
        if not seen[q.quest] then
            seen[q.quest] = true
            ns.Print(format("Class quest available: %s (level %d) – rewards %s.", q.quest, q.level, q.reward))
        end
    end
    if ns.UI then ns.UI.Refresh() end
end
