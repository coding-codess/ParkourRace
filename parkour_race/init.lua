-- Parkour Race Minigame for Luanti
-- Define the mod namespace
local modname = "parkour_race"
local modpath = minetest.get_modpath(modname)

-- Table to store player race data
local player_race_data = {}

-- Get mod storage for persistent scoreboard data
local storage = minetest.get_mod_storage()

-- Cache for required checkpoints count
local required_checkpoints_count = 0

-- Flag to track if initial scan has been done
local initial_scan_done = false

-- Function to count required checkpoints in the map and cache the result
local function update_required_checkpoints_count()
    local world_size = 200 -- Radius to search, volume = (400^3) = 64,000,000 nodes
    local min_pos = {x = -517, y = -192, z = -200} -- Adjusted to center around (-317, 8, 0)
    local max_pos = {x = -117, y = 208, z = 200}
    
    local volume = (max_pos.x - min_pos.x) * (max_pos.y - min_pos.y) * (max_pos.z - min_pos.z)
    if volume > 150000000 then
        minetest.log("error", "[Parkour Race] Search area volume (" .. volume .. ") exceeds limit of 150,000,000")
        return 0
    end

    local min_block = vector.divide(min_pos, 16):floor()
    local max_block = vector.divide(max_pos, 16):floor()
    local loaded_blocks = {}
    for x = min_block.x, max_block.x do
        for y = min_block.y, max_block.y do
            for z = min_block.z, max_block.z do
                local block_pos = {x=x, y=y, z=z}
                if minetest.forceload_block(block_pos, true) then
                    table.insert(loaded_blocks, minetest.pos_to_string(block_pos))
                end
            end
        end
    end
    minetest.log("action", "[Parkour Race] Force-loaded blocks: " .. table.concat(loaded_blocks, ", "))

    local nodes = minetest.find_nodes_in_area(min_pos, max_pos, {modname .. ":checkpoint_block"})
    required_checkpoints_count = #nodes
    
    if #nodes > 0 then
        for i, pos in ipairs(nodes) do
            minetest.log("action", "[Parkour Race] Detected required checkpoint " .. i .. " at " .. minetest.pos_to_string(pos))
        end
    else
        minetest.log("warning", "[Parkour Race] No required checkpoints found in search area " .. minetest.pos_to_string(min_pos) .. " to " .. minetest.pos_to_string(max_pos))
        local test_pos = {x=-317, y=8, z=5}
        local node = minetest.get_node(test_pos)
        minetest.log("action", "[Parkour Race] Node at checkpoint position " .. minetest.pos_to_string(test_pos) .. " is " .. node.name)
    end
    
    minetest.log("action", "[Parkour Race] Found " .. required_checkpoints_count .. " required checkpoint(s) in the map")
    
    for x = min_block.x, max_block.x do
        for y = min_block.y, max_block.y do
            for z = min_block.z, max_block.z do
                minetest.forceload_free_block({x=x, y=y, z=z}, true)
            end
        end
    end

    return required_checkpoints_count
end

-- Function to get the cached required checkpoints count
local function get_required_checkpoints_count()
    return required_checkpoints_count
end

-- Trigger checkpoint scan when the first player joins, with a short delay
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
        update_required_checkpoints_count()
        minetest.log("action", "[Parkour Race] Checkpoint placed, updated count to " .. required_checkpoints_count)
    end
end)

minetest.register_on_dignode(function(pos, oldnode)
    if oldnode.name == modname .. ":checkpoint_block" then
        update_required_checkpoints_count()
        minetest.log("action", "[Parkour Race] Checkpoint removed, updated count to " .. required_checkpoints_count)
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

-- Function to update the singleplayer scoreboard with a player's completion time
local function update_singleplayer_scoreboard(player_name, time)
    local scoreboard = storage:get_string("singleplayer_scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    if not scoreboard[player_name] or time < scoreboard[player_name] then
        scoreboard[player_name] = time
        storage:set_string("singleplayer_scoreboard", minetest.serialize(scoreboard))
        minetest.log("action", "[Parkour Race] Updated singleplayer scoreboard for " .. player_name .. " with time " .. format_time(time))
    end
end

-- Function to get the top 5 singleplayer scoreboard entries as a formspec table
local function get_singleplayer_scoreboard_formspec()
    local scoreboard = storage:get_string("singleplayer_scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    local sorted_scores = {}
    for name, time in pairs(scoreboard) do
        table.insert(sorted_scores, {name = name, time = time})
    end
    table.sort(sorted_scores, function(a, b) return a.time < b.time end)
    local formspec = {
        "formspec_version[4]",
        "size[6,8]",
        "label[0.5,0.5;Singleplayer Parkour Race Scoreboard]",
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

-- Function to reset the singleplayer leaderboard and announce the winner
local function reset_singleplayer_leaderboard()
    local scoreboard = storage:get_string("singleplayer_scoreboard")
    scoreboard = scoreboard ~= "" and minetest.deserialize(scoreboard) or {}
    local winner_name, winner_time = nil, nil
    for name, time in pairs(scoreboard) do
        if not winner_time or time < winner_time then
            winner_name = name
            winner_time = time
        end
    end

    -- Announce winner
    if winner_name and winner_time then
        minetest.chat_send_all("Daily Singleplayer Parkour Race Winner: " .. winner_name .. " with time " .. format_time(winner_time) .. "!")
        minetest.log("action", "[Parkour Race] Daily singleplayer winner: " .. winner_name .. " with time " .. format_time(winner_time))

        -- Store historical winner
        local winners = storage:get_string("singleplayer_winners")
        winners = winners ~= "" and minetest.deserialize(winners) or {}
        table.insert(winners, {
            name = winner_name,
            time = winner_time,
            timestamp = os.time()
        })
        storage:set_string("singleplayer_winners", minetest.serialize(winners))
    else
        minetest.chat_send_all("No winner for today's Singleplayer Parkour Race.")
        minetest.log("action", "[Parkour Race] No singleplayer winner for today")
    end

    -- Reset the leaderboard
    storage:set_string("singleplayer_scoreboard", "")
    minetest.log("action", "[Parkour Race] Singleplayer leaderboard reset")
end

-- Function to check and schedule daily reset at 12 PM UTC
local function schedule_leaderboard_reset()
    local now = os.time()
    local utc = os.date("!*t", now)
    local seconds_until_midday = ((24 - utc.hour) % 24) * 3600 - utc.min * 60 - utc.sec
    if utc.hour >= 12 then
        seconds_until_midday = seconds_until_midday + 24 * 3600
    end
    minetest.after(seconds_until_midday, function()
        reset_singleplayer_leaderboard()
        -- Schedule next reset
        minetest.after(24 * 3600, schedule_leaderboard_reset)
    end)
    minetest.log("action", "[Parkour Race] Scheduled singleplayer leaderboard reset in " .. seconds_until_midday .. " seconds")
end

-- Start the reset scheduler when mod loads
minetest.after(0, schedule_leaderboard_reset)

-- Command to manually reset the singleplayer leaderboard
minetest.register_chatcommand("reset_leaderboard", {
    description = "Manually reset the singleplayer parkour race leaderboard",
    privs = {server = true}, -- Requires admin privileges
    func = function(name, param)
        reset_singleplayer_leaderboard()
        return true, "Singleplayer leaderboard has been reset."
    end
})

-- Function to start the race for a player
local function start_race(player, start_pos)
    local player_name = player:get_player_name()
    local pos = player:get_pos()
    minetest.log("action", "[Parkour Race] Attempting to start race for " .. player_name .. " at " .. minetest.pos_to_string(pos))

    -- Initialize race data
    player_race_data[player_name] = {
        start_time = os.clock(),
        start_pos = start_pos, -- Use provided start_pos
        checkpoints = {}, -- Unified list: {pos=vector, type="required"/"optional", seq=number}
        checkpoint_seq = 0, -- Sequence counter for checkpoints
        hud_id = nil,
        last_node_pos = nil
    }

    -- Initialize HUD
    local hud = player:hud_add({
        type = "text",
        position = { x = 0.5, y = 0.2 },
        offset = { x = 0, y = 0 },
        text = "Time: 00:00.000 | Req CP: 0 | Opt CP: 0",
        number = 0xFFFFFF,
        alignment = { x = 0, y = 0 },
        scale = { x = 100, y = 100 }
    })
    if hud then
        player_race_data[player_name].hud_id = hud
        minetest.log("action", "[Parkour Race] HUD added for " .. player_name .. " with ID " .. hud)
    else
        minetest.log("error", "[Parkour Race] Failed to add HUD for " .. player_name)
    end

    -- Give the player the teleport stick
    local inv = player:get_inventory()
    if not inv:contains_item("main", modname .. ":teleport_stick") then
        inv:add_item("main", modname .. ":teleport_stick")
        minetest.log("action", "[Parkour Race] Gave teleport stick to " .. player_name)
    end

    local required_count = get_required_checkpoints_count()
    minetest.chat_send_player(player_name, "Singleplayer parkour race started! Reach all " .. required_count .. " required checkpoint(s) (if any) and the finish block. Optional checkpoints are bonus. Drop or left-click the teleport stick to reset to last checkpoint.")
    minetest.log("action", "[Parkour Race] Singleplayer race started for " .. player_name .. " at " .. minetest.pos_to_string(pos))
end

-- Function to update the HUD with elapsed time and checkpoint progress
local function update_hud(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time and data.hud_id then
        local status, err = pcall(function()
            local elapsed = os.clock() - data.start_time
            local req_count = 0
            local opt_count = 0
            for _, cp in ipairs(data.checkpoints) do
                if cp.type == "required" then
                    req_count = req_count + 1
                elseif cp.type == "optional" then
                    opt_count = opt_count + 1
                end
            end
            local checkpoint_text = "Req CP: " .. req_count .. "/" .. get_required_checkpoints_count() .. " | Opt CP: " .. opt_count
            player:hud_change(data.hud_id, "text", "Time: " .. format_time(elapsed) .. " | " .. checkpoint_text)
        end)
        if not status then
            minetest.log("error", "[Parkour Race] HUD update failed for " .. player_name .. ": " .. err)
        end
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

    local req_count = 0
    local opt_count = 0
    for _, cp in ipairs(data.checkpoints) do
        if cp.type == "required" then
            req_count = req_count + 1
        elseif cp.type == "optional" then
            opt_count = opt_count + 1
        end
    end

    local elapsed = os.clock() - data.start_time
    local time_str = format_time(elapsed)
    minetest.chat_send_all(player_name .. " finished the singleplayer parkour race in " .. time_str .. " with " .. req_count .. " required and " .. opt_count .. " optional checkpoints!")
    minetest.log("action", "[Parkour Race] " .. player_name .. " finished singleplayer race in " .. time_str .. " with " .. req_count .. " required and " .. opt_count .. " optional checkpoints")

    update_singleplayer_scoreboard(player_name, elapsed)

    if data.hud_id then
        pcall(function()
            player:hud_remove(data.hud_id)
        end)
    end

    local inv = player:get_inventory()
    inv:remove_item("main", modname .. ":teleport_stick")
    minetest.log("action", "[Parkour Race] Removed teleport stick from " .. player_name .. "'s inventory")

    player_race_data[player_name] = nil
end

-- Helper function to get the last checkpoint (required or optional)
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

-- Function to teleport player to last checkpoint (required or optional) or start
local function teleport_to_last_checkpoint(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local last_checkpoint = get_last_checkpoint(data)
        local teleport_pos = last_checkpoint and get_safe_teleport_pos(last_checkpoint) or get_safe_teleport_pos(data.start_pos)
        if teleport_pos then
            player:set_pos(teleport_pos)
            local destination = last_checkpoint and "last checkpoint" or "start"
            minetest.chat_send_player(player_name, "Teleported to " .. destination .. ".")
            minetest.log("action", "[Parkour Race] " .. player_name .. " teleported to " .. destination .. " at " .. minetest.pos_to_string(teleport_pos))
        else
            minetest.chat_send_player(player_name, "Failed to find a safe teleport position.")
            minetest.log("warning", "[Parkour Race] No safe teleport position for " .. player_name)
        end
    else
        minetest.chat_send_player(player_name, "You are not in a race.")
    end
end

-- Register the Start Sign node
minetest.register_node(modname .. ":start_sign", {
    description = "Singleplayer Parkour Race Start Sign",
    tiles = {"default_sign_wall_wood.png^[colorize:#00FF00:128"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    sounds = minetest.global_exists("default") and default.node_sound_wood_defaults() or nil,
})

-- Register the Required Checkpoint Block node
minetest.register_node(modname .. ":checkpoint_block", {
    description = "Singleplayer Parkour Race Required Checkpoint Block",
    tiles = {"default_stone.png^[colorize:#FFFF00:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Optional Checkpoint Block node
minetest.register_node(modname .. ":optional_checkpoint_block", {
    description = "Singleplayer Parkour Race Optional Checkpoint Block",
    tiles = {"default_stone.png^[colorize:#00FFFF:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Finish Block node
minetest.register_node(modname .. ":finish_block", {
    description = "Singleplayer Parkour Race Finish Block",
    tiles = {"default_stone.png^[colorize:#FF0000:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Scoreboard Sign node
minetest.register_node(modname .. ":scoreboard_sign", {
    description = "Singleplayer Parkour Race Scoreboard Sign",
    tiles = {"default_sign_wall_wood.png^[colorize:#0000FF:128"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    sounds = minetest.global_exists("default") and default.node_sound_wood_defaults() or nil,
    on_rightclick = function(pos, node, player, itemstack, pointed_thing)
        minetest.show_formspec(player:get_player_name(), "parkour_race:scoreboard", get_singleplayer_scoreboard_formspec())
        minetest.log("action", "[Parkour Race] " .. player:get_player_name() .. " opened singleplayer scoreboard")
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

-- Register a chat command to manually teleport to last checkpoint (for testing)
minetest.register_chatcommand("reset", {
    description = "Teleport to the last checkpoint or start position during a parkour race",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end
        teleport_to_last_checkpoint(player)
        return true, "Teleport command executed."
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
               node_name == modname .. ":optional_checkpoint_block" or node_name == modname .. ":finish_block" then
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
                    minetest.chat_send_player(player_name, "Fell off! Teleported to " .. destination .. ".")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " fell and teleported to " .. destination .. " at " .. minetest.pos_to_string(teleport_pos))
                else
                    minetest.chat_send_player(player_name, "Failed to find a safe teleport position.")
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
                        table.insert(data.checkpoints, {pos = player_pos, type = "required", seq = data.checkpoint_seq})
                        local req_count = 0
                        for _, cp in ipairs(data.checkpoints) do
                            if cp.type == "required" then req_count = req_count + 1 end
                        end
                        minetest.chat_send_player(player_name, "Required Checkpoint reached! (" .. req_count .. "/" .. get_required_checkpoints_count() .. ")")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " reached required checkpoint at " .. minetest.pos_to_string(player_pos) .. " (seq: " .. data.checkpoint_seq .. ")")
                    end
                elseif node_name == modname .. ":optional_checkpoint_block" then
                    local is_new_checkpoint = true
                    for _, cp in ipairs(data.checkpoints) do
                        if vector.equals(cp.pos, player_pos) then
                            is_new_checkpoint = false
                            break
                        end
                    end
                    if is_new_checkpoint then
                        data.checkpoint_seq = data.checkpoint_seq + 1
                        table.insert(data.checkpoints, {pos = player_pos, type = "optional", seq = data.checkpoint_seq})
                        local opt_count = 0
                        for _, cp in ipairs(data.checkpoints) do
                            if cp.type == "optional" then opt_count = opt_count + 1 end
                        end
                        minetest.chat_send_player(player_name, "Optional Checkpoint reached! (" .. opt_count .. ")")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " reached optional checkpoint at " .. minetest.pos_to_string(player_pos) .. " (seq: " .. data.checkpoint_seq .. ")")
                    end
                elseif node_name == modname .. ":finish_block" then
                    local req_count = 0
                    for _, cp in ipairs(data.checkpoints) do
                        if cp.type == "required" then req_count = req_count + 1 end
                    end
                    local required_count = get_required_checkpoints_count()
                    if required_count > 0 and req_count < required_count then
                        minetest.chat_send_player(player_name, "You must reach all " .. required_count .. " required checkpoint(s) first! (" .. req_count .. "/" .. required_count .. " reached)")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " tried to finish with only " .. req_count .. "/" .. required_count .. " required checkpoints")
                    else
                        local opt_count = 0
                        for _, cp in ipairs(data.checkpoints) do
                            if cp.type == "optional" then opt_count = opt_count + 1 end
                        end
                        minetest.log("action", "[Parkour Race] Finish block detected for " .. player_name .. " with " .. req_count .. " required and " .. opt_count .. " optional checkpoints")
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
                    minetest.chat_send_player(player_name, "Stand on the start sign and move away to begin the singleplayer race!")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " on start node at " .. minetest.pos_to_string(node_pos))
                end
            elseif data and data.on_start_node then
                local start_pos = data.start_pos -- Preserve start_pos
                player_race_data[player_name] = nil
                minetest.log("action", "[Parkour Race] " .. player_name .. " moved off start node, starting singleplayer race")
                start_race(player, start_pos) -- Pass start_pos to start_race
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
            minetest.log("action", "[Parkour Race] " .. player_name .. " respawned at " .. destination .. " at " .. minetest.pos_to_string(respawn_pos))
            return true
        end
    end
    return false
end)

-- Clean up race data when a player leaves
minetest.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local inv = player:get_inventory()
        inv:remove_item("main", modname .. ":teleport_stick")
        minetest.log("action", "[Parkour Race] Removed teleport stick from " .. player_name .. "'s inventory on leave")
    end
    player_race_data[player_name] = nil
    minetest.log("action", "[Parkour Race] " .. player_name .. " left, race data cleared")
end)

-- Log mod initialization
minetest.log("action", "[Parkour Race] Singleplayer mod loaded")