local cjson = require("cjson.safe")
local jsonschema = require("jsonschema")

local _M = {}

local SCHEMA_DIR = "/usr/local/openresty/nginx/schemas/"
local BODY_METHODS = { POST = true, PUT = true, PATCH = true }
local validators = {}

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function get_validator(resource)
    if validators[resource] ~= nil then
        return validators[resource]
    end

    local raw = read_file(SCHEMA_DIR .. resource .. ".json")
    if not raw then
        return nil, "no schema defined for resource: " .. resource
    end

    local schema = cjson.decode(raw)
    if type(schema) ~= "table" then
        return nil, "invalid schema file for resource: " .. resource
    end

    local ok, validator = pcall(jsonschema.generate_validator, schema)
    if not ok then
        return nil, "failed to compile schema for " .. resource .. ": " .. tostring(validator)
    end

    validators[resource] = validator
    return validator
end

local function read_body()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    if data then
        return data
    end

    local path = ngx.req.get_body_file()
    if path then
        return read_file(path)
    end
    return nil
end

function _M.validate()
    local method = ngx.req.get_method()
    if not BODY_METHODS[method] then
        return true
    end

    local resource = ngx.var.uri:match("^/([^/]+)")
    if not resource then
        return nil, "unknown resource"
    end

    local ctype = string.lower(ngx.var.content_type or "")
    if not ctype:find("application/json", 1, true) then
        return nil, "Content-Type must be application/json"
    end

    local raw = read_body()
    if not raw or raw == "" then
        return nil, "request body is required"
    end

    local body, derr = cjson.decode(raw)
    if body == nil then
        return nil, "malformed JSON body: " .. tostring(derr)
    end

    local validator, verr = get_validator(resource)
    if not validator then
        return nil, verr
    end

    local ok, err = validator(body)
    if not ok then
        return nil, "schema validation failed: " .. tostring(err)
    end

    ngx.req.set_body_data(cjson.encode(body))
    ngx.ctx.body_validated = true
    return true
end

return _M
