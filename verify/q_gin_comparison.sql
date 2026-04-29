-- Kịch bản 4: GIN vs no-GIN — automated before/after measurement
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f verify/q_gin_comparison.sql

\echo '=== Scenario 4: GIN Index Performance Comparison ==='
\timing on

-- Target query: find all audit rows where order status changed to PAID
-- Uses JSONB containment operator @> which benefits from GIN

-- ── WITH GIN (current state) ─────────────────────────────────────────────────
\echo ''
\echo '--- WITH GIN index ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}';

-- ── DROP GIN (one partition at a time is faster; drop parent index) ───────────
\echo ''
\echo '--- Dropping GIN index (drop parent cascades to all partition children)... ---'
DROP INDEX IF EXISTS idx_audit_new_data_gin;

\echo '--- WITHOUT GIN index ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}';

-- ── RECREATE GIN ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- Recreating GIN index (may take ~2 minutes)... ---'
CREATE INDEX idx_audit_new_data_gin ON audit_logs USING GIN (new_data);

\echo ''
\echo '--- Confirm GIN restored: WITH GIN (verify) ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}';

\timing off
\echo '=== Scenario 4 done. Compare execution times above. ==='
