local skynet = require "skynet"
local useragent = require "manager.useragent"
local roleinfo = require "roleinfo"
local rolehelp = require "mongo.rolehelp"
local logerr = require "log.err"
local utable = require "util.table"

local _MAS = require "handler.master"
local _LUA = require "handler.lua"

local force_load = {}

skynet.dispatch("master", function(_, _, cmd, ctx)
    local f = _MAS[cmd]
    if f then return skynet.retpack(200, f(ctx)) end
    local rid = tonumber(ctx.query.rid)
    if rid then
        local ref<close> = useragent.query_agent(rid)

        local requirestr = string.format([[require "role.master.%s"]],
            string.match(cmd, "([^_]+)"))
        local ok, err = skynet.call(ref.addr, "debug", "RUN", requirestr)
        if not ok then logerr(err) end

        return skynet.retpack(200, skynet.call(ref.addr, "master", cmd, ctx))
    else
        error(string.format("Unknown command : [%s]", cmd))
    end
end)

local function get_roleinfo(rlist)
    local ret = roleinfo.query_list_local(rlist)
    local list = {}
    for rid, info in pairs(ret) do
        local ref<close> = useragent.query_agent_loaded(rid)
        table.insert(list, {
            uid = info.uid,
            rid = tostring(rid),
            rname = info.rname,
            online = info.online,
            addr = ref and string.format("%08x", ref.addr),
            inforce = force_load[rid] ~= nil
        })
    end
    return list
end

function _MAS.list(ctx)
    local type = tonumber(ctx.query.listtype)
    if type == 0 then
        local user = useragent.anyrole(30)
        for rid in pairs(force_load) do user[rid] = true end
        return {e = 0, list = get_roleinfo(user)}
    else
        local dbmgr = skynet.uniqueservice("db/mgr")
        local proxy = skynet.call(dbmgr, "lua", "query", "DB_GAME")
        if type == 1 then
            local uid = ctx.query.input
            local user = {}
            for _, role in ipairs(rolehelp.select_byargs(proxy, {uid = uid})) do
                user[role.rid] = true
            end
            return {e = 0, list = get_roleinfo(user)}
        elseif type == 2 then
            local input = ctx.query.input
            local rid = tonumber(input) or 0
            local list = get_roleinfo({[rid] = true})

            rid = tonumber(input, 16)
            if rid then
                utable.mixture(list, get_roleinfo({[rid] = true}))
            end

            return {e = 0, list = list}
        elseif type == 3 then
            local rname = ctx.query.input
            local user = {}
            for _, role in ipairs(rolehelp.select_byargs(proxy, {
                rname = {['$regex'] = rname}
            }, nil, nil, 100)) do user[role.rid] = true end
            return {e = 0, list = get_roleinfo(user)}
        else
            error("unsupport")
        end
    end
end

function _MAS.forceload(ctx)
    local rid = tonumber(ctx.query.rid)
    local ref = force_load[rid]
    if not ref then
        force_load[rid] = useragent.query_agent(rid)
    else
        force_load[rid] = nil
        local rref<close> = ref
    end
    return {e = 0}
end

function _MAS.kickall()
    _LUA.kickall("by_master")
    return {e = 0}
end
