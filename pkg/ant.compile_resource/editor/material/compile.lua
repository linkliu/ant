local lfs           = require "filesystem.local"
local fs            = require "filesystem"
local toolset       = require "editor.material.toolset"
local fxsetting     = require "editor.material.setting"
local setting       = import_package "ant.settings".setting
local serialize     = import_package "ant.serialize"
local depends       = require "editor.depends"
local config        = require "editor.config"
local parallel_task = require "editor.parallel_task"

local ENABLE_SHADOW<const>      = setting:get "graphic/shadow/enable"

local function DEF_FUNC() end

local SHADER_BASE<const>            = lfs.absolute(fs.path "/pkg/ant.resources/shaders":localpath())
local function shader_includes()
    return {
        SHADER_BASE,
    }
end

local SETTING_MAPPING = {
    lighting = function (v)
        if v == "off" then
            return "MATERIAL_UNLIT=1"
        end
    end,
    shadow_receive = function (v)
        if ENABLE_SHADOW and v == "on" then
            return "ENABLE_SHADOW=1"
        end
    end,
    os          = DEF_FUNC,
    renderer    = DEF_FUNC,
    stage       = DEF_FUNC,
    varying_path= DEF_FUNC,
    subsurface  = DEF_FUNC,
    shadow_cast = DEF_FUNC,
}

local IRRADIANCE_SH_BAND_NUM<const> = setting:get "graphic/ibl/irradiance_bandnum"
local ENABLE_IBL_LUT<const>         = setting:get "graphic/ibl/enable_lut"
local USE_CS_SKINNING<const> = setting:get "graphic/skinning/use_cs"

local enable_cs<const>      = setting:get "graphic/lighting/cluster_shading" ~= 0
local enable_bloom<const>   = setting:get "graphic/postprocess/bloom/enable"
local fxaa_setting<const>   = setting:data().graphic.postprocess.fxaa
local enable_ao<const>      = setting:get "graphic/ao/enable"
local enable_ao_bentnormal<const> = setting:get "graphic/ao/bent_normal"
local ao_qulity<const>      = enable_ao and setting:get "graphic/ao/qulity" or ""

-- local curve_world = setting:data().graphic.curve_world
-- local curve_world_type_macros<const> = {
--     view_sphere = 1,
--     cylinder = 2,
-- }

local function default_macros(setting)
    local m = {
        "ENABLE_SRGB_TEXTURE=1",
        "ENABLE_SRGB_FB=1",
        "ENABLE_IBL=1",
        "ENABLE_TEXTURE_GATHER=1",
    }

    if enable_cs then
        m[#m+1] = "HOMOGENEOUS_DEPTH=" .. (setting.hd and "1" or "0")
        m[#m+1] = "ORIGIN_BOTTOM_LEFT=" .. (setting.obl and "1" or "0")
        m[#m+1] = "CLUSTER_SHADING=1"
    end

    -- if curve_world.enable then
    --     m[#m+1] = "ENABLE_CURVE_WORLD=" .. curve_world_type_macros[curve_world.type]
    -- end

    if enable_bloom then
        m[#m+1] = "BLOOM_ENABLE=1"
    end

    if enable_ao then
        m[#m+1] = "ENABLE_SSAO=1"
        if enable_ao_bentnormal then
            m[#m+1] = "ENABLE_BENT_NORMAL=1"
        end

        if ao_qulity == "high" then
            m[#m+1] = "HIGH_QULITY_SPECULAR_AO=1"
            m[#m+1] = "HIGH_QULITY_NORMAL_RECONSTRUCT=1"
        end
    end

    if fxaa_setting.enable and not fxaa_setting.use_green_as_luma then
        m[#m+1] = "COMPUTE_LUMINANCE_TO_ALPHA=1"
    end

    if IRRADIANCE_SH_BAND_NUM then
        m[#m+1] = "IRRADIANCE_SH_BAND_NUM=" .. IRRADIANCE_SH_BAND_NUM
        m[#m+1] = "IRRADIANCE_SH_BAND_NUM=" .. IRRADIANCE_SH_BAND_NUM
    end

    if USE_CS_SKINNING then
        m[#m+1] = "CS_SKINNING=1"
    end

    if ENABLE_IBL_LUT then
        m[#m+1] = "ENABLE_IBL_LUT=1"
    end

    return m
end

local function is_pbr_material(mat)
    local is_default_func = (not mat.fs_code) or mat.fs_code:match('\n#include "common/default_fs_func.sh"\n')
    local is_glb_pbr
    local pbr
    if mat.fx.vs and mat.fx.fs then
        is_glb_pbr = mat.fx.vs:match "/pkg/ant.resources/shaders/dynamic_material/vs_default.sc" and
        mat.fx.fs:match "/pkg/ant.resources/shaders/dynamic_material/fs_default.sc"
        pbr = mat.fx.vs:match "/pkg/ant.resources/shaders/pbr/vs_pbr.sc" and mat.fx.fs:match "/pkg/ant.resources/shaders/pbr/fs_pbr.sc"
    end
    local glb_pbr = is_default_func and is_glb_pbr

    return glb_pbr or pbr
end

local PBR_TEXTURE_MACROS<const> = {
    s_basecolor = "HAS_BASECOLOR_TEXTURE=1",
    s_normal    = "HAS_NORMAL_TEXTURE=1",
    s_metallic_roughness="HAS_METALLIC_ROUGHNESS_TEXTURE=1",
    s_emissive="HAS_EMISSIVE_TEXTURE=1",
    s_occlusion="HAS_OCCLUSION_TEXTURE=1",
}

local function get_macros(setting, mat)
    local macros = default_macros(setting)
    for k, v in pairs(mat.fx.setting) do
        local f = SETTING_MAPPING[k]
        if f == nil then
            macros[#macros+1] = k .. '=' .. v
        else
            local t = type(f)
            if t == "function" then
                local tt = f(v)
                if tt then
                    macros[#macros+1] = tt
                end
            elseif t == "string" then
                macros[#macros+1] = f
            else
                error("invalid type")
            end
        end
    end

    if is_pbr_material(mat) then
        local properties = mat.properties
        for texname, m in pairs(PBR_TEXTURE_MACROS) do
            if properties[texname] then
                macros[#macros+1] = m
            end
        end
    end
    table.sort(macros)
	return macros
end

local function compile_debug_shader(platform, renderer)
    if platform == "windows" and renderer:match "direct3d" then
        return true
    elseif platform == "windows" and renderer:match "vulkan" then
        return true
    end
end

local function readfile(filename)
	local f <close> = assert(lfs.open(filename, "r"))
	return f:read "a"
end

local function writefile(filename, data)
	local f<close> = assert(lfs.open(filename, "wb"))
	f:write(serialize.stringify(data))
end

local function mergeCfgSetting(fx, localpath)
    if fx.setting == nil then
        fx.setting = {}
    elseif type(fx.setting) == "string" then
        fx.setting = serialize.parse(fx.setting, readfile(localpath(fx.setting)))
    else
        assert(type(fx.setting) == "table")
    end

    fx.setting = fxsetting.adddef(fx.setting)
    if fx.cs then
        fx.setting["lighting"]          = 'off'
        fx.setting["shadow_receive"]    = 'off'
    end
end

local DEF_VARYING_FILE<const> = SHADER_BASE / "common/varying_def.sh"
local DEF_VARYING_FILE_GLB<const> = SHADER_BASE / "common/varying.def.sc"
local DEF_VS_FILE<const> = SHADER_BASE / "dynamic_material/vs_default.sc"
local DEF_FS_FILE<const> = SHADER_BASE / "dynamic_material/fs_default.sc"

local function replace_custom_func(default_file, temp_file, mat, stage)
    local file_read<close> = assert(lfs.open(default_file, "r"))
    local file_read_compile = file_read:read "a"
    if stage == "vs" then
        if not mat.vs_code then mat.vs_code = '\n#include "common/default_vs_func.sh"\n' end
        file_read_compile = file_read_compile:gsub("%s*$$CUSTOM_VS_FUNC$$%s*", mat.vs_code)
    elseif stage == "fs" then
        if not mat.fs_code then mat.fs_code = '\n#include "common/default_fs_func.sh"\n' end
        file_read_compile = file_read_compile:gsub("%s*$$CUSTOM_FS_FUNC$$%s*", mat.fs_code)
    end
    local file_write<close> = assert(lfs.open(temp_file, "wb"))
    file_write:write(file_read_compile)
end

local function compile(tasks, deps, mat, output, localpath)
    local setting = config.get "material".setting
    lfs.remove_all(output)
    lfs.create_directories(output)
    local fx = mat.fx
    mergeCfgSetting(fx, localpath)
    writefile(output / "main.cfg", mat)
    for _, stage in ipairs {"vs","fs","cs"} do
        local temp_file = output / (stage..".sc")
        local default_file
        if fx[stage] then
            local is_glb_mat = (mat.fx[stage] == "/pkg/ant.resources/shaders/dynamic_material/fs_default.sc") or (mat.fx[stage] == "/pkg/ant.resources/shaders/dynamic_material/vs_default.sc")
            if is_glb_mat then
                parallel_task.add(tasks, function ()
                    if stage == "vs" then
                        default_file = DEF_VS_FILE
                    else
                        default_file = DEF_FS_FILE
                    end
                    
                    replace_custom_func(default_file, temp_file, mat, stage)
                    
                    local varying_path = fx.varying_path
                    if varying_path then
                        varying_path = localpath(varying_path)
                    else
                        if not lfs.exists(default_file:parent_path() / "varying.def.sc") then
                            varying_path = DEF_VARYING_FILE_GLB
                        end
                    end
                    local ok, res = toolset.compile {
                        platform = setting.os,
                        renderer = setting.renderer,
                        input = temp_file,
                        output = output / (stage..".bin"),
                        includes = shader_includes(),
                        stage = stage,
                        varying_path = varying_path,
                        macros = get_macros(setting, mat),
                        debug = compile_debug_shader(setting.os, setting.renderer),
                    }
                    if not ok then
                        error("compile failed: " .. output:string() .. "\n" .. res)
                    end
                    depends.append(deps, res)
                    --os.remove(tostring(temp_file))
                end)
            else
                parallel_task.add(tasks, function ()
                    local inputpath = localpath(fx[stage])
                    local varying_path = fx.varying_path
                    if varying_path then
                        varying_path = localpath(varying_path)
                    else
                        if not lfs.exists(inputpath:parent_path() / "varying.def.sc") then
                            varying_path = DEF_VARYING_FILE
                        end
                    end
                    local ok, res = toolset.compile {
                        platform = setting.os,
                        renderer = setting.renderer,
                        input = inputpath,
                        output = output / (stage..".bin"),
                        includes = shader_includes(),
                        stage = stage,
                        varying_path = varying_path,
                        macros = get_macros(setting, mat),
                        debug = compile_debug_shader(setting.os, setting.renderer),
                    }
                    if not ok then
                        error("compile failed: " .. output:string() .. "\n" .. res)
                    end
                    depends.append(deps, res)
                end) 
            end
        end
    end
end

return compile
