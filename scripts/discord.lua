local utils = require 'mp.utils'
local msg = require("mp.msg")
local opts = require("mp.options")

-- Function to get the temporary path directory
local function get_temp_path()
    local dir_sep = package.config:match("([^\n]*)\n?")
    local temp_file_path = os.tmpname()

    -- Remove generated temp file
    pcall(os.remove, temp_file_path)

    local sep_idx = temp_file_path:reverse():find(dir_sep)
    return temp_file_path:sub(1, #temp_file_path - sep_idx)
end

-- Function to join paths
local function join_paths(...)
    local path = ""
    for _, v in ipairs({...}) do
        path = utils.join_path(path, tostring(v))
    end
    return path
end

-- Initialize temp directory and pid
local tempDir = get_temp_path()
local ppid = utils.getpid()

-- Create socket directory
os.execute("mkdir " .. join_paths(tempDir, "mpvSockets") .. " 2>/dev/null")
mp.set_property("options/input-ipc-server", join_paths(tempDir, "mpvSockets", ppid))

-- Shutdown handler to remove socket on exit
local function shutdown_handler()
    os.remove(join_paths(tempDir, "mpvSockets", ppid))
end
mp.register_event("shutdown", shutdown_handler)

-- Load and read configuration options
local options = {
    key = "D",
    active = true,
    client_id = "737663962677510245",
    binary_path = "",
    autohide_threshold = 0,
}

opts.read_options(options, "discord")

-- Validate binary path configuration
if options.binary_path == "" then
    msg.fatal("Missing binary path in config file.")
    os.exit(1)
end

-- Check if file exists
local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        io.close(f)
        return true
    end
    return false
end

-- Ensure binary file exists
if not file_exists(options.binary_path) then
    msg.fatal("The specified binary path does not exist.")
    os.exit(1)
end

-- Print version info
local version = "1.6.1"
msg.info(("mpv-discord v%s by tnychn"):format(version))

-- Define socket path
local socket_path = join_paths(tempDir, "mpvSockets", ppid)

-- Command to start subprocess
local cmd

-- Start subprocess function
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

-- Stop subprocess function
local function stop()
    if cmd then
        mp.abort_async_command(cmd)
        cmd = nil
        msg.info("Aborted subprocess")
        mp.osd_message("Discord Rich Presence: Stopped")
    end
end

-- Register event to start on file load
if options.active then
    mp.register_event("file-loaded", start)
end

-- Keybinding to toggle Discord
mp.add_key_binding(options.key, "toggle-discord", function()
    if cmd then
        stop()
    else
        start()
    end
end)

-- Register shutdown handler
mp.register_event("shutdown", function()
    if cmd then
        stop()
    end
end)

-- Autohide functionality based on pause status
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
