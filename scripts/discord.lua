local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")
local opts = require("mp.options")

local function get_temp_path()
	local dir_sep = package.config:match("([^\n]*)\n?")
	local temp_file_path = os.tmpname()

	-- Remove generated temp file
	pcall(os.remove, temp_file_path)

	local sep_idx = temp_file_path:reverse():find(dir_sep)
	return temp_file_path:sub(1, #temp_file_path - sep_idx)
end

local function join_paths(...)
	local path = ""
	for _, v in ipairs({ ... }) do
		path = utils.join_path(path, tostring(v))
	end
	return path
end

-- local tempDir = get_temp_path()
-- local ppid = utils.getpid()

-- Create socket directory
-- os.execute("mkdir " .. join_paths(tempDir, "mpvSockets") .. " 2>/dev/null")
-- mp.set_property("options/input-ipc-server", join_paths(tempDir, "mpvSockets", ppid))

local function shutdown_handler()
	os.remove(join_paths(tempDir, "mpvSockets", ppid))
end
mp.register_event("shutdown", shutdown_handler)

local options = {
	key = "D",
	active = true,
	client_id = "737663962677510245",
	binary_path = "",
	autohide_threshold = 0,
}

opts.read_options(options, "discord")

if options.binary_path == "" then
	msg.fatal("Missing binary path in config file.")
	os.exit(1)
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		io.close(f)
		return true
	end
	return false
end

if not file_exists(options.binary_path) then
	msg.fatal("The specified binary path does not exist.")
	os.exit(1)
end

local tempDir = get_temp_path()
local ppid = utils.getpid()
local socket_path = join_paths(tempDir, "mpvSockets", ppid)

local cmd

local function start()
	if not cmd then
		cmd = mp.command_native_async({
			name = "subprocess",
			playback_only = false,
			args = {
				options.binary_path,
				socket_path,
				options.client_id,
			},
		}, function() end)
		msg.info("Launched subprocess")
		mp.osd_message("Discord Rich Presence: Started")
	end
end

local function stop()
	if cmd then
		mp.abort_async_command(cmd)
		cmd = nil
		msg.info("Aborted subprocess")
		mp.osd_message("Discord Rich Presence: Stopped")
	end
end

if options.active then
	mp.register_event("file-loaded", start)
end

mp.add_key_binding(options.key, "toggle-discord", function()
	if cmd then
		stop()
	else
		start()
	end
end)

mp.register_event("shutdown", function()
	if cmd then
		stop()
	end
end)

if options.autohide_threshold > 0 then
	local timer
	local t = options.autohide_threshold
	mp.observe_property("pause", "bool", function(_, value)
		if value then
			timer = mp.add_timeout(t, function()
				if cmd then
					stop()
				end
			end)
		else
			if timer then
				timer:kill()
				timer = nil
			end
			if options.active and not cmd then
				start()
			end
		end
	end)
end
