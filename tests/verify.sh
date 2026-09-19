#!/usr/bin/env bash
#
# Verifikasi end-to-end API Gateway (OpenResty) + service API.
# Menjalankan matriks uji: health, auth JWT, authorization role, validasi request,
# load balancing, rate limiter, dan circuit breaker/failover.
#
# Prasyarat: stack berjalan (docker compose up -d), tersedia `curl` dan `docker`.
#
# Pemakaian:
#   ./tests/verify.sh
#   BASE_URL=http://localhost:8080 BURST=300 ./tests/verify.sh
#   SKIP_CHAOS=1 ./tests/verify.sh
#
set -u

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
VIEWER_USER="${VIEWER_USER:-viewer}"
VIEWER_PASS="${VIEWER_PASS:-viewer123}"
BURST="${BURST:-300}"
SKIP_CHAOS="${SKIP_CHAOS:-0}"

PASS=0
FAIL=0

if [ -t 1 ]; then
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
    C_GREEN=""; C_RED=""; C_CYAN=""; C_YELLOW=""; C_RESET=""
fi

pass() { PASS=$((PASS + 1)); printf '%s[PASS]%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '%s[FAIL]%s %s -> %s\n' "$C_RED" "$C_RESET" "$1" "$2"; }
check() { if [ "$2" = "1" ]; then pass "$1"; else fail "$1" "${3:-}"; fi; }

LAST_CODE=0
LAST_BODY=""
LAST_UP=""

req() {
    local method="$1" path="$2" auth="${3:-}" body="${4:-}" ctype="${5:-}"
    local tmp hdr; tmp=$(mktemp); hdr=$(mktemp)
    local args=(-s -D "$hdr" -o "$tmp" -w '%{http_code}' -X "$method" "$BASE_URL$path")
    [ -n "$auth" ] && args+=(-H "Authorization: Bearer $auth")
    [ -n "$ctype" ] && args+=(-H "Content-Type: $ctype")
    [ -n "$body" ] && args+=(--data "$body")

    LAST_CODE=$(curl "${args[@]}")
    LAST_BODY=$(cat "$tmp")
    LAST_UP=$(grep -i '^x-upstream-addr:' "$hdr" | awk '{print $2}' | tr -d '\r' | head -n1)
    rm -f "$tmp" "$hdr"
}

get_token() {
    req POST "/auth/login" "" "username=$1&password=$2" "application/x-www-form-urlencoded"
    if [ "$LAST_CODE" != "200" ]; then
        fail "login $1" "code=$LAST_CODE body=$LAST_BODY"
        return 1
    fi
    printf '%s' "$LAST_BODY" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

printf '%s== Verifikasi gateway: %s ==%s\n\n' "$C_CYAN" "$BASE_URL" "$C_RESET"

printf -- '-- Prasyarat & health --\n'
req GET "/_gateway/health"
check "gateway health 200" "$([ "$LAST_CODE" = "200" ] && echo 1 || echo 0)" "code=$LAST_CODE"

ADMIN_TOKEN=$(get_token "$ADMIN_USER" "$ADMIN_PASS") || { echo "Tidak bisa lanjut tanpa token admin."; exit 1; }
check "login admin mendapat token" "$([ -n "$ADMIN_TOKEN" ] && echo 1 || echo 0)" "token kosong"

VIEWER_TOKEN=$(get_token "$VIEWER_USER" "$VIEWER_PASS") || true
check "login viewer mendapat token" "$([ -n "${VIEWER_TOKEN:-}" ] && echo 1 || echo 0)" "token kosong"

printf '\n-- Authentication --\n'
req GET "/menu"
check "GET /menu tanpa token -> 401" "$([ "$LAST_CODE" = "401" ] && echo 1 || echo 0)" "code=$LAST_CODE"
req GET "/menu" "not-a-valid-token"
check "GET /menu token invalid -> 401" "$([ "$LAST_CODE" = "401" ] && echo 1 || echo 0)" "code=$LAST_CODE"
req GET "/menu" "$ADMIN_TOKEN"
check "GET /menu admin -> 200" "$([ "$LAST_CODE" = "200" ] && echo 1 || echo 0)" "code=$LAST_CODE"
if [ -n "${VIEWER_TOKEN:-}" ]; then
    req GET "/menu" "$VIEWER_TOKEN"
    check "GET /menu viewer -> 200" "$([ "$LAST_CODE" = "200" ] && echo 1 || echo 0)" "code=$LAST_CODE"
fi

printf '\n-- Authorization --\n'
if [ -n "${VIEWER_TOKEN:-}" ]; then
    req POST "/menu" "$VIEWER_TOKEN" '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10}' "application/json"
    check "POST /menu viewer -> 403" "$([ "$LAST_CODE" = "403" ] && echo 1 || echo 0)" "code=$LAST_CODE body=$LAST_BODY"
fi
req GET "/_gateway/status" "${VIEWER_TOKEN:-}"
check "GET /_gateway/status viewer -> 403" "$([ "$LAST_CODE" = "403" ] && echo 1 || echo 0)" "code=$LAST_CODE"

printf '\n-- Request validation (POST /menu, admin) --\n'
req POST "/menu" "$ADMIN_TOKEN" '{"id_stand":1,"id_kategori":1,"nama_menu":"Soto Uji","harga":15000,"status":"tersedia"}' "application/json"
check "POST /menu valid -> 201" "$([ "$LAST_CODE" = "201" ] && echo 1 || echo 0)" "code=$LAST_CODE body=$LAST_BODY"

validate_case() {
    local name="$1" payload="$2"
    req POST "/menu" "$ADMIN_TOKEN" "$payload" "application/json"
    check "POST /menu $name -> 400" "$([ "$LAST_CODE" = "400" ] && echo 1 || echo 0)" "code=$LAST_CODE body=$LAST_BODY"
}
validate_case "harga <= 0"         '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":0}'
validate_case "field asing"        '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10,"foo":1}'
validate_case "field wajib kurang" '{"id_kategori":1,"nama_menu":"X","harga":10}'
validate_case "JSON rusak"         '{not-json'

printf '\n-- Load balancing --\n'
addrs=""
for _ in 1 2 3 4 5 6; do
    req GET "/menu" "$ADMIN_TOKEN"
    [ -n "$LAST_UP" ] && addrs="$addrs $LAST_UP"
done
distinct=$(printf '%s\n' $addrs | sort -u | wc -l | tr -d ' ')
printf '    upstream terlihat:%s\n' "$addrs"
check "round-robin menyentuh >= 2 replica" "$([ "$distinct" -ge 2 ] && echo 1 || echo 0)" "distinct=$distinct"

printf '\n-- Service discovery / status --\n'
req GET "/_gateway/status" "$ADMIN_TOKEN"
node_count=$(printf '%s' "$LAST_BODY" | grep -o '"node_count":[0-9]*' | grep -o '[0-9]*')
check "status endpoint 200 + node_count >= 1" "$([ "${node_count:-0}" -ge 1 ] && echo 1 || echo 0)" "node_count=${node_count:-0}"

printf '\n-- Rate limiter (burst paralel %s ke /) --\n' "$BURST"
urls=()
for _ in $(seq 1 "$BURST"); do urls+=("$BASE_URL/"); done
burst_out=$(curl --parallel --parallel-immediate --parallel-max "$BURST" -s -o /dev/null -w '%{http_code}\n' "${urls[@]}" 2>/dev/null)
count_200=$(printf '%s\n' "$burst_out" | grep -c '^200$')
count_429=$(printf '%s\n' "$burst_out" | grep -c '^429$')
printf '    hasil: 200=%s 429=%s\n' "$count_200" "$count_429"
check "burst memicu 429" "$([ "$count_429" -gt 0 ] && echo 1 || echo 0)" "tidak ada 429"

if [ "$SKIP_CHAOS" = "1" ]; then
    printf '\n%s-- Circuit breaker / failover: DILEWATI (SKIP_CHAOS=1) --%s\n' "$C_YELLOW" "$C_RESET"
else
    printf '\n-- Circuit breaker / failover --\n'
    mapfile -t apis < <(docker ps --filter "name=load-balance-dabd-api-" --format '{{.Names}}')
    check ">= 2 replica API berjalan" "$([ "${#apis[@]}" -ge 2 ] && echo 1 || echo 0)" "ditemukan=${#apis[@]}"

    if [ "${#apis[@]}" -ge 2 ]; then
        victim="${apis[0]}"
        victim_addr=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$victim")
        victim_addr="$victim_addr:8000"
        printf '    menghentikan replica: %s (%s)\n' "$victim" "$victim_addr"

        docker stop "$victim" >/dev/null
        sleep 1
        ok=0; err=0
        for _ in $(seq 1 15); do
            req GET "/menu" "$ADMIN_TOKEN"
            if [ "$LAST_CODE" = "200" ]; then ok=$((ok + 1)); else err=$((err + 1)); fi
            sleep 0.3
        done
        check "failover: mayoritas request tetap 200" "$([ "$ok" -ge 10 ] && echo 1 || echo 0)" "ok=$ok err=$err"

        req GET "/_gateway/status" "$ADMIN_TOKEN"
        status_body="$LAST_BODY"
        if printf '%s' "$status_body" | grep -q '"circuit":"open"'; then open=1; else open=0; fi
        if printf '%s' "$status_body" | grep -q "$victim_addr"; then listed=1; else listed=0; fi
        cb_ok=0
        if [ "$open" = "1" ] || [ "$listed" = "0" ]; then cb_ok=1; fi
        check "circuit breaker OPEN atau node di-deregister" "$cb_ok" "open=$open listed=$listed"

        docker start "$victim" >/dev/null
        printf '    menyalakan ulang %s, menunggu pemulihan (~12s)...\n' "$victim"
        sleep 12
        for _ in 1 2 3 4 5 6; do req GET "/menu" "$ADMIN_TOKEN" >/dev/null; sleep 0.3; done
        req GET "/_gateway/status" "$ADMIN_TOKEN"
        if printf '%s' "$LAST_BODY" | grep -q '"circuit":"open"'; then still_open=1; else still_open=0; fi
        check "pemulihan: semua node CLOSED" "$([ "$still_open" = "0" ] && echo 1 || echo 0)" "masih open"
    fi
fi

printf '\n%s== Ringkasan: %s PASS, %s FAIL ==%s\n' "$C_CYAN" "$PASS" "$FAIL" "$C_RESET"
[ "$FAIL" -eq 0 ]
