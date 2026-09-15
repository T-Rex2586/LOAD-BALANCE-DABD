local cjson = require("cjson.safe")
local http = require("resty.http")

local _M = {}

local dict = ngx.shared.upstreams
local CONSUL = "http://consul:8500"
local SERVICE = "api"
local INTERVAL = 3

function _M.start()
    local ok, err = ngx.timer.every(INTERVAL, _M.sync)
    if not ok then
        ngx.log(ngx.ERR, "discovery: failed to create timer: ", err)
    end
end

function _M.sync(premature)
    if premature then
        return
    end

    local client = http.new()
    client:set_timeout(2000)

    local url = CONSUL .. "/v1/health/service/" .. SERVICE .. "?passing=true"
    local res, err = client:request_uri(url, { method = "GET" })
    if not res then
        ngx.log(ngx.ERR, "discovery: consul request failed: ", err)
        return
    end
    if res.status ~= 200 then
        ngx.log(ngx.ERR, "discovery: consul returned status ", res.status)
        return
    end

    local data = cjson.decode(res.body)
    if type(data) ~= "table" then
        ngx.log(ngx.ERR, "discovery: invalid consul response")
        return
    end

    local nodes = {}
    for _, entry in ipairs(data) do
        local svc = entry.Service or {}
        local addr = svc.Address
        if not addr or addr == "" then
            addr = (entry.Node or {}).Address
        end
        if addr and svc.Port then
            nodes[#nodes + 1] = {
                id = svc.ID or (addr .. ":" .. tostring(svc.Port)),
                host = addr,
                port = svc.Port,
                addr = addr .. ":" .. tostring(svc.Port),
            }
        end
    end

    dict:set("nodes", cjson.encode(nodes))
    dict:set("synced_at", ngx.now())
    ngx.log(ngx.NOTICE, "discovery: ", #nodes, " healthy node(s) for service '", SERVICE, "'")
end

return _M
