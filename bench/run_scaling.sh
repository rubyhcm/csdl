#!/usr/bin/env bash
# Scaling benchmark — Kịch bản 1 đo overhead ở 3 mức concurrency: 10, 50, 100 clients
# Mục đích: xây dựng scaling curve để trả lời "overhead có ổn định khi tải thay đổi không?"
# Usage: bash bench/run_scaling.sh   (chạy từ project root)

set -euo pipefail

DB="postgresql://db_admin:db_admin_pass@localhost/audit_poc"
RESULTS_DIR="bench/results/scaling"
SCRIPT="bench/update_orders.sql"
RUNS=3
DURATION=70          # 10s warm-up + 60s đo
LEVELS=(10 50 80)
HOT_PARTITION="audit_logs_$(date '+%Y_%m')"

mkdir -p "$RESULTS_DIR"

disable_trigger() {
  psql "$DB" -q -c "ALTER TABLE orders DISABLE TRIGGER trg_audit_orders;" 2>/dev/null
}

enable_trigger() {
  psql "$DB" -q -c "ALTER TABLE orders ENABLE TRIGGER trg_audit_orders;" 2>/dev/null
}

run_level() {
  local mode="$1"    # baseline | proposed
  local clients="$2"

  echo ""
  echo ">>> ${mode^^}  |  ${clients} clients  |  ${RUNS} runs × ${DURATION}s"

  if [[ "$mode" == "baseline" ]]; then
    disable_trigger
  else
    enable_trigger
    # Xóa hot partition trước mỗi proposed-level để không bị skew từ lần trước
    psql "$DB" -q -c "TRUNCATE ${HOT_PARTITION};" 2>/dev/null
    echo "    Hot partition (${HOT_PARTITION}) cleared."
  fi

  for i in $(seq 1 "$RUNS"); do
    LOGFILE="${RESULTS_DIR}/${mode}_c${clients}_run${i}.log"
    printf "    run %d/%d ... " "$i" "$RUNS"
    PGPASSWORD=db_admin_pass pgbench \
      -h localhost -U db_admin -d audit_poc \
      -c "$clients" -T "$DURATION" \
      -f "$SCRIPT" \
      --no-vacuum \
      > "$LOGFILE" 2>&1
    TPS=$(grep "^tps" "$LOGFILE" | awk '{printf "%.2f", $3}')
    LAT=$(grep "latency average" "$LOGFILE" | awk '{printf "%.1f", $4}')
    echo "TPS=${TPS}  lat=${LAT}ms"
    psql "$DB" -q -c "VACUUM ANALYZE orders;" 2>/dev/null
    sleep 2
  done
}

# ── Chạy toàn bộ ──────────────────────────────────────────────────
echo "========================================"
echo "  SCALING BENCHMARK  —  $(date '+%Y-%m-%d %H:%M')"
echo "  Concurrency levels: ${LEVELS[*]} clients"
echo "  Runs per level: $RUNS × ${DURATION}s"
echo "========================================"

for c in "${LEVELS[@]}"; do
  run_level "baseline" "$c"
done

enable_trigger   # đảm bảo trigger bật cho proposed

for c in "${LEVELS[@]}"; do
  run_level "proposed" "$c"
done

enable_trigger   # luôn bật lại trigger khi xong

# ── Tổng hợp kết quả ─────────────────────────────────────────────
echo ""
echo "========================================"
echo "  SCALING SUMMARY"
echo "========================================"
printf "%-8s | %-14s | %-14s | %-10s | %-12s\n" \
  "Clients" "Baseline TPS" "Proposed TPS" "Overhead" "Latency B/P"

for c in "${LEVELS[@]}"; do
  B_AVG=$(grep "^tps" "${RESULTS_DIR}/baseline_c${c}_run"*.log \
    | awk '{sum+=$3;n++} END {printf "%.2f", sum/n}')
  P_AVG=$(grep "^tps" "${RESULTS_DIR}/proposed_c${c}_run"*.log \
    | awk '{sum+=$3;n++} END {printf "%.2f", sum/n}')
  B_LAT=$(grep "latency average" "${RESULTS_DIR}/baseline_c${c}_run"*.log \
    | awk '{sum+=$4;n++} END {printf "%.1f", sum/n}')
  P_LAT=$(grep "latency average" "${RESULTS_DIR}/proposed_c${c}_run"*.log \
    | awk '{sum+=$4;n++} END {printf "%.1f", sum/n}')
  OV=$(awk -v b="$B_AVG" -v p="$P_AVG" \
    'BEGIN {printf "%.1f%%", (b-p)/b*100}')
  printf "%-8s | %-14s | %-14s | %-10s | %s / %s ms\n" \
    "${c}c" "$B_AVG" "$P_AVG" "$OV" "$B_LAT" "$P_LAT"
done

echo ""
echo "Raw logs: ${RESULTS_DIR}/"
echo "Done: $(date '+%Y-%m-%d %H:%M')"
