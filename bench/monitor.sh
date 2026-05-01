#!/usr/bin/env bash
# Real-time performance monitoring during benchmark
# Usage: bash bench/monitor.sh [duration_seconds]
# Default: monitor for 300 seconds (5 minutes)

# Load environment variables from .env if present
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DB="postgresql://${PGUSER:-db_admin}:${PGPASSWORD:-db_admin_pass}@${PGHOST:-localhost}/${PGDATABASE:-audit_poc}"
DURATION=${1:-300}
INTERVAL=5

echo "=== Real-time Performance Monitor ==="
echo "Monitoring for ${DURATION}s (interval: ${INTERVAL}s)"
echo "Press Ctrl+C to stop"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

# Seed the previous-transaction counter so the first TPS reading is meaningful
PREV_TXN=$(psql "$DB" -t -c "SELECT COALESCE(sum(xact_commit + xact_rollback), 0) FROM pg_stat_database WHERE datname = current_database();" 2>/dev/null | tr -d ' ')
[ -z "$PREV_TXN" ] && PREV_TXN=0

while [ $(date +%s) -lt $END_TIME ]; do
  TIMESTAMP=$(date '+%H:%M:%S')

  # Active connections
  CONNECTIONS=$(psql "$DB" -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tr -d ' ' || echo "0")

  # Transactions per second: delta since last sample divided by interval
  CURR_TXN=$(psql "$DB" -t -c "SELECT COALESCE(sum(xact_commit + xact_rollback), 0) FROM pg_stat_database WHERE datname = current_database();" 2>/dev/null | tr -d ' ' || echo "0")
  [ -z "$CURR_TXN" ] && CURR_TXN=0
  TPS=$(( (CURR_TXN - PREV_TXN) / INTERVAL ))
  PREV_TXN=$CURR_TXN

  # Table locks
  LOCKS=$(psql "$DB" -t -c "SELECT count(*) FROM pg_locks WHERE database = (SELECT oid FROM pg_database WHERE datname = current_database());" 2>/dev/null | tr -d ' ' || echo "0")

  # WAL written (MB)
  WAL=$(psql "$DB" -t -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::bigint / 1024 / 1024;" 2>/dev/null | tr -d ' ' || echo "0")

  # Cache hit ratio
  RATIO=$(psql "$DB" -t -c "SELECT round(100 * sum(blks_hit)::numeric / NULLIF(sum(blks_hit + blks_read), 0), 2) FROM pg_stat_database WHERE datname = current_database();" 2>/dev/null | tr -d ' ' || echo "0")

  # Audit logs count
  AUDIT_COUNT=$(psql "$DB" -t -c "SELECT count(*) FROM audit_logs;" 2>/dev/null | tr -d ' ' || echo "0")

  printf "[%s] Conn: %s | TPS: %s/s | Locks: %s | WAL: %sMB | Cache: %s%% | Audit: %s\n" \
    "$TIMESTAMP" "$CONNECTIONS" "$TPS" "$LOCKS" "$WAL" "$RATIO" "$AUDIT_COUNT"

  sleep $INTERVAL
done

echo ""
echo "=== Monitoring Complete ==="
