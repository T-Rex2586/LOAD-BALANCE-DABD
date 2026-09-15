local cjson = require("cjson.safe")

local _M = {}
local store = {}

local KEYS_FILE = "/usr/local/openresty/nginx/keys.json"

function _M.init()
    local f = io.open(KEYS_FILE, "r")
    if not f then
        ngx.log(ngx.ERR, "apikeys: cannot open ", KEYS_FILE)
        return
    end
    local raw = f:read("*a")
    f:close()

    local decoded = cjson.decode(raw)
    if type(decoded) ~= "table" then
        ngx.log(ngx.ERR, "apikeys: invalid JSON in ", KEYS_FILE)
        return
    end

    local count = 0
    for _, item in ipairs(decoded.keys or {}) do
        if item.key and item.id then
            store[item.key] = { id = item.id, scopes = item.scopes or {} }
            count = count + 1
        end
    end
    ngx.log(ngx.NOTICE, "apikeys: loaded ", count, " API key(s)")
end

function _M.lookup(key)
    return store[key]
end

return _M
