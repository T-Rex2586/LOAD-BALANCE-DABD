# Kantin Menu API + API Gateway (DABD - Load Balancing Demo)

REST API data menu kantin yang berjalan di belakang **API Gateway OpenResty**.
Gateway menangani reverse proxy, load balancing, service discovery (Consul),
circuit breaker, rate limiting, autentikasi JWT, authorization role, validasi
request, dan logging — semuanya dalam satu container nginx.

## Arsitektur

```
client ──▶ gateway (OpenResty :8080) ──▶ api replica 1 ──▶ PostgreSQL
                    │                    api replica 2
                    │                    api replica 3
                    └── consul (service discovery + health check)
```

- Gateway menemukan replica API secara dinamis dari Consul (`GET /v1/health/service/api?passing=true`).
- Tiap replica API mendaftar sendiri ke Consul saat start (`api/app/consul.py`).
- Gateway memverifikasi JWT (HS256) dan menegakkan role sebelum meneruskan ke API.
- API tetap memverifikasi JWT sendiri sebagai defense-in-depth.

## Stack
- Python 3.12 + FastAPI + Uvicorn (service `api`, 3 replica)
- PostgreSQL 16 (raw SQL, driver `psycopg` 3)
- JWT (PyJWT) untuk authentication & role-based authorization
- OpenResty 1.27 (nginx + Lua) sebagai API Gateway
- HashiCorp Consul sebagai service registry + health check
- Docker & Docker Compose

## Struktur
```
docker-compose.yml        # db + consul + api (3 replica) + gateway
docker-compose.dev.yml    # override: publish port 8000 untuk tes lokal
.env.example              # template konfigurasi
Database/init.sql         # DDL + seed data
api/
  Dockerfile
  requirements.txt
  app/
    main.py               # app FastAPI, lifespan, /health, /
    auth.py               # JWT, login, dependency auth
    consul.py             # self-register service ke Consul
    db.py                 # connection pool psycopg
    schemas.py            # model Pydantic
    routers/
      auth.py             # POST /auth/login
      menu.py             # CRUD /menu
Gateway/
  Dockerfile              # OpenResty + lua-resty-http/jsonschema/jwt/hmac
  conf/nginx.conf         # log_format, rate limit, upstream, shared dict
  conf.d/routes.conf      # routing, error JSON, header upstream
  lua/
    gateway.lua           # orkestrasi access phase (auth, authz, validasi, CB)
    auth.lua              # verifikasi JWT
    authz.lua             # public route + RBAC role
    validate.lua          # validasi JSON Schema
    discovery.lua         # sync daftar node dari Consul (timer)
    balancer.lua          # pilih replica (round-robin, skip circuit-open)
    circuit_breaker.lua   # state CLOSED/OPEN/HALF-OPEN
    logging.lua           # catat hasil upstream ke circuit breaker
    status.lua            # GET /_gateway/status (admin)
  schemas/menu.json       # JSON Schema body menu
```

## Endpoint (via gateway `http://localhost:8080`)
| Method | Path | Auth | Deskripsi |
|---|---|---|---|
| GET | `/health` | publik | Kesehatan API + DB |
| POST | `/auth/login` | publik | Login, dapat JWT (`form: username, password`) |
| GET | `/menu` | token | List menu (filter: `id_stand`, `id_kategori`, `status`) |
| GET | `/menu/{id_menu}` | token | Detail menu |
| POST | `/menu` | admin | Tambah menu |
| PUT | `/menu/{id_menu}` | admin | Ubah menu |
| DELETE | `/menu/{id_menu}` | admin | Hapus menu |
| GET | `/_gateway/health` | publik | Kesehatan gateway |
| GET | `/_gateway/status` | admin | Daftar node + status circuit breaker |

Dokumentasi FastAPI tetap tersedia di `http://localhost:8080/docs`.

### Body POST/PUT
```json
{ "id_stand": 1, "id_kategori": 1, "nama_menu": "Soto Ayam", "harga": 15000, "status": "tersedia" }
```
`status` hanya `tersedia` atau `habis`.

## Authentication & Authorization
Token JWT berisi `sub` (username), `role`, dan `exp`. Kirim sebagai header:
```
Authorization: Bearer <access_token>
```
- Gateway memverifikasi signature (`JWT_SECRET`), `exp`, dan role.
- Role `admin`: boleh GET, POST, PUT, DELETE.
- Role `viewer`: hanya boleh GET (write → `403`).
- Tanpa/invalid token → `401`.

Kredensial default (ubah lewat `.env`):
| Username | Password | Role |
|---|---|---|
| admin | admin123 | admin |
| viewer | viewer123 | viewer |

## Fitur Gateway
| Fitur | Implementasi |
|---|---|
| Reverse proxy | `proxy_pass http://api_backend` |
| Load balancing | `balancer_by_lua` round-robin (per-request `X-Upstream-Addr`) |
| Service discovery | timer 3s ke Consul → `lua_shared_dict upstreams` |
| Health check | Consul check `GET /health` tiap 5s |
| Circuit breaker | `lua_shared_dict cb_state`, 3 gagal → OPEN 10s → HALF-OPEN |
| Rate limiter | `limit_req`/`limit_conn` key dari `Authorization` (fallback IP) |
| Authentication | verifikasi JWT (lua-resty-jwt, whitelist HS256) |
| Authorization | role admin/viewer di `authz.lua` |
| Request validation | JSON Schema `schemas/menu.json` untuk POST/PUT `/menu` |
| Logging | `log_format` JSON ke stdout (request id, upstream, jwt sub/role) |

## Menjalankan
```bash
# salin config
copy .env.example .env      # PowerShell; Linux/macOS: cp .env.example .env

# jalankan seluruh stack (db + consul + 3 replica api + gateway)
docker compose up --build -d

# mode dev: publish API langsung di http://localhost:8000 (tanpa gateway)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# hentikan
docker compose down

# reset database (jalankan ulang init.sql)
docker compose down -v
```

## Contoh Pemakaian
```bash
# login admin lewat gateway
curl -X POST http://localhost:8080/auth/login \
  -d "username=admin&password=admin123"

TOKEN=<access_token>
curl http://localhost:8080/menu -H "Authorization: Bearer $TOKEN"

curl -X POST http://localhost:8080/menu \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id_stand":1,"id_kategori":1,"nama_menu":"Soto Ayam","harga":15000,"status":"tersedia"}'

# status node + circuit breaker (butuh token admin)
curl http://localhost:8080/_gateway/status -H "Authorization: Bearer $TOKEN"
```

## Uji Perilaku Gateway
```bash
# 401 tanpa token
curl -i http://localhost:8080/menu

# 403 viewer mencoba POST
VIEWER=<viewer_token>
curl -i -X POST http://localhost:8080/menu \
  -H "Authorization: Bearer $VIEWER" -H "Content-Type: application/json" \
  -d '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10}'

# 400 validasi JSON (harga <= 0 / field asing)
curl -i -X POST http://localhost:8080/menu \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":0}'

# 429 rate limit (burst banyak request)
for ($i=0; $i -lt 100; $i++) { curl -s -o $null http://localhost:8080/health }

# load balancing: lihat header X-Upstream-Addr berganti antar replica
curl -i http://localhost:8080/menu -H "Authorization: Bearer $TOKEN"

# circuit breaker: hentikan replica, lalu matikan semua
docker compose stop <api-container>   # sisa replica tetap melayani
docker compose stop api               # semua down -> 503 circuit_open
docker compose start api              # pulih -> closed
```

## Catatan
- `Database/docker-compose.yaml` adalah runner DB standalone (opsional); root `docker-compose.yml` sudah mencakup `db`.
- `init.sql` hanya dijalankan saat volume pertama dibuat; gunakan `down -v` untuk reseed.
- `JWT_SECRET` harus sama antara service `api` dan `gateway`.
