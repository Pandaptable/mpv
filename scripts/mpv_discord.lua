local mp = require("mp")
local opts = require("mp.options")
local utils = require("mp.utils")
local ffi = require("ffi")

local options = {
	enabled = false,
	application_id = "1031137720317263873",
	use_local_video_filename = true -- Set to false if you have a script like https://raw.githubusercontent.com/zenwarr/mpv-config/refs/heads/master/scripts/guess-media-title.lua setting the title
}
opts.read_options(options, "mpv_discord")

-- --- --

local is_windows = mp.get_property("platform") == "windows"

ffi.cdef[[
	typedef void* HANDLE;
	HANDLE CreateFileA(const char* lpName, uint32_t dwAccess, uint32_t dwShare, void* lpSec, uint32_t dwDisp, uint32_t dwFlags, HANDLE hTempl);
	int WriteFile(HANDLE hFile, const void* lpBuf, uint32_t nBytes, uint32_t* lpWritten, void* lpOver);
	int CloseHandle(HANDLE hObject);

	struct sockaddr_un {
		uint16_t sun_family;
		char sun_path[108];
	};
	int socket(int domain, int type, int protocol);
	int connect(int sockfd, const struct sockaddr_un *addr, uint32_t addrlen);
	int write(int fd, const void *buf, size_t count);
	int close(int fd);
]]

---@class sockaddr_un : ffi.cdata*
---@field sun_family integer
---@field sun_path   ffi.cdata*

local IPC = {
	handle = nil,

	AF_UNIX = 1,
	SOCK_STREAM = 1,
	INVALID_HANDLE = is_windows and (ffi.cast("HANDLE", -1)) or nil,
	GENERIC_READ_WRITE = 0xC0000000,
	OPEN_EXISTING = 3
}

function IPC:connect()
	if is_windows then
		for i = 0, 9 do
			local pipe_path = "\\\\.\\pipe\\discord-ipc-" .. i
			self.handle = ffi.C.CreateFileA(pipe_path, self.GENERIC_READ_WRITE, 0, nil, self.OPEN_EXISTING, 0, nil)
			if self.handle ~= self.INVALID_HANDLE then return true end
		end
	else
		local prefixes = { os.getenv("XDG_RUNTIME_DIR"), os.getenv("TMPDIR"), os.getenv("TMP"), "/tmp" }
		local paths = { "", "/app/com.discordapp.Discord", "/snap.discord-canary", "/snap.discord" }
		for _, prefix in ipairs(prefixes) do
			if prefix and prefix ~= "" then
				for _, path in ipairs(paths) do
					for i = 0, 9 do
						local socket_path = prefix .. path .. "/discord-ipc-" .. i
						local fd = ffi.C.socket(self.AF_UNIX, self.SOCK_STREAM, 0)
						if fd >= 0 then
							local addr = ffi.new("struct sockaddr_un") --[[@as sockaddr_un]]
							addr.sun_family = self.AF_UNIX
							ffi.copy(addr.sun_path, socket_path)

							if ffi.C.connect(fd, addr, ffi.sizeof(addr)) == 0 then
								self.handle = fd
								return true
							end
							ffi.C.close(fd)
						end
					end
				end
			end
		end
	end
	print("Could not connect to Discord socket")
	self.handle = nil
	return false
end

function IPC:send(op, payload)
	if not self.handle or self.handle == self.INVALID_HANDLE then return false end

	local json = utils.format_json(payload)
	local header = ffi.new("uint32_t[2]", {op, #json})

	if is_windows then
		local written = ffi.new("uint32_t[1]")
		local h_ok = ffi.C.WriteFile(self.handle, header, 8, written, nil)
		local p_ok = ffi.C.WriteFile(self.handle, json, #json, written, nil)
		return h_ok ~= 0 and p_ok ~= 0
	else
		local h_bytes = ffi.C.write(self.handle, header, 8)
		local p_bytes = ffi.C.write(self.handle, json, #json)
		return h_bytes == 8 and p_bytes == #json
	end
end

function IPC:close()
	if not self.handle then return end
	if is_windows then
		ffi.C.CloseHandle(self.handle)
	else
		ffi.C.close(self.handle)
	end
	self.handle = nil
end

local metadata = mp.get_property_native("metadata")
local function getMetadata(key)
	-- get metadata from table case insensitively
	local lowerKey = string.lower(key)
	for k, v in pairs(metadata) do
		if string.lower(tostring(k)) == lowerKey then
			return v
		end
	end
	return nil
end

local function update_presence()
	if not options.enabled then
		IPC:close()
		return
	end

	if not IPC.handle then
		if IPC:connect() then
			IPC:send(0, { v = 1, client_id = options.application_id })
		else
			return
		end
	end

	-- TODO: https://mpv.io/manual/stable/#properties

	local activity = {
		status_display_type = 1, -- state
		flags = 1,
		assets = {},
		timestamps = {}
	}

	local has_video = mp.get_property_native("current-tracks/video") ~= nil
	local has_audio = mp.get_property_native("current-tracks/audio") ~= nil
	local is_image = has_video and mp.get_property_bool("current-tracks/video/image")

	if not has_audio and (not has_video or is_image) then
		return
	end

	if has_video and not is_image then
		-- media is a video
		activity.type = 3 -- watching
		if options.use_local_video_filename then
			activity.state = mp.get_property("filename")
		else
			activity.state = mp.get_property("media-title")
		end
	else
		-- media is a track
		activity.type = 2 -- listening
		activity.state = mp.get_property("media-title")
		if metadata then
			activity.details = getMetadata("artistsort") or getMetadata("artist") or "Unknown Artist"
			activity.assets.large_text = getMetadata("album") or "Unknown Album"

			-- get urls and images from musicbrainz if mbid in metadata
			local albumid = getMetadata("musicbrainz_albumid")
			local artistid = getMetadata("musicbrainz_artistid") or getMetadata("musicbrainz_albumartistid")
			local trackid = getMetadata("musicbrainz_trackid")

			activity.state_url = artistid and ("https://musicbrainz.org/artist/" .. artistid) or nil
			activity.details_url = trackid and ("https://musicbrainz.org/recording/" .. trackid) or nil

			if albumid then
				activity.assets.large_image = string.format("https://coverartarchive.org/release/%s/front", albumid)
				activity.assets.large_url = "https://musicbrainz.org/release/" .. albumid
			end
		end
	end

	local time_pos = mp.get_property_number("time-pos")
	local duration = mp.get_property_number("duration")
	activity.timestamps["start"] = math.floor((os.time() - time_pos) * 1000)
	if duration > 0 then
		activity.timestamps["end"] = math.floor(activity.timestamps["start"] + (duration * 1000))
	end

	if next(activity.assets) == nil then activity.assets = nil end

	local success
	if mp.get_property_native("pause") or not activity["state"] then
		success = IPC:send(1, {
			cmd = "SET_ACTIVITY",
			args = {
				pid = utils.getpid(),
				activity = nil
			},
			nonce = tostring(os.time())
		})
		return
	else
		success = IPC:send(1, {
			cmd = "SET_ACTIVITY",
			args = {
				pid = utils.getpid(),
				activity = activity
			},
			nonce = tostring(os.time())
		})
	end

	if not success then
		print("Connection to Discord lost.")
		IPC:close()
	end
end

mp.register_event("shutdown", function ()
	IPC:close()
end)

mp.register_event("seek", update_presence)
mp.observe_property("metadata", "native", update_presence)
mp.observe_property("pause", "bool", update_presence)
mp.add_periodic_timer(15, update_presence)

mp.add_key_binding('Shift+D', 'discord-toggle', function()
	options.enabled = not options.enabled
	if options.enabled then
		mp.osd_message("Discord RPC enabled")
	else
		mp.osd_message("Discord RPC disabled")
	end
	update_presence()
end)

