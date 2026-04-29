-- Phase 3 (optional): tamper-evident hash chain for audit_logs
-- Requires: pgcrypto extension (already installed in Phase 0)
-- Run as db_admin:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/06_hash_chain.sql
--
-- NOTE: adds one SELECT per INSERT (prev_hash lookup) — measure overhead separately.
-- Disable this trigger before large seed runs (sql/03_seed_data.sql).

\echo '=== 06_hash_chain.sql ==='

-- Columns already added in 01_schema_audit.sql (prev_hash BYTEA, hash BYTEA)

-- ────────────────────────────────────────────────
-- 1. Hash chain BEFORE INSERT function
-- ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION func_audit_hash_chain()
RETURNS TRIGGER AS $$
DECLARE
    v_prev    BYTEA;
    v_payload TEXT;
BEGIN
    -- Find latest hash for the same table (per-table chain)
    SELECT hash INTO v_prev
    FROM audit_logs
    WHERE table_name = NEW.table_name
    ORDER BY changed_at DESC, id DESC
    LIMIT 1;

    -- Canonical payload: deterministic concatenation of key fields
    v_payload :=
        COALESCE(NEW.table_name, '')   || '|' ||
        COALESCE(NEW.operation, '')    || '|' ||
        COALESCE(NEW.user_name, '')    || '|' ||
        COALESCE(NEW.old_data::text, '') || '|' ||
        COALESCE(NEW.new_data::text, '') || '|' ||
        NEW.changed_at::text;

    NEW.prev_hash := v_prev;
    NEW.hash := digest(
        COALESCE(v_prev, ''::bytea) || v_payload::bytea,
        'sha256'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SET search_path = public, pg_temp;

\echo '  func_audit_hash_chain: OK'

DROP TRIGGER IF EXISTS trg_audit_hash ON audit_logs;

CREATE TRIGGER trg_audit_hash
BEFORE INSERT ON audit_logs
FOR EACH ROW EXECUTE FUNCTION func_audit_hash_chain();

\echo '  trg_audit_hash: OK'

-- ────────────────────────────────────────────────
-- 2. Verifier function: walk chain and detect tampering
-- ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION func_verify_hash_chain(p_table TEXT)
RETURNS TABLE (
    log_id      BIGINT,
    changed_at  TIMESTAMP,
    chain_ok    BOOLEAN,
    detail      TEXT
) AS $$
DECLARE
    r           RECORD;
    v_prev      BYTEA := NULL;
    v_payload   TEXT;
    v_expected  BYTEA;
BEGIN
    FOR r IN
        SELECT al.id, al.table_name, al.operation, al.user_name,
               al.old_data, al.new_data, al.changed_at, al.prev_hash, al.hash
        FROM audit_logs al
        WHERE al.table_name = p_table
        ORDER BY al.changed_at, al.id
    LOOP
        v_payload :=
            COALESCE(r.table_name, '')     || '|' ||
            COALESCE(r.operation, '')      || '|' ||
            COALESCE(r.user_name, '')      || '|' ||
            COALESCE(r.old_data::text, '') || '|' ||
            COALESCE(r.new_data::text, '') || '|' ||
            r.changed_at::text;

        v_expected := digest(
            COALESCE(v_prev, ''::bytea) || v_payload::bytea,
            'sha256'
        );

        log_id     := r.id;
        changed_at := r.changed_at;

        -- Rows seeded with hash trigger disabled have hash = NULL → skip
        IF r.hash IS NULL THEN
            chain_ok := NULL;
            detail   := 'SKIPPED — no hash (seeded before trigger)';
            v_prev   := NULL;
            RETURN NEXT;
            CONTINUE;
        END IF;

        chain_ok := (r.hash = v_expected);
        detail   := CASE
            WHEN r.hash = v_expected THEN 'OK'
            ELSE 'HASH MISMATCH — chain broken at id=' || r.id
        END;

        v_prev := r.hash;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql
   SET search_path = public, pg_temp;

\echo '  func_verify_hash_chain: OK'
\echo '=== 06_hash_chain.sql done ==='
\echo 'Usage: SELECT * FROM func_verify_hash_chain(''public.orders'');'
