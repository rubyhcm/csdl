#!/usr/bin/env bash
# Benchmark Scenario 1 — BASELINE (no audit trigger)
# Usage: bash bench/run_baseline.sh
# Run from project root: /home/loinguyen/agrios/csdl/

set -euo pipefail

DB="postgresql://db_admin:db_admin_pass@localhost/audit_poc"
RESULTS_DIR="bench/results"
SCRIPT="bench/update_orders.sql"
RUNS=5
CLIENTS=50
DURATION=70   # 70s = 10s warm-up + 60s measured

mkdir -p "$RESULTS_DIR"

echo "=== BASELINE benchmark — disabling audit trigger ==="
psql "$DB" -c "
  ALTER TABLE orders DISABLE TRIGGER trg_audit_orders;
  ALTER TABLE products DISABLE TRIGGER trg_audit_products;
"

echo "Trigger disabled. Starting $RUNS runs ($CLIENTS clients, ${DURATION}s each)..."

for i in $(seq 1 $RUNS); do
  echo ""
  echo "--- Run $i / $RUNS ---"
  LOGFILE="${RESULTS_DIR}/baseline_run_${i}.log"
  PGPASSWORD=db_admin_pass pgbench \
    -h localhost -U db_admin -d audit_poc \
    -c "$CLIENTS" -T "$DURATION" \
    -f "$SCRIPT" \
    --no-vacuum \
    2>&1 | tee "$LOGFILE"

  # Cool-down between runs
  psql "$DB" -c "VACUUM ANALYZE orders;" > /dev/null
  sleep 2
done

echo ""
echo "=== Re-enabling audit trigger ==="
psql "$DB" -c "
  ALTER TABLE orders ENABLE TRIGGER trg_audit_orders;
  ALTER TABLE products ENABLE TRIGGER trg_audit_products;
"

echo ""
echo "=== BASELINE summary (TPS, excluding connections) ==="
grep "tps" "$RESULTS_DIR"/baseline_run_*.log | \
  grep "excluding" | \
  awk '{print $1, $4}' | \
  sed 's/bench\/results\/baseline_run_//; s/.log:/  run/'

echo ""
echo "Average TPS:"
grep "tps" "$RESULTS_DIR"/baseline_run_*.log | \
  grep "excluding" | \
  awk '{sum += $4; n++} END {printf "  %.2f TPS (avg over %d runs)\n", sum/n, n}'
