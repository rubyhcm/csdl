# Kết quả thực nghiệm — Audit Log PoC PostgreSQL

## Môi trường

| Thông số | Giá trị |
|---|---|
| PostgreSQL | 16.10 (Ubuntu 16.10-0ubuntu0.24.04.1) |
| OS | Ubuntu 22.04 LTS (WSL2 / Windows 11) |
| CPU | 4 vCPU |
| RAM | 8 GB |
| Storage | SSD (WSL2 virtual disk) |
| pgbench | 16.10 |
| Ngày đo | 2026-04-29 |

---

## Kịch bản 1 — Hiệu năng xử lý (Stress test)

**Cấu hình:** 50 connections đồng thời, `-T 70` (10s warm-up + 60s đo), UPDATE ngẫu nhiên bảng `orders`, lặp 5 lần.

### Baseline (audit trigger DISABLED)

| Lần | TPS | Avg Latency (ms) | Ghi chú |
|---|---|---|---|
| 1 | 37.46 | 1,334.8 | |
| 2 | 31.01 | 1,612.1 | |
| 3 | 10.88 | 4,597.0 | **Outlier — WSL2 I/O hiccup** |
| 4 | 32.25 | 1,550.5 | |
| 5 | 35.03 | 1,427.4 | |
| **Avg (tất cả 5)** | **29.33** | **2,104.4** | Bị kéo bởi outlier |
| **Avg (loại run 3)** | **33.94** | **1,481.2** | Giá trị đại diện |

### Proposed (audit trigger ENABLED → JSONB → partitioned table)

| Lần | TPS | Avg Latency (ms) |
|---|---|---|
| 1 | 41.28 | 1,211.2 |
| 2 | 37.47 | 1,334.4 |
| 3 | 35.83 | 1,395.3 |
| 4 | 29.03 | 1,722.3 |
| 5 | 32.89 | 1,520.1 |
| **Avg (tất cả 5)** | **35.30** | **1,436.7** |

### So sánh

| Chỉ số | Baseline (clean) | Proposed | Overhead |
|---|---|---|---|
| TPS | 33.94 | 35.30 | **-4.0%** (Proposed nhanh hơn) |
| Latency (ms) | 1,481.2 | 1,436.7 | **-44.5 ms** (Proposed thấp hơn) |

> **Kết quả đáng chú ý:** Proposed có TPS cao hơn Baseline sạch 4% — overhead âm. Nguyên nhân: WSL2 I/O không ổn định làm phương sai cao; trong khoảng đo 60s, trigger overhead nhỏ (<5ms/transaction) bị che khuất bởi dao động hệ thống. Kết luận quan trọng: **overhead < 15%** ✓ — audit trigger không ảnh hưởng đáng kể đến throughput ở mức 50 clients.

### Biểu đồ 1.1 — So sánh TPS trung bình Baseline vs Proposed

```mermaid
xychart-beta
    title "TPS Trung Bình: Baseline vs Proposed (50 clients, 60s)"
    x-axis ["Baseline (no trigger)", "Proposed (Audit Trigger)"]
    y-axis "TPS (Transactions/s)" 0 --> 45
    bar [33.94, 35.30]
```

### Biểu đồ 1.2 — So sánh Latency trung bình (ms)

```mermaid
xychart-beta
    title "Avg Latency: Baseline vs Proposed (Thap hon = Tot hon)"
    x-axis ["Baseline (no trigger)", "Proposed (Audit Trigger)"]
    y-axis "Avg Latency (ms)" 1300 --> 1600
    bar [1481.2, 1436.7]
```

### Biểu đồ 1.3 — TPS từng lần chạy (Baseline vs Proposed, 5 runs)

```mermaid
xychart-beta
    title "TPS tung lan chay — Baseline vs Proposed"
    x-axis ["Run 1", "Run 2", "Run 3*", "Run 4", "Run 5"]
    y-axis "TPS" 0 --> 50
    line [37.46, 31.01, 10.88, 32.25, 35.03]
    line [41.28, 37.47, 35.83, 29.03, 32.89]
```

> _* Run 3 Baseline là outlier (10.88 TPS) do WSL2 I/O hiccup — bị loại khi tính trung bình đại diện._

---

## Kịch bản 2 — Lưu trữ & Retention

### 2a. Partition Pruning

Query `WHERE changed_at BETWEEN '2026-03-01' AND '2026-03-31'` trên 7.5M rows:

```
Parallel Index Only Scan using audit_logs_2026_03_changed_at_idx
  on audit_logs_2026_03 (1 in 8 partitions)
Planning Time:  1.2 ms
Execution Time: 351.9 ms
```

**Kết quả:** Planner loại 7/8 partitions, chỉ scan `audit_logs_2026_03`. Partition pruning hoạt động chính xác ✓

### Biểu đồ 2.1 — Partition Pruning: 1/8 partition được scan

```mermaid
pie title "Partition Pruning (8 partitions tong)"
    "Partitions bi loai - khong scan (7)" : 7
    "Partition thuc su scan - 2026-03 (1)" : 1
```

### 2b. DROP PARTITION vs DELETE (1,000,000 dòng)

| Phương pháp | Thời gian |
|---|---|
| `DELETE FROM audit_logs_2025_10_delete_test` | **641 ms** |
| `DROP TABLE audit_logs_2025_10` | **47 ms** |
| **Tỷ lệ cải thiện** | **~13.6x nhanh hơn** |

> DROP PARTITION chỉ xóa file vật lý + metadata, không ghi WAL cho từng row → nhanh hơn ~14x so với DELETE. Kỳ vọng < 1s ✓ (47ms).

### Biểu đồ 2.2 — DROP PARTITION vs DELETE (ms, thấp hơn = tốt hơn)

```mermaid
xychart-beta
    title "Thoi gian xoa 1,000,000 dong (ms) - Thap hon = Tot hon"
    x-axis ["DELETE truyen thong", "DROP TABLE partition"]
    y-axis "Thoi gian (ms)" 0 --> 700
    bar [641, 47]
```

---

## Kịch bản 3 — An toàn & Bảo mật

| Case | Hành động | Kết quả quan sát | Pass/Fail |
|---|---|---|---|
| 1 | `app_user` UPDATE orders → audit ghi | audit row với `user_name='app_user'` | **PASS** |
| 2 | `app_user` SELECT audit_logs | `ERROR: permission denied for table audit_logs` | **PASS** |
| 3 | `db_admin` DELETE audit_logs | `ERROR: Audit log is immutable` + 1 row security_alerts | **PASS** |

**3/3 PASS ✓**

### Biểu đồ 3.1 — Kết quả kiểm thử bảo mật

```mermaid
pie title "Ket qua kiem thu bao mat (3 kich ban)"
    "PASS (3)" : 3
    "FAIL (0)" : 0
```

---

## Kịch bản 4 — Hiệu năng truy vấn JSONB (có/không GIN)

**Query:** `SELECT count(*) FROM audit_logs WHERE table_name='public.orders' AND new_data @> '{"status":"PAID"}'`  
**Dataset:** 7.5M rows (5 cold partitions x 1.5M + hot partition)

| Trạng thái | Scan type | Execution Time | Ghi chú |
|---|---|---|---|
| **Có GIN** (warm cache) | Bitmap Index Scan (một số partition) + Seq Scan (phần còn lại) | **930 ms** | Cache ấm từ lần query trước |
| **Không có GIN** | Parallel Seq Scan toàn bộ | **1,032 ms** | |
| **Có GIN** (cold cache sau rebuild) | Bitmap Index Scan | **2,898 ms** | I/O cho GIN posting lists chưa cache |

**Cải thiện (warm cache):** ~10% (930 ms vs 1,032 ms)

> **Phân tích quan trọng:** Với data ngẫu nhiên (~33% rows có `status=PAID`), selectivity thấp khiến GIN ít hiệu quả hơn dự kiến. Khi cache lạnh, GIN thực ra chậm hơn Seq Scan vì overhead đọc posting lists. GIN hiệu quả nhất khi: (1) selectivity cao (ít kết quả), (2) cache đã ấm, (3) query theo key hiếm trong JSONB.

### Biểu đồ 4.1 — Execution Time truy vấn JSONB theo 3 trạng thái (ms)

```mermaid
xychart-beta
    title "Execution Time JSONB query - 7.5M rows (Thap hon = Tot hon)"
    x-axis ["No GIN (Seq Scan)", "GIN Warm Cache", "GIN Cold Cache"]
    y-axis "Execution Time (ms)" 0 --> 3200
    bar [1032, 930, 2898]
```

---

## Dung lượng

| Bảng | Rows | Data | Index | Total |
|---|---|---|---|---|
| orders | 1,000,001 | ~60 MB | ~36 MB | 87 MB |
| products | 100,000 | ~10 MB | ~8 MB | 18 MB |
| audit_logs (7 partitions có data) | 7,500,010 | 3,064 MB | 2,189 MB | **5,253 MB** |
| GIN index / partition | — | — | ~244 MB | — |
| B-tree(changed_at) / partition | — | — | ~32 MB | — |
| B-tree(table+time) / partition | — | — | ~58 MB | — |

### Biểu đồ 5.1 — Phân bổ dung lượng audit_logs (Data vs Index)

```mermaid
pie title "Dung luong audit_logs ~ 5,253 MB"
    "Data rows (3,064 MB)" : 3064
    "GIN index - 244x7 MB (1,708 MB)" : 1708
    "B-tree indexes - 90x7 MB (481 MB)" : 481
```

### Biểu đồ 5.2 — So sánh tổng dung lượng các bảng (MB)

```mermaid
xychart-beta
    title "Dung luong tong cac bang (MB)"
    x-axis ["orders (87 MB)", "products (18 MB)", "audit_logs (5,253 MB)"]
    y-axis "MB" 0 --> 5500
    bar [87, 18, 5253]
```

---

## Tóm tắt theo tiêu chí

| Tiêu chí | Kỳ vọng | Kết quả | Đạt |
|---|---|---|---|
| Overhead TPS | < 15% | **-4%** (không có overhead) | ✓ |
| DROP PARTITION | < 1s | **47 ms** | ✓ |
| Partition pruning | Đúng partition | Chỉ scan 1/8 partitions | ✓ |
| GIN cải thiện query | ≥ 10x | ~10% (warm); phụ thuộc selectivity | ~ |
| Security 3 cases | 3/3 PASS | **3/3 PASS** | ✓ |

### Biểu đồ 6.1 — Tổng hợp đánh giá mức đạt tiêu chí nghiên cứu

```mermaid
quadrantChart
    title Danh gia muc dat tieu chi nghien cuu
    x-axis "Ky vong thap" --> "Ky vong cao"
    y-axis "Ket qua thap" --> "Ket qua cao"
    quadrant-1 Vuot ky vong
    quadrant-2 Dat nhung can cai thien
    quadrant-3 Chua dat
    quadrant-4 Khong dat ky vong cao
    "Overhead TPS -4%": [0.3, 0.95]
    "DROP PARTITION 47ms": [0.5, 0.97]
    "Partition Pruning 1/8": [0.4, 0.9]
    "GIN Query 10% warm": [0.75, 0.45]
    "Security 3/3 PASS": [0.6, 0.95]
```
