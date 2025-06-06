-- mpv issue 5222
-- Automatically set loop-file=inf for duration <= given length. Default is 5s
-- Use autoloop_duration=n in script-opts/autoloop.conf to set your preferred length
-- Alternatively use script-opts=autoloop-autoloop_duration=n in mpv.conf (takes priority)
-- Also disables the save-position-on-quit for this file, if it qualifies for looping.

local mp = require("mp")
local options = require("mp.options")

local function getOption()
	-- Use recommended way to get options
	local opt = { autoloop_duration = 5 }
	options.read_options(opt)
	autoloop_duration = opt.autoloop_duration
end

local function set_loop()
	local duration = mp.get_property_native("duration")

	-- Checks whether the loop status was changed for the last file
	local was_loop = mp.get_property_native("loop-file")

	-- Cancel operation if there is no file duration
	if not duration then
		return
	end

	-- Loops file if was_loop is false, and file meets requirements
	if not was_loop and duration <= autoloop_duration then
		mp.set_property_native("loop-file", true)
		mp.set_property_bool("file-local-options/save-position-on-quit", false)
		-- Unloops file if was_loop is true, and file does not meet requirements
	elseif was_loop and duration > autoloop_duration then
		mp.set_property_native("loop-file", false)
	end
end

getOption()
mp.register_event("file-loaded", set_loop)
