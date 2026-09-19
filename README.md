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
tests/
  verify.ps1              # verifikasi end-to-end (PowerShell)
  verify.sh               # verifikasi end-to-end (bash)
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
| Health check | Consul check `GET /health` tiap 30s (lihat `api/app/consul.py`) |
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

## Verifikasi Otomatis
Prasyarat: stack berjalan (`docker compose up -d`) dan Docker CLI tersedia.
Script menjalankan seluruh matriks di bawah, mencetak `PASS/FAIL`, dan keluar
dengan kode `0` bila semua lulus.

PowerShell (Windows):
```powershell
# jalankan semua uji (termasuk failover/circuit breaker)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1

# lewati uji chaos (tidak menghentikan replica)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1 -SkipChaos

# ganti target/burst
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1 -BaseUrl http://localhost:8080 -Burst 300
```

Bash (Linux/macOS/Git Bash):
```bash
bash tests/verify.sh
SKIP_CHAOS=1 bash tests/verify.sh
BASE_URL=http://localhost:8080 BURST=300 bash tests/verify.sh
```

## Matriks Uji Manual
Definisikan `G=http://localhost:8080`. Ambil token lebih dulu:
```bash
TOKEN=$(curl -s -X POST $G/auth/login -d "username=admin&password=admin123" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
VIEWER=$(curl -s -X POST $G/auth/login -d "username=viewer&password=viewer123" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
```

| # | Skenario | Perintah (ringkas) | Diharapkan |
|---|---|---|---|
| 1 | Health gateway | `curl -i $G/_gateway/health` | `200 {"status":"ok"}` |
| 2 | Login admin/viewer | `curl -i -X POST $G/auth/login -d "username=admin&password=admin123"` | `200` + `access_token` |
| 3 | Tanpa token | `curl -i $G/menu` | `401 unauthorized` |
| 4 | Token invalid | `curl -i $G/menu -H "Authorization: Bearer x"` | `401` |
| 5 | GET menu (admin) | `curl -i $G/menu -H "Authorization: Bearer $TOKEN"` | `200` + data |
| 6 | GET menu (viewer) | `curl -i $G/menu -H "Authorization: Bearer $VIEWER"` | `200` |
| 7 | Viewer mencoba write | `curl -i -X POST $G/menu -H "Authorization: Bearer $VIEWER" -H "Content-Type: application/json" -d '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10}'` | `403 forbidden` |
| 8 | Validasi `harga <= 0` | POST (admin) `{"...","harga":0}` | `400 invalid_request` |
| 9 | Validasi field asing | POST (admin) `{"...","harga":10,"foo":1}` | `400` |
| 10 | Validasi field kurang | POST (admin) tanpa `id_stand` | `400` |
| 11 | JSON rusak | POST (admin) `{not-json` | `400` |
| 12 | POST valid | POST (admin) body lengkap | `201` |
| 13 | Load balancing | `curl -i $G/menu -H "Authorization: Bearer $TOKEN"` beberapa kali | header `X-Upstream-Addr` berganti antar replica |
| 14 | Status discovery/CB | `curl -s $G/_gateway/status -H "Authorization: Bearer $TOKEN"` | JSON `node_count` + `upstream_nodes[].circuit` |
| 15 | Rate limit | burst paralel (lihat `tests/verify.*`) | sebagian request `429 rate_limited` |
| 16 | Failover | `docker stop load-balance-dabd-api-1` lalu `curl $G/menu` | tetap `200` dari replica lain |
| 17 | Circuit breaker | hammer `GET /menu`, lalu cek status | node mati `"circuit":"open"` |
| 18 | Pemulihan CB | `docker start load-balance-dabd-api-1`, tunggu ~12s | node kembali `"closed"` |
| 19 | Semua replica mati | `docker stop` semua `load-balance-dabd-api-*`, lalu `curl $G/menu` | `503 no_upstream` (transien `504` sebelum Consul memperbarui) |
| 20 | Pulihkan | `docker compose up -d api` | `200` kembali |

Catatan matriks uji:
- Nama service compose adalah `api` (`docker compose stop api` menghentikan **semua** replica). Untuk menghentikan satu replica, pakai nama container, mis. `docker stop load-balance-dabd-api-1`.
- `circuit_open` (503) muncul saat replica masih terdaftar di Consul tetapi **semua** circuit-nya OPEN. Bila Consul sudah mengeluarkan semua replica, responsnya `no_upstream`.
- Rate limiter memakai key `Authorization` (fallback IP), rate `20r/s` + `burst=40`. Uji harus berupa burst paralel; loop serial biasanya tidak memicu `429`.

## Catatan
- `Database/docker-compose.yaml` adalah runner DB standalone (opsional); root `docker-compose.yml` sudah mencakup `db`.
- `init.sql` hanya dijalankan saat volume pertama dibuat; gunakan `down -v` untuk reseed.
- `JWT_SECRET` harus sama antara service `api` dan `gateway`.
