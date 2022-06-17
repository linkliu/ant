local ecs   = ...
local world = ecs.world
local w     = world.w

-- keyframe
local ika = ecs.interface "ikeyframe"
function ika.create(frames)
    return ecs.create_entity{
        policy = {
            "ant.animation|keyframe",
            "ant.general|name",
        },
        data = {
            keyframe = {
				frames = frames or {},
				play_state = {}
            },
            name = "keyframe"
        }
    }
end

function ika.add(e, time_ms, value, idx)
    local frames = e.keyframe.frames
	idx = idx or #frames+1
	table.insert(frames, idx, {
        value	 	= value,
        time 		= time_ms,	--ms
    })
end

function ika.remove(e, idx)
    idx = idx or #e.keyframe.frames
    table.remove(e.keyframe.frames, idx)
end

function ika.clear(e)
    e.keyframe.frames = {}
end

function ika.stop(e)
	local ps = e.keyframe.play_state
	ps.playing = false
end

function ika.play(e, desc)
	ika.stop(e)
	local ps = e.keyframe.play_state
	ps.loop = desc.loop
	ps.forwards = desc.forwards
	ps.current_time = 0
	ps.playing = true
end

local ma_sys = ecs.system "keyframe_system"
function ma_sys:component_init()
    -- for e in w:select "INIT keyframe:in" do
    --     e.keyframe.play_state = {
    --         current_time = 0,
    --         target_e = nil,
	-- 		loop = false,
	-- 		playing = false
    --     }
    -- end
end

local timer = ecs.import.interface "ant.timer|itimer"

local function step_keyframe(kf_anim, delta_time)
	if not kf_anim.play_state.playing then
		return
	end
	local frames = kf_anim.frames
	if #frames < 2 then return end

	local play_state = kf_anim.play_state
	local lerp = function (v0, v1, f)
		if type(v0) == "table" then
			local count = #v0
			local ret = {}
			for i = 1, count do
				ret[#ret + 1] = v0[i] + (v1[i] - v0[i]) * f
			end
			return ret
		else
			return v0 + (v1 - v0) * f
		end
	end
	local function get_value(time)
		local frame_count = #frames
		for i = 1, frame_count do
			if time < frames[i].time then
				local factor = math.min((time - frames[i-1].time) / (frames[i].time - frames[i-1].time), 1.0)
				return lerp(frames[i-1].value, frames[i].value, factor), false
			elseif i == frame_count then
				return frames[i].value, true
			end
		end
	end

	local value, last = get_value(play_state.current_time)
	play_state.current_value = value
	play_state.current_time = play_state.current_time + delta_time
	if last then
		if play_state.loop then
			play_state.current_time = 0
		else
			play_state.playing = false
			play_state.current_value = play_state.forwards and frames[#frames].value or frames[1].value
		end
	end
end

function ma_sys.data_changed()
	local delta_time = timer.delta()
	for e in w:select "keyframe:in" do
		step_keyframe(e.keyframe, delta_time)
	end
end