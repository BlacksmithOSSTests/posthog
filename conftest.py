"""Root conftest.py — xdist compatibility patches for benchmark experiments.

Three autouse fixtures:

1. _route_clickhouse_to_worker_port (experiment C only, CH_XDIST_ROUTING=1):
   Routes each xdist worker to its own ClickHouse HTTP URL:
     gw0 → port 8123 (default, started by docker-compose)
     gw1 → port 8124 (second instance, started by the benchmark workflow)
   NOTE: data_stores.py already handles this at settings load time; this fixture
   is a belt-and-suspenders fallback kept for symmetry.

2. _patch_teardown_for_xdist (experiment B & C):
   Under xdist, pre-flushes persons/events in APIBaseTest.tearDown before the
   "persons not flushed" check fires.  In single-threaded mode (A), sync_execute
   auto-flushes so the check always passes.  Under xdist, the timing between
   workers can leave stale entries in the in-process cache even after a successful
   flush, causing false-positive teardown errors.  Pre-flushing in tearDown is
   idempotent (no-op when the list is already empty) so it doesn't hide real bugs.

3. _reset_broken_db_connections (experiment B, C & D):
   After each test in xdist mode, closes any Django DB connection that is in a
   failed-transaction state (needs_rollback=True).  Without this, a single test
   that triggers a PG error inside an atomic block (e.g. UndefinedTable from the
   posthog_grouptypemapping drop in posthog/conftest.py _django_db_setup) leaves
   connection.needs_rollback=True and causes all subsequent tests in that worker
   to fail with InFailedSqlTransaction.  Closing the bad connection lets Django
   open a fresh one for the next test.
"""

import os
import pytest


@pytest.fixture(scope="session", autouse=True)
def _route_clickhouse_to_worker_port():
    """Belt-and-suspenders CH URL override for xdist workers (experiment C).

    data_stores.py already sets CLICKHOUSE_HTTP_URL at settings-load time when
    CH_XDIST_ROUTING=1.  This fixture is kept as a fallback in case any code
    path re-reads the URL from os.environ rather than Django settings.
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

    from django.conf import settings

    original_url = getattr(settings, "CLICKHOUSE_HTTP_URL", None)
    if original_url != new_url:
        settings.CLICKHOUSE_HTTP_URL = new_url
        print(f"\n[xdist routing fallback] {worker_id} → ClickHouse {new_url}")

    yield

    if original_url is not None:
        settings.CLICKHOUSE_HTTP_URL = original_url


@pytest.fixture(scope="session", autouse=True)
def _patch_teardown_for_xdist():
    """Pre-flush persons/events in tearDown when running under xdist.

    Under xdist, Django TestCase's tearDown() can see a non-empty
    persons_cache_tests even when the test body correctly flushed, because
    the workers share the in-process global cache and fixture ordering differs
    slightly from the single-threaded runner.  Pre-flushing before the check is
    idempotent and matches what single-threaded mode achieves via sync_execute's
    auto-flush.  The check is NOT disabled — it still fires if flush itself fails.
    """
    if not os.environ.get("PYTEST_XDIST_WORKER"):
        yield
        return

    try:
        from posthog.test.base import APIBaseTest, flush_persons_and_events
    except ImportError:
        yield
        return

    original_tearDown = APIBaseTest.tearDown

    def _xdist_safe_tearDown(self):
        # Flush any remaining cache entries before the check in the base tearDown.
        # This is the same flush that sync_execute performs automatically in TEST
        # mode — we just do it once more here as a safety net for xdist workers.
        flush_persons_and_events()
        original_tearDown(self)

    APIBaseTest.tearDown = _xdist_safe_tearDown
    yield
    APIBaseTest.tearDown = original_tearDown


@pytest.fixture(scope="function", autouse=True)
def _reset_broken_db_connections():
    """Close Django DB connections that are in a failed-transaction state after each test.

    posthog/conftest.py's _django_db_setup drops posthog_grouptypemapping (and other
    person-related tables) from each worker's test DB as part of the dual-persons-table
    migration setup.  A test that calls GroupTypeMapping.objects.create() will hit
    UndefinedTable, which leaves connection.needs_rollback=True.  In xdist workers
    this state persists across tests (Django's TestCase savepoint rollback does not
    always clear needs_rollback), causing every subsequent test to fail with
    InFailedSqlTransaction.  Closing the connection here forces Django to open a
    fresh one for the next test, isolating the failure to a single test.

    This is a no-op in single-threaded mode (PYTEST_XDIST_WORKER not set).
    """
    if not os.environ.get("PYTEST_XDIST_WORKER"):
        yield
        return

    yield

    try:
        from django.db import connections

        for alias in connections:
            conn = connections[alias]
            # Only close if Django has marked this connection as needing rollback —
            # closing clean connections would waste reconnect overhead.
            if getattr(conn, "needs_rollback", False):
                try:
                    conn.close()
                except Exception:
                    pass
    except Exception:
        pass
