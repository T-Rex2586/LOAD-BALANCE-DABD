local _M = {}

function _M.authenticate()
    local headers = ngx.req.get_headers()
    local key = headers["X-API-Key"]
    if type(key) == "table" then
        key = key[1]
    end

    if not key or key == "" then
        ngx.var.api_key_present = "0"
        return nil, "missing X-API-Key header"
    end

    ngx.var.api_key_present = "1"
    local client = require("apikeys").lookup(key)
    if not client then
        return nil, "invalid API key"
    end
    return client
end

return _M
