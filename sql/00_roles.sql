-- Phase 0 / Phase 1: roles and database-level grants
-- Run as superuser (postgres):
--   psql "postgresql://postgres:postgres@localhost/postgres" -f sql/00_roles.sql
-- Then run grants section again connected to audit_poc after tables are created (see bottom).

\echo '=== Creating roles ==='

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'db_admin') THEN
    CREATE ROLE db_admin LOGIN PASSWORD 'db_admin_pass';
    RAISE NOTICE 'Created role db_admin';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user LOGIN PASSWORD 'app_user_pass';
    RAISE NOTICE 'Created role app_user';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditor') THEN
    CREATE ROLE auditor LOGIN PASSWORD 'auditor_pass';
    RAISE NOTICE 'Created role auditor';
  END IF;
END$$;

\echo '=== Creating database audit_poc ==='

SELECT 'EXISTS' AS status FROM pg_database WHERE datname = 'audit_poc'
UNION ALL
SELECT 'WILL_CREATE' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'audit_poc');

-- NOTE: CREATE DATABASE cannot run inside a transaction block.
-- Run manually if needed:
--   CREATE DATABASE audit_poc OWNER db_admin;
--   \c audit_poc
--   CREATE EXTENSION IF NOT EXISTS pgcrypto;

\echo '=== Done: 00_roles.sql ==='
\echo 'Next: connect to audit_poc as db_admin and run 01_schema_audit.sql'
\echo 'After all tables created, run 08_grants.sql to enforce GRANT/REVOKE.'
