import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel

JWT_SECRET = os.getenv("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "60"))

_USERS: dict[str, dict[str, str]] = {
    os.getenv("API_ADMIN_USERNAME", "admin"): {
        "password": os.getenv("API_ADMIN_PASSWORD", "admin123"),
        "role": "admin",
    },
    os.getenv("API_VIEWER_USERNAME", "viewer"): {
        "password": os.getenv("API_VIEWER_PASSWORD", "viewer123"),
        "role": "viewer",
    },
}

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


class TokenPayload(BaseModel):
    sub: str
    role: str
    exp: int


def authenticate(username: str, password: str) -> dict | None:
    user = _USERS.get(username)
    if user and hmac.compare_digest(user["password"], password):
        return {"username": username, "role": user["role"]}
    return None


def create_access_token(username: str, role: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=JWT_EXPIRE_MINUTES)
    payload = {"sub": username, "role": role, "exp": expire}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def get_current_user(token: str = Depends(oauth2_scheme)) -> TokenPayload:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token tidak valid atau sudah kedaluwarsa",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        data = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return TokenPayload(**data)
    except jwt.PyJWTError as exc:
        raise credentials_error from exc


def require_admin(user: TokenPayload = Depends(get_current_user)) -> TokenPayload:
    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Akses ditolak: butuh role admin",
        )
    return user
