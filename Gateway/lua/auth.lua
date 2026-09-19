local jwt = require("resty.jwt")

local _M = {}

local SECRET = os.getenv("JWT_SECRET") or "change-me-in-production"
local ALGORITHM = os.getenv("JWT_ALGORITHM") or "HS256"

function _M.authenticate()
    local headers = ngx.req.get_headers()
    local authorization = headers["Authorization"]
    if type(authorization) == "table" then
        authorization = authorization[1]
    end

    if not authorization or authorization == "" then
        return nil, "missing Authorization header"
    end

    local token = authorization:match("^%s*[Bb]earer%s+(.+)$")
    if not token then
        return nil, "Authorization header must use the Bearer scheme"
    end

    jwt:set_alg_whitelist({ [ALGORITHM] = true })
    local obj = jwt:verify(SECRET, token)
    if not obj.verified then
        return nil, "invalid token: " .. tostring(obj.reason)
    end

    local payload = obj.payload
    if type(payload) ~= "table" then
        return nil, "invalid token payload"
    end
    if not payload.exp or tonumber(payload.exp) < ngx.time() then
        return nil, "token expired"
    end

    ngx.var.jwt_sub = payload.sub or ""
    ngx.var.jwt_role = payload.role or ""

    return { sub = payload.sub or "", role = payload.role or "" }
end

return _M
