"""Configuration + macOS Keychain secret access. Secrets are read on demand and NEVER written to disk,
logged, or echoed. (DV-03 decision 2026-10-22: DB string + service key live in the Keychain.)"""
from __future__ import annotations
import os
import subprocess
from functools import lru_cache

# Keychain items (account 'lanesight'). Add with, e.g.:
#   security add-generic-password -a lanesight -s lanesight.supabase.db_url -w '<postgres connection string>'
KEYCHAIN_ACCOUNT = 'lanesight'
ITEM_DB_URL = 'lanesight.supabase.db_url'
ITEM_SERVICE_ROLE = 'lanesight.supabase.service_role'
ITEM_JWT_SECRET = 'lanesight.supabase.jwt_secret'   # the Supabase project JWT secret (HS256) for token verify


def keychain_secret(service: str, account: str = KEYCHAIN_ACCOUNT) -> str | None:
    """Return a generic-password secret, or None if the item isn't present / can't be read.
    The value is returned to the caller only; it is never logged here."""
    try:
        r = subprocess.run(['security', 'find-generic-password', '-a', account, '-s', service, '-w'],
                           capture_output=True, text=True, timeout=10)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    secret = r.stdout.rstrip('\n')
    return secret or None


class Settings:
    """Lazily resolves secrets. `mode` is 'live' when a db_url is present, else 'memory' (offline/testing)."""
    def __init__(self):
        self._db_url = None
        self._service_role = None
        self._jwt_secret = None
        self._loaded = False

    def _load(self):
        if self._loaded:
            return
        self._db_url = os.environ.get('LANESIGHT_DB_URL') or keychain_secret(ITEM_DB_URL)
        self._service_role = os.environ.get('LANESIGHT_SERVICE_ROLE') or keychain_secret(ITEM_SERVICE_ROLE)
        self._jwt_secret = os.environ.get('LANESIGHT_JWT_SECRET') or keychain_secret(ITEM_JWT_SECRET)
        self._loaded = True

    @property
    def db_url(self):
        if os.environ.get('LANESIGHT_FORCE_MEMORY') == '1':
            return None          # safety: force MemoryStore even if Keychain creds exist (tests/offline)
        self._load(); return self._db_url

    @property
    def service_role(self):
        self._load(); return self._service_role

    @property
    def jwt_secret(self):
        self._load(); return self._jwt_secret

    @property
    def mode(self):
        return 'live' if self.db_url else 'memory'

    @property
    def jwks_url(self):
        """Public JWKS for verifying user JWTs. This project uses asymmetric keys (ES256), so there is no
        HS256 shared secret — tokens verify against this endpoint. Derived from the REST base."""
        if not self.db_url:
            return None
        from urllib.parse import urlparse
        p = urlparse(self.db_url)
        return f'{p.scheme}://{p.netloc}/auth/v1/.well-known/jwks.json'

    @property
    def dev_insecure(self):
        """Only true when explicitly opted in (LANESIGHT_API_DEV=1) — local testing only, never in prod."""
        return os.environ.get('LANESIGHT_API_DEV') == '1'

    def redacted(self) -> dict:
        """Safe-to-log view: presence booleans only, never the values."""
        return {'mode': self.mode, 'db_url_present': bool(self.db_url),
                'service_role_present': bool(self.service_role), 'jwks_url_present': bool(self.jwks_url),
                'dev_insecure': self.dev_insecure}


@lru_cache
def settings() -> Settings:
    return Settings()
