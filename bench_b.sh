#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Experiment B: xdist -n 2, single ClickHouse ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"

START=$(date +%s)
EXIT=0
python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  -n 2 --dist=loadscope 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "B_SECONDS=$ELAPSED"
echo "B_EXIT=$EXIT"
