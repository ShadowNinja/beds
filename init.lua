-- Boilerplate to support localized strings if intllib mod is installed.
local S
if intllib then
	S = intllib.Getter()
else
	S = function(s) return s end
end

-- Table of players currently in bed
--   key = player name, value = the bed node position
local players_in_bed = {}
local player_spawns = {}

local beds_list = {
	{"Red Bed", "red"},
	{"Orange Bed", "orange"},
	{"Yellow Bed", "yellow"},
	{"Green Bed", "green"},
	{"Blue Bed", "blue"},
	{"Violet Bed", "violet"},
	{"Black Bed", "black"},
	{"Grey Bed", "grey"},
	{"White Bed", "white"},
}


local function load_spawns()
	local file = io.open(minetest.get_worldpath().."/beds_player_spawns", "r")
	if file then
		player_spawns = minetest.deserialize(file:read("*all"))
		file:close()
	end
end


local function save_spawns()
	local file = io.open(minetest.get_worldpath().."/beds_player_spawns", "w")
	if file then
		file:write(minetest.serialize(player_spawns))
		file:close()
	end
end


local timer = 0
local wait = false
minetest.register_globalstep(function(dtime)
	if wait then return end
	if timer < 4 then
		timer = timer + dtime
		return
	end
	timer = 0

	-- Don't sleep through the night during the day
	local time = minetest.get_timeofday()
	if time > 0.2 and time < 0.805 then
		return
	end
	local players = minetest.get_connected_players()
	-- Don't change  the time when nobody is online.
	if #players == 0 then
		return
	end
	local all_in_bed = true
	for _, player in pairs(players) do
		if not players_in_bed[player:get_player_name()] then
			all_in_bed = false
			break
		end
	end

	if all_in_bed then
		minetest.chat_send_all(S("Good night!"))
		minetest.after(2, function()
			minetest.set_timeofday(0.23)
			wait = false
		end)
		wait = true
	end
end)


local function remove_from_bed(player)
	local player_name = player:get_player_name()
	if players_in_bed[player_name] then
		local meta = minetest.get_meta(players_in_bed[player_name])
		meta:set_string("player", "")
		players_in_bed[player] = nil

		player:setpos(player_spawns[player_name])
		if health then
			health.set_attr(player_name, "asleep", 0)
		else
			player:set_physics_override(1, 1, 1)
		end
	end
end


local function get_top_pos(pos, rot)
	local pos = vector.new(pos)
	if     rot == 0 then pos.z = pos.z + 1
	elseif rot == 1 then pos.x = pos.x + 1
	elseif rot == 2 then pos.z = pos.z - 1
	elseif rot == 3 then pos.x = pos.x - 1
	end
	return pos
end


for i, bed in ipairs(beds_list) do
	local color = bed[2]

	minetest.register_node("beds:bed_bottom_"..color, {
		description = S(bed[1]),
		drawtype = "nodebox",
		tiles = {"beds_bed_bottom_top_"..color..".png", "default_wood.png",
			"default_wood.png^beds_bed_side_"..color..".png",
			"default_wood.png^beds_bed_side_"..color..".png",
			"default_wood.png^beds_bed_side_"..color..".png",
			"default_wood.png^beds_bed_side_"..color..".png"},
		paramtype = "light",
		paramtype2 = "facedir",
		stack_max = 1,
		groups = {snappy=1, choppy=2, oddly_breakable_by_hand=2, flammable=3},
		sounds = default.node_sound_wood_defaults(),
		node_box = {
			type = "fixed",
			fixed = {
				{-0.5,  0.0, -0.5,  0.5,  0.3125, 0.5},  -- Bed
				{-0.5, -0.5, -0.5, -0.4,  0.0,   -0.4},  -- Leg
				{ 0.4,  0.0, -0.4,  0.5, -0.5,   -0.5},  -- Leg
			}
		},
		-- Make the bottom of the bed have the selection box for the whole bed
		selection_box = {
			type = "fixed",
			fixed = {
				{-0.5, -0.5, -0.5, 0.5, 0.3125, 1.5},
			}
		},

		after_place_node = function(pos, placer, itemstack)
			local node = minetest.get_node(pos)
			local top = get_top_pos(pos, node.param2)
			local top_node = minetest.get_node(top)
			local top_def = minetest.registered_nodes[top_node.name]
			if top_def and top_def.buildable_to  then
				node.name = "beds:bed_top_"..color
				minetest.set_node(top, node)
			else
				minetest.remove_node(pos)
				return true
			end
		end,

		on_destruct = function(pos)
			local node = minetest.get_node(pos)

			-- If there's a player in a destroyed/dug bed, they need removing
			for player_name, bed_pos in pairs(players_in_bed) do
				if vector.equals(bed_pos, pos) then
					local player = minetest.get_player_by_name(player_name)
					if player then
						remove_from_bed(player)
					end
				end
			end

			local top = get_top_pos(pos, node.param2)
			if minetest.get_node(top).name == "beds:bed_top_"..color and
					minetest.get_node(top).param2 == node.param2 then
				minetest.remove_node(top)
			end
		end,

		on_rightclick = function(pos, node, clicker)
			if not clicker:is_player() then
				return
			end

			local player_name = clicker:get_player_name()

			local meta = minetest.get_meta(pos)
			local bed_player = meta:get_string("player")

			if player_name == bed_player then
				remove_from_bed(clicker)
			elseif bed_player == "" then
				-- Save the spawn position before we move the player into
				-- the bed.
				player_spawns[player_name] = clicker:getpos()
				save_spawns()

				meta:set_string("player", player_name)
				players_in_bed[player_name] = vector.new(pos)

				if health then
					health.set_attr(player_name, "asleep", 1)
				else
					clicker:set_physics_override(0, 0, 0)
				end

				local rot = node.param2
				if     rot == 0 then
					pos.z = pos.z + 1
					clicker:set_look_yaw(math.pi)
				elseif rot == 1 then
					pos.x = pos.x + 1
					clicker:set_look_yaw(0.5 * math.pi)
				elseif rot == 2 then
					pos.z = pos.z - 1
					clicker:set_look_yaw(0)
				elseif rot == 3 then
					pos.x = pos.x - 1
					clicker:set_look_yaw(1.5 * math.pi)
				end
				pos.y = pos.y - 0.5
				clicker:setpos(pos)
			end
		end
	})

	minetest.register_node("beds:bed_top_"..color, {
		drawtype = "nodebox",
		tiles = {"beds_bed_top_top_"..color..".png", "default_wood.png",
			"default_wood.png^beds_bed_top_side_"..color..".png^[transformFX",
			"default_wood.png^beds_bed_top_side_"..color..".png",
			"default_wood.png^beds_bed_top_front.png",
			"default_wood.png^beds_bed_side_"..color..".png"},
		paramtype = "light",
		paramtype2 = "facedir",
		groups = {snappy=1,choppy=2,oddly_breakable_by_hand=2,flammable=3},
		sounds = default.node_sound_wood_defaults(),
		node_box = {
			type = "fixed",
			fixed = {
				{-0.5,    0.0,   -0.5,  0.5,    0.3125, 0.5},  -- Bed
				{-0.4375, 0.3125, 0.1,  0.4375, 0.4375, 0.5},  -- Pillow
				{-0.4,    0.0,    0.4, -0.5,   -0.5,    0.5},  -- Leg
				{ 0.5,   -0.5,    0.5,  0.4,    0.0,    0.4},  -- Leg
			}
		},
		pointable = false,
	})

	minetest.register_alias("beds:bed_"..color, "beds:bed_bottom_"..color)

	minetest.register_craft({
		output = "beds:bed_bottom_"..color,
		recipe = {
			{"wool:"..color,  "wool:"..color, "wool:white"},
			{"default:stick", "",             "default:stick"}
		}
	})

	minetest.register_craft({
		output = "beds:bed_"..color,
		recipe = {
			{"wool:white",    "wool:"..color, "wool:"..color},
			{"default:stick", "",             "default:stick"}
		}
	})
end

minetest.register_alias("beds:bed_bottom", "beds:bed_bottom_blue")
minetest.register_alias("beds:bed_top",    "beds:bed_top_blue")
minetest.register_alias("beds:bed",        "beds:bed_bottom_blue")

minetest.register_on_shutdown(function(player)
	local players = minetest.get_connected_players()
	for _, player in pairs(players) do
		if players_in_bed[player:get_player_name()] then
			remove_from_bed(player)
		end
	end
end)

minetest.register_on_leaveplayer(remove_from_bed)

minetest.register_on_respawnplayer(function(player)
	local player_name = player:get_player_name()
	remove_from_bed(player)
	if player_spawns[player_name] then
		player:setpos(player_spawns[player_name])
		return true
	end
	return false
end)


load_spawns()

if minetest.setting_get("log_mods") then
	minetest.log("action", S("[beds] Loaded."))
end

