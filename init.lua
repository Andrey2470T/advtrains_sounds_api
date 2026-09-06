-- wagon.lua
-- Holds all logic related to wagons
-- From now on, wagons are, just like trains, just entries in a table
local sound_params = {
	gain=3.0,
	loop=true,
	max_hear_distance=80
}

local SOUND_DELTA = 2 -- in sec

local wagon={
	collisionbox = {-0.5,-0.5,-0.5, 0.5,0.5,0.5},
	--physical = true,
	visual = "mesh",
	mesh = "wagon.b3d",
	visual_size = {x=1, y=1},
	textures = {"black.png"},
	is_wagon=true,
	wagon_span=1,--how many index units of space does this wagon consume
	wagon_width=3, -- Wagon width in meters
	has_inventory=false,
	static_save=false,
	sounds = {
		door_open = "advtrains_train_door_chime",
		door_close = "advtrains_train_door_chime",
		depart = "advtrains_train_depart",
		arrive = "advtrains_train_arrive",
		loop = "advtrains_train_loop",
		loop_outside = "advtrains_train_loop_outside"
	}
}

function wagon:on_deactivate(removal)
	if self.step_handle then
		minetest.sound_stop(self.step_handle)
		self.step_handle = nil
		self.cur_step_sound = nil
	end
end

function wagon:on_step(dtime)
		if not self:ensure_init() then return end

		if advtrains.is_no_action() then
			self.object:remove()
			return
		end

		local t=os.clock()
		local pos = self.object:get_pos()
		local data = advtrains.wagons[self.id]

		if not pos then
			--atdebug("["..self.id.."][fatal] missing position (object:get_pos() returned nil)")
			return
		end

		if not data.seatp then
			data.seatp={}
		end
		if not self.seatpc then
			self.seatpc={}
		end

		local train=self:train()

		local is_in_loaded_area = advtrains.is_node_loaded(pos)

		--custom on_step function
		if self.custom_on_step then
			self:custom_on_step(dtime, data, train)
		end

		--driver control
		for seatno, seat in ipairs(self.seats) do
			local pname=data.seatp[seatno]
			local driver=pname and minetest.get_player_by_name(pname)
			local has_driverstand = pname and advtrains.check_driving_couple_protection(pname, data.owner, data.whitelist)
			has_driverstand = has_driverstand and self:is_driver_stand(seat)
			if has_driverstand and driver then
				advtrains.update_driver_hud(driver:get_player_name(), self:train(), data.wagon_flipped)
			elseif driver then
				--only show the inside text
				local inside=self:train().text_inside or ""
				advtrains.set_trainhud(driver:get_player_name(), inside)
			end
			if driver and driver:get_player_control_bits()~=self.seatpc[seatno] then
				local pc=driver:get_player_control()
				self.seatpc[seatno]=driver:get_player_control_bits()

				if has_driverstand then
					--regular driver stand controls
					advtrains.on_control_change(pc, self:train(), data.wagon_flipped)
					--bordcom
					if pc.sneak and pc.jump then
						self:show_bordcom(data.seatp[seatno])
					end
					--sound horn when required
					if self.horn_sound and pc.aux1 and not pc.sneak and not self.horn_handle then
						self.horn_handle = minetest.sound_play(self.horn_sound, {
							object = self.object,
							gain = 1.0, -- default
							max_hear_distance = 128, -- default, uses an euclidean metric
							loop = true,
						})
					elseif not pc.aux1 and self.horn_handle then
						minetest.sound_stop(self.horn_handle)
						self.horn_handle = nil
					end
				else
					-- If on a passenger seat and doors are open, get off when W or D pressed.
					local pass = data.seatp[seatno] and minetest.get_player_by_name(data.seatp[seatno])
					if pass and self:train().door_open~=0 then
					local pc=pass:get_player_control()
						if pc.up or pc.down then
							self:get_off(seatno)
						end
					end
				end
				if pc.aux1 and pc.sneak then
					self:get_off(seatno)
				end
			end
		end

		--check infotext
		local outside=train.text_outside or ""
		if setting_show_ids then
			outside = outside .. "\nT:" .. data.train_id .. " W:" .. self.id .. " O:" .. data.owner
		end


		--show off-track information in outside text instead of notifying the whole server about this
		if train.off_track then
			outside = outside .."\n"..S("!!! Train off track !!!")
		end

		-- liquid container: display liquid contents in infotext
		if self.techage_liquid_capacity then
			if data.techage_liquid and data.techage_liquid.name then
				outside = outside .."\n"..S("Liquid: ")..data.techage_liquid.name..", "..data.techage_liquid.amount..S(" units")
			else
				outside = outside .."\n"..S("Liquid: empty")
			end
		end

		if self.infotext_cache~=outside  then
			self.object:set_properties({infotext=outside})
			self.infotext_cache=outside
		end

		local fct=data.wagon_flipped and -1 or 1

		--door animation
		if self.doors then
			if (self.door_anim_timer or 0)<=0 then
				local dstate = (train.door_open or 0) * fct
				if dstate ~= self.door_state then
					local at
					--meaning of the train.door_open field:
					-- -1: left doors (rel. to train orientation)
					--  0: closed
					--  1: right doors
					--this code produces the following behavior:
					-- if changed from 0 to +-1, play open anim. if changed from +-1 to 0, play close.
					-- if changed from +-1 to -+1, first close and set 0, then it will detect state change again and run open.
					if self.door_state == 0 then
						if self.sounds and self.sounds.door_open then
							minetest.sound_play(self.sounds.door_open, {object = self.object})
						end
						at=self.doors.open[dstate]
						self.object:set_animation(at.frames, at.speed or 15, at.blend or 0, false)
						self.door_state = dstate
					else
						if self.sounds and self.sounds.door_close then
							minetest.sound_play(self.sounds.door_open, {object = self.object})
						end
						at=self.doors.close[self.door_state or 1]--in case it has not been set yet
						self.object:set_animation(at.frames, at.speed or 15, at.blend or 0, false)
						self.door_state = 0
					end
					self.door_anim_timer = at.time
				end
			else
				self.door_anim_timer = (self.door_anim_timer or 0) - dtime
			end
		end

		--for path to be available. if not, skip step
		if not train.path or train.no_step then
			self.object:set_velocity({x=0, y=0, z=0})
			self.object:set_acceleration({x=0, y=0, z=0})
			return
		end
		if not data.pos_in_train then
			return
		end

		-- Calculate new position, yaw and direction vector
		-- note: "index" is needed to be the center index, required by door code
		local index = advtrains.path_get_index_by_offset(train, train.index, -data.pos_in_train)
		local pos, yaw, npos, npos2, vdir

		-- use new position logic?
		if self.wheel_positions then
			-- request two positions, calculate difference and yaw from this
			-- depending on flipstate, need to invert wheel pos indices -> wheelpos * fct
			local index1 = advtrains.path_get_index_by_offset(train, index, self.wheel_positions[1] * fct)
			local index2 = advtrains.path_get_index_by_offset(train, index, self.wheel_positions[2] * fct)
			local pos1 = advtrains.path_get_interpolated(train, index1)
			local pos2 = advtrains.path_get_interpolated(train, index2)
			npos = advtrains.path_get(train, atfloor(index)) -- need npos just for node loaded check
			-- calculate center of 2 positions and vdir vector
			-- if wheel positions are asymmetric, needs to weight by the difference!
			local fact = self.wheel_positions[1] / (self.wheel_positions[1]-self.wheel_positions[2])
			pos = {x=pos1.x-(pos1.x-pos2.x)*fact, y=pos1.y-(pos1.y-pos2.y)*fact, z=pos1.z-(pos1.z-pos2.z)*fact}
			if data.wagon_flipped then
				vdir = vector.normalize(vector.subtract(pos2, pos1))
			else
				vdir = vector.normalize(vector.subtract(pos1, pos2))
			end
			yaw = math.atan2(-vdir.x, vdir.z)
		else
			--old position logic (for small wagons): use center index and just get position
			pos, yaw, npos, npos2 = advtrains.path_get_interpolated(train, index)
			vdir = vector.normalize(vector.subtract(npos2, npos))
		end

		--automatic get_on
		--needs to know index and path
		if train.velocity==0 and self.door_entry and train.door_open and train.door_open~=0 then
			--using the mapping created by the trainlogic globalstep
			local platform_offset = math.floor(self.wagon_width / 2)
			for i, ino in ipairs(self.door_entry) do
				--fct is the flipstate flag from door animation above
				local aci = advtrains.path_get_index_by_offset(train, index, ino*fct)
				local ix1, ix2 = advtrains.path_get_adjacent(train, aci)
				-- the two wanted positions are ix1 and ix2 + (2nd-1st rotated by 90deg)
				-- (x z) rotated by 90deg is (-z x)  (http://stackoverflow.com/a/4780141)
				local add = {
					x = atround((ix2.z-ix1.z)*train.door_open),
					y = 0,
					z = atround((ix1.x-ix2.x)*train.door_open)
				}
				for offset = (platform_offset == 0 and 0 or 1), platform_offset do
					local scaled_add = vector.multiply(add, offset)
					local pts1=vector.add(ix1, scaled_add)
					local pts2=vector.add(ix2, scaled_add)
					if minetest.get_item_group(minetest.get_node(pts1).name, "platform")>0 then
						local ckpts={
							pts1,
							pts2,
							vector.add(pts1, {x=0, y=1, z=0}),
							vector.add(pts2, {x=0, y=1, z=0}),
						}
						for _,ckpos in ipairs(ckpts) do
							local cpp=minetest.pos_to_string(ckpos)
							if advtrains.playersbypts[cpp] then
								self:on_rightclick(advtrains.playersbypts[cpp])
							end
						end
					end
				end
			end
		end

		--checking for environment collisions(a 3x3 cube around the center)
		if not IGNORE_WORLD and is_in_loaded_area and not train.recently_collided_with_env then
			local collides=false
			local exh = self.extent_h or 1
			local exv = self.extent_v or 2
			for x=-exh,exh do
				for y=0,exv do
					for z=-exh,exh do
						local node=minetest.get_node_or_nil(vector.add(npos, {x=x, y=y, z=z}))
						if (advtrains.train_collides(node)) then
							collides=true
						end
					end
				end
			end
			if collides then
				-- screw collision mercy
				train.recently_collided_with_env=true
				train.velocity=0
				advtrains.atc.train_reset_command(train)
			end
		end

		-- Spawn discouple object when train stands, in all other cases remove it.
		-- FIX: Need to do this after the yaw calculation
		if train.velocity==0 and is_in_loaded_area and data.pos_in_trainparts and data.pos_in_trainparts>1 then
			if not self.discouple or not self.discouple.object:get_yaw() then
				atprint(self.id,"trying to spawn discouple")
				local dcpl_pos = vector.add(pos, {y=0, x=-math.sin(yaw)*self.wagon_span, z=math.cos(yaw)*self.wagon_span})
				local object=minetest.add_entity(dcpl_pos, "advtrains:discouple")
				if object then
					local le=object:get_luaentity()
					le.wagon=self
					--box is hidden when attached, so unuseful.
					--object:set_attach(self.object, "", {x=0, y=0, z=self.wagon_span*10}, {x=0, y=0, z=0})
					self.discouple=le
				end
			end
		else
			if self.discouple and self.discouple.object:get_yaw() then
				self.discouple.object:remove()
				atprint(self.id," removing discouple")
			end
		end

		-- object yaw (corrected by flipstate)
		local oyaw = yaw
		if data.wagon_flipped then
			oyaw = yaw + math.pi
		end

		--FIX: use index of the wagon, not of the train.
		local velocity = train.velocity * advtrains.global_slowdown
		local acceleration = (train.acceleration or 0) * (advtrains.global_slowdown*advtrains.global_slowdown)
		local velocityvec = vector.multiply(vdir, velocity)
		local accelerationvec = vector.multiply(vdir, acceleration)

		-- this timer runs off every 2 seconds.
		self.updatepct_timer=(self.updatepct_timer or 0)-dtime
		local updatepct_timer_elapsed = self.updatepct_timer<=0

		if updatepct_timer_elapsed then
			--restart timer
			self.updatepct_timer=2
			-- perform checks that are not frequently needed

			-- unload entity if out of range (because relevant pr won't be merged in engine)
			-- This is a WORKAROUND!
			local players_in = false
			for sno,pname in pairs(data.seatp) do
				if minetest.get_player_by_name(pname) then
					-- Fix: If the RTT is too high, a wagon might be recognized out of range even if a player sits in it
					-- (client updates position not fast enough)
					players_in = true
					break
				end
			end
			if not players_in then
				if advtrains.wagon_outside_range(pos) then
					--atdebug("wagon",self.id,"unloading (too far away)")
                    -- Workaround until minetest engine deletes attached sounds
                    if self.sound_loop_handle then
                        minetest.sound_stop(self.sound_loop_handle)
                    end
					self.object:remove()
				end
			end
		end

		if not self.old_velocity_vector
				or not vector.equals(velocityvec, self.old_velocity_vector)
				or not self.old_acceleration_vector
				or not vector.equals(accelerationvec, self.old_acceleration_vector)
				or self.old_yaw~=oyaw
				or updatepct_timer_elapsed then--only send update packet if something changed

			self.object:set_pos(pos)
			self.object:set_velocity(velocityvec)
			self.object:set_acceleration(accelerationvec)

			if #self.seats > 0 and self.old_yaw ~= oyaw then
				if not self.player_yaw then
					self.player_yaw = {}
				end
				if not self.old_yaw then
					self.old_yaw=oyaw
				end
				for _,name in pairs(data.seatp) do
					local p = minetest.get_player_by_name(name)
					if p then
						if not self.turning then
							-- save player looking direction offset
							self.player_yaw[name] = p:get_look_horizontal()-self.old_yaw
						end
						-- set player looking direction using calculated offset
						p:set_look_horizontal((self.player_yaw[name] or 0)+oyaw)
					end
				end
				self.turning = true
			elseif self.old_yaw == oyaw then
				-- train is no longer turning
				self.turning = false
			end

			if self.object.set_rotation then
                local pitch = math.atan2(vdir.y, math.hypot(vdir.x, vdir.z))
                if data.wagon_flipped then
                    pitch = -pitch
                end
                self.object:set_rotation({x=pitch, y=oyaw, z=0})
            else
                self.object:set_yaw(oyaw)
            end

			if self.update_animation then
				self:update_animation(train.velocity, self.old_velocity)
			end
			if self.custom_on_velocity_change then
				self:custom_on_velocity_change(train.velocity, self.old_velocity or 0, dtime)
			end
			-- handle the movement, arrival and depart sounds
			if self.sounds then
				if train.velocity > 0 and train.velocity == self.old_velocity then
					self.sound_timer = self.sound_timer or 0
					self.sound_timer = self.sound_timer + dtime
					if self.sound_timer > SOUND_DELTA then
						self.sound_timer = 0
						self.play_loop = "loop_outside"
						local around_objs = core.get_objects_inside_radius(pos, sound_params.max_hear_distance / 4)

						for _, player in ipairs(around_objs) do
							if player:is_player() then
								self.play_loop = "loop"
								break
							end
						end
					end
				end
				self:handle_step_sounds(train.velocity, self.old_velocity or 0)
			end
			-- remove discouple object, because it will be in a wrong location
			if not updatepct_timer_elapsed and self.discouple then
				self.discouple.object:remove()
			end
		end


		self.old_velocity_vector=velocityvec
		self.old_velocity = train.velocity
		self.old_acceleration_vector=accelerationvec
		self.old_yaw=oyaw
		atprintbm("wagon step", t)
end

local function change_step_sound(self, new_step_sound)
	if not self.sounds or not self.sounds[new_step_sound] then return end
	if self.cur_step_sound == new_step_sound then return end

	if self.step_handle then
		minetest.sound_stop(self.step_handle)
	end

	self.cur_step_sound = new_step_sound
	self.step_handle = minetest.sound_play({
		name=self.sounds[new_step_sound]},
		{
			object = self.object,
			gain=sound_params.gain,
			loop=sound_params.loop,
			max_hear_distance=sound_params.max_hear_distance
		})
end

function wagon:handle_step_sounds(cur_vel, old_vel)
	--Train has stopped
	if cur_vel == 0 and self.step_handle then
		minetest.sound_stop(self.step_handle)
		self.step_handle = nil
		self.cur_step_sound = nil
		return
	end

	-- Train is departing from station stop
	if old_vel <= 0 and cur_vel > old_vel then
		change_step_sound(self, "depart")
		return
	end

	-- Train is stopping (probably because arriving at a station stop)
	if cur_vel < old_vel then
		change_step_sound(self, "arrive")
		return
	end
	-- Train is moving with the constant velocity
	if old_vel == cur_vel and cur_vel > 0 then
		change_step_sound(self, self.play_loop)
	end
end
