--[[
Build a list of every action the current player can currently slot on
the hotbar — spells they've learned, abilities their job/level grants,
and items in their bags that have an on-use effect.

Used by the action-picker dropdown so the user doesn't have to remember
exact spell names (and doesn't get a list of spells they don't know).

Return shape: list of records
  { cmd, action, default_target, label, category }
where `category` groups the picker:
  'Magic', 'Ability', 'Weaponskill', 'Item', 'Pet'
]]

local actions = {}

local res = require('resources')

-- ============================================================================
-- Default-target inference
-- ============================================================================
-- XIVHotbar2's `target` field is one of:
--   me, t, stpc, stnpc, stal, stpt, bt, p0..p5, p1..p5
-- Most spells map cleanly from spell.targets bitfield.

local function infer_default_target(targets_str)
    if not targets_str then return 't' end
    local s = (targets_str):lower()
    if s:find('self', 1, true) then return 'me' end
    if s:find('enemy', 1, true) then return 'stnpc' end
    if s:find('player', 1, true) then return 'stpc' end
    if s:find('party', 1, true) then return 'stpt' end
    return 't'
end

-- ============================================================================
-- Spells
-- ============================================================================
function actions.list_spells()
    local out = {}
    local player = windower.ffxi.get_player()
    if not player then return out end
    local known = windower.ffxi.get_spells() or {}
    for id, is_known in pairs(known) do
        if is_known == true then
            local s = res.spells[id]
            if s and s.en and s.type and s.type ~= 'Trust' then
                table.insert(out, {
                    cmd = 'ma',
                    action = s.en,
                    default_target = infer_default_target(s.targets),
                    label = s.en:sub(1, 8),    -- short text shown on the slot
                    category = 'Magic',
                })
            end
        end
    end
    table.sort(out, function(a, b) return a.action < b.action end)
    return out
end

-- ============================================================================
-- Job abilities
-- ============================================================================
function actions.list_abilities()
    local out = {}
    local player = windower.ffxi.get_player()
    if not player then return out end
    local main_id, main_lv = player.main_job_id, player.main_job_level or 99
    local sub_id,  sub_lv  = player.sub_job_id,  player.sub_job_level  or 0

    for _, a in pairs(res.job_abilities) do
        if a.en and a.type ~= 'Monster' then
            local levels = a.levels or {}
            local lv_main = levels[main_id]
            local lv_sub  = levels[sub_id]
            if (lv_main and main_lv >= lv_main) or
               (lv_sub  and sub_lv  >= lv_sub) then
                table.insert(out, {
                    cmd = 'ja',
                    action = a.en,
                    default_target = infer_default_target(a.targets),
                    label = a.en:sub(1, 8),
                    category = 'Ability',
                })
            end
        end
    end
    table.sort(out, function(a, b) return a.action < b.action end)
    return out
end

-- ============================================================================
-- Weaponskills (filtered by equipped main weapon type would be ideal but
-- requires extra lookup; for now we list all WS the player meets the
-- level threshold for, and the user picks from there).
-- ============================================================================
function actions.list_weaponskills()
    local out = {}
    local player = windower.ffxi.get_player()
    if not player then return out end
    for _, ws in pairs(res.weapon_skills) do
        if ws.en and ws.type ~= 'BloodPactPhysical' and ws.type ~= 'BloodPactMagical' then
            table.insert(out, {
                cmd = 'ws',
                action = ws.en,
                default_target = 't',
                label = ws.en:sub(1, 8),
                category = 'Weaponskill',
            })
        end
    end
    table.sort(out, function(a, b) return a.action < b.action end)
    return out
end

-- ============================================================================
-- Items — only those that are usable (have an on-use effect / activate
-- flag), pulled from the player's actual bags.
-- ============================================================================
function actions.list_items()
    local out = {}
    local items = windower.ffxi.get_items()
    if not items then return out end
    local seen = {}
    local bags = { 'inventory', 'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4',
                   'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8',
                   'satchel', 'sack', 'case' }
    for _, bag_name in ipairs(bags) do
        local bag = items[bag_name]
        if bag and type(bag) == 'table' then
            for slot = 1, (bag.max or 80) do
                local it = bag[slot]
                if it and type(it) == 'table' and it.id and it.id ~= 0 then
                    local def = res.items[it.id]
                    -- Activate-able items have non-zero "activate_ability"
                    -- bit in flags (0x0200 = "Can use"). Best-effort filter.
                    if def and def.en and not seen[def.en] and def.flags then
                        local usable = bit.band(def.flags or 0, 0x0200) ~= 0
                        if usable then
                            seen[def.en] = true
                            table.insert(out, {
                                cmd = 'item',
                                action = def.en,
                                default_target = 'me',
                                label = def.en:sub(1, 8),
                                category = 'Item',
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.action < b.action end)
    return out
end

-- ============================================================================
-- All actions combined (for one big searchable list in the picker).
-- ============================================================================
function actions.list_all()
    local out = {}
    for _, list in ipairs({ actions.list_spells(),
                            actions.list_abilities(),
                            actions.list_weaponskills(),
                            actions.list_items() }) do
        for _, a in ipairs(list) do table.insert(out, a) end
    end
    return out
end

-- Valid XIVHotbar2 target identifiers
actions.TARGETS = { 'me', 't', 'stpc', 'stnpc', 'stal', 'stpt', 'bt',
                    'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }

-- Valid XIVHotbar2 command types
actions.COMMANDS = { 'ma', 'ja', 'ws', 'item', 'pet', 'macro', 'input', 'ct' }

return actions
