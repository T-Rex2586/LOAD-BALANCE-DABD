# Kantin Menu API (DABD - Load Balancing Demo)

REST API sederhana untuk data menu kantin. Dipakai sebagai backend/service yang nantinya
dilewati API Gateway, service discovery, load balancing, reverse proxy, health check,
circuit breaker, dan rate limiter (dikerjakan terpisah).

## Stack
- Python 3.12 + FastAPI + Uvicorn
- PostgreSQL 16 (raw SQL, driver `psycopg` 3)
- JWT (PyJWT) untuk authentication & role-based authorization
- Docker & Docker Compose

## Struktur
```
docker-compose.yml        # db + api (scalable, tanpa host port)
docker-compose.dev.yml    # override: publish port 8000 untuk tes lokal
.env.example              # template konfigurasi
Database/init.sql         # DDL + seed data
api/
  Dockerfile
  requirements.txt
  app/
    main.py               # app FastAPI, /health, / 
    auth.py               # JWT, login, dependency auth
    db.py                 # connection pool psycopg
    schemas.py            # model Pydantic
    routers/
      auth.py             # POST /auth/login
      menu.py             # CRUD /menu
```

## Endpoint
| Method | Path | Auth | Deskripsi |
|---|---|---|---|
| GET | `/health` | publik | Cek koneksi DB (`SELECT 1`) |
| POST | `/auth/login` | publik | Login, dapat JWT (`form: username, password`) |
| GET | `/menu` | token | List menu (filter: `id_stand`, `id_kategori`, `status`) |
| GET | `/menu/{id_menu}` | token | Detail menu |
| POST | `/menu` | admin | Tambah menu |
| PUT | `/menu/{id_menu}` | admin | Ubah menu |
| DELETE | `/menu/{id_menu}` | admin | Hapus menu |

Dokumentasi interaktif: `http://localhost:8000/docs`.

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
- Role `admin`: boleh GET, POST, PUT, DELETE.
- Role `viewer`: hanya boleh GET (write → `403`).

Kredensial default (ubah lewat `.env`):
| Username | Password | Role |
|---|---|---|
| admin | admin123 | admin |
| viewer | viewer123 | viewer |

## Menjalankan
```bash
# salin config
copy .env.example .env      # PowerShell; Linux/macOS: cp .env.example .env

# mode dev (API di http://localhost:8000)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# mode multi-replica untuk load balancing (tanpa publish port)
docker compose up --build -d --scale api=3

# hentikan
docker compose down

# reset database (jalankan ulang init.sql)
docker compose down -v
```

## Contoh Pemakaian
```bash
# login admin
curl -X POST http://localhost:8000/auth/login \
  -d "username=admin&password=admin123"

# gunakan token
TOKEN=<access_token>
curl http://localhost:8000/menu -H "Authorization: Bearer $TOKEN"

curl -X POST http://localhost:8000/menu \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id_stand":1,"id_kategori":1,"nama_menu":"Soto Ayam","harga":15000,"status":"tersedia"}'
```

## Catatan Integrasi Gateway
- Service DNS internal: `api`, port `8000` (mis. `http://api:8000`).
- Health check untuk gateway/LB: `GET /health`.
- API stateless (konfigurasi via env) sehingga aman di-scale beberapa replica.
- `init.sql` hanya dijalankan saat volume pertama dibuat; gunakan `down -v` untuk reseed.
