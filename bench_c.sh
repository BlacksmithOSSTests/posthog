#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Experiment C: xdist -n 2, two ClickHouse instances ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"

# Start second ClickHouse on port 8124
echo "Starting second ClickHouse on :8124..."
CHIMG=$(docker inspect posthog-clickhouse-1 --format '{{.Config.Image}}' 2>/dev/null \
  || echo "clickhouse/clickhouse-server:26.3.9.8")
echo "Using image: $CHIMG"

docker rm -f clickhouse2 2>/dev/null || true
docker run -d --name clickhouse2 --network posthog_default \
  -p 8124:8123 \
  -p 9001:9000 \
  -e CLICKHOUSE_SKIP_USER_SETUP=1 \
  -v "$PWD/docker/clickhouse/users-dev.xml:/etc/clickhouse-server/users.xml" \
  -v "$PWD/docker/clickhouse/config.xml:/etc/clickhouse-server/config.xml" \
  -v "$PWD/docker/clickhouse/config.d/default_ch2.xml:/etc/clickhouse-server/config.d/default.xml" \
  -v "$PWD/posthog/user_scripts:/var/lib/clickhouse/user_scripts" \
  -v "$PWD/posthog/user_scripts/latest_user_defined_function.xml:/etc/clickhouse-server/user_defined_function.xml" \
  "$CHIMG"

echo "Waiting for second ClickHouse on :8124..."
timeout 90 bash -c 'until curl -sf http://localhost:8124/ping 2>/dev/null; do sleep 3; done'
echo "Second ClickHouse ready."

START=$(date +%s)
EXIT=0
CH_XDIST_ROUTING=1 python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  --create-db \
  -n 2 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "C_SECONDS=$ELAPSED"
echo "C_EXIT=$EXIT"
