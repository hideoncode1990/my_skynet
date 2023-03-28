#!/bin/bash

export ROOT=$(
	cd $(dirname $0)
	pwd
)

function die() {
	if [ $2 -eq 0 ]  ;then
		echo "$1" && exit 0
	else
		echo "ERROR:$1" >&2 && exit $2
	fi
}

TMPFILE=$(mktemp) || die "mktemp failure" -1
trap 'rm -f "$TMPFILE"' EXIT
cat > $TMPFILE << EOF
    print(string.format('export opts_%s="%s"\n', "version", "5.4"))
EOF

eval $(${ROOT}/skynet/3rd/lua/lua $TMPFILE $@)
if [ $? -ne 0 ]; then
	exit -1
fi

str="
    local result = {}
	local function getenv(name) return assert(os.getenv(name), [[os.getenv() failed: ]] .. name) end
	local sep = package.config:sub(1,1)
	print([[package.config]],package.config)
    print([[++++++++++++++++++]])
	print([[sep]],sep)
	local current_path = [[.]]..sep
    print([[current_path]],current_path)
	local function include(filename)
		local last_path = current_path
		local path, name = filename:match([[(.*]]..sep..[[)(.*)$]])
        print([[path:]],path,[[name:]],name)
		if path then
			if path:sub(1,1) == sep then	-- root
				current_path = path
			else
				current_path = current_path .. path
			end
		else
			name = filename
		end
		local f = assert(io.open(current_path .. name))
		local code = assert(f:read [[*a]])
        print([[++++++++++++++++++]])
        print([[code_before]],code)
		code = string.gsub(code, [[%\$([%w_%d]+)]], getenv)
        print([[code_after]],code)
		f:close()
		assert(load(code,[[@]]..filename,[[t]],_G))()
		current_path = last_path
	end
    _G.include=include
	--setmetatable(result, { __index = { include = include } })
	local config_name = ...
	include(config_name)
	print([[config_name:::::]],config_name)
	setmetatable(result, nil)
	return result
"


$ROOT/skynet/skynet "$str" $1