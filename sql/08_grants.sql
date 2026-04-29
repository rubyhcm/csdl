-- Phase 1: enforce security model via GRANT/REVOKE
-- Run AFTER all tables are created (01, 02 done).
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/08_grants.sql

\echo '=== 08_grants.sql ==='

-- ── app_user: business tables only ──────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON orders, products TO app_user;
GRANT USAGE, SELECT ON SEQUENCE orders_id_seq, products_id_seq TO app_user;

-- app_user must NOT access audit tables directly
-- (writes go through SECURITY DEFINER trigger function)
REVOKE ALL ON audit_logs     FROM PUBLIC;
REVOKE ALL ON security_alerts FROM PUBLIC;

DO $$
BEGIN
    -- app_user may already have no grants, REVOKE is safe either way
    EXECUTE 'REVOKE ALL ON audit_logs      FROM app_user';
    EXECUTE 'REVOKE ALL ON security_alerts FROM app_user';
EXCEPTION WHEN OTHERS THEN
    NULL; -- role may not have had explicit grants
END$$;

\echo '  app_user: granted orders+products, revoked audit_logs+security_alerts'

-- ── auditor: read-only on audit tables ──────────────────────────────────────
GRANT SELECT ON audit_logs, security_alerts TO auditor;

\echo '  auditor: SELECT on audit_logs + security_alerts'

-- ── db_admin already owns objects; make explicit for clarity ─────────────────
GRANT ALL ON audit_logs, security_alerts, orders, products TO db_admin;

\echo '  db_admin: ALL on all tables'
\echo '=== 08_grants.sql done ==='
