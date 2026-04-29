# Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

> **Ghi chú**: Tài liệu này là **khung sườn báo cáo nghiên cứu khoa học**. Khi hoàn thiện, hãy thay các khối `[Nội dung cần viết]`, bổ sung hình/bảng, trích dẫn và số liệu thực nghiệm.

## Tóm tắt (Abstract)
- **Bối cảnh**: [Mô tả bài toán audit trail trong hệ thống quy mô lớn (tài chính/ngân hàng) và 3 thách thức: Big Data, Latency, Integrity/Security.]
- **Mục tiêu**: [Nêu mục tiêu tối ưu kiến trúc PostgreSQL để ghi log tự động, lưu trữ linh hoạt, truy xuất nhanh và chống can thiệp.]
- **Phương pháp**: Trigger + JSONB (+ GIN) + Declarative Partitioning + lớp bảo mật (append-only/immutability, tamper-evident hash chain).
- **Thực nghiệm**: [Môi trường, dataset, pgbench, các kịch bản đo TPS/latency, truy vấn JSONB, kiểm thử bảo mật.]
- **Kết quả chính (dự kiến/đạt được)**: [Tóm tắt số liệu: overhead, tốc độ truy vấn, thời gian drop partition, khả năng chống xóa/sửa.]
- **Từ khóa**: PostgreSQL; Audit Log; JSONB; GIN Index; Partitioning; Immutability.

---

## MỞ ĐẦU
### 1. Đặt vấn đề và tính cấp thiết
[Nêu lý do chọn đề tài, bối cảnh thực tế, tác động nếu thiếu audit log. Liên hệ 3 thách thức chính trong tongquan.md.]

### 2. Mục tiêu nghiên cứu
- Mục tiêu tổng quát: [tối ưu kiến trúc audit log trên PostgreSQL].
- Mục tiêu cụ thể:
  - (1) Lưu trữ linh hoạt đa cấu trúc (JSONB) + truy vấn có cấu trúc.
  - (2) Hiệu năng ghi/đọc chấp nhận được trên dữ liệu lớn (partitioning, indexing).
  - (3) Đảm bảo bất biến và chống giả mạo (immutability, tamper-evident).

### 3. Câu hỏi nghiên cứu / giả thuyết (tùy chọn)
- RQ1: [Trigger + JSONB + Partitioning có giữ overhead dưới ngưỡng chấp nhận được không?]
- RQ2: [GIN Index cải thiện truy vấn JSONB đến mức nào?]
- RQ3: [Cơ chế append-only + hash chain có ngăn chặn/chứng minh can thiệp log không?]

### 4. Đối tượng và phạm vi nghiên cứu
- Đối tượng: PostgreSQL 16; cơ chế trigger/PLpgSQL; JSONB; partitioning; phân quyền.
- Phạm vi: [mô hình PoC], tập trung audit DML (INSERT/UPDATE/DELETE) cho bảng nghiệp vụ; không bao gồm streaming real-time ở quy mô rất lớn.

### 5. Đóng góp của đề tài (Expected contributions)
- (C1) Mô hình dữ liệu audit log schema-less dựa trên JSONB + GIN.
- (C2) Bộ script/hàm PL/pgSQL generic để tự động audit nhiều bảng.
- (C3) Thiết kế partitioning theo thời gian + retention/archiving.
- (C4) Thiết kế bảo mật: security definer, append-only, tamper-evident.
- (C5) Bộ kịch bản benchmark/đánh giá định lượng.

### 6. Bố cục báo cáo
[Tóm tắt cấu trúc chương như dưới.]

---

## CHƯƠNG 1. TỔNG QUAN VÀ CƠ SỞ LÝ THUYẾT
### 1.1. Khái niệm Audit Trail/Audit Log và yêu cầu hệ thống
- Thuộc tính cần đảm bảo: đầy đủ (completeness), toàn vẹn (integrity), không chối bỏ (non-repudiation), truy vết (traceability).
- Các thách thức cốt lõi: **Storage**, **Processing/Latency**, **Security**.

### 1.2. Tổng quan các giải pháp hiện nay
- (1) Logical Decoding/WAL-based
- (2) Extension (ví dụ: pgAudit)
- (3) CDC/Streaming (ví dụ: Debezium)

### 1.3. So sánh giải pháp và lựa chọn hướng tiếp cận
- Bảng so sánh theo tiêu chí: Structured Query, Real-time, Application Context, Độ phức tạp, Chi phí vận hành.
- Lý do chọn: **Trigger + JSONB + Partitioning**.

### 1.4. Giới hạn áp dụng
- Không phù hợp: yêu cầu real-time streaming; throughput cực cao (>10k TPS); microservices đa database.

---

## CHƯƠNG 2. PHƯƠNG PHÁP ĐỀ XUẤT VÀ THIẾT KẾ HỆ THỐNG
### 2.1. Kiến trúc tổng quan
[Mô tả luồng: app_user DML → AFTER ROW trigger → generic audit function → ghi vào audit_logs (partitioned) → security layer/alerting.]

### 2.2. Thiết kế mô hình dữ liệu audit
- Bảng audit_logs (gợi ý cột):
  - id, occurred_at, table_name, operation (I/U/D), actor (app_user), txid, old_data (JSONB), new_data (JSONB), metadata (JSONB), hash, prev_hash
- Nguyên tắc thiết kế: append-only; tối ưu truy vấn theo thời gian và theo table_name/actor.

### 2.3. Thiết kế lưu trữ JSONB và lập chỉ mục
- JSONB: cách biểu diễn OLD/NEW; cân nhắc storage.
- Index:
  - GIN index cho new_data/old_data
  - B-tree index cho (occurred_at), (table_name, occurred_at), (actor, occurred_at)

### 2.4. Thiết kế Partitioning theo thời gian
- Declarative partitioning: PARTITION BY RANGE (occurred_at) theo tháng.
- Chiến lược tablespace: partition “nóng” trên SSD/NVMe; partition “nguội” trên HDD.
- Partition pruning và tác động đến truy vấn.

### 2.5. Phân tích đánh đổi (Trade-offs)
- JSONB: linh hoạt ↔ tốn storage/độ phức tạp truy vấn.
- Trigger: không sửa code app ↔ tăng latency/khó debug.
- Partitioning: quản lý vòng đời tốt ↔ cross-partition query có thể chậm.

---

## CHƯƠNG 3. TRIỂN KHAI CƠ CHẾ GHI LOG VÀ QUẢN LÝ VÒNG ĐỜI
### 3.1. Xây dựng generic audit trigger function (PL/pgSQL)
- Xử lý INSERT/UPDATE/DELETE; chuẩn hóa metadata.
- Chuyển đổi OLD/NEW → JSONB.

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

### 3.5. Cơ chế truy vấn/trích xuất log phục vụ nghiệp vụ và kiểm toán
- Query mẫu theo table_name/actor/time range.
- Query sâu vào JSONB (ví dụ: new_data->>'cpu' = 'Core i9').
- (Tùy chọn) Stored procedure/function trả về report.

---

## CHƯƠNG 4. AN TOÀN, BẢO MẬT VÀ CHỐNG CAN THIỆP LOG
### 4.1. Phân quyền và mô hình SECURITY DEFINER
- Vai trò: app_user, auditor, db_admin.
- Nguyên tắc: app_user ghi được log thông qua trigger nhưng không SELECT trực tiếp.

### 4.2. Immutability (Append-only) cho bảng audit
- Trigger BEFORE UPDATE/DELETE trên audit_logs → RAISE EXCEPTION.
- Phân tích các trường hợp ngoại lệ (bảo trì/khôi phục) và kiểm soát.

### 4.3. Tamper-evident logging (chuỗi băm)
- Mô tả công thức: hash_n = hash(log_n + hash_{n-1}).
- Cách lưu prev_hash/hash; cách kiểm tra tính toàn vẹn.

### 4.4. Cảnh báo và giám sát (Alerting/Monitoring)
- Bảng security_alerts hoặc integration SIEM.
- Sự kiện cảnh báo: cố xóa/sửa audit; truy cập trái phép; sai lệch hash chain.

---

## CHƯƠNG 5. THỰC NGHIỆM, KIỂM THỬ VÀ ĐÁNH GIÁ
### 5.1. Môi trường thực nghiệm
- PostgreSQL 16; WSL2 Ubuntu 22.04; 4 vCPU; 8GB RAM; 20GB SSD.
- Công cụ: pgbench; script PL/pgSQL generate_series.

### 5.2. Bộ dữ liệu giả lập
- Orders (structured): 1,000,000 bản ghi.
- Products (semi-structured): 100,000 bản ghi.
- Audit logs: ~10,000,000 dòng (5–8GB), trung bình 500B–1KB/dòng.
- Index: GIN trên new_data.

### 5.3. Phương pháp đo và thước đo (Metrics)
- TPS, latency (avg/p95/p99 nếu có), disk usage, storage growth.
- Thiết kế chạy benchmark: 5 lần, warm-up 10s, lấy trung bình.

### 5.4. Các kịch bản thực nghiệm
- Kịch bản 1: Hiệu năng xử lý (Baseline vs Proposed; kỳ vọng overhead < 15%).
- Kịch bản 2: Mô hình lưu trữ (JSONB đa cấu trúc; drop partition < 1s).
- Kịch bản 3: An toàn bảo mật (app_user ghi được; db_admin cố xóa/sửa bị chặn; sinh alert).
- Kịch bản 4: Hiệu năng truy vấn (Full scan vs GIN; kỳ vọng từ chục giây xuống ms).

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
[Liệt kê theo chuẩn IEEE/APA; tối thiểu gồm: PostgreSQL docs (JSONB, GIN, Partitioning, triggers, security definer), pgAudit, Debezium, bài báo/whitepaper về tamper-evident logging.]

## PHỤ LỤC
- Phụ lục A: DDL các bảng (orders/products/audit_logs/partitions)
- Phụ lục B: Code PL/pgSQL (generic audit function, immutability trigger, hash chain)
- Phụ lục C: Script pgbench và cách chạy benchmark
- Phụ lục D: Truy vấn mẫu phục vụ kiểm toán/báo cáo
