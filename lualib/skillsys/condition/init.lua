local skynet = require "skynet"
local lfs = require "lfs"
local env = require "env"
local dir = env.root .. "/lualib/skillsys"

local CBS = {}

skynet.init(function()
    for file in lfs.dir(string.format("%s/condition", dir)) do
        if file ~= "." and file ~= ".." and file ~= "init.lua" then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                local id = assert(tonumber(name))
                CBS[id] = require(string.format("skillsys.condition.%s", name))
            end
        end
    end
end)

return function(bctx, self, tobj, ctx, parm, ...)
    local ctype = parm[1]
    local cb = CBS[ctype]
    return cb(bctx, self, tobj, ctx, {table.unpack(parm, 2)}, ...)
end
