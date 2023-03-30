local _M = {}

function _M.ser_function(v)
    local info = debug.getinfo(v)
    local src = info.short_src
    local line = info.linedefined
    return string.format('"%s"--[[%s:%d]]', v, src, line)
end

function _M.ser_table(t)
    local mark = {}
    local assign = {}
    local function _ser(tbl, parent, dep)
        dep = dep or 1
        mark[tbl] = parent
        local tmp = {}
        for k, v in pairs(tbl) do
            local key, con
            if type(k) == "number" then
                key = "[" .. k .. "]"
                con = ""
            elseif tonumber(k) then
                key = '["' .. k .. '"]'
                con = ""
            elseif type(k) == "string" then
                key = '["' .. k .. '"]'
                con = ""
            elseif type(k) == "function" then
                key = '["' .. _M.ser_function(k) .. '"]'
                con = ""
            else
                key = string.format('["%s:%s"]', type(k), tostring(k))
                con = ""
            end
            local space = "\n" .. string.rep("\t", dep)
            if type(v) == "table" then
                local dotkey = parent .. con .. key
                if mark[v] then
                    table.insert(assign, dotkey .. "=" .. mark[v])
                else
                    table.insert(tmp, space .. key .. "=" ..
                        _ser(v, dotkey, dep + 1))
                end
            elseif type(v) == "function" then
                table.insert(tmp, space .. key .. "=" .. _M.ser_function(v))
            elseif type(v) == "string" then
                table.insert(tmp, space .. key .. "='" .. tostring(v) .. "'")
            else
                table.insert(tmp, space .. key .. "=" .. tostring(v))
            end
        end
        return "{" .. table.concat(tmp, ",") .. "\n" ..
                   string.rep("\t", dep - 1) .. "}"
    end
    return
        "do\nlocal r=" .. _ser(t, "r") .. "\n" .. table.concat(assign, "\n") ..
            " \nreturn r \nend"
end

function _M.dumptable(t)
    return _M.ser_table(t)
end

function _M.dump(o)
    if type(o) == "table" then
        return _M.ser_table(o)
    elseif type(o) == "function" then
        return _M.ser_function(o)
    elseif type(o) == "string" then
        return string.format('"%s"', string.gsub(o, '"', '\\"'))
    elseif type(o) == "number" then
        return tostring(o)
    elseif type(o) == "nil" then
        return "nil"
    else
        return string.format("%s:%s", type(o), tostring(o))
    end
end

function _M.pdump(o, str)
    if str then
        print("--------------" .. tostring(str) .. "-------------------")
        print(_M.dump(o))
        print("--------------" .. tostring(str) .. "-----------------end")
    else
        print(_M.dump(o))
    end
end

function _M.ldump(o, str)
    if str then
        local tb = {"--------------" .. tostring(str) .. "-------------------"}
        table.insert(tb, _M.dump(o))
        table.insert(tb, "--------------" .. tostring(str) ..
            "-----------------end")
        require("log")(table.concat(tb, "\n"))
    else
        require("log")(_M.dump(o))
    end
end
_G.pdump = _M.pdump
_G.ldump = _M.ldump

return _M
