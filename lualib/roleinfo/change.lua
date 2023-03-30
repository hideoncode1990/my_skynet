local skynet = require "skynet"
local timer = require "timer"

local select = select
local type = type
local assert = assert

local roleinfod
skynet.init(function()
    roleinfod = skynet.uniqueservice("game/roleinfod")
end)

local _M = require "roleinfo"

local CHANGE = {}
local function send_change(self)
    local c
    CHANGE, c = {}, CHANGE
    if next(c) then
        skynet.send(roleinfod, "lua", "changetable", self.rid, c)
        -- ldump(c, "roleinfo.change")

    end
end

local ROLEINFO
require("role.mods") {
    name = "roleinfo",
    load = function(self)
        local rid = self.rid
        local cache, err = skynet.call(roleinfod, "lua", "query_detail_safe",
            rid)
        if not cache then
            assert(err == "not_exist")
            cache = skynet.call(roleinfod, "lua", "init", rid, {
                uid = self.uid,
                rid = rid,
                sid = self.sid,
                rname = self.rname
            })
            ROLEINFO = cache
        else
            ROLEINFO = cache
            _M.change(self, "rname", self.rname)
        end
    end,
    unload = send_change
}

local function checktable(db, key)
    local dbt = db[key]
    if type(dbt) ~= "table" then
        dbt = {}
        db[key] = dbt
    end
    return dbt
end

local function update(db, ch, key, val, ...)
    if select("#", ...) == 0 then
        if type(val) == "table" then
            local dbt = checktable(db, key)
            local cht = checktable(ch, key)
            for k in pairs(dbt) do
                if not val[k] then
                    dbt[k] = nil
                    cht[k] = "___NIL___"
                end
            end
            for k, v in pairs(val) do update(dbt, cht, k, v) end
            if not next(cht) then ch[key] = nil end
        else
            if db[key] ~= val then
                db[key] = val
                if val == nil then val = "___NIL___" end
                ch[key] = val
            end
        end
    else
        local dbt = checktable(db, key)
        local cht = checktable(ch, key)
        update(dbt, cht, val, ...)
        if not next(cht) then ch[key] = nil end
    end
end

local insend
local function check_send(self)
    if insend then return end
    insend = true
    timer.add(300, function()
        insend = nil
        send_change(self)
    end)
end

function _M.change(self, key, val, ...)
    assert(key and val)
    update(ROLEINFO, CHANGE, key, val, ...)
    check_send(self)
end

function _M.changetable(self, data)
    for key, val in pairs(data) do update(ROLEINFO, CHANGE, key, val) end
    check_send(self)
end

function _M.query_cache(_, key)
    assert(key)
    return ROLEINFO[key]
end

return _M
