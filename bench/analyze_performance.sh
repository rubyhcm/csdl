#!/usr/bin/env bash
# Analyze pg_stat_statements after benchmark runs
# Usage: bash bench/analyze_performance.sh

# Load environment variables from .env if present (same pattern as manage_partitions.sh)
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DB="postgresql://${PGUSER:-db_admin}:${PGPASSWORD:-db_admin_pass}@${PGHOST:-localhost}/${PGDATABASE:-audit_poc}"

echo "=== Top Queries by Total Time ==="
psql "$DB" -c "
  SELECT 
    substr(query, 1, 80) AS query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    rows,
    (100 * total_exec_time / sum(total_exec_time) OVER())::numeric(5,2) AS pct_time
  FROM pg_stat_statements
  ORDER BY total_exec_time DESC
  LIMIT 15;
"

echo ""
echo "=== Queries with Most Calls ==="
psql "$DB" -c "
  SELECT 
    substr(query, 1, 60) AS query_preview,
    calls,
    mean_exec_time
  FROM pg_stat_statements
  ORDER BY calls DESC
  LIMIT 10;
"

echo ""
echo "=== Audit Trigger Impact ==="
psql "$DB" -c "
  SELECT 
    query LIKE '%audit_logs%' AS is_audit,
    count(*) AS num_queries,
    sum(calls) AS total_calls,
    sum(total_exec_time) AS total_time
  FROM pg_stat_statements
  GROUP BY is_audit
  ORDER BY is_audit;
"

echo ""
echo "=== Table Access Patterns ==="
psql "$DB" -c "
  SELECT 
    schemaname,
    relname AS table_name,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del
  FROM pg_stat_user_tables
  WHERE schemaname = 'public'
  ORDER BY (seq_scan + idx_scan) DESC;
"
