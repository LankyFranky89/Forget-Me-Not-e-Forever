-- Squire: profession milestones (Vanilla rules)
local ADDON, ns = ...
local P = {}
ns.Prof = P

-- Keyed by your current cap. Edit here if Forever's rules differ.
P.TIERS = {
    [75]  = { next = "Journeyman", cap = 150, level = 10, skill = 50 },
    [150] = { next = "Expert",     cap = 225, level = 20, skill = 125 },
    [225] = { next = "Artisan",    cap = 300, level = 35, skill = 200 },
}

-- Secondary professions don't always train at a trainer in Vanilla
P.SECONDARY = {
    ["Cooking"]   = { [150] = "a book from a vendor", [225] = "a quest" },
    ["First Aid"] = { [150] = "a book from a vendor", [225] = "a quest" },
    ["Fishing"]   = { [150] = "a book from a vendor", [225] = "a quest" },
}

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
                if rank >= rule.skill and level >= rule.level then
                    e.state = "train"
                    e.text = format("%s %d/%d: you can learn %s %s now, from %s.", name, rank, maxRank, rule.next, name, where)
                elseif rank >= maxRank then
                    e.state = "capped"
                    e.text = format("%s is capped at %d. %s needs level %d.", name, maxRank, rule.next, rule.level)
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
    if ns.UI then ns.UI.Refresh() end
end
