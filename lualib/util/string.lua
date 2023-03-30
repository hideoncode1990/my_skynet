local ext = require "ext.c"

local _M = {}

local gsub = string.gsub
local tonumber = tonumber

function _M.strfmt(fmt, ...)
    local params = {...}
    return (gsub(fmt, "{(%d+)}", function(k)
        return params[tonumber(k)]
    end))
end

_M.split = ext.split

_M.splitrow = ext.splitrow

function _M.bin2hex(s)
    return (string.gsub(s, "(.)", function(x)
        return string.format("%02x", string.byte(x))
    end))
end

function _M.int2hex(n)
    local b2h = {
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D",
        "E", "F"
    }
    if n == 0 then return "0" end
    local s = ""
    local f = ""
    if n < 0 then
        f = "-"
        n = 0 - s
    end
    while n > 0 do
        s = b2h[(n & 0xf) + 1] .. s
        n = n >> 4
    end
    return f .. s
end

function _M.hex2bin(hexstr)
    local h2b = {
        ["0"] = 0,
        ["1"] = 1,
        ["2"] = 2,
        ["3"] = 3,
        ["4"] = 4,
        ["5"] = 5,
        ["6"] = 6,
        ["7"] = 7,
        ["8"] = 8,
        ["9"] = 9,
        ["a"] = 10,
        ["b"] = 11,
        ["c"] = 12,
        ["d"] = 13,
        ["e"] = 14,
        ["f"] = 15,
        ["A"] = 10,
        ["B"] = 11,
        ["C"] = 12,
        ["D"] = 13,
        ["E"] = 14,
        ["F"] = 15
    }
    return (string.gsub(hexstr, "(.)(.)%s", function(h, l)
        return string.char(h2b[h] * 16 + h2b[l])
    end))
end

return _M
