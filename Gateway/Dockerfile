FROM openresty/openresty:1.27.1.2-alpine

RUN apk add --no-cache git \
    && git clone --depth 1 https://github.com/ledgetech/lua-resty-http.git /tmp/lua-resty-http \
    && cp /tmp/lua-resty-http/lib/resty/http.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-http/lib/resty/http_connect.lua /usr/local/openresty/lualib/resty/ \
    && cp /tmp/lua-resty-http/lib/resty/http_headers.lua /usr/local/openresty/lualib/resty/ \
    && git clone --depth 1 https://github.com/api7/jsonschema.git /tmp/jsonschema \
    && cp -r /tmp/jsonschema/lib/jsonschema.lua /usr/local/openresty/lualib/ \
    && cp -r /tmp/jsonschema/lib/jsonschema /usr/local/openresty/lualib/ \
    && rm -rf /tmp/lua-resty-http /tmp/jsonschema /var/cache/apk/*

COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/ /usr/local/openresty/nginx/conf/conf.d/
COPY lua/ /usr/local/openresty/nginx/lua/
COPY schemas/ /usr/local/openresty/nginx/schemas/
COPY keys.json /usr/local/openresty/nginx/keys.json

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
