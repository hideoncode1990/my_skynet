local skynet = require "skynet"
local env = require "map.env"
local cfgproxy = require "cfg.proxy"
local cfgbase = require "cfg.base"
local data = require "map.data"
local mods = require "map.mods"

require "map.object_load"
require "map.hero"
require "map.target"
require "map.fight"

require "util"

local _LUA = require "handler.lua"

local MAP_CFG
skynet.init(function()
    MAP_CFG = cfgproxy("scenemap")
    cfgbase.stopall()
end)

local function env_init(ctx)
    env.mapid = ctx.mapid
    env.mod_nm = ctx.mod_nm
    env.boxlist = ctx.boxlist
    env.new = ctx.new
    env.rid = assert(ctx.rid)
    env.battle_mapid = ctx.battle_mapid
    ctx.version = MAP_CFG[ctx.mapid].version
end

function _LUA.map_init(ctx)
    pdump(ctx, "map_init")

    env_init(ctx)
    mods.init(ctx)
    data.load(ctx)
    return true
end
