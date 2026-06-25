---@diagnostic disable: duplicate-set-field

local function print(message)
	mp.msg.info(message)
	mp.osd_message(message)
end

local function copy_to_clipboard(message, file_path)
	mp.msg.info(message)
	mp.osd_message(message .. "\n" .. file_path .. " copied to clipboard.")

	local powershell_command = [[
	Add-Type -AssemblyName System.Windows.Forms;
	$files = [System.Collections.Specialized.StringCollection]::new();
	$files.Add(']] .. file_path:gsub("'", "''") .. [[');
	[System.Windows.Forms.Clipboard]::SetFileDropList($files);
	]]

	mp.commandv("run", "powershell", "-nop", "-c", powershell_command)
end

KEY_CUT = "\\"
KEY_CANCEL_CUT = "|"
KEY_CYCLE_ACTION = "a"
KEY_BOOKMARK_ADD = "i"
KEY_SETTINGS = "Ctrl+\\"

ACTION = "ENCODE"

ENCODE_SETTINGS = {
	video_encoder = "h264_nvenc",
	profile = "high",
	preset = "p7",
	rc = "vbr_hq",
	cq = 25,
	audio_encoder = "aac",
	audio_bitrate = "128k",
	audio_only = false,
	audio_tracks = "all",
	copy_metadata = true,
	filter_timeline = true,
	hwaccel = "cuda",
}

local settings_path = mp.command_native({ "expand-path", "~~/mpv-opts/mpv-cut-settings.json" })

local function save_settings()
	local f = io.open(settings_path, "w")
	if f then
		f:write(utils.format_json(ENCODE_SETTINGS))
		f:close()
	end
end

local function load_settings()
	local f = io.open(settings_path, "r")
	if f then
		local content = f:read("*all")
		f:close()
		local ok, saved = pcall(utils.parse_json, content)
		if ok and type(saved) == "table" then
			for k, v in pairs(saved) do
				ENCODE_SETTINGS[k] = v
			end
		end
	end
end
load_settings()

ACTIONS.ENCODE = nil

local function get_audio_track_count()
	local tracks = mp.get_property_native("track-list", {})
	local n = 0
	for _, t in ipairs(tracks) do
		if t.type == "audio" then
			n = n + 1
		end
	end
	return n
end

local function probe_comment(filepath)
	local result = mp.command_native({
		name = "subprocess",
		args = {
			"ffprobe",
			"-v",
			"error",
			"-show_entries",
			"format_tags=comment",
			"-of",
			"default=noprint_wrappers=1:nokey=1",
			filepath,
		},
		capture_stdout = true,
		playback_only = false,
	})
	if result and result.status == 0 and result.stdout then
		return result.stdout:match("^%s*(.-)%s*$")
	end
	return nil
end

local function filter_timeline_events(comment_json, start_sec, end_sec)
	if not comment_json or comment_json == "" then
		return nil
	end
	local ok, events = pcall(utils.parse_json, comment_json)
	if not ok or type(events) ~= "table" then
		return nil
	end

	local filtered = {}
	for _, evt in ipairs(events) do
		local t = tonumber(evt.t)
		if t and t >= start_sec and t <= end_sec then
			local new_evt = {}
			for k, v in pairs(evt) do
				if k == "t" then
					new_evt[k] = math.floor((t - start_sec) * 1000 + 0.5) / 1000
				else
					new_evt[k] = v
				end
			end
			filtered[#filtered + 1] = new_evt
		end
	end

	if #filtered == 0 then
		return nil
	end
	return filtered
end

local function append_metadata_override(args, d, s)
	if not s.copy_metadata or not s.filter_timeline then
		return
	end
	local comment = probe_comment(d.inpath)
	local filtered = filter_timeline_events(comment, tonumber(d.start_time), tonumber(d.end_time))
	if filtered then
		args[#args + 1] = "-movflags"
		args[#args + 1] = "+use_metadata_tags"
		args[#args + 1] = "-metadata"
		args[#args + 1] = "comment=" .. utils.format_json(filtered)
	end
end

local function is_nvenc(enc)
	return enc:match("nvenc$") ~= nil
end

local function build_encode_args(d, output_path, overrides)
	local s = {}
	for k, v in pairs(ENCODE_SETTINGS) do
		s[k] = v
	end
	if overrides then
		for k, v in pairs(overrides) do
			s[k] = v
		end
	end

	local args = {
		"ffmpeg",
		"-hwaccel",
		s.hwaccel,
		"-nostdin",
		"-y",
		"-loglevel",
		"error",
		"-ss",
		d.start_time,
		"-t",
		d.duration,
		"-i",
		d.inpath,
	}

	if s.copy_metadata then
		args[#args + 1] = "-map_metadata"
		args[#args + 1] = "0"
	end

	append_metadata_override(args, d, s)

	if not s.audio_only then
		args[#args + 1] = "-map"
		args[#args + 1] = "0:v:0"
	else
		args[#args + 1] = "-vn"
	end

	if s.audio_tracks == "all" then
		args[#args + 1] = "-map"
		args[#args + 1] = "0:a"
	elseif type(s.audio_tracks) == "table" then
		for _, idx in ipairs(s.audio_tracks) do
			args[#args + 1] = "-map"
			args[#args + 1] = "0:a:" .. idx
		end
	end

	if not s.audio_only then
		args[#args + 1] = "-c:v"
		args[#args + 1] = s.video_encoder
		args[#args + 1] = "-profile:v"
		args[#args + 1] = s.profile

		if is_nvenc(s.video_encoder) then
			args[#args + 1] = "-preset"
			args[#args + 1] = s.preset
			args[#args + 1] = "-rc"
			args[#args + 1] = s.rc
			args[#args + 1] = "-cq"
			args[#args + 1] = tostring(s.cq)
		else
			args[#args + 1] = "-preset"
			args[#args + 1] = "medium"
			args[#args + 1] = "-crf"
			args[#args + 1] = tostring(s.cq)
			args[#args + 1] = "-pix_fmt"
			args[#args + 1] = "yuv420p"
		end
	end

	args[#args + 1] = "-c:a"
	args[#args + 1] = s.audio_encoder
	if s.audio_encoder ~= "copy" then
		args[#args + 1] = "-b:a"
		args[#args + 1] = s.audio_bitrate
	end

	args[#args + 1] = output_path
	return args
end

local function run_ffmpeg_with_progress(args, duration_sec, on_done)
	local output_dir = utils.split_path(args[#args])
	local progress_file = utils.join_path(output_dir, ".mpv_cut_progress." .. math.random(100000))

	local output_path = args[#args]
	args[#args] = "-progress"
	args[#args + 1] = progress_file
	args[#args + 1] = output_path

	for i, v in ipairs(args) do
		if i > 1 and v == "-loglevel" and args[i + 1] == "error" then
			args[i + 1] = "warning"
			break
		end
	end

	local total_us = duration_sec * 1000000
	local timer = nil
	local done = false

	local function cleanup()
		done = true
		if timer then
			timer:stop()
			timer = nil
		end
		mp.osd_message("")
		pcall(os.remove, progress_file)
	end

	timer = mp.add_periodic_timer(0.5, function()
		if done then
			return
		end
		local f = io.open(progress_file, "r")
		if not f then
			mp.osd_message("mpv-cut  encoding...", 1)
			return
		end
		local content = f:read("*all")
		f:close()

		local elapsed_us = content:match("out_time_ms=(%d+)") or content:match("out_time_us=(%d+)")
		if elapsed_us and total_us > 0 then
			local elapsed = tonumber(elapsed_us)
			local pct = math.min(100, math.floor(elapsed / total_us * 100))
			local speed = content:match("speed=([%d.]+)x")
			local bar_w = 20
			local filled = math.floor(pct / 100 * bar_w)
			local bar = string.rep("#", filled) .. string.rep("-", bar_w - filled)
			local suffix = speed and (" %.1fx"):format(tonumber(speed)) or ""
			mp.osd_message(string.format("mpv-cut  [%s] %3d%%%s", bar, pct, suffix), 1)
		else
			mp.osd_message("mpv-cut  encoding...", 1)
		end
	end)

	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function(success, result, error)
		cleanup()
		if on_done then
			on_done(success, result, error)
		end
	end)
end

local function get_output_ext(s)
	if s.audio_only then
		if s.audio_encoder == "aac" then
			return ".m4a"
		elseif s.audio_encoder == "libopus" then
			return ".opus"
		elseif s.audio_encoder == "libvorbis" then
			return ".ogg"
		else
			return ".mka"
		end
	end
	return ".mp4"
end

local function run_encode_action(d, output_path)
	local args = build_encode_args(d, output_path)
	run_ffmpeg_with_progress(args, tonumber(d.duration), function(success, result, error)
		if success then
			copy_to_clipboard("Done", output_path)
		else
			mp.msg.error("FFmpeg encoding failed: " .. (error or "unknown error"))
		end
	end)
end

ACTIONS.ENCODE = function(d)
	local s = ENCODE_SETTINGS
	local ext = get_output_ext(s)
	local output_path = utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ext)
	run_encode_action(d, output_path)
end

ACTIONS.COPY_ENCODE = function(d)
	local s = ENCODE_SETTINGS
	local ext = get_output_ext(s)
	local output_path = utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ext)

	local args = build_encode_args(d, output_path)
	local shell_args = {}
	for i, v in ipairs(args) do
		if i == 1 then
			shell_args[#shell_args + 1] = v
		elseif v == d.inpath or v == output_path then
			shell_args[#shell_args + 1] = '"' .. v .. '"'
		else
			shell_args[#shell_args + 1] = v
		end
	end

	local command = table.concat(shell_args, " ")
	if package.config:sub(1, 1) == "\\" then
		os.execute("echo " .. command .. " | clip")
	else
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end

ACTIONS.LIST = function(d)
	local inpath = mp.get_property("path")

	-- write traditional .list entry (channel:start:end)
	local list_path = inpath .. ".list"
	local f = io.open(list_path, "a")
	if not f then
		print("Error writing to cut list")
		return
	end
	local filesize = f:seek("end")
	f:write("\n", d.channel, ":", d.start_time, ":", d.end_time)
	local delta = f:seek("end") - filesize
	f:close()

	-- write current encoder settings as ffmpeg output args
	local args_path = inpath .. ".list.args"
	do
		local s = ENCODE_SETTINGS
		local ext = get_output_ext(s)
		local dummy_out = utils.join_path(d.indir, "DUMMY_" .. d.infile_noext .. ext)
		local full_args = build_encode_args(d, dummy_out)

		-- extract output options: everything after -i <inpath> and before output,
		-- skipping per-cut metadata override (doesn't apply to batch make_cuts)
		local out_opts = {}
		local past_input = false
		local skip_next = false
		for i = 1, #full_args - 1 do
			if skip_next then
				skip_next = false
			elseif past_input then
				if full_args[i] == "-movflags" or full_args[i] == "-metadata" then
					skip_next = true
				else
					out_opts[#out_opts + 1] = full_args[i]
				end
			elseif full_args[i] == "-i" then
				past_input = true
				i = i + 1
			end
		end

		local f2 = io.open(args_path, "w")
		if f2 then
			f2:write(table.concat(out_opts, " "), "\n")
			f2:close()
		end
	end

	print(string.format("Δ %d  —  make_cuts %s $(cat %s)", delta, list_path, args_path))
end

local uosc_available = false

local function build_settings_menu()
	local s = ENCODE_SETTINGS

	local menu = {
		type = "mpv_cut_settings",
		title = "mpv-cut Settings",
		keep_open = true,
		callback = { mp.get_script_name(), "mpv-cut-callback" },
		items = {
			{
				title = "Video Encoder",
				hint = s.video_encoder,
				icon = "videocam",
				keep_open = true,
				items = {
					{
						title = "h264_nvenc",
						value = { setting = "video_encoder", value = "h264_nvenc" },
						active = s.video_encoder == "h264_nvenc",
						keep_open = true,
					},
					{
						title = "hevc_nvenc",
						value = { setting = "video_encoder", value = "hevc_nvenc" },
						active = s.video_encoder == "hevc_nvenc",
						keep_open = true,
					},
					{
						title = "av1_nvenc",
						value = { setting = "video_encoder", value = "av1_nvenc" },
						active = s.video_encoder == "av1_nvenc",
						keep_open = true,
					},
					{
						title = "libx264",
						value = { setting = "video_encoder", value = "libx264" },
						active = s.video_encoder == "libx264",
						keep_open = true,
					},
					{
						title = "libx265",
						value = { setting = "video_encoder", value = "libx265" },
						active = s.video_encoder == "libx265",
						keep_open = true,
					},
				},
			},
			{
				title = "Profile",
				hint = s.profile,
				icon = "layers",
				keep_open = true,
				items = {
					{
						title = "high",
						value = { setting = "profile", value = "high" },
						active = s.profile == "high",
						keep_open = true,
					},
					{
						title = "main",
						value = { setting = "profile", value = "main" },
						active = s.profile == "main",
						keep_open = true,
					},
					{
						title = "baseline",
						value = { setting = "profile", value = "baseline" },
						active = s.profile == "baseline",
						keep_open = true,
					},
				},
			},
			{
				title = "Preset",
				hint = s.preset,
				icon = "speed",
				keep_open = true,
				items = {
					{
						title = "p1 (fastest)",
						value = { setting = "preset", value = "p1" },
						active = s.preset == "p1",
						keep_open = true,
					},
					{
						title = "p2",
						value = { setting = "preset", value = "p2" },
						active = s.preset == "p2",
						keep_open = true,
					},
					{
						title = "p3",
						value = { setting = "preset", value = "p3" },
						active = s.preset == "p3",
						keep_open = true,
					},
					{
						title = "p4",
						value = { setting = "preset", value = "p4" },
						active = s.preset == "p4",
						keep_open = true,
					},
					{
						title = "p5",
						value = { setting = "preset", value = "p5" },
						active = s.preset == "p5",
						keep_open = true,
					},
					{
						title = "p6",
						value = { setting = "preset", value = "p6" },
						active = s.preset == "p6",
						keep_open = true,
					},
					{
						title = "p7 (slowest)",
						value = { setting = "preset", value = "p7" },
						active = s.preset == "p7",
						keep_open = true,
					},
				},
			},
			{
				title = "Rate Control",
				hint = s.rc,
				icon = "settings_ethernet",
				keep_open = true,
				items = {
					{
						title = "vbr_hq (VBR high quality)",
						value = { setting = "rc", value = "vbr_hq" },
						active = s.rc == "vbr_hq",
						keep_open = true,
					},
					{
						title = "cbr (constant bitrate)",
						value = { setting = "rc", value = "cbr" },
						active = s.rc == "cbr",
						keep_open = true,
					},
					{
						title = "cbr_hq",
						value = { setting = "rc", value = "cbr_hq" },
						active = s.rc == "cbr_hq",
						keep_open = true,
					},
					{
						title = "cbr_ld_hq",
						value = { setting = "rc", value = "cbr_ld_hq" },
						active = s.rc == "cbr_ld_hq",
						keep_open = true,
					},
				},
			},
			{
				title = "Quality (CQ/CRF)",
				hint = tostring(s.cq),
				icon = "tune",
				keep_open = true,
				items = {
					{
						title = "14 (near lossless)",
						value = { setting = "cq", value = 14 },
						active = s.cq == 14,
						keep_open = true,
					},
					{
						title = "18",
						value = { setting = "cq", value = 18 },
						active = s.cq == 18,
						keep_open = true,
					},
					{
						title = "21",
						value = { setting = "cq", value = 21 },
						active = s.cq == 21,
						keep_open = true,
					},
					{
						title = "23",
						value = { setting = "cq", value = 23 },
						active = s.cq == 23,
						keep_open = true,
					},
					{
						title = "25 (balanced)",
						value = { setting = "cq", value = 25 },
						active = s.cq == 25,
						keep_open = true,
					},
					{
						title = "28",
						value = { setting = "cq", value = 28 },
						active = s.cq == 28,
						keep_open = true,
					},
					{
						title = "32 (low quality)",
						value = { setting = "cq", value = 32 },
						active = s.cq == 32,
						keep_open = true,
					},
				},
			},
			{
				title = "Audio Encoder",
				hint = s.audio_encoder,
				icon = "audiotrack",
				keep_open = true,
				items = {
					{
						title = "aac",
						value = { setting = "audio_encoder", value = "aac" },
						active = s.audio_encoder == "aac",
						keep_open = true,
					},
					{
						title = "libopus",
						value = { setting = "audio_encoder", value = "libopus" },
						active = s.audio_encoder == "libopus",
						keep_open = true,
					},
					{
						title = "libvorbis",
						value = { setting = "audio_encoder", value = "libvorbis" },
						active = s.audio_encoder == "libvorbis",
						keep_open = true,
					},
					{
						title = "copy (no re-encode)",
						value = { setting = "audio_encoder", value = "copy" },
						active = s.audio_encoder == "copy",
						keep_open = true,
					},
				},
			},
			{
				title = "Audio Bitrate",
				hint = s.audio_bitrate,
				icon = "graphic_eq",
				keep_open = true,
				items = {
					{
						title = "96k",
						value = { setting = "audio_bitrate", value = "96k" },
						active = s.audio_bitrate == "96k",
						keep_open = true,
					},
					{
						title = "128k",
						value = { setting = "audio_bitrate", value = "128k" },
						active = s.audio_bitrate == "128k",
						keep_open = true,
					},
					{
						title = "192k",
						value = { setting = "audio_bitrate", value = "192k" },
						active = s.audio_bitrate == "192k",
						keep_open = true,
					},
					{
						title = "256k",
						value = { setting = "audio_bitrate", value = "256k" },
						active = s.audio_bitrate == "256k",
						keep_open = true,
					},
					{
						title = "320k",
						value = { setting = "audio_bitrate", value = "320k" },
						active = s.audio_bitrate == "320k",
						keep_open = true,
					},
				},
			},
			{
				title = "HW Acceleration",
				hint = s.hwaccel,
				icon = "memory",
				keep_open = true,
				items = {
					{
						title = "cuda",
						value = { setting = "hwaccel", value = "cuda" },
						active = s.hwaccel == "cuda",
						keep_open = true,
					},
					{
						title = "none",
						value = { setting = "hwaccel", value = "none" },
						active = s.hwaccel == "none",
						keep_open = true,
					},
					{
						title = "d3d11va",
						value = { setting = "hwaccel", value = "d3d11va" },
						active = s.hwaccel == "d3d11va",
						keep_open = true,
					},
					{
						title = "dxva2",
						value = { setting = "hwaccel", value = "dxva2" },
						active = s.hwaccel == "dxva2",
						keep_open = true,
					},
				},
			},
			{
				title = "Audio Only",
				hint = s.audio_only and "yes" or "no",
				icon = "music_note",
				keep_open = true,
				items = {
					{
						title = "yes (no video)",
						value = { setting = "audio_only", value = true },
						active = s.audio_only,
						keep_open = true,
					},
					{
						title = "no",
						value = { setting = "audio_only", value = false },
						active = not s.audio_only,
						keep_open = true,
					},
				},
			},
			{
				title = "Audio Tracks",
				hint = s.audio_tracks == "all" and "all"
					or (type(s.audio_tracks) == "table" and (#s.audio_tracks > 0 and table.concat(
						(function()
							local d = {}
							for _, v in ipairs(s.audio_tracks) do
								d[#d + 1] = v + 1
							end
							return d
						end)(),
						", "
					) or "none"))
					or tostring(s.audio_tracks),
				icon = "playlist_add",
				keep_open = true,
				items = (function()
					local items = {}
					local max_tracks = math.max(1, math.min(get_audio_track_count(), 8))
					for i = 0, max_tracks - 1 do
						local selected = s.audio_tracks == "all"
							or (
								type(s.audio_tracks) == "table"
								and (function()
									for _, idx in ipairs(s.audio_tracks) do
										if idx == i then
											return true
										end
									end
									return false
								end)()
							)
						items[#items + 1] = {
							title = "Track " .. (i + 1),
							hint = selected and "on" or "off",
							value = { setting = "audio_tracks", toggle = i },
							active = selected,
							keep_open = true,
						}
					end
					return items
				end)(),
			},
			{
				title = "Copy Metadata (comment, etc.)",
				hint = s.copy_metadata and "yes" or "no",
				icon = "description",
				keep_open = true,
				items = {
					{
						title = "yes",
						value = { setting = "copy_metadata", value = true },
						active = s.copy_metadata,
						keep_open = true,
					},
					{
						title = "no",
						value = { setting = "copy_metadata", value = false },
						active = not s.copy_metadata,
						keep_open = true,
					},
				},
			},
			{
				title = "Filter Timeline to Cut Range",
				hint = s.filter_timeline and "yes" or "no",
				icon = "filter_list",
				keep_open = true,
				items = {
					{
						title = "yes (only events in range)",
						value = { setting = "filter_timeline", value = true },
						active = s.filter_timeline,
						keep_open = true,
					},
					{
						title = "no (keep all source events)",
						value = { setting = "filter_timeline", value = false },
						active = not s.filter_timeline,
						keep_open = true,
					},
				},
			},
		},
	}
	return menu
end

local function open_settings_menu()
	if not uosc_available then
		print("uosc not available - settings menu requires uosc")
		return
	end
	local menu = build_settings_menu()
	mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(menu))
end

mp.register_script_message("mpv-cut-callback", function(json)
	local event = utils.parse_json(json)
	if event.type == "activate" and event.value then
		if event.value.setting == "audio_tracks" and event.value.toggle ~= nil then
			local idx = event.value.toggle
			local cur = ENCODE_SETTINGS.audio_tracks
			local max_t = math.max(1, math.min(get_audio_track_count(), 8))
			if cur == "all" then
				local t = {}
				for i = 0, max_t - 1 do
					if i ~= idx then
						t[#t + 1] = i
					end
				end
				ENCODE_SETTINGS.audio_tracks = #t == 0 and "all" or t
			elseif type(cur) == "table" then
				local found = false
				for i, v in ipairs(cur) do
					if v == idx then
						table.remove(cur, i)
						found = true
						break
					end
				end
				if not found then
					cur[#cur + 1] = idx
					table.sort(cur)
				end
				if #cur == 0 then
					ENCODE_SETTINGS.audio_tracks = "all"
				elseif #cur == max_t then
					local all = true
					for i = 0, max_t - 1 do
						if cur[i + 1] ~= i then
							all = false
							break
						end
					end
					if all then
						ENCODE_SETTINGS.audio_tracks = "all"
					end
				end
			end
			save_settings()
			print(
				string.format(
					"mpv-cut: audio_tracks = %s",
					ENCODE_SETTINGS.audio_tracks == "all" and "all" or table.concat(ENCODE_SETTINGS.audio_tracks, ", ")
				)
			)
		elseif event.value.setting then
			ENCODE_SETTINGS[event.value.setting] = event.value.value
			save_settings()
			print(string.format("mpv-cut: %s = %s", event.value.setting, tostring(event.value.value)))
		end

		local menu = build_settings_menu()
		mp.commandv("script-message-to", "uosc", "update-menu", utils.format_json(menu))
	end
end)

mp.register_script_message("uosc-version", function()
	uosc_available = true
end)

mp.add_key_binding(KEY_SETTINGS, "mpv-cut-settings", open_settings_menu)
