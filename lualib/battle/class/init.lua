local lfs = require "lfs"
local env = require "env"
local fsm_state = require "battle.fsm.state"

local function load_module(classname, ...)
    local class = {}
    local path = string.format("%s/lualib/battle/class/%s", env.root, classname)
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." and file ~= "init.lua" then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                local m = require(string.format("battle.class.%s.%s", classname,
                    name))
                for k, v in pairs(m) do class[k] = v end
            end
        end
    end
    local mlist = {...}
    if next(mlist) then
        for _, m in ipairs(mlist) do
            for k, v in pairs(m) do class[k] = v end
        end
    end
    return class
end

local function create_class(classname, ...)
    local class = load_module(classname, ...)
    class.__index = class
    function class:new(o)
        o = o or {}
        o.__valid__ = true
        o.FSMstate = fsm_state.idle
        setmetatable(o, self)
        return o
    end

    return class
end

return create_class
