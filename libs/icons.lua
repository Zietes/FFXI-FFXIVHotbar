--[[
Icon library for FFXI-FFXIVHotbar.

XIVHotbar2 stores a custom icon in the 6th keybind field and resolves it as
    images/icons/custom/<value>.png
When that field is empty it auto-picks an icon from images/icons/spells|
abilities|weapons/<id>.png, and ma/ja/ws have NO fallback — so an action
whose icon PNG is missing renders as a blank white box. This module lets the
editor offer a picker so the user can assign a working icon.

What it exposes:
  icons.list()        -> sorted list of { value, label, category, path }
                         covering the user's images/icons/custom/ folder
                         (recursively) plus the bundled spells/abilities/
                         weapons/items sets. `path` is an absolute file path
                         for previews; `value` is what to store in the slot.
  icons.resolve(v)    -> absolute path a stored value points at (or nil)
  icons.reload()      -> drop the cached list

Built-in (non-custom) icons are referenced with a '../set/name' value so
XIVHotbar2's hard-coded 'custom/' prefix still resolves to them, e.g.
'../spells/00123' -> images/icons/custom/../spells/00123.png.
]]

local locator = require('libs/locator')

local icons = {}
local SEP = locator.sep()
local cache = nil

local function get_dir(path)
    if windower and windower.get_dir then
        local ok, res = pcall(windower.get_dir, path)
        if ok and type(res) == 'table' then return res end
    end
    return {}
end

local function is_dir(path)
    return windower and windower.dir_exists and windower.dir_exists(path) and true or false
end

local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close() return true end
    return false
end

-- Recursively gather PNGs under the custom/ folder. `rel` is the path so far
-- using '/' (the separator XIVHotbar2 expects in the stored value).
local function collect_custom(dir, rel, out, depth)
    if depth > 5 then return end
    for _, raw in ipairs(get_dir(dir)) do
        local name = raw:gsub('[\\/]+$', '')
        if name ~= '' and name ~= '.' and name ~= '..' then
            local full = dir .. name
            if is_dir(full .. SEP) then
                collect_custom(full .. SEP, rel .. name .. '/', out, depth + 1)
            else
                local base = name:match('^(.*)%.[Pp][Nn][Gg]$')
                if base then
                    local value = rel .. base
                    table.insert(out, { value = value, label = value,
                                        category = 'Custom', path = full })
                end
            end
        end
    end
end

-- Gather PNGs from a bundled icon set (flat folder of id-named files).
local function collect_set(set, out)
    local dir = icons.dir() .. set .. SEP
    for _, raw in ipairs(get_dir(dir)) do
        local name = raw:gsub('[\\/]+$', '')
        local base = name:match('^(.*)%.[Pp][Nn][Gg]$')
        if base then
            table.insert(out, {
                value    = '../' .. set .. '/' .. base,
                label    = set .. '/' .. base,
                category = set,
                path     = dir .. name,
            })
        end
    end
end

function icons.dir() return locator.icons_dir() end

function icons.reload() cache = nil end

function icons.list()
    if cache then return cache end
    local out = {}
    collect_custom(icons.dir() .. 'custom' .. SEP, '', out, 0)
    for _, set in ipairs({ 'spells', 'abilities', 'weapons', 'items' }) do
        collect_set(set, out)
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.label < b.label
    end)
    cache = out
    return out
end

-- Absolute path a stored icon value resolves to, mirroring XIVHotbar2
-- (images/icons/custom/<value>.png). Returns nil for empty/auto or missing.
function icons.resolve(value)
    if not value or value == '' then return nil end
    -- Built-in sets are stored as '../set/name'; collapse the leading '../'
    -- so the preview points straight at images/icons/<set>/<name>.png rather
    -- than relying on the OS to normalise '..' in custom/../set/name.
    local up = value:match('^%.%./(.+)$')
    local path
    if up then
        path = icons.dir() .. up:gsub('/', SEP) .. '.png'
    else
        path = icons.dir() .. 'custom' .. SEP .. value:gsub('/', SEP) .. '.png'
    end
    if file_exists(path) then return path end
    return nil
end

return icons
