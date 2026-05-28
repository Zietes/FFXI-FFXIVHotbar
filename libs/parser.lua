--[[
Parser for XIVHotbar2 keybind .lua files.

Reads the simple flat-list format used by aregowe/XIVHotbar2:

    xivhotbar_keybinds_job['Base'] = {
        {'battle 1 1', 'ma', 'Cure', 'stpc', 'Cure1'},
        {'battle 1 2', 'ma', 'Cure II', 'stpc', 'Cure2'},
        --{'battle 1 3', '', '', '', ''},   -- empty slot (commented out)
        ...
    }

Each entry is a 5- or 6-element table:
  [1] slot_id      'battle <hotbar> <slot>'  (1..3, 1..12)
  [2] command      'ma' | 'ja' | 'ws' | 'item' | 'macro' | 'input' | ''
  [3] action       spell / ability / item / raw input
  [4] target       'me' | 't' | 'stpc' | 'stnpc' | 'stal' | 'stpt' | ''
  [5] label        the short text shown on the hotbar icon
  [6] type_hint    optional — 'item', sometimes added for macro lines

Commented-out lines (`--{ ... }`) are recognized so the empty-slot
placeholders the addon expects keep their line ordering.

We do NOT execute the file — purely text parsing. Returns:
    { slots = { [slot_id] = { hotbar, slot, cmd, action, target, label, type_hint, commented, line } },
      raw   = "<entire file text>" }
]]

local parser = {}

-- Greedy quote-aware string-literal grabber. Returns content + new index.
local function read_string(src, i)
    local q = src:sub(i, i)
    if q ~= '"' and q ~= "'" then return nil, i end
    local content = {}
    i = i + 1
    while i <= #src do
        local c = src:sub(i, i)
        if c == '\\' then
            -- preserve the escape as-is; we don't decode \n etc. since
            -- we re-emit the same text on save anyway
            table.insert(content, src:sub(i, i + 1))
            i = i + 2
        elseif c == q then
            return table.concat(content), i + 1
        else
            table.insert(content, c)
            i = i + 1
        end
    end
    return table.concat(content), i
end

-- Parse a single `{ 'a', 'b', 'c', ... }` table literal starting at `start`.
-- Returns list of string fields + index just past the closing brace.
local function parse_table_literal(src, start)
    local i = start
    while i <= #src and src:sub(i, i):match('%s') do i = i + 1 end
    if src:sub(i, i) ~= '{' then return nil, start end
    i = i + 1
    local fields = {}
    while i <= #src do
        while i <= #src and src:sub(i, i):match('[%s,]') do i = i + 1 end
        local c = src:sub(i, i)
        if c == '}' then return fields, i + 1 end
        if c == '"' or c == "'" then
            local val, ni = read_string(src, i)
            table.insert(fields, val or '')
            i = ni
        else
            -- non-string (number, identifier) — slurp until comma/brace
            local start_j = i
            while i <= #src and not src:sub(i, i):match('[,}]') do
                i = i + 1
            end
            table.insert(fields, src:sub(start_j, i - 1):gsub('%s+$', ''))
        end
    end
    return fields, i
end

-- Walk the source line by line, find every `{'battle X Y', ...}` (active
-- or commented-out), and build a slot map.
function parser.parse(src)
    local slots = {}
    local line_num = 0
    for line in src:gmatch('([^\n]*)\n?') do
        line_num = line_num + 1
        -- Lua 5.1 (Windower) has no `continue` and no `goto`, so the
        -- skip-empty-line case is handled by wrapping the body in an
        -- `if line ~= ''` instead of a guard + jump.
        if line ~= '' then
            -- Strip leading whitespace, check for comment prefix
            local stripped = line:gsub('^%s+', '')
            local commented = stripped:sub(1, 2) == '--'
            if commented then stripped = stripped:gsub('^%-%-%s*', '') end

            if stripped:sub(1, 1) == '{' then
                -- Try to parse the table literal
                local fields, _ = parse_table_literal(stripped, 1)
                if fields and #fields >= 1 then
                    local slot_id = fields[1] or ''
                    local hb, sl = slot_id:match('^battle%s+(%d+)%s+(%d+)$')
                    if hb and sl then
                        -- A slot_id can appear more than once: the live entry
                        -- in the main table, plus commented-out duplicates
                        -- elsewhere (a disabled SUB-job block at the bottom of
                        -- the file often re-lists 'battle 2 1'.. as comments).
                        -- Keep the first ACTIVE entry and never let a later
                        -- commented duplicate clobber it — otherwise real
                        -- bindings (e.g. all of hotbar 2) vanish from the grid.
                        local existing = slots[slot_id]
                        if (not existing) or (existing.commented and not commented) then
                            slots[slot_id] = {
                                hotbar    = tonumber(hb),
                                slot      = tonumber(sl),
                                slot_id   = slot_id,
                                cmd       = fields[2] or '',
                                action    = fields[3] or '',
                                target    = fields[4] or '',
                                label     = fields[5] or '',
                                type_hint = fields[6] or '',
                                commented = commented,
                                line      = line_num,
                            }
                        end
                    end
                end
            end
        end
    end
    return { slots = slots, raw = src }
end

function parser.parse_file(path)
    local f, err = io.open(path, 'r')
    if not f then return nil, err end
    local src = f:read('*a')
    f:close()
    return parser.parse(src), src
end

-- Build a 3 × 12 grid keyed by [hotbar][slot] = slot record (or nil).
-- Slots that aren't in the parsed map come back as nil.
function parser.to_grid(parsed)
    local grid = { {}, {}, {} }
    if not parsed or not parsed.slots then return grid end
    for _, s in pairs(parsed.slots) do
        if s.hotbar and s.slot then
            grid[s.hotbar] = grid[s.hotbar] or {}
            grid[s.hotbar][s.slot] = s
        end
    end
    return grid
end

return parser
