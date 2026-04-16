#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/hostedtoolcache/Python/3.12.12/x64/bin:/home/runner/_work/_temp/sqlx-cli/bin:$PATH"
cd /home/runner/_work/posthog/posthog

echo "=== Setup overhead: --durations=0 -v on setUp-heavy test classes ==="
echo "Python: $(python --version)"
echo "pytest: $(python -m pytest --version)"
echo ""
echo "--- test_hogql_query_runner (setUp creates 10 persons once per test) ---"
START=$(date +%s)
python -m pytest --tb=no --durations=0 -v \
  posthog/hogql_queries/test/test_hogql_query_runner.py \
  -m "not async_migrations" \
  -p no:xdist 2>&1 || true
END=$(date +%s)
echo "HOGQL_RUNNER_SECONDS=$((END - START))"

echo ""
echo "--- test_actors_query_runner (each test creates its own 10 persons) ---"
START=$(date +%s)
python -m pytest --tb=no --durations=0 -v \
  posthog/hogql_queries/test/test_actors_query_runner.py \
  -m "not async_migrations" \
  -p no:xdist 2>&1 || true
END=$(date +%s)
echo "ACTORS_RUNNER_SECONDS=$((END - START))"
