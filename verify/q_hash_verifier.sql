-- Hash chain verification: chứng minh tamper-evident logging
-- Run as auditor:
--   psql "postgresql://auditor:auditor_pass@localhost/audit_poc" -f verify/q_hash_verifier.sql

\echo '=== Hash Chain Verification ==='

-- Summary: bao nhiêu rows có hash, bao nhiêu OK vs MISMATCH
SELECT
    CASE
        WHEN chain_ok IS NULL  THEN 'SKIPPED (no hash)'
        WHEN chain_ok = true   THEN 'OK'
        ELSE                        'MISMATCH'
    END                                           AS status,
    count(*)                                      AS row_count
FROM func_verify_hash_chain('public.orders')
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '--- Recent rows with valid hash chain ---'
SELECT log_id, changed_at, chain_ok, detail
FROM func_verify_hash_chain('public.orders')
WHERE chain_ok IS NOT NULL
ORDER BY log_id
LIMIT 20;

\echo ''
\echo '--- Stats ---'
SELECT
    count(*)                                   AS total_verified,
    sum(CASE WHEN chain_ok = true  THEN 1 END) AS chain_ok,
    sum(CASE WHEN chain_ok = false THEN 1 END) AS chain_broken,
    sum(CASE WHEN chain_ok IS NULL THEN 1 END) AS skipped_no_hash
FROM func_verify_hash_chain('public.orders');
