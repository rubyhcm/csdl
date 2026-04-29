# Kế hoạch xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL

> Tài liệu này là **kế hoạch triển khai PoC** cho đề tài trong `6-baocao.md`, dựa trên hướng dẫn kỹ thuật `7-huongdan-xay-dung-source.md`. Mục tiêu: từ máy trắng → demo đầy đủ 4 kịch bản thực nghiệm với số liệu định lượng, sẵn sàng đưa vào báo cáo.

---

## 0. Mục tiêu & phạm vi

| Hạng mục | Đích đến |
|---|---|
| **Output kỹ thuật** | Bộ script SQL/PL-pgSQL chạy được, repo có cấu trúc rõ ràng |
| **Output nghiên cứu** | Số liệu TPS/latency/disk/query-time đủ để fill các bảng/biểu đồ trong Chương 5 |
| **Output bảo mật** | Demo bằng video/screenshot 3 cuộc tấn công bị chặn |
| **Phạm vi loại trừ** | Streaming real-time, multi-DB, throughput >10k TPS, HA/replication |

**Tiêu chí thành công tổng thể:**
- Overhead Proposed vs Baseline **< 15%** TPS.
- `DROP PARTITION` < **1s** (so với DELETE ~minutes).
- Truy vấn JSONB có GIN nhanh hơn không-GIN ≥ **10×**.
- 100% nỗ lực `UPDATE/DELETE` trên `audit_logs` của `db_admin` đều bị chặn và lưu vào `security_alerts`.

---

## 1. Cấu trúc thư mục đề xuất

```
csdl/
├── 6-baocao.md
├── 7-huongdan-xay-dung-source.md
├── 8-ke-hoach-xay-dung.md          ← file này
├── sql/
│   ├── 00_roles.sql                ← role + GRANT/REVOKE
│   ├── 01_schema_audit.sql         ← audit_logs, security_alerts, partitions
│   ├── 02_schema_business.sql      ← orders, products
│   ├── 03_seed_data.sql            ← generate_series cho 1M orders + 100k products
│   ├── 04_audit_function.sql       ← func_audit_trigger + triggers
│   ├── 05_security_immutability.sql← func_prevent_audit_change + trigger
│   ├── 06_hash_chain.sql           ← (tùy chọn) tamper-evident
│   ├── 07_indexes.sql              ← B-tree + GIN
│   └── 99_cleanup.sql              ← drop database / reset
├── bench/
│   ├── update_orders.sql           ← pgbench script
│   ├── run_baseline.sh             ← disable trigger + chạy 5 lần
│   ├── run_proposed.sh             ← enable trigger + chạy 5 lần
│   └── results/                    ← *.log, *.csv của từng lượt chạy
├── verify/
│   ├── q_jsonb_examples.sql        ← truy vấn báo cáo §5.4 KB4
│   ├── q_partition_pruning.sql     ← EXPLAIN ANALYZE chứng minh pruning
│   ├── q_security_demo.sql         ← 3 case attack
│   └── q_hash_verifier.sql         ← (tùy chọn) duyệt log + so hash
└── docs/
    └── results-summary.md          ← bảng số liệu cuối cùng để paste vào báo cáo
```

> Quy ước: mọi file `sql/*.sql` chạy bằng `psql -v ON_ERROR_STOP=1 -f <file>`; mọi shell script in TPS/latency vào `bench/results/<scenario>_<run_id>.log`.

---

## 2. Phase 0 — Setup môi trường (0.5 ngày)

### Tasks
- [ ] Cài PostgreSQL 16 trên Ubuntu Server 22.04 (WSL2). Kiểm tra `pg_lsclusters`.
- [ ] Bật `shared_preload_libraries` (nếu cần `pg_stat_statements` cho diagnostic), cấp `max_connections >= 100`.
- [ ] Tạo database `audit_poc` (`CREATE DATABASE audit_poc OWNER db_admin;`).
- [ ] `CREATE EXTENSION pgcrypto;` (chuẩn bị cho hash chain).
- [ ] Khởi tạo cấu trúc thư mục mục §1.
- [ ] Init `git` và commit baseline.

### Acceptance
- `psql -U db_admin -d audit_poc -c "SELECT version();"` chạy được.
- `pgbench --version` ≥ 16.

---

## 3. Phase 1 — Schema & Roles (0.5 ngày)

### Tasks
- [ ] Viết `sql/00_roles.sql`: `CREATE ROLE db_admin/app_user/auditor`, password placeholder.
- [ ] Viết `sql/01_schema_audit.sql`:
  - `audit_logs` partitioned by RANGE(`changed_at`), PK `(id, changed_at)`.
  - `security_alerts` (theo §5.2 hướng dẫn).
  - `func_create_monthly_partition(p_month DATE)` + bootstrap 6 partition lịch sử + tháng hiện tại + tháng kế.
- [ ] Viết `sql/02_schema_business.sql`: `orders`, `products`.
- [ ] Áp `GRANT/REVOKE` ở cuối `00_roles.sql` (sau khi schema đã tồn tại — hoặc tách thành `08_grants.sql`).

### Acceptance
- `\dt+ audit_logs*` thấy ≥ 8 partition con.
- `\du` xác nhận 3 role tồn tại.
- `app_user` `SELECT * FROM audit_logs` ⇒ **permission denied** (mong đợi).

---

## 4. Phase 2 — Generic Audit Function & Triggers (0.5 ngày)

### Tasks
- [ ] Viết `sql/04_audit_function.sql`:
  - `func_audit_trigger()` — `SECURITY DEFINER`, `SET search_path = public, pg_temp`, ghi `schema.table`.
  - Gắn trigger `AFTER INSERT OR UPDATE OR DELETE` cho `orders`, `products`.
- [ ] Smoke test:
  ```sql
  INSERT INTO orders(...) VALUES (...);
  UPDATE orders SET status='PAID' WHERE id=1;
  DELETE FROM orders WHERE id=1;
  SELECT operation, user_name, new_data->>'status' FROM audit_logs ORDER BY id DESC LIMIT 5;
  ```

### Acceptance
- 3 hàng audit (I/U/D) xuất hiện đúng bảng, đúng `current_user`.
- `to_jsonb(NEW)` chứa toàn bộ cột.

---

## 5. Phase 3 — Bảo mật & Immutability (0.5 ngày)

### Tasks
- [ ] Viết `sql/05_security_immutability.sql`:
  - `func_prevent_audit_change()` ghi vào `security_alerts` rồi `RAISE EXCEPTION`.
  - Trigger `BEFORE UPDATE OR DELETE` trên `audit_logs`.
- [ ] (Tùy chọn) Viết `sql/06_hash_chain.sql` theo §5.3 hướng dẫn.
- [ ] Viết `verify/q_security_demo.sql` chứa 3 case:
  1. `app_user` UPDATE `orders` ⇒ log ghi OK.
  2. `app_user` `SELECT * FROM audit_logs` ⇒ **denied**.
  3. `db_admin` `DELETE FROM audit_logs` ⇒ **exception** + 1 dòng `security_alerts`.

### Acceptance
- Cả 3 case in ra kết quả đúng kỳ vọng (script tự `\echo` PASS/FAIL).

---

## 6. Phase 4 — Sinh dữ liệu giả lập (1 ngày)

### Tasks
- [ ] Viết `sql/03_seed_data.sql`:
  - `orders`: 1.000.000 dòng, `created_at` rải đều 180 ngày qua.
  - `products`: 100.000 dòng, `tech_specs` 50/50 hai schema (laptop / áo).
- [ ] Sinh **dữ liệu lịch sử cho `audit_logs`**: ~10M dòng phân bổ vào 5 partition cold.
  - Dùng `INSERT INTO audit_logs ... SELECT ... FROM generate_series(1, 1500000)` per partition (chú ý: hash chain trigger nên **TẮT** khi seed lịch sử để tăng tốc).
- [ ] Đo dung lượng:
  ```sql
  SELECT pg_size_pretty(pg_total_relation_size('audit_logs'));
  SELECT relname, pg_size_pretty(pg_total_relation_size(oid))
  FROM pg_class WHERE relname LIKE 'audit_logs_%';
  ```

### Acceptance
- Tổng `audit_logs` ≈ 5–8GB (khớp dự kiến §5.2.2).
- Mỗi partition cold ≈ 1.5M dòng.

---

## 7. Phase 5 — Indexing (0.25 ngày)

### Tasks
- [ ] Viết `sql/07_indexes.sql` với 4 index theo §6 hướng dẫn (`changed_at`, `(table_name, changed_at)`, `(user_name, changed_at)`, `GIN(new_data)`).
- [ ] `VACUUM ANALYZE audit_logs, orders, products`.

### Acceptance
- `\di+ idx_audit_*` thấy đủ 4 index.
- `EXPLAIN` của truy vấn theo thời gian thấy `Append` chỉ trên 1–2 partition (partition pruning).

---

## 8. Phase 6 — Benchmark (1.5 ngày)

### Kịch bản 1 — TPS/latency (overhead audit)
- [ ] `bench/update_orders.sql`: UPDATE ngẫu nhiên 1 đơn hàng theo id.
- [ ] `bench/run_baseline.sh`:
  ```bash
  psql -c "ALTER TABLE orders DISABLE TRIGGER trg_audit_orders;
           ALTER TABLE products DISABLE TRIGGER trg_audit_products;"
  for i in 1 2 3 4 5; do
    pgbench -c 50 -T 70 -f bench/update_orders.sql audit_poc \
      | tee bench/results/baseline_run_${i}.log
    psql -c "VACUUM ANALYZE orders;"
  done
  ```
  > `-T 70` để có 10s warm-up + 60s đo (loại bỏ 10s đầu khi tổng hợp).
- [ ] `bench/run_proposed.sh`: bật lại trigger, lặp lại 5 lần, ghi log.
- [ ] Tổng hợp TPS/latency trung bình vào `docs/results-summary.md`.

### Kịch bản 2 — Storage & retention
- [ ] Đo thời gian:
  ```sql
  -- DELETE truyền thống
  EXPLAIN (ANALYZE, BUFFERS) DELETE FROM audit_logs WHERE changed_at < now() - interval '5 months';
  -- vs DROP PARTITION
  \timing on
  DROP TABLE audit_logs_2025_11;
  ```
- [ ] So sánh dung lượng trước/sau.

### Kịch bản 3 — Security (đã chạy ở Phase 3, ghi lại số liệu)
- [ ] Re-run `verify/q_security_demo.sql`, screenshot output cho báo cáo.

### Kịch bản 4 — Read performance (JSONB ± GIN)
- [ ] Truy vấn:
  ```sql
  EXPLAIN (ANALYZE, BUFFERS)
  SELECT count(*) FROM audit_logs
  WHERE table_name='public.orders' AND new_data->>'status'='PAID';
  ```
- [ ] Lần 1: drop GIN, đo. Lần 2: tạo lại GIN, đo. Ghi 2 con số.

### Acceptance
- File `docs/results-summary.md` có đủ 4 bảng kết quả với số liệu thực, không TODO.
- Overhead < 15%, DROP PARTITION < 1s, tăng tốc GIN ≥ 10×, security 3/3 PASS.

---

## 9. Phase 7 — Tổng hợp báo cáo (1 ngày)

### Tasks
- [ ] Paste số liệu vào `6-baocao.md` §5.5; vẽ biểu đồ (matplotlib hoặc Excel) cho TPS/latency.
- [ ] Cập nhật phần "Kết quả dự kiến" → "Kết quả đạt được" (Abstract + Mở đầu §5).
- [ ] Hoàn thiện Phụ lục A/B/C/D bằng cách reference các file `sql/*.sql`, `bench/*.sh`.
- [ ] Viết Kết luận chương + tài liệu tham khảo (PostgreSQL docs, pgAudit, Debezium, paper hash chain).

### Acceptance
- Không còn block `[Nội dung cần viết]` nào trong báo cáo.
- Mỗi chỉ số trong §5.5 link được tới file log/CSV gốc.

---

## 10. Roadmap tổng (gantt rút gọn)

```
Tuần 1 ────────────────────────────────────────────
  Day 1   P0 Setup + P1 Schema/Roles
  Day 2   P2 Audit fn + P3 Security
  Day 3-4 P4 Seed dữ liệu (10M log có thể chạy qua đêm)
  Day 5   P5 Index + chuẩn bị benchmark scripts

Tuần 2 ────────────────────────────────────────────
  Day 6-7 P6 Chạy 4 kịch bản, lặp 5 lần, lưu log
  Day 8   P6 phân tích số liệu, vẽ biểu đồ
  Day 9   P7 viết báo cáo, hoàn thiện phụ lục
  Day 10  Review + dự phòng
```

Tổng: ~10 ngày làm việc cho 1 người, có thể nén còn 6–7 ngày nếu seed dữ liệu chạy nền song song với code.

---

## 11. Rủi ro & phương án giảm thiểu

| # | Rủi ro | Tác động | Phương án |
|---|---|---|---|
| R1 | WSL2 disk I/O thấp ⇒ TPS không đại diện production | Số liệu khó so sánh | Ghi rõ trong §5.6 "Giới hạn", đo trên cùng máy cho cả Baseline & Proposed để chênh lệch tương đối vẫn có nghĩa |
| R2 | Seed 10M log chậm hàng giờ | Trễ tiến độ | Tắt mọi trigger trên `audit_logs` khi seed; dùng `COPY` hoặc multi-row INSERT batch 10k |
| R3 | Hash chain quá chậm khi bench | Misleading overhead | Tách 2 lần đo: (a) audit thuần, (b) audit + hash chain — báo cáo cả hai |
| R4 | Quên tạo partition tháng kế ⇒ INSERT lỗi | Mất giao dịch khi chạy demo qua tháng | `func_create_monthly_partition` được gọi định kỳ; khi PoC ngắn, bootstrap sẵn 12 partition tới trước |
| R5 | `pgbench` không đo được latency ổn định với 50 connections trên 4 vCPU | Phương sai cao | Tăng số lần lặp ≥ 5, loại 1 lượt min/max trước khi lấy trung bình |
| R6 | `SECURITY DEFINER` để mặc định `search_path` ⇒ hijack | Lỗ hổng nghiên cứu | Đã hard-code `SET search_path = public, pg_temp` trong cả 2 function |

---

## 12. Definition of Done

PoC hoàn thành khi tất cả checkbox dưới đây đều xong:

- [ ] Toàn bộ file `sql/*.sql` chạy idempotent từ database trắng tới state demo (smoke test bằng `99_cleanup.sql` + replay).
- [ ] `bench/results/` chứa ≥ 10 file log (5 baseline + 5 proposed) cộng kết quả 3 kịch bản còn lại.
- [ ] `docs/results-summary.md` đầy đủ 4 bảng số liệu, đạt tiêu chí §0.
- [ ] `6-baocao.md` không còn placeholder; biểu đồ TPS/latency đính kèm.
- [ ] Repo Git có ≥ 1 commit/phase, README ngắn hướng dẫn chạy lại.
- [ ] Demo bảo mật (3 case) record được dưới dạng screenshot/log để đính kèm phụ lục.
