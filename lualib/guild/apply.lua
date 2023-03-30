local utime = require "util.time"
local helper = require "guild.helper"
local verify_t = helper.verify_t
local apply_t = helper.apply_t
local collection = "guildapply"
local _GUILDM = require "guild.m"
local mongo = require("mongo.help.one")("DB_FUNC", collection)
local schema = require "mongo.schema"
local sm = require"guild.schema".gen(schema.OBJ(
    {
        rid = schema.ORI,
        gid = schema.ORI,
        rname = schema.ORI,
        sid = schema.ORI,
        head = schema.ORI,
        ti = schema.ORI,
        zdl = schema.ORI
    }))
local _M = {}

return function(gid, TIMEOUT)
    local D = mongo("findall", collection, {gid = gid})
    local NUM = 0
    local expire_ti
    local _now = utime.time()
    local applylist = {}
    for _, d in ipairs(D) do
        local role = sm.decode(d)
        local rid = role.rid
        NUM = NUM + 1
        local ti = role.ti
        if _now >= ti + TIMEOUT then
            pcall(mongo, "delete", collection, {rid = rid, gid = gid})
        else
            if ti <= (expire_ti or ti) then expire_ti = ti end
            role.siteaddr = {node = role.node, addr = "@guild_proxy"}
            applylist[rid] = role
        end
    end
    expire_ti = expire_ti or _now

    local function add(role)
        local rid = role.rid
        local mem = {
            rid = rid,
            gid = gid,
            rname = role.rname,
            node = role.node,
            sid = role.sid,
            siteaddr = {node = role.node, addr = "@guild_proxy"},
            head = role.head,
            ti = utime.time(),
            zdl = role.zdl
        }
        mongo("insert", collection, sm.encode(mem))
        applylist[rid] = mem
        NUM = NUM + 1
        _GUILDM.push2official("guild_role_applynum", {num = NUM})
    end

    local function del(rid)
        mongo("delete", collection, {rid = rid, gid = gid})
        applylist[rid] = nil
        NUM = NUM - 1
        _GUILDM.push2official("guild_role_applynum", {num = NUM})
    end

    function _M.clear()
        mongo("delete", collection, {gid = gid})
        NUM = 0
        local list
        list, applylist = applylist, {}
        return list
    end

    local function check_expired()
        local now = utime.time()
        if now < expire_ti + TIMEOUT then return end
        expire_ti = nil
        for rid, role in pairs(applylist) do
            local ti = role.ti
            if ti + TIMEOUT <= now then
                del(rid)
            else
                if ti <= (expire_ti or ti) then expire_ti = ti end
            end
        end
        expire_ti = expire_ti or now
    end

    function _M.check_applysetting(type)
        if type ~= apply_t.auto and type ~= apply_t.permission and type ~=
            apply_t.cant then return false end
        return true
    end

    function _M.request(role, minlv, applytype, applymax)
        local rid = role.rid
        if applytype == apply_t.cant then return false, 1 end
        if role.level < minlv then return false, 2 end
        check_expired()
        if NUM >= applymax then return false, 3 end
        if applytype == apply_t.permission then
            if applylist[rid] then return false, 4 end
            add(role)
            return false, 0, true
        end
        if applylist[rid] then del(rid) end -- 之前已在申请列表中，申请设置该为自动加入后，可以再次申请加入
        return true, 0
    end

    function _M.query_list()
        check_expired()
        return applylist, NUM
    end

    function _M.verify(rid, op)
        local agree, refuse
        if op == verify_t.refuse then
            local role = applylist[rid]
            if not role then return false, 3 end
            del(rid)
            refuse = {role}
        elseif op == verify_t.agree then
            local role = applylist[rid]
            if not role then return false, 3 end
            del(rid)
            agree = {role}
        elseif op == verify_t.refuse_all then
            refuse = {}
            for _rid, role in pairs(applylist) do
                del(_rid)
                table.insert(refuse, role)
            end
            applylist = {}
        elseif op == verify_t.agree_all then
            agree = {}
            for _rid, role in pairs(applylist) do
                del(_rid)
                table.insert(agree, role)
            end
            applylist = {}
        end
        return true, 0, agree, refuse
    end

    function _M.get_cnt()
        return NUM
    end

    return _M
end
