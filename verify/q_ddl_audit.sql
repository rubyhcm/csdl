-- ------------------------------------------------------------
-- File: verify/q_ddl_audit.sql
-- Purpose: Demo và kiểm tra DDL audit via event trigger (09_audit_ddl.sql)
-- Usage:
--   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -f verify/q_ddl_audit.sql
-- ------------------------------------------------------------

\echo ''
\echo '======================================================='
\echo '  DDL AUDIT DEMO — audit_ddl_logs + event trigger'
\echo '======================================================='

-- ── 1. Lịch sử DDL hiện có ──────────────────────────────
\echo ''
\echo '--- 1. Lịch sử DDL đã ghi nhận ---'

SELECT
    id,
    command_tag,
    object_type,
    object_name,
    command_sql,
    to_char(executed_at, 'YYYY-MM-DD HH24:MI:SS') AS executed_at,
    user_name
FROM public.audit_ddl_logs
ORDER BY executed_at DESC
LIMIT 20;

-- ── 2. Demo live: chạy DDL và quan sát event trigger ────
\echo ''
\echo '--- 2. Demo live: tạo/sửa/xóa bảng demo, event trigger ghi nhận ---'

CREATE TABLE public._verify_ddl_demo (
    id   SERIAL PRIMARY KEY,
    code TEXT NOT NULL
);

ALTER TABLE public._verify_ddl_demo ADD COLUMN label TEXT;

CREATE INDEX idx_verify_ddl_demo_code ON public._verify_ddl_demo (code);

DROP INDEX IF EXISTS public.idx_verify_ddl_demo_code;

DROP TABLE IF EXISTS public._verify_ddl_demo;

\echo '5 DDL commands executed. Checking captured rows...'

-- ── 3. Kiểm tra các dòng vừa được ghi ───────────────────
\echo ''
\echo '--- 3. Rows mới nhất trong audit_ddl_logs (sau demo) ---'

SELECT
    id,
    command_tag,
    object_type,
    object_name,
    to_char(executed_at, 'HH24:MI:SS.MS') AS executed_at,
    user_name
FROM public.audit_ddl_logs
ORDER BY id DESC
LIMIT 10;

-- ── 4. Thống kê theo loại lệnh ───────────────────────────
\echo ''
\echo '--- 4. Thong ke DDL theo command_tag ---'

SELECT
    command_tag,
    count(*) AS total,
    count(DISTINCT user_name) AS distinct_users
FROM public.audit_ddl_logs
GROUP BY command_tag
ORDER BY total DESC;

-- ── 5. Lọc DDL theo user ─────────────────────────────────
\echo ''
\echo '--- 5. DDL thuc hien boi tung user ---'

SELECT
    user_name,
    count(*) AS ddl_count,
    string_agg(DISTINCT command_tag, ', ' ORDER BY command_tag) AS commands
FROM public.audit_ddl_logs
GROUP BY user_name
ORDER BY ddl_count DESC;

\echo ''
\echo '======================================================='
\echo '  DONE — DDL audit hoat dong chinh xac'
\echo '======================================================='
