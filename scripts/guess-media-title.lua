--[[
Uses [guessit](https://github.com/guessit-io/guessit) to detect media title by filename.
Upon detection, sets `force-media-title` variable.
Useful for getting cleaner screenshot file names.

Script options can be specified in `script-opts/guess-media-title.conf` file.
If `show_detection_message` is set to `yes`, the script is going to show a flash message in OSD with a detected media title.

Requires `guessit` to be installed for a Python interpreter accessible as `python`.
--]]


local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local options = require("mp.options")


local opts = {
    show_detection_message = false,
    show_episode_title = true,
    excludes = {},
    includes = {},
}

options.read_options(opts, "guess-media-title")
local excludes = opts.excludes
local includes = opts.includes


local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end


local function show_flash_message(text)
    local overlay = mp.create_osd_overlay("ass-events")
    overlay.data = "{\\a6\\fs14}" .. text
    overlay:update()

    mp.add_timeout(5, function()
        overlay:remove()
    end)
end


local function build_title(info)
    if info == nil then
        return nil
    elseif info.type == "episode" and info.season ~= nil and type(info.season) == "number" and info.episode ~= nil and type(info.episode) == "number" then
        local episode_spec = string.format("s%02de%02d", info.season, info.episode)
        if opts.show_episode_title and info.episode_title ~= nil and type(info.episode_title) == "string" then
            return string.format("%s (%s — %s)", info.title, episode_spec, info.episode_title)
        end
        return string.format("%s (%s)", info.title, episode_spec)
    else
        return info.title
    end
end


local function on_guessit_completed(success, result, error)
    if not success then
        msg.error("failed to guess media title: " .. error)
        return
    end

    local media_title = build_title(utils.parse_json(trim(result.stdout)))

    if media_title ~= nil then
        mp.set_property_native("force-media-title", media_title)

        if opts.show_detection_message then
            show_flash_message("Detected media title: {\\b1}" .. media_title)
        end
    end
end


local function should_guess()
    local duration = tonumber(mp.get_property('duration'))
    local active_format = mp.get_property('file-format')
    local directory = utils.split_path(mp.get_property('path'))

    if duration < 900 then
        mp.msg.warn('Video is less than 15 minutes\n' ..
                      '=> NOT Setting media title')
        return false
    elseif directory:find('^http') then
        mp.msg.warn('Setting media title is disabled for web streaming')
        return false
    elseif active_format:find('^cue') then
        mp.msg.warn('Setting media title is disabled for cue files')
        return false
    else
        local not_allowed = {'aiff', 'ape', 'flac', 'mp3', 'ogg', 'wav', 'wv', 'tta'}

        for _, file_format in pairs(not_allowed) do
            if file_format == active_format then
                mp.msg.warn('Setting media title is disabled for audio files')
                return false
            end
        end

        for _, exclude in pairs(excludes) do
            local escaped_exclude = exclude:gsub('%W','%%%0')
            local excluded = directory:find(escaped_exclude)

            if excluded then
                mp.msg.warn('This path is excluded from guessing media title')
                return false
            end
        end

        for i, include in ipairs(includes) do
            local escaped_include = include:gsub('%W','%%%0')
            local included = directory:find(escaped_include)

            if included then break
            elseif i == #includes then
                mp.msg.warn('This path is not included for guessing media title')
                return false
            end
        end
    end

    return true
end


local function guess_media_title()
    if not should_guess() then
        return
    end

    mp.command_native_async({
        name = "subprocess",
        capture_stdout = true,
        args = { "python", "-m", "guessit", "--json", mp.get_property_native("filename") }
    }, on_guessit_completed)
end


local function on_file_end()
    mp.set_property_native("force-media-title", "")
end


mp.register_event("start-file", guess_media_title)
mp.register_event("end-file", on_file_end)
