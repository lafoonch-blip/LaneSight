"""Supabase JWT verification. This project uses asymmetric keys (ES256) — user tokens are verified
against the project's public JWKS, not a shared secret. A local-testing bypass exists ONLY when
LANESIGHT_API_DEV=1 (config.dev_insecure); it is never active in a real deployment."""
from __future__ import annotations
import jwt
from jwt import PyJWKClient
from fastapi import Header, HTTPException
from .config import settings

_jwks_client = None


def _jwks(url: str) -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        s = settings()
        # the Supabase gateway wants an apikey header even on the public JWKS endpoint
        headers = {'apikey': s.service_role} if s.service_role else None
        try:
            _jwks_client = PyJWKClient(url, headers=headers)
        except TypeError:                      # older pyjwt without headers kwarg
            _jwks_client = PyJWKClient(url)
    return _jwks_client


def current_user(authorization: str | None = Header(default=None),
                 x_dev_user: str | None = Header(default=None)) -> str:
    """Returns the authenticated user_id (JWT `sub`). Raises 401/503 otherwise."""
    s = settings()
    if s.dev_insecure:
        if not x_dev_user:
            raise HTTPException(401, 'dev mode: supply X-Dev-User')
        return x_dev_user
    if not s.jwks_url:
        raise HTTPException(503, 'JWKS not configured (need the Supabase REST base in the Keychain db_url)')
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'missing bearer token')
    token = authorization[7:]
    try:
        key = _jwks(s.jwks_url).get_signing_key_from_jwt(token).key
        claims = jwt.decode(token, key, algorithms=['ES256', 'RS256'], options={'verify_aud': False})
    except Exception as e:
        raise HTTPException(401, f'invalid token: {type(e).__name__}')
    sub = claims.get('sub')
    if not sub:
        raise HTTPException(401, 'token has no subject')
    return sub
