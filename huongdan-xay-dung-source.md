# Hướng dẫn xây dựng “source code” (SQL scripts) cho nghiên cứu Audit Log trên PostgreSQL

Tài liệu này hướng dẫn **từng bước** để dựng PoC phục vụ nghiên cứu: **Audit Log hiệu năng cao trên PostgreSQL** với **Trigger + JSONB + Partitioning + Security**.

> Phạm vi: hướng dẫn tập trung vào **SQL/PL/pgSQL scripts** ("source code" của giải pháp CSDL) và cách chạy benchmark/kiểm chứng. Bạn có thể đặt các script vào thư mục `sql/` và chạy bằng `psql -f`.

---

## 0) Yêu cầu
- PostgreSQL 16+ (khuyến nghị giống báo cáo)
- Có `psql`, `pgbench`, `pg_dump`
- 1 database dành riêng cho PoC (ví dụ: `audit_poc`)

---

## 1) Chuẩn bị database và role
### 1.1. Tạo database
```sql
CREATE DATABASE audit_poc;
```

### 1.2. (Khuyến nghị) Tạo role theo mô hình
- `app_user`: user nghiệp vụ (được thao tác bảng nghiệp vụ)
- `auditor`: user kiểm toán (được xem/truy vấn log)
- `db_admin`: owner triển khai schema/function

Ví dụ (tùy môi trường bạn chỉnh password/privileges):
```sql
CREATE ROLE db_admin LOGIN;
CREATE ROLE app_user LOGIN;
CREATE ROLE auditor  LOGIN;
```

---

## 2) Tạo bảng audit dạng partition + JSONB
### 2.1. Tạo bảng cha `audit_logs`
**Lưu ý quan trọng**: partition key phải nằm trong primary key của bảng cha.

```sql
CREATE TABLE audit_logs (
    id BIGSERIAL,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL, -- INSERT/UPDATE/DELETE
    user_name TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);
```

### 2.2. Tạo partition theo tháng
```sql
CREATE TABLE audit_logs_2026_01
PARTITION OF audit_logs
FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

> Thực tế nên có script tạo partition tự động theo tháng.

---

## 3) Tạo bảng nghiệp vụ và sinh dữ liệu giả lập (reproducible)
Trong nghiên cứu, dữ liệu được thiết kế theo mô hình E-commerce để mô phỏng tải giao dịch cao.

### 3.1. Bảng Orders (dữ liệu có cấu trúc)
```sql
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  customer_id INT NOT NULL,
  total_amount NUMERIC(12,2) NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL
);
```

Sinh 1.000.000 bản ghi bằng `generate_series()`:
```sql
INSERT INTO orders (customer_id, total_amount, status, created_at)
SELECT
  floor(random() * 50000 + 1)::int,
  (random() * 100000000 + 100000)::numeric(12,2),
  (ARRAY['PENDING','PAID','SHIPPED','CANCELLED'])[floor(random()*4+1)],
  now() - (random() * interval '180 days')
FROM generate_series(1, 1000000);
```

### 3.2. Bảng Products (dữ liệu bán cấu trúc)
```sql
CREATE TABLE products (
  id BIGSERIAL PRIMARY KEY,
  sku TEXT UNIQUE NOT NULL,
  tech_specs JSONB
);
```

Sinh 100.000 bản ghi với 2 kiểu JSON khác nhau:
```sql
INSERT INTO products (sku, tech_specs)
SELECT
  'SKU-' || gs::text,
  CASE WHEN random() < 0.5
    THEN jsonb_build_object('cpu','Core i9','ram','32GB','screen','15 inch')
    ELSE jsonb_build_object('color','Blue','size','L','material','Cotton')
  END
FROM generate_series(1, 100000) gs;
```

> Mục tiêu: chứng minh `audit_logs.new_data` có thể lưu được các cấu trúc JSON khác nhau mà không đổi schema.

---

## 4) Viết Generic Audit Trigger Function (PL/pgSQL)
### 4.1. Hàm `func_audit_trigger()`
Hàm này ghi log động theo `TG_OP` và `TG_TABLE_NAME`.

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

### 4.2. Gắn trigger vào bảng nghiệp vụ
Gắn audit trigger cho các bảng nguồn phát sinh thay đổi (ít nhất: `orders`, `products`).

```sql
CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();

CREATE TRIGGER trg_audit_products
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();
```

---

## 5) Thiết lập bảo mật: SECURITY DEFINER + Append-only (WORM)
### 5.1. Ý nghĩa SECURITY DEFINER
- `app_user` **không cần** có quyền `INSERT` vào `audit_logs`.
- Trigger chạy qua function `SECURITY DEFINER` sẽ ghi log dưới quyền owner (thường là `db_admin`).

### 5.2. Chặn UPDATE/DELETE trên `audit_logs` (immutability) + ghi nhận cảnh báo
Theo thiết kế trong `csdl-nc-new.md`, khi có hành vi cố tình `UPDATE/DELETE` vào bảng log, hệ thống **vừa chặn** thao tác **vừa ghi nhận** vào bảng cảnh báo (`security_alerts`) để tích hợp giám sát/SIEM.

```sql
-- Bảng cảnh báo bảo mật (đơn giản, có thể mở rộng thêm request_id/correlation_id, ip, v.v.)
CREATE TABLE IF NOT EXISTS security_alerts (
    id BIGSERIAL PRIMARY KEY,
    alert_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action TEXT NOT NULL,
    table_name TEXT,
    user_name TEXT,
    details JSONB
);

CREATE OR REPLACE FUNCTION func_prevent_audit_change() RETURNS TRIGGER AS $$
DECLARE
    v_details JSONB;
BEGIN
    v_details := jsonb_build_object(
        'op', TG_OP,
        'schema', TG_TABLE_SCHEMA
    );

    IF (TG_OP = 'UPDATE') THEN
        v_details := v_details || jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
    ELSIF (TG_OP = 'DELETE') THEN
        v_details := v_details || jsonb_build_object('old', to_jsonb(OLD));
    END IF;

    INSERT INTO security_alerts(action, table_name, user_name, details)
    VALUES ('AUDIT_TAMPER_ATTEMPT', TG_TABLE_NAME, current_user, v_details);

    RAISE EXCEPTION 'Không được phép sửa hoặc xóa Audit Log!';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_protect_audit
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION func_prevent_audit_change();
```

> Gợi ý hardening: với các function `SECURITY DEFINER`, nên cấu hình `SET search_path` cố định để tránh rủi ro hijack đối tượng theo schema.

---

## 6) Tạo index phục vụ truy vấn
```sql
-- Tối ưu truy vấn theo thời gian + bảng
CREATE INDEX IF NOT EXISTS idx_audit_table_time
ON audit_logs (table_name, changed_at);

-- Tối ưu truy vấn sâu JSONB
CREATE INDEX IF NOT EXISTS idx_audit_new_data_gin
ON audit_logs USING GIN (new_data);
```

---

## 7) Chạy benchmark và thu thập số liệu
### 7.1. Nguyên tắc benchmark
- Chạy **5 lần**, warm-up **10s**, lấy giá trị trung bình.
- So sánh 2 trường hợp:
  - Baseline: không gắn trigger audit.
  - Proposed: có trigger audit (ghi vào bảng audit partitioned + JSONB).

### 7.2. Stress test bằng pgbench (50 connections, UPDATE 60s)
Kịch bản theo `csdl-nc-new.md`: giả lập **50 kết nối đồng thời**, chạy **60 giây**, UPDATE liên tục bảng `orders`.

1) Tạo file script cho pgbench (ví dụ `update_orders.sql`):
```sql
-- cập nhật ngẫu nhiên 1 đơn hàng
UPDATE orders
SET status = (ARRAY['PENDING','PAID','SHIPPED','CANCELLED'])[floor(random()*4+1)]
WHERE id = (random() * 1000000 + 1)::bigint;
```

2) Chạy pgbench:
```bash
pgbench -c 50 -T 60 -f update_orders.sql audit_poc
```

3) Lặp lại 5 lần và ghi TPS/latency.

> Gợi ý chạy Baseline: tạo dữ liệu và chạy benchmark **trước khi** tạo trigger audit (hoặc tạm DISABLE trigger), sau đó bật lại để chạy Proposed.

### 7.3. Thu thập chỉ số
- TPS
- Average latency (ms)
- Overhead (mức suy giảm TPS / tăng latency), kỳ vọng < 15%

---

## 8) Kiểm chứng truy vấn & truy vết
### 8.1. Truy vấn lịch sử thay đổi theo bảng/thời gian
```sql
SELECT *
FROM audit_logs
WHERE table_name = 'orders'
ORDER BY changed_at DESC
LIMIT 50;
```

### 8.2. Truy vấn sâu JSONB (ví dụ)
**Ví dụ 1: lọc theo trạng thái đơn hàng**
```sql
SELECT *
FROM audit_logs
WHERE table_name = 'orders'
  AND new_data->>'status' = 'PAID';
```

**Ví dụ 2: tìm log sản phẩm có laptop Core i9**
```sql
SELECT *
FROM audit_logs
WHERE table_name = 'products'
  AND new_data->'tech_specs'->>'cpu' = 'Core i9';
```

---

## 9) Backup/Restore theo partition (phục vụ archive)
### 9.1. Backup một partition
```bash
pg_dump -t audit_logs_2026_01 audit_poc > audit_logs_2026_01.sql
```

### 9.2. Drop partition để giải phóng
```sql
DROP TABLE audit_logs_2026_01;
```

### 9.3. Restore khi cần
```bash
psql audit_poc < audit_logs_2026_01.sql
```

---

## 10) Checklist đầu ra cho báo cáo
- DDL bảng cha + partition mẫu
- Source (PL/pgSQL): `func_audit_trigger`, `func_prevent_audit_change`
- Kịch bản benchmark: baseline vs proposed (TPS/latency)
- Kịch bản demo bảo mật: thử xóa/sửa audit log bị chặn
- Ví dụ truy vấn JSONB + so sánh có/không GIN
