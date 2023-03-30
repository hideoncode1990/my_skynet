return setmetatable({left = 1, right = 2}, {
    __call = function(_, camp) -- 取对立阵营标识
        return camp ~ 3
    end
})
