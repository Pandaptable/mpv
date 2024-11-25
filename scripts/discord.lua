local utils = require 'mp.utils'

local function get_temp_path()
    local directory_seperator = package.config:match("([^\n]*)\n?")
    local example_temp_file_path = os.tmpname()

    -- remove generated temp file
    pcall(os.remove, example_temp_file_path)

    local seperator_idx = example_temp_file_path:reverse():find(directory_seperator)
    local temp_path_length = #example_temp_file_path - seperator_idx

    return example_temp_file_path:sub(1, temp_path_length)
end

tempDir = get_temp_path()

function join_paths(...)
    local arg={...}
    path = ""
    for i,v in ipairs(arg) do
        path = utils.join_path(path, tostring(v))
    end
    return path;
end

ppid = utils.getpid()
os.execute("mkdir " .. join_paths(tempDir, "mpvSockets") .. " 2>/dev/null")
mp.set_property("options/input-ipc-server", join_paths(tempDir, "mpvSockets", ppid))

function shutdown_handler()
        os.remove(join_paths(tempDir, "mpvSockets", ppid))
end
mp.register_event("shutdown", shutdown_handler)

local msg = require("mp.msg")
local opts = require("mp.options")
local utils = require("mp.utils")

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

function file_exists(path)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

if not file_exists(options.binary_path) then
    msg.fatal("The specified binary path does not exist.")
    os.exit(1)
end

local version = "1.6.1"
msg.info(("mpv-discord v%s by tnychn"):format(version))

local socket_path = join_paths(tempDir, "mpvSockets", ppid)

local cmd = nil

local function start()
    if cmd == nil then
        cmd = mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            args = {
                options.binary_path,
                socket_path,
                options.client_id,
            },
        }, function() end)
        msg.info("launched subprocess")
        mp.osd_message("Discord Rich Presence: Started")
    end
end

function stop()
    mp.abort_async_command(cmd)
    cmd = nil
    msg.info("aborted subprocess")
    mp.osd_message("Discord Rich Presence: Stopped")
end

if options.active then
    mp.register_event("file-loaded", start)
end

mp.add_key_binding(options.key, "toggle-discord", function()
    if cmd ~= nil then
        stop()
    else
        start()
    end
end)

mp.register_event("shutdown", function()
    if cmd ~= nil then
        stop()
    end
end)

if options.autohide_threshold > 0 then
    local timer = nil
    local t = options.autohide_threshold
    mp.observe_property("pause", "bool", function(_, value)
        if value == true then
            timer = mp.add_timeout(t, function()
                if cmd ~= nil then
                    stop()
                end
            end)
        else
            if timer ~= nil then
                timer:kill()
                timer = nil
            end
            if options.active and cmd == nil then
                start()
            end
        end
    end)
end