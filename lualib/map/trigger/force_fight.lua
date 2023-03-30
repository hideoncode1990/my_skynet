local skynet = require "skynet"
local trigger = require "map.trigger"
local objmgr = require "map.objmgr"
local map_hero = require "map.hero"
local env = require "map.env"
local cfgproxy = require "cfg.proxy"
local monster_die = require "map.monster_die"
local map_buff = require "map.buff"
local monster = require "map.object.monster"
local battle = require "battle"
local map_attrs = require "map.attrs"
local battle_limit = require "battle.limit"

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            local heroes = map_hero.force_fight_lineup()
            if not next(heroes) then
                return
            else
                local reward
                local mobj = monster.new(nil, cfg.para[1][1])
                local monsters, bossid = monster_die.monster_create(mobj)
                local bcfg = BASIC.explore_force_fight

                local ctx<close> = battle.create(env.mod_nm, env.battle_mapid,
                    {
                        auto = bcfg[2] == 0 and false or true,
                        multi_speed = bcfg[1],
                        offline_skip = true
                    }, battle_limit.terminate | battle_limit.pause)
                local ply = objmgr.player()
                if not battle.join(ctx, {
                    rid = ply.uuid,
                    fd = ply.fd,
                    addr = ply.addr
                }) then assert(false) end

                local left = {
                    heroes = heroes,
                    player = {rname = ply.rname, level = ply.level},
                    passive_list = map_buff.passive_list()
                }
                local right = {heroes = monsters, player = {bossid = bossid}}
                battle.start(ctx, left, right, function(ok, ret)
                    if not ok then
                        return battle.abnormal_push(ply)
                    end
                    local win = ret.win
                    if win == 1 then
                        reward = cfg.para[2]
                        objmgr.agent_call("award_adde", {
                            flag = "force_fight_reward",
                            arg1 = env.mod_nm,
                            arg2 = env.mapid,
                            theme = "FORCE_FIGHT_THEME",
                            content = "FORCE_FIGHT_CONTENT"
                        }, {reward})
                        map_buff.trigger("victory")
                    end
                    ret = map_attrs.deal_ret(ret, heroes, monsters)
                    battle.push(ply, ret, {reward})
                end)
            end
            trigger.finishctx(ctx, cfg)
        end
    })
end

