--[[
FFXI-FFXIVHotbar — GSUI-styled editor for XIVHotbar2 (aregowe/XIVHotbar2)
keybind files. Click a slot, pick a command/action/target from dropdown,
hit Save. Writes back to data/<Character>/<job>.lua with a .bak backup
and fires `//xivhotbar reload` so the change shows up immediately.

Toggle with H key (chat-aware) or //xh / //ffxihotbar.
]]

_addon.name     = 'FFXI-FFXIVHotbar'
_addon.author   = 'mullerdane85-hash'
_addon.version  = '0.1.0'
_addon.commands = { 'xh', 'ffxihotbar' }

require('chat')
require('strings')
require('tables')

local config  = require('config')
local texts   = require('texts')
local images  = require('images')

local parser   = require('libs/parser')
local writer   = require('libs/writer')
local locator  = require('libs/locator')
local actions  = require('libs/actions')

-- ============================================================================
-- Settings
-- ============================================================================
local defaults = {
    pos     = { x = 260, y = 220 },
    visible = false,
}
local settings = config.load(defaults)
config.save(settings)

-- ============================================================================
-- Visual constants (match GSUI / FFXIJSE look)
-- ============================================================================
local BORDER       = 3
local TITLE_BAR_H  = 28
local PAD          = 8
local SLOT_W       = 78
local SLOT_H       = 40
local SLOT_GAP     = 4
local PANEL_W      = (SLOT_W + SLOT_GAP) * 12 + BORDER * 2 + PAD * 2
local PANEL_H      = (SLOT_H + SLOT_GAP) * 3 + BORDER * 2 + TITLE_BAR_H + PAD * 2 + 80
local FOOTER_H     = 60
local DROPDOWN_W   = 280
local DROPDOWN_ROW = 18
local DROPDOWN_MAX = 18

-- Color tuples are { alpha, red, green, blue }, alpha 0-255 (255 = fully
-- opaque). The body / slot / dropdown / button backgrounds previously sat
-- at 200-240 (78-94% opacity) which let the game world bleed through the
-- panel — the user could see their character right through the editor.
-- Bumped every panel-style fill to 250 so the addon reads as solid
-- against any background. Text and border alphas left alone.
local C_BORDER     = { 220, 70,  130, 200 }
local C_TITLE_BG   = { 250, 30,  60,  120 }
local C_TITLE_TXT  = { 255, 200, 200, 230 }
local C_BODY_BG    = { 250, 15,  15,  35  }
local C_SLOT_EMPTY = { 250, 30,  30,  60  }
local C_SLOT_FILLED= { 250, 40,  90,  140 }
local C_SLOT_SEL   = { 250, 100, 200, 100 }
local C_LABEL_TXT  = { 255, 230, 230, 230 }
local C_CMD_TXT    = { 255, 180, 200, 240 }
local C_DROP_BG    = { 250, 20,  30,  60  }
local C_DROP_ROW_OFF= { 250, 35, 50,  90 }
local C_DROP_ROW_ON = { 250, 70, 130, 180 }
local C_DROP_TXT_OFF= { 255, 200, 200, 220 }
local C_DROP_TXT_ON = { 255, 255, 255, 255 }
local C_BTN_SAVE   = { 250, 50,  150, 60 }
local C_BTN_CANCEL = { 250, 150, 60,  60 }
local C_BTN_TXT    = { 255, 255, 255, 255 }
local C_HINT       = { 255, 180, 180, 200 }
local C_ERROR      = { 255, 240, 140, 140 }

-- ============================================================================
-- State
-- ============================================================================
local ui = {
    el     = {},   -- background / static text elements
    slots  = {},   -- per-slot element refs: { [slot_id] = {bg, name_text, cmd_text} }
    rects  = {},   -- per-element click rects: name => { x, y, w, h, ... }
    drop   = {},   -- dropdown elements when picker is open
}
local state = {
    file_path     = nil,
    file_name     = nil,
    parsed        = nil,        -- result of parser.parse_file()
    grid          = nil,        -- 3 × 12 grid of slot records
    selected_id   = nil,        -- 'battle X Y' of slot being edited
    edit          = nil,        -- working copy of the slot being edited
    picker        = nil,        -- which dropdown is open: 'cmd' | 'action' | 'target'
    picker_scroll = 0,
    picker_filter = '',
    last_error    = nil,
    dragging      = false,
    drag_dx       = 0,
    drag_dy       = 0,
    window_rect   = nil,        -- full panel bounds (for blocking mouse pass-through)
    dropdown_rect = nil,        -- open dropdown bounds
}

-- ============================================================================
-- Element factories
-- ============================================================================
local function make_bg(x, y, w, h, c)
    return images.new({
        color = { alpha = c[1], red = c[2], green = c[3], blue = c[4] },
        pos   = { x = x, y = y },
        size  = { width = w, height = h },
        draggable = false,
    })
end

local function make_text(content, x, y, c, size, bold)
    local t = texts.new({
        text = { size = size or 10, font = 'Consolas',
            alpha = c[1] or 255, red = c[2] or 255, green = c[3] or 255, blue = c[4] or 255,
            stroke = { width = 1, alpha = 180, red = 0, green = 0, blue = 0 } },
        bg    = { alpha = 0 },
        pos   = { x = x, y = y },
        flags = { draggable = false, bold = bold or false },
    })
    t:text(content)
    return t
end

local function show(el)    if el and el.show then el:show() end end
local function destroy(el)
    if not el then return end
    if el.hide    then el:hide()    end
    if el.destroy then el:destroy() end
end

-- ============================================================================
-- Load + parse
-- ============================================================================
local function reload_file()
    state.last_error = nil
    local p = windower.ffxi.get_player()
    if not p or not p.name then
        state.last_error = 'Not logged in.'
        return false
    end
    local found = locator.find_active(p.name, p.main_job or '')
    if not found then
        state.last_error = 'No XIVHotbar2 file for ' .. p.name .. '/' .. (p.main_job or '?')
            .. ' under ' .. locator.data_dir()
        state.file_path, state.file_name, state.parsed, state.grid = nil, nil, nil, nil
        return false
    end
    state.file_path = found.path
    state.file_name = found.filename
    local parsed, raw = parser.parse_file(found.path)
    if not parsed then
        state.last_error = 'Parse error: ' .. tostring(raw)
        return false
    end
    state.parsed = parsed
    state.grid   = parser.to_grid(parsed)
    return true
end

-- ============================================================================
-- Rendering
-- ============================================================================
local function destroy_window()
    -- dropdown
    for _, e in pairs(ui.drop) do destroy(e) end
    ui.drop = {}
    -- slot grids
    for _, group in pairs(ui.slots) do
        destroy(group.bg); destroy(group.name); destroy(group.cmd)
    end
    ui.slots = {}
    -- static elements
    for _, e in pairs(ui.el) do destroy(e) end
    ui.el = {}
    ui.rects = {}
    state.window_rect = nil
    state.dropdown_rect = nil
end

local function build_dropdown()
    -- Tear down any existing dropdown
    for _, e in pairs(ui.drop) do destroy(e) end
    ui.drop = {}
    state.dropdown_rect = nil
    if not state.picker then return end

    local items
    if state.picker == 'cmd' then
        items = {}
        for _, c in ipairs(actions.COMMANDS) do
            table.insert(items, { display = c, value = c })
        end
    elseif state.picker == 'target' then
        items = {}
        for _, t in ipairs(actions.TARGETS) do
            table.insert(items, { display = t, value = t })
        end
    elseif state.picker == 'action' then
        local raw = actions.list_all()
        local filt = (state.picker_filter or ''):lower()
        items = {}
        for _, a in ipairs(raw) do
            if filt == '' or a.action:lower():find(filt, 1, true) then
                table.insert(items, {
                    display = a.category:sub(1, 4) .. '  ' .. a.action,
                    value   = a.action,
                    cmd_hint = a.cmd,
                    target_hint = a.default_target,
                })
            end
        end
    else
        items = {}
    end

    -- Anchor the dropdown directly under the picker button that opened it so
    -- it never draws on top of the edit panel/header (the old fixed offset of
    -- pos.y + 200 landed right on the edit controls). Fall back to that offset
    -- if the button rect isn't available yet.
    local anchor
    if state.picker == 'cmd'        then anchor = ui.rects.btn_pick_cmd
    elseif state.picker == 'action' then anchor = ui.rects.btn_pick_action
    elseif state.picker == 'target' then anchor = ui.rects.btn_pick_target end

    local h = math.min(#items, DROPDOWN_MAX) * DROPDOWN_ROW + 4
    if h < 24 then h = 24 end

    local dx, dy
    if anchor then
        dx = anchor.x
        dy = anchor.y + anchor.h + 2
        -- Flip above the button if the list would run off the bottom edge.
        local screen_h = 0
        if windower.get_windower_settings then
            local wsettings = windower.get_windower_settings()
            screen_h = wsettings and (wsettings.ui_y_res or wsettings.y_res) or 0
        end
        if screen_h > 0 and dy + h > screen_h then
            dy = math.max(0, anchor.y - h - 2)
        end
    else
        dx = settings.pos.x + 30
        dy = settings.pos.y + 200
    end
    state.dropdown_rect = { x = dx, y = dy, w = DROPDOWN_W, h = h }
    ui.drop.bg = make_bg(dx, dy, DROPDOWN_W, h, C_DROP_BG)
    show(ui.drop.bg)

    -- visible window of items (scroll)
    local first = math.floor(state.picker_scroll / DROPDOWN_ROW) + 1
    local last  = math.min(#items, first + DROPDOWN_MAX - 1)
    if #items == 0 then
        ui.drop.empty = make_text('(no matches)', dx + 6, dy + 4, C_HINT, 10)
        show(ui.drop.empty)
        return
    end
    for i = first, last do
        local row_y = dy + 2 + (i - first) * DROPDOWN_ROW
        local cell_bg = make_bg(dx + 2, row_y, DROPDOWN_W - 4, DROPDOWN_ROW - 1, C_DROP_ROW_OFF)
        show(cell_bg)
        local cell_tx = make_text(items[i].display, dx + 6, row_y + 2,
            C_DROP_TXT_OFF, 10, false)
        show(cell_tx)
        ui.drop['bg_' .. i]  = cell_bg
        ui.drop['tx_' .. i]  = cell_tx
        ui.rects['drop_' .. i] = {
            x = dx + 2, y = row_y, w = DROPDOWN_W - 4, h = DROPDOWN_ROW - 1,
            type = 'drop_row', item = items[i],
        }
    end
end

local function build_window()
    destroy_window()
    if not settings.visible then return end

    local x, y = settings.pos.x, settings.pos.y
    local W = PANEL_W
    -- Determine height based on whether edit panel is showing
    local edit_h = (state.selected_id and FOOTER_H + 30) or 0
    local H = PANEL_H + edit_h
    state.window_rect = { x = x, y = y, w = W, h = H }

    -- Border + title
    ui.el.top    = make_bg(x,              y,              W,      BORDER, C_BORDER)
    ui.el.bottom = make_bg(x,              y + H - BORDER, W,      BORDER, C_BORDER)
    ui.el.left   = make_bg(x,              y,              BORDER, H,      C_BORDER)
    ui.el.right  = make_bg(x + W - BORDER, y,              BORDER, H,      C_BORDER)
    for _, k in ipairs({'top','bottom','left','right'}) do show(ui.el[k]) end

    local tb_x = x + BORDER
    local tb_y = y + BORDER
    local tb_w = W - BORDER * 2
    ui.el.title_bg = make_bg(tb_x, tb_y, tb_w, TITLE_BAR_H, C_TITLE_BG)
    show(ui.el.title_bg)
    ui.rects.title = { x = tb_x, y = tb_y, w = tb_w, h = TITLE_BAR_H, type = 'title' }

    local title_text
    if state.file_name then
        local p = windower.ffxi.get_player() or {}
        title_text = ('FFXI-FFXIVHotbar  —  %s  /  %s'):format(p.main_job or '?', state.file_name)
    else
        title_text = 'FFXI-FFXIVHotbar  —  (no file loaded)'
    end
    ui.el.title = make_text(title_text, tb_x + 8, tb_y + 7, C_TITLE_TXT, 11, true)
    show(ui.el.title)

    -- Reload button on the title bar (right side)
    local rl_w, rl_h = 60, 18
    local rl_x = tb_x + tb_w - rl_w - 6
    local rl_y = tb_y + 5
    ui.el.reload_bg = make_bg(rl_x, rl_y, rl_w, rl_h, C_BTN_SAVE)
    show(ui.el.reload_bg)
    ui.el.reload_tx = make_text('Reload', rl_x + 13, rl_y + 2, C_BTN_TXT, 10, true)
    show(ui.el.reload_tx)
    ui.rects.reload = { x = rl_x, y = rl_y, w = rl_w, h = rl_h, type = 'reload' }

    -- Body
    local body_x = tb_x + PAD
    local body_y = tb_y + TITLE_BAR_H + PAD
    local body_w = tb_w - PAD * 2
    local body_h = H - BORDER * 2 - TITLE_BAR_H - PAD * 2 - edit_h
    ui.el.body_bg = make_bg(body_x - PAD/2, body_y - PAD/2, body_w + PAD, body_h + PAD, C_BODY_BG)
    show(ui.el.body_bg)

    -- Error state
    if state.last_error then
        ui.el.err = make_text(state.last_error, body_x, body_y + 4, C_ERROR, 10)
        show(ui.el.err)
        return
    end

    -- 3 × 12 slot grid
    for hb = 1, 3 do
        local hb_label_y = body_y + (hb - 1) * (SLOT_H + SLOT_GAP)
        ui.el['hb_lbl_' .. hb] = make_text('HB ' .. hb,
            body_x - 4, hb_label_y + 14, C_HINT, 9, true)
        show(ui.el['hb_lbl_' .. hb])

        for sl = 1, 12 do
            local sx = body_x + 22 + (sl - 1) * (SLOT_W + SLOT_GAP)
            local sy = hb_label_y
            local slot_id = ('battle %d %d'):format(hb, sl)
            local rec = state.grid and state.grid[hb] and state.grid[hb][sl] or nil
            local empty = (not rec) or rec.commented or
                ((rec.cmd or '') == '' and (rec.action or '') == '')
            local col = empty and C_SLOT_EMPTY or C_SLOT_FILLED
            if state.selected_id == slot_id then col = C_SLOT_SEL end

            local bg = make_bg(sx, sy, SLOT_W, SLOT_H, col)
            show(bg)

            local label = (rec and rec.label ~= '' and rec.label) or
                          (rec and rec.action ~= '' and rec.action:sub(1, 9)) or
                          '—'
            local cmd_tag = rec and rec.cmd ~= '' and rec.cmd or '·'
            local name_tx = make_text(label:sub(1, 11), sx + 4, sy + 4, C_LABEL_TXT, 9, true)
            show(name_tx)
            local cmd_tx = make_text(cmd_tag, sx + 4, sy + SLOT_H - 14, C_CMD_TXT, 8)
            show(cmd_tx)

            ui.slots[slot_id] = { bg = bg, name = name_tx, cmd = cmd_tx }
            ui.rects['slot_' .. slot_id] = {
                x = sx, y = sy, w = SLOT_W, h = SLOT_H,
                type = 'slot', slot_id = slot_id,
            }
        end
    end

    -- Edit panel (only when a slot is selected)
    if state.selected_id and state.edit then
        local ex = body_x
        local ey = body_y + body_h + 4
        local edit_text = ('Editing %s  ·  cmd=[%s]  action=[%s]  target=[%s]  label=[%s]')
            :format(state.selected_id, state.edit.cmd, state.edit.action,
                    state.edit.target, state.edit.label or '')
        ui.el.edit_hdr = make_text(edit_text, ex, ey, C_LABEL_TXT, 10, true)
        show(ui.el.edit_hdr)

        -- Dropdowns + save/cancel buttons
        local btn_y = ey + 22
        local btn_h = 22
        local btn_w = 80
        local btns = {
            { name = 'pick_cmd',    label = 'Cmd ▾',    x = ex,           type = 'pick_cmd'    },
            { name = 'pick_action', label = 'Action ▾', x = ex +  85,     type = 'pick_action' },
            { name = 'pick_target', label = 'Target ▾', x = ex + 230,     type = 'pick_target' },
            { name = 'save',        label = 'Save',     x = ex + 380,     type = 'save'        , color = C_BTN_SAVE },
            { name = 'cancel',      label = 'Cancel',   x = ex + 470,     type = 'cancel'      , color = C_BTN_CANCEL },
            { name = 'clear',       label = 'Clear',    x = ex + 560,     type = 'clear'       , color = C_BTN_CANCEL },
        }
        for _, b in ipairs(btns) do
            local col = b.color or C_DROP_ROW_OFF
            local bg = make_bg(b.x, btn_y, btn_w, btn_h, col)
            show(bg)
            local tx = make_text(b.label, b.x + 6, btn_y + 4, C_BTN_TXT, 10, true)
            show(tx)
            ui.el['btn_bg_' .. b.name] = bg
            ui.el['btn_tx_' .. b.name] = tx
            ui.rects['btn_' .. b.name] = {
                x = b.x, y = btn_y, w = btn_w, h = btn_h, type = b.type,
            }
        end
    end

    -- Dropdown last so it draws on top
    if state.picker then build_dropdown() end
end

-- ============================================================================
-- Show / hide / toggle
-- ============================================================================
local function show_window()
    settings.visible = true
    config.save(settings)
    if not state.parsed then reload_file() end
    build_window()
end
local function hide_window()
    settings.visible = false
    config.save(settings)
    state.selected_id, state.edit, state.picker = nil, nil, nil
    destroy_window()
end
local function toggle_window()
    if settings.visible then hide_window() else show_window() end
end

-- ============================================================================
-- Save the editing slot back to disk
-- ============================================================================
local function save_edit()
    if not state.edit or not state.selected_id or not state.file_path then
        windower.add_to_chat(167, 'FFXI-FFXIVHotbar: nothing to save.')
        return
    end
    local result, err = writer.save(state.file_path, state.edit)
    if not result then
        windower.add_to_chat(167, 'FFXI-FFXIVHotbar: save failed — ' .. tostring(err))
        return
    end
    if result.changed == false then
        windower.add_to_chat(207, 'FFXI-FFXIVHotbar: no change (slot already matches).')
    else
        windower.add_to_chat(207,
            ('FFXI-FFXIVHotbar: saved %s.  .bak at %s'):format(state.selected_id, result.backup or '?'))
        -- Reload XIVHotbar2 in-game so the edit is visible immediately
        windower.send_command('xivhotbar reload')
    end
    -- Re-parse from disk
    reload_file()
    state.selected_id, state.edit, state.picker = nil, nil, nil
    build_window()
end

-- ============================================================================
-- Mouse handling
-- ============================================================================
local function in_rect(x, y, r)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Is the cursor over any part of the editor (panel body or an open dropdown)?
-- Used to swallow ALL mouse events there so clicks/drags don't fall through to
-- the game world and spin the camera or change the target.
local function point_in_window(x, y)
    return in_rect(x, y, state.window_rect) or in_rect(x, y, state.dropdown_rect)
end

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if not settings.visible then return false end
    if blocked then return false end

    local over = point_in_window(x, y)

    -- Window drag via title bar
    if state.dragging then
        if mtype == 0 then
            settings.pos.x = math.max(0, x - state.drag_dx)
            settings.pos.y = math.max(0, y - state.drag_dy)
            build_window()
            return true
        elseif mtype == 2 then
            state.dragging = false
            config.save(settings)
            return true
        end
    end

    if mtype == 1 then       -- left button down
        -- Picker dropdown rows take precedence
        if state.picker then
            for i = 1, DROPDOWN_MAX do
                local r = ui.rects['drop_' .. i]
                if in_rect(x, y, r) then
                    -- Apply pick to the edit copy
                    if state.picker == 'cmd' then
                        state.edit.cmd = r.item.value
                    elseif state.picker == 'target' then
                        state.edit.target = r.item.value
                    elseif state.picker == 'action' then
                        state.edit.action = r.item.value
                        if r.item.cmd_hint    then state.edit.cmd    = r.item.cmd_hint    end
                        if r.item.target_hint then state.edit.target = r.item.target_hint end
                        state.edit.label = r.item.value:sub(1, 8)
                    end
                    state.picker = nil
                    state.picker_scroll = 0
                    build_window()
                    return true
                end
            end
            -- Click outside the dropdown closes it
            state.picker = nil
            build_window()
            return true
        end

        -- Title bar drag
        if in_rect(x, y, ui.rects.title) then
            state.dragging = true
            state.drag_dx = x - settings.pos.x
            state.drag_dy = y - settings.pos.y
            return true
        end

        if in_rect(x, y, ui.rects.reload) then
            reload_file()
            state.selected_id, state.edit = nil, nil
            build_window()
            return true
        end

        -- Edit-panel buttons
        for _, name in ipairs({'pick_cmd','pick_action','pick_target','save','cancel','clear'}) do
            if in_rect(x, y, ui.rects['btn_' .. name]) then
                if name == 'save' then
                    save_edit()
                elseif name == 'cancel' then
                    state.selected_id, state.edit, state.picker = nil, nil, nil
                    build_window()
                elseif name == 'clear' then
                    state.edit.cmd, state.edit.action = '', ''
                    state.edit.target, state.edit.label = '', ''
                    build_window()
                elseif name == 'pick_cmd' then
                    state.picker = 'cmd';   state.picker_scroll = 0; build_window()
                elseif name == 'pick_action' then
                    state.picker = 'action'; state.picker_scroll = 0; build_window()
                elseif name == 'pick_target' then
                    state.picker = 'target'; state.picker_scroll = 0; build_window()
                end
                return true
            end
        end

        -- Slot click — select it and copy into edit
        for k, r in pairs(ui.rects) do
            if r.type == 'slot' and in_rect(x, y, r) then
                state.selected_id = r.slot_id
                local hb, sl = r.slot_id:match('^battle (%d+) (%d+)$')
                hb, sl = tonumber(hb), tonumber(sl)
                local rec = state.grid and state.grid[hb] and state.grid[hb][sl] or nil
                state.edit = {
                    slot_id  = r.slot_id,
                    cmd      = rec and rec.cmd or '',
                    action   = rec and rec.action or '',
                    target   = rec and rec.target or '',
                    label    = rec and rec.label or '',
                    type_hint= rec and rec.type_hint or '',
                }
                state.picker = nil
                build_window()
                return true
            end
        end
    elseif mtype == 10 then  -- scroll wheel
        if state.picker then
            state.picker_scroll = math.max(0, state.picker_scroll - (delta or 0) * DROPDOWN_ROW)
            build_dropdown()
            return true
        end
    end

    -- Swallow every remaining event (move, button up/down, right-click, scroll)
    -- that happens over the panel so it can't reach the game and move the camera.
    return over
end)

-- ============================================================================
-- Keyboard (H key toggle, chat-aware)
-- ============================================================================
local DIK_H = 35
windower.register_event('keyboard', function(dik, pressed, flags, blocked)
    if blocked or not pressed then return false end
    if dik == DIK_H then
        local info = windower.ffxi.get_info()
        if info and not info.chat_open then
            toggle_window()
            return true
        end
    end
    return false
end)

-- ============================================================================
-- Commands
-- ============================================================================
windower.register_event('addon command', function(...)
    local cmd = (...) and (...):lower() or ''
    local args = { select(2, ...) }
    if cmd == '' or cmd == 'toggle' then
        toggle_window()
    elseif cmd == 'show' then
        show_window()
    elseif cmd == 'hide' then
        hide_window()
    elseif cmd == 'reload' then
        reload_file(); build_window()
    elseif cmd == 'where' then
        local p = windower.ffxi.get_player()
        windower.add_to_chat(207, 'FFXI-FFXIVHotbar: data dir = ' .. locator.data_dir())
        if p then
            windower.add_to_chat(207, 'FFXI-FFXIVHotbar: player="' .. (p.name or '?')
                .. '"  main_job="' .. (p.main_job or '?') .. '"')
            for _, c in ipairs(locator.list_candidates(p.name, p.main_job or '')) do
                windower.add_to_chat(160, '  ' .. (c.exists and '✓' or '✗') .. '  ' .. c.path)
            end
        end
    elseif cmd == 'help' or cmd == '?' then
        windower.add_to_chat(207, 'FFXI-FFXIVHotbar commands:')
        windower.add_to_chat(160, '  //xh           — toggle window (also: H key)')
        windower.add_to_chat(160, '  //xh reload    — re-read the keybind file from disk')
        windower.add_to_chat(160, '  //xh where     — show candidate file paths it tries')
    else
        windower.add_to_chat(167, 'FFXI-FFXIVHotbar: unknown command "' .. cmd .. '"')
    end
end)

-- ============================================================================
-- Lifecycle events
-- ============================================================================
windower.register_event('login', function()
    coroutine.schedule(function()
        reload_file()
        if settings.visible then build_window() end
    end, 5)
end)

windower.register_event('job change', function()
    coroutine.schedule(function()
        reload_file()
        state.selected_id, state.edit, state.picker = nil, nil, nil
        if settings.visible then build_window() end
    end, 2)
end)

windower.register_event('load', function()
    coroutine.schedule(function()
        if windower.ffxi.get_info().logged_in then
            reload_file()
            if settings.visible then build_window() end
        end
    end, 3)
end)

windower.register_event('unload', function()
    destroy_window()
end)
