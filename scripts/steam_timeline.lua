local utils = require 'mp.utils'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local config_dir = mp.command_native({"expand-path", "~~/"})

local function get_bgra(icon_name)
    local path = config_dir .. "/markers/" .. icon_name .. ".bgra"
    local f = io.open(path, "r")
    if f then
        f:close()
        return path, 32, 32
    end
    return nil
end

local active_markers = {}

local timeline_markers_overlay = mp.create_osd_overlay("ass-events")
timeline_markers_overlay.z = 9998

local tooltip_overlay = mp.create_osd_overlay("ass-events")
tooltip_overlay.z = 9999
local tooltip_bgra_added = {}

local function clear_popout()
    tooltip_overlay:remove()
    for id, _ in pairs(tooltip_bgra_added) do
        mp.command_native_async({"overlay-remove", id}, function() end)
    end
    tooltip_bgra_added = {}
end

local function draw_popout(group, mx, my, ax, bx, dim, dist, ay, size_max, mouse_y)
    local has_text = false
    local max_width = 80
    
    for _, m in ipairs(group) do
        if m.title or m.desc then has_text = true end
        local title_len = m.title and #m.title or 0
        local desc_len = m.desc and #m.desc or 0
        local item_w = math.max(80, title_len * 9, desc_len * 6)
        if m.bgra then item_w = item_w + 40 end
        if item_w > max_width then max_width = item_w end
    end

    if not has_text then
        clear_popout()
        return
    end

    local total_height = 12
    for _, m in ipairs(group) do
        local h = 4
        if m.title then h = h + 20 end
        if m.desc then h = h + 16 end
        if m.bgra and h < 40 then h = 40 end
        total_height = total_height + h
    end
    
    local x = math.floor(mx - max_width / 2)
    if x < ax then x = ax end
    if x + max_width > bx then x = bx - max_width end
    
    local thumb_h = mp.get_property_native("user-data/thumbfast/height") or 115
    local thumbfast_visible = mp.get_property_bool("user-data/thumbfast/visible", false)
    local y
    if thumbfast_visible then
        y = math.floor(ay - thumb_h - total_height - 24)
    else
        y = math.floor(ay - 40 - total_height - 24)
    end
    
    local factor = 1.0 - math.min(dist / 40, 1.0)
    if factor <= 0 then
        clear_popout()
        return
    end
    
    local alpha_fg = string.format("%02X", 255 - math.floor(factor * 255))
    
    local vig_w = max_width + 30
    local vig_x = math.floor(x - 15)
    local base_alpha = math.floor(factor * 70)
    
    local ass = assdraw.ass_new()
    for step = 1, 3 do
        local a = string.format("%02X", 255 - base_alpha)
        local step_y = y - 10 + (total_height / 3) * (step - 1)
        ass:new_event()
        ass:append(string.format("{\\pos(0,0)\\an7\\blur15\\bord0\\1c&H000000&\\1a&H%s&}", a))
        ass:draw_start()
        ass:rect_cw(vig_x, step_y, vig_x + vig_w, y + total_height + 10)
        ass:draw_stop()
    end
    
     local cur_y = y + 8
     local new_tooltip_bgra = {}
     
     for i, m in ipairs(group) do
         local text_x = x + 12
         local h = 4
         if m.title then h = h + 20 end
         if m.desc then h = h + 16 end
         if m.bgra and h < 40 then h = 40 end
         
         if m.bgra and factor > 0.5 then
             local icon_id = 60 + i
             if icon_id > 63 then icon_id = 63 end
             mp.command_native_async({"overlay-add", icon_id, math.floor(x + 10), math.floor(cur_y + (h - 32) / 2), m.bgra, 0, "bgra", 32, 32, 128}, function() end)
             new_tooltip_bgra[icon_id] = true
             text_x = text_x + 40
         end
        
        local align = "\\an7"
        local tx = text_x
        if not m.bgra then
            align = "\\an8"
            tx = x + max_width / 2
        end

        if m.title then
            ass:new_event()
            ass:append(string.format("{\\pos(%d,%d)%s\\fs16\\b1\\1c&HFFFFFF&\\1a&H%s&}%s", tx, cur_y, align, alpha_fg, m.title))
        end
        if m.desc then
            ass:new_event()
            ass:append(string.format("{\\pos(%d,%d)%s\\fs13\\b0\\1c&HAAAAAA&\\1a&H%s&}%s", tx, m.title and (cur_y + 20) or cur_y, align, alpha_fg, m.desc))
        end
        
        cur_y = cur_y + h
    end
    
    for id, _ in pairs(tooltip_bgra_added) do
        if not new_tooltip_bgra[id] then
            mp.command_native_async({"overlay-remove", id}, function() end)
        end
    end
    tooltip_bgra_added = new_tooltip_bgra
    
    tooltip_overlay.res_x = dim.w
    tooltip_overlay.res_y = dim.h
    tooltip_overlay.data = ass.text
    tooltip_overlay:update()
end


local is_visible = false
local overlays_added = {}
local last_hovered_marker = nil

local click_bound = false
local target_seek_time = nil

local function on_click()
    if target_seek_time then
        mp.commandv("seek", target_seek_time, "absolute")
    end
end

local function update_visibility()
    local pause = mp.get_property_native("pause")
    local idle = mp.get_property_native("idle-active")
    local mouse = mp.get_property_native("mouse-pos") or {x=0, y=0}
    local dim = mp.get_property_native("osd-dimensions")
    local dur = mp.get_property_native("duration")
    
    if not dim or not dur or dur <= 0 then
        if is_visible then
            for id, _ in pairs(overlays_added) do
                mp.command_native_async({"overlay-remove", id}, function() end)
            end
            overlays_added = {}
            is_visible = false
            clear_popout()
            timeline_markers_overlay:remove()
        end
        return
    end
    
    local bw = mp.get_property_number("script-opts/uosc-border_width", 0)
    local size_max = mp.get_property_number("script-opts/uosc-timeline_size_max", 40)
    local ay = dim.h - size_max - bw
    local ax = bw
    local bx = dim.w - bw
    
    local proximity_out = 120
    local mouse_near = mouse.y >= (ay - proximity_out)
    local should_be_visible = pause or idle or mouse_near
    
    if should_be_visible then
        is_visible = true
        
        local time_pos = mp.get_property_native("time-pos") or 0
        
        local hovered_group = {}
        local closest_dist = 60
        local avg_mx = 0
        
        local scored = {}
        
        for i, m in ipairs(active_markers) do
            m._has_bgra = false
            
            local mx = ax + (m.time / dur) * (bx - ax)
            local mouse_dist = math.abs(mouse.x - mx)
            local time_dist = math.abs(time_pos - m.time)
            
            local factor = 0
            if mouse.y >= (ay - size_max - 20) and mouse_dist < 40 then
                factor = 1.0 - (mouse_dist / 40)
            end
            if time_dist < 10 then
                local t_factor = 1.0 - (time_dist / 10)
                if t_factor > factor then factor = t_factor end
            end
            
            if m.bgra and factor > 0.1 then
                table.insert(scored, {i = i, score = factor * (m.pri / 100), mx = mx})
            end
            
            if mouse_dist < 15 and mouse.y >= (ay - size_max - 10) then
                table.insert(hovered_group, m)
                avg_mx = avg_mx + mx
                if mouse_dist < closest_dist then closest_dist = mouse_dist end
            end
        end
        
        table.sort(scored, function(a, b) return a.score > b.score end)
        
        local used_ids = {}
        local max_icons = 5
        local base_id = 43
        local bgra_times = {}
        
        for j = 1, math.min(max_icons, #scored) do
            local s = scored[j]
            local m = active_markers[s.i]
            local id = base_id + j - 1
            used_ids[id] = true
            m._has_bgra = true
            bgra_times[#bgra_times + 1] = m.time
            mp.command_native_async({"overlay-add", id, math.floor(s.mx - 16), math.floor(ay - 6 - 32), m.bgra, 0, "bgra", 32, 32, 128}, function() end)
            overlays_added[id] = true
        end
        
        for id = base_id, 59 do
            if not used_ids[id] and overlays_added[id] then
                mp.command_native_async({"overlay-remove", id}, function() end)
                overlays_added[id] = nil
            end
        end
        
        local fallback_ass = assdraw.ass_new()
        local has_fallback = false
        
        for i, m in ipairs(active_markers) do
            if m._has_bgra then
                goto continue_diamond
            end
            do
                local near_bgra = false
                for _, bt in ipairs(bgra_times) do
                    if math.abs(m.time - bt) < 0.3 then
                        near_bgra = true
                        break
                    end
                end
                if near_bgra then
                    goto continue_diamond
                end
            end
            
            local mx = ax + (m.time / dur) * (bx - ax)
            local mouse_dist = math.abs(mouse.x - mx)
            local time_dist = math.abs(time_pos - m.time)
            
            local factor = 0
            if mouse.y >= (ay - size_max - 20) and mouse_dist < 40 then
                factor = 1.0 - (mouse_dist / 40)
            end
            if time_dist < 10 then
                local t_factor = 1.0 - (time_dist / 10)
                if t_factor > factor then factor = t_factor end
            end
            
            local r = 2.5 + (5.5 * factor)
            local d_my = ay - r - 2
            local alpha = string.format("%02X", 255 - math.floor((0.5 + 0.5 * factor) * 255))
            fallback_ass:new_event()
            fallback_ass:append(string.format("{\\pos(0,0)\\an7\\blur0\\bord1\\1c&HFFFFFF&\\3c&H111111&\\1a&H%s&\\3a&H%s&}", alpha, alpha))
            fallback_ass:draw_start()
            fallback_ass:move_to(mx, d_my-r)
            fallback_ass:line_to(mx+r, d_my)
            fallback_ass:line_to(mx, d_my+r)
            fallback_ass:line_to(mx-r, d_my)
            fallback_ass:draw_stop()
            has_fallback = true
            ::continue_diamond::
        end
        
        if has_fallback then
            timeline_markers_overlay.res_x = dim.w
            timeline_markers_overlay.res_y = dim.h
            timeline_markers_overlay.data = fallback_ass.text
            timeline_markers_overlay:update()
        else
            timeline_markers_overlay:remove()
        end
        
        if #hovered_group > 0 then
            target_seek_time = hovered_group[1].time
            avg_mx = avg_mx / #hovered_group
            draw_popout(hovered_group, avg_mx, ay - 1, ax, bx, dim, closest_dist, ay, size_max, mouse.y)
            
            local hovering_icon = false
            if mouse.y >= (ay - 40) and mouse.y <= (ay - 2) and closest_dist <= 20 then
                hovering_icon = true
            end
            
            if hovering_icon and not click_bound then
                mp.add_forced_key_binding("MBTN_LEFT", "steam_timeline_click", on_click)
                click_bound = true
            elseif not hovering_icon and click_bound then
                mp.remove_key_binding("steam_timeline_click")
                click_bound = false
            end
        else
            clear_popout()
            if click_bound then
                mp.remove_key_binding("steam_timeline_click")
                click_bound = false
            end
        end
        last_hovered_marker = hovered_marker
    else
        if is_visible then
            for id, _ in pairs(overlays_added) do
                mp.command_native_async({"overlay-remove", id}, function() end)
            end
            overlays_added = {}
            is_visible = false
            clear_popout()
            timeline_markers_overlay:remove()
            last_hovered_marker = nil
        end
    end
end

local function on_metadata(_, metadata)
    if not metadata then return end
    
    local comment = metadata["comment"] or metadata["Comment"] or metadata["COMMENT"]
    if not comment then
        msg.warn("Steam Timeline script: No comment found in metadata")
        return 
    end

    if type(comment) == "string" and comment:match("^comment=") then
        comment = comment:sub(9)
    end

    local markers = utils.parse_json(comment)
    
    local f = io.open("C:\\Users\\nemmy\\AppData\\Local\\Temp\\steam_metadata.json", "w")
    if f then
        f:write(comment)
        f:close()
    end

    if not markers then
        msg.warn("Steam Timeline script: Failed to parse comment as JSON")
        return 
    end

    active_markers = {}

    for _, marker in ipairs(markers) do
        local m = {
            time = marker.t,
            type = marker.type,
            dur = marker.dur,
            icon_name = marker.icon,
            pri = marker.pri or 0
        }
        
        if marker.type == "instant" then
            m.title = marker.title
            m.desc = marker.desc
        elseif marker.type == "range" then
            m.title = marker.title
            m.desc = marker.desc
            m.dur = marker.dur
        elseif marker.type == "phase_attr" then
            m.title = string.format("%s: %s", marker.group or "", marker.value or "")
        elseif marker.type == "phase_tag" then
            m.title = marker.tagGroup
            m.desc = marker.tagName
            m.icon_name = marker.tagIcon
        elseif marker.type == "tooltip" then
            m.title = marker.text
        elseif marker.type == "phase_start" then
            m.dur = 0
            m.title = "Phase Start"
        elseif marker.type == "phase_end" then
            m.title = "Phase End"
        else
            m.title = marker.title
            m.desc = marker.desc
        end
        
        if marker.icon and marker.icon ~= "" then
            local bgra_path, w, h = get_bgra(marker.icon)
            if bgra_path then
                m.bgra = bgra_path
                m.w = w
                m.h = h
            end
        end
        
        table.insert(active_markers, m)
    end
    table.sort(active_markers, function(a, b) return a.time < b.time end)

    update_visibility()
end

mp.observe_property("metadata", "native", on_metadata)
mp.add_periodic_timer(0.03, update_visibility)
