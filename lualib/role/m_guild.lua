local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local _LUA = require "handler.lua"
local client = require "client.mods"
local award = require "role.award"
local _H = require "handler.client"
local fnopen = require "role.fnopen"
local roleinfochange = require "roleinfo.change"
local cache = require("mongo.role")("guild")
local guild = require "guild"
local event = require "role.event"
local noticecheck = require "util.noticecheck"
local namecheck = require "role.namecheck"
local gamesid = require "game.sid"
local task = require "task"
local flowlog = require "flowlog"

local _M = {}

local NM<const> = "guild"
local gap_e = 30

local BASIC, GUILDICON

local function dirty(self)
    local C = cache.get(self)
    C.gid = self.gid
    C.gname = self.gname
    cache.dirty(self)
end

local function in_guild(self)
    return guild.in_guild(self)
end

local function check_roleinfo(self, gid, gname)
    gid, gname = gid or 0, gname or ""
    local oid, oname = self.gid or 0, self.gname or ""
    if gid ~= oid or gname ~= oname then
        self.gid, self.gname = gid, gname
        dirty(self)
        roleinfochange.changetable(self, {gid = gid, gname = gname})
        if gid ~= oid then
            if gid == 0 then
                event.occur("EV_GUILD_QUIT", self)
                flowlog.role(self, "guild",
                    {flag = "guild_leave", gid = oid, gname = oname})
            else
                event.occur("EV_GUILD_JOIN", self)
                task.trigger(self, "in_guild")
                flowlog.role(self, "guild",
                    {flag = "guild_join", gid = gid, gname = gname})
            end
        end
    end
end

local function guild_reg(self)
    local ok, gid, gname = guild.call("reg", self.rid, skynet.self())
    if ok then check_roleinfo(self, gid, gname) end
end

local function guild_enter(self)
    local ok, gid, gname = guild.call("enter", self.rid, self.fd)
    if ok then check_roleinfo(self, gid, gname) end
end

skynet.init(function()
    BASIC, GUILDICON = cfgproxy("basic", "guild_icon")
    fnopen.reg(NM, NM, function(self)
        guild_reg(self)
    end)
end)

local function check_open(self)
    return fnopen.check_open(self, NM)
end

guild.reg({
    load = function(self)
        guild_reg(self)
    end,
    enter = function(self)
        guild_enter(self)
    end,
    leave = function(self)
        guild.send("leave", self.rid)
    end,
    unload = function(self)
        guild.send("unreg", self.rid)
    end,
    retry = function(self, gid, gname)
        if gid == 0 then
            check_roleinfo(self, gid, gname)
        else
            guild_enter(self)
        end
    end
}, NM)

require("role.mods") {
    name = NM,
    loadafter = function(self)
        local C = cache.get(self)
        self.gid = C.gid
        self.gname = C.gname
        if check_open(self) then guild.load(self) end
    end,
    enter = function(self)
        if check_open(self) then guild.enter(self) end
    end,
    leave = function(self)
        if check_open(self) then guild.leave(self) end
    end,
    unload = function(self)
        if check_open(self) then guild.unload(self) end
    end
}

function _H.guild_create(self, msg)
    if not check_open(self) then return {e = 1} end
    local icon = msg.icon
    local cfg = GUILDICON[icon]
    if cfg.unlock ~= 1 then return {e = 2} end
    local name, r = namecheck(msg.name, BASIC.guild_name_limit)
    if not name then return {e = r + 2} end
    local cost = {BASIC.guild_build}
    if not award.checkdel(self, cost) then return {e = 6} end
    local role = {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        sid = self.sid,
        head = self.head,
        zdl = self.zdl
    }
    local ok, e, gid, gname = guild.call("create", role, name, icon,
        skynet.self())
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild",
        {flag = "guild_create", gid = gid, gname = gname})
    guild.retry(self)
    return {e = 0}
end

function _H.guild_apply(self, msg)
    if not check_open(self) then return {e = 1} end
    if in_guild(self) then return {e = 2} end
    local role = {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        sid = self.sid,
        head = self.head,
        zdl = self.zdl
    }
    local ok, e, apply_succ, left_time = guild.call("apply", role, msg.gid)
    if not ok then return {e = e + gap_e} end
    if not left_time and not apply_succ then e = 3 end
    return {e = e, left_time = left_time}
end

function _H.guild_verify(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local rid, t_rid = self.rid, msg.rid
    local ok, e = guild.call("verify", rid, t_rid, msg.op)
    if not ok then return {e = e + gap_e} end
    return {e = 0}
end

function _H.guild_apply_list(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, r = guild.call("query_apply_list", self.rid)
    if not ok then return {e = r + gap_e} end
    return {e = 0, list = r}
end

function _H.guild_quit(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, e = guild.call("quit", self.rid)
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild",
        {flag = "guild_quit", gid = self.gid, gname = self.gname})
    check_roleinfo(self)
    return {e = 0}
end

function _H.guild_kick(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local rid, t_rid = self.rid, msg.rid
    if rid == t_rid then return {e = 3} end
    local ok, e = guild.call("kick", rid, t_rid, msg.op)
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild", {
        flag = "guild_kick",
        gid = self.gid,
        gname = self.gname,
        arg1 = t_rid
    })
    return {e = e}
end

function _H.guild_query(self, msg)
    if not check_open(self) then return {e = 1} end
    local cnt = BASIC.guild_list_cnt or 10
    local ok, e, list = guild.call("recommend_list", cnt, gamesid)
    if not ok then return {e = e + gap_e} end
    return {e = 0, list = list}
end

function _H.guild_query_detail(self, msg)
    if not check_open(self) then return {e = 1} end
    local ok, e, info = guild.call("query_guild_detail", msg.gid)
    if not ok then return {e = e + gap_e} end
    return {e = 0, info = info}
end

function _H.guild_search(self, msg)
    if not check_open(self) then return {e = 1} end
    local ok, e, list = guild.call("search", msg.name)
    if not ok then return {e = e + gap_e} end
    return {e = 0, list = list}
end

function _H.guild_change_name(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local name, r = namecheck(msg.gname, BASIC.guild_name_limit)
    if not name then return {e = r + 2} end
    local cost = {BASIC.guild_change_name_cost}
    if not award.checkdel(self, cost) then return {e = 6} end
    local ok, e = guild.call("change_gname", self.rid, name, skynet.self())
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild", {
        flag = "guild_changename",
        gid = self.gid,
        gname = self.gname,
        arg1 = name
    })
    return {e = 0}
end

function _H.guild_change_icon(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, e = guild.call("change_icon", self.rid, msg.icon)
    if not ok then return {e = e + gap_e} end
    return {e = 0}
end

function _H.guild_change_applysetting(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, e = guild.call("change_applysetting", self.rid,
        msg.apply_setting_minlv, msg.apply_setting_type)
    if not ok then return {e = e + gap_e} end
    return {e = 0}
end

function _H.guild_change_notice(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local notice = msg.notice
    local ok, e
    notice, e = noticecheck(msg.notice, {0, BASIC.guild_notice_len})
    if not notice then return {e = e + 2} end
    ok, e = guild.call("change_notice", self.rid, notice)
    if not ok then return {e = e + gap_e} end
    return {e = 0}
end

function _H.guild_change_position(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local rid, t_rid = self.rid, msg.rid
    if rid == t_rid then return {e = 3} end
    local ok, e = guild.call("change_position", rid, t_rid, msg.pos)
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild", {
        flag = "guild_changepos",
        gid = self.gid,
        gname = self.gname,
        arg1 = t_rid,
        arg2 = msg.pos
    })
    return {e = 0}
end

function _H.guild_set_star(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, e = guild.call("set_guildstar", self.rid, msg.rid, msg.state)
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild", {
        flag = "guild_setstar",
        gid = self.gid,
        gname = self.gname,
        arg1 = msg.rid
    })
    return {e = 0}
end

function _H.guild_query_logs(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local ok, e, logs = guild.call("query_logs", self.rid)
    if not ok then return {e = e + gap_e} end
    return {e = 0, logs = logs}
end

function _H.guild_impeach(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local rid, t_rid = self.rid, msg.rid
    if rid == t_rid then return {e = 3} end
    local ok, e = guild.call("impeach", rid, t_rid)
    if not ok then return {e = e + gap_e} end
    flowlog.role(self, "guild", {
        flag = "guild_impeach",
        gid = self.gid,
        gname = self.gname,
        arg1 = t_rid
    })
    return {e = 0}
end

function _H.guild_send_email(self, msg)
    if not check_open(self) then return {e = 1} end
    if not in_guild(self) then return {e = 2} end
    local theme, e1 = noticecheck(msg.theme, BASIC.guild_email_theme_limit)
    if not theme then return {e = e1 + 2} end
    local content, e2 =
        noticecheck(msg.content, BASIC.guild_email_content_limit)
    if not content then return {e = e2 + 5} end
    local ok, e = guild.call("guild_email", self.rid, theme, content)
    if not ok then return {e = e + gap_e} end
    return {e = 0}
end

function _LUA.guild_kicked(self)
    check_roleinfo(self)
    client.push(self, NM, "guild_kicked", {})
end

function _LUA.guild_gname_changed(self, gname)
    check_roleinfo(self, self.gid, gname)
    client.push(self, NM, "guild_base_change", {base = {gname = gname}})
end

function _LUA.guild_enterpush(self, cmd, msg)
    client.enter(self, NM, cmd, msg)
end

function _M.in_guild(self)
    return in_guild(self)
end

award.reg({
    type = require("role.award.type").guild_contribution,
    add = function(self, nms, pkts, option, items)
        if in_guild(self) then
            local val = 0
            for _, item in ipairs(items) do val = val + item[3] end
            if val > 0 then
                local ok, err = guild.call("add_contribution", self.rid, val)
                if not ok then require "log"(err) end
            end
        end
        return true
    end
}, nil)

return _M
