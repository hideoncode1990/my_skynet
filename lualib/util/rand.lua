local function sortcmp(a, b)
    return (a[2] - a[1]) > (b[2] - b[1])
end
local function roll(list)
    table.sort(list, sortcmp)
    local c = table.remove(list, 1)
    local r = math.random(c[1], c[2])
    if r > c[1] then table.insert(list, {c[1], r - 1}) end
    if r < c[2] then table.insert(list, {r + 1, c[2]}) end
    return r
end
return function(cnt, max, min)
    min = min or 1
    assert(cnt <= (max - min))
    local ret = {}
    local list = {{min, max}}
    while cnt > 0 do
        local r = roll(list)
        table.insert(ret, r)
        cnt = cnt - 1
    end
    return ret
end
