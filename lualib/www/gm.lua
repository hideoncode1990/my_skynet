local json = require "rapidjson.c"
local cluster = require "skynet.cluster"
local cfg_clusters = require("setting.factory").proxy("clusters")
local cfg_clusters_node = require("setting.factory").proxy("clusters_node")
local skynet = require "skynet"
local format = require "monitor.format"
local util = require "util"
local logerr = require "log.err"

---@type fun(url:string, method:string, call:fun(ctx:table, header:table))
local REG = require "handler.www"

local function getall(tbl, name)
    local ret = {}
    for node in pairs(tbl) do
        if string.match(node, "^" .. name .. "_[0-9]+") then
            ret[node] = true
        end
    end
    return ret
end

REG("/dump", "get", function(_, header)
    header["Content-Type"] = "text/plain"
    return 200, util.dump(REG)
end)

REG("/", "get", function(_, header)
    header["Content-Type"] = "text/plain"
    return 200, "ok"
end)

REG("/listcluster", "get", function(_, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    return 200, json.encode(cfg_clusters_node)
end)

REG("/updatecluster", "get", function(_, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local config = cfg_clusters_node
    local all = {}
    local oks = {}
    for node in pairs(config) do
        skynet.fork(function()
            oks[node] =
                pcall(cluster.call, node, "@debuggerd", "update_cluster")
        end)
    end
    skynet.sleep(10)
    for node in pairs(config) do
        local type, id = string.match(node, "(%a+)_(%d+)")
        table.insert(all, {
            id = id,
            name = node,
            type = type,
            status = oks[node] and 1 or 0
        })
    end
    return 200, json.encode({e = 0, list = all})
end)

REG("/statuscluster", "get", function(_, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local config = cfg_clusters_node
    local all = {}
    local oks = {}
    for node in pairs(config) do
        skynet.fork(function()
            oks[node] = pcall(cluster.query, node, "debuggerd")
        end)
    end
    skynet.sleep(10)
    for node in pairs(config) do
        local type, id = string.match(node, "(%a+)_(%d+)")
        table.insert(all, {
            id = id,
            name = node,
            type = type,
            status = oks[node] and 1 or 0
        })
    end
    return 200, json.encode({e = 0, list = all})
end)

REG("/metrics", "get", function(ctx, header)
    header["Content-Type"] = "text/plain"
    local node = ctx.query.node
    if not node then
        local config = cfg_clusters_node
        local oks = {}
        for node in pairs(config) do
            skynet.fork(function()
                local ok, data = pcall(cluster.call, node, "@monitord", "data")
                if ok then
                    oks[node] = data
                else
                    oks[node] = {}
                    logerr(data)
                end
            end)
        end
        skynet.sleep(30)
        return 200, format(oks)
    else

    end
end)

REG("/default", "*", function(ctx, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local node = ctx.query.node
    if not node then return 501 end
    local config = cfg_clusters
    if not config[node] then
        return 200, json.encode {e = 1, m = "NODE_ERROR"}
    end

    if #(ctx.body or "") > 0 and ctx.header["content-type"]:sub(1, 16) ==
        "application/json" then
        if ctx.body then ctx.body = json.decode(ctx.body) end
    end

    local code, responce = cluster.call(node, "@masterd", ctx)
    if responce ~= nil then
        return code, json.encode_forjs(responce)
    else
        return code
    end
end)

REG("/gamecfg", "get", function(ctx, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local _node, file = ctx.query.node, ctx.query.file
    ctx.path = "/gamecfg/" .. file
    ldump(ctx, "gamecfg")

    local config
    if _node then
        config = {[_node] = true}
    else
        config = getall(cfg_clusters_node, "game")
    end
    local ok, code, responce = false, nil, nil
    for node in pairs(config) do
        ok, code, responce = pcall(cluster.call, node, "@masterd", ctx)
        if not ok then
            logerr(code)
        elseif code == 200 then
            break
        end
    end
    if not ok then return 500 end
    if responce ~= nil then
        return code, json.encode(responce)
    else
        return code
    end
end)

REG("/pay", "post", function(ctx, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local sid = assert(ctx.query.sid, "not sid")

    local node = "game_" .. sid
    local config = cfg_clusters
    if not config[node] then
        return 200, json.encode {e = 1, m = "NODE_ERROR"}
    end
    ctx.body = json.decode(ctx.body)

    local responce = cluster.call(node, "@payd", "onpay", ctx)
    if responce ~= nil then
        return 200, json.encode(responce)
    else
        return 200
    end
end)

REG("/updategamestat", "get", function(_, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local config = getall(cfg_clusters_node, "game")
    for node in pairs(config) do
        pcall(cluster.send, node, "@debuggerd", "update_gamestat")
    end
    return 200
end)

REG("/updatefunc", "get", function(ctx, header)
    header["Content-Type"] = "application/json;charset=UTF-8"
    local config = getall(cfg_clusters_node, "func")
    for node in pairs(config) do
        pcall(cluster.send, node, "@funcmgr", "update")
    end
    return 200
end)
