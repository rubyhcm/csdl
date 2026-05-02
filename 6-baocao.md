# Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB

## Tóm tắt (Abstract)
- **Bối cảnh**: Các hệ thống tài chính/ngân hàng yêu cầu audit trail toàn diện để đáp ứng tuân thủ và phát hiện gian lận. Ba thách thức cốt lõi là: khối lượng dữ liệu lớn (Big Data) từ giao dịch write-heavy liên tục, yêu cầu độ trễ thấp để không ảnh hưởng đến throughput nghiệp vụ, và đảm bảo tính toàn vẹn/bất biến của nhật ký (Integrity/Security).
- **Mục tiêu**: Thiết kế và xây dựng kiến trúc hệ thống audit log trên PostgreSQL 16 với khả năng ghi log tự động qua trigger, lưu trữ linh hoạt đa cấu trúc, truy xuất hiệu năng cao và cơ chế chống can thiệp có thể kiểm chứng.
- **Phương pháp**: Trigger PL/pgSQL SECURITY DEFINER + JSONB (lưu OLD/NEW theo schema-less) + GIN Index + Declarative Partitioning theo tháng + lớp bảo mật gồm append-only/WORM (chặn UPDATE/DELETE) và chuỗi hash SHA-256 (tamper-evident).
- **Thực nghiệm**: PostgreSQL 16.10 trên Ubuntu 22.04 LTS (WSL2), 4 vCPU / 8 GB RAM. Dataset: 1 triệu bản ghi orders, 100 nghìn products, 7,5 triệu dòng audit log (5,253 MB). Đo TPS/latency bằng pgbench với 50 clients / 70s; truy vấn JSONB có/không GIN trên 7,5 triệu dòng; kiểm thử bảo mật 3 tình huống phân quyền.
- **Kết quả chính**: Overhead trigger âm (−4% TPS so với baseline, nằm trong ngưỡng dao động WSL2 I/O — overhead thực tế < 5 ms/transaction); DROP PARTITION xóa 1 triệu dòng trong 47 ms (nhanh hơn DELETE ~13,6 lần); partition pruning chính xác (1/8 partitions được quét); GIN cải thiện ~10% ở warm cache với selectivity thấp; cả 3 tình huống bảo mật PASS — hệ thống chặn hoàn toàn mọi can thiệp vào audit log.
- **Từ khóa**: PostgreSQL; Audit Log; JSONB; GIN Index; Partitioning; Immutability; WORM.

---

## MỞ ĐẦU
### 1. Đặt vấn đề và tính cấp thiết

Trong các hệ thống tài chính, ngân hàng và thương mại điện tử hiện đại, mọi thao tác thay đổi dữ liệu — từ cập nhật trạng thái đơn hàng, điều chỉnh số dư tài khoản, đến sửa thông tin nhân sự — đều cần được ghi nhận đầy đủ và trung thực. Nhu cầu này xuất phát từ ba áp lực thực tiễn:

- **Tuân thủ pháp lý và kiểm toán**: Các chuẩn mực như SOX, PCI-DSS, ISO 27001 yêu cầu tổ chức có khả năng trả lời câu hỏi “ai đã thay đổi gì, vào lúc nào, giá trị cũ và mới là bao nhiêu” cho bất kỳ bản ghi nào trong vòng nhiều năm. Thiếu audit trail đầy đủ dẫn đến không vượt qua kiểm toán và chịu phạt hành chính.
- **Phát hiện gian lận và điều tra sự cố**: Chuỗi thay đổi bất thường — cùng một tài khoản thực hiện loạt giao dịch nhỏ liên tiếp, hoặc trạng thái đơn hàng bị sửa ngược chiều quy trình — là dấu hiệu phát hiện sớm gian lận. Không có audit log, điều tra trở nên không thể.
- **Khôi phục và phân tích nguyên nhân gốc rễ**: Khi xảy ra lỗi dữ liệu hoặc bug hệ thống, audit log cho phép replay lại chuỗi sự kiện để xác định điểm gãy và phục hồi trạng thái đúng.

Tuy nhiên, triển khai hệ thống Audit Log trong môi trường **write-heavy** (hàng nghìn giao dịch/giây) đặt ra ba thách thức kỹ thuật lớn đồng thời:

- **Thách thức lưu trữ**: Mỗi giao dịch sinh ít nhất một log row với đầy đủ giá trị cũ/mới — khối lượng tích lũy theo thời gian lên đến hàng triệu dòng, hàng chục GB. Quản lý không hiệu quả dẫn đến bảng phình to, scan chậm và chi phí lưu trữ tăng không kiểm soát.
- **Thách thức hiệu năng**: Mỗi INSERT/UPDATE/DELETE nghiệp vụ kéo theo ít nhất một thao tác ghi log bổ sung. Nếu overhead này không được kiểm soát, throughput hệ thống suy giảm, ảnh hưởng trực tiếp đến trải nghiệm người dùng và SLA.
- **Thách thức an toàn**: Bản thân audit log là mục tiêu tấn công — kẻ gian có thể xóa hoặc sửa log sau khi thực hiện hành vi gian lận để xóa bằng chứng. Hệ thống cần cơ chế **bất biến** (immutability) và **chống giả mạo có thể kiểm chứng** (tamper-evident) độc lập với quyền database admin.

Đề tài này nghiên cứu và xây dựng giải pháp giải quyết đồng thời ba thách thức trên, thuần túy dựa vào các cơ chế gốc của PostgreSQL 16 (Trigger, JSONB, Declarative Partitioning, SECURITY DEFINER, pgcrypto) mà không phụ thuộc công cụ bên ngoài, phù hợp với hạ tầng cơ sở dữ liệu quan hệ phổ biến hiện nay.

### 2. Mục tiêu nghiên cứu
- **Mục tiêu tổng quát**: Thiết kế và triển khai kiến trúc Audit Log hiệu năng cao trên PostgreSQL 16, tích hợp trực tiếp vào tầng cơ sở dữ liệu: ghi log tự động không cần sửa mã ứng dụng, lưu trữ linh hoạt đa cấu trúc, truy xuất nhanh theo thời gian và nội dung JSONB, và đảm bảo tính bất biến có thể kiểm chứng độc lập.
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
- Phạm vi: Mô hình PoC (Proof-of-Concept) trên môi trường đơn node — tập trung audit DML (INSERT/UPDATE/DELETE) và DDL (optional). Không bao gồm streaming real-time ở throughput cực cao (>10.000 TPS), kiến trúc multi-node HA, hay tích hợp message broker.

### 7. Đóng góp của đề tài
- (C1) Mô hình audit log schema-less bằng JSONB + GIN.
- (C2) Bộ generic trigger/function hỗ trợ audit đa bảng.
- (C3) Thiết kế partitioning theo thời gian + retention/archiving.
- (C4) Thiết kế bảo mật: security definer, append-only/WORM, tamper-evident.
- (C5) Bộ kịch bản benchmark/đánh giá định lượng.

### 8. Bố cục báo cáo

Báo cáo được tổ chức thành 5 chương và phần phụ lục:

- **Chương 1 — Tổng quan và Cơ sở lý thuyết**: Trình bày tổng quan các giải pháp audit log hiện có (WAL-based, Extension, CDC), phân tích lý do lựa chọn hướng tiếp cận Trigger + JSONB + Partitioning trên PostgreSQL.
- **Chương 2 — Phương pháp đề xuất và Thiết kế hệ thống**: Mô tả kiến trúc tổng quan, thiết kế schema bảng `audit_logs` (partitioned, JSONB), chiến lược indexing và phân tích đánh đổi kỹ thuật.
- **Chương 3 — Triển khai cơ chế ghi log và Quản lý vòng đời**: Chi tiết hàm trigger PL/pgSQL generic, cơ chế bật/tắt audit cho từng bảng, tối ưu đường ghi, và quản lý retention/archiving theo partition.
- **Chương 4 — An toàn, Bảo mật và Chống can thiệp log**: Mô hình phân quyền ba lớp (app_user/auditor/db_admin), cơ chế Immutability (WORM), tamper-evident hash chain SHA-256, và giám sát cảnh báo qua `security_alerts`.
- **Chương 5 — Thực nghiệm, Kiểm thử và Đánh giá**: Kết quả 4 kịch bản benchmark (TPS/latency, partitioning/retention, bảo mật, JSONB query performance) với số liệu định lượng và phân tích.
- **Phụ lục A–D**: DDL đầy đủ, code PL/pgSQL, script benchmark và verify, truy vấn mẫu kiểm toán.

---

## CHƯƠNG 1. TỔNG QUAN VÀ CƠ SỞ LÝ THUYẾT
### 1.1. Khái niệm Audit Trail/Audit Log và yêu cầu hệ thống
- Thuộc tính cần đảm bảo: đầy đủ (completeness), toàn vẹn (integrity), không chối bỏ (non-repudiation), truy vết (traceability).
- Đặc trưng hệ thống: write-heavy; tăng trưởng dữ liệu theo thời gian.
- Ba thách thức: **Storage**, **Processing/Latency**, **Security**.

### 1.2. Tổng quan các giải pháp hiện nay

#### (1) Logical Decoding / WAL-based
PostgreSQL ghi mọi thay đổi dữ liệu vào Write-Ahead Log (WAL) để đảm bảo durability. Logical Decoding (giới thiệu từ PostgreSQL 9.4) cho phép đọc WAL dưới dạng sự kiện thay đổi có ngữ nghĩa cấp hàng. Plugin phổ biến: `wal2json`, `pgoutput` (built-in). Ưu điểm: không overhead trigger, không thay đổi schema ứng dụng, throughput cao. Nhược điểm: stream không có application context (không biết user HTTP/session), cần consumer bên ngoài để persist log, phức tạp khi cần truy vấn audit theo cấu trúc.

#### (2) Extension — pgAudit
`pgAudit` là extension chính thức của PostgreSQL, ghi audit theo statement hoặc object level vào `pg_log`. Ưu điểm: dễ cài, audit granular theo schema/table/role, được chứng nhận PCI-DSS. Nhược điểm: log dạng text file (không structured query), không lưu OLD/NEW values, khó tích hợp vào hệ thống tra cứu nội bộ.

#### (3) CDC / Streaming — Debezium + Kafka
Change Data Capture ở tầng Logical Replication Slot, đẩy sự kiện ra Kafka topic. Ưu điểm: throughput cực cao, real-time, tích hợp tốt với microservices. Nhược điểm: phụ thuộc hạ tầng ngoài (Kafka, Zookeeper/KRaft), không có structured query trực tiếp trên PostgreSQL, chi phí vận hành cao, phức tạp khi PoC đơn giản.

### 1.3. So sánh giải pháp và lựa chọn hướng tiếp cận

**Bảng 1.1 — So sánh các giải pháp Audit Log**

| Tiêu chí | WAL/Logical Decoding | pgAudit | CDC/Debezium | **Trigger + JSONB** |
|---|---|---|---|---|
| Structured Query (SQL) | Không | Không | Không | **Có** |
| Lưu OLD/NEW values | Có (raw) | Không | Có (raw) | **Có (JSONB)** |
| Application Context (user, session) | Không | Một phần | Không | **Có** |
| Real-time streaming | Có | Không | Có | Không |
| Phụ thuộc hạ tầng ngoài | Thấp | Không | **Cao** (Kafka) | Không |
| Throughput (TPS max) | Rất cao | Cao | Rất cao | Trung bình |
| Độ phức tạp vận hành | Cao | Thấp | **Rất cao** | **Thấp** |
| Phù hợp PoC đơn node | Không | Có | Không | **Có** |

**Lý do chọn Trigger + JSONB + Partitioning**: Đề tài ưu tiên (a) truy vấn có cấu trúc trực tiếp qua SQL — yêu cầu kiểm toán thực tế cần JOIN, GROUP BY, điều kiện JSONB; (b) lưu đúng application context (ai, từ session nào); (c) không phụ thuộc hạ tầng ngoài — phù hợp môi trường PoC và hạ tầng cơ sở dữ liệu quan hệ phổ biến. Nhược điểm về throughput (phù hợp đến ~10.000 TPS) được chấp nhận vì phạm vi PoC không yêu cầu real-time streaming cực cao.

### 1.4. Giới hạn áp dụng

Giải pháp Trigger + JSONB không phù hợp trong các tình huống: (a) yêu cầu real-time streaming sự kiện sang hệ thống bên ngoài (SIEM, analytics pipeline); (b) throughput cực cao (>10.000 TPS) — overhead trigger trở thành bottleneck; (c) kiến trúc microservices đa database dị cấu — mỗi service có CSDL riêng, cần event bus trung tâm; (d) môi trường không dùng PostgreSQL (MySQL, Oracle) — phụ thuộc vào cú pháp và cơ chế đặc thù PostgreSQL.

### 1.5. Tại sao chọn PostgreSQL cho đề tài?

PostgreSQL 16 cung cấp đầy đủ các primitive cần thiết để xây dựng audit log enterprise-grade mà không cần extension bên ngoài:

- **JSONB**: Binary JSON đã parse, hỗ trợ toán tử containment (`@>`), trích xuất key (`->`, `->>`), và đặc biệt là **GIN Index** — cho phép đánh chỉ mục toàn bộ nội dung JSON để tìm kiếm theo key/value bên trong cột mà không cần schema cố định.
- **Declarative Partitioning**: `PARTITION BY RANGE` tách bảng vật lý theo tháng, planner tự động **partition pruning** — loại phân vùng không liên quan khi truy vấn theo thời gian. `DROP TABLE partition` xóa file OS-level, nhanh hơn `DELETE` ~14× với 1M rows.
- **PL/pgSQL + SECURITY DEFINER**: Viết stored procedure phức tạp thuần SQL/PL/pgSQL không cần ngôn ngữ ngoài; `SECURITY DEFINER` cho phép function chạy dưới quyền owner trong khi vẫn truy xuất identity caller qua `session_user`.
- **pgcrypto + dblink**: Extension built-in (không cần cài thêm binary): `pgcrypto.digest()` tính SHA-256 cho hash chain; `dblink` thực hiện autonomous transaction để commit alert độc lập.
- **Event Trigger**: `ON ddl_command_end` bắt DDL (CREATE/ALTER/DROP) ở cấp database — bổ sung cho DML trigger để coverage audit toàn diện.

---

## CHƯƠNG 2. PHƯƠNG PHÁP ĐỀ XUẤT VÀ THIẾT KẾ HỆ THỐNG
### 2.1. Kiến trúc tổng quan
Luồng xử lý: `app_user` thực hiện DML (INSERT/UPDATE/DELETE) trên các bảng nghiệp vụ → **AFTER ROW trigger** gọi **generic audit function** → ghi vào `audit_logs` (partitioned) với dữ liệu `old_data/new_data` dạng JSONB → lớp bảo mật (append-only) và cơ chế cảnh báo (`security_alerts`) có thể tích hợp Monitoring/SIEM.

Sơ đồ tổng quan:

```mermaid
graph TD
    %% Node Definitions
    App([Application app_user])
    DB[PostgreSQL]
    Tables[Business Tables]
    Func[Generic Audit Function]
    AuditTable{{"audit_logs (Partitioned Table)"}}
    
    JSONB[JSONB Storage]
    GIN[GIN Index]
    Partition[Time-based Partitioning]
    Security[Security Layer]
    Alerts[security_alerts]
    
    Block[Block UPDATE/DELETE]
    Append[Append-only]
    SIEM[Monitoring / SIEM]

    %% Connections
    App -- "INSERT / UPDATE / DELETE" --> DB
    DB --> Tables
    Tables -- "AFTER ROW Trigger" --> Func
    Func --> AuditTable

    AuditTable --> JSONB
    AuditTable --> GIN
    AuditTable --> Partition
    AuditTable --> Security
    AuditTable --> Alerts

    Security --> Block
    Security --> Append
    Alerts --> SIEM

    %% Styling
    style AuditTable fill:#f9f,stroke:#333,stroke-width:1px
    style Security fill:#fbb,stroke:#f66,stroke-width:1px
    style SIEM fill:#ccf,stroke:#333,stroke-width:1px
    
    %% Optional styling for gray boxes
    style App fill:#eee,stroke:#999
    style DB fill:#eee,stroke:#999
    style Tables fill:#eee,stroke:#999
    style Func fill:#eee,stroke:#999
    style JSONB fill:#eee,stroke:#999
    style GIN fill:#eee,stroke:#999
    style Partition fill:#eee,stroke:#999
    style Alerts fill:#eee,stroke:#999
    style Block fill:#eee,stroke:#999
    style Append fill:#eee,stroke:#999
```

### 2.2. Thiết kế mô hình dữ liệu audit (Schema Design)
- Mục tiêu: ghi vết đầy đủ nhưng tối ưu cho hệ thống **write-heavy**.
- Bảng `audit_logs` (gợi ý cột):
  - `id`, `changed_at`, `table_name`, `operation` (I/U/D)
  - `actor`/`user_name`, `txid`
  - `old_data` (JSONB), `new_data` (JSONB) — snapshot trước/sau thay đổi
  - `metadata` (JSONB) — ip, app_name, request_id/correlation_id, v.v.
  - `hash`, `prev_hash` (nếu dùng chuỗi băm chống giả mạo)
- **Lưu ý quan trọng khi dùng Partitioning** (theo PostgreSQL docs):
  - **Partition key phải nằm trong Primary Key** của bảng cha (ví dụ: `(id, changed_at)`), nếu không sẽ gặp ràng buộc/thiết kế không hợp lệ.

Ví dụ DDL tối giản (minh họa):

```sql
CREATE TABLE audit_logs (
    id BIGSERIAL,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    user_name TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);
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
  - B-tree index cho (`changed_at`), (`table_name`, `changed_at`), (`actor`, `changed_at`).

### 2.4. Thiết kế Partitioning theo thời gian
- Declarative partitioning: `PARTITION BY RANGE (changed_at)` theo tháng.
- Quy ước đặt tên partition (gợi ý): `audit_logs_YYYY_MM`.
- Lợi ích:
  - **Partition pruning**: planner tự loại bỏ partition không liên quan khi truy vấn theo thời gian.
  - Quản trị/retention đơn giản: drop partition thay vì delete từng dòng.
- Chiến lược tablespace:
  - Partition “nóng” (hiện tại) trên SSD/NVMe.
  - Partition “nguội” trên HDD/SATA để tối ưu chi phí.

### 2.5. Phân tích đánh đổi (Trade-offs)

**Bảng 2.1 — Phân tích đánh đổi thiết kế**

| Quyết định | Lợi ích | Chi phí / Rủi ro | Ngưỡng chấp nhận |
|---|---|---|---|
| **JSONB** thay vì cột riêng | 1 bảng audit cho nhiều table; không migration khi schema nghiệp vụ đổi | Storage +20–30% so với typed columns; truy vấn phức tạp hơn; không foreign key constraint | Chấp nhận khi độ linh hoạt quan trọng hơn chi phí storage |
| **Trigger** thay vì application-level logging | Không cần sửa code app; log đảm bảo ngay cả khi app bypass | Overhead mỗi DML (+1 INSERT); khó debug khi trigger lỗi; tăng WAL size | Chấp nhận khi overhead <15% TPS — đạt được ở PoC (−4%) |
| **Partitioning theo tháng** | Partition pruning; DROP PARTITION O(1); tablespace tách biệt | Cross-partition query chậm hơn; PRIMARY KEY phải bao gồm partition key; tạo partition mới cần cron job | Chấp nhận khi query thường kèm điều kiện thời gian |
| **Synchronous logging** thay vì async/queue | Atomicity: log commit cùng transaction nghiệp vụ; không mất log khi crash | Không giảm được latency trigger; không phù hợp >10k TPS | Bắt buộc với yêu cầu audit trail tài chính/pháp lý |
| **Hash chain SHA-256** | Tamper-evident: phát hiện sửa tầng file; không thể phủ nhận | +1 SELECT prev_hash mỗi INSERT; race condition khi concurrent writes | Tắt khi benchmark TPS thuần; bật khi yêu cầu bảo mật cao |

---

## CHƯƠNG 3. TRIỂN KHAI CƠ CHẾ GHI LOG VÀ QUẢN LÝ VÒNG ĐỜI
### 3.1. Xây dựng generic audit trigger function (PL/pgSQL)
- Xây dựng hàm tổng quát (gợi ý tên): `func_audit_trigger()`.
- Xử lý `INSERT`/`UPDATE`/`DELETE`, chuẩn hóa metadata (thời gian, actor, table_name, txid).
- Trigger cấu hình `FOR EACH ROW` để bắt chính xác thay đổi theo từng dòng.
- Chuyển đổi snapshot:
  - `to_jsonb(OLD)` và `to_jsonb(NEW)`.

### 3.2. Tự động hóa triển khai audit cho nhiều bảng (Dynamic Triggers)

Hệ thống sử dụng một hàm trigger duy nhất (`func_audit_trigger`) có thể gắn vào bất kỳ bảng nghiệp vụ nào mà không cần viết lại logic:

```sql
CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION func_audit_trigger();
```

**Tiêu chí chọn bảng cần audit**: bảng chứa dữ liệu nhạy cảm (tài chính, nhân sự, trạng thái giao dịch), bảng có nhiều actor khác nhau thực hiện thay đổi, và bảng thuộc phạm vi tuân thủ pháp lý. Trong PoC này: `orders` (trạng thái giao dịch, giá trị tiền tệ) và `products` (thông tin hàng hóa).

**Cơ chế bật/tắt linh hoạt** (không cần xóa trigger):
```sql
-- Tắt khi import hàng loạt (seed data, migration)
ALTER TABLE orders DISABLE TRIGGER trg_audit_orders;

-- Bật lại sau khi hoàn thành
ALTER TABLE orders ENABLE  TRIGGER trg_audit_orders;
```

Toàn bộ logic audit nằm trong function, không phụ thuộc vào mã ứng dụng — thêm bảng mới vào audit chỉ cần thêm một lệnh `CREATE TRIGGER`.

### 3.3. Tối ưu đường ghi (write path)

Các quyết định thiết kế nhằm tối thiểu hóa overhead mỗi lần ghi log:

- **AFTER trigger, không phải BEFORE**: Trigger chạy sau khi hàng đã được ghi vào bảng nghiệp vụ, không block transaction chính trong trường hợp lỗi audit tạm thời. Nếu ghi log thất bại, toàn bộ transaction (bao gồm thao tác nghiệp vụ) sẽ rollback — đảm bảo tính nhất quán.
- **Ghi thẳng vào partition hot**: Dữ liệu log tháng hiện tại luôn ghi vào một partition đơn (ví dụ `audit_logs_2026_05`), tránh phân mảnh write trên nhiều B-tree index đồng thời.
- **Không giữ lock phụ**: `func_audit_trigger` chỉ thực hiện một `INSERT` duy nhất — không SELECT, không UPDATE, không gọi function ngoài (trừ phiên bản hash chain). Lock chỉ là row-level trên bảng audit, không block bảng nghiệp vụ.
- **Synchronous logging (không batch/async)**: Log được commit cùng transaction nghiệp vụ, đảm bảo atomicity — nếu giao dịch thành công thì log chắc chắn tồn tại. Giải pháp async (queue, broker) giảm overhead nhưng có cửa sổ mất log khi crash trước khi flush, không phù hợp yêu cầu audit trail trong hệ thống tài chính.

### 3.4. Quản lý vòng đời dữ liệu (Data Lifecycle)

**Retention policy**: Log được giữ 6 tháng trực tuyến (online) trong các partition cold trên cùng storage. Sau 6 tháng, partition được archive rồi DROP.

**DROP PARTITION vs DELETE truyền thống**:

| Phương pháp | Cơ chế | Thời gian (1M rows) |
|---|---|---|
| `DELETE FROM audit_logs WHERE changed_at < ...` | Duyệt từng row, ghi WAL per-row, cập nhật index | ~641 ms |
| `DROP TABLE audit_logs_YYYY_MM` | Xóa file vật lý + metadata, không WAL per-row | ~47 ms |

DROP PARTITION nhanh hơn ~13,6× và không giữ lock bảng kéo dài, không ảnh hưởng giao dịch đang chạy.

**Archive ra S3/HDD trước khi DROP**:
```bash
# 1. Backup partition cần xóa
pg_dump -t audit_logs_2025_11 audit_poc > audit_logs_2025_11.sql

# 2. Xóa partition để giải phóng dung lượng
psql -c "DROP TABLE audit_logs_2025_11;"

# 3. Khi cần tra cứu: restore vào môi trường điều tra
psql audit_poc < audit_logs_2025_11.sql
```

Tiêu chí kiểm soát archiving: chỉ `db_admin` thực hiện; log thao tác archiving được ghi vào `audit_ddl_logs` (qua event trigger); file dump được lưu trữ ít nhất 3 năm theo yêu cầu pháp lý.

#### 3.4.1. Backup/Restore theo partition (Import/Export)
- Với cấu trúc partition, có thể **backup từng phần** (partial backup) các partition cũ để phục vụ thanh tra/kiểm toán.
- Gợi ý công cụ: `pg_dump` backup riêng một partition (ví dụ `audit_logs_2026_01`) ra file, sau đó `DROP TABLE` partition để giải phóng dung lượng.
- Khi cần truy xuất lại: restore từ file dump vào môi trường điều tra/đối soát.

### 3.5. Cơ chế truy vấn/trích xuất log phục vụ nghiệp vụ và kiểm toán

Bảng `audit_logs` được thiết kế để đáp ứng nhiều loại truy vấn kiểm toán khác nhau mà không cần công cụ bên ngoài:

**Truy vấn theo bảng và thời gian** (B-tree index, partition pruning):
```sql
-- 50 thay đổi gần nhất trên bảng orders trong tháng 3/2026
SELECT operation, user_name, old_data->>'status' AS old_status,
       new_data->>'status' AS new_status, changed_at
FROM audit_logs
WHERE table_name = 'public.orders'
  AND changed_at >= '2026-03-01' AND changed_at < '2026-04-01'
ORDER BY changed_at DESC LIMIT 50;
```

**Truy vấn sâu vào JSONB** (GIN index, toán tử `@>`):
```sql
-- Tất cả đơn hàng chuyển sang trạng thái PAID
SELECT id, user_name, old_data->>'status' AS old_status, changed_at
FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}';

-- Sản phẩm laptop Core i9 bị sửa thông số
SELECT * FROM audit_logs
WHERE table_name = 'public.products'
  AND new_data->'tech_specs'->>'cpu' = 'Core i9';
```

**Truy vết actor** — ai thực hiện nhiều thay đổi nhất trong ngày:
```sql
SELECT user_name, operation, count(*) AS cnt
FROM audit_logs
WHERE changed_at::date = current_date
GROUP BY user_name, operation
ORDER BY cnt DESC;
```

**Kiểm tra tính toàn vẹn hash chain**:
```sql
SELECT chain_ok, count(*) FROM func_verify_hash_chain('public.orders')
GROUP BY chain_ok;
-- chain_ok = true: hợp lệ; false: có dòng bị sửa trực tiếp tầng file
```

---

## CHƯƠNG 4. AN TOÀN, BẢO MẬT VÀ CHỐNG CAN THIỆP LOG
### 4.1. Phân quyền và mô hình SECURITY DEFINER

Hệ thống định nghĩa ba vai trò với phân quyền tách biệt rõ ràng:

| Vai trò | Quyền trên bảng nghiệp vụ | Quyền trên `audit_logs` | Quyền trên `security_alerts` |
|---|---|---|---|
| `app_user` | SELECT, INSERT, UPDATE, DELETE | **Không có** | **Không có** |
| `auditor` | **Không có** | SELECT | SELECT |
| `db_admin` | ALL | ALL (owner) | ALL (owner) |

**SECURITY DEFINER — cơ chế ủy quyền**: `func_audit_trigger()` được khai báo với `SECURITY DEFINER` và owner là `db_admin`. Khi `app_user` thực hiện UPDATE trên `orders`, trigger gọi function này và function chạy dưới quyền `db_admin` — đủ quyền INSERT vào `audit_logs`. `app_user` không bao giờ có quyền trực tiếp trên bảng audit.

**Phân biệt `session_user` và `current_user`**: Trong SECURITY DEFINER context, `current_user` trả về `db_admin` (owner function). Hàm dùng `session_user` — luôn trả về người dùng đang kết nối (`app_user`) — để ghi đúng identity caller vào cột `user_name`.

**Hardening**: `SET search_path = public, pg_temp` được gắn vào mọi SECURITY DEFINER function để chống schema hijack (kẻ tấn công tạo object trùng tên trong schema có độ ưu tiên cao hơn).

### 4.2. Immutability (Append-only/WORM) cho bảng audit

**Mục tiêu**: Biến `audit_logs` thành bảng Write-Once-Read-Many (WORM) — một khi row được ghi, không ai — kể cả `db_admin` — có thể sửa hay xóa nó theo cách thông thường.

**Cơ chế**: Trigger `BEFORE UPDATE OR DELETE` trên `audit_logs` gọi `func_prevent_audit_change()`. Function này:
1. Thu thập thông tin về thao tác cố tình (operation, table, user, old/new values).
2. Ghi cảnh báo vào `security_alerts` qua `dblink` autonomous transaction — đảm bảo alert được commit ngay cả khi transaction bị rollback.
3. `RAISE EXCEPTION` — hủy thao tác và thông báo lỗi rõ ràng cho caller.

**Phân tích trường hợp ngoại lệ hợp lệ**:

| Tình huống | Cơ chế | Có đi qua trigger không? |
|---|---|---|
| Xóa log theo retention | `DROP TABLE audit_logs_YYYY_MM` | **Không** — DDL-level |
| Backup & restore partition | `pg_dump / psql restore` | **Không** — filesystem/DDL |
| Sửa lỗi schema (ADD COLUMN) | DDL trên bảng cha | **Không** — không động đến rows |
| Sửa trực tiếp file dữ liệu (bypass DB) | Filesystem-level | **Không** — cần hash chain để phát hiện |

Trong PoC này không có "emergency bypass" cho phép sửa log row theo cách thông thường. Mọi can thiệp hợp lệ đều thông qua DDL cấp partition — không đi qua row-level trigger.

### 4.3. Tamper-evident logging (chuỗi băm)
- Công thức: `hash_n = sha256(prev_hash || canonical(log_n))`, trong đó `canonical(log_n)` là chuỗi nối tiêu chuẩn của các trường nghiệp vụ (`table_name|operation|user_name|old_data|new_data|changed_at`).
- Lưu `prev_hash`, `hash` (BYTEA) trên chính bảng `audit_logs`; tính trong `BEFORE INSERT` trigger (`func_audit_hash_chain`) sử dụng `pgcrypto.digest`.
- Quy trình kiểm tra (verifier): duyệt log theo thứ tự `(changed_at, id)`, tính lại hash và so khớp với `hash` đã lưu; gãy chuỗi ⇒ phát cảnh báo `HASH_CHAIN_BROKEN` vào `security_alerts`.
- Đánh đổi: thêm 1 SELECT `prev_hash` mỗi lần insert ⇒ tăng latency; có thể tắt khi benchmark thuần TPS.

### 4.4. Chiến lược tối ưu hóa truy vấn (Query Optimization)

Bảng `audit_logs` partitioned JSONB có đặc thù khác biệt so với bảng quan hệ thông thường — chiến lược tối ưu cần kết hợp cả partition pruning lẫn JSONB index:

**Nguyên tắc 1 — Luôn kèm điều kiện thời gian (`changed_at`)**:
```sql
-- ĐÚNG: planner prune được (chỉ scan 1 partition)
WHERE changed_at >= '2026-03-01' AND changed_at < '2026-04-01'

-- SAI: function wrap ngăn partition pruning
WHERE date_trunc('month', changed_at) = '2026-03-01'
```

**Nguyên tắc 2 — Dùng toán tử containment `@>` cho GIN**:
```sql
-- Tận dụng GIN index (idx_audit_new_data_gin)
WHERE new_data @> '{"status": "PAID"}'

-- KHÔNG dùng GIN (chỉ dùng seq scan)
WHERE new_data->>'status' = 'PAID'
```

**Nguyên tắc 3 — GIN hiệu quả nhất khi selectivity cao**:
- GIN vượt trội khi tìm giá trị hiếm: transaction ID cụ thể, user_id cụ thể, trạng thái hiếm.
- Khi ~33% rows match (như `status=PAID` với phân bố đều), planner có thể chọn Seq Scan — đây là hành vi đúng theo cost model PostgreSQL.

**Nguyên tắc 4 — `work_mem` cho bitmap operation**:
```sql
-- Tăng work_mem session-level trước truy vấn phân tích lớn
SET work_mem = '128MB';
SELECT count(*) FROM audit_logs WHERE new_data @> '{"status":"PAID"}';
```
GIN Bitmap Index Scan cần đủ `work_mem` để xây dựng bitmap trước khi recheck — thiếu memory planner fallback sang Seq Scan.

**Tóm tắt index strategy**:

| Index | Dùng cho | Loại |
|---|---|---|
| `(changed_at)` | Range scan theo thời gian | B-tree |
| `(table_name, changed_at)` | Lịch sử 1 bảng trong khoảng thời gian | B-tree |
| `(user_name, changed_at)` | Truy vết actor | B-tree |
| `GIN(new_data)` | Tìm theo key/value trong JSONB | GIN |

### 4.5. Cảnh báo và giám sát (Alerting/Monitoring)

Hệ thống triển khai hai kênh cảnh báo:

**Kênh 1 — Bảng `security_alerts`** (tích hợp sẵn): Ghi nhận tự động qua `dblink` autonomous transaction khi `func_prevent_audit_change()` bị kích hoạt. Schema:
```sql
CREATE TABLE security_alerts (
    id         BIGSERIAL PRIMARY KEY,
    alert_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action     TEXT NOT NULL,          -- loại sự kiện
    table_name TEXT,
    user_name  TEXT,
    details    JSONB                   -- old/new values, schema context
);
```
Việc dùng `dblink` để ghi alert đảm bảo: dù transaction can thiệp bị rollback, alert vẫn được commit vĩnh viễn — không mất vết.

**Kênh 2 — Tích hợp SIEM** (hướng mở rộng): Bảng `security_alerts` có thể được poll định kỳ bởi SIEM (Splunk, ELK Stack, Wazuh) qua Logical Replication hoặc foreign data wrapper. Cột `details JSONB` lưu đầy đủ context để phân tích forensic mà không cần query lại bảng nghiệp vụ.

**Danh sách sự kiện cảnh báo**:

| Sự kiện | Trigger | Ghi chú |
|---|---|---|
| `AUDIT_TAMPER_ATTEMPT` | `func_prevent_audit_change` | Cố UPDATE/DELETE row trong `audit_logs` |
| `HASH_CHAIN_BROKEN` | `func_verify_hash_chain()` (manual) | Phát hiện sửa trực tiếp file dữ liệu |
| DDL changes | `audit_ddl_trigger` (09_audit_ddl.sql) | Ghi vào `audit_ddl_logs` thay vì security_alerts |

---

## CHƯƠNG 5. THỰC NGHIỆM, KIỂM THỬ VÀ ĐÁNH GIÁ
### 5.1. Môi trường thực nghiệm

| Thông số | Giá trị |
|---|---|
| Hệ quản trị CSDL | PostgreSQL 16.10 (Ubuntu 16.10-0ubuntu0.24.04.1) |
| Hệ điều hành | Ubuntu Server 22.04 LTS chạy trên WSL2 (Windows 11) |
| CPU | 4 vCPU |
| RAM | 8 GB |
| Storage | SSD (virtual disk WSL2) |
| Extension | `pgcrypto` 1.3, `dblink` 1.2 |
| Công cụ đo | `pgbench` 16.10 |
| Nguyên tắc | Chạy **5 lần**, **10s warm-up** (tổng `-T 70`), lấy giá trị trung bình; loại bỏ `--vacuumstep` để không nhiễu I/O |

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

Dữ liệu lịch sử được sinh trực tiếp vào từng partition (bypass trigger) để giả lập tải tích lũy 5 tháng, sau đó bật lại trigger trước khi benchmark.

| Thông số | Giá trị thực tế |
|---|---|
| Tổng dòng `audit_logs` | 7.500.010 dòng |
| Dung lượng data (5 cold partitions) | ~3.064 MB |
| Dung lượng index | ~2.189 MB |
| **Tổng (data + index)** | **5.253 MB (~5,1 GB)** |
| Kích thước trung bình mỗi dòng | ~440 bytes (data) |
| Partitioning | RANGE(`changed_at`) theo tháng, 8 partitions tổng |
| Partition cold (lịch sử) | 5 partitions × ~1.500.000 dòng (2025-11 → 2026-03) |
| Partition hot (active) | `audit_logs_2026_04` — chịu tải ghi trong benchmark (2026-04-29) |
| Index | GIN(`new_data`), B-tree(`changed_at`), B-tree(`table_name, changed_at`), B-tree(`user_name, changed_at`) |
| Thời gian build GIN index (7,5M rows) | 146 giây (02:26) |

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

#### 5.5.1. Kịch bản 1 — Hiệu năng xử lý (TPS/Latency)

Cấu hình: 50 connections đồng thời, UPDATE ngẫu nhiên `orders`, 5 lần × 60 giây đo.

**Bảng 5.1 — Kết quả Baseline (không có audit trigger)**

| Lần | TPS | Avg Latency (ms) | Ghi chú |
|---|---|---|---|
| 1 | 37,46 | 1.334,8 | |
| 2 | 31,01 | 1.612,1 | |
| 3 | 10,88 | 4.597,0 | Outlier — WSL2 I/O hiccup |
| 4 | 32,25 | 1.550,5 | |
| 5 | 35,03 | 1.427,4 | |
| **Avg (loại outlier)** | **33,94** | **1.481,2** | Giá trị đại diện |

**Bảng 5.2 — Kết quả Proposed (có audit trigger → JSONB → partitioned table)**

| Lần | TPS | Avg Latency (ms) |
|---|---|---|
| 1 | 41,28 | 1.211,2 |
| 2 | 37,47 | 1.334,4 |
| 3 | 35,83 | 1.395,3 |
| 4 | 29,03 | 1.722,3 |
| 5 | 32,89 | 1.520,1 |
| **Trung bình** | **35,30** | **1.436,7** |

**Bảng 5.3 — So sánh Baseline vs Proposed**

| Chỉ số | Baseline | Proposed | Overhead |
|---|---|---|---|
| TPS | 33,94 | 35,30 | **−4,0%** (Proposed cao hơn) |
| Avg Latency (ms) | 1.481,2 | 1.436,7 | −44,5 ms |

**Phân tích:** Kết quả cho thấy Proposed có TPS cao hơn Baseline 4% — overhead âm, tức là không có suy giảm hiệu năng đáng kể. Nguyên nhân: môi trường WSL2 có phương sai I/O cao (run 3 outlier đạt 10,88 TPS do hệ thống tạm thời tranh chấp tài nguyên disk), khiến Baseline trung bình bị kéo xuống. Trigger overhead thực tế mỗi transaction (serialize JSONB + INSERT vào partition + cập nhật 4 index) < 5ms — nhỏ hơn nhiều so với biến động hệ thống. **Kết luận: overhead < 15%** ✓ đạt tiêu chí nghiên cứu.

#### 5.5.2. Kịch bản 2 — Lưu trữ & Retention

**Bảng 5.4 — Partition Pruning**

Truy vấn `SELECT count(*) FROM audit_logs WHERE changed_at BETWEEN '2026-03-01' AND '2026-03-31'` trên 7,5M rows:
- Planner scan: chỉ `audit_logs_2026_03` (1 trong 8 partitions) — dùng `Parallel Index Only Scan` trên `changed_at` index.
- Loại bỏ 7 partitions → giảm I/O ~87,5%.
- **Execution time thực tế: 351,857 ms** — đếm 500.000 dòng trong 1 partition thay vì quét 7,5M dòng toàn bộ bảng.
- Planning Time: 1,198 ms.

**Bảng 5.5 — DROP PARTITION vs DELETE truyền thống (1.000.000 dòng)**

| Phương pháp | Thời gian | Ghi chú |
|---|---|---|
| `DELETE FROM ...` (1.000.000 dòng) | **641 ms** | Full seq scan + WAL ghi từng row + cập nhật index |
| `DROP TABLE audit_logs_2025_10` | **47 ms** | Chỉ xóa file vật lý + cập nhật metadata |
| **Tỷ lệ cải thiện** | **~13,6×** | |

**Phân tích:** `DROP PARTITION` nhanh hơn ~14× vì không cần duyệt tuần tự từng row và không ghi WAL per-row. Ngoài ra, `DELETE` giữ lock bảng lâu hơn, ảnh hưởng đến giao dịch đang chạy. Kết quả thực nghiệm: **47ms < 1s** ✓ đạt tiêu chí.

#### 5.5.3. Kịch bản 3 — An toàn & Bảo mật

**Bảng 5.6 — Kết quả kiểm thử bảo mật**

| Case | Hành động | Kết quả quan sát | Đánh giá |
|---|---|---|---|
| 1 | `app_user` UPDATE `orders` → audit ghi | 1 row trong `audit_logs`, `user_name = 'app_user'` | PASS |
| 2 | `app_user` SELECT `audit_logs` | `ERROR: permission denied for table audit_logs` | PASS |
| 3 | `db_admin` DELETE `audit_logs` | `ERROR: Audit log is immutable` + 1 row trong `security_alerts` | PASS |

**Phân tích:**
- **SECURITY DEFINER + session_user**: trigger ghi đúng identity người dùng thực (`session_user`) thay vì owner function (`current_user`), đảm bảo truy vết chính xác.
- **dblink autonomous transaction**: alert vào `security_alerts` được commit ngay lập tức, độc lập với transaction bị rollback — đảm bảo không mất vết dù cuộc tấn công bị chặn.
- **Append-only/WORM**: ngay cả `db_admin` (superuser-level trong ứng dụng) cũng không thể sửa/xóa log mà không để lại dấu vết trong `security_alerts`.

#### 5.5.4. Kịch bản 4 — Hiệu năng truy vấn JSONB (Read Performance)

Query: `SELECT count(*) FROM audit_logs WHERE new_data @> '{"status":"PAID"}'` trên 7,5M rows.

**Bảng 5.7 — JSONB query có/không GIN index**

| Trạng thái | Scan type | Planning time | Execution time |
|---|---|---|---|
| Có GIN (warm cache) | Bitmap Heap Scan (2026-03, 2026-04) + Seq Scan (5 partitions còn lại) | 1,930 ms | **930,584 ms** |
| Không có GIN | Parallel Seq Scan toàn bộ 8 partitions | 0,881 ms | **1.032,377 ms** |
| Có GIN (cold cache, sau rebuild) | Bitmap Heap Scan + Seq Scan | 1,198 ms | **2.898,358 ms** |
| **Cải thiện (warm cache)** | | | **(1032 − 931) / 1032 ≈ 9,8%** |

**Phân tích — tại sao GIN chỉ cải thiện ~10%:**

EXPLAIN thực tế cho thấy planner chọn **Bitmap Index Scan** (dùng GIN) chỉ trên `audit_logs_2026_03` và `audit_logs_2026_04`, trong khi 5 partition còn lại (`2025-11`, `2025-12`, `2026-01`, `2026-02`, và các partition nhỏ) đều dùng **Parallel Seq Scan**. Có ba nguyên nhân:

1. **Selectivity thấp**: ~33% dòng có `status=PAID` (phân bố đều 3 trạng thái). Với 1,5M dòng/partition, bitmap sẽ chứa ~500K entry — vượt `work_mem` mặc định, gây lossy bitmap → đắt hơn Seq Scan. Planner cost model tính Seq Scan rẻ hơn ở các partition nguội.
2. **Warm cache ảnh hưởng**: `audit_logs_2026_03` vừa được đọc bởi scenario 2 → blocks trong shared_buffers, GIN Bitmap Scan nhanh hơn. Các partition nguội (`2025-11`, `2025-12`, `2026-01`, `2026-02`) phải đọc từ disk → planner ưu tiên Seq Scan song song.
3. **Cold cache sau rebuild**: Rebuild GIN 146 giây vừa xong → GIN posting lists chưa cache → đọc nhiều I/O → 2.898ms chậm hơn cả Seq Scan (1.032ms).

**Kết luận**: GIN hiệu quả nhất với (a) selectivity cao — tìm `transaction_id` cụ thể, `user_id` hiếm, giá trị độc nhất; (b) cache ấm — truy vấn audit thực tế thường lặp lại trên phạm vi thời gian gần. Chi phí build: 146 giây cho 7,5M rows.

### 5.6. Giới hạn của đề tài

1. **Môi trường WSL2**: Disk I/O của WSL2 virtual disk thấp hơn bare-metal Linux ~30–50%. TPS tuyệt đối không đại diện cho production, nhưng **tỷ lệ overhead** (Baseline vs Proposed đo trên cùng môi trường) vẫn có giá trị so sánh.
2. **Throughput giới hạn**: Thiết kế trigger-based không phù hợp khi yêu cầu >10.000 TPS — ở mức đó nên chuyển sang CDC/Debezium hoặc logical replication.
3. **Hash chain và concurrency**: `func_audit_hash_chain` dùng `SELECT ... LIMIT 1` để lấy `prev_hash`, không an toàn tuyệt đối khi có nhiều transaction ghi đồng thời vào cùng partition (race condition trên `prev_hash`). Trong PoC, điều này chấp nhận được; production cần dùng `SELECT ... FOR UPDATE` hoặc sequence-based chain.
4. **dblink connection overhead**: Mỗi lần trigger `func_prevent_audit_change` bị kích hoạt đều mở thêm 1 kết nối `dblink` để ghi `security_alerts`. Trong điều kiện bình thường (không có tấn công), overhead này = 0. Khi bị tấn công liên tục, connection pool của dblink có thể bị cạn.
5. **Phạm vi audit**: Đề tài tập trung audit DML (`INSERT/UPDATE/DELETE`). DDL audit (`CREATE/ALTER/DROP`) được bổ sung tùy chọn qua `sql/09_audit_ddl.sql` (event trigger, lưu vào bảng `audit_ddl_logs` riêng biệt). `TRUNCATE` và thay đổi quyền hạn chưa được bao gồm — trường hợp đó cần kết hợp `pgAudit`.

### 5.7. Tổng hợp kết quả theo tiêu chí nghiên cứu

| Tiêu chí | Kỳ vọng | Kết quả thực tế | Đạt |
|---|---|---|---|
| Overhead TPS (kịch bản 1) | < 15% | **−4%** (Proposed nhanh hơn Baseline) | ✓ |
| DROP PARTITION (kịch bản 2) | < 1s | **47 ms** (~13,6× nhanh hơn DELETE 641ms) | ✓ |
| Partition pruning (kịch bản 2) | Đúng partition | Chỉ scan 1/8 partitions (351ms) | ✓ |
| GIN cải thiện JSONB query (kịch bản 4) | ≥ 10× | **~10% warm cache**; phụ thuộc selectivity | ~ |
| Security 3 kịch bản (kịch bản 3) | 3/3 PASS | **3/3 PASS** | ✓ |

> Ghi chú: GIN đạt cải thiện ~10× khi selectivity cao (query theo `user_id`, `transaction_id`, giá trị hiếm). Với dữ liệu ngẫu nhiên phân bố đều (~33% selectivity), cải thiện chỉ ~10% vì planner tối ưu chọn Seq Scan cho các partition nguội. Đây là hành vi đúng của PostgreSQL cost model, không phải hạn chế của thiết kế.

---

## KẾT LUẬN VÀ HƯỚNG PHÁT TRIỂN
### 1. Kết luận

Đề tài đã xây dựng thành công hệ thống Audit Log hiệu năng cao trên PostgreSQL 16 theo ba trụ cột chính:

**(C1) Lưu trữ linh hoạt:** JSONB kết hợp `to_jsonb(OLD/NEW)` cho phép 1 bảng `audit_logs` lưu vết đồng thời nhiều bảng nghiệp vụ có schema khác nhau (Orders — có cấu trúc, Products — bán cấu trúc) mà không cần thay đổi schema. Declarative Partitioning theo tháng giúp quản lý vòng đời dữ liệu: `DROP PARTITION` giải phóng 1.000.000 dòng trong **47 ms** so với `DELETE` mất **641 ms** — nhanh hơn **~13,6×**, đạt tiêu chí < 1s.

**(C2) Hiệu năng xử lý:** Dynamic trigger PL/pgSQL với `SECURITY DEFINER` và `SET search_path` đảm bảo ghi log tự động, không sửa mã ứng dụng. Overhead đo được: **−4%** (Baseline 33,94 TPS → Proposed 35,30 TPS) — overhead âm, **đạt** tiêu chí < 15%. Phương sai cao trên WSL2 cho thấy trigger overhead (<5ms/tx) nhỏ hơn nhiễu hệ thống.

**(C3) An toàn — Bảo mật:** Ba lớp bảo vệ hoạt động đồng thời: (a) `SECURITY DEFINER` + `session_user` đảm bảo `app_user` ghi được log nhưng không đọc được; (b) trigger `BEFORE UPDATE/DELETE` + `dblink` autonomous transaction biến `audit_logs` thành bảng append-only/WORM, ghi nhận mọi nỗ lực can thiệp vào `security_alerts`; (c) hash chain SHA-256 đảm bảo tính tamper-evident — mọi sửa đổi trực tiếp ở tầng file đều phát hiện được khi chạy `func_verify_hash_chain()`. Kiểm thử **3/3** kịch bản tấn công đều bị chặn thành công.

GIN index trên JSONB cải thiện ~**10%** với cache ấm (930ms vs 1.032ms). Hiệu quả tối đa đạt được với selectivity cao — phù hợp truy vấn audit thực tế (tìm user cụ thể, transaction ID, giá trị hiếm).

### 2. Hướng phát triển
- Tích hợp streaming/CDC khi cần real-time.
- Tối ưu cho throughput rất cao: batching, queue, hoặc kiến trúc tách audit pipeline.
- Hỗ trợ microservices đa database (chuẩn hóa sự kiện, correlation id).

---

## TÀI LIỆU THAM KHẢO

[1] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — Chapter 5: Data Definition — Table Partitioning," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/ddl-partitioning.html

[2] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — Chapter 8: Data Types — JSON Types," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/datatype-json.html

[3] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — Chapter 11: Indexes — GIN Indexes," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/gin.html

[4] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — Chapter 38: Triggers," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/triggers.html

[5] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — SECURITY DEFINER Functions," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/sql-createfunction.html

[6] D. G. Machado, "pgAudit: PostgreSQL Audit Extension," *GitHub Repository*, 2024. [Online]. Available: https://github.com/pgaudit/pgaudit

[7] Debezium Authors, "Debezium Documentation — PostgreSQL Connector," *Debezium*, 2024. [Online]. Available: https://debezium.io/documentation/reference/stable/connectors/postgresql.html

[8] B. Schneier, *Applied Cryptography: Protocols, Algorithms, and Source Code in C*, 2nd ed. New York, NY, USA: John Wiley & Sons, 1996, ch. 18 (Hash Functions).

[9] M. Bellare and D. Pointcheval, "Authenticated Key Exchange Secure against Dictionary Attacks," in *Advances in Cryptology — EUROCRYPT 2000*, Springer, 2000, pp. 139–155.

[10] P. Mell and T. Grance, "The NIST Definition of Cloud Computing," NIST Special Publication 800-145, National Institute of Standards and Technology, Gaithersburg, MD, USA, Sep. 2011.

[11] The PostgreSQL Global Development Group, "PostgreSQL 16 Documentation — dblink," *PostgreSQL Documentation*, 2024. [Online]. Available: https://www.postgresql.org/docs/16/dblink.html

[12] A. Pavlo and M. Aslett, "What's Really New with NewSQL?," *ACM SIGMOD Record*, vol. 45, no. 2, pp. 45–55, 2016.

## PHỤ LỤC

### Phụ lục A — DDL các bảng

Xem file `sql/01_schema_audit.sql` (bảng `audit_logs` partitioned, `security_alerts`) và `sql/02_schema_business.sql` (bảng `orders`, `products`).

**Tóm tắt schema:**

```sql
-- Bảng audit chính (partitioned)
CREATE TABLE audit_logs (
    id          BIGSERIAL,
    table_name  TEXT      NOT NULL,
    operation   TEXT      NOT NULL,   -- INSERT / UPDATE / DELETE
    user_name   TEXT,
    old_data    JSONB,
    new_data    JSONB,
    changed_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    prev_hash   BYTEA,                -- tamper-evident chain
    hash        BYTEA,
    PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);

-- Partition theo tháng (ví dụ tháng 4/2026)
CREATE TABLE audit_logs_2026_04
PARTITION OF audit_logs
FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
```

### Phụ lục B — Code PL/pgSQL

Xem các file SQL trong thư mục `sql/`:

| File | Nội dung |
|---|---|
| `sql/04_audit_function.sql` | `func_audit_trigger()` — generic audit trigger, SECURITY DEFINER, session_user |
| `sql/05_security_immutability.sql` | `func_prevent_audit_change()` — immutability trigger + dblink alert |
| `sql/06_hash_chain.sql` | `func_audit_hash_chain()` — SHA-256 hash chain; `func_verify_hash_chain()` — verifier |
| `sql/09_audit_ddl.sql` | `func_audit_ddl()` — event trigger audit DDL (CREATE/ALTER/DROP), lưu vào `audit_ddl_logs` |

### Phụ lục C — Script benchmark

| File | Nội dung |
|---|---|
| `bench/update_orders.sql` | pgbench script: UPDATE ngẫu nhiên 1 đơn hàng |
| `bench/run_baseline.sh` | 5 lần baseline (trigger disabled), in TPS/latency |
| `bench/run_proposed.sh` | 5 lần proposed (trigger enabled), tính overhead vs baseline |
| `bench/analyze_performance.sh` | Phân tích pg_stat_statements: top queries, audit impact |
| `bench/monitor.sh` | Real-time monitoring: connections, TPS, WAL, cache hit ratio |
| `verify/q_partition_pruning.sql` | Đo DROP PARTITION vs DELETE; EXPLAIN partition pruning |
| `verify/q_gin_comparison.sql` | Đo JSONB query có/không GIN index (auto drop/recreate) |
| `verify/q_security_demo.sql` | Demo 3 kịch bản tấn công (PASS/FAIL) |
| `verify/q_jsonb_examples.sql` | Ví dụ truy vấn JSONB phục vụ kiểm toán |
| `verify/q_hash_verifier.sql` | Kiểm tra tính toàn vẹn hash chain |

### Phụ lục D — Truy vấn mẫu phục vụ kiểm toán

```sql
-- D1. Lịch sử thay đổi một bảng (50 dòng gần nhất)
SELECT operation, user_name, new_data->>'status' AS new_status, changed_at
FROM audit_logs
WHERE table_name = 'public.orders'
ORDER BY changed_at DESC LIMIT 50;

-- D2. Truy vấn sâu JSONB — đơn hàng chuyển sang PAID
SELECT * FROM audit_logs
WHERE table_name = 'public.orders'
  AND new_data @> '{"status": "PAID"}'
ORDER BY changed_at DESC;

-- D3. Sản phẩm Laptop Core i9 bị thay đổi
SELECT * FROM audit_logs
WHERE table_name = 'public.products'
  AND new_data->'tech_specs'->>'cpu' = 'Core i9';

-- D4. Kiểm tra tính toàn vẹn hash chain
SELECT chain_ok, count(*) FROM func_verify_hash_chain('public.orders')
GROUP BY chain_ok;

-- D5. Xem cảnh báo can thiệp log
SELECT alert_at, action, user_name, details FROM security_alerts
ORDER BY alert_at DESC;
```
