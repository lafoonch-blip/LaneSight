#!/usr/bin/env bash
# DEC-113 tiered benchmark — pick the tier from the changed paths.
#   quick    : pytest + 1-clip smoke (every commit/deploy). The default.
#   standard : a diff touches CV / decode / metric / score-baseline code -> also run the IMG_8751-54 regression.
#   full     : NOT auto-selected here — it's nightly / pre-prod-promote / finalists, or an auto-escalation when
#              the standard regression finds a tolerance breach or a new failure (ops/regression_tier.py says so).
# Usage: ops/tier_for_diff.sh <base_ref> [head_ref]   (head defaults to the working tree / staged changes)
set -euo pipefail
base="${1:-HEAD}"; head="${2:-}"
if [ -n "$head" ]; then
  files=$(git diff --name-only "$base" "$head")
elif git rev-parse --verify -q "$base" >/dev/null; then
  files=$(git diff --name-only "$base")            # working tree vs base
else
  files=$(git diff --cached --name-only)           # staged (pre-commit, no base)
fi
# Standard-triggering paths: the CV engine (decode + every metric stage), the at-lane runner, the metric
# contract, and the score/baseline engine. A change anywhere here can move a measured number.
if printf '%s\n' "$files" | grep -qE \
  '^lanesight-core/lanesight_core/cv/|^lanesight-core/lanesight_runner/|^lanesight-core/lanesight_core/form/|^lanesight-core/lanesight_core/models/shot\.py|^lanesight-core/lanesight_api/engines\.py|^lanesight_core/cv/|^lanesight_runner/|^lanesight_core/form/|^lanesight_core/models/shot\.py|^lanesight_api/engines\.py'; then
  echo standard
else
  echo quick
fi
