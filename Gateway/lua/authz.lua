local _M = {}

local PUBLIC = {
    ["/auth/login"] = true,
    ["/health"] = true,
    ["/"] = true,
    ["/docs"] = true,
    ["/docs/oauth2-redirect"] = true,
    ["/redoc"] = true,
    ["/openapi.json"] = true,
}

local READ_ONLY = {
    GET = true,
    HEAD = true,
    OPTIONS = true,
}

function _M.is_public(uri)
    return PUBLIC[uri] == true
end

function _M.authorize(client)
    local uri = ngx.var.uri
    local resource = uri:match("^/([^/]+)")
    if resource ~= "menu" then
        return nil, "unknown resource"
    end

    local method = ngx.req.get_method()
    if READ_ONLY[method] then
        return true
    end

    if client.role ~= "admin" then
        return nil, "role 'admin' is required for " .. method .. " " .. uri
    end
    return true
end

return _M
