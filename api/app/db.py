import logging
import os
import time

from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

logger = logging.getLogger("kantin.api.db")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "db_kantin")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password123")

_pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        conninfo = make_conninfo(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
        )
        _pool = ConnectionPool(
            conninfo=conninfo,
            min_size=1,
            max_size=10,
            open=False,
            kwargs={"row_factory": dict_row},
        )
    return _pool


def init_pool(retries: int = 15, delay: float = 2.0) -> None:
    pool = get_pool()
    for attempt in range(1, retries + 1):
        try:
            pool.open(wait=True, timeout=5)
            logger.info("Koneksi database siap (%s:%s/%s)", DB_HOST, DB_PORT, DB_NAME)
            return
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "Menunggu database (%s/%s): %s", attempt, retries, exc
            )
            time.sleep(delay)
    raise RuntimeError("Gagal terhubung ke database setelah beberapa percobaan")


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def get_conn():
    pool = get_pool()
    with pool.connection() as conn:
        yield conn
