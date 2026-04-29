-- Phase 3: security demo — 3 attack cases
-- Run as db_admin (controls \connect switches):
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=0 -f verify/q_security_demo.sql
--
-- ON_ERROR_STOP=0 is intentional: cases 2 and 3 are EXPECTED to error.

\echo ''
\echo '╔══════════════════════════════════════════════════════╗'
\echo '║           SECURITY DEMO — 3 attack cases            ║'
\echo '╚══════════════════════════════════════════════════════╝'

-- ────────────────────────────────────────────────
-- Case 1: app_user UPDATE orders → audit log ghi OK
-- ────────────────────────────────────────────────
\echo ''
\echo '─── Case 1: app_user UPDATE orders (expect: audit row written) ───'

\c "postgresql://app_user:app_user_pass@localhost/audit_poc"

-- seed a fresh order to work with
INSERT INTO orders (customer_id, total_amount, status, created_at)
VALUES (9999, 1000000, 'PENDING', now());

UPDATE orders
SET status = 'SHIPPED'
WHERE customer_id = 9999
  AND status = 'PENDING';

\c "postgresql://auditor:auditor_pass@localhost/audit_poc"

SELECT
    'Case 1' AS case_num,
    CASE WHEN count(*) > 0 THEN 'PASS — audit row found' ELSE 'FAIL — no audit row' END AS result,
    count(*) AS audit_rows
FROM audit_logs
WHERE table_name = 'public.orders'
  AND operation   = 'UPDATE'
  AND user_name   = 'app_user'
  AND new_data->>'status' = 'SHIPPED';

-- ────────────────────────────────────────────────
-- Case 2: app_user SELECT audit_logs → permission denied
-- ────────────────────────────────────────────────
\echo ''
\echo '─── Case 2: app_user SELECT audit_logs (expect: permission denied) ───'

\c "postgresql://app_user:app_user_pass@localhost/audit_poc"

\set ON_ERROR_STOP 0
SELECT 'Case 2 — should NOT reach here' AS result FROM audit_logs LIMIT 1;
\set ON_ERROR_STOP 0

-- The error message from PostgreSQL IS the proof; script continues.
\echo 'Case 2: PASS if ERROR above says "permission denied for table audit_logs"'

-- ────────────────────────────────────────────────
-- Case 3: db_admin DELETE audit_logs → blocked + security_alerts written
-- ────────────────────────────────────────────────
\echo ''
\echo '─── Case 3: db_admin DELETE audit_logs (expect: exception + alert) ───'

\c "postgresql://db_admin:db_admin_pass@localhost/audit_poc"

\set ON_ERROR_STOP 0
DELETE FROM audit_logs
WHERE (id, changed_at) IN (
  SELECT id, changed_at
  FROM audit_logs
  WHERE user_name = 'app_user'
  ORDER BY changed_at DESC
  LIMIT 1
);
\set ON_ERROR_STOP 0

\echo 'Case 3: checking security_alerts for AUDIT_TAMPER_ATTEMPT...'

SELECT
    'Case 3' AS case_num,
    CASE WHEN count(*) > 0 THEN 'PASS — tamper attempt recorded' ELSE 'FAIL — no alert written' END AS result,
    count(*) AS alert_rows,
    max(user_name) AS attacker,
    max(action)    AS action
FROM security_alerts
WHERE action = 'AUDIT_TAMPER_ATTEMPT';

-- ────────────────────────────────────────────────
-- Summary
-- ────────────────────────────────────────────────
\echo ''
\echo '╔══════════════════════════════════════════════════════╗'
\echo '║  All 3 cases complete. Review PASS/FAIL lines above. ║'
\echo '╚══════════════════════════════════════════════════════╝'
