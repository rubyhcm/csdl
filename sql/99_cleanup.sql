-- Full reset: drop database + roles. Run as superuser connected to postgres (NOT audit_poc).
--   psql "postgresql://postgres:postgres@localhost/postgres" -f sql/99_cleanup.sql

\echo '=== Cleanup: dropping database and roles ==='

SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'audit_poc' AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS audit_poc;
DROP ROLE IF EXISTS db_admin;
DROP ROLE IF EXISTS app_user;
DROP ROLE IF EXISTS auditor;

\echo '=== Cleanup done. Re-run 00_roles.sql to start fresh. ==='
