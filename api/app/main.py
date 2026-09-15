import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status

from . import consul
from .db import close_pool, get_pool, init_pool
from .routers import auth, menu

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_pool()
    consul.start()
    yield
    consul.stop()
    close_pool()


app = FastAPI(
    title="Kantin Menu API",
    description="REST API sederhana untuk data menu kantin (demo API Gateway / Load Balancing).",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(auth.router)
app.include_router(menu.router)


@app.get("/health", tags=["health"])
def health():
    try:
        with get_pool().connection(timeout=2) as conn:
            conn.execute("SELECT 1")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"status": "degraded", "db": "down"},
        ) from exc
    return {"status": "ok", "db": "up"}


@app.get("/", tags=["health"])
def root():
    return {
        "service": "kantin-menu-api",
        "docs": "/docs",
        "health": "/health",
        "login": "/auth/login",
    }
