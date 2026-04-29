# Kết quả thực nghiệm — Audit Log PoC PostgreSQL

> Điền số liệu vào các bảng sau sau khi chạy benchmark. File này là nguồn dữ liệu cho §5.5 báo cáo.

## Môi trường

| Thông số | Giá trị |
|---|---|
| PostgreSQL | 16.10 |
| OS | Ubuntu 22.04 LTS (WSL2) |
| CPU | 4 vCPU |
| RAM | 8 GB |
| Storage | SSD (WSL2 virtual disk) |
| pgbench | 16.10 |
| Ngày đo | _điền ngày_ |

---

## Kịch bản 1 — Hiệu năng xử lý (Stress test)

**Cấu hình:** 50 connections đồng thời, 60 giây đo (+ 10s warm-up), UPDATE ngẫu nhiên bảng `orders`, lặp 5 lần.

### Baseline (không có audit trigger)

| Lần | TPS | Avg Latency (ms) |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| **Trung bình** | | |

### Proposed (có audit trigger → JSONB → partitioned table)

| Lần | TPS | Avg Latency (ms) |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| **Trung bình** | | |

### So sánh

| Chỉ số | Baseline | Proposed | Overhead |
|---|---|---|---|
| TPS (avg) | | | __%  (kỳ vọng < 15%)_ |
| Latency ms (avg) | | | |

---

## Kịch bản 2 — Lưu trữ & Retention

### 2a. Partition Pruning

```
EXPLAIN ANALYZE — kết quả dán vào đây
```

**Nhận xét:** Planner chỉ scan partition `audit_logs_YYYY_MM` khớp range → pruning hoạt động.

### 2b. DROP PARTITION vs DELETE truyền thống (1,000,000 rows)

| Phương pháp | Thời gian | Ghi chú |
|---|---|---|
| `DELETE FROM audit_logs_2025_10` | ___ ms | Full table scan + WAL logging |
| `DROP TABLE audit_logs_2025_10`  | ___ ms | Kỳ vọng < 1s, chỉ xóa file vật lý |

---

## Kịch bản 3 — An toàn & Bảo mật

| Case | Hành động | Kết quả | Pass/Fail |
|---|---|---|---|
| 1 | `app_user` UPDATE orders → audit ghi | _audit row tìm thấy_ | |
| 2 | `app_user` SELECT audit_logs | `ERROR: permission denied` | |
| 3 | `db_admin` DELETE audit_logs | `EXCEPTION + security_alerts` | |

---

## Kịch bản 4 — Hiệu năng truy vấn JSONB (có/không GIN)

**Query:** `SELECT count(*) FROM audit_logs WHERE new_data @> '{"status":"PAID"}'`

| Index | Planning time | Execution time | Scan type |
|---|---|---|---|
| Không có GIN | | | Seq Scan |
| Có GIN | | | Bitmap Index Scan |

**Cải thiện:** ___× (kỳ vọng ≥ 10×)

---

## Dung lượng tổng

| Bảng | Rows | Data size | Index size | Total |
|---|---|---|---|---|
| orders | 1,000,001 | 87 MB | 36 MB | |
| products | 100,000 | 18 MB | 8 MB | |
| audit_logs (7 partitions) | 7,500,010 | 3,064 MB | 2,189 MB | 5,253 MB |

---

## Kết luận

_Điền sau khi có đủ số liệu._
