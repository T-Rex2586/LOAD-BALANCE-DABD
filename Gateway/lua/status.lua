local cjson = require("cjson.safe")

local _M = {}

function _M.serve()
    local gateway = require("gateway")
    local client = require("auth").authenticate()
    if not client then
        return gateway.json(401, "unauthorized", "missing or invalid X-API-Key")
    end

    local is_admin = false
    for _, scope in ipairs(client.scopes) do
        if scope == "*" then
            is_admin = true
        end
    end
    if not is_admin then
        return gateway.json(403, "forbidden", "status endpoint requires admin scope")
    end

    local synced = ngx.shared.upstreams:get("synced_at")
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        service = "gateway",
        console = "api",
        consul_service = "api",
        discovered_at = synced,
        age_seconds = synced and (ngx.now() - synced) or nil,
        upstream_nodes = require("circuit_breaker").snapshot(),
    }))
end

return _M
