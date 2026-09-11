-- wagon.lua
if not core.global_exists("advtrains") then
    core.log("error", "[advtrains_sounds_api] advtrains mod is missing!")
    return
end

local SOUND_GAIN = 3.0
local MAX_HEAR_DIST = 80

local wagon = getmetatable(advtrains.wagon_prototypes["advtrains:wagon_placeholder"]).__index

wagon.sounds = {
	door_open = {name="advtrains_train_door_chime", duration=3},
	door_close = {name="advtrains_train_door_chime", duration=3},
	depart = {name="advtrains_train_depart", duration=9},
	arrive = {name="advtrains_train_arrive", duration=0.8},
	loop = {name="advtrains_train_loop", duration=18},
	loop_outside = {name="advtrains_train_loop_outside", duration=11}
}

function wagon:stop_sound()
	if self.sound_handle then
		core.sound_stop(self.sound_handle)
		self.sound_handle = nil
		self.cur_sound = nil
	end
end

function wagon:play_sound(new_sound, replay)
	if not self.sounds or not self.sounds[new_sound] then return end
	if not replay and self.cur_sound == new_sound then return end

	core.debug("play_sound: " .. new_sound)
	self:stop_sound()

	self.sound_timer = 0
	self.cur_sound = new_sound
	self.sound_handle = core.sound_play({
		name=self.sounds[self.cur_sound].name},
		{
			object = self.object,
			gain=SOUND_GAIN,
			loop=false,
			max_hear_distance=MAX_HEAR_DIST
		})
end

function wagon:tick_sound_timer(dtime)
	if not self.cur_sound then return false end

	self.sound_timer = (self.sound_timer or 0) + dtime

	if self.sound_timer > self.sounds[self.cur_sound].duration then
		self.sound_timer = 0
		return true
	end

	return false
end

function wagon:handle_step_sounds(play_loop, cur_vel, old_vel, dtime)
	--Train has stopped
	if cur_vel == 0 then
		self:stop_sound()
		return
	end

	-- Train is departing from station stop
	if old_vel <= 0 and cur_vel > old_vel then
		core.debug("handle_step_sounds: depart")
		self:play_sound("depart")
	-- Train is stopping (probably because arriving at a station stop)
	elseif cur_vel < old_vel then
		core.debug("handle_step_sounds: arrive")
		self:play_sound("arrive")
	-- Train is moving with the constant velocity
	elseif old_vel == cur_vel and cur_vel > 0 then
		core.debug("handle_step_sounds:" .. play_loop)
		self:play_sound(play_loop)
	end

	-- Repeat the cycle if the current sound is not changed
	if self:tick_sound_timer(dtime) then
		self:play_sound(self.cur_sound, true)
	end
end

local prev_on_activate = wagon.on_activate
function wagon:on_activate(sd_uid, dtime_s)
    if prev_on_activate then
        prev_on_activate(self, sd_uid, dtime_s)
    end

    self.sound_timer = 0
end

local prev_on_deactivate = wagon.on_deactivate
function wagon:on_deactivate(removal)
    if prev_on_deactivate then
        prev_on_deactivate(self, removal)
    end

    self:stop_sound()
end

local prev_on_step = wagon.on_step
function wagon:on_step(dtime)
    -- handle the movement, arrival and depart sounds
	if self.sounds then
		local play_loop = "loop_outside"
		local train = self:train()

		if train.velocity > 0 then
			local pos = self.object:get_pos()
			local around_objs = core.get_objects_inside_radius(pos, MAX_HEAR_DIST / 4)

			for _, obj in ipairs(around_objs) do
				if obj:is_player() then
					play_loop = "loop"
					break
				end
			end
		end
		self:handle_step_sounds(play_loop, train.velocity, self.old_velocity or 0, dtime)
	end

	if prev_on_step then
        prev_on_step(self, dtime)
    end
end

core.log("action", "[advtrains_sounds_api] Successfully injected custom sound API into advtrains!")
