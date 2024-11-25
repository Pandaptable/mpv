
--[[

	https://github.com/stax76/mpv-scripts

	This script changes options depending on what type of
	file is played. It uses the file extension to detect
	if the current file is a video, audio or image file.

	The changes happen not on every file load, but only
	when a mode change is detected.

	On mode change 3 things can be done:

	1. Change options
	2. Change key bindings
	3. Send messages

	The configuration is done in code.

]]--


----- start config

-- video mode

function on_video_mode_activate()
	mp.set_property("osd-playing-msg", "${media-title}")       -- in video mode use media-title
	mp.command("script-message osc-visibility auto no_osd")    -- set osc visibility to auto
end

function on_video_mode_deactivate()
end

-- audio mode

function on_audio_mode_activate()
	mp.set_property("osd-playing-msg", "${media-title}")       -- in audio mode use media-title
	mp.command("script-message osc-visibility never no_osd")   -- in audio mode disable the osc
end

function on_audio_mode_deactivate()
end

-- image mode

function on_image_mode_activate()
	mp.set_property("osd-playing-msg", "")                     -- disable osd-playing-msg for images
	mp.set_property("background", "#1A2226")                   -- use dark grey background for images
	mp.command("script-message osc-visibility never no_osd") -- disable osc for images
	mp.set_property("pause", "yes")                       -- pause when opening images
end

function on_image_mode_deactivate()
	mp.set_property("background", "#000000")                   -- use black background for audio and video
end

-- called whenever the file extension changes

function on_type_change(old_ext, new_ext)
	if new_ext == ".gif" then
		mp.set_property("loop-file", "inf")                    -- loop GIF files
	end

	if old_ext == ".gif" then
		mp.set_property("loop-file", "no")                     -- use loop-file=no for anything except GIF
	end
end

-- binding configuration

audio_mode_bindings = {
	{ "Left",   function () mp.command("no-osd seek -10") end,        "repeatable" }, -- make audio mode seek length longer than video mode seek length
	{ "Right",  function () mp.command("no-osd seek  10") end,        "repeatable" }, -- make audio mode seek length longer than video mode seek length
}

image_mode_bindings = {
	{ "UP",         function () mp.command("ignore") end,							"repeatable" }, -- nothing
	{ "DOWN",       function () mp.command("ignore") end,							"repeatable" }, -- nothing
	{ "LEFT",       function()  mp.command("playlist-prev") end,					"repeatable" }, -- show previous image
	{ "alt+SPACE",  function()  mp.command("playlist-prev") end,					"repeatable" }, -- show previous image
	{ "RIGHT",      function () mp.command("playlist-next") end,					"repeatable" }, -- show next image
	{ "SPACE",      function () mp.command("playlist-next") end,					"repeatable" }, -- show next image
	{ "MBTN_RIGHT", function() mp.command("script-binding drag-to-pan") end },
	{ "MBTN_MID", function() mp.command("script-binding drag-to-pan") end },
	{ "MBTN_LEFT",  function() mp.command("script-binding pan-follows-cursor") end },
	{ "MBTN_LEFT_DBL", function() mp.command("ignore") end },
	{ "WHEEL_UP",      function() mp.command("script-message cursor-centric-zoom 0.1") end },
	{ "WHEEL_DOWN",    function() mp.command("script-message cursor-centric-zoom -0.1") end },
	{ "ctrl+DOWN",  function () mp.command("script-message pan-image y -0.1 yes yes") end, "repeatable" },
	{ "ctrl+UP",    function () mp.command("script-message pan-image y +0.1 yes yes") end, "repeatable" },
	{ "ctrl+RIGHT", function () mp.command("script-message pan-image x -0.1 yes yes") end, "repeatable" },
	{ "ctrl+LEFT",  function () mp.command("script-message pan-image x +0.1 yes yes") end, "repeatable" },
	{ "alt+DOWN",   function () mp.command("script-message pan-image y -0.01 yes yes") end, "repeatable" },
	{ "alt+UP",     function () mp.command("script-message pan-image y +0.01 yes yes") end, "repeatable" },
	{ "alt+RIGHT",  function () mp.command("script-message pan-image x -0.01 yes yes") end, "repeatable" },
	{ "alt+LEFT",   function () mp.command("script-message pan-image x +0.01 yes yes") end, "repeatable" },
	{ "ctrl+0",        function() mp.command("no-osd set video-pan-x 0; no-osd set video-pan-y 0; no-osd set video-zoom 0") end },
	{ "+", function () mp.command("add video-zoom 0.5") end, "repeatable" },
	{ "-", function () mp.command("add video-zoom -0.5; script-message reset-pan-if-visible") end, "repeatable" },
	{ "=",             function() mp.command("no-osd set video-zoom 0; script-message reset-pan-if-visible") end },
	{ "e", function () mp.command("script-message equalizer-toggle") end },
	{ "alt+e",         function() mp.command("script-message equalizer-reset") end },
	{ "h", function () mp.command("no-osd vf toggle hflip; show-text \"Horizontal flip\"") end },
	{ "v", function () mp.command("no-osd vf toggle vflip; show-text \"Vertical flip\"") end },
	{ "r", function () mp.command("script-message rotate-video 90; show-text \"Clockwise rotation\"") end },
	{ "R", function () mp.command("script-message rotate-video -90; show-text \"Counter-clockwise rotation\"") end },
	{ "alt+r", function () mp.command("no-osd set video-rotate 0; show-text \"Reset rotation\"") end },
	{ "d", function () mp.command("script-message ruler") end },
	{ "a", function () mp.command("cycle-values scale nearest ewa_lanczossharp") end },
	{ "c", function () mp.command("cycle icc-profile-auto") end },
	{ "A", function () mp.command("cycle-values video-aspect-override \"-1\" \"no\"") end },
	{ "p", function () mp.command("script-message force-print-filename") end },
}

-- extension configuration

image_file_extensions = { ".jpg", ".png", ".bmp", ".gif", ".webp" }
audio_file_extensions = { ".mp3", ".ogg", ".opus", ".flac", ".m4a", ".mka", ".ac3", ".dts", ".dtshd", ".dtshr", ".dtsma", ".eac3", ".mp2", ".mpa", ".thd", ".w64", ".wav", ".aac" }

----- end config


----- string

function ends_with(value, ending)
	return ending == "" or value:sub(-#ending) == ending
end

----- path

function get_file_ext(path)
	if path == nil then return nil end
	local val = path:match("^.+(%.[^%./\\]+)$")
	if val == nil then return nil end
	return val:lower()
end

----- list

function list_contains(list, value)
	for _, v in pairs(list) do
		if v == value then
			return true
		end
	end

	return false
end

----- key bindings

function add_bindings(definition)
	if type(active_bindings) ~= "table" then
		active_bindings = {}
	end

	local script_name = mp.get_script_name()

	for _, bind in ipairs(definition) do
		local name = script_name .. "_key_" .. (#active_bindings + 1)
		active_bindings[#active_bindings + 1] = name
		mp.add_forced_key_binding(bind[1], name, bind[2], bind[3])
	end
end

function remove_bindings()
	if type(active_bindings) == "table" then
		for _, name in ipairs(active_bindings) do
			mp.remove_key_binding(name)
		end
	end
end

----- main

active_mode = "video"
last_type = nil

function enable_video_mode()
	if active_mode == "video" then return end
	active_mode = "video"
	remove_bindings()
	on_video_mode_activate()
end

function enable_audio_mode()
	if active_mode == "audio" then return end
	active_mode = "audio"
	remove_bindings()
	add_bindings(audio_mode_bindings)
	on_audio_mode_activate()
end

function enable_image_mode()
	if active_mode == "image" then return end
	active_mode = "image"
	remove_bindings()
	add_bindings(image_mode_bindings)
	on_image_mode_activate()
end

function disable_video_mode()
	if active_mode ~= "video" then return end
	active_mode = ""
	remove_bindings()
	on_video_mode_deactivate()
end

function disable_image_mode()
	if active_mode ~= "image" then return end
	active_mode = ""
	remove_bindings()
	on_image_mode_deactivate()
end

function disable_audio_mode()
	if active_mode ~= "audio" then return end
	active_mode = ""
	remove_bindings()
	on_audio_mode_deactivate()
end

function on_start_file(event)
	local ext = get_file_ext(mp.get_property("path"))

	if list_contains(image_file_extensions, ext) then
		disable_video_mode()
		disable_audio_mode()
		enable_image_mode()
	elseif list_contains(audio_file_extensions, ext) then
		disable_image_mode()
		disable_video_mode()
		enable_audio_mode()
	else
		disable_audio_mode()
		disable_image_mode()
		enable_video_mode()
	end

	if last_type ~= ext then
		on_type_change(last_type, ext)
		last_type = ext
	end
end

mp.register_event("start-file", on_start_file)
