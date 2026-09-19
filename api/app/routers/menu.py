from psycopg import Connection
from psycopg.errors import ForeignKeyViolation
from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..auth import get_current_user, require_admin
from ..db import get_conn
from ..schemas import MenuCreate, MenuOut, MenuUpdate

router = APIRouter(
    prefix="/menu",
    tags=["menu"],
    dependencies=[Depends(get_current_user)],
)

BASE_SELECT = """
SELECT m.id_menu, m.id_stand, m.id_kategori, m.nama_menu, m.harga, m.status,
       s.nama_stand, k.nama_kategori
FROM menu m
JOIN stand s ON s.id_stand = m.id_stand
JOIN kategori k ON k.id_kategori = m.id_kategori
"""

FK_DETAIL = "id_stand atau id_kategori tidak ditemukan"


def _fetch_one(conn: Connection, id_menu: int):
    with conn.cursor() as cur:
        cur.execute(BASE_SELECT + " WHERE m.id_menu = %s", (id_menu,))
        return cur.fetchone()


@router.get("", response_model=list[MenuOut])
def list_menu(
    id_stand: int | None = Query(None, gt=0),
    id_kategori: int | None = Query(None, gt=0),
    status_menu: str | None = Query(
        None, alias="status", pattern="^(tersedia|habis)$"
    ),
    conn: Connection = Depends(get_conn),
):
    where: list[str] = []
    params: list[object] = []
    if id_stand is not None:
        where.append("m.id_stand = %s")
        params.append(id_stand)
    if id_kategori is not None:
        where.append("m.id_kategori = %s")
        params.append(id_kategori)
    if status_menu is not None:
        where.append("m.status = %s")
        params.append(status_menu)

    sql = BASE_SELECT
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY m.id_menu"

    with conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


@router.get("/{id_menu}", response_model=MenuOut)
def get_menu(id_menu: int, conn: Connection = Depends(get_conn)):
    row = _fetch_one(conn, id_menu)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Menu tidak ditemukan"
        )
    return row


@router.post(
    "",
    response_model=MenuOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_admin)],
)
def create_menu(payload: MenuCreate, conn: Connection = Depends(get_conn)):
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO menu (id_stand, id_kategori, nama_menu, harga, status)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id_menu
                """,
                (
                    payload.id_stand,
                    payload.id_kategori,
                    payload.nama_menu,
                    payload.harga,
                    payload.status,
                ),
            )
            new_id = cur.fetchone()["id_menu"]
    except ForeignKeyViolation as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=FK_DETAIL
        ) from exc

    return _fetch_one(conn, new_id)


@router.put(
    "/{id_menu}",
    response_model=MenuOut,
    dependencies=[Depends(require_admin)],
)
def update_menu(
    id_menu: int, payload: MenuUpdate, conn: Connection = Depends(get_conn)
):
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE menu
                SET id_stand = %s, id_kategori = %s, nama_menu = %s,
                    harga = %s, status = %s
                WHERE id_menu = %s
                """,
                (
                    payload.id_stand,
                    payload.id_kategori,
                    payload.nama_menu,
                    payload.harga,
                    payload.status,
                    id_menu,
                ),
            )
            if cur.rowcount == 0:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Menu tidak ditemukan",
                )
    except ForeignKeyViolation as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=FK_DETAIL
        ) from exc

    return _fetch_one(conn, id_menu)


@router.delete(
    "/{id_menu}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_admin)],
)
def delete_menu(id_menu: int, conn: Connection = Depends(get_conn)):
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM menu WHERE id_menu = %s", (id_menu,))
            if cur.rowcount == 0:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Menu tidak ditemukan",
                )
    except ForeignKeyViolation as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Menu masih dipakai pada detail transaksi",
        ) from exc
    return None
