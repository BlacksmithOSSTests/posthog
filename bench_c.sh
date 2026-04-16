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
  -e KAFKA_HOSTS=kafka:9092 \
  -v "$PWD/docker/clickhouse/users-dev.xml:/etc/clickhouse-server/users.xml" \
  -v "$PWD/docker/clickhouse/config.xml:/etc/clickhouse-server/config.xml" \
  -v "$PWD/docker/clickhouse/config.d/default_ch2.xml:/etc/clickhouse-server/config.d/default.xml" \
  -v "$PWD/posthog/user_scripts:/var/lib/clickhouse/user_scripts" \
  -v "$PWD/posthog/user_scripts/latest_user_defined_function.xml:/etc/clickhouse-server/user_defined_function.xml" \
  "$CHIMG"

echo "Waiting for second ClickHouse on :8124..."
timeout 90 bash -c 'until curl -sf http://localhost:8124/ping 2>/dev/null; do sleep 3; done'
echo "Second ClickHouse ready."

# Drop stale xdist worker databases so --create-db gets a clean slate
# Note: DROP DATABASE must run outside a transaction block, so use separate psql calls
echo "Dropping stale xdist worker databases..."
for db in test_posthog_gw0 test_posthog_gw1 test_posthog_persons_gw0 test_posthog_persons_gw1; do
  PGPASSWORD=posthog psql -U posthog -h localhost -d posthog -c "DROP DATABASE IF EXISTS \"$db\"" 2>&1 || true
done

START=$(date +%s)
EXIT=0
# IN_EVAL_TESTING=1 causes create_clickhouse_tables() to also create Kafka-engine
# tables (kafka_person_distinct_id2 etc.) in the test DB on CH2, which is needed
# because CH2 is a fresh instance without PostHog's docker-compose initialization.
IN_EVAL_TESTING=1 CH_XDIST_ROUTING=1 python -m pytest --tb=line -q posthog/hogql_queries/test/ \
  -m "not async_migrations" \
  --create-db \
  -n 2 2>&1 || EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
echo "C_SECONDS=$ELAPSED"
echo "C_EXIT=$EXIT"
