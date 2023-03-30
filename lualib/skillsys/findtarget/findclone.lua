-- 寻找自己的召唤物
local insert = table.insert

return function(bctx, ecfg, src, tobj, x, y)
    if not src then return {} end
    local clones = src.clones
    if not clones then return {} end
    local r = {}
    for _, o in pairs(clones) do insert(r, o) end
    return r
end
