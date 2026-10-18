local sounds_overrides = {
	{ 	-- subway sounds override
		wagons = {
			["advtrains_train_subway"] = {"subway_wagon"},
			["advtrains_subway_ny"] = {"NY_lokomotive", "ny_wagon"},
			["subways_01700_series"] = {"subways_01700_series:01700_series"},
			["subways_lrv_type_9"] = {"subways_lrv_type_9:lrv_type_9", "subways_lrv_type_9_middle:lrv_type_9_middle"}
		},
		sounds = {
			depart = {{name="advtrains_metro_depart_0", duration=12.3}, {name="advtrains_metro_depart_1", duration=11.5}},
			arrive = {{name="advtrains_metro_arrive_0", duration=12.7}, {name="advtrains_metro_arrive_0", duration=12.7}},
			loop = {{name="advtrains_metro_loop_0", duration=59}, {name="advtrains_metro_loop_1", duration=63}},
			loop_inside = {{name="advtrains_metro_loop_0", duration=59}, {name="advtrains_metro_loop_1", duration=63}},
			loop_outside = {{name="advtrains_metro_loop_0", duration=59}, {name="advtrains_metro_loop_1", duration=63}}
		}
	}
}

for _, override in ipairs(sounds_overrides) do
	for mod, wagons in pairs(override.wagons) do
		if core.get_modpath(mod) then
			for _, wagon in ipairs(wagons) do
				local wagon_objname = wagon:find(":") and wagon or "advtrains:"..wagon
				local proto = advtrains.wagon_prototypes[wagon_objname].__index
				proto.custom_on_velocity_change = nil
				proto.sounds.door_open = override.sounds.door_open or proto.sounds.door_open
				proto.sounds.door_close = override.sounds.door_close or proto.sounds.door_close
				proto.sounds.depart = override.sounds.depart or proto.sounds.depart
				proto.sounds.arrive = override.sounds.arrive or proto.sounds.arrive
				proto.sounds.loop = override.sounds.loop or proto.sounds.loop
				proto.sounds.loop_inside = override.sounds.loop_inside or proto.sounds.loop_inside
				proto.sounds.loop_outside = override.sounds.loop_outside or proto.sounds.loop_outside
			end
		end
	end
end
