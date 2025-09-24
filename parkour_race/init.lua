-- Parkour Race Minigame Mod for Luanti (Minetest fork)
-- This mod allows players to participate in a parkour race with start, checkpoint, finish, and scoreboard nodes.
-- Features: Start race when moving away from start node, track time, save checkpoints, teleport on fall, display time on HUD, announce finish time, show scoreboard.

-- Define the mod namespace
local modname = "parkour_race"
local modpath = minetest.get_modpath(modname)

-- Table to store player race data (start time, start position, checkpoint position, HUD ID, etc.)
local player_race_data = {}

-- Get mod storage for persistent scoreboard data
local storage = minetest.get_mod_storage()

-- Function to format time in seconds to MM:SS.mmm (minutes, seconds, milliseconds)
local function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local millis = math.floor((seconds % 1) * 1000)
    return string.format("%02d:%02d.%03d", minutes, secs, millis)
end

-- Function to get a safe teleport position (on top of the block)
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
        checkpoint_pos = nil,
        hud_id = nil,
        last_node_pos = nil
    }

    -- Initialize HUD
    local hud = player:hud_add({
        hud_elem_type = "text",
        position = { x = 0.5, y = 0.2 },
        offset = { x = 0, y = 0 },
        text = "Time: 00:00.000",
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

    minetest.chat_send_player(player_name, "Parkour race started! Reach the finish block.")
    minetest.log("action", "[Parkour Race] Race started for " .. player_name .. " at " .. minetest.pos_to_string(pos))
end

-- Function to update the HUD with elapsed time
local function update_hud(player)
    local player_name = player:get_player_name()
    local data = player_race_data[player_name]
    if data and data.start_time and data.hud_id then
        local status, err = pcall(function()
            local elapsed = os.clock() - data.start_time
            player:hud_change(data.hud_id, "text", "Time: " .. format_time(elapsed))
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
    minetest.chat_send_all(player_name .. " finished the parkour race in " .. time_str .. "!")
    minetest.log("action", "[Parkour Race] " .. player_name .. " finished in " .. time_str)

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

-- Register the Checkpoint Block node
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
            if node_name == modname .. ":start_sign" or node_name == modname .. ":checkpoint_block" or node_name == modname .. ":finish_block" then
                break
            end
        end
    

        if data and data.start_time then
            -- Player is in a race
            update_hud(player)

            if pos.y < 0 then
                local teleport_pos = data.checkpoint_pos and get_safe_teleport_pos(data.checkpoint_pos) or data.start_pos
                if teleport_pos then
                    player:set_pos(teleport_pos)
                    minetest.chat_send_player(player_name, "Fell off! Teleported to last checkpoint.")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " fell and teleported to " .. minetest.pos_to_string(teleport_pos))
                end
            end

            if not data.last_node_pos or not vector.equals(player_pos, data.last_node_pos) then
                if node_name == modname .. ":checkpoint_block" then
                    data.checkpoint_pos = player_pos
                    minetest.chat_send_player(player_name, "Checkpoint reached!")
                    minetest.log("action", "[Parkour Race] " .. player_name .. " reached checkpoint at " .. minetest.pos_to_string(player_pos))
                elseif node_name == modname .. ":finish_block" then
                    minetest.log("action", "[Parkour Race] Finish block detected for " .. player_name)
                    end_race(player)
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
        local respawn_pos = data.checkpoint_pos and get_safe_teleport_pos(data.checkpoint_pos) or data.start_pos
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