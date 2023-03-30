local skynet = require "skynet"
local queue = require "skynet.queue"
local _H = require "handler.client"
local award = require "role.award"
local uaward = require "util.award"
local event = require "role.event"

local _M = {}

local NM<const> = "map"

local MAPMGR
skynet.init(function()
    MAPMGR = skynet.uniqueservice("game/mapmgr")
end)

require("role.mods") {
    name = NM,
    unload = function(self)
        _M.over(self)
    end
}

function _M.over(self)
    self.map_addr = nil
    skynet.call(MAPMGR, "lua", "over", self.rid)
end

function _M.start(self, ctx, cb)
    local keep<close> = setmetatable({addr = nil}, {
        __close = function(t)
            if t.addr then
                skynet.call(MAPMGR, "lua", "over", self.rid)
            end
        end
    })

    local map_addr = self.map_addr
    if not map_addr then
        map_addr = skynet.call(MAPMGR, "lua", "start", self.rid)
        if not map_addr then return end

        keep.addr = map_addr
        skynet.call(map_addr, "lua", "map_init", ctx)
        if cb then cb(map_addr) end
    end

    assert(skynet.call(map_addr, "lua", "map_enter", {
        uuid = self.rid,
        addr = self.addr,
        fd = self.fd,
        rname = self.rname,
        level = self.level
    }))
    keep.addr = nil
    self.map_addr = map_addr
end

function _M.move(self, desti)
    if not self.map_addr then return false, 100 end
    return skynet.call(self.map_addr, "lua", "map_move", self.rid, desti)
end

function _M.battle_start(self, uuid, list, battle_info)
    if not self.map_addr then return false, 100 end
    return skynet.call(self.map_addr, "lua", "map_battle_start", self.rid, uuid,
        list, battle_info)
end

local NOT_IN_MAP = {__name = "NOT_IN_MAP"}

_M.NOT_IN_MAP = NOT_IN_MAP

function _M.call(self, ...)
    local addr = self.map_addr
    if not addr then return nil, NOT_IN_MAP end
    return skynet.call(addr, "lua", ...)
end

function _M.send(self, ...)
    local addr = self.map_addr
    if not addr then return end
    return skynet.send(addr, "lua", ...)
end

function _M.deldata(collection, list)
    skynet.call(MAPMGR, "lua", "deldata", collection, list)
end

function _H.map_move(self, msg)
    local ok, err = _M.move(self, msg.way)
    return {e = ok and 0 or err}
end

function _H.map_box(self, msg)
    if not self.map_addr then return {e = 1} end
    local uuid = msg.uuid
    local ok, err = skynet.call(self.map_addr, "lua", "map_box", self.rid, uuid)
    if ok then
        award.adde(self, {
            flag = "map_box",
            arg1 = uuid,
            theme = "MAP_BOX_FULL_THEME_",
            content = "MAP_BOX_FULL_CONTENT_"
        }, ok)
        return {e = 0, reward = uaward.pack(ok)}
    end
    return {e = err}
end

function _H.map_switch(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_switch", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_transport(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_transport", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_elevator(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_elevator", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end
function _H.map_cannon(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_cannon", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_heal(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_heal", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_herotower(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_herotower", self.rid,
        msg.uuid, msg.index)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_buff(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_buff", self.rid,
        msg.uuid, msg.index)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_npc(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_npc", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_choice_finish(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_choice_finish",
        self.rid, msg.id, msg.index)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_chat_over(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_chat_over", self.rid,
        msg.id, msg.index)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_shop_buy(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_shop_buy", self.rid,
        msg.uuid, msg.index)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_shop_close(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_shop_close",
        self.rid, msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_boxtemp(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_boxtemp", self.rid,
        msg.uuid)
    if ok then return {e = 0} end
    return {e = err}
end

function _H.map_itemuse(self, msg)
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_itemuse", self.rid,
        msg.id, msg.cnt)
    if ok then return {e = 0} end
    return {e = err}
end

event.reg("EV_LVUP", NM, function(self, level)
    _M.send(self, "map_player_infochange", {level = level})
end)

event.reg("EV_NAMECHANGE", NM, function(self, rname)
    _M.send(self, "map_player_infochange", {rname = rname})
end)

event.reg("EV_HERO_DELS", NM, function(self, uuids)
    _M.send(self, "map_hero_dels", uuids)
end)
return _M
