"""Supabase JWT verification (HS256 with the project JWT secret, read from the Keychain). Every request
except /health goes through current_user. A local-testing bypass exists ONLY when LANESIGHT_API_DEV=1 and
no JWT secret is configured (config.dev_insecure); it is never active in a real deployment."""
from __future__ import annotations
import jwt
from fastapi import Header, HTTPException
from .config import settings


def current_user(authorization: str | None = Header(default=None),
                 x_dev_user: str | None = Header(default=None)) -> str:
    """Returns the authenticated user_id (JWT `sub`). Raises 401/503 otherwise."""
    s = settings()
    if s.dev_insecure:
        if not x_dev_user:
            raise HTTPException(401, 'dev mode: supply X-Dev-User')
        return x_dev_user
    if not s.jwt_secret:
        raise HTTPException(503, 'JWT secret not configured (Keychain lanesight.supabase.jwt_secret)')
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'missing bearer token')
    try:
        claims = jwt.decode(authorization[7:], s.jwt_secret, algorithms=['HS256'],
                            options={'verify_aud': False})
    except Exception as e:
        raise HTTPException(401, f'invalid token: {type(e).__name__}')
    sub = claims.get('sub')
    if not sub:
        raise HTTPException(401, 'token has no subject')
    return sub
