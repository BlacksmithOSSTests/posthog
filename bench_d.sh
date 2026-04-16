#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Experiment D: xdist -n 4, single ClickHouse, 4vCPU runner ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"
echo "CPUs: $(nproc)"

START=$(date +%s)
EXIT=0
python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  --create-db \
  -n 4 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "D_SECONDS=$ELAPSED"
echo "D_EXIT=$EXIT"
