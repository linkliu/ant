-- luacheck: globals log bullet
local log = log and log(...) or print
local ecs = require "ecs"

--local elog = require "editor.log"
--local db = require "debugger"

-- --windows dir
-- asset.insert_searchdir(1, "D:/Engine/ant/assets")
-- --mac dir
-- asset.insert_searchdir(2, "/Users/ejoy/Desktop/Engine/ant/assets")


local util = {}
util.__index = util

local world = nil

local bullet_module = require "bullet"
bullet = bullet_module.new()

function util.start_new_world(input_queue, fbw, fbh, modules, module_searchdirs)
	if input_queue == nil then		
		log("input queue is not privided, no input event will be received!")
	end

	local engine_searchdir = "engine/libs/?.lua;engine/libs/?/?.lua"	-- read local libs before engine/libs	
	local searchdirs = module_searchdirs and (module_searchdirs .. ';' .. engine_searchdir) or engine_searchdir
	world = ecs.new_world {
		modules = modules,
		module_path = searchdirs,
		update_order = {"timesystem", "message_system"},
		update_bydepend = true,
		args = { 
			mq = input_queue, 
			fb_size={w=fbw, h=fbh},
			physic_world = bullet:new_world(),
		},
    }
    return world
end

return util
