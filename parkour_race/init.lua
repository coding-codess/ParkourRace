-- Parkour Race Minigame for Minetest
-- Define the mod namespace
local modname = "parkour_race"
local modpath = minetest.get_modpath(modname)

-- Table to store player race data
local player_race_data = {}

-- Get mod storage for persistent data
local storage = minetest.get_mod_storage()

-- Cache for required checkpoints count
local required_checkpoints_count = 0

-- Flag to track if initial scan has been done
local initial_scan_done = false

-- Store positions for start, checkpoints, finish, and spawn
local parkour_positions = {
    start = nil,
    checkpoints = {},
    finish = nil,
    spawn = nil
}

-- Load positions from storage on mod load
local function load_parkour_positions()
    local saved_positions = storage:get_string("parkour_positions")
    if saved_positions ~= "" then
        parkour_positions = minetest.deserialize(saved_positions) or parkour_positions
        minetest.log("action", "[Parkour Race] Loaded parkour positions from storage")
        -- Update checkpoint count after loading
        required_checkpoints_count = #parkour_positions.checkpoints
        minetest.log("action", "[Parkour Race] Set required checkpoints count to " .. required_checkpoints_count .. " from loaded positions")
    end
end

-- Save positions to storage
local function save_parkour_positions()
    storage:set_string("parkour_positions", minetest.serialize(parkour_positions))
    minetest.log("action", "[Parkour Race] Saved parkour positions to storage")
    -- Update checkpoint count after saving
    required_checkpoints_count = #parkour_positions.checkpoints
    minetest.log("action", "[Parkour Race] Updated required checkpoints count to " .. required_checkpoints_count)
end

-- Load positions when mod initializes
load_parkour_positions()

-- Function to count required checkpoints from parkour_positions
local function update_required_checkpoints_count()
    required_checkpoints_count = #parkour_positions.checkpoints
    if required_checkpoints_count > 0 then
        for i, pos in ipairs(parkour_positions.checkpoints) do
            minetest.log("action", "[Parkour Race] Registered required checkpoint " .. i .. " at " .. minetest.pos_to_string(pos))
        end
    else
        minetest.log("warning", "[Parkour Race] No required checkpoints registered in parkour_positions")
    end
    minetest.log("action", "[Parkour Race] Set required checkpoints count to " .. required_checkpoints_count .. " from parkour_positions")
    return required_checkpoints_count
end

-- Function to get the cached required checkpoints count
local function get_required_checkpoints_count()
    return required_checkpoints_count
end

-- Trigger checkpoint scan when the first player joins
minetest.register_on_joinplayer(function(player)
    if not initial_scan_done then
        minetest.after(1, function()
            update_required_checkpoints_count()
            initial_scan_done = true
            minetest.log("action", "[Parkour Race] Initial checkpoint scan triggered by player join: " .. player:get_player_name())
        end)
    end
end)

-- Update checkpoint count when a checkpoint block is placed or removed
minetest.register_on_placenode(function(pos, node)
    if node.name == modname .. ":checkpoint_block" then
        -- Add to parkour_positions if not already present
        local pos_str = minetest.pos_to_string(pos)
        for _, cp_pos in ipairs(parkour_positions.checkpoints) do
            if minetest.pos_to_string(cp_pos) == pos_str then
                return -- Checkpoint already in parkour_positions
            end
        end
        table.insert(parkour_positions.checkpoints, pos)
        save_parkour_positions()
        minetest.log("action", "[Parkour Race] Checkpoint placed manually, added to parkour_positions and updated count to " .. required_checkpoints_count)
    end
end)

minetest.register_on_dignode(function(pos, oldnode)
    if oldnode.name == modname .. ":checkpoint_block" then
        -- Remove from parkour_positions if present
        local pos_str = minetest.pos_to_string(pos)
        for i, cp_pos in ipairs(parkour_positions.checkpoints) do
            if minetest.pos_to_string(cp_pos) == pos_str then
                table.remove(parkour_positions.checkpoints, i)
                save_parkour_positions()
                minetest.log("action", "[Parkour Race] Checkpoint removed manually, updated count to " .. required_checkpoints_count)
                return
            end
        end
    end
end)

-- Function to format time in seconds to MM:SS.mmm
local function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local millis = math.floor((seconds % 1) * 1000)
    return string.format("%02d:%02d.%03d", minutes, secs, millis)
end

-- Function to get a safe teleport position
local function get_safe_teleport_pos(pos)
    if not pos then return nil end
    local safe_pos = vector.new(pos.x, pos.y + 1, pos.z)
    for i = 0, 1 do
        local node = minetest.get_node(safe_pos)
        minetest.log("action", "[Parkour Race] Checking safe pos " .. minetest.pos_to_string(safe_pos) .. ": " .. node.name)
        if not minetest.registered_nodes[node.name].walkable then
            return safe_pos
        end
        safe_pos.y = safe_pos.y + 1
    end
    minetest.log("warning", "[Parkour Race] No safe teleport position found at " .. minetest.pos_to_string(pos))
    return nil
end

-- Function to update the scoreboard with a player's completion time
local function update_scoreboard(player_name, time)
    local scoreboard = storage:get_string("scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    if not scoreboard[player_name] or time < scoreboard[player_name] then
        scoreboard[player_name] = time
        storage:set_string("scoreboard", minetest.serialize(scoreboard))
        minetest.log("action", "[Parkour Race] Updated scoreboard for " .. player_name .. " with time " .. format_time(time))
    end
end

-- Function to get the top 5 scoreboard entries as a formspec table
local function get_scoreboard_formspec()
    local scoreboard = storage:get_string("scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    local sorted_scores = {}
    for name, time in pairs(scoreboard) do
        table.insert(sorted_scores, {name = name, time = time})
    end
    table.sort(sorted_scores, function(a, b) return a.time < b.time end)
    local formspec = {
        "formspec_version[4]",
        "size[6,8]",
        "label[0.5,0.5;Parkour Race Scoreboard]",
        "tablecolumns[text;text]",
        "table[0.5,1;5,6;scoreboard;"
    }
    local rows = {}
    for i, score in ipairs(sorted_scores) do
        if i <= 5 then
            table.insert(rows, minetest.formspec_escape(score.name) .. "," .. format_time(score.time))
        end
    end
    if #rows == 0 then
        table.insert(rows, "-,No scores yet")
    end
    formspec[#formspec + 1] = table.concat(rows, ",") .. "]"
    formspec[#formspec + 1] = "button_exit[0.5,7;5,0.8;exit;Close]"
    return table.concat(formspec)
end

-- Function to create the parkour setup GUI
local function get_setup_formspec(player_name)
    local formspec = {
        "formspec_version[4]",
        "size[8,11]",
        "label[0.5,0.5;Parkour Race Setup]",
        "label[0.5,1;Select positions for parkour elements]",
        "button[0.5,2;7,0.8;set_start;Set Start Position (" .. (parkour_positions.start and minetest.pos_to_string(parkour_positions.start) or "Not set") .. ")]",
        "button[0.5,3;7,0.8;add_checkpoint;Add Checkpoint (" .. #parkour_positions.checkpoints .. " set)]",
        "button[0.5,4;7,0.8;set_finish;Set Finish Position (" .. (parkour_positions.finish and minetest.pos_to_string(parkour_positions.finish) or "Not set") .. ")]",
        "button[0.5,5;7,0.8;set_spawn;Set Spawn Position (" .. (parkour_positions.spawn and minetest.pos_to_string(parkour_positions.spawn) or "Not set") .. ")]",
        "button[0.5,6;7,0.8;clear_checkpoints;Clear All Checkpoints]",
        "button[0.5,7;7,0.8;place_nodes;Place Nodes at Selected Positions]",
        "button_exit[0.5,10;7,0.8;exit;Close]"
    }
    -- Display current checkpoints
    local checkpoint_list = {"label[0.5,8;Current Checkpoints:]"}
    if #parkour_positions.checkpoints > 0 then
        for i, pos in ipairs(parkour_positions.checkpoints) do
            table.insert(checkpoint_list, "label[0.5," .. (8.5 + i * 0.5) .. ";Checkpoint " .. i .. ": " .. minetest.pos_to_string(pos) .. "]")
        end
    else
        table.insert(checkpoint_list, "label[0.5,8.5;No checkpoints set]")
    end
    return table.concat(formspec) .. table.concat(checkpoint_list)
end

-- Handle formspec submission for parkour setup
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "parkour_race:setup" then return end
    local player_name = player:get_player_name()
    if not minetest.check_player_privs(player_name, {server = true}) then
        minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "You need server privileges to use this command."))
        return
    end

    local pos = vector.round(player:get_pos())
    if fields.set_start then
        parkour_positions.start = pos
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Start position set at " .. minetest.pos_to_string(pos)))
        minetest.log("action", "[Parkour Race] " .. player_name .. " set start position at " .. minetest.pos_to_string(pos))
        save_parkour_positions()
        minetest.show_formspec(player_name, "parkour_race:setup", get_setup_formspec(player_name))
    elseif fields.add_checkpoint then
        table.insert(parkour_positions.checkpoints, pos)
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Checkpoint added at " .. minetest.pos_to_string(pos)))
        minetest.log("action", "[Parkour Race] " .. player_name .. " added checkpoint at " .. minetest.pos_to_string(pos))
        save_parkour_positions()
        minetest.show_formspec(player_name, "parkour_race:setup", get_setup_formspec(player_name))
    elseif fields.set_finish then
        parkour_positions.finish = pos
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Finish position set at " .. minetest.pos_to_string(pos)))
        minetest.log("action", "[Parkour Race] " .. player_name .. " set finish position at " .. minetest.pos_to_string(pos))
        save_parkour_positions()
        minetest.show_formspec(player_name, "parkour_race:setup", get_setup_formspec(player_name))
    elseif fields.set_spawn then
        parkour_positions.spawn = pos
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Spawn position set at " .. minetest.pos_to_string(pos)))
        minetest.log("action", "[Parkour Race] " .. player_name .. " set spawn position at " .. minetest.pos_to_string(pos))
        save_parkour_positions()
        minetest.show_formspec(player_name, "parkour_race:setup", get_setup_formspec(player_name))
    elseif fields.clear_checkpoints then
        parkour_positions.checkpoints = {}
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "All checkpoints cleared"))
        minetest.log("action", "[Parkour Race] " .. player_name .. " cleared all checkpoints")
        save_parkour_positions()
        minetest.show_formspec(player_name, "parkour_race:setup", get_setup_formspec(player_name))
    elseif fields.place_nodes then
        if parkour_positions.start then
            minetest.set_node(parkour_positions.start, {name = modname .. ":start_sign"})
            minetest.log("action", "[Parkour Race] Placed start sign at " .. minetest.pos_to_string(parkour_positions.start))
        end
        for i, cp_pos in ipairs(parkour_positions.checkpoints) do
            minetest.set_node(cp_pos, {name = modname .. ":checkpoint_block"})
            minetest.log("action", "[Parkour Race] Placed checkpoint " .. i .. " at " .. minetest.pos_to_string(cp_pos))
        end
        if parkour_positions.finish then
            minetest.set_node(parkour_positions.finish, {name = modname .. ":finish_block"})
            minetest.log("action", "[Parkour Race] Placed finish block at " .. minetest.pos_to_string(parkour_positions.finish))
        end
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Nodes placed at selected positions"))
        update_required_checkpoints_count()
    elseif fields.exit then
        -- Form closed
    end
end)

-- Chat command to open the setup GUI
minetest.register_chatcommand("parkour_setup", {
    description = "Open the Parkour Race setup GUI",
    privs = {server = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, minetest.colorize("#FFA500", "Player not found.")
        end
        minetest.show_formspec(name, "parkour_race:setup", get_setup_formspec(name))
        return true, minetest.colorize("#90ee90", "Parkour setup GUI opened.")
    end
})

-- Function to reset the leaderboard and announce the winner
local function reset_leaderboard()
    local scoreboard = storage:get_string("scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    local winner_name, winner_time = nil, nil
    for name, time in pairs(scoreboard) do
        if not winner_time or time < winner_time then
            winner_name = name
            winner_time = time
        end
    end

    if winner_name and winner_time then
        minetest.chat_send_all(minetest.colorize("#FFA500", "Daily Parkour Race Winner: ") .. minetest.colorize("#FFFFFF", winner_name) .. minetest.colorize("#FFA500", " with time ") .. minetest.colorize("#FFFFFF", format_time(winner_time)) .. minetest.colorize("#FFA500", "!"))
        minetest.log("action", "[Parkour Race] Daily winner: " .. winner_name .. " with time " .. format_time(winner_time))
        local winners = storage:get_string("winners")
        winners = winners ~= "" and minetest.deserialize(winners) or {}
        table.insert(winners, {
            name = winner_name,
            time = winner_time,
            timestamp = os.time()
        })
        storage:set_string("winners", minetest.serialize(winners))
    else
        minetest.chat_send_all(minetest.colorize("#FFA500", "No winner for today's Parkour Race."))
        minetest.log("action", "[Parkour Race] No winner for today")
    end

    storage:set_string("scoreboard", "")
    minetest.log("action", "[Parkour Race] Leaderboard reset")
end

-- Function to check and schedule daily reset at 6 PM UTC
local function schedule_leaderboard_reset()
    local now = os.time()
    local utc = os.date("!*t", now)
    local seconds_until_six_pm = ((18 - utc.hour) % 24) * 3600 - utc.min * 60 - utc.sec
    if utc.hour >= 18 then
        seconds_until_six_pm = seconds_until_six_pm + 24 * 3600
    end
    minetest.after(seconds_until_six_pm, function()
        reset_leaderboard()
        minetest.after(24 * 3600, schedule_leaderboard_reset)
    end)
    minetest.log("action", "[Parkour Race] Scheduled leaderboard reset in " .. seconds_until_six_pm .. " seconds")
end

-- Start the reset scheduler when mod loads
minetest.after(0, schedule_leaderboard_reset)

-- Command to manually reset the leaderboard
minetest.register_chatcommand("reset_leaderboard", {
    description = "Manually reset the parkour race leaderboard",
    privs = {server = true},
    func = function(name, param)
        reset_leaderboard()
        return true, minetest.colorize("#f55f5f", "Leaderboard has been reset.")
    end
})

-- Function to start the race for a player
local function start_race(player, start_pos)
    local player_name = player:get_player_name()
    local pos = player:get_pos()
    minetest.log("action", "[Parkour Race] Attempting to start race for " .. player_name .. " at " .. minetest.pos_to_string(pos))

    player_race_data[player_name] = {
        start_time = os.clock(),
        start_pos = start_pos,
        checkpoints = {},
        checkpoint_seq = 0,
        hud_ids = {},
        last_node_pos = nil
    }

    -- Initialize HUD elements
    local hud1 = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.9 },
        offset = { x = -140, y = -60 },
        text = "Time:",
        number = 0xFFA500,
        alignment = { x = 1, y = 0 },
        scale = { x = 100, y = 100 }
    })

    local hud2 = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.9 },
        offset = { x = -20, y = -60 },
        text = "00:00.000",
        number = 0xFFFFFF,
        alignment = { x = -1, y = 0 },
        scale = { x = 100, y = 100 }
    })

    local hud3 = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.9 },
        offset = { x = 40, y = -60 },
        text = "CP:",
        number = 0xFFA500,
        alignment = { x = -1, y = 0 },
        scale = { x = 100, y = 100 }
    })

    local hud4 = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.9 },
        offset = { x = 70, y = -60 },
        text = "0",
        number = 0xFFFFFF,
        alignment = { x = -1, y = 0 },
        scale = { x = 100, y = 100 }
    })

    player_race_data[player_name].hud_ids = {
        time_label = hud1,
        time_value = hud2,
        cp_label = hud3,
        cp_value = hud4
    }
    minetest.log("action", "[Parkour Race] HUD added for " .. player_name .. " with IDs: time_label=" .. hud1 .. ", time_value=" .. hud2 .. ", cp_label=" .. hud3 .. ", cp_value=" .. hud4)

    local inv = player:get_inventory()
    if not inv:contains_item("main", modname .. ":teleport_stick") then
        inv:add_item("main", modname .. ":teleport_stick")
        minetest.log("action", "[Parkour Race] Gave teleport stick to " .. player_name)
    end
    if not inv:contains_item("main", modname .. ":cancel_stick") then
        inv:add_item("main", modname .. ":cancel_stick")
        minetest.log("action", "[Parkour Race] Gave cancel stick to " .. player_name)
    end

    local required_count = get_required_checkpoints_count()
    minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Parkour race started! Reach all ") .. minetest.colorize("#FFFFFF", required_count) .. minetest.colorize("#FFA500", " checkpoint(s) and the finish block."))
    minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Drop or left-click the teleport stick to reset to last checkpoint. Use cancel stick to end race."))
    minetest.log("action", "[Parkour Race] Race started for " .. player_name .. " at " .. minetest.pos_to_string(pos))
end

-- Function to update the HUD with elapsed time and checkpoint progress
local function update_hud(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time and data.hud_ids then
        local status, err = pcall(function()
            local elapsed = os.clock() - data.start_time
            local req_count = #data.checkpoints
            player:hud_change(data.hud_ids.time_value, "text", format_time(elapsed))
            player:hud_change(data.hud_ids.cp_value, "text", req_count .. "/" .. get_required_checkpoints_count())
        end)
        if not status then
            minetest.log("error", "[Parkour Race] HUD update failed for " .. player_name .. ": " .. err)
        end
    end
end

-- Function to cancel the race and teleport to start
local function cancel_race(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        -- Remove HUD elements
        if data.hud_ids then
            pcall(function()
                for _, hud_id in pairs(data.hud_ids) do
                    player:hud_remove(hud_id)
                end
            end)
        end
        -- Remove teleport and cancel sticks from inventory
        local inv = player:get_inventory()
        inv:remove_item("main", modname .. ":teleport_stick")
        inv:remove_item("main", modname .. ":cancel_stick")
        minetest.log("action", "[Parkour Race] Removed teleport and cancel sticks from " .. player_name .. "'s inventory")
        -- Teleport to start position
        local teleport_pos = get_safe_teleport_pos(data.start_pos)
        if teleport_pos then
            player:set_pos(teleport_pos)
            minetest.chat_send_player(player_name, minetest.colorize("#f55f5f", "Race cancelled. Teleported to start."))
            minetest.log("action", "[Parkour Race] " .. player_name .. " cancelled race and teleported to start at " .. minetest.pos_to_string(teleport_pos))
        else
            minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Failed to find a safe teleport position."))
            minetest.log("warning", "[Parkour Race] No safe teleport position for " .. player_name)
        end
        -- Clear race data
        player_race_data[player_name] = nil
        minetest.log("action", "[Parkour Race] Race data cleared for " .. player_name .. " after cancellation")
    else
        minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "You are not in a race."))
    end
end

-- Function to end the race for a player
local function end_race(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if not data or not data.start_time then
        minetest.log("warning", "[Parkour Race] Cannot end race for " .. player_name .. ": No race data")
        return
    end

    local req_count = #data.checkpoints
    local elapsed = os.clock() - data.start_time
    local time_str = format_time(elapsed)
    minetest.chat_send_all(minetest.colorize("#FFFFFF", player_name) .. minetest.colorize("#f55f5f", " finished the parkour race in ") .. minetest.colorize("#FFFFFF", time_str) .. minetest.colorize("#FFA500", "!"))
    minetest.log("action", "[Parkour Race] " .. player_name .. " finished race in " .. time_str .. " with " .. req_count .. " checkpoints")

    update_scoreboard(player_name, elapsed)

    if data.hud_ids then
        pcall(function()
            for _, hud_id in pairs(data.hud_ids) do
                player:hud_remove(hud_id)
            end
        end)
    end

    local inv = player:get_inventory()
    inv:remove_item("main", modname .. ":teleport_stick")
    inv:remove_item("main", modname .. ":cancel_stick")
    minetest.log("action", "[Parkour Race] Removed teleport and cancel sticks from " .. player_name .. "'s inventory")

    -- Teleport to spawn
    local teleport_pos = parkour_positions.spawn and get_safe_teleport_pos(parkour_positions.spawn) or get_safe_teleport_pos(data.start_pos)
    if teleport_pos then
        player:set_pos(teleport_pos)
        minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Teleported to spawn."))
        minetest.log("action", "[Parkour Race] " .. player_name .. " teleported to spawn at " .. minetest.pos_to_string(teleport_pos) .. " after finishing race")
    else
        minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Failed to find a safe teleport position for spawn."))
        minetest.log("warning", "[Parkour Race] No safe teleport position for spawn for " .. player_name)
    end

    player_race_data[player_name] = nil
end

-- Helper function to get the last checkpoint
local function get_last_checkpoint(data)
    if #data.checkpoints == 0 then
        return nil
    end
    local latest_checkpoint = data.checkpoints[1]
    for _, cp in ipairs(data.checkpoints) do
        if cp.seq > latest_checkpoint.seq then
            latest_checkpoint = cp
        end
    end
    return latest_checkpoint.pos
end

-- Function to teleport player to last checkpoint or start
local function teleport_to_last_checkpoint(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local last_checkpoint = get_last_checkpoint(data)
        local teleport_pos = last_checkpoint and get_safe_teleport_pos(last_checkpoint) or get_safe_teleport_pos(data.start_pos)
        if teleport_pos then
            player:set_pos(teleport_pos)
            local destination = last_checkpoint and "last checkpoint" or "start"
            minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Teleported to ") .. minetest.colorize("#90ee90", destination) .. minetest.colorize("#90ee90", "."))
            minetest.log("action", "[Parkour Race] " .. player_name .. " teleported to " .. destination .. " at " .. minetest.pos_to_string(teleport_pos))
        else
            minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Failed to find a safe teleport position."))
            minetest.log("warning", "[Parkour Race] No safe teleport position for " .. player_name)
        end
    else
        minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "You are not in a race."))
    end
end

-- Register the Start Sign node
minetest.register_node(modname .. ":start_sign", {
    description = "Parkour Race Start Sign",
    tiles = {"default_sign_wall_wood.png^[colorize:#00FF00:128"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    sounds = minetest.global_exists("default") and default.node_sound_wood_defaults() or nil,
})

-- Register the Required Checkpoint Block node
minetest.register_node(modname .. ":checkpoint_block", {
    description = "Parkour Race Checkpoint Block",
    tiles = {"default_stone.png^[colorize:#FFFF00:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Finish Block node
minetest.register_node(modname .. ":finish_block", {
    description = "Parkour Race Finish Block",
    tiles = {"default_stone.png^[colorize:#FF0000:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Scoreboard Sign node
minetest.register_node(modname .. ":scoreboard_sign", {
    description = "Parkour Race Scoreboard Sign",
    tiles = {"default_sign_wall_wood.png^[colorize:#0000FF:128"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    sounds = minetest.global_exists("default") and default.node_sound_wood_defaults() or nil,
    on_rightclick = function(pos, node, player, itemstack, pointed_thing)
        minetest.show_formspec(player:get_player_name(), "parkour_race:scoreboard", get_scoreboard_formspec())
        minetest.log("action", "[Parkour Race] " .. player:get_player_name() .. " opened scoreboard")
    end
})

-- Register the teleport stick item
minetest.register_craftitem(modname .. ":teleport_stick", {
    description = "Teleport Stick\nDrop or left-click to teleport to last checkpoint or start",
    inventory_image = "default_stick.png^[colorize:#FF00FF:128",
    stack_max = 1,
    on_drop = function(itemstack, dropper, pos)
        local player = dropper
        if not player or not player:is_player() then return itemstack end
        teleport_to_last_checkpoint(player)
        return itemstack
    end,
    on_use = function(itemstack, user, pointed_thing)
        local player = user
        if not player or not player:is_player() then return itemstack end
        teleport_to_last_checkpoint(player)
        return itemstack
    end
})

-- Register the cancel stick item
minetest.register_craftitem(modname .. ":cancel_stick", {
    description = "Cancel Stick\nDrop or left-click to cancel the race and return to start",
    inventory_image = "default_stick.png^[colorize:#FF0000:128",
    stack_max = 1,
    on_drop = function(itemstack, dropper, pos)
        local player = dropper
        if not player or not player:is_player() then return itemstack end
        cancel_race(player)
        return itemstack
    end,
    on_use = function(itemstack, user, pointed_thing)
        local player = user
        if not player or not player:is_player() then return itemstack end
        cancel_race(player)
        return itemstack
    end
})

-- Register a chat command to manually teleport to last checkpoint
minetest.register_chatcommand("reset", {
    description = "Teleport to the last checkpoint or start position during a parkour race",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, minetest.colorize("#FFA500", "Player not found.")
        end
        teleport_to_last_checkpoint(player)
        return true
    end
})

-- Global step to check for falls, update HUD, detect checkpoint/finish nodes, and start race
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()
        local data = player_race_data[player_name]
        local pos = player:get_pos()
        local offsets = {-0.5, -1, 0}
        local node_name = "unknown"
        local player_pos = nil
        local node_pos = nil
        for _, offset in ipairs(offsets) do
            player_pos = vector.round({x = pos.x, y = pos.y + offset, z = pos.z})
            local node = minetest.get_node(player_pos)
            node_name = node.name
            if node_name == modname .. ":start_sign" or node_name == modname .. ":checkpoint_block" or
               node_name == modname .. ":finish_block" then
                node_pos = player_pos
                break
            end
        end

        if data and data.start_time then
            update_hud(player)

            if pos.y < 0 then
                local teleport_pos = get_safe_teleport_pos(get_last_checkpoint(data) or data.start_pos)
                if teleport_pos then
                    player:set_pos(teleport_pos)
                    local destination = get_last_checkpoint(data) and "last checkpoint" or "start"
                    minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Fell off! Teleported to ") .. minetest.colorize("#90ee90", destination) .. minetest.colorize("#90ee90", "."))
                    minetest.log("action", "[Parkour Race] " .. player_name .. " fell and teleported to " .. destination .. " at " .. minetest.pos_to_string(teleport_pos))
                else
                    minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Failed to find a safe teleport position."))
                    minetest.log("warning", "[Parkour Race] No safe teleport position for " .. player_name)
                end
            end

            if not data.last_node_pos or not vector.equals(player_pos, data.last_node_pos) then
                if node_name == modname .. ":checkpoint_block" then
                    local is_new_checkpoint = true
                    for _, cp in ipairs(data.checkpoints) do
                        if vector.equals(cp.pos, player_pos) then
                            is_new_checkpoint = false
                            break
                        end
                    end
                    if is_new_checkpoint then
                        data.checkpoint_seq = data.checkpoint_seq + 1
                        table.insert(data.checkpoints, {pos = player_pos, seq = data.checkpoint_seq})
                        local req_count = #data.checkpoints
                        minetest.chat_send_player(player_name, minetest.colorize("#FFFF00", "Checkpoint reached! (") .. minetest.colorize("#FFFFFF", req_count .. "/" .. get_required_checkpoints_count()) .. minetest.colorize("#FFFF00", ")"))
                        minetest.log("action", "[Parkour Race] " .. player_name .. " reached checkpoint at " .. minetest.pos_to_string(player_pos) .. " (seq: " .. data.checkpoint_seq .. ")")
                    end
                elseif node_name == modname .. ":finish_block" then
                    local req_count = #data.checkpoints
                    local required_count = get_required_checkpoints_count()
                    if required_count > 0 and req_count < required_count then
                        minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "You must reach all ") .. minetest.colorize("#FFFFFF", required_count) .. minetest.colorize("#FFA500", " checkpoint(s) first! (") .. minetest.colorize("#FFFFFF", req_count .. "/" .. required_count) .. minetest.colorize("#FFA500", " reached)"))
                        minetest.log("action", "[Parkour Race] " .. player_name .. " tried to finish with only " .. req_count .. "/" .. required_count .. " checkpoints")
                    else
                        minetest.log("action", "[Parkour Race] Finish block detected for " .. player_name .. " with " .. req_count .. " checkpoints")
                        end_race(player)
                    end
                end
                data.last_node_pos = player_pos
            end
        else
            if node_name == modname .. ":start_sign" then
                if not data or not data.on_start_node then
                    player_race_data[player_name] = {
                        on_start_node = true,
                        start_pos = node_pos,
                        last_node_pos = player_pos
                    }
                    minetest.chat_send_player(player_name, minetest.colorize("#90ee90", "Move away from the ") .. minetest.colorize("#90ee90", "start") .. minetest.colorize("#90ee90", " to begin the race!"))
                    minetest.log("action", "[Parkour Race] " .. player_name .. " on start node at " .. minetest.pos_to_string(node_pos))
                end
            elseif data and data.on_start_node then
                local start_pos = data.start_pos
                player_race_data[player_name] = nil
                minetest.log("action", "[Parkour Race] " .. player_name .. " moved off start node, starting race")
                start_race(player, start_pos)
            end
        end
    end
end)

-- Handle player respawn
minetest.register_on_respawnplayer(function(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local respawn_pos = get_safe_teleport_pos(get_last_checkpoint(data) or data.start_pos)
        if respawn_pos then
            player:set_pos(respawn_pos)
            local destination = get_last_checkpoint(data) and "last checkpoint" or "start"
            minetest.chat_send_player(player_name, minetest.colorize("#FF00FF", "Respawned at ") .. minetest.colorize("#FFFFFF", destination) .. minetest.colorize("#FF00FF", "."))
            minetest.log("action", "[Parkour Race] " .. player_name .. " respawned at " .. destination .. " at " .. minetest.pos_to_string(respawn_pos))
            return true
        else
            minetest.chat_send_player(player_name, minetest.colorize("#FFA500", "Failed to find a safe respawn position."))
            minetest.log("warning", "[Parkour Race] No safe respawn position for " .. player_name)
        end
    end
    return false
end)

-- Prevent fall damage during race
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time and reason.type == "fall" then
        minetest.log("action", "[Parkour Race] Prevented fall damage for " .. player_name)
        return 0 -- Cancel fall damage
    end
    return hp_change
end, true)

-- Clean up race data when a player leaves
minetest.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local inv = player:get_inventory()
        inv:remove_item("main", modname .. ":teleport_stick")
        inv:remove_item("main", modname .. ":cancel_stick")
        minetest.log("action", "[Parkour Race] Removed teleport and cancel sticks from " .. player_name .. "'s inventory on leave")
    end
    player_race_data[player_name] = nil
    minetest.log("action", "[Parkour Race] " .. player_name .. " left, race data cleared")
end)

-- Log mod initialization
minetest.log("action", "[Parkour Race] Mod loaded")