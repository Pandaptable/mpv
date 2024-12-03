---@diagnostic disable: duplicate-set-field
local function print(s)
	mp.msg.info(s)
	mp.osd_message(s)
end

-- Key config
KEY_CUT = "\\"
KEY_CANCEL_CUT = "|"
KEY_CYCLE_ACTION = "a"
KEY_BOOKMARK_ADD = "i"

-- The default action
ACTION = "ENCODE"

-- Delete a default action
ACTIONS.LIST = nil

ACTIONS.COPY = function(d)
	local args = {
		"ffmpeg",
		"-nostdin", "-y",
		"-loglevel", "error",
		"-ss", d.start_time,
		"-t", d.duration,
		"-i", d.inpath,
		"-c", "copy",
		"-map", "0",
		"-dn",
		"-avoid_negative_ts", "make_zero",
		utils.join_path(d.indir, "COPY_" .. d.infile_noext .. d.ext)
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function() print("Done") end)
end

-- ACTIONS.ENCODE = function(d)
-- 	local args = {
-- 		"ffmpeg",
-- 		"-hwaccel", "cuda",
-- 		"-nostdin", "-y",
-- 		"-loglevel", "error",
-- 		"-ss", d.start_time,
-- 		"-t", d.duration,
-- 		"-i", d.inpath,
-- 		"-c:v", "h264_nvenc",
-- 		"-pix_fmt", "yuv420p",
-- 		"-preset", "p7",
-- 		"-b:v", "15000K",
-- 		"-maxrate","15000K",
-- 		"-minrate", "15000K",
-- 		"-bufsize", "15000K",
-- 		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. d.ext)
-- 	}
-- 	mp.command_native_async({
-- 		name = "subprocess",
-- 		args = args,
-- 		playback_only = false,
-- 	}, function() print("Done") end)
-- end

ACTIONS.ENCODE = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel", "cuda",
		"-nostdin", "-y",
		"-loglevel", "error",
		"-ss", d.start_time,
		"-t", d.duration,
		"-i", d.inpath,
		"-c:v", "h264_nvenc",
		"-pix_fmt", "yuv420p",
		"-preset", "p7",
		"-rc", "vbr_hq",
		"-qmin", "0",
		"-cq", "25",
		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4")
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function() print("Done") end)
end

ACTIONS.COPY_ENCODE = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel", "cuda",
		"-nostdin", "-y",
		"-loglevel", "error",
		"-ss", d.start_time,
		"-t", d.duration,
		"-i", '"' .. d.inpath .. '"',
		"-c:v", "h264_nvenc",
		"-pix_fmt", "yuv420p",
		"-preset", "p7",
		"-rc", "vbr_hq",
		"-qmin", "0",
		"-cq", "25",
		'"' .. utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".mp4") .. '"'
	}
	local command = table.concat(args, " ")
	if package.config:sub(1,1) == "\\" then
		-- Windows
		os.execute('echo ' .. command .. ' | clip')
	else
		-- Linux/macOS
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end

ACTIONS.ENCODE_AUDIO = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel", "cuda",
		"-nostdin", "-y",
		"-loglevel", "error",
		"-ss", d.start_time,
		"-t", d.duration,
		"-i", d.inpath,
		"-vn",
		"-c:a", "libvorbis",
		utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".ogg")
	}
	mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
	}, function() print("Done") end)
end

ACTIONS.COPY_AUDIO = function(d)
	local args = {
		"ffmpeg",
		"-hwaccel", "cuda",
		"-nostdin", "-y",
		"-loglevel", "error",
		"-ss", d.start_time,
		"-t", d.duration,
		"-i", '"' .. d.inpath .. '"',
		"-vn",
		"-c:a", "libvorbis",
		'"' .. utils.join_path(d.indir, "ENCODE_" .. d.infile_noext .. ".ogg") .. '"'
	}
	local command = table.concat(args, " ")
	if package.config:sub(1,1) == "\\" then
		-- Windows
		os.execute('echo ' .. command .. ' | clip')
	else
		-- Linux/macOS
		os.execute('echo "' .. command .. '" | pbcopy || xclip -selection clipboard')
	end

	print("Command copied:" .. command)
end