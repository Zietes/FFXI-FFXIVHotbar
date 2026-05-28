--[[
Macro library for FFXI-FFXIVHotbar.

Keeps a list of named, reusable command macros in a plain-text file
(data/macros.txt) that the user edits in any text editor. When a hotbar
slot's command type is "macro", the Action dropdown lists these by name;
picking one writes the macro body into the slot's `action` field and the
macro name into its `label`.

File format — one macro per line:

    # lines starting with '#' or '--' are comments
    Name = command body

The body is stored verbatim in the keybind file, so multi-step macros use
whatever separator XIVHotbar2 expects (typically ';'):

    Pull = /p Pulling <t> ; /ws "Combo" <t>
]]

local macros = {}

local SAMPLE = [[
# FFXI-FFXIVHotbar macro library
# One macro per line:   Name = command body
# Lines starting with '#' or '--' are ignored.
#
# Write normal game commands (keep the leading slash). For multi-step
# macros, separate commands with ';' and use 'wait N' for a delay:
#
#   Buffs = /ma "Protect" <me> ; wait 5 ; /ma "Shell" <me>
#
# Advanced: a step WITHOUT a leading slash runs as a Windower command
# (e.g. gs c ...), so you can mix those in too.
#
# Examples (edit or delete these):
Sneak = /ma "Sneak" <me>
Pull  = /p Pulling <t> ; /ws "Combo" <t>
]]

local function data_dir()
    local dir = (windower and windower.addon_path or '') .. 'data/'
    if windower and windower.dir_exists and not windower.dir_exists(dir) then
        if windower.create_dir then windower.create_dir(dir) end
    end
    return dir
end

function macros.path()
    return data_dir() .. 'macros.txt'
end

-- Create a starter file the first time so the user always has something to
-- edit and a known location to look in.
function macros.ensure()
    local path = macros.path()
    local f = io.open(path, 'r')
    if f then f:close(); return path end
    local w = io.open(path, 'w')
    if w then w:write(SAMPLE); w:close() end
    return path
end

-- Split a macro body on ';' into trimmed, non-empty steps.
local function split_steps(body)
    local steps = {}
    local start = 1
    while true do
        local p = body:find(';', start, true)
        local chunk = p and body:sub(start, p - 1) or body:sub(start)
        chunk = chunk:gsub('^%s+', ''):gsub('%s+$', '')
        if chunk ~= '' then table.insert(steps, chunk) end
        if not p then break end
        start = p + 1
    end
    return steps
end

-- Convert a human-written macro body into the string to store in a 'macro'
-- slot. XIVHotbar2 runs a macro action as ('//' .. action), so a raw game
-- command like `/ma "Sneak" <me>` would become `///ma ...` and silently fail.
-- We wrap each game command (a step starting with '/') as `input /...` so it
-- becomes `//input /ma "Sneak" <me>` and actually types into the game. Steps
-- that are already Windower commands (gs, send, wait, input, ...) are left
-- alone, and multiple steps stay ';'-separated so Windower runs them in order.
function macros.to_command(body)
    local out = {}
    for _, s in ipairs(split_steps(body or '')) do
        if s:sub(1, 1) == '/' then s = 'input ' .. s end
        table.insert(out, s)
    end
    return table.concat(out, '; ')
end

-- Read + parse the macro file fresh (cheap, only called when the macro
-- dropdown opens). Returns a sorted list of { name = ..., body = ... }.
function macros.list()
    macros.ensure()
    local out = {}
    local f = io.open(macros.path(), 'r')
    if not f then return out end
    for line in f:lines() do
        local s = line:gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' and s:sub(1, 1) ~= '#' and s:sub(1, 2) ~= '--' then
            local name, body = s:match('^(.-)%s*=%s*(.*)$')
            if name and name ~= '' and body and body ~= '' then
                table.insert(out, { name = name, body = body })
            end
        end
    end
    f:close()
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

return macros
