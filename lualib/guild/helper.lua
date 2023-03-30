local _M = {}
local apply_t = {auto = 1, permission = 2, cant = 3}
local verify_t = {refuse = 1, agree = 2, refuse_all = 3, agree_all = 4}
local sync_t = {add = 1, del = 2, update = 3}
local apply_fail_t = {full = 1, refuse = 2, dismiss = 3}
local log_t = {
    chairman = 1, -- 会长变更
    vice_chairman = 2, -- 长老变更
    guild_star = 3, -- 设置最强之人变更
    mem_add = 4, -- 新人入会
    mem_quit = 5, -- 离开公会
    mem_kick = 6, -- 踢出公会
    act_open = 7, -- 活动开启
    act_close = 8, -- 活动结束
    impeach = 9, -- 弹劾会长
    cancel_guild_star = 10 -- 取消最强之人
}

_M.apply_t = apply_t
_M.verify_t = verify_t
_M.sync_t = sync_t
_M.log_t = log_t
_M.apply_fail_t = apply_fail_t

local authority = require "guild.authority"
local utime = require "util.time"

function _M.new_mem(role, gid, pos)
    local mem = {
        rid = role.rid,
        gid = gid,
        rname = role.rname,
        pos = pos or authority.ordinary,
        sid = role.sid,
        head = role.head,
        contribution = 0,
        login = utime.time(),
        guildstar = false,
        punish_quit_ti = 0
    }
    return mem
end

local base_id<const> = ((1 << 4 + 1) << 4 + 1) << 8
function _M.genid(val)
    return base_id + val
end

return _M
