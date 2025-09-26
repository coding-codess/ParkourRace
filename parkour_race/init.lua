-- Parkour Race Minigame for Luanti
-- Features: Start race when moving away from start node, track time, save required and optional checkpoints, teleport on fall, display time and checkpoints on HUD, announce finish time, show scoreboard.

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
    -- Define a search area centered around (-317, 8, 0) to cover the provided coordinates
    local world_size = 200 -- Radius to search, volume = (400^3) = 64,000,000 nodes
    local min_pos = {x = -517, y = -192, z = -200} -- Adjusted to center around (-317, 8, 0)
    local max_pos = {x = -117, y = 208, z = 200}
    
    -- Calculate volume to ensure it's within limits
    local volume = (max_pos.x - min_pos.x) * (max_pos.y - min_pos.y) * (max_pos.z - min_pos.z)
    if volume > 150000000 then
        minetest.log("error", "[Parkour Race] Search area volume (" .. volume .. ") exceeds limit of 150,000,000")
        return 0
    end

    -- Force load map chunks in the search area
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

    -- Find all required checkpoint nodes in the area
    local nodes = minetest.find_nodes_in_area(min_pos, max_pos, {modname .. ":checkpoint_block"})
    required_checkpoints_count = #nodes
    
    -- Log detected checkpoints for debugging
    if #nodes > 0 then
        for i, pos in ipairs(nodes) do
            minetest.log("action", "[Parkour Race] Detected required checkpoint " .. i .. " at " .. minetest.pos_to_string(pos))
        end
    else
        minetest.log("warning", "[Parkour Race] No required checkpoints found in search area " .. minetest.pos_to_string(min_pos) .. " to " .. minetest.pos_to_string(max_pos))
        -- Debug: Check if the specific checkpoint node exists
        local test_pos = {x=-317, y=8, z=5}
        local node = minetest.get_node(test_pos)
        minetest.log("action", "[Parkour Race] Node at checkpoint position " .. minetest.pos_to_string(test_pos) .. " is " .. node.name)
    end
    
    minetest.log("action", "[Parkour Race] Found " .. required_checkpoints_count .. " required checkpoint(s) in the map")
    
    -- Free forceloaded blocks after scanning
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
    local node = minetest.get_node(safe_pos)
    if minetest.registered_nodes[node.name].walkable then
        safe_pos.y = safe_pos.y + 1
        local node_above = minetest.get_node(safe_pos)
        if minetest.registered_nodes[node_above.name].walkable then
            return nil
        end
    end
    return safe_pos
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

-- Function to start the race for a player
local function start_race(player)
    local player_name = player:get_player_name()
    local pos = player:get_pos()
    minetest.log("action", "[Parkour Race] Attempting to start race for " .. player_name .. " at " .. minetest.pos_to_string(pos))

    -- Clear any existing race data to avoid conflicts
    player_race_data[player_name] = {
        start_time = os.clock(),
        start_pos = vector.round(pos),
        required_checkpoints = {}, -- List of required checkpoint positions
        optional_checkpoints = {}, -- List of optional checkpoint positions
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

    local required_count = get_required_checkpoints_count()
    minetest.chat_send_player(player_name, "Parkour race started! Reach all " .. required_count .. " required checkpoint(s) (if any) and the finish block. Optional checkpoints are bonus.")
    minetest.log("action", "[Parkour Race] Race started for " .. player_name .. " at " .. minetest.pos_to_string(pos))
end

-- Function to update the HUD with elapsed time and checkpoint progress
local function update_hud(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time and data.hud_id then
        local status, err = pcall(function()
            local elapsed = os.clock() - data.start_time
            local checkpoint_text = "Req CP: " .. #data.required_checkpoints .. "/" .. get_required_checkpoints_count() .. " | Opt CP: " .. #data.optional_checkpoints
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

    local elapsed = os.clock() - data.start_time
    local time_str = format_time(elapsed)
    minetest.chat_send_all(player_name .. " finished the parkour race in " .. time_str .. " with " .. #data.required_checkpoints .. " required and " .. #data.optional_checkpoints .. " optional checkpoints!")
    minetest.log("action", "[Parkour Race] " .. player_name .. " finished in " .. time_str .. " with " .. #data.required_checkpoints .. " required and " .. #data.optional_checkpoints .. " optional checkpoints")

    update_scoreboard(player_name, elapsed)

    if data.hud_id then
        pcall(function()
            player:hud_remove(data.hud_id)
        end)
    end

    player_race_data[player_name] = nil
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
    description = "Parkour Race Required Checkpoint Block",
    tiles = {"default_stone.png^[colorize:#FFFF00:128"},
    groups = {cracky = 3},
    sounds = minetest.global_exists("default") and default.node_sound_stone_defaults() or nil
})

-- Register the Optional Checkpoint Block node
minetest.register_node(modname .. ":optional_checkpoint_block", {
    description = "Parkour Race Optional Checkpoint Block",
    tiles = {"default_stone.png^[colorize:#00FFFF:128"}, -- Cyan to distinguish from required checkpoint
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

-- Global step to check for falls, update HUD, detect checkpoint/finish nodes, and start race
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()
        local data = player_race_data[player_name]
        local pos = player:get_pos()
        -- Check multiple Y-offsets to improve node detection
        local offsets = {-0.5, -1, 0}
        local node_name = "unknown"
        local player_pos = nil
        for _, offset in ipairs(offsets) do
            player_pos = vector.round({x = pos.x, y = pos.y + offset, z = pos.z})
            local node = minetest.get_node(player_pos)
            node_name = node.name
            if node_name == modname .. ":start_sign" or node_name == modname .. ":checkpoint_block" or node_name == modname .. ":optional_checkpoint_block" or node_name == modname .. ":finish_block" then
                break
            end
        end

        if data and data.start_time then
            -- Player is in a race
            update_hud(player)

            if pos.y < 0 then
                -- Teleport to the last required checkpoint or start if none exist
                local teleport_pos = (data.required_checkpoints[#data.required_checkpoints] and get_safe_teleport_pos(data.required_checkpoints[#data.required_checkpoints])) or data.start_pos
                if teleport_pos then
                    player:set_pos(teleport_pos)
                    minetest.chat_send_player(player_name, "Fell off! Teleported to last required checkpoint or start.")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " fell and teleported to " .. minetest.pos_to_string(teleport_pos))
                end
            end

            if not data.last_node_pos or not vector.equals(player_pos, data.last_node_pos) then
                if node_name == modname .. ":checkpoint_block" then
                    -- Check if this required checkpoint is not already in the list
                    local is_new_checkpoint = true
                    for _, cp_pos in ipairs(data.required_checkpoints) do
                        if vector.equals(cp_pos, player_pos) then
                            is_new_checkpoint = false
                            break
                        end
                    end
                    if is_new_checkpoint then
                        table.insert(data.required_checkpoints, player_pos)
                        minetest.chat_send_player(player_name, "Required Checkpoint reached! (" .. #data.required_checkpoints .. "/" .. get_required_checkpoints_count() .. ")")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " reached required checkpoint at " .. minetest.pos_to_string(player_pos))
                    end
                elseif node_name == modname .. ":optional_checkpoint_block" then
                    -- Check if this optional checkpoint is not already in the list
                    local is_new_checkpoint = true
                    for _, cp_pos in ipairs(data.optional_checkpoints) do
                        if vector.equals(cp_pos, player_pos) then
                            is_new_checkpoint = false
                            break
                        end
                    end
                    if is_new_checkpoint then
                        table.insert(data.optional_checkpoints, player_pos)
                        minetest.chat_send_player(player_name, "Optional Checkpoint reached! (" .. #data.optional_checkpoints .. ")")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " reached optional checkpoint at " .. minetest.pos_to_string(player_pos))
                    end
                elseif node_name == modname .. ":finish_block" then
                    -- Check if required checkpoints exist and have been reached
                    local required_count = get_required_checkpoints_count()
                    if required_count > 0 and #data.required_checkpoints < required_count then
                        minetest.chat_send_player(player_name, "You must reach all " .. required_count .. " required checkpoint(s) first! (" .. #data.required_checkpoints .. "/" .. required_count .. " reached)")
                        minetest.log("action", "[Parkour Race] " .. player_name .. " tried to finish with only " .. #data.required_checkpoints .. "/" .. required_count .. " required checkpoints")
                    else
                        minetest.log("action", "[Parkour Race] Finish block detected for " .. player_name .. " with " .. #data.required_checkpoints .. " required and " .. #data.optional_checkpoints .. " optional checkpoints")
                        end_race(player)
                    end
                end
                data.last_node_pos = player_pos
            end
        else
            -- Player is not in a race
            if node_name == modname .. ":start_sign" then
                if not data or not data.on_start_node then
                    player_race_data[player_name] = {
                        on_start_node = true,
                        start_pos = player_pos,
                        last_node_pos = player_pos
                    }
                    minetest.chat_send_player(player_name, "Stand on the start sign and move away to begin the race!")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " on start node at " .. minetest.pos_to_string(player_pos))
                end
            elseif data and data.on_start_node then
                -- Player moved off start sign, start the race
                player_race_data[player_name] = nil -- Clear on_start_node data
                minetest.log("action", "[Parkour Race] " .. player_name .. " moved off start node, starting race")
                start_race(player)
            end
        end
    end
end)

-- Handle player respawn
minetest.register_on_respawnplayer(function(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time then
        local respawn_pos = (data.required_checkpoints[#data.required_checkpoints] and get_safe_teleport_pos(data.required_checkpoints[#data.required_checkpoints])) or data.start_pos
        if respawn_pos then
            player:set_pos(respawn_pos)
            minetest.log("action", "[Parkour Race] " .. player_name .. " respawned at " .. minetest.pos_to_string(respawn_pos))
            return true
        end
    end
    return false
end)

-- Clean up race data when a player leaves
minetest.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()
    player_race_data[player_name] = nil
    minetest.log("action", "[Parkour Race] " .. player_name .. " left, race data cleared")
end)

-- Log mod initialization
minetest.log("action", "[Parkour Race] Mod loaded")