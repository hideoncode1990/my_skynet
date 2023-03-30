local _M = {}

function _M.set(data, idx)
    idx = idx - 1
    local i = idx // 64 + 1
    local b = idx % 64
    for _ = #data + 1, i do table.insert(data, 0) end

    local n = data[i]
    local _b = 1 << b
    if not ((n & _b) == _b) then
        data[i] = n | _b
        return true
    end
end

function _M.get(data, idx)
    idx = idx - 1
    local i = idx // 64 + 1
    local n = data[i]
    if not data[i] then return false end
    local b = 1 << (idx % 64)
    return (n & b) == b
end

function _M.iter(data)
    local idx = 1
    local bit = 0
    return function()
        while true do
            if bit == 64 then idx, bit = idx + 1, 0 end
            local i, b = idx, bit

            local bits = data[i]
            if not bits then
                return nil
            else
                if (bits >> b) & 1 == 1 then
                    local result = (i - 1) * 64 + b + 1
                    bit = bit + 1
                    return result
                end
            end
            bit = bit + 1
        end
    end
end

return _M
