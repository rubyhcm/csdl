-- Phase 1: audit schema — audit_logs (partitioned), security_alerts, auto-partition function
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/01_schema_audit.sql

\echo '=== 01_schema_audit.sql ==='

-- ────────────────────────────────────────────────
-- 1. Bảng cha: audit_logs (partitioned by RANGE)
-- ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    id           BIGSERIAL,
    table_name   TEXT      NOT NULL,
    operation    TEXT      NOT NULL,   -- INSERT / UPDATE / DELETE
    user_name    TEXT,
    old_data     JSONB,
    new_data     JSONB,
    changed_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- hash chain (tamper-evident, optional — populated by 06_hash_chain.sql)
    prev_hash    BYTEA,
    hash         BYTEA,
    PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);

\echo '  audit_logs parent table: OK'

-- ────────────────────────────────────────────────
-- 2. Bảng security_alerts
-- ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS security_alerts (
    id         BIGSERIAL PRIMARY KEY,
    alert_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action     TEXT      NOT NULL,
    table_name TEXT,
    user_name  TEXT,
    details    JSONB
);

\echo '  security_alerts table: OK'

-- ────────────────────────────────────────────────
-- 3. Hàm tạo partition tự động theo tháng (idempotent)
-- ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION func_create_monthly_partition(p_month DATE)
RETURNS TEXT AS $$
DECLARE
    v_start DATE := date_trunc('month', p_month)::date;
    v_end   DATE := (v_start + INTERVAL '1 month')::date;
    v_name  TEXT := format('audit_logs_%s', to_char(v_start, 'YYYY_MM'));
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs FOR VALUES FROM (%L) TO (%L)',
        v_name, v_start, v_end
    );
    RETURN v_name;
END;
$$ LANGUAGE plpgsql;

\echo '  func_create_monthly_partition: OK'

-- ────────────────────────────────────────────────
-- 4. Bootstrap partitions:
--    6 lịch sử (cold) + tháng hiện tại + tháng kế (hot/next)
-- ────────────────────────────────────────────────
DO $$
DECLARE
    v_name TEXT;
    i      INT;
BEGIN
    -- current month (i=0) + 6 history months (i=1..6)
    FOR i IN 0..6 LOOP
        v_name := func_create_monthly_partition(
            (date_trunc('month', now()) - (i || ' months')::interval)::date
        );
        RAISE NOTICE '  Partition: %', v_name;
    END LOOP;
    -- next month
    v_name := func_create_monthly_partition(
        (date_trunc('month', now()) + INTERVAL '1 month')::date
    );
    RAISE NOTICE '  Partition (next): %', v_name;
END$$;

\echo '=== 01_schema_audit.sql done ==='
