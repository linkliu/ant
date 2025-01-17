local ecs   = ...
local world = ecs.world
local w     = world.w

local setting   = import_package "ant.settings"
local bloom_sys = ecs.system "bloom_system"
local fbmgr     = require "framebuffer_mgr"

if not setting:get "graphic/postprocess/bloom/enable" then
    return
end

local hwi       = import_package "ant.hwi"

local ipps      = ecs.require "ant.render|postprocess.stages"
local ips       = ecs.require "ant.render|postprocess.pyramid_sample"
local iviewport = ecs.require "viewport.state"
local queuemgr  = ecs.require "queue_mgr"

local math3d    = require "math3d"

local DOWNSAMPLE_NAME<const> = "bloom_downsample"
local UPSAMPLE_NAME<const> = "bloom_upsample"

local BLOOM_DS_VIEWID <const> = hwi.viewid_get "bloom_ds1"
local BLOOM_US_VIEWID <const> = hwi.viewid_get "bloom_us1"
local BLOOM_PARAM = math3d.ref(math3d.vector(0, setting:get "graphic/postprocess/bloom/inv_highlight", setting:get "graphic/postprocess/bloom/threshold", 0))

local MIP_COUNT<const> = 4

local pyramid_sampleeid
local function register_queues()
    for i=1, MIP_COUNT do
        queuemgr.register_queue(DOWNSAMPLE_NAME..i)
        queuemgr.register_queue(UPSAMPLE_NAME..i)
    end

    local pyramid_sample = {
        downsample      = ips.init_sample(MIP_COUNT, DOWNSAMPLE_NAME,   BLOOM_DS_VIEWID),
        upsample        = ips.init_sample(MIP_COUNT, UPSAMPLE_NAME,     BLOOM_US_VIEWID),
        sample_params   = BLOOM_PARAM,
    }

    local fbs
    pyramid_sampleeid, fbs = ips.create(pyramid_sample, iviewport.viewrect)
    assert(fbs)
    ipps.stage "bloom".output = fbmgr.get_rb(fbs[#fbs], 1).handle
end

local function update_bloom_handle(ps)
    local lasteid = ps.upsample[#ps.upsample].queue
    local q = world:entity(lasteid, "render_target:in")
    if q then
        ipps.stage "bloom".output = fbmgr.get_rb(q.render_target.fb_idx, 1).handle
    end
end

function bloom_sys:init()
    register_queues()
end

function bloom_sys:init_world()
    local e = world:entity(pyramid_sampleeid, "pyramid_sample:in")
    update_bloom_handle(e.pyramid_sample)
end

local vr_mb = world:sub{"view_rect_changed", "main_queue"}

function bloom_sys:bloom()
    local e = world:entity(pyramid_sampleeid, "pyramid_sample:in")
    ips.do_pyramid_sample(e, ipps.input "bloom")

    for _, _, vr in vr_mb:unpack() do
        ips.update_viewrect(e, vr)
        update_bloom_handle(e.pyramid_sample)
        break
    end

end
