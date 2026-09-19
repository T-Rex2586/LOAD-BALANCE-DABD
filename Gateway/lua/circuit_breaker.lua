local cjson = require("cjson.safe")

local _M = {}

local dict = ngx.shared.cb_state
local upstreams = ngx.shared.upstreams
local THRESHOLD = 3
local OPEN_TIMEOUT = 10

local function key(addr, suffix)
    return "cb:" .. addr .. (suffix or "")
end

function _M.is_open(addr)
    local state = dict:get(key(addr))
    if state ~= "open" then
        return false
    end

    local opened = dict:get(key(addr, ":opened")) or 0
    if ngx.now() - opened >= OPEN_TIMEOUT then
        dict:set(key(addr), "half")
        ngx.log(ngx.WARN, "circuit_breaker: HALF-OPEN for ", addr)
        return false
    end
    return true
end

function _M.record(addr, ok)
    if not addr or addr == "" then
        return
    end

    if ok then
        dict:set(key(addr, ":fail"), 0)
        dict:set(key(addr), "closed")
        return
    end

    local fails = dict:incr(key(addr, ":fail"), 1, 0)
    local state = dict:get(key(addr))
    if fails >= THRESHOLD or state == "half" then
        dict:set(key(addr), "open")
        dict:set(key(addr, ":opened"), ngx.now())
        ngx.log(ngx.WARN, "circuit_breaker: OPEN for ", addr, " after ", fails, " failure(s)")
    end
end

function _M.node_count()
    local raw = upstreams:get("nodes")
    if not raw then
        return 0
    end
    local nodes = cjson.decode(raw)
    if type(nodes) ~= "table" then
        return 0
    end
    return #nodes
end

function _M.all_open()
    local raw = upstreams:get("nodes")
    if not raw then
        return false
    end

    local nodes = cjson.decode(raw)
    if type(nodes) ~= "table" or #nodes == 0 then
        return false
    end

    for _, n in ipairs(nodes) do
        if not _M.is_open(n.addr) then
            return false
        end
    end
    return true
end

function _M.snapshot()
    local raw = upstreams:get("nodes")
    local nodes = raw and cjson.decode(raw) or {}
    local out = {}

    for _, n in ipairs(nodes) do
        out[#out + 1] = {
            addr = n.addr,
            id = n.id,
            circuit = dict:get(key(n.addr)) or "closed",
            failures = dict:get(key(n.addr, ":fail")) or 0,
        }
    end
    return out
end

return _M
