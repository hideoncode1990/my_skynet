#!/bin/bash
export ROOT=$(
	cd $(dirname $0)
	pwd
)

export logpath=$ROOT/logs

if [ ! -d $logpath ]; then
	mkdir $logpath
fi

if [ ! -d cservice ]; then
	mkdir cservice
fi
# function die() {
# 	if [ $2 -eq 0 ]  ;then
# 		echo "$1" && exit 0
# 	else
# 		echo "ERROR:$1" >&2 && exit $2
# 	fi
# }

# TMPFILE=$(mktemp) || die "mktemp failure" -1
# trap 'rm -f "$TMPFILE"' EXIT
# cat > $TMPFILE << EOF
#     print(string.format('export opts_%s="%s"\n', "version", "5.4"))
# EOF

# eval $(${ROOT}/skynet/3rd/lua/lua $TMPFILE $@)
# if [ $? -ne 0 ]; then
# 	exit -1
# fi

export node_type=$1
export node_id=$2

str="
    local result = {}
	local function getenv(name) return assert(os.getenv(name), [[os.getenv() failed: ]] .. name) end
	local sep = package.config:sub(1,1)
	local current_path = [[.]]..sep
	local function include(filename)
		local last_path = current_path
		local path, name = filename:match([[(.*]]..sep..[[)(.*)$]])
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
		code = string.gsub(code, [[%\$([%w_%d]+)]], getenv)
		f:close()
		assert(load(code,[[@]]..filename,[[t]],_G))()
		current_path = last_path
	end
    _G.include=include
	--setmetatable(result, { __index = { include = include } })
	local config_name = [[$ROOT/servercfg/$node_type.config]]
	include(config_name)
	setmetatable(result, nil)
	return result
"
#${ROOT}/skynet/3rd/lua/lua -e "$str"
make all
$ROOT/skynet/skynet $ROOT/servercfg/$node_type.config $node_type