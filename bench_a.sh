#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Experiment A: single-threaded baseline ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"

START=$(date +%s)
EXIT=0
python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  -p no:xdist 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "A_SECONDS=$ELAPSED"
echo "A_EXIT=$EXIT"
