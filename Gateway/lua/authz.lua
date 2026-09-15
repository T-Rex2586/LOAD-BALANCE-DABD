local _M = {}

local RESOURCES = {
    stand = true,
    kategori = true,
    menu = true,
    transaksi = true,
    detail_transaksi = true,
}

local function required_scope(method, resource)
    if method == "GET" or method == "HEAD" or method == "OPTIONS" then
        return "read:" .. resource
    end
    return "write:" .. resource
end

local function has_scope(client, scope)
    for _, s in ipairs(client.scopes) do
        if s == "*" or s == scope then
            return true
        end
    end
    return false
end

function _M.authorize(client)
    local method = ngx.req.get_method()
    local resource = ngx.var.uri:match("^/([^/]+)")
    if not resource or not RESOURCES[resource] then
        return nil, "unknown resource"
    end

    local scope = required_scope(method, resource)
    if not has_scope(client, scope) then
        return nil, "missing required scope: " .. scope
    end

    ngx.ctx.required_scope = scope
    return true
end

return _M
