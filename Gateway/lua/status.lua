local cjson = require("cjson.safe")

local _M = {}

function _M.serve()
    local gateway = require("gateway")
    local client, err = require("auth").authenticate()
    if not client then
        return gateway.json(401, "unauthorized", err)
    end

    if client.role ~= "admin" then
        return gateway.json(403, "forbidden", "status endpoint requires role admin")
    end

    local synced = ngx.shared.upstreams:get("synced_at")
    local cb = require("circuit_breaker")
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        service = "gateway",
        consul_service = "api",
        discovered_at = synced,
        age_seconds = synced and (ngx.now() - synced) or nil,
        node_count = cb.node_count(),
        upstream_nodes = cb.snapshot(),
    }))
end

return _M
