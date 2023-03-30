local function new_meta(rt,call_once_list)
	call_once_list=call_once_list or {}
	local mt={}
	function mt.__index(_,k)
		return rt[k]
	end
	function mt.__newindex(_,k,v)
		local val=rt[k]
		if not val then
			rt[k]=v
		elseif type(val)=="table" then
			table.insert(val,v)
		elseif v then
			rt[k]={val,v}
		else
			rt[k]=nil
		end
	end
	function mt.__call(_,k,...)
		local calls
		if type(k)=="string" then
			calls=rt[k]
		else
			calls=k
		end
		if calls then
			if call_once_list[k] then rt[k]=nil end
			if type(calls)=="table" then
				for _,v in pairs(calls) do
					v(...)
				end
			else
				return calls(...)
			end
		end
	end
	function mt.__pairs(_)
		return pairs(rt)
	end
	function mt.__tostring(_)
		return tostring(rt)
	end
	return mt
end

return function(call_once_list)
	return setmetatable({},new_meta({},call_once_list))
end