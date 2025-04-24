--New child with start with the current 'aid' and 'audio-device' of the parent
-- non-Windows environments require the use of the 'socat' package
local platform_is_windows = (package.config:sub(1, 1) == "\\")
local options = require("mp.options")
local o = {
	pipe_template = platform_is_windows and "\\\\.\\pipe\\mpvDupedAudio" or "~/mpvDupedAudio", --windows format
	new_child_key = "Ctrl+Shift+a", --Start a new child: 'Ctrl+Shift+a'
	cycle_child_control_key = "Ctrl+Shift+Alt+a", --Cycle child control: 'Ctrl+Shift+Alt+a'
	cycle_child_aid_key = "Ctrl+Alt+a", --Cycle 'aid' of child: 'Ctrl+Alt+a'
	child_increase_volume_key = "Ctrl+Alt+WHEEL_UP", --Change volume of child: 'Ctrl+Alt+wheel'
	child_decrease_volume_key = "Ctrl+Alt+WHEEL_DOWN", --Change volume of child: 'Ctrl+Alt+wheel'
}
options.read_options(o)

local piper = platform_is_windows and " >" or " | socat - "
local mpvexe = "mpv" .. (platform_is_windows and ".com" or "")
local pipeInstance = {}
local control = 0

local function sync(prop, newVal)
	local timestamp = mp.get_property("audio-pts") or mp.get_property("time-pos")
	for k, v in pairs(pipeInstance) do
		if v then
			os.execute("echo no-osd set time-pos " .. timestamp .. piper .. o.pipe_template .. k)
			if prop == "speed" then
				os.execute("echo no-osd set speed " .. newVal .. piper .. o.pipe_template .. k)
			end
			if prop == "pause" then
				os.execute("echo no-osd set pause " .. newVal .. piper .. o.pipe_template .. k)
			end
		end
	end
end

local function cycle_aid()
	os.execute("echo cycle aid" .. piper .. o.pipe_template .. control)
end

local function switchControl()
	local lastInstance = 0
	for k, v in ipairs(pipeInstance) do
		if v then
			lastInstance = k
		end
	end
	if lastInstance == 0 then
		control = 0
		return
	end
	if control >= lastInstance then
		control = 0
	end
	for k, v in ipairs(pipeInstance) do
		if k > control and v then
			control = k
			return
		end
	end
end

local controlling = false
local function quit()
	os.execute("echo quit" .. piper .. o.pipe_template .. control)
	pipeInstance[control] = false
	switchControl()
	print(control)
	if control == 0 then
		print(">>> Removed last child <<<")
		mp.remove_key_binding("quit")
		mp.remove_key_binding("cycle_aid")
		mp.remove_key_binding("volumeUP")
		mp.remove_key_binding("volumeDOWN")
		mp.unobserve_property(cycle_pause)
		mp.unobserve_property(syncSpeed)
		mp.unregister_event(sync)
		controlling = false
	else
		print(">>> Now controlling child: " .. control .. " <<<")
	end
end

local function start_child()
	table.insert(pipeInstance, true)
	control = #pipeInstance
	print(">>> Now controlling child: " .. control .. " <<<")
	mp.commandv("set", "msg-level", mp.get_script_name() .. "=warn")
	if controlling == false then
		mp.register_event("playback-restart", sync)
		mp.add_forced_key_binding("q", "quit", quit)
		mp.add_forced_key_binding(o.cycle_child_aid_key, "cycle_aid", cycle_aid)
		mp.add_forced_key_binding(o.child_increase_volume_key, "volumeUP", function()
			os.execute("echo add volume 5" .. piper .. o.pipe_template .. control)
		end)
		mp.add_forced_key_binding(o.child_decrease_volume_key, "volumeDOWN", function()
			os.execute("echo add volume -5" .. piper .. o.pipe_template .. control)
		end)
		mp.add_timeout(0.25, function()
			mp.observe_property("pause", "string", sync)
			mp.observe_property("speed", "string", sync)
		end)
		controlling = true
	end
	mp.command_native_async({
		name = "subprocess",
		args = {
			mpvexe,
			mp.get_property("path"),
			"--speed=" .. mp.get_property("speed"),
			"--pause=" .. mp.get_property("pause"),
			"--no-video",
			"--no-sub",
			"--osd-level=1",
			"--aid=" .. mp.get_property("aid"),
			"--audio-device=" .. mp.get_property("audio-device"),
			"--input-ipc-server=" .. o.pipe_template .. control,
			"--start=" .. (mp.get_property("audio-pts") or mp.get_property("time-pos")),
		},
		playback_only = false,
	}, function() end)
	mp.add_timeout(0.25, function()
		mp.commandv("set", "msg-level", mp.get_script_name() .. "=status")
	end)
end

mp.add_forced_key_binding(o.cycle_child_control_key, "switchControl", function()
	switchControl()
	if control == 0 then
		print(">>> No active children <<<")
	else
		print(">>> Now controlling child: " .. control .. " <<<")
	end
end)

mp.add_forced_key_binding(o.new_child_key, "start", start_child)

mp.register_event("shutdown", function()
	for k, _ in pairs(pipeInstance) do
		os.execute("echo quit" .. piper .. o.pipe_template .. k)
	end
end)
