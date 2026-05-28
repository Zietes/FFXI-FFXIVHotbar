--[[
Write XIVHotbar2 keybind .lua files back with a single slot's worth of
change, preserving the existing line ordering and any non-slot content
(headers, comments, the assignment statement, etc.).

Strategy:
  1. Read the entire file as text.
  2. Locate the line for the target slot_id ('battle X Y'). It can be
     active (`{...}`) or commented-out (`--{...}`).
  3. Replace that single line with a freshly-serialized version using
     the new field values.
  4. If the slot was set to "empty" (cmd/action/target/label all blank),
     emit it as a `--{...}` comment so XIVHotbar2's index alignment stays
     correct.
  5. Backup the original to data/backups/<filename>.<timestamp>.bak in
     OUR addon's folder (not XIVHotbar2's) before writing.

If the slot_id line doesn't exist in the file at all, we APPEND a new
line at the end of the table literal (best-effort). For now we only
support files that already declare every slot — XIVHotbar2's stock
data templates do this, so it's the common case.
]]

local writer = {}

local function read_file(path)
    local f, err = io.open(path, 'r')
    if not f then return nil, err end
    local s = f:read('*a')
    f:close()
    return s
end

local function write_file(path, content)
    local f, err = io.open(path, 'w')
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function basename(path)
    return (path or ''):match('([^\\/]+)$') or 'unknown.lua'
end

-- Where backups go. Lives under FFXI-FFXIVHotbar/data/backups/ so each
-- player's edits get logged locally without bloating the XIVHotbar2
-- folder.
local function backup_dir()
    local dir = (windower and windower.addon_path or '') .. 'data/backups/'
    if windower and windower.dir_exists and not windower.dir_exists(dir) then
        if windower.create_dir then windower.create_dir(dir) end
    end
    return dir
end

local function backup(path, src)
    local stamp = os.date('%Y%m%d_%H%M%S')
    local out = backup_dir() .. basename(path) .. '.' .. stamp .. '.bak'
    return write_file(out, src), out
end

-- Quote-escape a value for Lua single-quoted string literals.
local function q(s)
    s = tostring(s or '')
    return s:gsub('\\', '\\\\'):gsub("'", "\\'")
end

-- Serialize a slot record back to its `{...}` line form. fields_count
-- controls whether we emit 5 or 6 fields (6 only when a custom icon is set).
local function serialize_slot(slot)
    local parts = {
        "'" .. q(slot.slot_id) .. "'",
        "'" .. q(slot.cmd or '') .. "'",
        "'" .. q(slot.action or '') .. "'",
        "'" .. q(slot.target or '') .. "'",
        "'" .. q(slot.label or '') .. "'",
    }
    if slot.icon and slot.icon ~= '' then
        table.insert(parts, "'" .. q(slot.icon) .. "'")
    end
    return '{' .. table.concat(parts, ', ') .. '}'
end

-- Decide whether the slot's content is effectively empty (so we emit
-- it as a commented-out placeholder).
local function is_empty_slot(slot)
    return (slot.cmd    or '') == ''
       and (slot.action or '') == ''
       and (slot.target or '') == ''
       and (slot.label  or '') == ''
end

-- Replace the line in `src` that defines the given slot_id with a new
-- serialization of `slot`. Match either the active `{'battle X Y', ...}`
-- or the commented `--{'battle X Y', ...}` form.
function writer.save(path, slot)
    if not slot or not slot.slot_id then
        return nil, 'slot.slot_id missing'
    end
    local src, err = read_file(path)
    if not src then return nil, err end

    local literal = is_empty_slot(slot)
        and ("--" .. serialize_slot({slot_id = slot.slot_id, cmd='', action='', target='', label=''}))
        or  serialize_slot(slot)

    -- Locate any line containing the slot_id literal as the first field
    -- of a table constructor. Both `--{'battle 1 1',...` and `{'battle
    -- 1 1',...` patterns are accepted. The regex captures: leading
    -- whitespace + (optional `--`) + `{...}` + trailing chars.
    local needle = "'" .. slot.slot_id .. "'"
    local matched = false
    local lines = {}
    local i = 1
    for line in src:gmatch('([^\n]*)\n?') do
        if not matched then
            local trimmed = line:gsub('^%s+', '')
            local has_dash = trimmed:sub(1, 2) == '--'
            local body = has_dash and trimmed:gsub('^%-%-%s*', '') or trimmed
            if body:sub(1, 1) == '{' and body:find(needle, 1, true) then
                -- Preserve the indentation of the original line.
                local indent = line:match('^(%s*)') or ''
                -- Preserve any trailing comma so the surrounding table
                -- literal's syntax stays valid.
                local trailing = line:match('}(.-)$') or ''
                if not trailing:find(',', 1, true) and not is_empty_slot(slot) then
                    trailing = ',' .. trailing
                end
                table.insert(lines, indent .. literal .. trailing)
                matched = true
            else
                table.insert(lines, line)
            end
        else
            table.insert(lines, line)
        end
        i = i + 1
    end

    if not matched then
        return nil, 'slot_id "' .. slot.slot_id .. '" not found in file — cannot patch'
    end

    local new_src = table.concat(lines, '\n')
    -- io.lines drops the trailing newline; restore it if the original had one
    if src:sub(-1) == '\n' and new_src:sub(-1) ~= '\n' then
        new_src = new_src .. '\n'
    end

    if new_src == src then
        return { changed = false }
    end

    local ok, bpath = backup(path, src)
    if not ok then
        return nil, 'failed to write backup (' .. tostring(bpath) .. ')'
    end

    local wrote, werr = write_file(path, new_src)
    if not wrote then return nil, werr end

    return { changed = true, backup = bpath }
end

return writer
