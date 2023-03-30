local searchpath = package.searchpath

local flags = {}

local function replace(source)
    for _, flag in ipairs(flags) do source = source:gsub("-- " .. flag, flag) end
    return source
end

local function checkload(name, fname)
    local f<close> = assert(io.open(fname))
    local source = f:read("a")
    local ok, err = load(replace(source), "battle@" .. fname)
    if not ok then
        error(string.format("error loading module '%s' from file '%s':\n\t%s",
            name, fname, err))
    else
        return ok, fname
    end
end

local function loader(name)
    local fname, err = searchpath(name, package.path)
    if not fname then return err end
    return checkload(name, fname)
end

return function(_flags)
    flags = assert(_flags)
    table.remove(package.searchers, 2)
    table.insert(package.searchers, 2, loader)
end
