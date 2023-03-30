local skynet = require "skynet"
local site = require "site"
local parallels = require "parallels"
local roleid = require "roleid"
local utable = require "util.table"
local logerr = require "log.err"

local _M = {}

local function get_siteaddr(rid)
    local sid = roleid.getsid(rid)
    return {node = "game_" .. sid, addr = "@roleinfod"}
end

local function call(method, rid, ...)
    return pcall(site.call, get_siteaddr(rid), method, rid, ...)
end

function _M.query(rid, ks)
    local ok, ret = call("query", rid, ks)
    if ok then return ret end
end

function _M.query_detail(rid)
    local ok, ret = call("query", rid)
    if ok then return ret end
end

function _M.query_list(list, ks)
    local success, failed = {}, {}

    local SIDS = {}
    for rid in pairs(list) do
        failed[rid] = true
        local dict = utable.sub(SIDS, roleid.getsid(rid))
        dict[rid] = true
    end
    for sid, dict in pairs(SIDS) do
        local ok, ret = pcall(site.call,
            {node = "game_" .. sid, addr = "@roleinfod"}, "query_safe_list",
            dict, ks)
        if ok then
            for rid, info in pairs(ret) do
                success[rid] = info
                failed[rid] = nil
            end
        else
            logerr(ret)
        end
    end
    return success, failed
end

-- 此接口只能在game服务调用
function _M.query_list_local(list, ks)
    return skynet.call(skynet.uniqueservice("game/roleinfod"), "lua",
        "query_safe_list", list, ks)
end

return _M
