local lfs = require "lfs"
local env = require "env"
local root = env.cfgpath

local _M = {}

local function load_luacfg(f)
    local file = assert(io.open(f))
    local source = file:read("*a")
    file:close()
    local ret = {}
    local ok, err = pcall(assert(load(source, "@" .. f, "t", ret)))
    if ok then
        return err or ret
    else
        error(string.format("occur error when load [%s] %s", tostring(f),
            tostring(err)))
    end
end

local function load_convert(f)
    local file = assert(io.open(f))
    local source = file:read("*a")
    file:close()
    local ok, err = pcall(assert(load(source, "@" .. f, "t", _ENV)))
    if ok then
        return err
    else
        error(string.format("occur error when load [%s] %s", tostring(f),
            tostring(err)))
    end
end

local function alise_field(tbls)
    local ret = {}
    for file, tbl in pairs(tbls) do
        for f, t in pairs(tbl) do
            if type(t) == "table" then
                local nm = string.format("%s_%s", file, f)
                if f == file then nm = file end
                assert(not ret[nm], nm)
                ret[nm] = t
            end
        end
    end
    return ret
end

function _M.load_dir()
    local ret = {}
    for file in lfs.dir(root .. "/") do
        if file ~= "." and file ~= ".." then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                ret[name] = load_luacfg(string.format("%s/%s", root, file))
            end
        end
    end
    local convert = load_convert(root .. "/convert/init.lua")
    for nm, call in pairs(convert) do call(ret[nm], ret) end
    return alise_field(ret)
end

local function load_slotfile(file)
    local lines = {}
    for line in io.lines(file) do
        table.insert(lines, (string.gsub(line, "\r", "")))
    end
    return (table.concat(lines))
end

function _M.load_slotmap(scenemap)
    local ret = {}
    local cfgs = scenemap
    for _, cfg in pairs(cfgs) do
        local stop = cfg.stop
        if stop and stop ~= "" and not ret[stop .. ".stop"] then
            ret[stop .. ".stop"] = load_slotfile(
                string.format("%s/stopinfo/%s_stopinfo.stop", root, stop))
        end
    end
    return ret
end

return _M
