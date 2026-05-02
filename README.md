# Audit Log PoC — PostgreSQL Partitioning + JSONB

Research project: high-performance audit log system on PostgreSQL 16.

## Quick start (từ máy trắng)

### Cách 1: Docker (Khuyến nghị)

```bash
# 1. Clone repository
git clone <repo-url>
cd csdl

# 2. Copy và chỉnh sửa cấu hình (tùy chọn)
cp .env.example .env
# Chỉnh sửa .env theo nhu cầu

# 3. Khởi động PostgreSQL qua Docker
docker-compose up -d

# 4. Chạy benchmark
bash bench/run_baseline.sh
bash bench/run_proposed.sh

# 5. Xem kết quả performance
bash bench/analyze_performance.sh
```

### Cách 2: Local PostgreSQL

```bash
# 1. Prerequisites
#    PostgreSQL 16, psql, pgbench — đã có sẵn trên Ubuntu 22.04 WSL2

# 2. Bootstrap database (run as superuser)
#    Roles phải tồn tại TRƯỚC khi tạo database với OWNER db_admin
psql "postgresql://postgres:postgres@localhost/postgres" -f sql/00_roles.sql
psql "postgresql://postgres:postgres@localhost/postgres" -c "CREATE DATABASE audit_poc OWNER db_admin;"

# 3. Schema
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/01_schema_audit.sql
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/02_schema_business.sql

# 4. Seed data (~5-8 GB, chạy nền)
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/03_seed_data.sql

# 5. Audit function + triggers
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/04_audit_function.sql

# 6. Immutability
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/05_security_immutability.sql

# 7. (Optional) Hash chain
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/06_hash_chain.sql

# 8. (Optional) DDL Audit - Audit các thay đổi schema (requires superuser — event trigger creation)
psql "postgresql://postgres:postgres@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/09_audit_ddl.sql

# 9. Indexes
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/07_indexes.sql

# 10. GRANT/REVOKE
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/08_grants.sql

# 11. Benchmark
bash bench/run_baseline.sh
bash bench/run_proposed.sh
```

## Tính năng mới (Recent Enhancements)

### 📊 Performance Monitoring
- **pg_stat_statements**: Tự động bật trong benchmark để theo dõi hiệu năng
- **analyze_performance.sh**: Phân tích truy vấn chậm, tần suất gọi, và tác động của audit trigger
- **monitor.sh**: Real-time monitoring trong khi chạy benchmark (kết nối, TPS, WAL, cache hit ratio)

### 🔍 DDL Audit Support
- **sql/09_audit_ddl.sql**: Event trigger ghi lại các thay đổi schema (CREATE, ALTER, DROP)
- Lưu trữ trong bảng `audit_ddl_logs` với thông tin người dùng và câu lệnh SQL

### 🐳 Docker Support
- **docker-compose.yml**: Khởi chạy PostgreSQL 16 với pg_stat_statements sẵn sàng
- **Adminer**: Web interface quản lý database tại http://localhost:8080
- Cấu hình qua file `.env` (copy từ `.env.example`)

### 🗂️ Partition Management
- **scripts/manage_partitions.sh**: Quản lý partition tự động
  - `create`: Tạo partition cho 3 tháng tới
  - `drop_old`: Xóa partition cũ (mặc định > 6 tháng)
  - `list`: Liệt kê tất cả partition và kích thước

### 📖 Enhanced Documentation
- **docs/GETTING_STARTED.md**: Hướng dẫn chi tiết từng bước với Docker và local setup
- Tích hợp performance monitoring và DDL audit vào workflow

## Reset

```bash
psql "postgresql://postgres:postgres@localhost/postgres" -f sql/99_cleanup.sql
```

## Tài liệu

- `6-baocao.md` — Khung báo cáo nghiên cứu
- `7-huongdan-xay-dung-source.md` — Hướng dẫn kỹ thuật chi tiết
- `8-ke-hoach-xay-dung.md` — Kế hoạch phase-by-phase
- `docs/results-summary.md` — Kết quả thực nghiệm (fill sau khi chạy bench)
