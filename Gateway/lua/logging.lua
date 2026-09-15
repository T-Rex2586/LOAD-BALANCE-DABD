local _M = {}

local function split(value)
    local out = {}
    if not value or value == "" then
        return out
    end
    for item in value:gmatch("[^,]+") do
        out[#out + 1] = (item:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return out
end

function _M.log()
    local upstream_addr = ngx.var.upstream_addr
    if not upstream_addr or upstream_addr == "" then
        return
    end

    local addrs = split(upstream_addr)
    local statuses = split(ngx.var.upstream_status or "")
    local cb = require("circuit_breaker")

    for i, addr in ipairs(addrs) do
        local status = tonumber(statuses[i]) or 0
        local ok = status >= 200 and status < 500
        cb.record(addr, ok)
    end
end

return _M
