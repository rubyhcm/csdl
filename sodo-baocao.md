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
**Ý nghĩa**: Trình bày cấu trúc dữ liệu của các thành phần tham gia trong hệ thống, nhấn mạnh mối liên hệ từ bảng nghiệp vụ đến bảng lịch sử (Audit Logs) và bảng cảnh báo bảo mật (Security Alerts).

```mermaid
erDiagram
    BUSINESS_TABLES {
        BIGINT id PK "Ví dụ: orders, products"
        TEXT data "Cột dữ liệu"
    }
    
    AUDIT_LOGS {
        BIGSERIAL id PK
        TIMESTAMP changed_at PK "Partition Key"
        TEXT table_name
        TEXT operation "INSERT / UPDATE / DELETE"
        TEXT user_name "Actor (session_user)"
        JSONB old_data "Dữ liệu trước thay đổi"
        JSONB new_data "Dữ liệu sau thay đổi"
        BYTEA prev_hash "Chuỗi liên kết trước"
        BYTEA hash "Chuỗi băm hiện tại"
    }
    
    SECURITY_ALERTS {
        BIGSERIAL id PK
        TIMESTAMP alert_at
        TEXT action "Loại cảnh báo"
        TEXT table_name
        TEXT user_name
        JSONB details "Chi tiết về vi phạm"
    }
    
    BUSINESS_TABLES ||--o{ AUDIT_LOGS : "Ghi nhật ký qua Trigger"
    AUDIT_LOGS ||--o{ SECURITY_ALERTS : "Phát hiện can thiệp tạo Alert"
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
