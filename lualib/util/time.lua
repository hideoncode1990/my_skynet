local time_core = require "time.core"

---@class utime
---@field begin_hour fun(t:number,s:integer):integer
---@field begin_day fun(t:number,s:integer):integer
---@field begin_week fun(t:number,s:integer):integer
---@field wday fun(t:number):integer
---@field now fun():number
---@field time fun():number
---@field time_decimal fun():number
---@field time_int fun():integer
---@field time_elapse fun(t:integer):number
---@field debug_init fun(t:integer):nil
---@field DEBUG_DEFINE boolean
local _M = setmetatable({}, {__index = time_core})

local SEC_HOUR<const> = 60 * 60
local SEC_DAY<const> = 24 * SEC_HOUR
local SEC_WEEK<const> = 7 * SEC_DAY
local SEC_MONTH<const> = 28 * SEC_DAY
local SEP_DEFAULT<const> = 0

function _M.begin_month(_ti, sep)
    local ti = math.floor(_ti)
    local t = os.date("*t", ti)
    t.day = 1
    t.hour = 0
    t.min = 0
    t.sec = sep or 0
    local b = os.time(t)
    if ti < b then
        t.month = t.month - 1
        return os.time(t)
    else
        return b
    end
end

function _M.same_day(t1, t2, sep)
    sep = sep or SEP_DEFAULT
    assert(sep >= 0 and sep < SEC_DAY)
    return time_core.begin_day(t1, sep) == time_core.begin_day(t2, sep)
end

function _M.same_hours(t1, t2, sep)
    sep = sep or SEP_DEFAULT
    assert(sep >= 0 and sep < SEC_HOUR)
    return time_core.begin_hour(t1, sep) == time_core.begin_hour(t2, sep)
end

function _M.same_week(t1, t2, sep)
    sep = sep or SEP_DEFAULT
    assert(sep >= 0 and sep < SEC_WEEK)
    return time_core.begin_week(t1, sep) == time_core.begin_week(t2, sep)
end

function _M.same_month(t1, t2, sep)
    sep = sep or SEP_DEFAULT
    assert(sep >= 0 and sep < SEC_MONTH)
    return _M.begin_month(t1, sep) == _M.begin_month(t2, sep)
end

return _M
