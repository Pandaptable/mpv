--[[
    A horribly written script to change the audio tracks for `-lavfi-complex='[aid1] [aid2] amix [ao]'` at runtime
    requires mpv-scroll-list: https://github.com/CogentRedTester/mpv-scroll-list

    Open the browser with `N`
    Select tracks with `ENTER`
    Once two tracks are selected select again to undo the audio mix
]]

local mp = require("mp")

package.path = mp.command_native({ "expand-path", "~~/script-modules/?.lua;" }) .. package.path
local list = require("scroll-list")

list.header = "Select multiple audio tracks:\\N------------------------------------------------"

-- updates the list with the current audio tracks
function update_tracks(tracks)
	list.list = {}
	for _, track in ipairs(tracks or mp.get_property_native("track-list")) do
		if track.type == "audio" then
			table.insert(list.list, {
				id = track.id,
				ass = ("{\\c&H%s&}aid%d: [%s] %s"):format(
					track.selected and "33ff66" or "ffffff",
					track.id,
					track.lang,
					track.title or ""
				),
			})
		end
	end
end

mp.observe_property("track-list", "native", function(_, tracks)
	update_tracks(tracks)
end)
mp.observe_property("aid", "number", function()
	update_tracks()
	list:update()
end)

-- selects the tracks when ENTER is used on the list
function select_track()
	local track_1 = mp.get_property_number("aid")
	local track_2 = list.__current.id

	-- disables lavfi if it is already set
	if mp.get_property("lavfi-complex", "") ~= "" then
		mp.set_property("lavfi-complex", "")
		mp.set_property_number("aid", track_2)
	else
		if not track_1 or not track_2 then
			return
		end
		mp.set_property("lavfi-complex", ("[aid%d] [aid%d] amix [ao]"):format(track_1, track_2))
	end

	update_tracks()
	list:update()
end

table.insert(list.keybinds, { "ENTER", "select", select_track })

mp.add_forced_key_binding("Shift+n", "multi-ao-browser", function()
	list:toggle()
end)
