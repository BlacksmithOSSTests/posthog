#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Experiment B: xdist -n 2, single ClickHouse ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"

# Drop stale xdist worker databases so --create-db gets a clean slate
# Note: DROP DATABASE must run outside a transaction block, so use separate psql calls
echo "Dropping stale xdist worker databases..."
for db in test_posthog_gw0 test_posthog_gw1 test_posthog_gw2 test_posthog_gw3 \
           test_posthog_persons_gw0 test_posthog_persons_gw1 test_posthog_persons_gw2 test_posthog_persons_gw3; do
  PGPASSWORD=posthog psql -U posthog -h localhost -d posthog -c "DROP DATABASE IF EXISTS \"$db\"" 2>&1 || true
done

START=$(date +%s)
EXIT=0
python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  --create-db \
  -n 2 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "B_SECONDS=$ELAPSED"
echo "B_EXIT=$EXIT"
