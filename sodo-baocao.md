# Các sơ đồ bổ sung cho Báo cáo (Mermaid)

Dưới đây là các sơ đồ được thiết kế dựa trên nội dung của báo cáo `6-baocao.md`. Bạn có thể sao chép trực tiếp các đoạn mã Mermaid này và dán vào báo cáo để minh họa trực quan hơn cho các cơ chế kỹ thuật.

## 1. Sơ đồ tuần tự: Luồng xử lý ghi Audit Log (Sequence Diagram)
**Vị trí đề xuất**: Phần `3.1. Xây dựng generic audit trigger function` hoặc `2.1. Kiến trúc tổng quan`.
**Ý nghĩa**: Minh họa cách thao tác nghiệp vụ kích hoạt Trigger, quyền SECURITY DEFINER và quá trình ghi nhận log một cách đồng bộ trong cùng một transaction.

```mermaid
sequenceDiagram
    autonumber
    participant App as Ứng dụng (app_user)
    participant BT as Bảng nghiệp vụ (orders, products)
    participant Trg as func_audit_trigger<br/>(SECURITY DEFINER)
    participant Hash as func_audit_hash_chain<br/>(BEFORE INSERT)
    participant AL as Bảng audit_logs<br/>(Partition hiện tại)
    
    App->>BT: Thực hiện DML (INSERT / UPDATE / DELETE)
    activate BT
    
    BT->>Trg: Kích hoạt AFTER ROW Trigger
    activate Trg
    Note right of Trg: Chuyển sang quyền db_admin<br/>Lấy định danh thực session_user<br/>Chuyển đổi OLD/NEW sang JSONB
    
    Trg->>AL: Thực hiện lệnh INSERT log
    activate AL
    
    AL->>Hash: Kích hoạt BEFORE INSERT Trigger (Hash chain)
    activate Hash
    Hash->>AL: SELECT prev_hash (LIMIT 1)
    AL-->>Hash: Trả về prev_hash
    Note right of Hash: Tính SHA-256 (prev_hash || payload)
    Hash-->>AL: Gán prev_hash và hash vào dòng mới
    deactivate Hash
    
    AL-->>Trg: INSERT thành công
    deactivate AL
    
    Trg-->>BT: Trả về kết quả Trigger
    deactivate Trg
    
    BT-->>App: Giao dịch thành công (Commit)
    deactivate BT
```

---

## 2. Sơ đồ luồng bảo vệ chống can thiệp (Immutability & dblink Alert)
**Vị trí đề xuất**: Phần `4.2. Immutability (Append-only/WORM) cho bảng audit`.
**Ý nghĩa**: Trực quan hóa cơ chế bảo vệ WORM. Thể hiện rõ việc dùng `dblink` tạo ra một giao dịch tự trị (autonomous transaction) để ghi nhận lại cảnh báo an ninh ngay cả khi transaction chính bị Rollback.

```mermaid
sequenceDiagram
    autonumber
    participant Attacker as Kẻ tấn công (kể cả db_admin)
    participant AL as Bảng audit_logs
    participant Sec as func_prevent_audit_change()
    participant Dblink as dblink<br/>(Autonomous Transaction)
    participant SA as Bảng security_alerts
    
    Attacker->>AL: Cố tình UPDATE / DELETE dòng log
    activate AL
    
    AL->>Sec: Kích hoạt BEFORE ROW Trigger
    activate Sec
    
    Note right of Sec: Thu thập thông tin thao tác bị chặn<br/>(user, bảng, OLD/NEW values)
    
    Sec->>Dblink: Gọi dblink_exec() mở kết nối mới
    activate Dblink
    
    Dblink->>SA: INSERT (AUDIT_TAMPER_ATTEMPT)
    activate SA
    SA-->>Dblink: Giao dịch độc lập thành công (Commit)
    deactivate SA
    
    Dblink-->>Sec: Trả về kết quả
    deactivate Dblink
    
    Sec-->>AL: RAISE EXCEPTION
    deactivate Sec
    
    AL-->>Attacker: ERROR: Audit log is immutable<br/>(Giao dịch chính bị Rollback)
    deactivate AL
```

---

## 3. Sơ đồ thực thể liên kết (ER Diagram)
**Vị trí đề xuất**: Phần `2.2. Thiết kế mô hình dữ liệu audit (Schema Design)`.
**Ý nghĩa**: Trình bày cấu trúc dữ liệu của các thành phần tham gia trong hệ thống, nhấn mạnh mối liên hệ từ bảng nghiệp vụ đến bảng lịch sử (Audit Logs), bảng cảnh báo bảo mật (Security Alerts) và bảng audit DDL (Audit DDL Logs).

```mermaid
erDiagram
    BUSINESS_TABLES {
        BIGINT id PK "Ví dụ: orders, products"
        TEXT data "Cột dữ liệu"
    }
    
    AUDIT_LOGS {
        BIGSERIAL id PK "Composite PK (id, changed_at)"
        TIMESTAMP changed_at PK "Composite PK — Partition Key RANGE"
        TEXT table_name
        TEXT operation "INSERT / UPDATE / DELETE"
        TEXT user_name "Actor (session_user)"
        JSONB old_data "Dữ liệu trước thay đổi"
        JSONB new_data "Dữ liệu sau thay đổi"
        BYTEA prev_hash "Chuỗi liên kết trước"
        BYTEA hash "SHA-256 tamper-evident"
    }
    
    SECURITY_ALERTS {
        BIGSERIAL id PK
        TIMESTAMP alert_at
        TEXT action "Loại cảnh báo"
        TEXT table_name
        TEXT user_name
        JSONB details "Chi tiết về vi phạm"
    }

    AUDIT_DDL_LOGS {
        BIGSERIAL id PK
        TEXT command_tag "CREATE TABLE / ALTER TABLE / DROP"
        TEXT object_type "TABLE / INDEX / FUNCTION"
        TEXT object_name "Tên đối tượng schema"
        TEXT command_sql "Tóm tắt lệnh DDL"
        TIMESTAMP executed_at
        TEXT user_name "Actor (session_user)"
    }
    
    BUSINESS_TABLES ||--o{ AUDIT_LOGS : "Ghi nhật ký DML qua AFTER Trigger"
    AUDIT_LOGS ||--o{ SECURITY_ALERTS : "Phát hiện can thiệp tạo Alert"
    BUSINESS_TABLES ||--o{ AUDIT_DDL_LOGS : "Thay đổi schema qua Event Trigger"
```

---

## 4. Sơ đồ trạng thái vòng đời phân vùng (Partition Lifecycle)
**Vị trí đề xuất**: Phần `3.4. Quản lý vòng đời dữ liệu (Data Lifecycle)`.
**Ý nghĩa**: Diễn tả vòng đời của một phân vùng (partition) từ lúc là vùng dữ liệu đang ghi (Hot) đến lúc đóng băng (Cold), lưu trữ lâu dài (Archive) và cuối cùng là giải phóng dung lượng (Drop).

```mermaid
stateDiagram-v2
    direction LR
    
    [*] --> HotPartition : Tạo phân vùng tháng hiện tại
    
    state HotPartition {
        [*] --> Ghi_Log_Moi
        Ghi_Log_Moi --> [*]
    }
    note right of HotPartition
        Partition tháng hiện tại.
        Thường xuyên có lệnh INSERT.
        Nằm trên ổ SSD/NVMe (tối ưu I/O).
    end note
    
    HotPartition --> ColdPartition : Sang tháng tiếp theo
    
    state ColdPartition {
        [*] --> Chi_Doc
        Chi_Doc --> [*]
    }
    note right of ColdPartition
        Các partition lịch sử (VD: giữ 6 tháng).
        Chỉ hỗ trợ SELECT cho kiểm toán.
        Có thể chuyển sang ổ HDD lưu trữ.
    end note
    
    ColdPartition --> Archived : Hết hạn retention (VD: > 6 tháng)
    
    state Archived {
        [*] --> DumpToFile
        DumpToFile --> [*]
    }
    note right of Archived
        Dùng pg_dump sao lưu ra file.
        Lưu kho lâu dài (S3, Cold Storage).
    end note
    
    Archived --> Dropped : Đã sao lưu an toàn
    
    state Dropped {
        [*] --> DropTable
        DropTable --> [*]
    }
    note right of Dropped
        Lệnh DROP TABLE partition.
        Giải phóng I/O và dung lượng ngay lập tức (O(1)).
    end note
    
    Dropped --> [*]
```

---

## 5. Biểu đồ Scaling Curve — TPS và Overhead theo Concurrency
**Vị trí đề xuất**: Phần `5.5.1. Kịch bản 1 — Hiệu năng xử lý`.  
**Ý nghĩa**: Trực quan hóa scaling curve cho thấy TPS ổn định (~33–36) qua 3 mức concurrency — bottleneck là phần cứng, không phải trigger. Overhead nằm trong khoảng [−5.8%, +5.0%] nhất quán.

### 5a. Scaling Curve: TPS Baseline vs Proposed

```mermaid
xychart-beta
    title "Scaling Curve: TPS Baseline vs Proposed (3 concurrency levels)"
    x-axis ["10 clients", "50 clients", "80 clients"]
    y-axis "TPS (Transactions/s)" 25 --> 42
    line [33.71, 34.06, 33.90]
    line [32.02, 36.03, 35.40]
```

> _Line 1 = Baseline (trigger OFF), Line 2 = Proposed (trigger ON). TPS phẳng ~33–36 — hệ thống bão hòa từ 10 clients trên 4 vCPU WSL2._

### 5b. Overhead % tại từng mức concurrency

```mermaid
xychart-beta
    title "Overhead trigger theo concurrency — trong nguong < 15%"
    x-axis ["10c (+5.0%)", "50c (-5.8%)", "80c (-4.4%)"]
    y-axis "Overhead (%)" -10 --> 10
    bar [5.0, -5.8, -4.4]
```

> _Overhead dương (+5.0%) tại 10 clients là ước tính thực tế nhất (ít nhiễu I/O nhất). Overhead âm tại 50c/80c do I/O variance WSL2 > trigger cost._

### 5c. Latency scaling — minh họa Little's Law (L = λW)

```mermaid
xychart-beta
    title "Latency scaling (ms) — Baseline vs Proposed — L = Clients / TPS"
    x-axis ["10 clients", "50 clients", "80 clients"]
    y-axis "Avg Latency (ms)" 0 --> 2600
    line [297.1, 1468.4, 2361.9]
    line [313.0, 1387.9, 2260.5]
```

> _Latency tăng tuyến tính (~10×/~8×) khi concurrency tăng từ 10→80, trong khi TPS không đổi — đúng theo Little's Law: W = L/λ = Clients/TPS._

---

## 6. Sơ đồ kiến trúc bảo mật ba lớp (Security Layered Architecture)
**Vị trí đề xuất**: Phần `4.1. Phân quyền và mô hình SECURITY DEFINER` hoặc đầu `Chương 4`.  
**Ý nghĩa**: Trực quan hóa ba lớp bảo vệ độc lập: phân quyền (app_user không đọc được log), WORM (ngay cả admin không xóa được), và hash chain (phát hiện can thiệp ở tầng file).

```mermaid
flowchart TB
    subgraph L1["Lớp 1 — Phân quyền (GRANT / REVOKE)"]
        AppUser([app_user])
        Auditor([auditor - chỉ đọc])
        DBA([db_admin])
    end

    AuditLogs[("audit_logs<br/>partitioned · append-only")]

    subgraph L2["Lớp 2 — Immutability / WORM (BEFORE trigger + dblink)"]
        WORMTrigger["func_prevent_audit_change()<br/>RAISE EXCEPTION khi UPDATE/DELETE"]
        SecurityAlerts[("security_alerts<br/>autonomous commit via dblink")]
    end

    subgraph L3["Lớp 3 — Tamper-evident (SHA-256 hash chain)"]
        HashChain["hash = SHA256(prev_hash || payload)"]
        Verifier["func_verify_hash_chain()<br/>phát hiện chuỗi bị phá vỡ"]
    end

    Alert[/"Phát hiện can thiệp"/]

    AppUser -->|"DML nghiệp vụ → trigger ghi log"| AuditLogs
    Auditor -->|"SELECT read-only"| AuditLogs
    DBA -.->|"cố UPDATE/DELETE — BỊ CHẶN"| WORMTrigger
    WORMTrigger -->|"autonomous INSERT"| SecurityAlerts
    WORMTrigger -->|"RAISE EXCEPTION → Rollback"| DBA

    AuditLogs --> HashChain
    HashChain --> Verifier
    Verifier -->|"chain_ok = FALSE"| Alert
```
