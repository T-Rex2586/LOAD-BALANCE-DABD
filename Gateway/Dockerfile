FROM openresty/openresty:1.27.1.2-alpine

RUN apk add --no-cache git \
    && git clone --depth 1 https://github.com/ledgetech/lua-resty-http.git /tmp/lua-resty-http \
    && cp /tmp/lua-resty-http/lib/resty/http.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-http/lib/resty/http_connect.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-http/lib/resty/http_headers.lua /usr/local/openresty/lualib/resty/ \
    && git clone --depth 1 https://github.com/api7/jsonschema.git /tmp/jsonschema \
    && cp /tmp/jsonschema/lib/jsonschema.lua /usr/local/openresty/lualib/ \
    && cp -r /tmp/jsonschema/lib/jsonschema /usr/local/openresty/lualib/ \
    && git clone --depth 1 https://github.com/golgote/neturl.git /tmp/neturl \
    && mkdir -p /usr/local/openresty/lualib/net \
    && cp /tmp/neturl/lib/net/url.lua /usr/local/openresty/lualib/net/ \
    && git clone --depth 1 https://github.com/api7/lua-resty-jwt.git /tmp/lua-resty-jwt \
    && cp /tmp/lua-resty-jwt/lib/resty/jwt.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-jwt/lib/resty/evp.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-jwt/lib/resty/jwt-validators.lua /usr/local/openresty/lualib/resty/ \
    && git clone --depth 1 https://github.com/fffonion/lua-resty-openssl.git /tmp/lua-resty-openssl \
    && cp /tmp/lua-resty-openssl/lib/resty/openssl.lua /usr/local/openresty/lualib/resty/ \
    && cp -r /tmp/lua-resty-openssl/lib/resty/openssl /usr/local/openresty/lualib/resty/ \
    && git clone --depth 1 https://github.com/jkeys089/lua-resty-hmac.git /tmp/lua-resty-hmac \
    && cp /tmp/lua-resty-hmac/lib/resty/hmac.lua /usr/local/openresty/lualib/resty/ \
    && rm -rf /tmp/lua-resty-http /tmp/jsonschema /tmp/neturl /tmp/lua-resty-jwt /tmp/lua-resty-openssl /tmp/lua-resty-hmac /var/cache/apk/*

COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/ /usr/local/openresty/nginx/conf/conf.d/
COPY lua/ /usr/local/openresty/nginx/lua/
COPY schemas/ /usr/local/openresty/nginx/schemas/

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
