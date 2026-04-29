-- Phase 4: seed data — orders (1M), products (100K), audit_logs history (7.5M)
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/03_seed_data.sql
--
-- Strategy:
--   - Disable audit triggers before seeding business tables (no spurious log rows)
--   - Disable hash chain trigger before seeding audit_logs history (performance)
--   - Seed 5 cold partitions x 1.5M rows = 7.5M historical audit rows
--   - Re-enable all triggers after seeding

\echo '=== 03_seed_data.sql — start ==='
\timing on

-- ────────────────────────────────────────────────
-- 0. Clean slate
-- ────────────────────────────────────────────────
\echo '--- 0. Cleaning existing data ---'

ALTER TABLE orders   DISABLE TRIGGER trg_audit_orders;
ALTER TABLE products DISABLE TRIGGER trg_audit_products;
ALTER TABLE audit_logs DISABLE TRIGGER trg_audit_hash;

TRUNCATE orders, products;

-- Clear all audit partition data (keep structure)
TRUNCATE audit_logs_2025_10, audit_logs_2025_11, audit_logs_2025_12,
         audit_logs_2026_01, audit_logs_2026_02, audit_logs_2026_03,
         audit_logs_2026_04, audit_logs_2026_05;

-- Clear test alerts
TRUNCATE security_alerts;

\echo '--- Clean done ---'

-- ────────────────────────────────────────────────
-- 1. Seed orders: 1,000,000 rows
--    created_at rải đều 180 ngày qua
-- ────────────────────────────────────────────────
\echo '--- 1. Seeding orders (1,000,000 rows) ---'

INSERT INTO orders (customer_id, total_amount, status, created_at)
SELECT
    floor(random() * 50000 + 1)::int,
    round((random() * 99900000 + 100000)::numeric, 2),
    (ARRAY['PENDING','PAID','SHIPPED','CANCELLED'])[floor(random() * 4 + 1)],
    now() - (random() * interval '180 days')
FROM generate_series(1, 1000000);

\echo '--- orders: done ---'

-- ────────────────────────────────────────────────
-- 2. Seed products: 100,000 rows (50/50 laptop / áo)
-- ────────────────────────────────────────────────
\echo '--- 2. Seeding products (100,000 rows) ---'

INSERT INTO products (sku, tech_specs)
SELECT
    'SKU-' || gs::text,
    CASE WHEN random() < 0.5
        THEN jsonb_build_object('cpu', 'Core i9', 'ram', '32GB', 'screen', '15 inch')
        ELSE jsonb_build_object('color', 'Blue', 'size', 'L', 'material', 'Cotton')
    END
FROM generate_series(1, 100000) gs;

\echo '--- products: done ---'

-- Re-enable business triggers
ALTER TABLE orders   ENABLE TRIGGER trg_audit_orders;
ALTER TABLE products ENABLE TRIGGER trg_audit_products;

-- ────────────────────────────────────────────────
-- 3. Seed historical audit_logs: 5 cold partitions x 1,500,000 rows
--    Hash chain trigger stays DISABLED for performance (re-enabled at end)
-- ────────────────────────────────────────────────
\echo '--- 3. Seeding audit_logs history (7,500,000 rows across 5 partitions) ---'

-- Helper: build realistic old/new JSONB pair for an order status change
-- old_status -> new_status (simulate UPDATE workload)

-- Partition 2025-11
\echo '  partition 2025-11 (1,500,000 rows)...'
INSERT INTO audit_logs_2025_11
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders',
    'UPDATE',
    'app_user',
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PENDING','PAID','SHIPPED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PAID','SHIPPED','CANCELLED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    '2025-11-01'::timestamp + random() * interval '29 days'
FROM generate_series(1, 1500000);

-- Partition 2025-12
\echo '  partition 2025-12 (1,500,000 rows)...'
INSERT INTO audit_logs_2025_12
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders',
    'UPDATE',
    'app_user',
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PENDING','PAID','SHIPPED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PAID','SHIPPED','CANCELLED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    '2025-12-01'::timestamp + random() * interval '30 days'
FROM generate_series(1, 1500000);

-- Partition 2026-01
\echo '  partition 2026-01 (1,500,000 rows)...'
INSERT INTO audit_logs_2026_01
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders',
    'UPDATE',
    'app_user',
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PENDING','PAID','SHIPPED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PAID','SHIPPED','CANCELLED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    '2026-01-01'::timestamp + random() * interval '30 days'
FROM generate_series(1, 1500000);

-- Partition 2026-02
\echo '  partition 2026-02 (1,500,000 rows)...'
INSERT INTO audit_logs_2026_02
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders',
    'UPDATE',
    'app_user',
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PENDING','PAID','SHIPPED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PAID','SHIPPED','CANCELLED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    '2026-02-01'::timestamp + random() * interval '27 days'
FROM generate_series(1, 1500000);

-- Partition 2026-03
\echo '  partition 2026-03 (1,500,000 rows)...'
INSERT INTO audit_logs_2026_03
    (table_name, operation, user_name, old_data, new_data, changed_at)
SELECT
    'public.orders',
    'UPDATE',
    'app_user',
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PENDING','PAID','SHIPPED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    jsonb_build_object(
        'id',           floor(random() * 1000000 + 1)::bigint,
        'customer_id',  floor(random() * 50000 + 1)::int,
        'total_amount', round((random() * 99900000 + 100000)::numeric, 2),
        'status',       (ARRAY['PAID','SHIPPED','CANCELLED'])[floor(random()*3+1)],
        'created_at',   (now() - random() * interval '180 days')::text
    ),
    '2026-03-01'::timestamp + random() * interval '30 days'
FROM generate_series(1, 1500000);

\echo '--- audit_logs history: done ---'

-- Re-enable hash chain trigger
ALTER TABLE audit_logs ENABLE TRIGGER trg_audit_hash;

-- ────────────────────────────────────────────────
-- 4. VACUUM ANALYZE
-- ────────────────────────────────────────────────
\echo '--- 4. VACUUM ANALYZE ---'
VACUUM ANALYZE orders;
VACUUM ANALYZE products;
VACUUM ANALYZE audit_logs;

-- ────────────────────────────────────────────────
-- 5. Size report
-- ────────────────────────────────────────────────
\echo '--- 5. Size report ---'

SELECT
    relname                                          AS table_name,
    pg_size_pretty(pg_total_relation_size(oid))      AS total_size,
    to_char(reltuples::bigint, '999,999,999')        AS est_rows
FROM pg_class
WHERE relname IN ('orders','products','audit_logs')
   OR relname LIKE 'audit_logs_20%'
ORDER BY
    CASE WHEN relname = 'orders'     THEN 0
         WHEN relname = 'products'   THEN 1
         WHEN relname = 'audit_logs' THEN 2
         ELSE 3
    END, relname;

\timing off
\echo '=== 03_seed_data.sql — done ==='
