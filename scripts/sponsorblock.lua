-- sponsorblock.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock

local ON_WINDOWS = package.config:sub(1, 1) ~= "/"

local options = {
    server_address = "https://sponsor.ajay.app",

    python_path = ON_WINDOWS and "python" or "python3",

    -- Categories to fetch
    categories = "sponsor,intro,outro,interaction,selfpromo,filler",

    -- Categories to skip automatically
    skip_categories = "sponsor",

    -- If true, sponsored segments will only be skipped once
    skip_once = true,

    -- Note that sponsored segments may ocasionally be inaccurate if this is turned off
    -- see https://blog.ajay.app/voting-and-pseudo-randomness-or-sponsorblock-or-youtube-sponsorship-segment-blocker
    local_database = true,

    -- Update database on first run, does nothing if local_database is false
    auto_update = true,

    -- How long to wait between local database updates
    -- Format: "X[d,h,m]", leave blank to update on every mpv run
    auto_update_interval = "6h",

    -- User ID used to submit sponsored segments, leave blank for random
    user_id = "",

    -- Name to display on the stats page https://sponsor.ajay.app/stats/ leave blank to keep current name
    display_name = "",

    -- Use sponsor times from server if they're more up to date than our local database
    server_fallback = true,

    -- Create chapters at sponsor boundaries for OSC display and manual skipping
    make_chapters = true,

    -- Minimum duration for sponsors (in seconds), segments under that threshold will be ignored
    min_duration = 1,

    -- Length of the sha256 prefix (3-32) when querying server, 0 to disable
    sha256_length = 4,

    -- Pattern for video id in local files, ignored if blank
    -- Recommended value for base youtube-dl is "-([%w-_]+)%.[mw][kpe][v4b]m?$"
    local_pattern = "%[([%w-_]+)%]%..*$",

    -- Legacy option, use skip_categories instead
    skip = true
}

local mp = require "mp"
mp.options = require "mp.options"
mp.options.read_options(options, "sponsorblock")

local legacy = mp.command_native_async == nil
--[[
if legacy then
    options.local_database = false
end
--]]
options.local_database = false

local utils = require "mp.utils"
local scripts_dir = mp.find_config_file("scripts")

local sponsorblock = utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.py")
local uid_path = utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.txt")
local database_file = options.local_database and utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.db") or
    ""
local youtube_id = nil
local ranges = {}
local init = false
local retrying = false
-- Enabled SponsorBlock categories
-- Cat = true
local categories = {}
local chapter_cache = {}
local update

for category in string.gmatch(options.skip_categories, "([^,]+)") do
    categories[category] = true
end

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

local function t_count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function time_sort(a, b)
    if a.time == b.time then
        return string.match(a.title, "segment end")
    end
    return a.time < b.time
end

local function parse_update_interval()
    local s = options.auto_update_interval
    if s == "" then return 0 end -- Interval Disabled

    local num, mod = s:match "^(%d+)([hdm])$"

    if num == nil or mod == nil then
        mp.osd_message("[sponsorblock] auto_update_interval " .. s .. " is invalid", 5)
        return nil
    end

    local time_table = {
        m = 60,
        h = 60 * 60,
        d = 60 * 60 * 24,
    }

    return num * time_table[mod]
end

local function create_chapter(chapter_title, chapter_time)
    local chapters = mp.get_property_native("chapter-list")
    local duration = mp.get_property_native("duration")
    table.insert(chapters,
        { title = chapter_title, time = (duration == nil or duration > chapter_time) and chapter_time or duration - .001 })
    table.sort(chapters, time_sort)
    mp.set_property_native("chapter-list", chapters)
end

local function process(uuid, t, new_ranges)
    local start_time = tonumber(string.match(t, "[^,]+"))
    local end_time = tonumber(string.sub(string.match(t, ",[^,]+"), 2))
    for o_uuid, o_t in pairs(ranges) do
        if (start_time >= o_t.start_time and start_time <= o_t.end_time) or (o_t.start_time >= start_time and o_t.start_time <= end_time) then
            new_ranges[o_uuid] = o_t
            return
        end
    end
    local category = string.match(t, "[^,]+$")
    if categories[category] and end_time - start_time >= options.min_duration then
        -- mp.msg.info("Got: " .. uuid .. "--" .. t .. "--" .. tostring(new_ranges))
        new_ranges[uuid] = {
            start_time = start_time,
            end_time = end_time,
            category = category,
            skipped = false
        }
    end
    if options.make_chapters and not chapter_cache[uuid] then
        chapter_cache[uuid] = true
        local category_title = (category:gsub("^%l", string.upper):gsub("_", " "))
        create_chapter(category_title .. " segment start (" .. string.sub(uuid, 1, 6) .. ")", start_time)
        create_chapter(category_title .. " segment end (" .. string.sub(uuid, 1, 6) .. ")", end_time)
    end
end

local function getranges(_, exists, db, more)
    if type(exists) == "table" and exists["status"] == "1" then
        if options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        else
            return mp.osd_message("[sponsorblock] database update failed, gave up")
        end
    end
    if db ~= "" and db ~= database_file then db = database_file end
    if exists ~= true and not file_exists(db) then
        if not retrying then
            mp.osd_message("[sponsorblock] database update failed, retrying...")
            retrying = true
        end
        return update()
    end
    if retrying then
        mp.osd_message("[sponsorblock] database update succeeded")
        retrying = false
    end
    local sponsors
    local args = {
        options.python_path,
        sponsorblock,
        "ranges",
        db,
        options.server_address,
        youtube_id,
        options.categories,
        tostring(options.sha256_length)
    }
    if not legacy then
        sponsors = mp.command_native({ name = "subprocess", capture_stdout = true, playback_only = false, args = args })
    else
        sponsors = utils.subprocess({ args = args })
    end
    mp.msg.debug("Got: " .. string.gsub(sponsors.stdout, "[\n\r]", ""))
    if not string.match(sponsors.stdout, "^%s*(.*%S)") then return end
    if string.match(sponsors.stdout, "error") then return getranges(true, true) end
    local new_ranges = {}
    local r_count = 0
    if more then r_count = -1 end
    for t in string.gmatch(sponsors.stdout, "[^:%s]+") do
        local uuid = string.match(t, "([^,]+),[^,]+$")
        if ranges[uuid] then
            new_ranges[uuid] = ranges[uuid]
        else
            process(uuid, t, new_ranges)
        end
        r_count = r_count + 1
    end
    local c_count = t_count(ranges)
    if c_count == 0 or r_count >= c_count then
        ranges = new_ranges
    end
end

local function skip_ads(name, pos)
    if pos == nil then return end
    for _, t in pairs(ranges) do
        if (not options.skip_once or not t.skipped) and t.start_time <= pos and t.end_time > pos then
            mp.osd_message("[sponsorblock] " .. t.category .. " skipped")
            mp.set_property("time-pos", t.end_time)
            t.skipped = true
            return
        end
    end
end

update = function()
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = {
            options.python_path,
            sponsorblock,
            "update",
            database_file,
            options.server_address
        }
    }, getranges)
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function file_loaded(event)
    -- mp.msg.info("File Load: " .. dump(event))
    local initialized = init
    ranges = {}
    chapter_cache = {}
    local video_path = mp.get_property("path", "")
    mp.msg.debug("Path: " .. video_path)
    local video_referer = string.match(mp.get_property("http-header-fields", ""), "Referer:([^,]+)") or ""
    mp.msg.debug("Referer: " .. video_referer)

    local urls = {
        "ytdl://([%w-_]+).*",
        "https?://youtu%.be/([%w-_]+).*",
        "https?://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
        "/watch.*[?&]v=([%w-_]+).*",
        "/embed/([%w-_]+).*"
    }
    youtube_id = nil
    for _, url in ipairs(urls) do
        youtube_id = youtube_id or string.match(video_path, url) or string.match(video_referer, url)
        if youtube_id then break end
    end
    youtube_id = youtube_id or string.match(video_path, options.local_pattern)
    if youtube_id == nil then
        mp.msg.verbose("YouTube ID Not Found")
    end

    if not youtube_id or string.len(youtube_id) < 11 or (options.local_pattern and string.len(youtube_id) ~= 11) then
        return
    end
    youtube_id = string.sub(youtube_id, 1, 11)
    mp.msg.debug("Found YouTube ID: " .. youtube_id)
    init = true
    if not options.local_database then
        getranges(true, true)
    else
        local exists = file_exists(database_file)
        if exists and options.server_fallback then
            getranges(true, true)
            mp.add_timeout(0, function() getranges(true, true, "", true) end)
        elseif exists then
            getranges(true, true)
        elseif options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        end
    end
    if initialized then return end
    if options.skip then
        mp.observe_property("time-pos", "native", skip_ads)
    end
    if options.display_name ~= "" then
        local args = {
            options.python_path,
            sponsorblock,
            "username",
            database_file,
            options.server_address,
            youtube_id,
            "",
            "",
            uid_path,
            options.user_id,
            options.display_name
        }
        if not legacy then
            mp.command_native_async({ name = "subprocess", playback_only = false, args = args }, function() end)
        else
            utils.subprocess_detached({ args = args })
        end
    end
    if not options.local_database or (not options.auto_update and file_exists(database_file)) then return end

    if file_exists(database_file) then
        local db_info = utils.file_info(database_file)
        ---@diagnostic disable-next-line: param-type-mismatch
        local cur_time = os.time(os.date("*t"))
        local upd_interval = parse_update_interval()
        if upd_interval == nil or os.difftime(cur_time, db_info.mtime) < upd_interval then return end
    end

    update()
end

local function file_loop(event)
    -- mp.msg.info("File Loop: " .. dump(event))
    if init then
        local pos = mp.get_property("time-pos")
        -- Sometimes pos can be nil when exiting the video, depending on timing.
        if pos == nil then
            return
        end
        -- mp.msg.info("File Loop: Init")
        -- mp.msg.info("File Loop: " .. pos)
        -- 0.010
        if tonumber(pos) < 0.020 then
            -- mp.msg.info("File Looped!!")
            for u, t in pairs(ranges) do
                -- mp.msg.info("Range: " .. u .. ": " .. dump(t))
                t.skipped = false
            end
        end
    end
end

mp.register_event("file-loaded", file_loaded)
mp.register_event("playback-restart", file_loop)
