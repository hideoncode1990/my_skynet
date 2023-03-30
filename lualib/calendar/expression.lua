local lpeg = require "lpeg"
local ustring = require "util.string"

local TYPE_SECOND = 1
local TYPE_MINUTE = 2
local TYPE_HOUR = 3
local TYPE_DAY_OF_MONTH = 4
local TYPE_MONTH = 5
local TYPE_DAY_OF_WEEK = 6
local TYPE_YEAR = 7
local ALL_SPEC_INT = 99 -- *
local NO_SPEC_INT = 98 -- ?
local ALL_SPEC = ALL_SPEC_INT
local NO_SPEC = NO_SPEC_INT

local function build2call(id)
    return function(v)
        table.insert(v, 1, id)
        return v
    end
end
local COM_NUMBERS = lpeg.R("09") ^ 1 / tonumber
local NUMS = COM_NUMBERS / function(v)
    return {1, v}
end
local ANY = lpeg.P("*") / function()
    return {2}
end
local RANGE = lpeg.Ct(COM_NUMBERS * lpeg.P("-") * COM_NUMBERS) / build2call(3)
local EVERY = lpeg.Ct(COM_NUMBERS * lpeg.P("/") * COM_NUMBERS) / build2call(4)
local REFANY = lpeg.P("?") / function()
    return {5}
end

local SECOND_FIELD_STR = EVERY + RANGE + ANY + NUMS
local SECOND_STR = lpeg.Ct((SECOND_FIELD_STR * lpeg.P(",")) ^ 0 *
                               SECOND_FIELD_STR)
local DAY_FIELD_STR = REFANY + SECOND_FIELD_STR
local DAYOFMONTH = lpeg.Ct((DAY_FIELD_STR * lpeg.P(",")) ^ 0 * DAY_FIELD_STR)

local MATCH_METHOD = {
    [TYPE_SECOND] = SECOND_STR,
    [TYPE_MINUTE] = SECOND_STR,
    [TYPE_HOUR] = SECOND_STR,
    [TYPE_DAY_OF_MONTH] = DAYOFMONTH,
    [TYPE_MONTH] = SECOND_STR,
    [TYPE_DAY_OF_WEEK] = DAYOFMONTH,
    [TYPE_YEAR] = SECOND_STR
}

local MAX_YEAR = os.date("*t").year + 5

local function set_add(set, val)
    local low = 1 - 1
    local hight = #set - 1
    while low <= hight do
        local mid = low + math.floor((hight - low) / 2)
        local vv = set[mid + 1]
        if vv < val then low = mid + 1 end
        if vv > val then hight = mid - 1 end
        if vv == val then return set end
    end
    table.insert(set, low + 1, val)
    return set
end

local function set_contains(set, val)
    local low = 1 - 1
    local hight = #set - 1
    while low <= hight do
        local mid = low + math.floor((hight - low) / 2)
        local vv = set[mid + 1]
        if vv < val then low = mid + 1 end
        if vv > val then hight = mid - 1 end
        if vv == val then return true end
    end
    return set[low + 1] == val
end

local function set_tail(set, val)
    local low = 1 - 1
    local hight = #set - 1
    while low <= hight do
        local mid = low + math.floor((hight - low) / 2)
        local vv = set[mid + 1]
        if vv < val then low = mid + 1 end
        if vv > val then hight = mid - 1 end
        if vv == val then return val end
    end
    return set[low + 1]
end

local function add_to_set(self, val, stop, incr, type)
    local set = self[type]
    -- print("add_to_set",set,self, val, stop, incr, type)
    if type == TYPE_SECOND or type == TYPE_MINUTE then
        if (val < 0 or val > 59 or stop > 59) and val ~= ALL_SPEC_INT then
            error("Minute and Second values must be between 0 and 59")
        end
    elseif type == TYPE_HOUR then
        if (val < 0 or val > 23 or stop > 23) and val ~= ALL_SPEC_INT then
            error("Hour values must be between 0 and 23")
        end
    elseif type == TYPE_DAY_OF_MONTH then
        if (val < 1 or val > 31 or stop > 31) and val ~= ALL_SPEC_INT and val ~=
            NO_SPEC_INT then
            error("Day of month values must be between 1 and 31")
        end
    elseif type == TYPE_MONTH then
        if (val < 1 or val > 12 or stop > 12) and val ~= ALL_SPEC_INT then
            error("Month values must be between 1 and 12")
        end
    elseif type == TYPE_DAY_OF_WEEK then
        if (val < 1 or val > 7 or stop > 7) and val ~= ALL_SPEC_INT and val ~=
            NO_SPEC_INT then
            error("Day of week values must be between 1 and 7")
        end
    end
    if (incr == 0 or incr == -1) and val ~= ALL_SPEC_INT then
        if val ~= -1 then
            set_add(set, val)
        else
            set_add(set, NO_SPEC)
        end
        return
    end
    local start_at, stop_at = val, stop
    if val == ALL_SPEC_INT and incr <= 0 then
        incr = 1
        set_add(set, ALL_SPEC)
    end
    if type == TYPE_SECOND or type == TYPE_MINUTE then
        if stop_at == -1 then stop_at = 59 end
        if start_at == -1 or start_at == ALL_SPEC_INT then start_at = 0 end
    elseif type == TYPE_HOUR then
        if stop_at == -1 then stop_at = 23 end
        if start_at == -1 or start_at == ALL_SPEC_INT then start_at = 0 end
    elseif type == TYPE_DAY_OF_MONTH then
        if stop_at == -1 then stop_at = 31 end
        if start_at == -1 or start_at == ALL_SPEC_INT then start_at = 1 end
    elseif type == TYPE_MONTH then
        if stop_at == -1 then stop_at = 12 end
        if start_at == -1 or start_at == ALL_SPEC_INT then start_at = 1 end
    elseif type == TYPE_DAY_OF_WEEK then
        if stop_at == -1 then stop_at = 7 end
        if start_at == -1 or start_at == ALL_SPEC_INT then start_at = 1 end
    elseif type == TYPE_YEAR then
        if stop_at == -1 then stop_at = MAX_YEAR end
        if start_at == -1 or start_at == ALL_SPEC_INT then
            start_at = 1970
        end
    end
    local max = -1
    if stop_at < start_at then
        if type == TYPE_SECOND then
            max = 60
        elseif type == TYPE_MINUTE then
            max = 60
        elseif type == TYPE_HOUR then
            max = 24
        elseif type == TYPE_MONTH then
            max = 12
        elseif type == TYPE_DAY_OF_WEEK then
            max = 7
        elseif type == TYPE_DAY_OF_MONTH then
            max = 31
        else
            error("Start year must be less than stop year")
        end
        stop_at = stop_at + max
    end
    for i = start_at, stop_at, incr do
        if max == -1 then
            set_add(set, i)
        else
            local i2 = i % max
            if i2 == 0 and
                (type == TYPE_MONTH or type == TYPE_DAY_OF_WEEK or type ==
                    TYPE_DAY_OF_MONTH) then i2 = max end
            set_add(set, i2)
        end
    end
end

local function deal_field(self, type, fieldstr)
    -- print(self,type,fieldstr)
    local match_tbl = assert(MATCH_METHOD[type]:match(fieldstr))
    for _, val in pairs(match_tbl) do
        local t1, t2, t3 = table.unpack(val)
        if t1 == 1 then -- local NUMS=COM_NUMBERS/function(v) return table.concat({1,v},",") end
            add_to_set(self, t2, -1, 0, type)
        elseif t1 == 2 then -- local ANY=lpeg.P("*")/function(v) return table.concat({2},",") end
            add_to_set(self, ALL_SPEC_INT, -1, 0, type)
        elseif t1 == 3 then -- local RANGE=lpeg.Ct(COM_NUMBERS*lpeg.P("-")*COM_NUMBERS)/build2call(3)
            add_to_set(self, t2, t3, 1, type)
        elseif t1 == 4 then -- local EVERY=lpeg.Ct(COM_NUMBERS*lpeg.P("/")*COM_NUMBERS)/build2call(4)
            add_to_set(self, t2, -1, t3, type)
        elseif t1 == 5 then -- local REFANY=lpeg.P("?")/function(v) return table.concat({6},",") end
            assert(type == TYPE_DAY_OF_WEEK or type == TYPE_DAY_OF_MONTH)
            add_to_set(self, NO_SPEC_INT, -1, 0, type)
        end
    end
end

local function isleapyear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local day_num_of_month = {
    [1] = 31,
    [2] = nil,
    [3] = 31,
    [4] = 30,
    [5] = 31,
    [6] = 30,
    [7] = 31,
    [8] = 31,
    [9] = 30,
    [10] = 31,
    [11] = 30,
    [12] = 31
}
local function lastday_of_month(month, year)
    if month == 2 then
        return (isleapyear(year) and 29 or 28)
    else
        return day_num_of_month[month]
    end
end

local function time_set(cl, sec, min, hour, day, mon, year)
    if sec then cl.sec = sec end
    if min then cl.min = min end
    if hour then cl.hour = hour end
    if day then cl.day = day end
    if mon then cl.month = mon end
    if year then cl.year = year end
    local ncl = os.date("*t", os.time(cl))
    for k, v in pairs(ncl) do cl[k] = v end
    -- print("time_set",sec,min,hour,day,mon,year,os.date("%c",os.time(cl)))
end

local function get_timeafter(self, ti)
    local cl = os.date("*t", ti + 1)
    local gotone = false

    local self_seconds = self[TYPE_SECOND]
    local self_mintes = self[TYPE_MINUTE]
    local self_hours = self[TYPE_HOUR]
    local self_dayofmonth = self[TYPE_DAY_OF_MONTH]
    local self_months = self[TYPE_MONTH]
    local self_dayofweek = self[TYPE_DAY_OF_WEEK]
    local self_years = self[TYPE_YEAR]

    local function calc_step()
        -- print("calc_step")
        while not gotone do
            if cl.year > MAX_YEAR then return end
            local sec = cl.sec
            --------------------------sec---
            -- print("sec",cl.sec)
            local st = set_tail(self_seconds, sec)
            if st then
                sec = st
                time_set(cl, sec)
            else
                sec = self_seconds[1]
                time_set(cl, sec, cl.min + 1)
            end
            local min = cl.min
            local hr = cl.hour
            local t = -1
            -----------------------------min-
            -- print("min",cl.min)
            st = set_tail(self_mintes, min)
            if st then
                t = min
                min = st
            else
                min = self_mintes[1]
                hr = hr + 1
            end
            if min ~= t then
                time_set(cl, 0, min, hr)
                return calc_step()
            end
            time_set(cl, nil, min)
            hr = cl.hour
            local day = cl.day
            t = -1
            ------------------------hour-
            -- print("hour",cl.hour)
            st = set_tail(self_hours, hr)
            if st then
                t = hr
                hr = st
            else
                hr = self_hours[1]
                day = day + 1
            end
            if hr ~= t then
                time_set(cl, 0, 0, hr, day)
                return calc_step()
            end
            time_set(cl, nil, nil, hr)
            day = cl.day
            local mon = cl.month
            t = -1
            local tmon = mon
            ------------------day
            -- print("day",cl.day)
            local day_of_mspec = not set_contains(self_dayofmonth, NO_SPEC)
            local day_of_wspec = not set_contains(self_dayofweek, NO_SPEC)
            if day_of_mspec and not day_of_wspec then
                st = set_tail(self_dayofmonth, day)
                if st then
                    t = day
                    day = st
                    local lastday = lastday_of_month(mon, cl.year)
                    if day > lastday then
                        day = self_dayofmonth[1]
                        mon = mon + 1
                    end
                else
                    day = self_dayofmonth[1]
                    mon = mon + 1
                end
                if day ~= t or mon ~= tmon then
                    time_set(cl, 0, 0, 0, day, mon)
                    return calc_step()
                end
            elseif day_of_wspec and not day_of_mspec then
                local cdow = cl.wday
                local dow = self_dayofweek[1]
                st = set_tail(self_dayofweek, cdow)
                if st then dow = st end
                local days_to_add = 0
                if cdow < dow then days_to_add = dow - cdow end
                if cdow > dow then days_to_add = dow + (7 - cdow) end
                local lday = lastday_of_month(mon, cl.year)
                if day + days_to_add > lday then
                    time_set(cl, 0, 0, 0, 1, mon + 1)
                    return calc_step()
                elseif days_to_add > 0 then
                    time_set(cl, 0, 0, 0, day + days_to_add, mon)
                    return calc_step()
                end
            else
                error("")
            end
            time_set(cl, nil, nil, nil, day)
            mon = cl.month
            local year = cl.year
            t = -1
            if year > MAX_YEAR then return end
            --------------------month-
            -- print("month",cl.month)
            st = set_tail(self_months, mon)
            if st then
                t = mon
                mon = st
            else
                mon = self_months[1]
                year = year + 1
            end
            if mon ~= t then
                time_set(cl, 0, 0, 0, 1, mon, year)
                return calc_step()
            end
            time_set(cl, nil, nil, nil, nil, mon)
            year = cl.year
            ---------------year-
            -- print("year",cl.year)
            st = set_tail(self_years, year)
            if st then
                t = year
                year = st
            else
                assert(false)
                return
            end
            if year ~= t then
                time_set(cl, 0, 0, 0, 1, 1, year)
                return calc_step()
            end
            time_set(cl, nil, nil, nil, nil, nil, year)
            gotone = true
        end
        return os.time(cl)
    end
    return calc_step()
end

local _M = {}
function _M.expression(str)
    local match_row = ustring.split(str, " ")
    local self = {
        [TYPE_SECOND] = {},
        [TYPE_MINUTE] = {},
        [TYPE_HOUR] = {},
        [TYPE_DAY_OF_MONTH] = {},
        [TYPE_MONTH] = {},
        [TYPE_DAY_OF_WEEK] = {},
        [TYPE_YEAR] = {}
    }
    for type = TYPE_SECOND, TYPE_YEAR do
        local fieldstr = match_row[type]
        if type == TYPE_YEAR then
            deal_field(self, type, fieldstr or "*")
        elseif fieldstr then
            deal_field(self, type, assert(fieldstr))
        end
    end
    return self
end

function _M.next_time(self, ti)
    return get_timeafter(self, ti)
end

return _M
