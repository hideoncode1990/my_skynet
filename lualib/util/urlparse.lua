local tonumber = tonumber
local type = type
local string = string

local function decode(str, path)
	if not path then
		str = str:gsub('+', ' ')
	end
	return (str:gsub("%%(%x%x)", function(c)
		return string.char(tonumber(c, 16))
	end))
end

local function parseQuery(str, sep)
	if not sep then
		sep = '&'
	end

	local values = {}
	for kkey,val in str:gmatch(string.format('([^%q=]+)(=*[^%q=]*)', sep, sep)) do
		local key = decode(kkey)
		local keys = {}
		key = key:gsub('%[([^%]]*)%]', function(v)
				-- extract keys between balanced brackets
				if string.find(v, "^-?%d+$") then
					v = tonumber(v)
				else
					v = decode(v)
				end
				table.insert(keys, v)
				return "="
		end)
		key = key:gsub('=+.*$', "")
		key = key:gsub('%s', "_") -- remove spaces in parameter name
		val = val:gsub('^=+', "")

		if not values[key] then
			values[key] = {}
		end
		if #keys > 0 and type(values[key]) ~= 'table' then
			values[key] = {}
		elseif #keys == 0 and type(values[key]) == 'table' then
			values[key] = decode(val)
		end

		local t = values[key]
		for i,k in ipairs(keys) do
			if type(t) ~= 'table' then
				t = {}
			end
			if k == "" then
				k = #t+1
			end
			if not t[k] then
				t[k] = {}
			end
			if i == #keys then
				t[k] = decode(val)
			end
			t = t[k]
		end
	end
	return values
end

local function setQuery(self, query)
	self.query = parseQuery(query)
	return query
end

local function setAuthority(self, authority)
	self.authority = authority
	self.port = nil
	self.host = nil
	self.userinfo = nil
	self.user = nil
	self.password = nil

	authority = authority:gsub('^([^@]*)@', function(v)
		self.userinfo = v
		return ''
	end)
	authority = authority:gsub("^%[[^%]]+%]", function(v) -- ipv6
		self.host = v
		return ''
	end)
	authority = authority:gsub(':([^:]*)$', function(v)
		self.port = tonumber(v)
		return ''
	end)
	if authority ~= '' and not self.host then
		self.host = authority:lower()
	end
	if self.userinfo then
		local userinfo = self.userinfo
		userinfo = userinfo:gsub(':([^:]*)$', function(v)
				self.password = v
				return ''
		end)
		self.user = userinfo
	end
	return authority
end

return function (url)
	local comp = {}
	setAuthority(comp, "")
	setQuery(comp, "")

	url = tostring(url or '')
	url = url:gsub('#(.*)$', function(v)
		comp.fragment = v
		return ''
	end)
	url =url:gsub('^([%w][%w%+%-%.]*)%:', function(v)
		comp.scheme = v:lower()
		return ''
	end)
	url = url:gsub('%?(.*)', function(v)
		setQuery(comp, v)
		return ''
	end)
	url = url:gsub('^//([^/]*)', function(v)
        setAuthority(comp, v)
		return ''
	end)
	comp.path = decode(url, true)
	return comp
end
