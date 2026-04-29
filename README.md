# Audit Log PoC — PostgreSQL Partitioning + JSONB

Research project: high-performance audit log system on PostgreSQL 16.

## Quick start (từ máy trắng)

```bash
# 1. Prerequisites
#    PostgreSQL 16, psql, pgbench — đã có sẵn trên Ubuntu 22.04 WSL2

# 2. Bootstrap database (run as superuser)
psql "postgresql://postgres:postgres@localhost/postgres" -c "CREATE DATABASE audit_poc OWNER db_admin;"
psql "postgresql://postgres:postgres@localhost/postgres" -f sql/00_roles.sql
psql "postgresql://postgres:postgres@localhost/audit_poc" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

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

# 8. Indexes
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/07_indexes.sql

# 9. GRANT/REVOKE
psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/08_grants.sql

# 10. Benchmark
bash bench/run_baseline.sh
bash bench/run_proposed.sh
```

## Reset

```bash
psql "postgresql://postgres:postgres@localhost/postgres" -f sql/99_cleanup.sql
```

## Tài liệu

- `6-baocao.md` — Khung báo cáo nghiên cứu
- `7-huongdan-xay-dung-source.md` — Hướng dẫn kỹ thuật chi tiết
- `8-ke-hoach-xay-dung.md` — Kế hoạch phase-by-phase
- `docs/results-summary.md` — Kết quả thực nghiệm (fill sau khi chạy bench)
