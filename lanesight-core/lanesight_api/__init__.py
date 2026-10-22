"""lanesight_api — the Mac service for Dev Build v0 (HANDOFF §2/§3).

FastAPI over the real lanesight_core pipeline + engines, reached from the iPhone over Tailscale
(tailscale serve -> localhost HTTPS). Binds to localhost only. Verifies the Supabase JWT on every
request. Video stays on the Mac; the Supabase service key lives only in the macOS Keychain, never in
the repo or a log. Analysis runs one shot at a time (serial queue, DEC-043).
"""
API_VERSION = 'lanesight-api-0.1.0'
APP_COMPAT = '>=0.1.0'      # minimum iOS app build this API is compatible with
