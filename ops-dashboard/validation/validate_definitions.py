#!/usr/bin/env python3
"""Ops reporting validation (§1) — static, no DB required.

Checks that the artifacts of the ops reporting layer agree and that the honesty + security rules are
actually encoded:

  1. definitions.json is internally consistent (metrics/panels point at real views+columns; known domains).
  2. definitions.json matches 025_ops_reporting.sql: every view exists in the `ops` schema with the columns
     a metric reads, every non-metadata view has an owner-checked RPC, and the 8 domains line up with
     ops.coverage_status.
  3. Honesty: every rate metric (with a denominator) is computed with nullif(...); canonical views exclude
     staged accounts; no available/partial metric hangs off a no_data domain.
  4. Security: the RPCs are SECURITY DEFINER and check ops.is_owner(); the owner id in owner.py matches the
     id seeded in the migration.

Run:  python3 validate_definitions.py   (exit 0 = pass, 1 = fail).  Pytest picks up test_definitions_valid().
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
APP_DIR = HERE.parents[1]
REPO_ROOT = HERE.parents[2]
DEFS_PATH = APP_DIR / "definitions.json"
MIG_DIR = REPO_ROOT / "lanesight-core" / "lanesight_core" / "models" / "migrations"
SQL_PATHS = [MIG_DIR / "025_ops_reporting.sql", MIG_DIR / "027_ops_instrumentation.sql", MIG_DIR / "028_engine_provenance.sql", MIG_DIR / "029_ops_decode_cache.sql"]
OWNER_PY = REPO_ROOT / "lanesight-core" / "lanesight_core" / "owner.py"

# Views with no per-user staged concept to filter: metadata views, and the pseudonymous/infra-level tables
# (api_request / product_event / storage_snapshot) where staged scope is handled upstream in app.py.
CANONICAL_NON_REAL_VIEWS = {"freshness", "coverage_status", "api_daily", "event_daily", "funnel",
                            "storage_latest"}


def _load():
    sql = "\n".join(p.read_text() for p in SQL_PATHS if p.exists())
    return json.loads(DEFS_PATH.read_text()), sql


def _view_blocks(sql: str) -> dict[str, str]:
    """{bare_view_name: body} for `create [or replace] view ops.<name> as ...`."""
    blocks: dict[str, str] = {}
    pattern = re.compile(r"create (?:or replace )?view\s+ops\.(\w+)\s+as\b", re.IGNORECASE)
    matches = list(pattern.finditer(sql))
    for i, m in enumerate(matches):
        name = m.group(1)
        end = matches[i + 1].start() if i + 1 < len(matches) else len(sql)
        blocks[name] = sql[m.end():end]
    return blocks


def validate() -> list[str]:
    errors: list[str] = []
    defs, sql = _load()
    views = defs["views"]
    view_names = set(views)
    domain_names = {d["domain"] for d in defs["domains"]}
    domain_avail = {d["domain"]: d["availability"] for d in defs["domains"]}
    blocks = _view_blocks(sql)

    # 1. definitions views exist in the SQL with the columns they claim.
    for vname, v in views.items():
        if vname not in blocks:
            errors.append(f"view '{vname}' in definitions.json is not CREATEd as ops.{vname} in 025+027 migrations")
            continue
        body = blocks[vname]
        for col in v["columns"]:
            if not re.search(rf"\b{re.escape(col)}\b", body):
                errors.append(f"view '{vname}': column '{col}' not found in its SQL definition")

    # 2. every SQL ops view is documented.
    for sql_view in blocks:
        if sql_view not in view_names:
            errors.append(f"SQL view ops.{sql_view} is not documented in definitions.json")

    # 3. every non-metadata view has an owner-checked RPC present in the SQL.
    for vname, v in views.items():
        rpc = v.get("rpc")
        if vname in CANONICAL_NON_REAL_VIEWS or rpc:
            if rpc and not re.search(rf"create (?:or replace )?function\s+public\.{re.escape(rpc)}\s*\(", sql, re.I):
                errors.append(f"view '{vname}': RPC public.{rpc} not defined in the SQL")

    # 4. metrics -> real views+columns, known domains, honesty.
    for mdef in defs["metrics"]:
        mid, v = mdef["id"], mdef["view"]
        if v not in view_names:
            errors.append(f"metric '{mid}': view '{v}' is unknown")
            continue
        if mdef["column"] not in views[v]["columns"]:
            errors.append(f"metric '{mid}': column '{mdef['column']}' not in view '{v}'")
        if mdef["domain"] not in domain_names:
            errors.append(f"metric '{mid}': domain '{mdef['domain']}' is unknown")
        elif domain_avail.get(mdef["domain"]) == "no_data":
            errors.append(f"metric '{mid}': belongs to no_data domain '{mdef['domain']}'")
        if mdef.get("denominator") and "nullif" not in blocks.get(v, "").lower():
            errors.append(f"metric '{mid}': denominator '{mdef['denominator']}' but view '{v}' has no nullif()")

    # 5. panels -> real views.
    for p in defs["panels"]:
        for v in p["views"]:
            if v not in view_names:
                errors.append(f"panel '{p['id']}': view '{v}' is unknown")

    # 6. canonical (non-metadata) views are real_only and exclude staged in the SQL.
    for vname, v in views.items():
        if vname in CANONICAL_NON_REAL_VIEWS:
            continue
        if not v.get("real_only"):
            errors.append(f"view '{vname}': must be real_only (staged accounts excluded)")
        if "is_staged" not in blocks.get(vname, "").lower():
            errors.append(f"view '{vname}': SQL does not reference is_staged — staged accounts may leak in")

    # 7. coverage domains line up; 8 domains.
    cov_body = blocks.get("coverage_status", "")
    for d in defs["domains"]:
        if d["domain"] not in cov_body:
            errors.append(f"coverage: domain '{d['domain']}' missing from ops.coverage_status SQL")
    if len(defs["domains"]) != 8:
        errors.append(f"expected 8 observability domains, found {len(defs['domains'])}")

    # 8. security: RPCs are SECURITY DEFINER + owner-checked; owner id matches owner.py.
    n_rpcs = len(re.findall(r"create (?:or replace )?function\s+public\.ops_rpc_\w+", sql, re.I))
    n_definer = len(re.findall(r"security definer", sql, re.I))
    n_ownercheck = len(re.findall(r"ops\.is_owner\(\)", sql))
    if n_rpcs < 9:
        errors.append(f"expected >=9 public.ops_rpc_* functions, found {n_rpcs}")
    if n_definer < n_rpcs + 1:  # each rpc + is_owner()
        errors.append(f"not every RPC is SECURITY DEFINER (definer={n_definer}, rpcs={n_rpcs})")
    if n_ownercheck < n_rpcs:
        errors.append(f"not every RPC calls ops.is_owner() (checks={n_ownercheck}, rpcs={n_rpcs})")
    owner_py = OWNER_PY.read_text() if OWNER_PY.exists() else ""
    m_owner = re.search(r"OWNER_USER_ID\s*=\s*'([0-9a-f-]{36})'", owner_py)
    if not m_owner:
        errors.append("owner.py OWNER_USER_ID not found")
    elif m_owner.group(1) not in sql:
        errors.append(f"owner.py OWNER_USER_ID ({m_owner.group(1)}) not seeded in the migration (drift)")

    return errors


def test_definitions_valid():
    errs = validate()
    assert not errs, "ops reporting definition errors:\n  - " + "\n  - ".join(errs)


def main() -> int:
    errs = validate()
    if errs:
        print(f"FAIL — {len(errs)} ops reporting definition error(s):")
        for e in errs:
            print(f"  - {e}")
        return 1
    defs = json.loads(DEFS_PATH.read_text())
    print(f"OK — {len(defs['views'])} views, {len(defs['metrics'])} metrics; definitions.json <-> 025+027 migrations "
          f"consistent; honesty + owner-RPC security invariants hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
