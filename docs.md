# Xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

## Tại sao chọn PostgreSQL?

PostgreSQL là lựa chọn "điểm 10" cho đề tài này vì hai lý do:

1. **JSONB:** PostgreSQL xử lý dữ liệu JSON (dạng nhị phân - JSONB) mạnh mẽ và nhanh hơn nhiều so với các RDBMS khác, hỗ trợ tuyệt vời cho việc lưu trữ log thay đổi dữ liệu (Bán cấu trúc).

2. **Declarative Partitioning:** Tính năng phân mảnh dữ liệu (Partitioning) của Postgres rất rõ ràng và dễ quản lý cho các bảng dữ liệu lớn.

---

## 1. Khía cạnh Lưu trữ (Storage)

**Mục tiêu:** Tối ưu hóa lưu trữ dữ liệu lớn, hỗ trợ dữ liệu bán cấu trúc.

### Cấu trúc bảng Audit (JSONB)

Thay vì lưu trữ cứng nhắc, bạn sử dụng kiểu dữ liệu `JSONB` để lưu snapshot của dòng dữ liệu. Điều này giúp bảng Audit có thể chứa log của bất kỳ bảng nào (User, Product, Order) mà không cần thay đổi cấu trúc.

```sql
-- Bảng cha (Partitioned Table)
CREATE TABLE audit_logs (
    id BIGSERIAL, -- Tự tăng
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL, -- INSERT, UPDATE, DELETE
    user_name TEXT,
    old_data JSONB, -- Dữ liệu trước khi sửa (Lưu trữ bán cấu trúc)
    new_data JSONB, -- Dữ liệu sau khi sửa
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, changed_at) -- Partition key phải nằm trong PK
) PARTITION BY RANGE (changed_at);
```

### Phân mảnh (Partitioning)

Sử dụng Declarative Partitioning để chia nhỏ dữ liệu theo thời gian (ví dụ: từng tháng). Giúp truy vấn nhanh và dễ dàng Archive (nén/cất) dữ liệu cũ.

```sql
-- Tạo bảng con cho tháng 1/2026
CREATE TABLE audit_logs_2026_01 
PARTITION OF audit_logs
FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

---

## 2. Khía cạnh Xử lý (Processing)

**Mục tiêu:** Tự động hóa việc ghi log mà không làm ảnh hưởng code ứng dụng.

### Trigger Function (Generic)

Trong PostgreSQL, Trigger phải gọi một Function. Bạn sẽ viết một Function dùng PL/pgSQL có khả năng xử lý động (Dynamic) cho mọi bảng.

```sql
CREATE OR REPLACE FUNCTION func_audit_trigger() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, old_data)
        VALUES (TG_TABLE_NAME, 'DELETE', current_user, to_jsonb(OLD));
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'UPDATE', current_user, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_logs (table_name, operation, user_name, new_data)
        VALUES (TG_TABLE_NAME, 'INSERT', current_user, to_jsonb(NEW));
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

> **Lưu ý:** `SECURITY DEFINER` là mấu chốt an toàn (xem phần 3)

### Gán Trigger

```sql
CREATE TRIGGER trg_audit_users
AFTER INSERT OR UPDATE OR DELETE ON users -- Bảng nghiệp vụ
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();
```

---

## 3. Khía cạnh An toàn (Security)

**Mục tiêu:** Đảm bảo tính toàn vẹn, User thường không thể xóa dấu vết.

### SECURITY DEFINER (Điểm nhấn nghiên cứu)

Đây là kỹ thuật quan trọng trong PostgreSQL.

- Khi bạn tạo Function với từ khóa `SECURITY DEFINER`, function đó sẽ chạy với quyền của người tạo (thường là Superuser/Admin) chứ không phải quyền của người đang thực thi câu lệnh (User thường).

- **Kịch bản:** User "NhanVien" có quyền `UPDATE` bảng `users`, nhưng KHÔNG có quyền `INSERT` vào bảng `audit_logs`. Tuy nhiên, nhờ Trigger gọi Function `SECURITY DEFINER`, việc ghi log vẫn thành công dưới quyền Admin ngầm định.

- **Kết quả:** Hacker dù chiếm được tài khoản "NhanVien" cũng không thể vào bảng `audit_logs` để xóa dấu vết được.

### Block Delete trên Audit Log (Append-Only)

Tạo thêm một Trigger đặc biệt trên bảng `audit_logs` để chặn mọi hành động `DELETE` hoặc `UPDATE`.

```sql
CREATE OR REPLACE FUNCTION func_prevent_audit_change() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Không được phép sửa hoặc xóa Audit Log!';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_audit
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION func_prevent_audit_change();
```

---

## 4. Backup/Restore & Import/Export

### Backup từng phần (Partial Backup)

Với cấu trúc Partition, bạn có thể nghiên cứu sử dụng `pg_dump` để backup riêng lẻ các partition cũ (ví dụ: log của năm ngoái) ra file, sau đó `DROP TABLE` partition đó để giải phóng dung lượng, nhưng vẫn giữ file backup để Restore khi cần thanh tra.

---

---

## Đề cương nghiên cứu cụ thể cho đề tài này (Gợi ý viết báo cáo)

Nếu chọn hướng này, cấu trúc báo cáo của bạn nên như sau:

### 1. Cơ sở lý thuyết

- Kiến trúc Partitioning trong PostgreSQL (Kế thừa bảng).
- Kiểu dữ liệu JSONB và lợi thế so với XML/Text.
- Cơ chế Trigger và Security Definer.

### 2. Thiết kế giải pháp

- Sơ đồ ERD (chủ yếu là quan hệ Partition).
- Thiết kế Function tổng quát (Generic Audit Function).

### 3. Thực nghiệm & Đánh giá (Phần quan trọng để lấy điểm cao)

- **Kịch bản 1:** Đo thời gian Insert 10.000 dòng vào bảng `users` khi chưa có Trigger Audit.
- **Kịch bản 2:** Đo thời gian Insert 10.000 dòng khi CÓ Trigger Audit (để tính toán độ trễ - Overhead).
- **Kịch bản 3:** Thử nghiệm xóa log bằng tài khoản thường (Chứng minh tính bảo mật).
- **Kịch bản 4:** Truy vấn tìm kiếm lịch sử thay đổi của 1 user cụ thể trong đống log 1 triệu dòng (Chứng minh hiệu năng của JSONB Index).
