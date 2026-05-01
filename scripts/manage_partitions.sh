#!/usr/bin/env bash
# Partition Management Script
# Usage: bash scripts/manage_partitions.sh [create|drop_old|list]

set -euo pipefail

# Load environment variables if .env exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DB="postgresql://${PGUSER:-db_admin}:${PGPASSWORD:-db_admin_pass}@${PGHOST:-localhost}/${PGDATABASE:-audit_poc}"
RETENTION_MONTHS=${PARTITION_RETENTION_MONTHS:-6}

ACTION=${1:-list}

case "$ACTION" in
  create)
    echo "=== Creating future partitions ==="
    psql "$DB" -c "
      DO \$\$
      DECLARE
        start_date date := date_trunc('month', CURRENT_DATE);
        end_date date := date_trunc('month', CURRENT_DATE) + interval '3 months';
        partition_name text;
        start_str text;
        end_str text;
      BEGIN
        WHILE start_date < end_date LOOP
          partition_name := 'audit_logs_' || to_char(start_date, 'YYYY_MM');
          start_str := to_char(start_date, 'YYYY-MM-DD');
          end_str := to_char(start_date + interval '1 month', 'YYYY-MM-DD');
          
          EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs FOR VALUES FROM (%L) TO (%L)',
                         partition_name, start_str, end_str);
          RAISE NOTICE 'Ensured partition: %', partition_name;
          start_date := start_date + interval '1 month';
        END LOOP;
      END;
      \$\$;
    "
    ;;
    
  drop_old)
    echo "=== Dropping partitions older than ${RETENTION_MONTHS} months ==="
    psql "$DB" -t -c "
      SELECT format('DROP TABLE IF EXISTS %I;', schemaname||'.'||tablename)
      FROM pg_tables
      WHERE schemaname = 'public'
        AND tablename LIKE 'audit_logs_%'
        AND tablename ~ '^audit_logs_[0-9]{4}_[0-9]{2}$'
        AND to_date(substring(tablename from 'audit_logs_([0-9]{4}_[0-9]{2})'), 'YYYY_MM') 
            < date_trunc('month', CURRENT_DATE) - interval '${RETENTION_MONTHS} months'
      ORDER BY tablename;
    " | psql "$DB"
    echo "Done."
    ;;
    
  list)
    echo "=== Current Partitions ==="
    psql "$DB" -c "
      SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
        partitionboundexpr AS bound
      FROM pg_tables t
      LEFT JOIN pg_partition_tree('audit_logs') p ON p.relname = t.tablename
      WHERE t.schemaname = 'public'
        AND t.tablename LIKE 'audit_logs_%'
      ORDER BY t.tablename;
    "
    ;;
    
  *)
    echo "Usage: $0 {create|drop_old|list}"
    exit 1
    ;;
esac
