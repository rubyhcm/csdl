# Getting Started

This guide walks you through setting up and running the **Audit Log PoC** on a fresh machine.

## Prerequisites

- **Docker** (recommended) or a local PostgreSQL 16 installation
- `psql` client
- `git`

## Quick Start with Docker

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-org/audit-log-poc.git
   cd audit-log-poc
   ```

2. **(Optional) Configure environment**

   ```bash
   cp .env.example .env
   # Edit .env to override defaults (passwords, ports, etc.)
   ```

3. **Start PostgreSQL via Docker Compose**

   Docker Compose starts PostgreSQL 16 with `pg_stat_statements` pre-loaded and mounts the SQL files to `/sql` inside the container.

   ```bash
   docker-compose up -d
   # Wait for the health-check to pass before continuing
   docker-compose ps   # STATUS should show "healthy"
   ```

4. **Create roles and the audit database**

   Roles must exist before the database is created with `OWNER db_admin`.

   ```bash
   psql "postgresql://postgres:postgres@localhost/postgres" -v ON_ERROR_STOP=1 -f sql/00_roles.sql
   psql "postgresql://postgres:postgres@localhost/postgres" -c "CREATE DATABASE audit_poc OWNER db_admin;"
   ```

5. **Bootstrap the schema**

   ```bash
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/01_schema_audit.sql
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/02_schema_business.sql
   ```

6. **Seed data (~5–8 GB, may take a few minutes)**

   Seed chạy được cả TRƯỚC và SAU khi tạo audit triggers — script tự kiểm tra trigger tồn tại.

   ```bash
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/03_seed_data.sql
   ```

7. **Audit trigger function + immutability**

   ```bash
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/04_audit_function.sql
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/05_security_immutability.sql
   ```

8. **(Optional) Hash chain tamper-evident + DDL audit**

   `06_hash_chain.sql` cài `pgcrypto` tự động. `09_audit_ddl.sql` kích hoạt event trigger cho DDL.

   ```bash
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/06_hash_chain.sql
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/09_audit_ddl.sql
   ```

9. **Indexes và phân quyền**

   ```bash
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/07_indexes.sql
   psql "postgresql://db_admin:db_admin_pass@localhost/audit_poc" -v ON_ERROR_STOP=1 -f sql/08_grants.sql
   ```

10. **Run the benchmark**

    ```bash
    bash bench/run_baseline.sh
    bash bench/run_proposed.sh
    ```

    After each run the scripts will output **performance metrics** collected via `pg_stat_statements` (see *Performance Monitoring* below).

## Running without Docker

If you prefer a local PostgreSQL 16 installation, make sure PostgreSQL 16 and `pgbench` are installed, then follow steps **4–10** above directly against your local server. `pgcrypto` và `dblink` sẽ được cài tự động bởi `06_hash_chain.sql` và `05_security_immutability.sql`.

## Performance Monitoring

Both benchmark scripts automatically:

- Enable `pg_stat_statements` for the session.
- Store the summary in `bench/results/performance_<run>.log`.

You can view the logs after a run:

```bash
cat bench/results/performance_baseline.log
cat bench/results/performance_proposed.log
```

## Support for Additional Audit Events

The PoC now includes an **event trigger** that captures DDL changes (e.g., `CREATE TABLE`, `ALTER TABLE`). The trigger is defined in `sql/09_audit_ddl.sql` and is loaded in step 6 above (optional).

## Cleaning Up

To drop the entire environment:

```bash
docker rm -f audit-poc-pg
psql "postgresql://postgres:postgres@localhost/postgres" -f sql/99_cleanup.sql
```

---

Feel free to explore the `docs/` folder for deeper technical details, architecture diagrams, and result summaries.
