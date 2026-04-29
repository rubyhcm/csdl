-- Phase 5: indexes for query performance
-- IMPORTANT: run AFTER seeding data (03_seed_data.sql) for faster index build.
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/07_indexes.sql

\echo '=== 07_indexes.sql ==='
\timing on

-- ── audit_logs indexes ────────────────────────────────────────────────────────

-- Range queries by time (reports, pagination)
\echo '  Creating idx_audit_changed_at...'
CREATE INDEX IF NOT EXISTS idx_audit_changed_at
ON audit_logs (changed_at);

-- Per-table history queries (most common query pattern)
\echo '  Creating idx_audit_table_time...'
CREATE INDEX IF NOT EXISTS idx_audit_table_time
ON audit_logs (table_name, changed_at);

-- Per-user tracing
\echo '  Creating idx_audit_user_time...'
CREATE INDEX IF NOT EXISTS idx_audit_user_time
ON audit_logs (user_name, changed_at);

-- Deep JSONB search (Scenario 4 benchmark: with vs without GIN)
\echo '  Creating idx_audit_new_data_gin (GIN — may take a while)...'
CREATE INDEX IF NOT EXISTS idx_audit_new_data_gin
ON audit_logs USING GIN (new_data);

\echo '  All audit_logs indexes: OK'

-- ── business table indexes ────────────────────────────────────────────────────
\echo '  Creating idx_orders_status...'
CREATE INDEX IF NOT EXISTS idx_orders_status
ON orders (status);

\echo '  Creating idx_orders_customer...'
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
ON orders (customer_id);

\echo '  Creating idx_products_gin...'
CREATE INDEX IF NOT EXISTS idx_products_gin
ON products USING GIN (tech_specs);

-- ── final ANALYZE ─────────────────────────────────────────────────────────────
\echo '--- VACUUM ANALYZE after indexing ---'
VACUUM ANALYZE audit_logs;
VACUUM ANALYZE orders;
VACUUM ANALYZE products;

-- ── index list ────────────────────────────────────────────────────────────────
\echo '--- Index summary ---'
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND relname IN ('orders','products','audit_logs')
ORDER BY relname, indexname;

\timing off
\echo '=== 07_indexes.sql done ==='
