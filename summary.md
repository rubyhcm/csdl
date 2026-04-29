# Nghiên cứu và Xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

## Mục tiêu nghiên cứu

Giải quyết bài toán lưu vết dữ liệu (Audit Trail) trong các hệ thống thông tin lớn (Tài chính, Ngân hàng) với ba thách thức chính:

- **Khối lượng dữ liệu tăng trưởng nhanh** (Big Data)
- **Yêu cầu không làm chậm hiệu năng hệ thống** (Latency)
- **Đảm bảo tính toàn vẹn dữ liệu** trước sự can thiệp của người quản trị (Security)

---

## Nội dung thực hiện

### 1. Lưu trữ

- Sử dụng kiểu dữ liệu **JSONB** (Binary JSON) để lưu trữ linh hoạt (Schema-less) trạng thái dữ liệu trước và sau khi thay đổi (OLD và NEW values), cho phép một bảng Log duy nhất phục vụ cho toàn bộ hệ thống.

- Áp dụng kỹ thuật **Declarative Partitioning** (Phân mảnh theo thời gian) để tối ưu hóa việc quản lý các bảng Log có kích thước lớn, hỗ trợ truy vấn nhanh và lưu trữ phân cấp (Tablespace).

### 2. Xử lí

- Xây dựng các **Dynamic Triggers** và **Generic Functions** bằng ngôn ngữ PL/pgSQL để tự động hóa việc bắt các sự kiện `INSERT`, `UPDATE`, `DELETE` mà không cần can thiệp vào mã nguồn ứng dụng.

- Tối ưu hóa thuật toán ghi log để đảm bảo độ trễ (Overhead) ở mức thấp nhất, không gây tắc nghẽn (Blocking I/O) cho các giao dịch nghiệp vụ chính.

### 3. An toàn - bảo mật

- Triển khai mô hình **SECURITY DEFINER** trong Stored Procedures để thiết lập cơ chế ủy quyền: Người dùng có thể kích hoạt ghi Log nhưng không có quyền truy cập trực tiếp vào bảng Log.

- Xây dựng cơ chế **Immutability** (Bất biến): Sử dụng Trigger chặn chiều `DELETE`/`UPDATE` trên bảng Log, biến bảng này thành dạng "Append-Only", đảm bảo ngay cả tài khoản Admin cũng không thể xóa log.

---

## Kết quả dự kiến

- Mô hình cơ sở dữ liệu hoàn chỉnh với Partitioning và JSONB Indexing.
- Bộ Script PL/pgSQL tự động hóa việc Audit cho các bảng nghiệp vụ.
- Báo cáo thực nghiệm so sánh hiệu năng (TPS - Transactions Per Second) giữa việc có và không có Audit Log.
- Kịch bản Demo tấn công giả lập: Chứng minh hệ thống ngăn chặn được nỗ lực xóa log của tài khoản có quyền cao.
