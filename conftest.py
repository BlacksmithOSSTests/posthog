"""Root conftest.py — xdist ClickHouse instance routing for benchmark experiments.

When running with pytest-xdist (-n 2), routes each worker to its own ClickHouse:
  gw0 → port 8123 (default, started by docker-compose)
  gw1 → port 8124 (second instance, started by the benchmark workflow)
  gw2 → port 8125, etc.

This is a session-scoped autouse fixture, so it runs before any package-scoped
django_db_setup fixture creates the ClickHouse Database objects — meaning each
worker's db_url is already correctly overridden when tables are created.

Without this file (or when CH_XDIST_ROUTING=0), all workers share port 8123
with separate databases (posthog_test_gw0, posthog_test_gw1, ...) — that also
works because settings.py already handles PYTEST_XDIST_WORKER isolation.
"""

import os
import pytest


@pytest.fixture(scope="session", autouse=True)
def _route_clickhouse_to_worker_port():
    """Override CLICKHOUSE_HTTP_URL per xdist worker when CH_XDIST_ROUTING=1.

    Only active when both:
    - CH_XDIST_ROUTING=1 env var is set (opt-in, so single-CH experiments still work)
    - PYTEST_XDIST_WORKER is set to a non-gw0 worker

    gw0 keeps the default port 8123. gw1 gets 8124, gw2 gets 8125, ...
    """
    if os.environ.get("CH_XDIST_ROUTING") != "1":
        yield
        return

    worker_id = os.environ.get("PYTEST_XDIST_WORKER")
    if not worker_id or worker_id == "gw0":
        yield
        return

    try:
        worker_num = int("".join(c for c in worker_id if c.isdigit()))
    except ValueError:
        yield
        return

    port = 8123 + worker_num  # gw1→8124, gw2→8125, ...
    new_url = f"http://localhost:{port}/"

    # Patch Django settings — safe because this session fixture runs before
    # the package-scoped django_db_setup fixture creates any Database objects.
    from django.conf import settings

    original_url = getattr(settings, "CLICKHOUSE_HTTP_URL", None)
    settings.CLICKHOUSE_HTTP_URL = new_url

    # Also patch logs URL if it points to the same host
    original_logs = getattr(settings, "CLICKHOUSE_LOGS_URL", None)
    if original_logs and ":8123" in original_logs:
        settings.CLICKHOUSE_LOGS_URL = new_url

    print(f"\n[xdist routing] {worker_id} → ClickHouse {new_url}")
    yield

    # Restore (defensive cleanup, though session teardown handles it)
    if original_url is not None:
        settings.CLICKHOUSE_HTTP_URL = original_url
    if original_logs is not None:
        settings.CLICKHOUSE_LOGS_URL = original_logs
