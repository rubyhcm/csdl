# Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

> **Ghi chú**: Tài liệu này là **khung sườn báo cáo nghiên cứu khoa học**. Khi hoàn thiện, hãy thay các khối `[Nội dung cần viết]`, bổ sung hình/bảng, trích dẫn và số liệu thực nghiệm.

## Tóm tắt (Abstract)
- **Bối cảnh**: [Audit trail trong hệ thống quy mô lớn (tài chính/ngân hàng) với 3 thách thức: Big Data, Latency, Integrity/Security.]
- **Mục tiêu**: [Tối ưu kiến trúc PostgreSQL để ghi log tự động, lưu trữ linh hoạt, truy xuất nhanh và chống can thiệp.]
- **Phương pháp**: Trigger + JSONB (+ GIN) + Declarative Partitioning + lớp bảo mật (append-only/WORM, tamper-evident).
- **Thực nghiệm**: [Môi trường, dataset, pgbench, kịch bản đo TPS/latency; truy vấn JSONB; kiểm thử bảo mật.]
- **Kết quả chính (dự kiến/đạt được)**: [Overhead, tốc độ truy vấn có/không GIN, thời gian drop partition, minh chứng chặn xóa/sửa log.]
- **Từ khóa**: PostgreSQL; Audit Log; JSONB; GIN Index; Partitioning; Immutability; WORM.

---

## MỞ ĐẦU
### 1. Đặt vấn đề và tính cấp thiết
[Nêu nhu cầu biết “ai sửa gì/khi nào/giá trị cũ-mới”, tính tuân thủ, rủi ro khi thiếu audit log. Nhấn mạnh bài toán write-heavy và 3 thách thức: lưu trữ, độ trễ, an toàn.]

### 2. Mục tiêu nghiên cứu
- **Mục tiêu tổng quát**: [Tối ưu kiến trúc audit log trên PostgreSQL để ghi log tự động, lưu trữ linh hoạt, truy xuất nhanh và chống can thiệp].
- **Mục tiêu cụ thể**:
  - (1) **Lưu trữ** linh hoạt đa cấu trúc bằng JSONB và truy vấn có cấu trúc.
  - (2) **Xử lý/Hiệu năng**: đảm bảo overhead thấp, không làm chậm giao dịch nghiệp vụ.
  - (3) **An toàn-bảo mật**: đảm bảo bất biến và chống giả mạo (immutability, tamper-evident).

### 3. Nội dung thực hiện (theo 3 trụ cột)
#### 3.1. Lưu trữ
- Sử dụng **JSONB** để lưu trạng thái trước/sau thay đổi (**OLD/NEW**) theo hướng schema-less.
- Áp dụng **Declarative Partitioning** theo thời gian để quản lý bảng log kích thước lớn và hỗ trợ lưu trữ phân cấp (tablespace).

#### 3.2. Xử lý
- Xây dựng **Dynamic Triggers** và **Generic Functions** (PL/pgSQL) để tự động audit `INSERT`/`UPDATE`/`DELETE` mà không sửa mã nguồn ứng dụng.
- Tối ưu thuật toán ghi log để **overhead thấp**, hạn chế blocking I/O.

#### 3.3. An toàn - bảo mật
- Triển khai **SECURITY DEFINER** để user nghiệp vụ kích hoạt ghi log nhưng không truy cập trực tiếp bảng log.
- Xây dựng **Immutability (Append-only/WORM)**: trigger chặn `DELETE`/`UPDATE` trên bảng log.

### 4. Câu hỏi nghiên cứu / giả thuyết (tùy chọn)
- RQ1: [Trigger + JSONB + Partitioning có giữ overhead dưới ngưỡng chấp nhận được không?]
- RQ2: [GIN Index cải thiện truy vấn JSONB đến mức nào?]
- RQ3: [Append-only + hash chain có ngăn chặn/chứng minh can thiệp log không?]

### 5. Kết quả dự kiến
- Mô hình CSDL hoàn chỉnh với **Partitioning** và **JSONB Indexing**.
- Bộ script PL/pgSQL tự động hóa audit cho các bảng nghiệp vụ.
- Báo cáo thực nghiệm so sánh hiệu năng (**TPS**) giữa việc có và không có audit log.
- Kịch bản demo tấn công giả lập: chứng minh hệ thống ngăn chặn nỗ lực xóa log của tài khoản quyền cao.

### 6. Đối tượng và phạm vi nghiên cứu
- Đối tượng: PostgreSQL 16; trigger/PL/pgSQL; JSONB; partitioning; cơ chế phân quyền.
- Phạm vi: [mô hình PoC], tập trung audit DML; không bao gồm streaming real-time ở throughput cực cao.

### 7. Đóng góp của đề tài
- (C1) Mô hình audit log schema-less bằng JSONB + GIN.
- (C2) Bộ generic trigger/function hỗ trợ audit đa bảng.
- (C3) Thiết kế partitioning theo thời gian + retention/archiving.
- (C4) Thiết kế bảo mật: security definer, append-only/WORM, tamper-evident.
- (C5) Bộ kịch bản benchmark/đánh giá định lượng.

### 8. Bố cục báo cáo
[Tóm tắt cấu trúc chương như dưới.]

---

## CHƯƠNG 1. TỔNG QUAN VÀ CƠ SỞ LÝ THUYẾT
### 1.1. Khái niệm Audit Trail/Audit Log và yêu cầu hệ thống
- Thuộc tính cần đảm bảo: đầy đủ (completeness), toàn vẹn (integrity), không chối bỏ (non-repudiation), truy vết (traceability).
- Đặc trưng hệ thống: write-heavy; tăng trưởng dữ liệu theo thời gian.
- Ba thách thức: **Storage**, **Processing/Latency**, **Security**.

### 1.2. Tổng quan các giải pháp hiện nay
- (1) Logical Decoding/WAL-based
- (2) Extension (ví dụ: pgAudit)
- (3) CDC/Streaming (ví dụ: Debezium)

### 1.3. So sánh giải pháp và lựa chọn hướng tiếp cận
- Bảng so sánh theo tiêu chí: Structured Query, Real-time, Application Context, Độ phức tạp, Chi phí vận hành.
- Lý do chọn: **Trigger + JSONB + Partitioning** (truy vấn có cấu trúc, có application context, độ phức tạp vừa phải).

### 1.4. Giới hạn áp dụng
- Không phù hợp: yêu cầu real-time streaming; throughput cực cao (>10k TPS); microservices đa database.

### 1.5. Tại sao chọn PostgreSQL cho đề tài?
- **JSONB**: hỗ trợ lưu bán cấu trúc và truy vấn/đánh chỉ mục hiệu quả (GIN), phù hợp schema-less logging.
- **Native Partitioning**: quản trị vật lý rõ ràng, hỗ trợ partition pruning và tách tablespace cho tối ưu chi phí.
- **Security Definer**: cơ chế ủy quyền trong function linh hoạt, giải quyết bài toán phân quyền khi trigger ghi log.

---

## CHƯƠNG 2. PHƯƠNG PHÁP ĐỀ XUẤT VÀ THIẾT KẾ HỆ THỐNG
### 2.1. Kiến trúc tổng quan
[Mô tả luồng: app_user DML → AFTER ROW trigger → generic audit function → ghi vào audit_logs (partitioned) → security layer/alerting.]

### 2.2. Thiết kế mô hình dữ liệu audit (Schema Design)
- Mục tiêu: ghi vết đầy đủ nhưng tối ưu cho hệ thống **write-heavy**.
- Bảng `audit_logs` (gợi ý cột):
  - `id`, `occurred_at` (hoặc `changed_at`), `table_name`, `operation` (I/U/D)
  - `actor`/`user_name`, `txid`
  - `old_data` (JSONB), `new_data` (JSONB) — snapshot trước/sau thay đổi
  - `metadata` (JSONB) — ip, app_name, request_id/correlation_id, v.v.
  - `hash`, `prev_hash` (nếu dùng chuỗi băm chống giả mạo)
- **Lưu ý quan trọng khi dùng Partitioning** (theo hướng dẫn trong `docs.md`):
  - **Partition key phải nằm trong Primary Key** của bảng cha (ví dụ: `(id, occurred_at)`), nếu không sẽ gặp ràng buộc/thiết kế không hợp lệ.

Ví dụ DDL tối giản (minh họa):

```sql
CREATE TABLE audit_logs (
    id BIGSERIAL,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    user_name TEXT,
    old_data JSONB,
    new_data JSONB,
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
```

- Nguyên tắc:
  - **Schema-less logging**: 1 bảng audit phục vụ nhiều bảng nghiệp vụ.
  - **Append-only/WORM**: không cho UPDATE/DELETE log.
  - Tối ưu truy vấn theo **thời gian** và theo `table_name`/`actor`.

### 2.3. Thiết kế lưu trữ JSONB và lập chỉ mục
- JSONB là dạng JSON nhị phân đã parse, thuận lợi cho truy vấn có cấu trúc.
- Quy ước ghi dữ liệu:
  - `old_data = to_jsonb(OLD)`
  - `new_data = to_jsonb(NEW)`
- Index (gợi ý):
  - GIN index cho `new_data`/`old_data` để tìm kiếm theo key/value bên trong JSON.
  - B-tree index cho (`occurred_at`), (`table_name`, `occurred_at`), (`actor`, `occurred_at`).

### 2.4. Thiết kế Partitioning theo thời gian
- Declarative partitioning: `PARTITION BY RANGE (occurred_at)` theo tháng.
- Quy ước đặt tên partition (gợi ý): `audit_logs_YYYY_MM`.
- Lợi ích:
  - **Partition pruning**: planner tự loại bỏ partition không liên quan khi truy vấn theo thời gian.
  - Quản trị/retention đơn giản: drop partition thay vì delete từng dòng.
- Chiến lược tablespace:
  - Partition “nóng” (hiện tại) trên SSD/NVMe.
  - Partition “nguội” trên HDD/SATA để tối ưu chi phí.

### 2.5. Phân tích đánh đổi (Trade-offs)
- JSONB: linh hoạt ↔ tốn storage/độ phức tạp truy vấn.
- Trigger: không sửa code app ↔ tăng latency/khó debug.
- Partitioning: quản lý vòng đời tốt ↔ cross-partition query có thể chậm.

---

## CHƯƠNG 3. TRIỂN KHAI CƠ CHẾ GHI LOG VÀ QUẢN LÝ VÒNG ĐỜI
### 3.1. Xây dựng generic audit trigger function (PL/pgSQL)
- Xây dựng hàm tổng quát (gợi ý tên): `func_audit_trigger()`.
- Xử lý `INSERT`/`UPDATE`/`DELETE`, chuẩn hóa metadata (thời gian, actor, table_name, txid).
- Trigger cấu hình `FOR EACH ROW` để bắt chính xác thay đổi theo từng dòng.
- Chuyển đổi snapshot:
  - `to_jsonb(OLD)` và `to_jsonb(NEW)`.

### 3.2. Tự động hóa triển khai audit cho nhiều bảng (Dynamic Triggers)
- Tiêu chí chọn bảng nghiệp vụ cần audit.
- Script tạo trigger hàng loạt; cơ chế bật/tắt theo schema/bảng.

### 3.3. Tối ưu đường ghi (write path)
- Giảm overhead: hạn chế thao tác nặng trong trigger; tránh lock không cần thiết.
- Chiến lược batch/async (nếu có) và lý do chọn/không chọn.

### 3.4. Quản lý vòng đời dữ liệu (Data Lifecycle)
- Retention: 6 tháng.
- Drop partition vs delete truyền thống.
- Archive ra S3/HDD (mô tả quy trình, tiêu chí kiểm soát).

#### 3.4.1. Backup/Restore theo partition (Import/Export)
- Với cấu trúc partition, có thể **backup từng phần** (partial backup) các partition cũ để phục vụ thanh tra/kiểm toán.
- Gợi ý công cụ: `pg_dump` backup riêng một partition (ví dụ `audit_logs_2026_01`) ra file, sau đó `DROP TABLE` partition để giải phóng dung lượng.
- Khi cần truy xuất lại: restore từ file dump vào môi trường điều tra/đối soát.

### 3.5. Cơ chế truy vấn/trích xuất log phục vụ nghiệp vụ và kiểm toán
- Query mẫu theo `table_name`/`actor`/time range.
- Query sâu vào JSONB (ví dụ trường lương thay đổi):

```sql
SELECT *
FROM audit_logs
WHERE table_name = 'nhan_vien'
  AND (new_data->>'luong')::int > 50000000;
```

- (Tùy chọn) Stored procedure/function trả về report theo yêu cầu kiểm toán.

---

## CHƯƠNG 4. AN TOÀN, BẢO MẬT VÀ CHỐNG CAN THIỆP LOG
### 4.1. Phân quyền và mô hình SECURITY DEFINER
- Vai trò: `app_user`, `auditor`, `db_admin`.
- Nguyên tắc: `app_user` ghi được log thông qua trigger nhưng không SELECT trực tiếp bảng log.

### 4.2. Immutability (Append-only/WORM) cho bảng audit
- Mục tiêu: bảo vệ log theo hướng **Write-Once-Read-Many (WORM)**.
- Trigger `BEFORE UPDATE OR DELETE` trên `audit_logs` → `RAISE EXCEPTION`.
- Phân tích các trường hợp ngoại lệ (bảo trì/khôi phục) và kiểm soát.

### 4.3. Tamper-evident logging (chuỗi băm)
- Công thức: `hash_n = hash(log_n + hash_{n-1})`.
- Cách lưu `prev_hash`/`hash`; quy trình kiểm tra tính toàn vẹn.

### 4.4. Cảnh báo và giám sát (Alerting/Monitoring)
- Bảng `security_alerts` hoặc integration SIEM.
- Sự kiện cảnh báo: cố xóa/sửa audit; truy cập trái phép; sai lệch hash chain.

---

## CHƯƠNG 5. THỰC NGHIỆM, KIỂM THỬ VÀ ĐÁNH GIÁ
### 5.1. Môi trường thực nghiệm
- Hệ quản trị CSDL: PostgreSQL 16.
- Hệ điều hành: Windows 11 + Ubuntu Server 22.04 LTS (WSL2).
- Phần cứng: 4 vCPU; 8GB RAM; 20GB SSD.
- Công cụ đo lường: `pgbench`.
- Nguyên tắc benchmark: chạy **5 lần**, warm-up **10s**, lấy kết quả trung bình.

### 5.2. Bộ dữ liệu giả lập
Dữ liệu được sinh bằng script/Stored Procedure (PL/pgSQL) dựa trên `generate_series()` để đảm bảo **tốc độ sinh nhanh** và **khả năng tái lập (reproducibility)**.

#### 5.2.1. Nhóm dữ liệu nghiệp vụ (nguồn phát sinh thay đổi)
- **Bảng Orders** (dữ liệu có cấu trúc)
  - Số lượng: 1.000.000 bản ghi.
  - Mục đích: stress test hiệu năng ghi log (TPS) do có tần suất cập nhật trạng thái cao.
  - Trường dữ liệu gợi ý: `id (BIGSERIAL)`, `customer_id (1..50.000)`, `total_amount (100.000..100.000.000)`, `status (PENDING/PAID/SHIPPED/CANCELLED)`, `created_at` (rải đều 6 tháng gần nhất).

- **Bảng Products** (dữ liệu bán cấu trúc)
  - Số lượng: 100.000 bản ghi.
  - Mục đích: kiểm chứng JSONB lưu “dynamic attributes” vào cùng một cột.
  - Trường dữ liệu gợi ý: `id`, `sku`, `tech_specs (JSONB)`.
  - Ví dụ dữ liệu JSON:
    - Laptop: `{ "cpu": "Core i9", "ram": "32GB", "screen": "15 inch" }`
    - Áo thun: `{ "color": "Blue", "size": "L", "material": "Cotton" }`

#### 5.2.2. Nhóm dữ liệu audit (đích lưu vết)
- `audit_logs`: ~10.000.000 dòng (xấp xỉ 5–8GB bao gồm index), trung bình 500B–1KB/dòng.
- Partitioning: RANGE theo thời gian dựa trên cột `changed_at`/`occurred_at`.
- Phân bố:
  - **Partition lịch sử (cold)**: 5 partition cho 5 tháng trước (mỗi partition ~1.5 triệu dòng).
  - **Partition hiện tại (active/hot)**: 1 partition tháng hiện tại, chịu tải ghi trong benchmark.
- Index: GIN trên `new_data` (và/hoặc `old_data`) phục vụ tìm kiếm sâu trong JSON.

### 5.3. Phương pháp đo và thước đo (Metrics)
- TPS (Transactions Per Second).
- Average latency (ms) và (nếu có) p95/p99.
- Overhead: chênh lệch TPS/latency giữa Baseline và Proposed.
- Disk usage / storage growth.

### 5.4. Các kịch bản thực nghiệm
- **Kịch bản 1: Đánh giá hiệu năng xử lý (Stress test pgbench)**
  - Thiết lập: `pgbench` giả lập **50 kết nối đồng thời**, chạy **60 giây**, thao tác **UPDATE liên tục** trên bảng Orders.
  - So sánh 2 trường hợp:
    1) Baseline: không gắn trigger audit.
    2) Proposed: có dynamic trigger (ghi log JSONB vào bảng audit partitioned).
  - Chỉ số: TPS và average latency; kỳ vọng overhead < 15%.

- **Kịch bản 2: Đánh giá mô hình lưu trữ (JSONB + Partitioning)**
  - JSONB: thay đổi dữ liệu trên Orders và Products → kỳ vọng cùng một cơ chế audit lưu đúng hai cấu trúc khác nhau.
  - Partitioning/Retention: xóa log cũ 1 tháng (~1.000.000 dòng) và so sánh:
    - `DELETE` truyền thống vs `DROP PARTITION`.
    - Kỳ vọng: `DROP PARTITION` < 1s và tránh table locking kéo dài.

- **Kịch bản 3: Đánh giá an toàn & bảo mật (Security & Integrity)**
  - Thiết lập: `app_user` (quyền hạn chế) và `db_admin` (quyền cao).
  - Thử nghiệm 1 (SECURITY DEFINER):
    - `app_user` UPDATE bảng nghiệp vụ → log ghi thành công.
    - `app_user` cố SELECT bảng audit → bị từ chối (Access denied).
  - Thử nghiệm 2 (Immutability):
    - `db_admin` cố UPDATE/DELETE trực tiếp lên `audit_logs` → trigger bảo vệ chặn và trả lỗi exception.

- **Kịch bản 4: Hiệu năng truy vấn (Read Performance)**
  - So sánh truy vấn JSONB theo key/value khi **không có** và **có** GIN index.
  - Kỳ vọng: giảm từ hàng chục giây xuống mili-giây với dữ liệu lớn.

#### 5.4.1. Ma trận tổng hợp mục tiêu và kịch bản
| Nội dung thực hiện | Kịch bản thực nghiệm | Kết quả đầu ra dự kiến |
|---|---|---|
| Lưu trữ: JSONB cho đa dạng cấu trúc | Kịch bản 2 (Audit Orders & Products) | Log lưu trữ thành công cấu trúc khác nhau vào 1 bảng |
| Lưu trữ: Partitioning tối ưu quản lý | Kịch bản 2 (Drop Partition) | Thời gian giải phóng dữ liệu nhanh hơn DELETE |
| Xử lý: Hiệu năng cao, độ trễ thấp | Kịch bản 1 (Stress test pgbench) | Báo cáo TPS và latency ở mức chấp nhận được |
| An toàn: Security Definer (Ủy quyền) | Kịch bản 3 (User quyền thấp) | User ghi được log nhưng không xem được log |
| An toàn: Immutability (Chống xóa) | Kịch bản 3 (Admin can thiệp) | Hệ thống báo lỗi, dữ liệu log được bảo toàn |

### 5.5. Kết quả và phân tích
- Bảng/biểu đồ: TPS/latency; dung lượng; thời gian truy vấn; thời gian quản trị partition.
- Thảo luận: nguyên nhân, trade-offs, khuyến nghị vận hành.

### 5.6. Giới hạn của đề tài
- Hạn chế môi trường WSL2/PC; nút thắt Disk I/O; khác biệt production.

---

## KẾT LUẬN VÀ HƯỚNG PHÁT TRIỂN
### 1. Kết luận
[Tóm tắt mức độ đạt mục tiêu: hiệu năng, linh hoạt lưu trữ, bảo mật/tính bất biến.]

### 2. Hướng phát triển
- Tích hợp streaming/CDC khi cần real-time.
- Tối ưu cho throughput rất cao: batching, queue, hoặc kiến trúc tách audit pipeline.
- Hỗ trợ microservices đa database (chuẩn hóa sự kiện, correlation id).

---

## TÀI LIỆU THAM KHẢO
[Liệt kê theo chuẩn IEEE/APA; tối thiểu gồm: PostgreSQL docs (JSONB, GIN, Partitioning, triggers, security definer), pgAudit, Debezium, tài liệu/bài báo về tamper-evident logging.]

## PHỤ LỤC
- Phụ lục A: DDL các bảng (orders/products/audit_logs/partitions)
- Phụ lục B: Code PL/pgSQL (generic audit function, immutability trigger, hash chain)
- Phụ lục C: Script pgbench và cách chạy benchmark
- Phụ lục D: Truy vấn mẫu phục vụ kiểm toán/báo cáo
