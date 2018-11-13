local rdebug = require 'remotedebug'

local function event(name, level, ...)
    local r
    rdebug.probe(name)
    return r
end

local function start_hook()
    local _print = print
    function print(...)
        if not event('print', 1, ...) then
            _print(...)
        end
    end

    local _xpcall = xpcall
    function xpcall(f, msgh, ...)
        return _xpcall(f, function(msg)
            event('exception', 2, 'xpcall', msg)
            return msgh(msg)
        end, ...)
    end

    local _pcall = pcall
    function pcall(f, ...)
        return _xpcall(f, function(msg)
            event('exception', 2, 'pcall', msg)
            return msg
        end, ...)
    end
    
    local _coroutine_resume = coroutine.resume
    function coroutine.resume(co, ...)
        event('coroutine', 1, co)
        return _coroutine_resume(co, ...)
    end
end

local function start_master(io)
    local master = require 'debugger.backend.master'
    if master.init(io) then
        return master.update
    end
end

local function start_worker(wait)
    start_hook()
    rdebug.start([[
        package.searchers[3] = ...
        package.searchers[4] = nil
        dofile 'firmware/init_thread.lua'
        require 'debugger.backend.worker'
    ]], package.searchers[3])
    if wait then
        event('wait_client', 1, false)
    end
    return function()
        event 'update'
    end
end

local function start_init()
    local thread = require 'thread'
    thread.newchannel 'DbgMaster'
end

local function start_all(wait)
    start_init()
    start_hook()
    rdebug.start([[
        package.searchers[3] = ...
        package.searchers[4] = nil
        dofile 'firmware/init_thread.lua'
        require 'debugger.backend.worker'
    ]], package.searchers[3])
    if wait then
        event('wait_client', 1, true)
    end
    return function()
        event 'update_all'
    end
end

return {
    start_master = start_master,
    start_worker = start_worker,
    start_init = start_init,
    start_all = start_all,
}
