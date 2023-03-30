local supply = require "map.supply"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local monster_die = require "map.monster_die"
local map_attrs = require "map.attrs"
local map_hero = require "map.hero"
local map_buff = require "map.buff"
local battle = require "battle"
local env = require "map.env"
local gird = require "map.gird"

local _LUA = require "handler.lua"

function _LUA.map_battle_start(rid, uuid, list, battle_info)
    if not supply.check() then return false, 107 end
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.monster)
    if not o then return false, 108 end

    if ply.pos ~= o.pos and not gird.isneibo(ply.pos, o.pos) then
        return false, 101
    end
    if monster_die.check(uuid) then return false, 102 end
    local heroes, simple = map_hero.check_create(list)
    if not heroes then return false, simple end
    local monsters, bossid = monster_die.monster_create(o)
    local ctx<close> = battle.create(env.mod_nm, env.battle_mapid, {
        auto = battle_info.auto,
        multi_speed = battle_info.multi_speed,
        no_play = battle_info.no_play
    })

    if not battle.join(ctx, {rid = ply.uuid, fd = ply.fd, addr = ply.addr}) then
        return false, 106
    end

    local left = {
        passive_list = map_buff.passive_list(),
        heroes = heroes,
        player = {rname = ply.rname, level = ply.level}
    }

    local right = {heroes = monsters, player = {bossid = bossid}}
    battle.start(ctx, left, right, function(ok, ret)
        if not ok then return battle.abnormal_push(ply) end
        if ret.restart or ret.terminate then return battle.push(ply, ret) end
        local win = ret.win
        if win == 1 then
            objmgr.del(uuid)
            o:die(simple)
            map_buff.trigger("victory")
        end
        ret = map_attrs.deal_ret(ret, heroes, monsters, uuid)
        battle.push(ply, ret)
    end)
    return true
end
