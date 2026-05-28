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
# Multi-step macros: separate the commands the way XIVHotbar2 expects (';').
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
