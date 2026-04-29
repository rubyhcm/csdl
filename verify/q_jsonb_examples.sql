-- Kịch bản 4: Read performance — JSONB queries with vs without GIN index
-- Run as auditor:
--   psql "postgresql://auditor:auditor_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f verify/q_jsonb_examples.sql
-- NOTE: must run q_jsonb_no_gin.sql (drops GIN) then this file (with GIN) to compare.
--       Or use the combined script below which drops/recreates GIN inline (requires db_admin).

\echo '=== Scenario 4: JSONB Query Performance ==='
\timing on

-- ── Sample queries for audit/report (functional verification) ─────────────────

\echo ''
\echo '--- Query 1: Last 50 changes to orders table ---'
SELECT operation, user_name, new_data->>'status' AS new_status, changed_at
FROM audit_logs
WHERE table_name = 'public.orders'
ORDER BY changed_at DESC
LIMIT 50;

\echo ''
\echo '--- Query 2: Orders changed to PAID status (JSONB key/value filter) ---'
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data->>'status' = 'PAID';

\echo ''
\echo '--- Query 3: Laptop products changed (nested JSONB) ---'
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.products'
  AND new_data->'tech_specs'->>'cpu' = 'Core i9';

\echo ''
\echo '--- Query 4: Changes by specific user in time range ---'
SELECT count(*)
FROM audit_logs
WHERE user_name = 'app_user'
  AND changed_at >= now() - interval '30 days';

-- ── GIN performance comparison ────────────────────────────────────────────────
-- Run as db_admin to drop/recreate GIN

\echo ''
\echo '=== GIN Performance Comparison (run as db_admin) ==='

\echo '--- WITH GIN index (current state) ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*)
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}';

\timing off
\echo ''
\echo 'To measure WITHOUT GIN: drop idx_audit_new_data_gin, re-run EXPLAIN, then recreate index.'
\echo 'Command: DROP INDEX CONCURRENTLY idx_audit_new_data_gin_2026_03; (per partition)'
\echo 'Or use verify/q_gin_comparison.sql for automated before/after measurement.'
