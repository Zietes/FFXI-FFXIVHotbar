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
--
-- Windower's res.spells stores `spell.targets` as a BITFIELD NUMBER, not
-- a string. Older docs sometimes describe it as a string, so we handle
-- both shapes defensively. The bits are:
--
--   0x01 / 1   Self
--   0x02 / 2   Player    (other PC, sub-target pick)
--   0x04 / 4   Party
--   0x08 / 8   Ally      (alliance)
--   0x10 / 16  NPC
--   0x20 / 32  Enemy
--
-- Example values you'll see in res.spells: Cure=63 (every bit), Curaga=5
-- (self+party), Stone=32 (enemy only), Stoneskin=1 (self only),
-- Raise=157 (self+party+ally+npc+0x80=corpse).
--
-- Calling :lower() on a number (the original implementation) crashed the
-- spell-list build and broke every Action dropdown — that's the fix here.

local function infer_default_target(targets)
    if not targets then return 't' end

    -- Tolerate the legacy string form.
    if type(targets) == 'string' then
        local s = targets:lower()
        if s:find('self', 1, true) then return 'me' end
        if s:find('enemy', 1, true) then return 'stnpc' end
        if s:find('player', 1, true) then return 'stpc' end
        if s:find('party', 1, true) then return 'stpt' end
        return 't'
    end

    if type(targets) ~= 'number' then return 't' end

    -- Bitfield path. `bit` is the BitOp library Windower bundles.
    local has = function(mask) return bit.band(targets, mask) ~= 0 end

    -- Pure self spells (Stoneskin / Cocoon / Spectral Jig)
    if has(1) and not has(2) and not has(4) and not has(32) then
        return 'me'
    end
    -- Enemy-only attack spells (Stone, Fire, Silence, etc.)
    if has(32) and not has(1) and not has(2) and not has(4) then
        return 'stnpc'
    end
    -- Single-target friendly cast (Cure family — has player bit set).
    -- Prefer stpc so XIVHotbar2 will sub-target a player to heal.
    if has(2) then return 'stpc' end
    -- Party-wide (Curaga, Protectra, Phalanx II)
    if has(4) then return 'stpt' end
    -- Self-capable fallback
    if has(1) then return 'me' end
    -- Enemy fallback
    if has(32) then return 'stnpc' end
    return 't'
end

-- ============================================================================
-- Spells
-- ============================================================================
function actions.list_spells()
    local out = {}
    local player = windower.ffxi.get_player()
    if not player then return out end
    -- Only spells the CURRENT main/sub job can actually cast. get_spells()
    -- returns every spell the player has ever learned on any job, so without
    -- this filter a GEO would see DRK Absorb spells, etc. res.spells[id].levels
    -- maps job_id -> the level at which that job learns the spell.
    local main_id, main_lv = player.main_job_id, player.main_job_level or 99
    local sub_id,  sub_lv  = player.sub_job_id,  player.sub_job_level  or 0
    local known = windower.ffxi.get_spells() or {}
    for id, is_known in pairs(known) do
        if is_known == true then
            local s = res.spells[id]
            if s and s.en and s.type and s.type ~= 'Trust' then
                local levels = s.levels or {}
                local lv_main = main_id and levels[main_id]
                local lv_sub  = sub_id  and levels[sub_id]
                if (lv_main and main_lv >= lv_main) or
                   (lv_sub  and sub_lv  >= lv_sub) then
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
    end
    table.sort(out, function(a, b) return a.action < b.action end)
    return out
end

-- ============================================================================
-- Job abilities
-- ============================================================================
function actions.list_abilities()
    local out = {}
    -- get_abilities() returns exactly what the current job/subjob can use
    -- right now — it accounts for level, merits and unlocked flags — so we
    -- don't have to re-derive availability from res.job_abilities level tables.
    local avail = windower.ffxi.get_abilities()
    if not avail or not avail.job_abilities then return out end
    local seen = {}
    for _, id in pairs(avail.job_abilities) do
        local a = res.job_abilities[id]
        if a and a.en and a.type ~= 'Monster' and not seen[a.en] then
            seen[a.en] = true
            table.insert(out, {
                cmd = 'ja',
                action = a.en,
                default_target = infer_default_target(a.targets),
                label = a.en:sub(1, 8),
                category = 'Ability',
            })
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
    -- Weapon skills from get_abilities() are the ones usable with the
    -- currently equipped weapon at the player's skill level, which is far
    -- more useful than listing every WS in the resources.
    local avail = windower.ffxi.get_abilities()
    if not avail or not avail.weapon_skills then return out end
    local seen = {}
    for _, id in pairs(avail.weapon_skills) do
        local ws = res.weapon_skills[id]
        if ws and ws.en and not seen[ws.en] then
            seen[ws.en] = true
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

-- Current Windower exposes res.items[id].flags as a structured flag
-- table (named bitflags) rather than a raw number, so bit.band on it
-- throws "number expected, got table". Handle both shapes, and fall
-- back to cast_time (only usable items have one) so the filter still
-- works if the flag layout changes again.
local function is_usable_item(def)
    local f = def.flags
    if type(f) == 'number' then
        return bit.band(f, 0x0200) ~= 0
    end
    if type(f) == 'table' then
        if f['Can Use'] or f.CanUse or f.can_use then return true end
        if f['Activatable'] or f.activatable then return true end
    end
    return def.cast_time ~= nil and def.cast_time > 0
end

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
                    if def and def.en and not seen[def.en] then
                        if is_usable_item(def) then
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
