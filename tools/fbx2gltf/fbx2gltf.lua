package.path = "tools/fbx2gltf/?.lua;./?.lua;libs/?.lua;libs/?/?.lua;packages/glTF/?.lua"
package.cpath = "projects/msvc/vs_bin/x64/Debug/?.dll"

local fs = require "filesystem.local"
local util = require "util"

local convert = require "convert"

local files = {
	fs.path "packages/resources/meshes/build_boat_01.FBX"
}

-- for _, srcpath in ipairs {
-- 	fs.path "packages/resources/meshes",
-- } do
-- 	util.list_files(srcpath, ".fbx", {
-- 		[".git"] = true, 
-- 		[".repo"] = true, 
-- 		[".vscode"] = true,
-- 		[".vs"] = true
-- 	}, files)
-- end

local defconfig = {
	postconvert = function(filepath, scene)
		if util.is_PVPScene_obj(filepath) then
			util.reset_PVPScene_object_root_pos(filepath, scene)
		end
	end
}

convert(files, defconfig)