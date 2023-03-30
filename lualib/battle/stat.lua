local profile = require "battle.profile"
local _M = {}

local profile_add = profile.add

local total_msg_sz = 0

function _M.push(bctx, self, name, msg, force)
    msg.frame = bctx.btime.frame
    local sz, cnt = bctx.objmgr.sendall(name, msg, force)
    profile_add(bctx, bctx, "total_msg_sz", sz)
    profile_add(bctx, bctx, "msg_cnt", cnt)
    total_msg_sz = total_msg_sz + sz
end

function _M.damage(bctx, self, damage, tobj, dead)
    while self.masterid do
        local o = bctx.objmgr.get(self.masterid)
        if not o then break end
        self = o
    end
    local d = self.report
    if d then
        d.damage = d.damage + damage
        profile.addtable(bctx, bctx, "report_" .. self.camp, "damage", damage)
        if dead then
            d.kill = d.kill + 1
            bctx.final_kill = self.id
            profile.addtable(bctx, bctx, "report_" .. self.camp, "kill", 1)
        end
    end

    local t = tobj.report
    if t then
        t.hurt = t.hurt + damage
        if dead then t.dead = true end
    end
end

function _M.heal(self, hp, tobj)
    local h = self.report
    if h then h.heal = h.heal + hp end
end

function _M.get_msgsz()
    return total_msg_sz
end

return _M
