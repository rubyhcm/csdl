-- Phase 1: business tables — orders, products
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/02_schema_business.sql

\echo '=== 02_schema_business.sql ==='

CREATE TABLE IF NOT EXISTS orders (
    id            BIGSERIAL PRIMARY KEY,
    customer_id   INT           NOT NULL,
    total_amount  NUMERIC(12,2) NOT NULL,
    status        TEXT          NOT NULL,
    created_at    TIMESTAMP     NOT NULL
);

\echo '  orders table: OK'

CREATE TABLE IF NOT EXISTS products (
    id         BIGSERIAL PRIMARY KEY,
    sku        TEXT  UNIQUE NOT NULL,
    tech_specs JSONB
);

\echo '  products table: OK'
\echo '=== 02_schema_business.sql done ==='
