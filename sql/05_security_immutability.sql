-- Phase 3: immutability (append-only/WORM) for audit_logs
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/05_security_immutability.sql

\echo '=== 05_security_immutability.sql ==='

-- dblink extension required for autonomous-transaction alert writes
CREATE EXTENSION IF NOT EXISTS dblink;

-- ────────────────────────────────────────────────
-- 1. Function chặn UPDATE/DELETE + ghi security_alerts
--    INSERT alert qua dblink (autonomous transaction) để không bị rollback
--    cùng với RAISE EXCEPTION.
-- ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION func_prevent_audit_change()
RETURNS TRIGGER AS $$
DECLARE
    v_details JSONB;
    v_sql     TEXT;
BEGIN
    v_details := jsonb_build_object(
        'op',     TG_OP,
        'schema', TG_TABLE_SCHEMA
    );

    IF (TG_OP = 'UPDATE') THEN
        v_details := v_details || jsonb_build_object(
            'old', to_jsonb(OLD),
            'new', to_jsonb(NEW)
        );
    ELSIF (TG_OP = 'DELETE') THEN
        v_details := v_details || jsonb_build_object('old', to_jsonb(OLD));
    END IF;

    -- Ghi alert vào transaction độc lập (không bị rollback khi exception xảy ra)
    v_sql := format(
        'INSERT INTO security_alerts(action, table_name, user_name, details) VALUES (%L, %L, %L, %L)',
        'AUDIT_TAMPER_ATTEMPT', TG_TABLE_NAME, session_user, v_details::text
    );
    PERFORM dblink_exec('dbname=audit_poc host=localhost user=db_admin password=db_admin_pass', v_sql);

    RAISE EXCEPTION 'Audit log is immutable — % on % is not allowed (user: %)',
        TG_OP, TG_TABLE_NAME, session_user;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, pg_temp;

\echo '  func_prevent_audit_change: OK'

-- ────────────────────────────────────────────────
-- 2. Attach BEFORE trigger to audit_logs parent
--    (cascades to all partition children automatically)
-- ────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_protect_audit ON audit_logs;

CREATE TRIGGER trg_protect_audit
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION func_prevent_audit_change();

\echo '  trg_protect_audit: OK'
\echo '=== 05_security_immutability.sql done ==='
