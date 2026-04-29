-- Kịch bản 2: Partitioning — pruning proof + DROP vs DELETE timing
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f verify/q_partition_pruning.sql

\echo '=== Scenario 2: Partitioning & Retention ==='
\timing on

-- ── 2a. Partition pruning: planner chỉ scan 1 partition ──────────────────────
\echo ''
\echo '--- 2a. Partition pruning EXPLAIN ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*)
FROM audit_logs
WHERE changed_at BETWEEN '2026-03-01' AND '2026-03-31';

-- ── 2b. DROP PARTITION vs DELETE truyền thống ────────────────────────────────
-- Dùng partition 2025-10 (rỗng, safe để thử)
-- Tạo lại với dữ liệu test để đo thời gian thực tế

\echo ''
\echo '--- 2b. Seed 1,000,000 rows vào partition test (2025-10) ---'
ALTER TABLE audit_logs DISABLE TRIGGER trg_audit_hash;

INSERT INTO audit_logs_2025_10
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders', 'UPDATE', 'app_user',
    jsonb_build_object('id', i, 'status', 'PENDING'),
    jsonb_build_object('id', i, 'status', 'PAID'),
    '2025-10-01'::timestamp + (i % 2592000) * interval '1 second'
FROM generate_series(1, 1000000) i;

ALTER TABLE audit_logs ENABLE TRIGGER trg_audit_hash;

\echo '  1,000,000 rows seeded into audit_logs_2025_10'

-- Measure DELETE (traditional)
\echo ''
\echo '--- Measuring DELETE (traditional) on 2025-10 copy ---'

-- Backup via CTAS then measure DELETE on a renamed copy
CREATE TABLE audit_logs_2025_10_delete_test (LIKE audit_logs_2025_10 INCLUDING ALL);
INSERT INTO audit_logs_2025_10_delete_test SELECT * FROM audit_logs_2025_10;

\echo 'DELETE on 1M rows:'
DELETE FROM audit_logs_2025_10_delete_test;
DROP TABLE audit_logs_2025_10_delete_test;

-- Measure DROP PARTITION
\echo ''
\echo '--- Measuring DROP PARTITION on audit_logs_2025_10 (1M rows) ---'
\echo 'DROP PARTITION:'
DROP TABLE audit_logs_2025_10;

\echo ''
\echo '--- Recreate partition 2025-10 for idempotency ---'
SELECT func_create_monthly_partition('2025-10-01'::date);

\timing off
\echo '=== Scenario 2 done. Compare DELETE vs DROP times above. ==='
