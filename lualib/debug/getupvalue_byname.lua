local maxinteger = math.maxinteger
local getupvalue = debug.getupvalue
return function(func, name)
    for i = 1, maxinteger do
        local nm, value = getupvalue(func, i)
        if not nm then break end
        if nm == name then return value, i, name end
    end
    error("not found upvalue " .. tostring(name))
end
