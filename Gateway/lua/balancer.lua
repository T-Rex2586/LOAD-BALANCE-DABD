local cjson = require("cjson.safe")
local balancer = require("ngx.balancer")

local _M = {}

local dict = ngx.shared.upstreams

function _M.balance()
    local raw = dict:get("nodes")
    if not raw then
        ngx.log(ngx.ERR, "balancer: discovery data not ready")
        return
    end

    local nodes = cjson.decode(raw)
    if type(nodes) ~= "table" or #nodes == 0 then
        ngx.log(ngx.ERR, "balancer: no healthy nodes available")
        return
    end

    local cb = require("circuit_breaker")
    local avail = {}
    for _, n in ipairs(nodes) do
        if not cb.is_open(n.addr) then
            avail[#avail + 1] = n
        end
    end

    if #avail == 0 then
        ngx.log(ngx.ERR, "balancer: all nodes are circuit-open")
        return
    end

    local idx = dict:incr("rr", 1, 0)
    local node = avail[(idx % #avail) + 1]

    local ok, err = balancer.set_current_peer(node.host, node.port)
    if not ok then
        ngx.log(ngx.ERR, "balancer: set_current_peer failed: ", err)
    end
end

return _M
