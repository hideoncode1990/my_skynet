local skynet = require "skynet"
local client = require "role.client"
local cluster = require "skynet.cluster"
local factory = require "setting.factory"
local utime = require "util.time"
local calendar = require "calendar"

local _MAS = require "handler.master"

local function changeall_time_to(timestamp)

    local clusters_node = factory.proxy("clusters_node")
    local clusters_game = factory.proxy("clusters_game")

    for node in pairs(clusters_node) do
        local ok, now, diff = pcall(cluster.call, node, "@debuggerd",
            "changetime", timestamp)
        if ok and now and clusters_game[node] then
            pcall(cluster.call, node, "@chatd", "chat_native_push", "time_to",
                {now = now, diff = diff})
        end
    end
end

local function timeformat(ti)
    ti = ti or utime.time_int()
    return os.date("%z %Y-%m-%d %H:%M:%S %w", ti)
end

local function changetime(ti)
    local now = utime.time_int()
    utime.time_elapse(ti)
    local nnow = utime.time_int()
    local diff = nnow - now
    skynet.error("changetime", nnow, diff)
    return nnow, diff
end

local function checkinteger(val, min, max)
    if val == "*" then return val end
    val = tonumber(val)
    if not val then return nil, "expected integer or *" end
    if val ~= math.floor(val) then return nil, "not a integer" end
    if val > max or val < min then
        return nil, string.format("must in %d %d", min, max)
    end
    return val
end

local function calc_constr(val)
    local hour, min, sec = string.match(val, "^([%d%*]+):([%d%*]+):([%d%*]+)$")
    if not hour then return nil, "match failure" end
    local err
    hour, err = checkinteger(hour, 0, 24)
    if not hour then return hour, err end
    min, err = checkinteger(min, 0, 60)
    if not min then return min, err end
    sec, err = checkinteger(sec, 0, 60)
    if not sec then return sec, err end
    local constr = string.format("%s %s %s * * ?", sec, min, hour)
    return constr
end

local function next_time(val)
    local constr, e, m = calc_constr(val)
    if not constr then return false, e, m end

    return calendar.next_time(constr)
end

local function calc_second(type, num)
    if (not type or type == '') and not num then
        return false, 0, timeformat()
    end

    if not num then return false, 1, "num error" end

    local t = num
    t = math.max(0, t)
    local second
    if type == "s" then
        second = t
    elseif type == "m" then
        second = t * 60
    elseif type == "h" then
        second = t * 3600
    elseif type == "d" then
        second = t * 3600 * 24
    elseif type == "w" then
        second = t * 3600 * 24 * 7
    end
    return second
end

function _MAS.time_to(_, ctx)
    local timestamp, e, m = next_time(ctx.query.val)
    if not timestamp then return {e = e, m = m} end

    local now, diff = changetime(timestamp - utime.time_int())
    client.push_all("time_to", {now = now, diff = diff})
    return {e = 0, m = timeformat()}
end

function _MAS.time(_, ctx)
    local second, e, m = calc_second(ctx.query.type, ctx.query.num)
    if not second then return {e = e, m = m} end

    local now, diff = changetime(second)
    client.push_all("time_to", {now = now, diff = diff})
    return {e = e, m = timeformat()}
end

function _MAS.time_allto(_, ctx)
    local timestamp, e, m = next_time(ctx.query.val)
    if not timestamp then return {e = e, m = m} end

    changeall_time_to(timestamp)
    return {e = 0, m = timeformat()}
end

function _MAS.time_all(_, ctx)
    local second, e, m = calc_second(ctx.query.type, ctx.query.num)
    if not second then return {e = e, m = m} end

    local tiemstamp = utime.time_int() + second
    changeall_time_to(tiemstamp)
    return {e = 0, m = timeformat()}
end
