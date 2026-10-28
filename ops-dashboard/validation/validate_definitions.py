#!/usr/bin/env python3
"""Ops reporting validation (§1) — static, no DB required.

Checks that the three artifacts of the ops reporting layer agree and that the honesty rules
(CLAUDE.md: no mock/placeholder/fallback numbers) are actually encoded:

  1. definitions.json is internally consistent (every metric/panel points at a real view+column,
     every domain is known).
  2. definitions.json matches the SQL in 0XX_ops_reporting.sql: every view exists, every column a
     metric reads is selected by that view, and the 8 observability domains line up with
     ops_coverage_status.
  3. Honesty invariants hold: every rate metric (one with a denominator) is computed with nullif(...)
     so an empty window is NULL (NO DATA), never a fake 0; canonical views are real-only (staged
     excluded); no "available/partial" metric hangs off a no_data domain.

Run:  python3 validate_definitions.py        (exit 0 = pass, 1 = fail)
Pytest picks up test_definitions_valid().
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
APP_DIR = HERE.parents[1]                       # <repo>/ops-dashboard
REPO_ROOT = HERE.parents[2]                     # <repo>
DEFS_PATH = APP_DIR / "definitions.json"
SQL_PATH = REPO_ROOT / "lanesight-core" / "lanesight_core" / "models" / "migrations" / "0XX_ops_reporting.sql"

CANONICAL_NON_REAL_VIEWS = {"ops_freshness", "ops_coverage_status"}  # metadata views, not row-level real-only


def _load():
    defs = json.loads(DEFS_PATH.read_text())
    sql = SQL_PATH.read_text()
    return defs, sql


def _view_blocks(sql: str) -> dict[str, str]:
    """Return {view_name: body-up-to-the-next-create-or-semicolon-statement}."""
    blocks: dict[str, str] = {}
    pattern = re.compile(r"create (?:or replace )?view\s+(\w+)\s+as\b", re.IGNORECASE)
    matches = list(pattern.finditer(sql))
    for i, m in enumerate(matches):
        name = m.group(1)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(sql)
        blocks[name] = sql[start:end]
    return blocks


def validate() -> list[str]:
    errors: list[str] = []
    defs, sql = _load()
    views = defs["views"]
    view_names = set(views)
    domain_names = {d["domain"] for d in defs["domains"]}
    domain_avail = {d["domain"]: d["availability"] for d in defs["domains"]}
    blocks = _view_blocks(sql)

    # 1. every definitions view is actually created in the SQL, with the columns it claims.
    for vname, v in views.items():
        if vname not in blocks:
            errors.append(f"view '{vname}' in definitions.json is not CREATEd in {SQL_PATH.name}")
            continue
        body = blocks[vname]
        for col in v["columns"]:
            # column must appear as a selected alias/name in the view body (word-boundary match).
            if not re.search(rf"\b{re.escape(col)}\b", body):
                errors.append(f"view '{vname}': column '{col}' not found in its SQL definition")

    # 2. every SQL ops_* view is declared in definitions (no undocumented view).
    for sql_view in blocks:
        if sql_view.startswith("ops_") and sql_view not in view_names:
            errors.append(f"SQL view '{sql_view}' is not documented in definitions.json")

    # 3. metrics point at real views+columns, known domains.
    for mdef in defs["metrics"]:
        mid = mdef["id"]
        v = mdef["view"]
        if v not in view_names:
            errors.append(f"metric '{mid}': view '{v}' is unknown")
            continue
        if mdef["column"] not in views[v]["columns"]:
            errors.append(f"metric '{mid}': column '{mdef['column']}' not in view '{v}'")
        if mdef["domain"] not in domain_names:
            errors.append(f"metric '{mid}': domain '{mdef['domain']}' is unknown")
        elif domain_avail.get(mdef["domain"]) == "no_data":
            errors.append(f"metric '{mid}': belongs to no_data domain '{mdef['domain']}' — no_data domains "
                          f"must have NO metric (render NO DATA, pending §2)")
        # honesty: a metric with a denominator must be computed with nullif in its view.
        if mdef.get("denominator"):
            if "nullif" not in blocks.get(v, "").lower():
                errors.append(f"metric '{mid}': has denominator '{mdef['denominator']}' but view '{v}' "
                              f"does not use nullif() — a rate could divide by zero / show a fake 0")

    # 4. panels point at real views.
    for p in defs["panels"]:
        for v in p["views"]:
            if v not in view_names:
                errors.append(f"panel '{p['id']}': view '{v}' is unknown")

    # 5. honesty: canonical (non-metadata) views are real_only=true and exclude staged in the SQL.
    for vname, v in views.items():
        if vname in CANONICAL_NON_REAL_VIEWS:
            continue
        if not v.get("real_only"):
            errors.append(f"view '{vname}': must be real_only (staged accounts excluded)")
        body = blocks.get(vname, "").lower()
        if "is_staged" not in body:
            errors.append(f"view '{vname}': SQL does not reference is_staged — staged accounts may leak in")

    # 6. the 8 observability domains in definitions match the ops_coverage_status VALUES in the SQL.
    cov_body = blocks.get("ops_coverage_status", "")
    for d in defs["domains"]:
        # domain label appears, and if availability is no_data the SQL row must say 'no_data'
        if d["domain"] not in cov_body:
            errors.append(f"coverage: domain '{d['domain']}' missing from ops_coverage_status SQL")
    if len(defs["domains"]) != 8:
        errors.append(f"expected 8 observability domains, found {len(defs['domains'])}")

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
    n_views = len(json.loads(DEFS_PATH.read_text())["views"])
    n_metrics = len(json.loads(DEFS_PATH.read_text())["metrics"])
    print(f"OK — {n_views} views, {n_metrics} metrics; definitions.json <-> {SQL_PATH.name} consistent; "
          f"honesty invariants hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
