-- Phase 2: generic audit trigger function + attach to business tables
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/04_audit_function.sql

\echo '=== 04_audit_function.sql ==='

-- ────────────────────────────────────────────────
-- 1. Generic audit trigger function
-- ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION func_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_table TEXT := TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
BEGIN
    -- session_user = người dùng kết nối thực (không bị ảnh hưởng SECURITY DEFINER)
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, old_data)
        VALUES (v_table, 'DELETE', session_user, to_jsonb(OLD));
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, old_data, new_data)
        VALUES (v_table, 'UPDATE', session_user, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, new_data)
        VALUES (v_table, 'INSERT', session_user, to_jsonb(NEW));
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, pg_temp;

\echo '  func_audit_trigger: OK'

-- ────────────────────────────────────────────────
-- 2. Attach triggers to business tables
-- ────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_orders   ON orders;
DROP TRIGGER IF EXISTS trg_audit_products ON products;

CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();

CREATE TRIGGER trg_audit_products
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();

\echo '  trg_audit_orders + trg_audit_products: OK'
\echo '=== 04_audit_function.sql done ==='
