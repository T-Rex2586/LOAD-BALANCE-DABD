local cjson = require("cjson.safe")

local _M = {}

local STATUS = {
    [408] = { "request_timeout", "upstream request timed out" },
    [413] = { "payload_too_large", "request body is too large" },
    [429] = { "rate_limited", "too many requests" },
    [500] = { "internal_error", "internal server error" },
    [502] = { "bad_gateway", "no healthy upstream instance" },
    [503] = { "service_unavailable", "service temporarily unavailable" },
    [504] = { "gateway_timeout", "upstream did not respond in time" },
}

function _M.json(status, code, message, extra)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"

    local body = { error = { code = code, message = message } }
    if extra then
        for k, v in pairs(extra) do
            body.error[k] = v
        end
    end

    ngx.say(cjson.encode(body))
    return ngx.exit(status)
end

function _M.error_page()
    local status = ngx.status
    if not status or status < 400 then
        status = 500
    end
    local info = STATUS[status] or { "error", "request failed" }
    return _M.json(status, info[1], info[2])
end

function _M.access()
    local client, err = require("auth").authenticate()
    if not client then
        return _M.json(401, "unauthorized", err)
    end

    ngx.ctx.client = client
    ngx.var.client_id = client.id
    ngx.req.set_header("X-Client-Id", client.id)
    ngx.req.set_header("X-Client-Scopes", table.concat(client.scopes, ","))
    ngx.req.set_header("X-API-Key", nil)

    local ok, aerr = require("authz").authorize(client)
    if not ok then
        return _M.json(403, "forbidden", aerr)
    end

    local vok, verr = require("validate").validate()
    if not vok then
        return _M.json(400, "invalid_request", verr)
    end

    if require("circuit_breaker").all_open() then
        return _M.json(503, "circuit_open", "all upstream instances are circuit-open")
    end
end

return _M
