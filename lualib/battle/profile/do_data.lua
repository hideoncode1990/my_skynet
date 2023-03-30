return function(data)
    local total_cost = 0
    local total_cnt = 0
    local list = {}
    for frame, d in pairs(data) do
        local cnt = d.cnt
        local cost = d.cost
        d.ave = cost / cnt
        local maxcost = d.max[1]
        local mincost = d.min[1]
        table.insert(list, {frame, d.ave, cnt, maxcost, mincost})

        total_cnt = total_cnt + cnt
        total_cost = total_cost + cost
    end
    local total_ave = total_cost / total_cnt

    table.sort(list, function(a, b)
        return a[1] < b[1]
    end)

    local t = {}
    for i, v in ipairs(list) do
        t[i] = string.format("[%d]={ave=%f,cnt=%d,max=%5.2f,min=%5.2f}",
            table.unpack(v))
    end

    ldump({cnt = total_cnt, cost = total_cost, ave = total_ave, list = t},
        "profile all")
end
