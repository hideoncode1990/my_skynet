local client = require "client.mods"
local utable = require "util.table"
local email = require "email"
local lang = require "lang"

--- @class awardoption
--- @field flag string
--- @field arg1 any
--- @field arg2 any
--- @field theme string
--- @field content string

--- @class role
--- @field uid string
--- @field rid number
--- @field uname string
--- @field ip string

--- @class award
--- @field add fun(self:role, option:awardoption, adds:table):boolean
--- @field adde fun(self:role, option:awardoption, adds:table):boolean
--- @field del fun(self:role, option:awardoption, dels:table):boolean
--- @field deladd fun(self:role, option:awardoption, dels:table, adds:table):boolean
--- @field checkdel fun(self:role, dels:table):boolean
--- @field checkadd fun(self:role, adds:table):boolean
--- @field getcnt fun(self:role, type:number, id:number):number
local _M = {}

local REGS = {}
local POOR<const>, FULL<const> = 1, 2

local function make_e(add, type, id)
    -- assert(id < (1 << 20)) -- 0xFFFFF
    -- assert(type < (1 << 8)) -- 0xFF
    -- assert(add < (1 << 4))
    return add << 28 | (type << 20) | (id or 0)
end

function _M.full_e(type, id)
    return make_e(FULL, type, id)
end
-- local function take_e(e)
--     local add = ((~(0) << 28) & e) >> 28
--     local type = (0xFF00000 & e) >> 20
--     local id = (0xFFFFF & e)
--     return add, type, id
-- end

--- @param opt table
--- @param type number|nil
function _M.reg(opt, type)
    type = type or opt.type
    assert(not REGS[type])
    REGS[type] = opt
end

local function make_group(items)
    local group = {}
    for _, item in ipairs(items) do
        local t = item[1]
        local grp = utable.sub(group, t)
        table.insert(grp, item)
    end
    return group
end

local function make_lang_text(key, _type)
    if type(key) == "table" then
        return lang(key[1] .. _type, table.unpack(key, 2))
    else
        return lang(key .. _type)
    end
end

local function do_add(self, nms, pkts, option, adds, need_email)
    local grps = make_group(adds)
    for type, grp in pairs(grps) do
        local checkadd = REGS[type].checkadd
        if checkadd then
            local ok, id = checkadd(self, grp)
            if not ok then
                if need_email then
                    email.send {
                        target = self.rid,
                        theme = make_lang_text(option.theme, type),
                        content = make_lang_text(option.content, type),
                        option = {
                            flag = option.flag,
                            arg1 = option.arg1,
                            arg2 = option.arg2,
                            FROME = true
                        },
                        items = adds
                    }
                    return true
                else
                    return false, make_e(FULL, type, id)
                end
            end
        end
    end
    for type, grp in pairs(grps) do
        local add = REGS[type].add
        assert(add(self, nms, pkts, option, grp))
    end
    return true
end

local function award_adde(self, nms, pkts, option, adds)
    return do_add(self, nms, pkts, option, adds, true)
end

local function award_add(self, nms, pkts, option, adds)
    return do_add(self, nms, pkts, option, adds)
end

local function award_checkdel(self, dels)
    for type, grp in pairs(make_group(dels)) do
        local checkdel = REGS[type].checkdel
        if checkdel then
            local ok, id = checkdel(self, grp)
            if not ok then return false, make_e(POOR, type, id) end
        end
    end
    return true
end

local function award_checkadd(self, adds)
    for type, grp in pairs(make_group(adds)) do
        local checkadd = REGS[type].checkadd
        if checkadd then
            local ok, id = checkadd(self, grp)
            if not ok then return false, make_e(FULL, type, id) end
        end
    end
    return true
end

local function award_del(self, nms, pkts, option, dels)
    local grps = make_group(dels)
    for type, grp in pairs(grps) do
        local checkdel = REGS[type].checkdel
        if checkdel then
            local ok, id = checkdel(self, grp)
            if not ok then return false, make_e(POOR, type, id) end
        end
    end
    for type, grp in pairs(grps) do
        local del = REGS[type].del
        assert(del(self, nms, pkts, option, grp))
    end
    return true
end

local function award_getcnt(self, tp, id)
    local getcnt = assert(REGS[tp].getcnt)
    return getcnt(self, id or 0)
end

local function award_deladd(self, nms, pkts, option, _dels, _adds)
    local grps_dels = make_group(_dels)
    for type, grp in pairs(grps_dels) do
        local reg = REGS[type]
        local checkdel = reg.checkdel
        if checkdel then
            local ok, id = checkdel(self, grp)
            if not ok then return false, make_e(POOR, type, id) end
        end
    end
    local grps_adds = make_group(_adds)
    for type, grp in pairs(grps_adds) do
        local reg = REGS[type]
        local checkadd = reg.checkadd
        if checkadd then
            local ok, id = checkadd(self, grp)
            if not ok then return false, make_e(FULL, type, id) end
        end
    end

    for type, grp in pairs(grps_dels) do
        local del = REGS[type].del
        assert(del(self, nms, pkts, option, grp))
    end
    for type, grp in pairs(grps_adds) do
        local add = REGS[type].add
        assert(add(self, nms, pkts, option, grp))
    end
    return true
end

local _LUA = require "handler.lua"

local auto_index_mt = {
    __index = function(t, k)
        local n = (rawget(t, "n") or 0) + 1
        local v = {}
        t[k], t[n], t.n = v, {k, v}, n
        return v
    end,
    __pairs = function(t)
        local n, i = rawget(t, "n") or 0, 0
        return function()
            i = i + 1
            if i <= n then
                local d = t[i]
                return d[1], d[2]
            end
        end
    end
}

local function MAKE_API(name, call)
    local function api(...)
        return call(...)
    end
    _M[name] = api
    _LUA["award_" .. name] = api
end

local function MAKE_MSG_API(name, call)
    local function api(self, option, ...)
        local nms, pkts = {}, setmetatable({}, auto_index_mt)
        local ret, err = call(self, nms, pkts, option, ...)
        for cmd, list in pairs(pkts) do
            client.push(self, nms[cmd], cmd, {list = list, args = option.flag})
        end
        return ret, err
    end
    _M[name] = api
    _LUA["award_" .. name] = api
end

MAKE_MSG_API("add", award_add)
MAKE_MSG_API("adde", award_adde)
MAKE_MSG_API("del", award_del)
MAKE_MSG_API("deladd", award_deladd)
MAKE_API("checkdel", award_checkdel)
MAKE_API("checkadd", award_checkadd)
MAKE_API("getcnt", award_getcnt)
return _M
