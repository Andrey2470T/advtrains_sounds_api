-- wagon.lua
if not core.global_exists("advtrains") then
    core.log("error", "[advtrains_sounds_api] advtrains mod is missing!")
    return
end

local SOUND_GAIN = 3.0
local MAX_HEAR_DIST = 80

local wagon = getmetatable(advtrains.wagon_prototypes["advtrains:wagon_placeholder"]).__index

wagon.sounds = {
	door_open = {
		{name="advtrains_train_door_0", duration=3},
		{name="advtrains_train_door_1", duration=3}
	},
	door_close = {
		{name="advtrains_train_door_0", duration=3},
		{name="advtrains_train_door_1", duration=3}
	},
	depart = {
		{name="advtrains_train_depart_0", duration=9},
		{name="advtrains_train_depart_1", duration=12}
	},
	arrive = {
		{name="advtrains_train_arrive_0", duration=22},
		{name="advtrains_train_arrive_1", duration=14}
	},
	loop = {
		{name="advtrains_train_loop_0", duration=18},
		{name="advtrains_train_loop_1", duration=5},
		{name="advtrains_train_loop_2", duration=5}
	},
	loop_inside = {
		{name="advtrains_train_loop_inside_0", duration=4},
		{name="advtrains_train_loop_inside_1", duration=5}
	},
	loop_outside = {{name="advtrains_train_loop_outside", duration=11}}
}

function wagon:stop_all_sounds()
	for pname, sound_data in pairs(self.player_sounds) do
		core.sound_stop(sound_data.handle)
	end
	self.player_sounds = {}
end

function wagon:stop_sound(pname)
	if self.player_sounds[pname] then
		core.sound_stop(self.player_sounds[pname].handle)
		self.player_sounds[pname] = nil
	end
end

function wagon:play_sound(pname, new_sound, replay)
	if not self.sounds or not self.sounds[new_sound] then return end

	local current = self.player_sounds[pname]
	if current and not replay and current.action == new_sound then
		return
	end

	self:stop_sound(pname)

	local variation = math.random(1, #self.sounds[new_sound])
	local sound_name = self.sounds[new_sound][variation].name

	local handle = core.sound_play({name = sound_name}, {
		object = self.object,
		to_player = pname,
		gain = SOUND_GAIN,
		loop = false,
		max_hear_distance = MAX_HEAR_DIST
	})

	self.player_sounds[pname] = {
		action = new_sound,
		variation = variation,
		timer = 0,
		handle = handle
	}
end

function wagon:tick_sound_timer(pname, dtime)
	local current = self.player_sounds[pname]
	if not current or not current.action:match("loop") then return false end

	current.timer = (current.timer or 0) + dtime

	if current.timer > self.sounds[current.action][current.variation].duration then
		current.timer = 0
		return true
	end

	return false
end

function wagon:handle_step_sounds(pname, target_loop, cur_vel, old_vel, dtime)
	self.player_sounds = self.player_sounds or {}
	local current = self.player_sounds[pname]

	--Train has stopped and it doesn't play the doors sounds
	local can_be_stopped = cur_vel == 0 and current and not current.action:match("door")
	if can_be_stopped then
		self:stop_sound(pname)
		return
	end

	-- Open/close doors
	if self.doors and (self.door_anim_timer or 0)<=0 then
		local train = self:train()
		local dstate = (train.door_open or 0) * (advtrains.wagons[self.id].wagon_flipped and -1 or 1)
		if dstate ~= self.door_state then
			if self.door_state == 0 then
				self:play_sound(pname, "door_open")
			else
				self:play_sound(pname, "door_close")
			end
			return
		end
	end

	-- Train is departing from station stop
	if old_vel <= 0 and cur_vel > old_vel then
		self:play_sound(pname, "depart")
	-- Train is stopping (probably because arriving at a station stop)
	elseif cur_vel < old_vel then
		self:play_sound(pname, "arrive")
	-- Train is moving with the constant velocity
	elseif cur_vel == old_vel and cur_vel > 0 then
		self:play_sound(pname, target_loop)
	end

	-- Repeat the cycle if the current sound is looped and not changed
	if self:tick_sound_timer(pname, dtime) then
		current = self.player_sounds[pname]
		self:play_sound(pname, current.action, true)
	end
end

local prev_on_activate = wagon.on_activate
function wagon:on_activate(sd_uid, dtime_s)
    if prev_on_activate then
        prev_on_activate(self, sd_uid, dtime_s)
    end

    self.player_sounds = {}
end

local prev_on_deactivate = wagon.on_deactivate
function wagon:on_deactivate(removal)
    if prev_on_deactivate then
        prev_on_deactivate(self, removal)
    end

    self:stop_all_sounds()
end

local prev_on_step = wagon.on_step
function wagon:on_step(dtime)
	-- handle the movement, arrival and depart sounds
	if self.sounds then
		local train = self:train()
		local cur_vel = train and train.velocity or 0
		local old_vel = self.old_velocity or 0

		if cur_vel > 0 then
			local pos = self.object:get_pos()

			local around_objs = core.get_objects_inside_radius(pos, MAX_HEAR_DIST)
			local active_players = {}

			local data = advtrains.wagons[self.id]
			local seats = data and data.seatp or {}
			local passengers = {}
			for _, pname in pairs(seats) do
				passengers[pname] = true
			end

			-- play loop_inside if the player sits, otherwise loop_outside if the distance from him to the wagon < MAX_HEAR_DIST/4, else loop
			for _, obj in ipairs(around_objs) do
				if obj:is_player() then
					local pname = obj:get_player_name()
					active_players[pname] = true

					local target_loop = "loop_outside"

					if passengers[pname] then
						target_loop = "loop_inside"
					else
						local ppos = obj:get_pos()
						local dist = vector.distance(pos, ppos)
						if dist <= MAX_HEAR_DIST / 4 then
							target_loop = "loop"
						end
					end

					self:handle_step_sounds(pname, target_loop, cur_vel, old_vel, dtime)
				end
			end

			-- If some player is out of MAX_HEAR_DIST, stop the sound
			if self.player_sounds then
				for pname, _ in pairs(self.player_sounds) do
					if not active_players[pname] then
						self:stop_sound(pname)
					end
				end
			end
		else
			self:stop_all_sounds()
		end
	end

	if prev_on_step then
        prev_on_step(self, dtime)
    end
end

core.log("action", "[advtrains_sounds_api] Successfully injected custom sound API into advtrains!")
