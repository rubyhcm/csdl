# Xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

## 1. Phân tích bài toán (Đặt vấn đề)

Trong các hệ thống tài chính/ngân hàng hoặc bảo mật, việc biết "Ai đã sửa cái gì, vào lúc nào, giá trị cũ là gì?" quan trọng hơn cả việc lưu trữ dữ liệu hiện tại.

### Thách thức 1 (Lưu trữ - Storage)
Bảng Log tăng trưởng cực nhanh ("Write-heavy"). Nếu bảng chính có 1 triệu dòng, bảng Log có thể lên tới hàng chục triệu dòng.

### Thách thức 2 (Xử lý - Processing)
Việc ghi Log phải có độ trễ thấp nhất để không làm chậm transaction chính (Blocking I/O).

### Thách thức 3 (An toàn - Security)
Admin hệ thống (DBA/Superuser) hoặc kẻ tấn công chiếm quyền cao nhất có thể xóa dấu vết. Cần cơ chế bảo vệ "Write-Once-Read-Many" (WORM).

---

## 2. Chi tiết triển khai kỹ thuật

### A. Khía cạnh LƯU TRỮ (Storage)

**Mục tiêu:** Tối ưu không gian lưu trữ và tốc độ truy xuất trên tập dữ liệu lớn.

#### Cấu trúc bảng Audit (Schema Design) & JSONB

**Vấn đề:** Các RDBMS cũ thường dùng XML hoặc TEXT để lưu log, rất chậm khi truy vấn.

**Giải pháp PostgreSQL:** Sử dụng kiểu dữ liệu `JSONB` (Binary JSON).

- `JSONB` được lưu dưới dạng nhị phân đã phân tích cú pháp, cho phép đánh chỉ mục (GIN Index) trực tiếp vào key/value bên trong chuỗi JSON.
- **Cột `old_data` (JSONB):** Lưu toàn bộ dòng dữ liệu trước khi update (`row_to_json(OLD)`).
- **Cột `new_data` (JSONB):** Lưu toàn bộ dòng dữ liệu sau khi update (`row_to_json(NEW)`).
- **Lợi ích:** Một bảng Audit duy nhất có thể lưu vết cho hàng trăm bảng nghiệp vụ khác nhau (Schema-less logging).

#### Kỹ thuật Declarative Partitioning (Phân mảnh khai báo)

**Triển khai:** Sử dụng tính năng `PARTITION BY RANGE` của PostgreSQL.

- Chia bảng `audit_logs` thành các bảng con (child tables) theo tháng (ví dụ: `audit_logs_2025_10`, `audit_logs_2025_11`).
- Có thể gán các Partition cũ vào các Tablespace nằm trên ổ cứng giá rẻ (HDD) để tiết kiệm chi phí, trong khi Partition hiện tại nằm trên SSD NVMe.
- **Lợi ích:** Khi cần truy vấn log tháng 10, Planner của Postgres sẽ tự động bỏ qua (Partition Pruning) các tháng khác, tăng tốc độ truy vấn gấp nhiều lần.

---

### B. Khía cạnh XỬ LÝ (Processing)

**Mục tiêu:** Tự động hóa logic ghi log bằng Procedural Language (PL/pgSQL).

#### Trigger Function & Biến đặc biệt (OLD/NEW)

Trong PostgreSQL, Trigger phải gọi một Function.

**Cơ chế:** Viết một hàm `func_audit_trigger()` tổng quát bằng ngôn ngữ PL/pgSQL.

**Xử lý:**

- Sử dụng biến đặc biệt `OLD` (bản ghi cũ) và `NEW` (bản ghi mới) có sẵn trong Trigger.
- Sử dụng hàm `to_jsonb(OLD)` và `to_jsonb(NEW)` để chuyển đổi dữ liệu dòng thành JSONB.
- Trigger được thiết lập ở chế độ `FOR EACH ROW` để bắt chính xác từng dòng dữ liệu bị thay đổi (kể cả trong các lệnh Bulk Update).

#### Đánh giá hiệu năng (Performance Benchmarking) - Yêu cầu cho luận văn

Thực hiện đo đạc TPS (Transactions Per Second) khi Insert 100.000 dòng trong 2 trường hợp:

1. Không có Audit Trigger.
2. Có Audit Trigger (ghi vào Partitioned Table).

=> Chứng minh độ trễ (Overhead) là chấp nhận được.

#### Stored Procedure (Truy vấn)

Viết Procedure (hoặc Function trả về Table) để trích xuất dữ liệu.

**Ví dụ:** Tìm tất cả các lần lương của nhân viên thay đổi.

```sql
-- Query trực tiếp vào JSONB cực nhanh
SELECT * FROM audit_logs 
WHERE table_name = 'nhan_vien' 
AND (new_data->>'luong')::int > 50000000;
```

---

### C. Khía cạnh AN TOÀN (Security)

**Mục tiêu:** Phân quyền chặt chẽ và chống chối bỏ.

#### Mô hình SECURITY DEFINER (Nâng quyền tạm thời)

**Vấn đề:** User thường (NhanVien) không được phép có quyền `INSERT` vào bảng `audit_logs` để tránh họ tự làm giả log. Nhưng nếu không có quyền, Trigger của họ sẽ bị lỗi khi cố ghi log.

**Giải pháp:** Định nghĩa hàm Trigger với từ khóa `SECURITY DEFINER`.

- Hàm này sẽ chạy dưới quyền của người tạo ra nó (thường là Superuser/DBA), bỏ qua quyền hạn hạn chế của người thực thi (NhanVien).
- User NhanVien thực hiện `UPDATE` bảng nghiệp vụ → Trigger kích hoạt (dưới quyền Admin) → Ghi log thành công → User vẫn không thể truy cập trực tiếp bảng Audit.

#### Cơ chế Immutability (Bất biến) cho Log

- Tạo một Trigger riêng cho bảng `audit_logs`: `BEFORE UPDATE OR DELETE`.
- Trong Trigger này, luôn luôn `RAISE EXCEPTION` (Báo lỗi).
- **Kết quả:** Biến bảng Audit thành dạng Append-Only (Chỉ được ghi thêm). Ngay cả Admin nếu lỡ tay chạy lệnh `DELETE FROM audit_logs` cũng sẽ bị chặn lại.

---

## 3. Đề xuất kịch bản Demo (Để viết báo cáo)

### Bước 1: Thiết lập môi trường

- Tạo Database PostgreSQL.
- Tạo bảng `salary_table`.
- Tạo bảng `audit_trail` với Partition theo tháng.

### Bước 2: Tấn công giả lập (Penetration Test)

- Đăng nhập bằng role `accountant` (Kế toán).
- Thực hiện sửa lương: `UPDATE salary_table SET amount = 10000 WHERE id = 1;`
- Kẻ tấn công cố gắng xóa dấu vết: `DELETE FROM audit_trail WHERE user_name = 'accountant';`

### Bước 3: Kiểm chứng kết quả

**Kết quả 1:** Lệnh `DELETE` log bị từ chối `ACCESS DENIED` (do không có quyền) hoặc bị chặn bởi Trigger bảo vệ (`Operation not permitted`).

**Kết quả 2:** Đăng nhập bằng role `auditor` (Thanh tra).

Chạy câu truy vấn JSONB để xem lịch sử:

- User: `accountant`
- Old Data: `{"amount": 500}`
- New Data: `{"amount": 10000}`
- Time: `2025-10-24 10:00:00`

---

## 4. Tại sao chọn PostgreSQL cho đề tài này?

*(Phần này dùng để bảo vệ đề cương)*

- **JSONB:** Hiệu năng truy vấn dữ liệu bán cấu trúc tốt hơn `NVARCHAR(MAX)` chứa JSON của SQL Server hay `CLOB` của Oracle trong các phiên bản cũ.
- **Native Partitioning:** Quản lý file vật lý rõ ràng, hỗ trợ tách Tablespace (Lưu trữ).
- **Security Definer:** Cơ chế ủy quyền trong Function rất linh hoạt, giải quyết triệt để bài toán phân quyền (An toàn).
