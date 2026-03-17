---@diagnostic disable: duplicate-set-field

local function print(message)
	mp.msg.info(message)
	mp.osd_message(message)
end

local function copy_to_clipboard(message, file_path)
	mp.msg.info(message)
	mp.osd_message(message .. "\n" .. file_path .. " copied to clipboard.")

	-- PowerShell command to copy file paths to the clipboard
	local powershell_command = [[
	Add-Type -AssemblyName System.Windows.Forms;
	$files = [System.Collections.Specialized.StringCollection]::new();
	$files.Add(']] .. file_path:gsub("'", "''") .. [[');
	[System.Windows.Forms.Clipboard]::SetFileDropList($files);
	]]

	mp.commandv("run", "powershell", "-nop", "-c", powershell_command)
end

-- Key config
KEY_CUT = "\\"
KEY_CANCEL_CUT = "|"
KEY_CYCLE_ACTION = "a"
KEY_BOOKMARK_ADD = "i"

-- The default action
ACTION = "ENCODE_h264"

-- Delete a default action
-- ACTIONS.LIST = nil
ACTIONS.ENCODE = nil

ACTIONS.COPY = function(d)
	local output_path = utils.join_path(d.indir, "COPY_" .. d.infile_noext .. ".mp4")


	local args = {
		"ffmpeg",
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
		"-c",
		"copy",
		"-map",
		"0",
		"-dn",
		"-avoid_negative_ts",
		"make_zero",
		utils.join_path(d.indir, "COPY_" .. d.infile_noext .. d.ext),
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function(success, result, error)
		if success then
			local python_args = {
				"uv",
				"run",
				mp.command_native({ "expand-path", "~~/scripts/mpv-cut/clip.py" }),
				d.inpath,
				output_path,
			}

			mp.command_native_async({
				name = "subprocess",
				args = python_args,
				playback_only = false,
			}, function()
				copy_to_clipboard("Done", output_path)
			end)
		else
			mp.msg.error("FFmpeg encoding failed: " .. (error or "unknown error"))
		end
	end)
end

ACTIONS.ENCODE_h265 = function(d)
	local output_path = utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4")


	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
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
		"-c:v",
		"hevc_nvenc",
		"-profile:v",
		"main",
		"-preset",
		"p7",
		"-rc",
		"vbr_hq",
		"-cq",
		"25",
		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4"),
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function(success, result, error)
		if success then
			local python_args = {
				"uv",
				"run",
				mp.command_native({ "expand-path", "~~/scripts/mpv-cut/clip.py" }),
				d.inpath,
				output_path,
			}

			mp.command_native_async({
				name = "subprocess",
				args = python_args,
				playback_only = false,
			}, function()
				copy_to_clipboard("Done", output_path)
			end)
		else
			mp.msg.error("FFmpeg encoding failed: " .. (error or "unknown error"))
		end
	end)
end

ACTIONS.ENCODE_h264 = function(d)
	local output_path = utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4")

	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
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
		"-c:v",
		"h264_nvenc",
		"-profile:v",
		"high",
		"-preset",
		"p7",
		"-rc",
		"vbr_hq",
		"-cq",
		"25",
		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4"),
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function(success, result, error)
		if success then
			local python_args = {
				"uv",
				"run",
				mp.command_native({ "expand-path", "~~/scripts/mpv-cut/clip.py" }),
				d.inpath,
				output_path,
			}

			mp.command_native_async({
				name = "subprocess",
				args = python_args,
				playback_only = false,
			}, function()
				copy_to_clipboard("Done", output_path)
			end)
		else
			mp.msg.error("FFmpeg encoding failed: " .. (error or "unknown error"))
		end
	end)
end

ACTIONS.COPY_ENCODE_h264 = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
		"-nostdin",
		"-y",
		"-loglevel",
		"error",
		"-ss",
		d.start_time,
		"-t",
		d.duration,
		"-i",
		'"' .. d.inpath .. '"',
		"-c:v",
		"h264_nvenc",
		"-profile:v",
		"high",
		"-preset",
		"p7",
		"-rc",
		"vbr_hq",
		"-cq",
		"25",
		'"' .. utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4") .. '"',
	}
	local command = table.concat(args, " ")
	if package.config:sub(1, 1) == "\\" then
		-- Windows
		os.execute("echo " .. command .. " | clip")
	else
		-- Linux/macOS
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end

ACTIONS.COPY_ENCODE_h265 = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
		"-nostdin",
		"-y",
		"-loglevel",
		"error",
		"-ss",
		d.start_time,
		"-t",
		d.duration,
		"-i",
		'"' .. d.inpath .. '"',
		"-c:v",
		"hevc_nvenc",
		"-profile:v",
		"main",
		"-preset",
		"p7",
		"-rc",
		"vbr_hq",
		"-cq",
		"25",
		'"' .. utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4") .. '"',
	}
	local command = table.concat(args, " ")
	if package.config:sub(1, 1) == "\\" then
		-- Windows
		os.execute("echo " .. command .. " | clip")
	else
		-- Linux/macOS
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end

ACTIONS.ENCODE_AUDIO = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
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
		"-vn",
		"-c:a",
		"libvorbis",
		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".ogg"),
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function()
		copy_to_clipboard("Done", utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".ogg"))
	end)
end

ACTIONS.COPY_AUDIO = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel",
		"cuda",
		"-nostdin",
		"-y",
		"-loglevel",
		"error",
		"-ss",
		d.start_time,
		"-t",
		d.duration,
		"-i",
		'"' .. d.inpath .. '"',
		"-vn",
		"-c:a",
		"libvorbis",
		'"' .. utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".ogg") .. '"',
	}
	local command = table.concat(args, " ")
	if package.config:sub(1, 1) == "\\" then
		-- Windows
		os.execute("echo " .. command .. " | clip")
	else
		-- Linux/macOS
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end
