local skynet = require "skynet"
local sys = require "skillsys.skill_sys"
local lfs = require "lfs"
local env = require "env"
local dir = env.root .. "/lualib/skillsys"

local function load_luafile(name, subdir)
    local require_file = string.format("skillsys.%s.%s", subdir, name)
    return require(require_file)
end

local function init_findtarget()
    for file in lfs.dir(string.format("%s/findtarget", dir)) do
        if file ~= "." and file ~= ".." then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                assert(#name > 0)
                -- print(name,"init_findtarget")
                sys.register_findtarget(name, load_luafile(name, "findtarget"))
            end
        end
    end
end

local function init_effect()
    for file in lfs.dir(string.format("%s/effect", dir)) do
        if file ~= "." and file ~= ".." then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                assert(#name > 0)
                -- print(name,"init_effect")
                local id = assert(tonumber(name))
                sys.register_effect(id, load_luafile(name, "effect"))
            end
        end
    end
end

skynet.init(function()
    init_findtarget()
    init_effect()
end)

return sys
