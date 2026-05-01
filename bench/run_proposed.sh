#!/usr/bin/env bash
# Benchmark Scenario 1 — PROPOSED (with audit trigger + JSONB + partitioned table)
# Usage: bash bench/run_proposed.sh
# Run from project root: /home/loinguyen/agrios/csdl/
# Run AFTER run_baseline.sh

set -euo pipefail

DB="postgresql://db_admin:db_admin_pass@localhost/audit_poc"
RESULTS_DIR="bench/results"
SCRIPT="bench/update_orders.sql"
RUNS=5
CLIENTS=50
DURATION=70

mkdir -p "$RESULTS_DIR"

echo "=== PROPOSED benchmark — audit trigger ENABLED ==="
psql "$DB" -c "
  ALTER TABLE orders ENABLE TRIGGER trg_audit_orders;
  ALTER TABLE products ENABLE TRIGGER trg_audit_products;
"

# Truncate current-month partition to avoid I/O skew from baseline run
CURRENT_PARTITION="audit_logs_$(date '+%Y_%m')"
psql "$DB" -c "TRUNCATE ${CURRENT_PARTITION};" > /dev/null
echo "Hot partition (${CURRENT_PARTITION}) cleared. Starting $RUNS runs ($CLIENTS clients, ${DURATION}s each)..."

for i in $(seq 1 $RUNS); do
  echo ""
  echo "--- Run $i / $RUNS ---"
  LOGFILE="${RESULTS_DIR}/proposed_run_${i}.log"
  PGPASSWORD=db_admin_pass pgbench \
    -h localhost -U db_admin -d audit_poc \
    -c "$CLIENTS" -T "$DURATION" \
    -f "$SCRIPT" \
    --no-vacuum \
    2>&1 | tee "$LOGFILE"

  psql "$DB" -c "VACUUM ANALYZE orders, audit_logs;" > /dev/null
  sleep 2
done

echo ""
echo "=== PROPOSED summary (TPS, excluding connections) ==="
grep "tps" "$RESULTS_DIR"/proposed_run_*.log | \
  grep "excluding" | \
  awk '{print $1, $4}' | \
  sed 's/bench\/results\/proposed_run_//; s/.log:/  run/'

echo ""
echo "Average TPS:"
grep "tps" "$RESULTS_DIR"/proposed_run_*.log | \
  grep "excluding" | \
  awk '{sum += $4; n++} END {printf "  %.2f TPS (avg over %d runs)\n", sum/n, n}'

echo ""
echo "=== Overhead vs Baseline ==="
BASELINE_AVG=$(grep "tps" "$RESULTS_DIR"/baseline_run_*.log 2>/dev/null | \
  grep "excluding" | awk '{sum+=$4;n++} END {print sum/n}')
PROPOSED_AVG=$(grep "tps" "$RESULTS_DIR"/proposed_run_*.log | \
  grep "excluding" | awk '{sum+=$4;n++} END {print sum/n}')

if [[ -n "$BASELINE_AVG" ]]; then
  awk -v b="$BASELINE_AVG" -v p="$PROPOSED_AVG" \
    'BEGIN {overhead=(b-p)/b*100; printf "  Baseline: %.2f TPS\n  Proposed: %.2f TPS\n  Overhead: %.1f%%\n", b, p, overhead}'
else
  echo "  Run run_baseline.sh first to compute overhead."
fi
