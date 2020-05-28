local thread = require "thread"
local fs = require "filesystem"

local function read_file(filename)
    local f = assert(fs.open(filename, "rb"))
    local c = f:read "a"
    f:close()
    return c
end
return {
    loader = function (filename)
        local c = read_file(filename)
        return thread.unpack(c)
    end,
    unloader = function (res)
    end
}