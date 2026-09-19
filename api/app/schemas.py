from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, Field

Status = Literal["tersedia", "habis"]


class MenuBase(BaseModel):
    id_stand: int = Field(gt=0)
    id_kategori: int = Field(gt=0)
    nama_menu: str = Field(min_length=1, max_length=100)
    harga: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    status: Status = "tersedia"


class MenuCreate(MenuBase):
    pass


class MenuUpdate(MenuBase):
    pass


class MenuOut(BaseModel):
    id_menu: int
    id_stand: int
    id_kategori: int
    nama_menu: str
    harga: Decimal
    status: str
    nama_stand: Optional[str] = None
    nama_kategori: Optional[str] = None
